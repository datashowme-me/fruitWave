import AVFoundation
import FruitWaveCore
import Vision

final class PoseTrackingEngine: @unchecked Sendable {
    var onSample: (@Sendable (PoseSample) -> Void)?
    private let queue = DispatchQueue(label: "com.fruitwave.pose.inference", qos: .userInteractive)
    private var isProcessing = false
    private var pending: FramePacket?
    private let sequenceHandler = VNSequenceRequestHandler()
    private var sequence = 0

    func submit(_ packet: FramePacket) {
        queue.async { [weak self] in
            guard let self else { return }
            if isProcessing {
                pending = packet
                return
            }
            isProcessing = true
            process(packet)
        }
    }

    func reset() {
        queue.async { [weak self] in self?.pending = nil }
    }

    private func process(_ packet: FramePacket) {
        defer {
            if let next = pending {
                pending = nil
                process(next)
            } else {
                isProcessing = false
            }
        }
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try sequenceHandler.perform([request], on: packet.pixelBuffer, orientation: packet.orientation)
            sequence += 1
            let candidates = try (request.results ?? []).compactMap(makeCandidate)
            onSample?(PoseSample(
                sessionID: packet.sessionID,
                sourceTime: packet.sourcePTS.seconds,
                receivedAtMonotonic: packet.receivedAtMonotonic,
                inferenceCompletedAt: ProcessInfo.processInfo.systemUptime,
                candidates: candidates
            ))
        } catch {
            onSample?(PoseSample(sessionID: packet.sessionID, sourceTime: packet.sourcePTS.seconds, receivedAtMonotonic: packet.receivedAtMonotonic, inferenceCompletedAt: ProcessInfo.processInfo.systemUptime, candidates: []))
        }
    }

    private func makeCandidate(_ observation: VNHumanBodyPoseObservation) throws -> PoseCandidate? {
        let neck = try observation.recognizedPoint(.neck)
        let root = try observation.recognizedPoint(.root)
        let leftShoulder = try observation.recognizedPoint(.leftShoulder)
        let rightShoulder = try observation.recognizedPoint(.rightShoulder)
        guard neck.confidence >= 0.3, root.confidence >= 0.3,
              leftShoulder.confidence >= 0.3, rightShoulder.confidence >= 0.3 else { return nil }
        let center = Vector2(x: (neck.location.x + root.location.x) / 2, y: (neck.location.y + root.location.y) / 2)
        let scale = hypot(leftShoulder.location.x - rightShoulder.location.x, leftShoulder.location.y - rightShoulder.location.y)
        return PoseCandidate(
            torsoCenter: center,
            torsoScale: scale,
            leftWrist: try joint(.leftWrist, from: observation),
            rightWrist: try joint(.rightWrist, from: observation)
        )
    }

    private func joint(_ name: VNHumanBodyPoseObservation.JointName, from observation: VNHumanBodyPoseObservation) throws -> JointPoint? {
        let point = try observation.recognizedPoint(name)
        guard point.confidence >= 0.5 else { return nil }
        // Mirror exactly once so preview and mapped movement share the same direction.
        return JointPoint(position: .init(x: 1 - point.location.x, y: point.location.y), confidence: Double(point.confidence))
    }
}
