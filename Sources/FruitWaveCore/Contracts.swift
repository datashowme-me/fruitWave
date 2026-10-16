import Foundation

public enum HandSide: String, Sendable, Codable, CaseIterable { case left, right }

public enum InvalidHandReason: String, Sendable, Codable {
    case lowConfidence, nonFinite, stale, timeRegression, jump, outsideCalibration, identityUncertain
}

public struct TrackedHand: Sendable, Equatable {
    public let playerSessionID: UUID
    public let handSide: HandSide
    public let mappingVersion: Int
    public let sampleTime: TimeInterval
    public let receivedAt: TimeInterval
    public let mappedPosition: Vector2
    public let confidence: Double
    public let isValid: Bool
    public let invalidReason: InvalidHandReason?

    public init(
        playerSessionID: UUID,
        handSide: HandSide,
        mappingVersion: Int,
        sampleTime: TimeInterval,
        receivedAt: TimeInterval,
        mappedPosition: Vector2,
        confidence: Double,
        isValid: Bool = true,
        invalidReason: InvalidHandReason? = nil
    ) {
        self.playerSessionID = playerSessionID
        self.handSide = handSide
        self.mappingVersion = mappingVersion
        self.sampleTime = sampleTime
        self.receivedAt = receivedAt
        self.mappedPosition = mappedPosition
        self.confidence = confidence
        self.isValid = isValid
        self.invalidReason = invalidReason
    }
}

public struct SlashSegment: Sendable, Equatable {
    public let sessionID: UUID
    public let playerSessionID: UUID
    public let mappingVersion: Int
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let startPosition: Vector2
    public let endPosition: Vector2
    public let speed: Double
}

public enum GameState: String, Sendable, Codable, CaseIterable {
    case waitingForConnection, framing, calibration, ready, playing, paused, resuming, results
}

public enum CameraState: Sendable, Equatable {
    case idle, authorizing, selecting, configuring, streaming
    case interrupted(String), failed(String)
}

public enum PauseReason: String, Sendable, Codable {
    case user, cameraInterrupted, handUnavailable, identityUncertain, mappingChanged
}
