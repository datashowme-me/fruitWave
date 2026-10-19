import Foundation

public struct MotionProcessor: Sendable {
    public struct Configuration: Sendable, Equatable {
        // Tuned for a ~24–30 fps Continuity Camera stream. The lower start
        // threshold catches a deliberate wrist swing one frame earlier while
        // hysteresis still prevents stationary jitter from becoming a slash.
        // Lower than the old defaults so a casual flick of the wrist already
        // counts as a slash; still well above the One Euro filtered noise floor.
        public var startSpeed = 0.72
        public var stopSpeed = 0.30
        public var jumpSpeed = 6.0
        public var maximumPointInterval = 0.100
        public var maximumResultAge = 0.120
        public var minimumConfidence = 0.42
        public init() {}
    }

    private struct Sample: Sendable { let hand: TrackedHand; let filtered: Vector2 }
    private var previous: Sample?
    private var filter: OneEuroFilter2D
    private var isSlashing = false
    public var configuration: Configuration

    public init(
        configuration: Configuration = .init(),
        filterConfiguration: OneEuroFilter2D.Configuration = .init(
            minCutoff: 2.2,
            beta: 0.9,
            derivativeCutoff: 1.5
        )
    ) {
        self.configuration = configuration
        self.filter = OneEuroFilter2D(configuration: filterConfiguration)
    }

    public mutating func reset() {
        previous = nil
        isSlashing = false
        filter.reset()
    }

    public mutating func process(_ hand: TrackedHand, sessionID: UUID, roundID: UUID = UUID(), now: TimeInterval) -> SlashSegment? {
        guard hand.isValid,
              hand.confidence >= configuration.minimumConfidence,
              hand.mappedPosition.isFinite,
              now - hand.receivedAt <= configuration.maximumResultAge else {
            reset()
            return nil
        }
        guard let previous else {
            self.previous = Sample(hand: hand, filtered: filter.filter(hand.mappedPosition, at: hand.sampleTime))
            return nil
        }
        let dt = hand.sampleTime - previous.hand.sampleTime
        guard dt > 0,
              dt <= configuration.maximumPointInterval,
              hand.playerSessionID == previous.hand.playerSessionID,
              hand.mappingVersion == previous.hand.mappingVersion else {
            reset()
            self.previous = Sample(hand: hand, filtered: filter.filter(hand.mappedPosition, at: hand.sampleTime))
            return nil
        }
        let rawSpeed = (hand.mappedPosition - previous.hand.mappedPosition).length / dt
        guard rawSpeed <= configuration.jumpSpeed else { reset(); return nil }
        let filtered = filter.filter(hand.mappedPosition, at: hand.sampleTime)
        let speed = (filtered - previous.filtered).length / dt
        // Use a conservative fraction of raw velocity only for starting the
        // gesture. This removes a frame of One Euro filter lag on a clean
        // swing while filtered velocity still controls stop hysteresis and
        // the segment endpoints used for collision.
        let activationSpeed = max(speed, rawSpeed * 0.85)
        if isSlashing {
            if speed < configuration.stopSpeed { isSlashing = false }
        } else if activationSpeed >= configuration.startSpeed {
            isSlashing = true
        }
        defer { self.previous = Sample(hand: hand, filtered: filtered) }
        guard isSlashing else { return nil }
        return SlashSegment(
            sessionID: sessionID,
            roundID: roundID,
            playerSessionID: hand.playerSessionID,
            mappingVersion: hand.mappingVersion,
            startTime: previous.hand.sampleTime,
            endTime: hand.sampleTime,
            // Collision follows the newest measured wrist positions. The
            // filter is retained for gesture hysteresis, but no longer makes
            // the visible blade trail behind the player's hand.
            startPosition: previous.hand.mappedPosition,
            endPosition: hand.mappedPosition,
            speed: activationSpeed
        )
    }
}
