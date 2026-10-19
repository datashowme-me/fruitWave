import AVFoundation
import FruitWaveCore
import Vision

final class PoseTrackingEngine: @unchecked Sendable {
    var onSample: (@Sendable (PoseSample) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    private let queue = DispatchQueue(label: "com.fruitwave.pose.inference", qos: .userInteractive)
    private let stateLock = NSLock()
    private var isProcessing = false
    private struct WorkItem { let packet: FramePacket; let runEpoch: UInt64; let sequence: UInt64 }
    private var pending: WorkItem?
    private var runEpoch: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private let sequenceHandler = VNSequenceRequestHandler()

    func submit(_ packet: FramePacket) {
        stateLock.lock()
        nextSequence &+= 1
        let item = WorkItem(packet: packet, runEpoch: runEpoch, sequence: nextSequence)
        if isProcessing {
            pending = item
            stateLock.unlock()
            return
        }
        isProcessing = true
        stateLock.unlock()

        queue.async { [weak self] in self?.processLoop(startingWith: item) }
    }

    @discardableResult func reset() -> UInt64 {
        stateLock.lock()
        runEpoch &+= 1
        pending = nil
        let epoch = runEpoch
        stateLock.unlock()
        return epoch
    }

    private func processLoop(startingWith firstItem: WorkItem) {
        var item: WorkItem? = firstItem
        while let current = item {
            autoreleasepool { processOne(current) }

            stateLock.lock()
            item = pending
            pending = nil
            if item == nil { isProcessing = false }
            stateLock.unlock()
        }
    }

    private func processOne(_ item: WorkItem) {
        let packet = item.packet
        let request = VNDetectHumanBodyPoseRequest()
        let inferenceStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            try sequenceHandler.perform([request], on: packet.pixelBuffer, orientation: packet.orientation)
            let candidates = try (request.results ?? []).compactMap(makeCandidate)
            onSample?(PoseSample(
                sessionID: packet.sessionID,
                runEpoch: item.runEpoch,
                sequence: item.sequence,
                sourceTime: packet.sourcePTS.seconds,
                capturedAtMonotonic: packet.capturedAtMonotonic,
                receivedAtMonotonic: packet.receivedAtMonotonic,
                inferenceStartedAt: inferenceStartedAt,
                inferenceCompletedAt: ProcessInfo.processInfo.systemUptime,
                geometry: packet.geometry,
                candidates: candidates
            ))
        } catch {
            onFailure?(error.localizedDescription)
            onSample?(PoseSample(
                sessionID: packet.sessionID,
                runEpoch: item.runEpoch,
                sequence: item.sequence,
                sourceTime: packet.sourcePTS.seconds,
                capturedAtMonotonic: packet.capturedAtMonotonic,
                receivedAtMonotonic: packet.receivedAtMonotonic,
                inferenceStartedAt: inferenceStartedAt,
                inferenceCompletedAt: ProcessInfo.processInfo.systemUptime,
                geometry: packet.geometry,
                candidates: []
            ))
        }
    }

    private func makeCandidate(_ observation: VNHumanBodyPoseObservation) throws -> PoseCandidate? {
        let leftShoulder = try observation.recognizedPoint(.leftShoulder)
        let rightShoulder = try observation.recognizedPoint(.rightShoulder)
        // Continuity Camera is commonly framed waist-up. Requiring Vision's
        // root joint rejects an otherwise clear player whenever the lower body
        // is outside the frame, so use the shoulders as the identity anchor.
        guard leftShoulder.confidence >= 0.2, rightShoulder.confidence >= 0.2 else { return nil }
        let center = Vector2(
            x: (leftShoulder.location.x + rightShoulder.location.x) / 2,
            y: (leftShoulder.location.y + rightShoulder.location.y) / 2
        )
        let scale = hypot(leftShoulder.location.x - rightShoulder.location.x, leftShoulder.location.y - rightShoulder.location.y)
        guard scale >= 0.04 else { return nil }
        return PoseCandidate(
            torsoCenter: center,
            torsoScale: scale,
            leftWrist: try joint(.leftWrist, from: observation),
            rightWrist: try joint(.rightWrist, from: observation)
        )
    }

    private func joint(_ name: VNHumanBodyPoseObservation.JointName, from observation: VNHumanBodyPoseObservation) throws -> JointPoint? {
        let point = try observation.recognizedPoint(name)
        // Preserve moderately confident points for the slow, dwell-based
        // calibration flow. Gameplay applies its stricter 0.5 threshold in
        // MotionProcessor before a point can create a slash.
        guard point.confidence >= 0.25 else { return nil }
        // Mirror exactly once so preview and mapped movement share the same direction.
        return JointPoint(position: .init(x: 1 - point.location.x, y: point.location.y), confidence: Double(point.confidence))
    }
}
