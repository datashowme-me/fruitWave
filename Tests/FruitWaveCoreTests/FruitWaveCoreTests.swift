import Foundation
import Testing
@testable import FruitWaveCore

@Test func calibrationRejectsSmallAreaAndMapsPhysicalAspect() {
    var mapper = CalibrationMapper(playableAspectRatio: 9.0 / 16.0)
    let rejected = mapper.calibrate(lowerLeft: .init(x: 0.1, y: 0.1), upperRight: .init(x: 0.2, y: 0.2))
    #expect(!rejected)
    let accepted = mapper.calibrate(lowerLeft: .init(x: 0.2, y: 0.2), upperRight: .init(x: 0.8, y: 0.8))
    #expect(accepted)
    let result = mapper.map(.init(x: 0.5, y: 0.5))
    #expect(result?.isInside == true)
    #expect(abs((result?.position.x ?? 0) - 0.5) < 0.0001)
    #expect(abs((result?.position.y ?? 0) - 0.28125) < 0.0001)
}

@Test func motionProcessorBreaksAcrossMappingVersionsAndStartsAtThreshold() {
    let playerID = UUID()
    let sessionID = UUID()
    var processor = MotionProcessor()
    let first = TrackedHand(playerSessionID: playerID, handSide: .right, mappingVersion: 1, sampleTime: 1, receivedAt: 1, mappedPosition: .zero, confidence: 1)
    #expect(processor.process(first, sessionID: sessionID, now: 1) == nil)
    let fast = TrackedHand(playerSessionID: playerID, handSide: .right, mappingVersion: 1, sampleTime: 1.09, receivedAt: 1.09, mappedPosition: .init(x: 0.45, y: 0), confidence: 1)
    #expect(processor.process(fast, sessionID: sessionID, now: 1.09) != nil)
    let changed = TrackedHand(playerSessionID: playerID, handSide: .right, mappingVersion: 2, sampleTime: 1.14, receivedAt: 1.14, mappedPosition: .init(x: 0.5, y: 0), confidence: 1)
    #expect(processor.process(changed, sessionID: sessionID, now: 1.14) == nil)
}

@Test func staleOrJumpingSamplesNeverCreateSlash() {
    let playerID = UUID()
    let sessionID = UUID()
    var processor = MotionProcessor()
    let stale = TrackedHand(playerSessionID: playerID, handSide: .left, mappingVersion: 1, sampleTime: 0, receivedAt: 0, mappedPosition: .zero, confidence: 1)
    #expect(processor.process(stale, sessionID: sessionID, now: 1) == nil)
    let base = TrackedHand(playerSessionID: playerID, handSide: .left, mappingVersion: 1, sampleTime: 2, receivedAt: 2, mappedPosition: .zero, confidence: 1)
    _ = processor.process(base, sessionID: sessionID, now: 2)
    let jump = TrackedHand(playerSessionID: playerID, handSide: .left, mappingVersion: 1, sampleTime: 2.01, receivedAt: 2.01, mappedPosition: .init(x: 1, y: 1), confidence: 1)
    #expect(processor.process(jump, sessionID: sessionID, now: 2.01) == nil)
}

@Test func movingFruitCollisionIsIdempotent() {
    var engine = GameplayEngine()
    engine.start(at: 0)
    let fruit = Fruit(kind: .watermelon, spawnedAt: 0, position: .init(x: 0.5, y: 0.25), velocity: .zero)
    engine.tick(at: 0, spawn: { _ in fruit })
    let slash = SlashSegment(sessionID: UUID(), playerSessionID: UUID(), mappingVersion: 1, startTime: 1, endTime: 1.05, startPosition: .init(x: 0.3, y: 0.25), endPosition: .init(x: 0.7, y: 0.25), speed: 8)
    #expect(engine.apply(slash, gameTimeRange: 0...0.05).count == 1)
    #expect(engine.score == 10)
    #expect(engine.apply(slash, gameTimeRange: 0...0.05).isEmpty)
    #expect(engine.score == 10)
}

@Test func pauseDoesNotAdvanceGameClock() {
    var engine = GameplayEngine()
    engine.start(at: 10)
    engine.tick(at: 11)
    engine.pause()
    engine.tick(at: 50)
    #expect(engine.gameTime == 1)
    engine.resume(at: 50)
    engine.tick(at: 51)
    #expect(engine.gameTime == 2)
}

@Test func coordinatorRejectsIllegalTransitions() {
    var coordinator = GameCoordinator()
    let illegal = coordinator.transition(to: .playing)
    #expect(!illegal)
    let framing = coordinator.transition(to: .framing)
    #expect(framing)
    let calibration = coordinator.transition(to: .calibration)
    #expect(calibration)
    let ready = coordinator.transition(to: .ready)
    #expect(ready)
    let playing = coordinator.transition(to: .playing)
    #expect(playing)
    let paused = coordinator.transition(to: .paused, reason: .user)
    #expect(paused)
    #expect(coordinator.pauseReason == .user)
}
