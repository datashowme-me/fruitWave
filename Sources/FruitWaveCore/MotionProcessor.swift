import Foundation

public struct MotionProcessor: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var startSpeed = 1.2
        public var stopSpeed = 0.6
        public var jumpSpeed = 6.0
        public var maximumPointInterval = 0.100
        public var maximumResultAge = 0.150
        public var minimumConfidence = 0.5
        public init() {}
    }

    private struct Sample: Sendable { let hand: TrackedHand; let filtered: Vector2 }
    private var previous: Sample?
    private var filter: OneEuroFilter2D
    private var isSlashing = false
    public var configuration: Configuration

    public init(configuration: Configuration = .init(), filterConfiguration: OneEuroFilter2D.Configuration = .init()) {
        self.configuration = configuration
        self.filter = OneEuroFilter2D(configuration: filterConfiguration)
    }

    public mutating func reset() {
        previous = nil
        isSlashing = false
        filter.reset()
    }

    public mutating func process(_ hand: TrackedHand, sessionID: UUID, now: TimeInterval) -> SlashSegment? {
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
        if isSlashing {
            if speed < configuration.stopSpeed { isSlashing = false }
        } else if speed >= configuration.startSpeed {
            isSlashing = true
        }
        defer { self.previous = Sample(hand: hand, filtered: filtered) }
        guard isSlashing else { return nil }
        return SlashSegment(
            sessionID: sessionID,
            playerSessionID: hand.playerSessionID,
            mappingVersion: hand.mappingVersion,
            startTime: previous.hand.sampleTime,
            endTime: hand.sampleTime,
            startPosition: previous.filtered,
            endPosition: filtered,
            speed: speed
        )
    }
}
