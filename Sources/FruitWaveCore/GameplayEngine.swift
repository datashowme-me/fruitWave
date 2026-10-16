import Foundation

public enum FruitKind: String, Sendable, Codable, CaseIterable { case watermelon, strawberry, pineapple }
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
}

public struct GameplayEngine: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var duration: TimeInterval = 90
        public var spawnInterval: TimeInterval = 0.8
        public var maximumFruitCount = 6
        public var pointsPerFruit = 10
        public var bladeRadius = 0.005
        public var maximumSubstep: TimeInterval = 1.0 / 120.0
        public init() {}
    }

    public private(set) var score = 0
    public private(set) var gameTime: TimeInterval = 0
    public private(set) var fruits: [Fruit] = []
    public var configuration: Configuration
    private var lastTick: TimeInterval?
    private var nextSpawnTime: TimeInterval = 0

    public init(configuration: Configuration = .init()) { self.configuration = configuration }

    public mutating func start(at monotonicTime: TimeInterval) {
        score = 0; gameTime = 0; fruits.removeAll(); lastTick = monotonicTime; nextSpawnTime = 0
    }

    public mutating func resume(at monotonicTime: TimeInterval) { lastTick = monotonicTime }
    public mutating func pause() { lastTick = nil }

    public mutating func tick(at monotonicTime: TimeInterval, spawn: ((TimeInterval) -> Fruit)? = nil) {
        guard let lastTick else { return }
        let dt = max(0, monotonicTime - lastTick)
        self.lastTick = monotonicTime
        gameTime = min(configuration.duration, gameTime + dt)
        if gameTime >= nextSpawnTime, fruits.lazy.filter({ $0.state == .active }).count < configuration.maximumFruitCount {
            if let fruit = spawn?(gameTime) { fruits.append(fruit) }
            nextSpawnTime = gameTime + configuration.spawnInterval
        }
        // Fruit positions are derived from spawn time so collision and rendering share one timeline.
        for index in fruits.indices where fruits[index].state == .active {
            if fruits[index].position(at: gameTime).y > 0.72 {
                fruits[index].state = .expired
            }
        }
    }

    @discardableResult
    public mutating func apply(_ slash: SlashSegment, gameTimeRange: ClosedRange<TimeInterval>) -> [HitEvent] {
        guard gameTimeRange.upperBound >= gameTimeRange.lowerBound else { return [] }
        var hits: [HitEvent] = []
        for index in fruits.indices where fruits[index].state == .active {
            if let contact = contactTime(slash: slash, fruit: fruits[index], gameTimeRange: gameTimeRange) {
                fruits[index].state = .sliced
                hits.append(.init(fruitID: fruits[index].id, contactTime: contact))
            }
        }
        hits.sort { $0.contactTime == $1.contactTime ? $0.fruitID.uuidString < $1.fruitID.uuidString : $0.contactTime < $1.contactTime }
        score += hits.count * configuration.pointsPerFruit
        return hits
    }

    public var isFinished: Bool { gameTime >= configuration.duration }

    private func contactTime(slash: SlashSegment, fruit: Fruit, gameTimeRange: ClosedRange<TimeInterval>) -> TimeInterval? {
        let duration = max(slash.endTime - slash.startTime, 0.000_1)
        let gameDuration = gameTimeRange.upperBound - gameTimeRange.lowerBound
        let steps = max(1, Int(ceil(gameDuration / configuration.maximumSubstep)))
        for index in 0...steps {
            let fraction = Double(index) / Double(steps)
            let hand = slash.startPosition.interpolated(to: slash.endPosition, fraction: fraction)
            let sampleGameTime = gameTimeRange.lowerBound + gameDuration * fraction
            let fruitCenter = fruit.position(at: sampleGameTime)
            if (hand - fruitCenter).length <= fruit.radius + configuration.bladeRadius {
                return slash.startTime + duration * fraction
            }
        }
        return nil
    }
}
