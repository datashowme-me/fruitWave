@preconcurrency import AVFoundation
import FruitWaveCore
import ImageIO
import Observation

@MainActor
@Observable
final class CameraSessionManager {
    private(set) var state: CameraState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    let captureSession = AVCaptureSession()
    var onFrame: (@Sendable (FramePacket) -> Void)?
    var onStateChange: ((CameraState) -> Void)?
    var onPreferredCameraChange: ((AVCaptureDevice) -> Void)?
    var onCenterStageChange: ((Bool) -> Void)?

    private(set) var frameDropCounts: [FrameDropReason: Int] = [:]
    private(set) var isCenterStageActive = false

    private let sessionQueue = DispatchQueue(label: "com.fruitwave.camera.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "com.fruitwave.camera.frames", qos: .userInteractive)
    private var videoOutputDelegate: VideoOutputDelegate?
    private var notifications: [NSObjectProtocol] = []
    private var centerStageObservation: NSKeyValueObservation?
    private let preferredCameraObserver = PreferredCameraObserver()
    private(set) var sessionID = UUID()
    private(set) var activeDeviceUniqueID: String?

    init() {
        observeSession()
        preferredCameraObserver.handler = { [weak self] device in
            Task { @MainActor in self?.onPreferredCameraChange?(device) }
        }
    }

    func beginSelection() { state = .selecting }

    func requestVideoAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            state = .authorizing
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { state = .failed("未获得相机权限") }
            return granted
        case .denied, .restricted:
            state = .failed("相机权限已关闭，请在 Apple TV 设置中允许 FruitWave 使用相机")
            return false
        @unknown default:
            state = .failed("无法确认相机权限")
            return false
        }
    }

    func cancelSelection() {
        if state == .selecting { state = .idle }
    }

    func preferredContinuityCamera() -> AVCaptureDevice? {
        if let preferred = AVCaptureDevice.systemPreferredCamera,
           preferred.isContinuityCamera,
           preferred.isConnected {
            return preferred
        }
        guard let fallback = AVCaptureDevice.default(
            .continuityCamera,
            for: .video,
            position: .unspecified
        ), fallback.isConnected else { return nil }
        return fallback
    }

    func markStreaming(sessionID expectedSessionID: UUID) {
        guard expectedSessionID == sessionID else { return }
        state = .streaming
    }

    func configure(with camera: AVCaptureDevice) {
        guard activeDeviceUniqueID != camera.uniqueID || state != .streaming else { return }
        activeDeviceUniqueID = camera.uniqueID
        if notifications.isEmpty { observeSession() }
        observeGeometryChanges(on: camera)
        state = .configuring
        sessionID = UUID()
        let configuredSessionID = sessionID
        let delegate = VideoOutputDelegate(
            sessionID: configuredSessionID,
            captureSession: captureSession,
            onFrame: onFrame,
            onDrop: { [weak self] reason in
                Task { @MainActor in
                    guard self?.sessionID == configuredSessionID else { return }
                    self?.frameDropCounts[reason, default: 0] += 1
                }
            }
        )
        videoOutputDelegate = delegate
        let captureSession = captureSession
        let outputQueue = outputQueue
        sessionQueue.async { [weak self] in
            captureSession.beginConfiguration()
            captureSession.inputs.forEach(captureSession.removeInput)
            captureSession.outputs.forEach(captureSession.removeOutput)
            do {
                if captureSession.canSetSessionPreset(.hd1280x720) {
                    captureSession.sessionPreset = .hd1280x720
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard captureSession.canAddInput(input) else { throw CameraError.cannotAddInput }
                captureSession.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                // Continuity cameras don't all expose the full-range 420 format.
                // Let AVFoundation use the device-native format so adding the
                // output can't force an unsupported active format.
                output.videoSettings = [:]
                output.setSampleBufferDelegate(delegate, queue: outputQueue)
                guard captureSession.canAddOutput(output) else { throw CameraError.cannotAddOutput }
                captureSession.addOutput(output)
                if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                    // Keep the pixel buffer unmirrored. The preview and joint
                    // coordinates each apply the same explicit mirror once.
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                captureSession.commitConfiguration()
                captureSession.startRunning()
            } catch {
                captureSession.inputs.forEach(captureSession.removeInput)
                captureSession.outputs.forEach(captureSession.removeOutput)
                captureSession.commitConfiguration()
                let message = error.localizedDescription
                Task { @MainActor in
                    guard self?.sessionID == configuredSessionID else { return }
                    self?.state = .failed(message)
                }
            }
        }
    }

    func stop() {
        // Rotate the identifier before stopping so callbacks already in flight
        // cannot be mistaken for frames from a future connection.
        sessionID = UUID()
        activeDeviceUniqueID = nil
        centerStageObservation?.invalidate()
        centerStageObservation = nil
        isCenterStageActive = false
        videoOutputDelegate = nil
        removeSessionObservers()
        let captureSession = captureSession
        sessionQueue.async {
            captureSession.stopRunning()
            captureSession.beginConfiguration()
            captureSession.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }
                .forEach { $0.setSampleBufferDelegate(nil, queue: nil) }
            captureSession.inputs.forEach(captureSession.removeInput)
            captureSession.outputs.forEach(captureSession.removeOutput)
            captureSession.commitConfiguration()
        }
        state = .idle
    }

    func suspend() {
        // Presenting the system Continuity Camera picker can temporarily make
        // the app inactive. There is no capture session to suspend while the
        // user is still selecting a phone, and stopping it here can cancel the
        // connection that the picker is about to return.
        guard activeDeviceUniqueID != nil, state != .idle else { return }
        let captureSession = captureSession
        sessionQueue.async { captureSession.stopRunning() }
        state = .interrupted("应用已进入后台")
    }

    func resume() {
        guard activeDeviceUniqueID != nil else { return }
        state = .configuring
        let captureSession = captureSession
        sessionQueue.async { captureSession.startRunning() }
    }

    private func observeSession() {
        guard notifications.isEmpty else { return }
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: captureSession, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.state != .idle else { return }
                self?.state = .interrupted("相机采集中断")
            }
        })
        notifications.append(center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: captureSession, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.restartCaptureAfterInterruption()
            }
        })
        notifications.append(center.addObserver(forName: .AVCaptureSessionRuntimeError, object: captureSession, queue: .main) { [weak self] note in
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "相机运行错误"
            Task { @MainActor in
                guard self?.state != .idle else { return }
                self?.state = .failed(message)
            }
        })
        notifications.append(center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] note in
            guard let device = note.object as? AVCaptureDevice else { return }
            Task { @MainActor in
                guard self?.activeDeviceUniqueID == device.uniqueID else { return }
                self?.activeDeviceUniqueID = nil
                // tvOS can re-publish the same Continuity Camera under a new
                // device instance shortly after the session starts. If a
                // connected camera is already available, treat this as a
                // camera swap so the session is rebuilt against the new
                // instance instead of showing a dead connection.
                if let replacement = AVCaptureDevice.default(
                    .continuityCamera, for: .video, position: .unspecified
                ), replacement.isConnected {
                    self?.onPreferredCameraChange?(replacement)
                } else {
                    self?.state = .interrupted("iPhone 相机已断开")
                }
            }
        })
    }

    private func removeSessionObservers() {
        let center = NotificationCenter.default
        notifications.forEach(center.removeObserver)
        notifications.removeAll()
    }

    private func restartCaptureAfterInterruption() {
        guard activeDeviceUniqueID != nil, state != .idle else { return }
        state = .configuring
        let captureSession = captureSession
        sessionQueue.async {
            if !captureSession.isRunning { captureSession.startRunning() }
        }
    }

    private func observeGeometryChanges(on camera: AVCaptureDevice) {
        centerStageObservation?.invalidate()
        // Read the current value as the baseline instead of using the `.initial`
        // option, so the first delivery is never mistaken for a change. Center
        // Stage often becomes active shortly after the session starts; that
        // activation is a real framing change, but the baseline itself is not.
        isCenterStageActive = camera.isCenterStageActive
        centerStageObservation = camera.observe(\.isCenterStageActive, options: [.new]) { [weak self] _, change in
            let isActive = change.newValue ?? false
            Task { @MainActor in
                guard let self, self.activeDeviceUniqueID == camera.uniqueID else { return }
                let changed = self.isCenterStageActive != isActive
                self.isCenterStageActive = isActive
                if changed { self.onCenterStageChange?(isActive) }
            }
        }
    }
}

private final class PreferredCameraObserver: NSObject, @unchecked Sendable {
    private static let cameraPropertyPath = "systemPreferredCamera"
    var handler: (@Sendable (AVCaptureDevice) -> Void)?

    override init() {
        super.init()
        AVCaptureDevice.addObserver(
            self,
            forKeyPath: Self.cameraPropertyPath,
            options: [.new],
            context: nil
        )
    }

    deinit {
        AVCaptureDevice.removeObserver(self, forKeyPath: Self.cameraPropertyPath)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == Self.cameraPropertyPath else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        guard let camera = change?[.newKey] as? AVCaptureDevice else { return }
        handler?(camera)
    }
}

private enum CameraError: LocalizedError {
    case cannotAddInput, cannotAddOutput
    var errorDescription: String? {
        switch self { case .cannotAddInput: "无法添加相机输入"; case .cannotAddOutput: "无法添加视频输出" }
    }
}

private final class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sessionID: UUID
    private weak var captureSession: AVCaptureSession?
    private let onFrame: (@Sendable (FramePacket) -> Void)?
    private let onDrop: (@Sendable (FrameDropReason) -> Void)?

    init(
        sessionID: UUID,
        captureSession: AVCaptureSession,
        onFrame: (@Sendable (FramePacket) -> Void)?,
        onDrop: (@Sendable (FrameDropReason) -> Void)?
    ) {
        self.sessionID = sessionID
        self.captureSession = captureSession
        self.onFrame = onFrame
        self.onDrop = onDrop
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation: CGImagePropertyOrientation
        switch Int(connection.videoRotationAngle.rounded()).positiveModulo(360) {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .up
        }
        let receivedAt = ProcessInfo.processInfo.systemUptime
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let capturedAt = captureTimeOnMonotonicClock(sourcePTS, receivedAt: receivedAt)
        onFrame?(FramePacket(
            pixelBuffer: buffer,
            sourcePTS: sourcePTS,
            capturedAtMonotonic: capturedAt,
            receivedAtMonotonic: receivedAt,
            orientation: orientation,
            geometry: CaptureGeometry(
                pixelWidth: CVPixelBufferGetWidth(buffer),
                pixelHeight: CVPixelBufferGetHeight(buffer),
                orientationRawValue: orientation.rawValue,
                isVideoMirrored: connection.isVideoMirrored
            ),
            sessionID: sessionID
        ))
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let value = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_DroppedFrameReason,
            attachmentModeOut: nil
        ) else {
            onDrop?(.unknown)
            return
        }
        if CFEqual(value, kCMSampleBufferDroppedFrameReason_FrameWasLate) {
            onDrop?(.frameWasLate)
        } else if CFEqual(value, kCMSampleBufferDroppedFrameReason_OutOfBuffers) {
            onDrop?(.outOfBuffers)
        } else if CFEqual(value, kCMSampleBufferDroppedFrameReason_Discontinuity) {
            onDrop?(.discontinuity)
        } else {
            onDrop?(.unknown)
        }
    }

    private func captureTimeOnMonotonicClock(_ sourcePTS: CMTime, receivedAt: TimeInterval) -> TimeInterval {
        guard sourcePTS.isValid,
              let sessionClock = captureSession?.synchronizationClock else { return receivedAt }
        let hostClock = CMClockGetHostTimeClock()
        let convertedPTS = sessionClock.convertTime(sourcePTS, to: hostClock)
        let hostNow = CMClockGetTime(hostClock)
        let age = CMTimeSubtract(hostNow, convertedPTS).seconds
        guard age.isFinite, age >= -0.1, age < 10 else { return receivedAt }
        return receivedAt - max(0, age)
    }
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int { (self % divisor + divisor) % divisor }
}
