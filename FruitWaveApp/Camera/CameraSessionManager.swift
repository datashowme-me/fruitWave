@preconcurrency import AVFoundation
import FruitWaveCore
import ImageIO
import Observation

@MainActor
@Observable
final class CameraSessionManager {
    private(set) var state: CameraState = .idle
    let captureSession = AVCaptureSession()
    var onFrame: (@Sendable (FramePacket) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.fruitwave.camera.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "com.fruitwave.camera.frames", qos: .userInteractive)
    private let delegate = VideoOutputDelegate()
    private var notifications: [NSObjectProtocol] = []
    private(set) var sessionID = UUID()

    init() {
        delegate.onFrame = { [weak self] buffer, pts, orientation, id in
            let packet = FramePacket(
                pixelBuffer: buffer,
                sourcePTS: pts,
                receivedAtMonotonic: ProcessInfo.processInfo.systemUptime,
                orientation: orientation,
                sessionID: id
            )
            Task { @MainActor in self?.onFrame?(packet) }
        }
        observeSession()
    }

    func beginSelection() { state = .selecting }

    func markStreaming() { state = .streaming }

    func configure(with camera: AVCaptureDevice) {
        state = .configuring
        sessionID = UUID()
        delegate.sessionID = sessionID
        let captureSession = captureSession
        let delegate = delegate
        let outputQueue = outputQueue
        sessionQueue.async { [weak self] in
            captureSession.beginConfiguration()
            captureSession.inputs.forEach(captureSession.removeInput)
            captureSession.outputs.forEach(captureSession.removeOutput)
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard captureSession.canAddInput(input) else { throw CameraError.cannotAddInput }
                captureSession.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
                output.setSampleBufferDelegate(delegate, queue: outputQueue)
                guard captureSession.canAddOutput(output) else { throw CameraError.cannotAddOutput }
                captureSession.addOutput(output)
                captureSession.commitConfiguration()
                captureSession.startRunning()
            } catch {
                captureSession.commitConfiguration()
                Task { @MainActor in self?.state = .failed(error.localizedDescription) }
            }
        }
    }

    func stop() {
        let captureSession = captureSession
        sessionQueue.async { captureSession.stopRunning() }
        state = .idle
    }

    private func observeSession() {
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: captureSession, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.state = .interrupted("相机采集中断") }
        })
        notifications.append(center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: captureSession, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.state = self?.captureSession.isRunning == true ? .streaming : .idle }
        })
        notifications.append(center.addObserver(forName: .AVCaptureSessionRuntimeError, object: captureSession, queue: .main) { [weak self] note in
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "相机运行错误"
            Task { @MainActor in self?.state = .failed(message) }
        })
    }
}

private enum CameraError: LocalizedError {
    case cannotAddInput, cannotAddOutput
    var errorDescription: String? {
        switch self { case .cannotAddInput: "无法添加相机输入"; case .cannotAddOutput: "无法添加视频输出" }
    }
}

private final class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var sessionID = UUID()
    var onFrame: (@Sendable (CVPixelBuffer, CMTime, CGImagePropertyOrientation, UUID) -> Void)?
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation: CGImagePropertyOrientation
        switch Int(connection.videoRotationAngle.rounded()).positiveModulo(360) {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .up
        }
        onFrame?(buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer), orientation, sessionID)
    }
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int { (self % divisor + divisor) % divisor }
}
