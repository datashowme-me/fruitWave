import AVFoundation
import AVKit
import FruitWaveCore
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    private(set) var coordinator = GameCoordinator()
    private(set) var score = 0
    private(set) var highScore = UserDefaults.standard.integer(forKey: "fruitWave.highScore")
    private(set) var secondsRemaining = 90
    private(set) var statusMessage = "连接 iPhone 后开始"
    private(set) var isDemoMode = false
    var selectedHand: HandSide = .right
    var soundEnabled = true { didSet { renderer.soundEnabled = soundEnabled } }
    var reduceMotion = false { didSet { renderer.reduceMotion = reduceMotion } }
    var showDevicePicker = false
    var calibrationStep = 0
    private(set) var calibrationProgress = 0.0
    private(set) var calibrationCursor: Vector2?
    private(set) var calibrationCursorIsInside = true
    private(set) var captureGeometry: CaptureGeometry?
    private(set) var framingWristPreviewPoint: Vector2?

    let camera = CameraSessionManager()
    let renderer = GameRenderer(size: CGSize(width: 1920, height: 1080))

    private let poseEngine = PoseTrackingEngine()
    private var playerTracker = PlayerTracker()
    private var mapper = CalibrationMapper()
    private var sampler = CalibrationSampler()
    private var calibrationWristFilter = OneEuroFilter2D(
        configuration: .init(minCutoff: 1.0, beta: 0.25, derivativeCutoff: 1)
    )
    private var motion = MotionProcessor()
    private var gameplay = GameplayEngine()
    private var currentCandidate: PoseCandidate?
    private var currentCandidateTime: TimeInterval?
    private var currentHandPosition: Vector2?
    /// Capture time of the pose frame behind `currentHandPosition` (monotonic
    /// clock) — rides along to the HUD so the cursor can compensate pipeline age.
    private var currentHandSampleTime: TimeInterval?
    /// True between a bomb hit and the results transition (~0.9 s) so the
    /// blast can play before the round ends.
    private var bombExploding = false
    private var lowerLeft: Vector2?
    private var lastValidHandTime: TimeInterval?
    private var trackedHandStableSince: TimeInterval?
    private var identityUncertainSince: TimeInterval?
    private var lastPoseSampleTime: TimeInterval?
    private var frameLiveness = FrameLivenessWatchdog()
    private var reviewDwellStartedAt: TimeInterval?
    private var lastCalibrationRawPoint: (point: Vector2, time: TimeInterval)?
    private var cameraWatchdogTask: Task<Void, Never>?
    private var cameraReconnectTask: Task<Void, Never>?
    private var devicePickerTimeoutTask: Task<Void, Never>?
    /// Consecutive failed reconnects, for exponential backoff. Reset once the
    /// camera streams again.
    private var reconnectAttempts = 0
    private var connectionTask: Task<Void, Never>?
    private var wantsCameraConnection = false
    /// The system can publish the newly paired Continuity Camera before the
    /// SwiftUI picker delivers `onDidConnect`. Keep it as a recovery path
    /// instead of discarding the event while the picker is presented.
    private var pendingPreferredCamera: AVCaptureDevice?
    private var runEpochGate = RunEpochGate()
    private var frameSequenceGate = FrameSequenceGate()
    private var currentRoundID = UUID()
    private var activePlayerID = UUID()
    private var gameClockHistory = GameClockHistory()
    private var lastFrameArrivalForMetrics: TimeInterval?
    private var frameIntervals: [TimeInterval] = []
    private var queueDurations: [TimeInterval] = []
    private var inferenceDurations: [TimeInterval] = []
    private var resultAges: [TimeInterval] = []
    private var framesSinceDiagnosticsWrite = 0
    private var pendingCalibrationPoint: Vector2?
    private var pendingCalibrationPointLockedAt: TimeInterval?
    private let calibrationMinimumWristConfidence = 0.30
    private let reviewTargets = [
        Vector2(x: 0.5, y: 0.28),
        .init(x: 0.15, y: 0.12), .init(x: 0.85, y: 0.12),
        .init(x: 0.15, y: 0.44), .init(x: 0.85, y: 0.44)
    ]
    private var geometryMismatchCount = 0
    private var statusMessageLocked = false
    /// The player asked to start a new round while the camera was down; start
    /// it as soon as streaming resumes instead of leaving them stranded.
    private var pendingRestart = false
    private var lastDemoSlashTime: TimeInterval?
    private let demoSessionID = UUID()
    private var didHandleLaunchArguments = false
    private var demoVerificationHitCount = 0
    private var didReportDemoVerification = false
    private var isAutomatedDemoVerification: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-verify")
    }
    private static let logger = Logger(subsystem: "com.example.FruitWave", category: "AppModel")

    var state: GameState { coordinator.state }
    var pauseReason: PauseReason? { coordinator.pauseReason }
    var isHandVisible: Bool { currentHandPosition != nil }
    var calibrationStepCount: Int { 2 + reviewTargets.count }
    var diagnosticsSummary: String {
        let dimensions = captureGeometry.map { "\($0.pixelWidth)×\($0.pixelHeight)" } ?? "等待画面"
        let frameP95 = percentile(frameIntervals, 0.95).map { String(format: "%.1fms", $0 * 1_000) } ?? "—"
        let queueP95 = percentile(queueDurations, 0.95).map { String(format: "%.1fms", $0 * 1_000) } ?? "—"
        let inferenceP50 = percentile(inferenceDurations, 0.50).map { String(format: "%.1fms", $0 * 1_000) } ?? "—"
        let inferenceP95 = percentile(inferenceDurations, 0.95).map { String(format: "%.1fms", $0 * 1_000) } ?? "—"
        let drops = camera.frameDropCounts.values.reduce(0, +)
        return "视频 \(dimensions) · 帧间隔 P95 \(frameP95) · 排队 P95 \(queueP95) · Vision P50/P95 \(inferenceP50)/\(inferenceP95) · 丢帧 \(drops)"
    }
    var canBeginCalibration: Bool {
        guard state == .framing,
              let candidate = currentCandidate,
              let currentCandidateTime,
              ProcessInfo.processInfo.systemUptime - currentCandidateTime <= 1.0 else { return false }
        return calibratableWrist(in: candidate) != nil
    }
    var reviewTarget: Vector2? {
        let index = calibrationStep - 2
        return reviewTargets.indices.contains(index) ? reviewTargets[index] : nil
    }

    init() {
        camera.onFrame = { [weak self, weak poseEngine] packet in
            Task { @MainActor in self?.recordFrameArrival(packet) }
            poseEngine?.submit(packet)
        }
        camera.onStateChange = { [weak self] state in self?.handleCameraState(state) }
        camera.onPreferredCameraChange = { [weak self] device in
            self?.handlePreferredCameraChange(device)
        }
        camera.onCenterStageChange = { [weak self] isActive in
            self?.handleCenterStageChange(isActive)
        }
        poseEngine.onSample = { [weak self] sample in
            Task { @MainActor in self?.consume(sample) }
        }
        poseEngine.onFailure = { [weak self] message in
            Task { @MainActor in self?.handlePoseFailure(message) }
        }
        renderer.onTick = { [weak self] now in self?.tick(now: now) }
        renderer.pointsPerSlice = gameplay.configuration.pointsPerFruit
    }

    func requestConnection() {
        guard state == .waitingForConnection else { return }
        wantsCameraConnection = true
        connectionTask?.cancel()
        logCameraFlow("requestConnection")
        connectionTask = Task { [weak self] in
            guard let self else { return }
            self.statusMessage = "正在检查相机权限…"
            let granted = await self.camera.requestVideoAccess()
            self.logCameraFlow("videoAccess=\(granted)")
            guard granted else {
                self.wantsCameraConnection = false
                return
            }
            guard !Task.isCancelled, self.wantsCameraConnection else { return }
            self.beginDeviceConnection()
        }
    }

    func handleInitialLaunchArguments() {
        guard !didHandleLaunchArguments else { return }
        didHandleLaunchArguments = true
        if isAutomatedDemoVerification {
            startAnimationDemo()
        }
    }

    func startAnimationDemo() {
        guard state == .waitingForConnection else { return }
        wantsCameraConnection = false
        connectionTask?.cancel()
        devicePickerTimeoutTask?.cancel()
        showDevicePicker = false
        camera.cancelSelection()
        isDemoMode = true
        lastDemoSlashTime = nil
        demoVerificationHitCount = 0
        didReportDemoVerification = false
        statusMessageLocked = false
        _ = coordinator.transition(to: .framing)
        _ = coordinator.transition(to: .calibration)
        _ = coordinator.transition(to: .ready)
        statusMessage = "动画演示：自动挥砍"
        if isAutomatedDemoVerification { print("DEMO_VERIFY started") }
        startGame()
    }

    func handleAppBecameInactive() {
        logCameraFlow("app became inactive")
        guard wantsCameraConnection else { return }
        if state == .playing || state == .resuming || state == .ready {
            pause(reason: .cameraInterrupted, source: "app-inactive")
        } else {
            invalidateVisionRun()
            motion.reset()
            renderer.clearTrail()
        }
        camera.suspend()
    }

    func handleAppBecameActive() {
        logCameraFlow("app became active")
        guard wantsCameraConnection, camera.activeDeviceUniqueID != nil else { return }
        frameLiveness.reset()
        invalidateVisionRun()
        camera.resume()
        startCameraWatchdog(for: camera.sessionID)
        statusMessage = "正在恢复 iPhone 画面…"
    }

    private func beginDeviceConnection() {
        // The system picker owns pairing once it is up; re-presenting it
        // mid-scan resets the QR session and makes pairing fail repeatedly.
        guard !showDevicePicker else {
            logCameraFlow("beginDeviceConnection skipped (picker already up)")
            return
        }
        if let preferredCamera = camera.preferredContinuityCamera() {
            logCameraFlow("beginDeviceConnection -> preferred camera exists")
            configureCamera(preferredCamera)
            statusMessage = "正在连接已配对的 iPhone…"
            return
        }

        logCameraFlow("beginDeviceConnection -> show picker")
        pendingPreferredCamera = nil
        camera.beginSelection()
        showDevicePicker = true
        statusMessage = "请在 iPhone 上扫码、点按“连接到 Apple TV”并确认"
        devicePickerTimeoutTask?.cancel()
        devicePickerTimeoutTask = Task { [weak self] in
            // First-time pairing over a slow Wi‑Fi link can exceed 45 s;
            // give the scan a full 90 s before giving up.
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self, self.showDevicePicker else { return }
            self.logCameraFlow("picker timeout fired -> cancel selection")
            self.showDevicePicker = false
            self.camera.cancelSelection()
            self.wantsCameraConnection = false
            self.statusMessage = "二维码连接超时，请确认 iPhone 已解锁、蓝牙和 Wi‑Fi 已开启后重试"
        }
    }

    func connect(_ device: AVContinuityDevice?) {
        devicePickerTimeoutTask?.cancel()
        showDevicePicker = false
        logCameraFlow(device == nil ? "connect(nil) -> user cancelled" : "connect(device) -> configure")
        guard let cameraDevice = device?.videoDevices.first ?? pendingPreferredCamera else {
            wantsCameraConnection = false
            camera.cancelSelection()
            statusMessage = "未选择设备，可重新连接"
            return
        }
        pendingPreferredCamera = nil
        configureCamera(cameraDevice)
    }

    private func configureCamera(_ cameraDevice: AVCaptureDevice) {
        logCameraFlow("configureCamera (appState=\(String(describing: state)), cameraState=\(String(describing: camera.state)))")
        showDevicePicker = false
        devicePickerTimeoutTask?.cancel()
        let replacesActiveCamera = state != .waitingForConnection &&
            camera.activeDeviceUniqueID != cameraDevice.uniqueID
        if replacesActiveCamera {
            requireRecalibration(message: "相机已变化，请重新确认站位并校准")
        }
        captureGeometry = nil
        invalidateVisionRun()
        camera.configure(with: cameraDevice)
        startCameraWatchdog(for: camera.sessionID)
        statusMessage = "正在等待视频画面…"
    }

    func selectHand(_ side: HandSide) {
        selectedHand = side
        updateFramingStatus()
    }

    func startWithAutomaticRange() {
        guard state == .framing else { return }
        playerTracker.reset()
        if let currentCandidate {
            _ = playerTracker.lock(candidates: [currentCandidate])
        }
        guard mapper.calibrate(
            lowerLeft: .init(x: 0.12, y: 0.12),
            upperRight: .init(x: 0.88, y: 0.88)
        ) else { return }
        calibrationStep = 0
        calibrationProgress = 0
        pendingCalibrationPoint = nil
        pendingCalibrationPointLockedAt = nil
        _ = coordinator.transition(to: .calibration)
        _ = coordinator.transition(to: .ready)
        statusMessage = "正在开始游戏…"
        startGame()
    }

    func cancelCalibration() {
        guard state == .calibration else { return }
        statusMessageLocked = false
        sampler.reset()
        calibrationWristFilter.reset()
        playerTracker.reset()
        mapper.invalidate()
        calibrationStep = 0
        calibrationProgress = 0
        calibrationCursor = nil
        calibrationCursorIsInside = true
        reviewDwellStartedAt = nil
        pendingCalibrationPoint = nil
        pendingCalibrationPointLockedAt = nil
        lowerLeft = nil
        lastCalibrationRawPoint = nil
        currentHandPosition = nil; currentHandSampleTime = nil
        identityUncertainSince = nil
        lastValidHandTime = nil
        _ = coordinator.transition(to: .framing)
        updateFramingStatus()
    }

    /// Staleness grace after entering .playing — mounting the 3D scene view
    /// stalls the main thread long enough to trip the 0.5 s frame watchdog.
    private var playingGraceUntil: TimeInterval = 0

    func startGame() {
        guard state == .ready else { return }
        guard isDemoMode || camera.state == .streaming else {
            statusMessage = "iPhone 画面尚未就绪"
            return
        }
        statusMessageLocked = false
        Self.logger.notice("Starting game")
        let now = ProcessInfo.processInfo.systemUptime
        currentRoundID = UUID()
        activePlayerID = UUID()
        gameplay.start(at: now, roundID: currentRoundID)
        gameClockHistory.reset(monotonicTime: now)
        score = 0
        secondsRemaining = Int(gameplay.configuration.duration)
        motion.reset()
        renderer.clearTrail()
        bombExploding = false
        lastDemoSlashTime = nil
        playingGraceUntil = now + 3
        logDiagnostic("startGame")
        guard coordinator.transition(to: .playing) else { return }
        // Produce and render the first fruit in the same interaction that
        // starts the round instead of waiting for a countdown or later tick.
        tick(now: now)
    }

    func pause(reason: PauseReason = .user, source: String = "user") {
        guard state == .playing || state == .resuming || state == .ready else { return }
        Self.logger.warning("Pausing game, reason: \(String(describing: reason), privacy: .public)")
        logDiagnostic("pause reason=\(reason) source=\(source) gameTime=\(gameplay.gameTime)")
        _ = coordinator.transition(to: .paused, reason: reason)
        invalidateVisionRun(); gameplay.pause(); motion.reset(); renderer.clearTrail()
        statusMessage = pauseText(reason)
    }

    /// Appends a line to a file in the app container so on-device acceptance
    /// issues can be triaged by pulling the container with devicectl. No-op
    /// in release builds. Lives in Caches: on tvOS the Documents directory is
    /// not reliably writable (silent failures observed on device).
    private func logDiagnostic(_ line: String, to fileName: String = "fruitwave-pause-log.txt") {
        let text = String(format: "%.3f %@\n", ProcessInfo.processInfo.systemUptime, line)
        guard let url = try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(fileName) else { return }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 128 * 1_024 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Pairing-flow log (DEBUG only): every camera state transition and
    /// connection decision lands in Caches/fruitwave-camera-log.txt so a
    /// failed on-device pairing can be triaged by pulling the container.
    /// Never writes device identifiers or names.
    private func logCameraFlow(_ line: String) {
        logDiagnostic(line, to: "fruitwave-camera-log.txt")
    }

    func setDevicePickerPresented(_ isPresented: Bool) {
        guard showDevicePicker != isPresented else { return }
        showDevicePicker = isPresented
        logCameraFlow("picker presentation -> \(isPresented)")
        guard !isPresented else { return }
        Task { [weak self] in
            // Let the picker's onDidConnect callback run first. If it doesn't,
            // activate the camera published through systemPreferredCamera.
            await Task.yield()
            self?.activatePendingPreferredCameraIfNeeded()
        }
    }

    private func activatePendingPreferredCameraIfNeeded() {
        guard wantsCameraConnection,
              camera.activeDeviceUniqueID == nil,
              let device = pendingPreferredCamera else { return }
        pendingPreferredCamera = nil
        logCameraFlow("activating camera published during picker")
        configureCamera(device)
        statusMessage = "已发现 iPhone，正在连接相机…"
    }

    func resume() {
        guard isDemoMode || (camera.state == .streaming && hasFreshTrackedHand) else {
            statusMessage = "请让所选手腕回到画面中"
            return
        }
        guard coordinator.transition(to: .resuming) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        gameplay.resume(at: now)
        motion.reset()
        renderer.clearTrail()
        playingGraceUntil = now + 3
        logDiagnostic("resume")
        _ = coordinator.transition(to: .playing)
    }

    func recalibrate() {
        statusMessageLocked = false
        invalidateVisionRun(); motion.reset(); mapper.invalidate(); playerTracker.reset()
        identityUncertainSince = nil
        lastValidHandTime = nil
        if state == .paused || state == .ready { _ = coordinator.transition(to: .calibration) }
        if state == .calibration { _ = coordinator.transition(to: .framing) }
        statusMessage = "请重新确认玩家和左右手，然后开始游戏"
    }

    func restart() {
        guard state == .paused || state == .results || state == .ready else { return }
        guard isDemoMode || camera.state == .streaming else {
            pendingRestart = true
            statusMessageLocked = true
            Self.logger.notice("Restart requested while camera is down; will start on recovery")
            statusMessage = "正在等待 iPhone 画面恢复，恢复后自动开始新一局…"
            scheduleCameraReconnect()
            return
        }
        invalidateVisionRun()
        motion.reset()
        renderer.clearTrail()
        if state != .ready {
            guard coordinator.transition(to: .ready) else {
                statusMessage = "无法重开：游戏状态异常"
                return
            }
        }
        startGame()
    }

    func changePlayer() {
        guard state == .results else { return }
        statusMessageLocked = false
        invalidateVisionRun(); playerTracker.reset(); mapper.invalidate(); motion.reset(); renderer.clearTrail()
        currentCandidate = nil; currentCandidateTime = nil; currentHandPosition = nil; currentHandSampleTime = nil
        framingWristPreviewPoint = nil; trackedHandStableSince = nil; lastValidHandTime = nil
        calibrationStep = 0; calibrationProgress = 0; pendingCalibrationPoint = nil
        pendingCalibrationPointLockedAt = nil
        _ = coordinator.transition(to: .ready)
        _ = coordinator.transition(to: .calibration)
        _ = coordinator.transition(to: .framing)
        statusMessage = "请让新玩家单独站在画面中，并选择左右手"
    }

    func exitToConnection() {
        statusMessageLocked = false
        pendingRestart = false
        isDemoMode = false
        lastDemoSlashTime = nil
        wantsCameraConnection = false
        connectionTask?.cancel(); cameraReconnectTask?.cancel(); cameraWatchdogTask?.cancel(); devicePickerTimeoutTask?.cancel(); camera.stop(); invalidateVisionRun(); playerTracker.reset(); motion.reset(); mapper.invalidate()
        currentCandidate = nil
        currentCandidateTime = nil
        currentHandPosition = nil; currentHandSampleTime = nil
        framingWristPreviewPoint = nil
        calibrationProgress = 0
        pendingCalibrationPoint = nil
        pendingCalibrationPointLockedAt = nil
        calibrationCursor = nil
        calibrationCursorIsInside = true
        reviewDwellStartedAt = nil
        identityUncertainSince = nil
        lastValidHandTime = nil
        lastPoseSampleTime = nil
        frameLiveness.reset()
        frameSequenceGate.reset()
        captureGeometry = nil
        if state == .playing { pause(reason: .user) }
        while state != .waitingForConnection {
            if !coordinator.transition(to: .waitingForConnection) { break }
        }
        coordinator = GameCoordinator()
        statusMessage = "连接 iPhone 后开始"
    }

    private func consume(_ sample: PoseSample) {
        guard sample.sessionID == camera.sessionID,
              runEpochGate.accepts(sample.runEpoch),
              frameSequenceGate.accepts(
                sessionID: sample.sessionID,
                runEpoch: sample.runEpoch,
                sequence: sample.sequence
              ) else { return }
        if let baseline = captureGeometry, baseline != sample.geometry {
            // The connection settles for a few frames right after streaming
            // starts, and one isolated mismatch must not interrupt a running
            // game. Before the game starts the new geometry is simply adopted;
            // a persistent change during play requires recalibration because
            // hand coordinates are no longer comparable.
            geometryMismatchCount += 1
            let shouldAdopt = state == .framing || state == .calibration || geometryMismatchCount >= 5
            guard shouldAdopt else { return }
            Self.logger.notice("Capture geometry changed: \(String(describing: baseline), privacy: .public) -> \(String(describing: sample.geometry), privacy: .public), state \(String(describing: self.state), privacy: .public)")
            captureGeometry = sample.geometry
            geometryMismatchCount = 0
            if state != .framing, state != .calibration {
                requireRecalibration(message: "相机方向或画面尺寸已变化，请重新校准")
                return
            }
        } else {
            captureGeometry = sample.geometry
            geometryMismatchCount = 0
        }
        lastPoseSampleTime = sample.inferenceCompletedAt
        if camera.state == .configuring {
            camera.markStreaming(sessionID: sample.sessionID)
        }
        guard camera.state == .streaming else { return }
        let sampleAge = sample.inferenceCompletedAt - sample.receivedAtMonotonic
        appendMetric(max(0, sample.inferenceStartedAt - sample.receivedAtMonotonic), to: &queueDurations)
        appendMetric(max(0, sample.inferenceCompletedAt - sample.inferenceStartedAt), to: &inferenceDurations)
        appendMetric(sampleAge, to: &resultAges)
        // Gameplay needs very fresh points for fair collision timing, while
        // framing and calibration only need a stable position and can accept
        // slower Vision inference on Apple TV hardware.
        let maximumSampleAge = state == .playing ? motion.configuration.maximumResultAge : 1.0
        guard sampleAge >= 0, sampleAge <= maximumSampleAge else {
            invalidateHand(reason: .stale, now: sample.inferenceCompletedAt)
            resetCalibrationFeedbackIfNeeded(now: sample.inferenceCompletedAt)
            if state == .framing || state == .calibration, !statusMessageLocked {
                statusMessage = "姿态识别延迟过高，请改善光线并减少画面中的人物"
            }
            return
        }
        if state == .paused, pauseReason == .cameraInterrupted {
            statusMessage = "画面已恢复，可以继续"
        }
        if state == .framing {
            if let detected = bestFramingCandidate(from: sample.candidates) {
                currentCandidate = detected
                currentCandidateTime = sample.inferenceCompletedAt
                if let wrist = calibratableWrist(in: detected) {
                    framingWristPreviewPoint = .init(x: wrist.position.x, y: 1 - wrist.position.y)
                } else {
                    framingWristPreviewPoint = nil
                }
            } else if let currentCandidateTime,
                      sample.inferenceCompletedAt - currentCandidateTime > 1.0 {
                currentCandidate = nil
                self.currentCandidateTime = nil
                framingWristPreviewPoint = nil
            }
            updateFramingStatus()
            return
        }
        let trackedCandidate: PoseCandidate?
        if playerTracker.playerSessionID == nil {
            trackedCandidate = playerTracker.lock(candidates: sample.candidates)
        } else {
            trackedCandidate = playerTracker.track(candidates: sample.candidates)
        }
        // Identity matching improves multi-person stability, but it must not
        // be a gate that freezes a single-player family game. When shoulder
        // matching is briefly lost, continue with the clearest selected wrist
        // and keep the same round-scoped player identifier.
        guard let candidate = trackedCandidate ?? bestPlayableCandidate(from: sample.candidates) else {
            let now = sample.inferenceCompletedAt
            if identityUncertainSince == nil { identityUncertainSince = now }
            invalidateHand(reason: .identityUncertain, now: now, pauseWhenExpired: false)
            resetCalibrationFeedbackIfNeeded(now: now)
            if state == .calibration, !statusMessageLocked {
                statusMessage = "正在寻找一名玩家；请让上半身和所选手腕保持在画面内"
            }
            return
        }
        identityUncertainSince = nil
        let joint = selectedHand == .left ? candidate.leftWrist : candidate.rightWrist
        guard let joint else {
            invalidateHand(reason: .lowConfidence, now: sample.inferenceCompletedAt, pauseWhenExpired: false)
            resetCalibrationFeedbackIfNeeded(now: sample.inferenceCompletedAt)
            return
        }
        let minimumConfidence = state == .calibration
            ? calibrationMinimumWristConfidence
            : motion.configuration.minimumConfidence
        guard joint.confidence >= minimumConfidence else {
            invalidateHand(reason: .lowConfidence, now: sample.inferenceCompletedAt, pauseWhenExpired: false)
            resetCalibrationFeedbackIfNeeded(now: sample.inferenceCompletedAt)
            return
        }
        lastValidHandTime = sample.inferenceCompletedAt
        if trackedHandStableSince == nil { trackedHandStableSince = sample.inferenceCompletedAt }
        if state == .calibration {
            guard let stabilizedPoint = stabilizedCalibrationPoint(
                joint.position,
                at: sample.inferenceCompletedAt
            ) else {
                sampler.append(.init(
                    time: sample.inferenceCompletedAt,
                    point: .zero,
                    isValid: false
                ))
                return
            }
            sampler.append(.init(
                time: sample.inferenceCompletedAt,
                point: stabilizedPoint,
                isValid: true
            ))
            let mapped = mapper.map(stabilizedPoint)
            currentHandPosition = mapped?.position
            currentHandSampleTime = sample.capturedAtMonotonic
            updateCalibration(rawPoint: stabilizedPoint, mapped: mapped, now: sample.inferenceCompletedAt)
            return
        }
        let mapped = mapper.map(joint.position)
        currentHandPosition = mapped?.position
        guard let mapped, mapped.isInside else { currentHandPosition = nil; currentHandSampleTime = nil; motion.reset(); return }
        let hand = TrackedHand(playerSessionID: activePlayerID, handSide: selectedHand, mappingVersion: mapper.mappingVersion, sampleTime: sample.capturedAtMonotonic, receivedAt: sample.receivedAtMonotonic, mappedPosition: mapped.position, confidence: joint.confidence)
        guard state == .playing else { render(hand: mapped.position, slash: nil, hits: []); return }
        let slash = motion.process(hand, sessionID: sample.sessionID, roundID: currentRoundID, now: sample.inferenceCompletedAt)
        var hits: [HitEvent] = []
        if let slash {
            if let gameTimeRange = gameTimeRange(for: slash) {
                hits = gameplay.apply(slash, gameTimeRange: gameTimeRange)
            }
            score = gameplay.score
            // Bomb hit: freeze the engine, let the blast play, then end the
            // round. Double detonations are ignored.
            if gameplay.hitBomb, !bombExploding {
                bombExploding = true
                gameplay.pause()
                render(hand: mapped.position, slash: slash, hits: hits)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    guard let self else { return }
                    self.finishRound()
                }
                return
            }
        }
        render(hand: mapped.position, slash: slash, hits: hits)
    }

    private func invalidateHand(reason: InvalidHandReason, now: TimeInterval, pauseWhenExpired: Bool = true) {
        sampler.append(.init(time: now, point: .zero, isValid: false))
        currentHandPosition = nil; currentHandSampleTime = nil; trackedHandStableSince = nil; motion.reset(); renderer.clearTrail()
        if pauseWhenExpired, let lastValidHandTime, now - lastValidHandTime >= 0.5, state == .playing {
            pause(reason: .handUnavailable, source: "hand-unavailable")
        }
    }

    private func updateCalibration(
        rawPoint: Vector2,
        mapped: (position: Vector2, isInside: Bool)?,
        now: TimeInterval
    ) {
        if calibrationStep < 2 {
            calibrationCursorIsInside = true
            calibrationCursor = Vector2(
                x: min(max(rawPoint.x, 0), 1),
                y: min(max(1 - rawPoint.y, 0), 1)
            )
            let measuredProgress = sampler.stabilityProgress(at: now)
            if let stablePoint = sampler.stableMedian(at: now), pendingCalibrationPoint == nil {
                pendingCalibrationPoint = stablePoint
                pendingCalibrationPointLockedAt = now
                calibrationProgress = 1
            } else if pendingCalibrationPoint == nil {
                // Camera cadence and an occasional weak Vision frame should
                // make progress ease back, not jump abruptly between values.
                calibrationProgress = measuredProgress >= calibrationProgress
                    ? measuredProgress
                    : max(measuredProgress, calibrationProgress - 0.02)
            }
            if let pendingCalibrationPoint,
               let pendingCalibrationPointLockedAt,
               now - pendingCalibrationPointLockedAt >= 0.35 {
                captureCalibrationCorner(pendingCalibrationPoint)
                return
            }
            statusMessage = pendingCalibrationPoint == nil
                ? (calibrationStep == 0 ? "把手移到左下角并保持稳定" : "把手移到右上角并保持稳定")
                : "位置已锁定，正在自动采集…"
            return
        }

        guard let target = reviewTarget, let mapped else {
            currentHandPosition = nil; currentHandSampleTime = nil
            calibrationCursor = nil
            calibrationCursorIsInside = false
            calibrationProgress = 0
            reviewDwellStartedAt = nil
            statusMessage = "暂时无法定位所选手腕"
            return
        }

        calibrationCursor = Vector2(
            x: mapped.position.x,
            y: 1 - mapped.position.y / mapper.playableRect.height
        )
        calibrationCursorIsInside = mapped.isInside
        guard mapped.isInside else {
            currentHandPosition = nil; currentHandSampleTime = nil
            calibrationProgress = 0
            reviewDwellStartedAt = nil
            statusMessage = "沿橙色光标方向，把手腕移回活动范围"
            return
        }

        let isOnTarget = (target - mapped.position).length <= 0.045
        guard isOnTarget else {
            calibrationProgress = 0
            reviewDwellStartedAt = nil
            statusMessage = "将白色手部光标移入绿色目标"
            return
        }

        let startedAt = reviewDwellStartedAt ?? now
        reviewDwellStartedAt = startedAt
        calibrationProgress = min(1, (now - startedAt) / 0.5)
        statusMessage = "保持在目标内…"
        guard calibrationProgress >= 1 else { return }

        calibrationStep += 1
        calibrationProgress = 0
        reviewDwellStartedAt = nil
        if calibrationStep - 2 >= reviewTargets.count {
            calibrationCursor = nil
            calibrationCursorIsInside = true
            _ = coordinator.transition(to: .ready)
            statusMessage = "校准完成"
        } else {
            statusMessage = "移动到下一个绿色目标"
        }
    }

    private func captureCalibrationCorner(_ point: Vector2) {
        pendingCalibrationPoint = nil
        pendingCalibrationPointLockedAt = nil
        if calibrationStep == 0 {
            lowerLeft = point
            calibrationStep = 1
            calibrationProgress = 0
            sampler.reset()
            statusMessage = "左下角已采集；移动到舒适活动区右上角并保持稳定"
            return
        }

        guard let lowerLeft else { return }
        guard mapper.calibrate(lowerLeft: lowerLeft, upperRight: point) else {
            calibrationProgress = 0
            sampler.reset()
            statusMessage = "范围过小或方向不正确，请把手移到更远的右上角"
            return
        }
        calibrationStep = 2
        calibrationProgress = 0
        sampler.reset()
        reviewDwellStartedAt = nil
        statusMessage = "移动白色手部光标进入绿色目标"
    }

    private func resetCalibrationFeedbackIfNeeded(now: TimeInterval) {
        guard state == .calibration else { return }
        if pendingCalibrationPoint != nil {
            calibrationProgress = 1
            statusMessage = "位置已锁定，正在自动采集…"
            return
        }
        if let lastValidHandTime, now - lastValidHandTime < 0.2 {
            return
        }
        if calibrationStep < 2 {
            let measuredProgress = sampler.stabilityProgress(at: now)
            calibrationProgress = max(measuredProgress, calibrationProgress - 0.03)
        } else {
            calibrationProgress = 0
        }
        calibrationCursor = nil
        calibrationCursorIsInside = false
        reviewDwellStartedAt = nil
        statusMessage = "未识别到所选手腕，请放下手中物品并让手掌、手腕完整可见"
    }

    private var hasFreshTrackedHand: Bool {
        guard camera.state == .streaming,
              currentHandPosition != nil,
              let lastValidHandTime else { return false }
        return ProcessInfo.processInfo.systemUptime - lastValidHandTime <= 0.5
    }

    private func selectedWrist(in candidate: PoseCandidate) -> JointPoint? {
        selectedHand == .left ? candidate.leftWrist : candidate.rightWrist
    }

    private func calibratableWrist(in candidate: PoseCandidate) -> JointPoint? {
        guard let wrist = selectedWrist(in: candidate),
              wrist.confidence >= calibrationMinimumWristConfidence else { return nil }
        return wrist
    }

    private func bestFramingCandidate(from candidates: [PoseCandidate]) -> PoseCandidate? {
        guard candidates.count == 1 else { return nil }
        return candidates.first
    }

    private func bestPlayableCandidate(from candidates: [PoseCandidate]) -> PoseCandidate? {
        candidates
            .filter { selectedWrist(in: $0) != nil }
            .max { lhs, rhs in
                let lhsWrist = selectedWrist(in: lhs)?.confidence ?? 0
                let rhsWrist = selectedWrist(in: rhs)?.confidence ?? 0
                let lhsScore = lhsWrist + min(lhs.torsoScale, 0.5) * 0.2
                let rhsScore = rhsWrist + min(rhs.torsoScale, 0.5) * 0.2
                return lhsScore < rhsScore
            }
    }

    private func framingDistance(from candidate: PoseCandidate, to reference: PoseCandidate) -> Double {
        let centerDistance = (candidate.torsoCenter - reference.torsoCenter).length
        let scaleRatio = candidate.torsoScale / max(reference.torsoScale, 0.0001)
        return centerDistance + abs(log(max(scaleRatio, 0.0001))) * 0.12
    }

    private func stabilizedCalibrationPoint(_ point: Vector2, at time: TimeInterval) -> Vector2? {
        guard point.isFinite else { return nil }
        if let previous = lastCalibrationRawPoint {
            let dt = time - previous.time
            if dt > 0, dt < 0.25, (point - previous.point).length > 0.22 {
                calibrationWristFilter.reset()
                lastCalibrationRawPoint = (point, time)
                return nil
            }
        }
        lastCalibrationRawPoint = (point, time)
        return calibrationWristFilter.filter(point, at: time)
    }

    private func updateFramingStatus() {
        guard state == .framing, let candidate = currentCandidate else {
            if state == .framing {
                statusMessage = "请确保画面中只有一名玩家，并让双肩和所选手腕清晰可见"
            }
            return
        }
        if calibratableWrist(in: candidate) == nil {
            statusMessage = "已识别玩家，但所选手腕不清晰；请放下手中物品并露出手腕"
        } else if camera.isCenterStageActive {
            statusMessage = "已识别玩家，可以直接开始；游戏期间请勿切换“人物居中”"
        } else {
            statusMessage = "已识别玩家，可以直接开始"
        }
    }

    private func handleCameraState(_ cameraState: CameraState) {
        logCameraFlow("cameraState -> \(String(describing: cameraState))")
        switch cameraState {
        case .configuring:
            statusMessage = "正在等待视频画面…"
        case .streaming:
            cameraReconnectTask?.cancel()
            reconnectAttempts = 0
            if pendingRestart {
                pendingRestart = false
                statusMessageLocked = false
                Self.logger.notice("Camera recovered; starting the requested new round")
                restart()
                return
            }
            if state == .waitingForConnection {
                _ = coordinator.transition(to: .framing)
                statusMessage = "选择左手或右手，然后直接开始"
            } else if state == .calibration {
                statusMessage = "iPhone 画面已恢复，请继续校准"
            } else if state == .ready {
                statusMessage = "iPhone 连接已恢复，可以立即开始"
            } else if state == .framing {
                updateFramingStatus()
            } else if state == .paused, pauseReason == .cameraInterrupted {
                statusMessage = "iPhone 画面已恢复，可以继续"
            }
        case .interrupted(let message), .failed(let message):
            Self.logger.warning("Camera state: \(String(describing: cameraState), privacy: .public)")
            statusMessageLocked = false
            statusMessage = message
            if state == .playing {
                pause(reason: .cameraInterrupted, source: "camera-interrupted")
                statusMessage = "相机中断：\(message)"
            }
            scheduleCameraReconnect()
        case .authorizing:
            statusMessage = "请允许 FruitWave 使用 iPhone 相机"
        case .idle, .selecting:
            break
        }
    }

    private func scheduleCameraReconnect() {
        guard wantsCameraConnection else { return }
        cameraReconnectTask?.cancel()
        let interruptedSessionID = camera.sessionID
        reconnectAttempts += 1
        // Back off 1.5 s → 3 s → 6 s → 12 s so a slow route renegotiation is
        // not hammered by repeated session rebuilds.
        let delay = min(1.5 * pow(2.0, Double(reconnectAttempts - 1)), 12.0)
        cameraReconnectTask = Task { [weak self] in
            // Continuity Camera can emit a short interruption while tvOS and
            // iPhone renegotiate the route. Give that path time to recover so
            // calibration is not discarded because of a transient event.
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.wantsCameraConnection,
                  self.camera.sessionID == interruptedSessionID else { return }
            // The picker owns pairing: never re-present it mid-scan, and only
            // reconnect a session that was actually configured before.
            guard !self.showDevicePicker else {
                self.logCameraFlow("reconnect attempt \(self.reconnectAttempts): picker up, skip")
                return
            }
            guard self.camera.activeDeviceUniqueID != nil else {
                self.logCameraFlow("reconnect attempt \(self.reconnectAttempts): no configured session, skip")
                return
            }
            switch self.camera.state {
            case .streaming, .configuring, .selecting, .authorizing:
                self.logCameraFlow("reconnect attempt \(self.reconnectAttempts): state recovered, skip")
                return
            case .idle, .interrupted, .failed:
                self.logCameraFlow("reconnect attempt \(self.reconnectAttempts): beginDeviceConnection")
                self.statusMessage = "正在自动恢复 iPhone 连接…"
                self.beginDeviceConnection()
            }
        }
    }

    private func handlePoseFailure(_ message: String) {
        guard state == .framing || state == .calibration else { return }
        statusMessage = "人体姿态识别失败：\(message)"
    }

    private func handlePreferredCameraChange(_ device: AVCaptureDevice) {
        guard wantsCameraConnection,
              device.isContinuityCamera,
              camera.activeDeviceUniqueID != device.uniqueID else { return }
        // Pairing may publish the camera before SwiftUI delivers
        // `onDidConnect`. Preserve it and activate it after dismissal rather
        // than throwing away a valid system connection event.
        guard !showDevicePicker, camera.state != .selecting else {
            pendingPreferredCamera = device
            logCameraFlow("preferredCameraChange retained while picker is up")
            return
        }
        // tvOS re-publishes the already-streaming camera as the new preferred
        // device shortly after connection. Rebuilding the session mid-game
        // would interrupt it; a genuine switch to another iPhone always goes
        // through a disconnect first, and the reconnect path picks up the new
        // device there.
        guard camera.state != .streaming else {
            Self.logger.info("Ignoring preferred camera promotion while streaming")
            return
        }
        Self.logger.notice("Preferred camera changed, reconfiguring")
        logCameraFlow("preferredCameraChange accepted -> configureCamera")
        configureCamera(device)
        statusMessage = "检测到 iPhone 相机变化，正在恢复画面…"
    }

    private func handleCenterStageChange(_ isActive: Bool) {
        guard wantsCameraConnection, state != .waitingForConnection else { return }
        if state == .framing {
            updateFramingStatus()
            return
        }
        let stateDescription = isActive ? "已开启" : "已关闭"
        Self.logger.warning("Center Stage \(stateDescription, privacy: .public) while \(String(describing: self.state), privacy: .public)")
        requireRecalibration(message: "“人物居中”\(stateDescription)，取景范围已变化，请重新校准")
    }

    private func requireRecalibration(message: String) {
        Self.logger.warning("Require recalibration: \(message, privacy: .public), state \(String(describing: self.state), privacy: .public)")
        invalidateVisionRun()
        playerTracker.reset()
        sampler.reset()
        calibrationWristFilter.reset()
        mapper.invalidate()
        motion.reset()
        renderer.clearTrail()
        currentCandidate = nil
        currentCandidateTime = nil
        currentHandPosition = nil; currentHandSampleTime = nil
        framingWristPreviewPoint = nil
        lowerLeft = nil
        lastCalibrationRawPoint = nil
        lastValidHandTime = nil
        identityUncertainSince = nil
        reviewDwellStartedAt = nil
        calibrationStep = 0
        calibrationProgress = 0
        calibrationCursor = nil
        pendingCalibrationPoint = nil
        pendingCalibrationPointLockedAt = nil

        switch state {
        case .playing, .resuming, .ready:
            pause(reason: .mappingChanged, source: "mapping-changed")
        case .results:
            _ = coordinator.transition(to: .ready)
        case .waitingForConnection, .framing, .calibration, .paused:
            break
        }
        if state == .ready { _ = coordinator.transition(to: .calibration) }
        if state == .paused { _ = coordinator.transition(to: .calibration) }
        if state == .calibration { _ = coordinator.transition(to: .framing) }
        statusMessage = message
        statusMessageLocked = true
    }

    private func startCameraWatchdog(for sessionID: UUID) {
        cameraWatchdogTask?.cancel()
        lastPoseSampleTime = nil
        frameLiveness.reset()
        let startedAt = ProcessInfo.processInfo.systemUptime
        cameraWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.camera.sessionID == sessionID else { return }
                let now = ProcessInfo.processInfo.systemUptime
                switch self.camera.state {
                case .configuring where now - startedAt >= 8:
                    self.statusMessage = "尚未收到 iPhone 画面，请确认相机授权和网络连接"
                case .streaming:
                    guard self.frameLiveness.isStale(at: now) else { continue }
                    if self.state == .playing {
                        guard now >= self.playingGraceUntil else {
                            self.logDiagnostic("watchdog stale within grace")
                            continue
                        }
                        self.pause(reason: .cameraInterrupted, source: "watchdog-stale")
                    } else if self.state != .paused {
                        self.statusMessage = "画面已停止，请检查 iPhone 连接"
                    }
                default:
                    continue
                }
            }
        }
    }

    private func tick(now: TimeInterval) {
        guard state == .playing else { return }
        guard isDemoMode || camera.state == .streaming else {
            pause(reason: .cameraInterrupted, source: "tick-camera-state")
            return
        }
        gameplay.tick(at: now) { gameTime in
            // Bombs join the wave after 10 s, ~12% of spawns; they're never
            // part of the plain random roster.
            let kind: FruitKind
            if !self.isDemoMode, gameTime > 10, Double.random(in: 0..<1) < 0.12 {
                kind = .bomb
            } else {
                kind = FruitKind.allCases.filter { $0 != .bomb }.randomElement() ?? .watermelon
            }
            return Fruit(kind: kind, spawnedAt: gameTime, position: .init(x: Double.random(in: 0.1...0.9), y: -0.06), velocity: .init(x: Double.random(in: -0.05...0.05), y: Double.random(in: 0.16...0.23)))
        }
        recordGameClock(monotonic: now)
        var demoSlash: SlashSegment?
        var demoHits: [HitEvent] = []
        if isDemoMode, let slash = makeDemoSlash(at: now) {
            demoSlash = slash
            let startGameTime = max(0, gameplay.gameTime - max(0, slash.endTime - slash.startTime))
            demoHits = gameplay.apply(slash, gameTimeRange: startGameTime...gameplay.gameTime)
            currentHandPosition = slash.endPosition
            currentHandSampleTime = now
        }
        if score != gameplay.score { score = gameplay.score }
        let remaining = max(0, Int(ceil(gameplay.configuration.duration - gameplay.gameTime)))
        if secondsRemaining != remaining { secondsRemaining = remaining }
        render(hand: currentHandPosition, slash: demoSlash, hits: demoHits)
        if isAutomatedDemoVerification, !demoHits.isEmpty {
            demoVerificationHitCount += demoHits.count
            print("DEMO_VERIFY rendered_hits=\(demoVerificationHitCount) score=\(gameplay.score) active_fruit=\(gameplay.fruits.filter { $0.state == .active }.count)")
            if demoVerificationHitCount >= 3, !didReportDemoVerification {
                didReportDemoVerification = true
                print("DEMO_VERIFY PASS: spawn, flight, slash collision, slice render and scoring completed")
            }
        }
        if gameplay.isFinished { finishRound() }
    }

    private func makeDemoSlash(at now: TimeInterval) -> SlashSegment? {
        if let lastDemoSlashTime, now - lastDemoSlashTime < 0.58 { return nil }
        guard let target = gameplay.fruits.first(where: {
            guard $0.state == .active, $0.kind != .bomb else { return false }
            let position = $0.position(at: gameplay.gameTime)
            // Let fruit travel well into the visible playfield before the
            // automated blade strikes. Cutting at the old 0.04 threshold made
            // the demo technically score while the fruit and juice effect
            // were still clipped by the bottom edge of the television.
            return position.y >= 0.26 && position.y <= 0.60
        }) else { return nil }

        lastDemoSlashTime = now
        let center = target.position(at: gameplay.gameTime)
        let direction = gameplay.score.isMultiple(of: 20)
            ? Vector2(x: 0.13, y: 0.09)
            : Vector2(x: 0.13, y: -0.09)
        return SlashSegment(
            sessionID: demoSessionID,
            roundID: currentRoundID,
            playerSessionID: activePlayerID,
            mappingVersion: mapper.mappingVersion,
            startTime: now - 0.08,
            endTime: now,
            startPosition: center - direction,
            endPosition: center + direction,
            speed: direction.length * 2 / 0.08
        )
    }

    /// Transitions to the results screen and records the high score.
    private func finishRound() {
        _ = coordinator.transition(to: .results)
        highScore = max(highScore, score)
        UserDefaults.standard.set(highScore, forKey: "fruitWave.highScore")
        logDiagnostic("finishRound score=\(score) highScore=\(highScore)")
    }

    private func render(hand: Vector2?, slash: SlashSegment?, hits: [HitEvent]) {
        renderer.render(.init(fruits: gameplay.fruits, gameTime: gameplay.gameTime, score: gameplay.score, hand: hand, handCapturedAt: currentHandSampleTime, slash: slash, hits: hits))
    }

    private func invalidateVisionRun() {
        runEpochGate.advance(to: poseEngine.reset())
    }

    private func recordFrameArrival(_ packet: FramePacket) {
        frameLiveness.recordFrame(receivedAt: packet.receivedAtMonotonic)
        if let previous = lastFrameArrivalForMetrics {
            let interval = packet.receivedAtMonotonic - previous
            if interval > 0, interval < 1 { appendMetric(interval, to: &frameIntervals) }
        }
        lastFrameArrivalForMetrics = packet.receivedAtMonotonic
        framesSinceDiagnosticsWrite += 1
        if framesSinceDiagnosticsWrite >= 300 {
            framesSinceDiagnosticsWrite = 0
            persistDiagnostics()
        }
    }

    private func appendMetric(_ value: TimeInterval, to values: inout [TimeInterval]) {
        guard value.isFinite, value >= 0 else { return }
        values.append(value)
        if values.count > 900 { values.removeFirst(values.count - 900) }
    }

    private func percentile(_ values: [TimeInterval], _ quantile: Double) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * quantile)) - 1))
        return sorted[index]
    }

    private func persistDiagnostics() {
        let sortedIntervals = frameIntervals.sorted()
        let snapshot = RuntimeDiagnosticsSnapshot(
            generatedAtUptime: ProcessInfo.processInfo.systemUptime,
            pixelWidth: captureGeometry?.pixelWidth,
            pixelHeight: captureGeometry?.pixelHeight,
            sampleCount: frameIntervals.count,
            frameIntervalP50Milliseconds: percentile(sortedIntervals, 0.50).map { $0 * 1_000 },
            frameIntervalP95Milliseconds: percentile(sortedIntervals, 0.95).map { $0 * 1_000 },
            frameIntervalP99Milliseconds: percentile(sortedIntervals, 0.99).map { $0 * 1_000 },
            frameIntervalsAbove33MillisecondsRatio: sortedIntervals.isEmpty ? nil : Double(sortedIntervals.filter { $0 > 1.0 / 30.0 }.count) / Double(sortedIntervals.count),
            queueP50Milliseconds: percentile(queueDurations, 0.50).map { $0 * 1_000 },
            queueP95Milliseconds: percentile(queueDurations, 0.95).map { $0 * 1_000 },
            inferenceP50Milliseconds: percentile(inferenceDurations, 0.50).map { $0 * 1_000 },
            inferenceP95Milliseconds: percentile(inferenceDurations, 0.95).map { $0 * 1_000 },
            resultAgeP50Milliseconds: percentile(resultAges, 0.50).map { $0 * 1_000 },
            resultAgeP95Milliseconds: percentile(resultAges, 0.95).map { $0 * 1_000 },
            droppedFrames: Dictionary(uniqueKeysWithValues: camera.frameDropCounts.map { ($0.key.rawValue, $0.value) })
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = directory.appendingPathComponent("FruitWaveDiagnostics.json")
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }

    private func recordGameClock(monotonic: TimeInterval) {
        gameClockHistory.record(monotonicTime: monotonic, gameTime: gameplay.gameTime)
    }

    private func gameTimeRange(for slash: SlashSegment) -> ClosedRange<TimeInterval>? {
        guard slash.roundID == currentRoundID,
              let range = gameClockHistory.gameTimeRange(from: slash.startTime, to: slash.endTime) else { return nil }
        return range
    }

    private func pauseText(_ reason: PauseReason) -> String {
        switch reason {
        case .user: "游戏已暂停"
        case .cameraInterrupted: "相机中断，恢复后可继续"
        case .handUnavailable: "未能稳定识别，请检查光线、遮挡与站位"
        case .identityUncertain: "玩家身份不确定，请重新校准"
        case .mappingChanged: "画面映射已变化，请重新校准"
        }
    }
}

private struct RuntimeDiagnosticsSnapshot: Codable, Sendable {
    let generatedAtUptime: TimeInterval
    let pixelWidth: Int?
    let pixelHeight: Int?
    let sampleCount: Int
    let frameIntervalP50Milliseconds: Double?
    let frameIntervalP95Milliseconds: Double?
    let frameIntervalP99Milliseconds: Double?
    let frameIntervalsAbove33MillisecondsRatio: Double?
    let queueP50Milliseconds: Double?
    let queueP95Milliseconds: Double?
    let inferenceP50Milliseconds: Double?
    let inferenceP95Milliseconds: Double?
    let resultAgeP50Milliseconds: Double?
    let resultAgeP95Milliseconds: Double?
    let droppedFrames: [String: Int]
}
