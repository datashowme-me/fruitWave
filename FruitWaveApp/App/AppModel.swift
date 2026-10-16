import AVFoundation
import AVKit
import FruitWaveCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var coordinator = GameCoordinator()
    private(set) var score = 0
    private(set) var highScore = UserDefaults.standard.integer(forKey: "fruitWave.highScore")
    private(set) var secondsRemaining = 90
    private(set) var statusMessage = "连接 iPhone 后开始"
    var selectedHand: HandSide = .right
    var soundEnabled = true
    var showDevicePicker = false
    var calibrationStep = 0
    var countdown = 3
    private(set) var isResumeCountdown = false

    let camera = CameraSessionManager()
    let scene = GameScene(size: CGSize(width: 1920, height: 1080))

    private let poseEngine = PoseTrackingEngine()
    private var playerTracker = PlayerTracker()
    private var mapper = CalibrationMapper()
    private var sampler = CalibrationSampler()
    private var motion = MotionProcessor()
    private var gameplay = GameplayEngine()
    private var currentCandidate: PoseCandidate?
    private var currentHandPosition: Vector2?
    private var lowerLeft: Vector2?
    private var lastValidHandTime: TimeInterval?
    private var countdownTask: Task<Void, Never>?
    private let reviewTargets = [Vector2(x: 0.15, y: 0.10), .init(x: 0.85, y: 0.10), .init(x: 0.85, y: 0.46), .init(x: 0.15, y: 0.46), .init(x: 0.5, y: 0.28)]

    var state: GameState { coordinator.state }
    var pauseReason: PauseReason? { coordinator.pauseReason }
    var reviewTarget: Vector2? {
        let index = calibrationStep - 2
        return reviewTargets.indices.contains(index) ? reviewTargets[index] : nil
    }

    init() {
        camera.onFrame = { [weak poseEngine] packet in poseEngine?.submit(packet) }
        poseEngine.onSample = { [weak self] sample in
            Task { @MainActor in self?.consume(sample) }
        }
        scene.onTick = { [weak self] now in self?.tick(now: now) }
    }

    func requestConnection() {
        camera.beginSelection()
        showDevicePicker = true
    }

    func connect(_ device: AVContinuityDevice?) {
        showDevicePicker = false
        guard let cameraDevice = device?.videoDevices.first else {
            statusMessage = "未选择设备，可重新连接"
            return
        }
        camera.configure(with: cameraDevice)
        statusMessage = "正在等待视频画面…"
    }

    func selectHand(_ side: HandSide) { selectedHand = side }

    func beginCalibration() {
        guard let candidate = playerTracker.lock(candidates: currentCandidate.map { [$0] } ?? []) else {
            statusMessage = "需要画面中只有一名清晰可见的玩家"
            return
        }
        currentCandidate = candidate
        calibrationStep = 0
        lowerLeft = nil
        sampler.reset()
        _ = coordinator.transition(to: .calibration)
        statusMessage = "把所选手移动到舒适活动区左下角，并保持稳定"
    }

    func confirmCalibrationPoint() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let point = sampler.stableMedian(at: now) else {
            statusMessage = "手腕尚未稳定，请保持约半秒后重试"
            return
        }
        if calibrationStep == 0 {
            lowerLeft = point
            calibrationStep = 1
            sampler.reset()
            statusMessage = "现在移动到舒适活动区右上角，并保持稳定"
        } else if calibrationStep == 1, let lowerLeft {
            guard mapper.calibrate(lowerLeft: lowerLeft, upperRight: point) else {
                statusMessage = "活动范围过小或方向不正确，请重采右上角"
                sampler.reset()
                return
            }
            calibrationStep = 2
            statusMessage = "依次触达屏幕目标并按遥控器确认"
        } else {
            guard let target = reviewTarget, let hand = currentHandPosition, (target - hand).length <= 0.09 else {
                statusMessage = "请把手部指示点移动到目标附近"
                return
            }
            calibrationStep += 1
            if calibrationStep - 2 >= reviewTargets.count {
                _ = coordinator.transition(to: .ready)
                statusMessage = "校准完成"
            }
        }
    }

    func startGame() { beginCountdown(resuming: false) }

    func pause(reason: PauseReason = .user) {
        guard state == .playing || state == .resuming || state == .ready else { return }
        countdownTask?.cancel()
        _ = coordinator.transition(to: .paused, reason: reason)
        gameplay.pause(); motion.reset(); scene.clearTrail()
        statusMessage = pauseText(reason)
    }

    func resume() {
        guard camera.state == .streaming, currentHandPosition != nil else {
            statusMessage = "相机和手腕稳定后才能继续"
            return
        }
        guard coordinator.transition(to: .resuming) else { return }
        beginCountdown(resuming: true)
    }

    func recalibrate() {
        countdownTask?.cancel(); motion.reset(); mapper.invalidate(); playerTracker.reset()
        _ = coordinator.transition(to: .calibration)
        _ = coordinator.transition(to: .framing)
        statusMessage = "请重新确认画面后开始校准"
    }

    func restart() {
        motion.reset(); scene.clearTrail(); _ = coordinator.transition(to: .ready); startGame()
    }

    func exitToConnection() {
        countdownTask?.cancel(); camera.stop(); poseEngine.reset(); playerTracker.reset(); motion.reset(); mapper.invalidate()
        if state == .playing { pause(reason: .user) }
        while state != .waitingForConnection {
            if !coordinator.transition(to: .waitingForConnection) { break }
        }
        coordinator = GameCoordinator()
        statusMessage = "连接 iPhone 后开始"
    }

    private func consume(_ sample: PoseSample) {
        guard sample.sessionID == camera.sessionID else { return }
        if camera.state != .streaming {
            camera.markStreaming()
            if state == .waitingForConnection { _ = coordinator.transition(to: .framing) }
        }
        let candidate: PoseCandidate?
        if state == .framing {
            candidate = sample.candidates.count == 1 ? sample.candidates[0] : nil
            currentCandidate = candidate
            statusMessage = candidate == nil ? "请确保画面中只有一名玩家" : "选择左手或右手，然后开始校准"
            return
        } else {
            candidate = playerTracker.track(candidates: sample.candidates)
        }
        guard let candidate, let playerID = playerTracker.playerSessionID else {
            invalidateHand(reason: .identityUncertain, now: sample.inferenceCompletedAt)
            if state == .playing { pause(reason: .identityUncertain) }
            return
        }
        let joint = selectedHand == .left ? candidate.leftWrist : candidate.rightWrist
        guard let joint else {
            invalidateHand(reason: .lowConfidence, now: sample.inferenceCompletedAt)
            return
        }
        lastValidHandTime = sample.inferenceCompletedAt
        sampler.append(.init(time: sample.inferenceCompletedAt, point: joint.position, isValid: true))
        let mapped = mapper.map(joint.position)
        currentHandPosition = mapped?.position
        guard let mapped, mapped.isInside else { motion.reset(); return }
        let hand = TrackedHand(playerSessionID: playerID, handSide: selectedHand, mappingVersion: mapper.mappingVersion, sampleTime: sample.receivedAtMonotonic, receivedAt: sample.inferenceCompletedAt, mappedPosition: mapped.position, confidence: joint.confidence)
        guard state == .playing else { render(hand: mapped.position, slash: nil, hits: []); return }
        let slash = motion.process(hand, sessionID: sample.sessionID, now: sample.inferenceCompletedAt)
        var hits: [HitEvent] = []
        if let slash {
            let duration = max(0, slash.endTime - slash.startTime)
            hits = gameplay.apply(slash, gameTimeRange: max(0, gameplay.gameTime - duration)...gameplay.gameTime)
            score = gameplay.score
        }
        render(hand: mapped.position, slash: slash, hits: hits)
    }

    private func invalidateHand(reason: InvalidHandReason, now: TimeInterval) {
        sampler.append(.init(time: now, point: .zero, isValid: false))
        currentHandPosition = nil; motion.reset(); scene.clearTrail()
        if let lastValidHandTime, now - lastValidHandTime >= 0.5, state == .playing { pause(reason: .handUnavailable) }
    }

    private func tick(now: TimeInterval) {
        guard state == .playing else { return }
        guard camera.state == .streaming else {
            pause(reason: .cameraInterrupted)
            return
        }
        gameplay.tick(at: now) { gameTime in
            let kind = FruitKind.allCases.randomElement() ?? .watermelon
            return Fruit(kind: kind, spawnedAt: gameTime, position: .init(x: Double.random(in: 0.1...0.9), y: -0.06), velocity: .init(x: Double.random(in: -0.05...0.05), y: Double.random(in: 0.16...0.23)))
        }
        score = gameplay.score
        secondsRemaining = max(0, Int(ceil(gameplay.configuration.duration - gameplay.gameTime)))
        render(hand: currentHandPosition, slash: nil, hits: [])
        if gameplay.isFinished {
            _ = coordinator.transition(to: .results)
            highScore = max(highScore, score)
            UserDefaults.standard.set(highScore, forKey: "fruitWave.highScore")
        }
    }

    private func beginCountdown(resuming: Bool) {
        countdownTask?.cancel()
        countdown = 3
        isResumeCountdown = resuming
        if !resuming, state != .ready { return }
        if !resuming { _ = coordinator.transition(to: .resuming) }
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for value in stride(from: 3, through: 1, by: -1) {
                countdown = value
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if resuming {
                gameplay.resume(at: now); _ = coordinator.transition(to: .playing)
            } else {
                gameplay.start(at: now); score = 0; secondsRemaining = 90; _ = coordinator.transition(to: .playing)
            }
            motion.reset(); scene.clearTrail()
        }
    }

    private func render(hand: Vector2?, slash: SlashSegment?, hits: [HitEvent]) {
        scene.render(.init(fruits: gameplay.fruits, gameTime: gameplay.gameTime, score: gameplay.score, hand: hand, slash: slash, hits: hits))
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
