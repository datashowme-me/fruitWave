import AVFoundation
import ImageIO
import FruitWaveCore

struct FramePacket: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let sourcePTS: CMTime
    /// Capture PTS converted onto ProcessInfo.systemUptime's monotonic basis.
    /// Falls back to `receivedAtMonotonic` when the session clock is unavailable.
    let capturedAtMonotonic: TimeInterval
    let receivedAtMonotonic: TimeInterval
    let orientation: CGImagePropertyOrientation
    let geometry: CaptureGeometry
    let sessionID: UUID
}

struct CaptureGeometry: Sendable, Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let orientationRawValue: UInt32
    let isVideoMirrored: Bool

    var orientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(rawValue: orientationRawValue) ?? .up
    }

    var orientedPixelSize: CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            CGSize(width: pixelHeight, height: pixelWidth)
        default:
            CGSize(width: pixelWidth, height: pixelHeight)
        }
    }
}

enum FrameDropReason: String, Sendable, Hashable {
    case frameWasLate
    case outOfBuffers
    case discontinuity
    case unknown
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
    let runEpoch: UInt64
    let sequence: UInt64
    let sourceTime: TimeInterval
    let capturedAtMonotonic: TimeInterval
    let receivedAtMonotonic: TimeInterval
    let inferenceStartedAt: TimeInterval
    let inferenceCompletedAt: TimeInterval
    let geometry: CaptureGeometry
    let candidates: [PoseCandidate]
}
