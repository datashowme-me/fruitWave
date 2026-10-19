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
    public let roundID: UUID
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

public struct RunEpochGate: Sendable, Equatable {
    public private(set) var acceptedEpoch: UInt64

    public init(acceptedEpoch: UInt64 = 0) { self.acceptedEpoch = acceptedEpoch }

    public mutating func advance(to epoch: UInt64) {
        if epoch > acceptedEpoch { acceptedEpoch = epoch }
    }

    public func accepts(_ epoch: UInt64) -> Bool { epoch == acceptedEpoch }
}

/// Rejects duplicate or out-of-order results within one camera session and
/// Vision run. A new session or run starts an independent sequence domain.
public struct FrameSequenceGate: Sendable, Equatable {
    public private(set) var sessionID: UUID?
    public private(set) var runEpoch: UInt64?
    public private(set) var lastAcceptedSequence: UInt64?

    public init() {}

    public mutating func accepts(sessionID: UUID, runEpoch: UInt64, sequence: UInt64) -> Bool {
        guard self.sessionID == sessionID, self.runEpoch == runEpoch else {
            self.sessionID = sessionID
            self.runEpoch = runEpoch
            lastAcceptedSequence = sequence
            return true
        }
        guard let lastAcceptedSequence, sequence > lastAcceptedSequence else { return false }
        self.lastAcceptedSequence = sequence
        return true
    }

    public mutating func reset() {
        sessionID = nil
        runEpoch = nil
        lastAcceptedSequence = nil
    }
}

public struct PlayerIdentityCandidate: Sendable, Equatable {
    public let torsoCenter: Vector2
    public let torsoScale: Double
    public init(torsoCenter: Vector2, torsoScale: Double) {
        self.torsoCenter = torsoCenter
        self.torsoScale = torsoScale
    }
}

public struct SinglePlayerIdentityTracker: Sendable {
    public private(set) var playerSessionID: UUID?
    private var lastCenter: Vector2?
    private var lastScale: Double?

    public init() {}

    public mutating func lock(candidates: [PlayerIdentityCandidate]) -> Int? {
        guard candidates.count == 1, let candidate = candidates.first,
              candidate.torsoCenter.isFinite, candidate.torsoScale.isFinite,
              candidate.torsoScale > 0 else { return nil }
        playerSessionID = UUID()
        lastCenter = candidate.torsoCenter
        lastScale = candidate.torsoScale
        return 0
    }

    public mutating func track(candidates: [PlayerIdentityCandidate]) -> Int? {
        guard let lastCenter, let lastScale, playerSessionID != nil else { return nil }
        let matches = candidates.indices.filter { index in
            let candidate = candidates[index]
            let ratio = candidate.torsoScale / max(lastScale, 0.0001)
            return candidate.torsoCenter.isFinite && candidate.torsoScale.isFinite &&
                (candidate.torsoCenter - lastCenter).length <= 0.15 && ratio >= 0.70 && ratio <= 1.40
        }
        guard matches.count == 1, let index = matches.first else { return nil }
        self.lastCenter = candidates[index].torsoCenter
        self.lastScale = candidates[index].torsoScale
        return index
    }

    public mutating func reset() {
        playerSessionID = nil
        lastCenter = nil
        lastScale = nil
    }
}

public struct FrameLivenessWatchdog: Sendable, Equatable {
    public var timeout: TimeInterval
    public private(set) var lastFrameReceivedAt: TimeInterval?

    public init(timeout: TimeInterval = 0.5) { self.timeout = timeout }

    public mutating func reset() { lastFrameReceivedAt = nil }

    public mutating func recordFrame(receivedAt: TimeInterval) {
        guard receivedAt.isFinite,
              lastFrameReceivedAt.map({ receivedAt >= $0 }) ?? true else { return }
        lastFrameReceivedAt = receivedAt
    }

    public func isStale(at now: TimeInterval) -> Bool {
        guard let lastFrameReceivedAt, now.isFinite else { return false }
        return now - lastFrameReceivedAt >= timeout
    }
}
