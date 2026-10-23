import Foundation

public enum FruitKind: String, Sendable, Codable, CaseIterable {
    case watermelon, strawberry, pineapple
    case apple, orange, banana, kiwi, peach
    case mango, lemon, grape, dragonFruit
    case pear, cherry, blueberry, plum
    case pomegranate, coconut, cantaloupe, persimmon
    /// Not a fruit: slicing it detonates and ends the round with no score.
    case bomb
}
public enum FruitState: String, Sendable, Codable { case active, sliced, expired }

public struct Fruit: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let kind: FruitKind
    public let spawnedAt: TimeInterval
    public var position: Vector2
    public var velocity: Vector2
    public let radius: Double
    public var state: FruitState

    public init(id: UUID = UUID(), kind: FruitKind, spawnedAt: TimeInterval, position: Vector2, velocity: Vector2, radius: Double = 0.055, state: FruitState = .active) {
        self.id = id
        self.kind = kind
        self.spawnedAt = spawnedAt
        self.position = position
        self.velocity = velocity
        self.radius = radius
        self.state = state
    }

    public func position(at gameTime: TimeInterval) -> Vector2 {
        position + velocity * (gameTime - spawnedAt)
    }
}

public struct HitEvent: Sendable, Equatable {
    public let fruitID: UUID
    public let contactTime: TimeInterval
    /// Blade contact point in mapped (screen-normalized) space.
    public let contactPosition: Vector2
    /// Unit blade direction at contact, same space as fruit positions.
    /// `.zero` when the segment was effectively stationary.
    public let slashDirection: Vector2
}

public struct GameplayEngine: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var duration: TimeInterval = 90
        public var spawnInterval: TimeInterval = 0.8
        public var maximumFruitCount = 6
        public var pointsPerFruit = 10
        public var bladeRadius = 0.005
        public var maximumSubstep: TimeInterval = 1.0 / 120.0
        public var expirationY = 0.64
        public init() {}
    }

    public private(set) var score = 0
    public private(set) var gameTime: TimeInterval = 0
    public private(set) var fruits: [Fruit] = []
    public var configuration: Configuration
    private var lastTick: TimeInterval?
    private var nextSpawnTime: TimeInterval = 0
    public private(set) var roundID = UUID()
    /// Set when a bomb is sliced; consumed by the host to end the round.
    public private(set) var hitBomb = false

    public init(configuration: Configuration = .init()) { self.configuration = configuration }

    public mutating func start(at monotonicTime: TimeInterval, roundID: UUID = UUID()) {
        self.roundID = roundID
        score = 0; gameTime = 0; fruits.removeAll(); lastTick = monotonicTime; nextSpawnTime = 0
        hitBomb = false
    }

    public mutating func resume(at monotonicTime: TimeInterval) { lastTick = monotonicTime }
    public mutating func pause() { lastTick = nil }

    public mutating func tick(at monotonicTime: TimeInterval, spawn: ((TimeInterval) -> Fruit)? = nil) {
        guard let lastTick else { return }
        // Keep the hot rendering/collision collection bounded. Sliced fruit
        // has already been handed to the scene as a hit event before this tick.
        fruits.removeAll { $0.state != .active }
        let dt = max(0, monotonicTime - lastTick)
        self.lastTick = monotonicTime
        gameTime = min(configuration.duration, gameTime + dt)
        if gameTime >= nextSpawnTime, fruits.lazy.filter({ $0.state == .active }).count < configuration.maximumFruitCount {
            if let fruit = spawn?(gameTime) { fruits.append(fruit) }
            nextSpawnTime = gameTime + configuration.spawnInterval
        }
        // Fruit positions are derived from spawn time so collision and rendering share one timeline.
        for index in fruits.indices where fruits[index].state == .active {
            if fruits[index].position(at: gameTime).y > configuration.expirationY {
                fruits[index].state = .expired
            }
        }
    }

    @discardableResult
    public mutating func apply(_ slash: SlashSegment, gameTimeRange: ClosedRange<TimeInterval>) -> [HitEvent] {
        guard slash.roundID == roundID,
              gameTimeRange.upperBound >= gameTimeRange.lowerBound else { return [] }
        let direction = (slash.endPosition - slash.startPosition).normalized
        var hits: [HitEvent] = []
        for index in fruits.indices where fruits[index].state == .active {
            if let contact = contact(slash: slash, fruit: fruits[index], gameTimeRange: gameTimeRange) {
                fruits[index].state = .sliced
                hits.append(.init(
                    fruitID: fruits[index].id,
                    contactTime: contact.time,
                    contactPosition: contact.position,
                    slashDirection: direction
                ))
                // Bombs detonate instead of scoring.
                if fruits[index].kind == .bomb {
                    hitBomb = true
                } else {
                    score += configuration.pointsPerFruit
                }
            }
        }
        hits.sort { $0.contactTime == $1.contactTime ? $0.fruitID.uuidString < $1.fruitID.uuidString : $0.contactTime < $1.contactTime }
        return hits
    }

    public var isFinished: Bool { gameTime >= configuration.duration }

    private func contact(slash: SlashSegment, fruit: Fruit, gameTimeRange: ClosedRange<TimeInterval>) -> (time: TimeInterval, position: Vector2)? {
        let duration = max(slash.endTime - slash.startTime, 0.000_1)
        let gameDuration = gameTimeRange.upperBound - gameTimeRange.lowerBound
        let steps = max(1, Int(ceil(gameDuration / configuration.maximumSubstep)))
        for index in 0...steps {
            let fraction = Double(index) / Double(steps)
            let hand = slash.startPosition.interpolated(to: slash.endPosition, fraction: fraction)
            let sampleGameTime = gameTimeRange.lowerBound + gameDuration * fraction
            let fruitCenter = fruit.position(at: sampleGameTime)
            if (hand - fruitCenter).length <= fruit.radius + configuration.bladeRadius {
                return (slash.startTime + duration * fraction, hand)
            }
        }
        return nil
    }
}

public struct GameClockHistory: Sendable {
    public struct Sample: Sendable, Equatable {
        public let monotonicTime: TimeInterval
        public let gameTime: TimeInterval
        public init(monotonicTime: TimeInterval, gameTime: TimeInterval) {
            self.monotonicTime = monotonicTime
            self.gameTime = gameTime
        }
    }

    public var retention: TimeInterval
    public private(set) var samples: [Sample] = []

    public init(retention: TimeInterval = 0.6) { self.retention = retention }

    public mutating func reset(monotonicTime: TimeInterval, gameTime: TimeInterval = 0) {
        samples = [.init(monotonicTime: monotonicTime, gameTime: gameTime)]
    }

    public mutating func record(monotonicTime: TimeInterval, gameTime: TimeInterval) {
        guard monotonicTime.isFinite, gameTime.isFinite,
              samples.last.map({ monotonicTime >= $0.monotonicTime }) ?? true else { return }
        if samples.last?.monotonicTime == monotonicTime {
            samples[samples.count - 1] = .init(monotonicTime: monotonicTime, gameTime: gameTime)
        } else {
            samples.append(.init(monotonicTime: monotonicTime, gameTime: gameTime))
        }
        let cutoff = monotonicTime - retention
        while samples.count > 2, samples[1].monotonicTime < cutoff { samples.removeFirst() }
    }

    public func gameTime(at monotonicTime: TimeInterval) -> TimeInterval? {
        guard let first = samples.first, let last = samples.last,
              monotonicTime >= first.monotonicTime, monotonicTime <= last.monotonicTime else { return nil }
        if monotonicTime == last.monotonicTime { return last.gameTime }
        for index in 1..<samples.count {
            let upper = samples[index]
            guard monotonicTime <= upper.monotonicTime else { continue }
            let lower = samples[index - 1]
            let duration = upper.monotonicTime - lower.monotonicTime
            guard duration > 0 else { return upper.gameTime }
            let fraction = (monotonicTime - lower.monotonicTime) / duration
            return lower.gameTime + (upper.gameTime - lower.gameTime) * fraction
        }
        return nil
    }

    public func gameTimeRange(from start: TimeInterval, to end: TimeInterval) -> ClosedRange<TimeInterval>? {
        guard let mappedStart = gameTime(at: start), let mappedEnd = gameTime(at: end),
              mappedEnd >= mappedStart else { return nil }
        return mappedStart...mappedEnd
    }
}
