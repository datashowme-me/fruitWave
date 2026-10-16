import AVFoundation
import ImageIO
import FruitWaveCore

struct FramePacket: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let sourcePTS: CMTime
    let receivedAtMonotonic: TimeInterval
    let orientation: CGImagePropertyOrientation
    let sessionID: UUID
}

struct PoseCandidate: Sendable {
    let torsoCenter: Vector2
    let torsoScale: Double
    let leftWrist: JointPoint?
    let rightWrist: JointPoint?
}

struct JointPoint: Sendable {
    let position: Vector2
    let confidence: Double
}

struct PoseSample: Sendable {
    let sessionID: UUID
    let sourceTime: TimeInterval
    let receivedAtMonotonic: TimeInterval
    let inferenceCompletedAt: TimeInterval
    let candidates: [PoseCandidate]
}
