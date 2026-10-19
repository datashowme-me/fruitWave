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

@Test func calibrationRequiresEnoughSamplesAcrossTheHoldDuration() {
    var sampler = CalibrationSampler()
    let point = Vector2(x: 0.3, y: 0.4)
    for time in [0.0, 0.12, 0.24] {
        sampler.append(.init(time: time, point: point, isValid: true))
    }
    #expect(sampler.stableMedian(at: 0.24) == nil)
    #expect(sampler.stabilityProgress(at: 0.24) < 1)

    sampler.append(.init(time: 0.36, point: point, isValid: true))
    #expect(sampler.stableMedian(at: 0.36) == nil)
    sampler.append(.init(time: 0.5, point: point, isValid: true))
    #expect(sampler.stableMedian(at: 0.5) == point)
    #expect(sampler.stabilityProgress(at: 0.5) == 1)
}

@Test func calibrationRejectsMovingOrMostlyInvalidSamples() {
    var moving = CalibrationSampler()
    for (index, time) in [0.0, 0.12, 0.24, 0.36, 0.48].enumerated() {
        moving.append(.init(
            time: time,
            point: .init(x: 0.1 + Double(index) * 0.08, y: 0.2),
            isValid: true
        ))
    }
    #expect(moving.stableMedian(at: 0.48) == nil)
    #expect(moving.stabilityProgress(at: 0.48) < 1)

    var unreliable = CalibrationSampler()
    for (index, time) in [0.0, 0.12, 0.24, 0.36, 0.48].enumerated() {
        unreliable.append(.init(
            time: time,
            point: .init(x: 0.3, y: 0.4),
            isValid: index >= 3
        ))
    }
    #expect(unreliable.stableMedian(at: 0.48) == nil)
    #expect(unreliable.stabilityProgress(at: 0.48) < 1)
}

@Test func calibrationAcceptsRealisticThirtyFPSJitterAndOneWeakFrame() {
    var sampler = CalibrationSampler()
    let center = Vector2(x: 0.3, y: 0.4)

    for index in 0..<18 {
        let cadenceJitter = index.isMultiple(of: 4) ? 0.003 : 0
        let time = Double(index) / 30.0 + cadenceJitter
        let pointJitter = Double((index % 5) - 2) * 0.004
        sampler.append(.init(
            time: time,
            point: .init(x: center.x + pointJitter, y: center.y - pointJitter / 2),
            isValid: index != 8
        ))
    }

    let now = 17.0 / 30.0
    #expect(sampler.stableMedian(at: now) != nil)
    #expect(sampler.stabilityProgress(at: now) == 1)
}

@Test func calibrationMapperClampsOutsidePointsWithoutMarkingThemInside() {
    var mapper = CalibrationMapper()
    let accepted = mapper.calibrate(lowerLeft: .init(x: 0.2, y: 0.2), upperRight: .init(x: 0.8, y: 0.8))
    #expect(accepted)

    let outside = mapper.map(.init(x: 0.95, y: 0.95))
    #expect(outside?.isInside == false)
    #expect(outside?.position.x == mapper.playableRect.max.x)
    #expect(outside?.position.y == mapper.playableRect.max.y)
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

@Test func inferenceLatencyMakesAnOtherwiseRecentSampleStale() {
    let playerID = UUID()
    let sessionID = UUID()
    var processor = MotionProcessor()
    let delayed = TrackedHand(
        playerSessionID: playerID,
        handSide: .right,
        mappingVersion: 1,
        sampleTime: 10,
        receivedAt: 10,
        mappedPosition: .init(x: 0.5, y: 0.25),
        confidence: 1
    )
    #expect(processor.process(delayed, sessionID: sessionID, now: 10.3) == nil)
}

@Test func motionProcessorRejectsCalibrationOnlyConfidence() {
    let playerID = UUID()
    let sessionID = UUID()
    var processor = MotionProcessor()
    let first = TrackedHand(
        playerSessionID: playerID,
        handSide: .right,
        mappingVersion: 1,
        sampleTime: 1,
        receivedAt: 1,
        mappedPosition: .zero,
        confidence: 0.4
    )
    let fast = TrackedHand(
        playerSessionID: playerID,
        handSide: .right,
        mappingVersion: 1,
        sampleTime: 1.05,
        receivedAt: 1.05,
        mappedPosition: .init(x: 0.4, y: 0),
        confidence: 0.4
    )
    #expect(processor.process(first, sessionID: sessionID, now: 1) == nil)
    #expect(processor.process(fast, sessionID: sessionID, now: 1.05) == nil)
}

@Test func motionProcessorToleratesARecoverableFrameGap() {
    let playerID = UUID()
    let sessionID = UUID()
    var processor = MotionProcessor()
    let first = TrackedHand(playerSessionID: playerID, handSide: .right, mappingVersion: 1, sampleTime: 1, receivedAt: 1, mappedPosition: .zero, confidence: 1)
    _ = processor.process(first, sessionID: sessionID, now: 1)
    let next = TrackedHand(playerSessionID: playerID, handSide: .right, mappingVersion: 1, sampleTime: 1.09, receivedAt: 1.09, mappedPosition: .init(x: 0.45, y: 0), confidence: 1)
    #expect(processor.process(next, sessionID: sessionID, now: 1.09) != nil)
}

@Test func responsiveMotionStartsOnTheFirstCleanSwingFrame() {
    let playerID = UUID()
    let sessionID = UUID()
    let roundID = UUID()
    var processor = MotionProcessor()
    let first = TrackedHand(
        playerSessionID: playerID,
        handSide: .right,
        mappingVersion: 1,
        sampleTime: 1,
        receivedAt: 1,
        mappedPosition: .init(x: 0.25, y: 0.25),
        confidence: 0.9
    )
    _ = processor.process(first, sessionID: sessionID, roundID: roundID, now: 1)
    let swing = TrackedHand(
        playerSessionID: playerID,
        handSide: .right,
        mappingVersion: 1,
        sampleTime: 1.05,
        receivedAt: 1.05,
        mappedPosition: .init(x: 0.30, y: 0.25),
        confidence: 0.9
    )
    #expect(processor.process(swing, sessionID: sessionID, roundID: roundID, now: 1.05) != nil)
}

@Test func commonFruitRosterIsAvailable() {
    #expect(Set(FruitKind.allCases) == Set([
        .watermelon, .strawberry, .pineapple, .apple,
        .orange, .banana, .kiwi, .peach,
        .mango, .lemon, .grape, .dragonFruit,
        .pear, .cherry, .blueberry, .plum,
        .pomegranate, .coconut, .cantaloupe, .persimmon
    ]))
}

@Test func gameplayRejectsSlashFromAnotherRound() {
    var engine = GameplayEngine()
    engine.start(at: 0, roundID: UUID())
    let fruit = Fruit(kind: .watermelon, spawnedAt: 0, position: .init(x: 0.5, y: 0.25), velocity: .zero)
    engine.tick(at: 0, spawn: { _ in fruit })
    let slash = SlashSegment(sessionID: UUID(), roundID: UUID(), playerSessionID: UUID(), mappingVersion: 1, startTime: 0, endTime: 0.05, startPosition: .init(x: 0.3, y: 0.25), endPosition: .init(x: 0.7, y: 0.25), speed: 8)
    #expect(engine.apply(slash, gameTimeRange: 0...0.05).isEmpty)
    #expect(engine.score == 0)
}

@Test func gameClockHistoryInterpolatesAndRejectsExpiredSamples() {
    var history = GameClockHistory(retention: 0.5)
    history.reset(monotonicTime: 10, gameTime: 2)
    history.record(monotonicTime: 10.1, gameTime: 2.1)
    #expect(abs((history.gameTime(at: 10.05) ?? 0) - 2.05) < 0.0001)
    #expect(history.gameTimeRange(from: 10.02, to: 10.08) != nil)
    #expect(history.gameTime(at: 9.9) == nil)
    #expect(history.gameTime(at: 10.2) == nil)

    for index in 2...12 {
        history.record(monotonicTime: 10 + Double(index) * 0.1, gameTime: 2 + Double(index) * 0.1)
    }
    #expect(history.samples.count <= 7)
    #expect(history.gameTime(at: 10.1) == nil)
}

@Test func runEpochGateRejectsEveryEarlierPipelineRun() {
    var gate = RunEpochGate()
    #expect(gate.accepts(0))
    gate.advance(to: 1)
    #expect(!gate.accepts(0))
    #expect(gate.accepts(1))
    gate.advance(to: 4)
    #expect(!gate.accepts(1))
    #expect(!gate.accepts(3))
    #expect(gate.accepts(4))
    gate.advance(to: 2)
    #expect(gate.acceptedEpoch == 4)
}

@Test func frameSequenceGateRejectsDuplicatesAndOutOfOrderResults() {
    let session = UUID()
    var gate = FrameSequenceGate()

    let first = gate.accepts(sessionID: session, runEpoch: 2, sequence: 10)
    let newer = gate.accepts(sessionID: session, runEpoch: 2, sequence: 12)
    let duplicate = gate.accepts(sessionID: session, runEpoch: 2, sequence: 12)
    let outOfOrder = gate.accepts(sessionID: session, runEpoch: 2, sequence: 11)
    #expect(first)
    #expect(newer)
    #expect(!duplicate)
    #expect(!outOfOrder)
    #expect(gate.lastAcceptedSequence == 12)
}

@Test func frameSequenceGateSeparatesVisionRunsAndCameraSessions() {
    let firstSession = UUID()
    let secondSession = UUID()
    var gate = FrameSequenceGate()

    let initialRun = gate.accepts(sessionID: firstSession, runEpoch: 1, sequence: 100)
    let nextRun = gate.accepts(sessionID: firstSession, runEpoch: 2, sequence: 1)
    let duplicate = gate.accepts(sessionID: firstSession, runEpoch: 2, sequence: 1)
    let nextSession = gate.accepts(sessionID: secondSession, runEpoch: 2, sequence: 1)
    #expect(initialRun)
    #expect(nextRun)
    #expect(!duplicate)
    #expect(nextSession)

    gate.reset()
    let afterReset = gate.accepts(sessionID: firstSession, runEpoch: 1, sequence: 1)
    #expect(afterReset)
}

@Test func singlePlayerTrackerRequiresOneUnambiguousMatchWithinPRDThresholds() {
    var tracker = SinglePlayerIdentityTracker()
    let initial = PlayerIdentityCandidate(torsoCenter: .init(x: 0.5, y: 0.5), torsoScale: 0.2)
    #expect(tracker.lock(candidates: []) == nil)
    #expect(tracker.lock(candidates: [initial, initial]) == nil)
    #expect(tracker.lock(candidates: [initial]) == 0)

    let valid = PlayerIdentityCandidate(torsoCenter: .init(x: 0.64, y: 0.5), torsoScale: 0.14)
    #expect(tracker.track(candidates: [valid]) == 0)

    let matchingA = PlayerIdentityCandidate(torsoCenter: .init(x: 0.63, y: 0.5), torsoScale: 0.15)
    let matchingB = PlayerIdentityCandidate(torsoCenter: .init(x: 0.65, y: 0.5), torsoScale: 0.16)
    #expect(tracker.track(candidates: [matchingA, matchingB]) == nil)

    let tooFar = PlayerIdentityCandidate(torsoCenter: .init(x: 0.9, y: 0.5), torsoScale: 0.14)
    #expect(tracker.track(candidates: [tooFar]) == nil)
}

@Test func frameLivenessExpiresAtHalfSecondWithoutFrames() {
    var watchdog = FrameLivenessWatchdog()
    #expect(!watchdog.isStale(at: 100))
    watchdog.recordFrame(receivedAt: 100)
    #expect(!watchdog.isStale(at: 100.499))
    #expect(watchdog.isStale(at: 100.5))
    watchdog.recordFrame(receivedAt: 100.4)
    #expect(!watchdog.isStale(at: 100.899))
    watchdog.recordFrame(receivedAt: 99)
    #expect(watchdog.lastFrameReceivedAt == 100.4)
    watchdog.reset()
    #expect(!watchdog.isStale(at: 200))
}

@Test func completeGameAndChangePlayerStateFlowIsLegal() {
    var coordinator = GameCoordinator()
    var succeeded = coordinator.transition(to: .framing); #expect(succeeded)
    succeeded = coordinator.transition(to: .calibration); #expect(succeeded)
    succeeded = coordinator.transition(to: .ready); #expect(succeeded)
    succeeded = coordinator.transition(to: .resuming); #expect(succeeded)
    succeeded = coordinator.transition(to: .playing); #expect(succeeded)
    succeeded = coordinator.transition(to: .paused, reason: .cameraInterrupted); #expect(succeeded)
    succeeded = coordinator.transition(to: .resuming); #expect(succeeded)
    succeeded = coordinator.transition(to: .playing); #expect(succeeded)
    succeeded = coordinator.transition(to: .results); #expect(succeeded)
    succeeded = coordinator.transition(to: .ready); #expect(succeeded)
    succeeded = coordinator.transition(to: .calibration); #expect(succeeded)
    succeeded = coordinator.transition(to: .framing); #expect(succeeded)
}

@Test func movingFruitCollisionIsIdempotent() {
    var engine = GameplayEngine()
    engine.start(at: 0)
    let fruit = Fruit(kind: .watermelon, spawnedAt: 0, position: .init(x: 0.5, y: 0.25), velocity: .zero)
    engine.tick(at: 0, spawn: { _ in fruit })
    let slash = SlashSegment(sessionID: UUID(), roundID: engine.roundID, playerSessionID: UUID(), mappingVersion: 1, startTime: 1, endTime: 1.05, startPosition: .init(x: 0.3, y: 0.25), endPosition: .init(x: 0.7, y: 0.25), speed: 8)
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

@Test func gameplayPrunesInactiveFruitOnTheNextTick() {
    var engine = GameplayEngine()
    engine.start(at: 0)
    let fruit = Fruit(kind: .watermelon, spawnedAt: 0, position: .init(x: 0.5, y: 0.25), velocity: .zero)
    engine.tick(at: 0, spawn: { _ in fruit })
    let slash = SlashSegment(sessionID: UUID(), roundID: engine.roundID, playerSessionID: UUID(), mappingVersion: 1, startTime: 0, endTime: 0.05, startPosition: .init(x: 0.3, y: 0.25), endPosition: .init(x: 0.7, y: 0.25), speed: 8)
    #expect(engine.apply(slash, gameTimeRange: 0...0.05).count == 1)
    engine.tick(at: 0.1)
    #expect(engine.fruits.isEmpty)
}

@Test func gameplayStressRemainsBoundedAcrossOneHundredRounds() {
    var largestFruitCollection = 0
    var totalHits = 0

    for round in 0..<100 {
        var engine = GameplayEngine()
        let start = Double(round) * 100
        engine.start(at: start)

        for frame in 0...5_400 {
            let now = start + Double(frame) / 60
            engine.tick(at: now) { gameTime in
                Fruit(
                    kind: FruitKind.allCases[(frame / 48) % FruitKind.allCases.count],
                    spawnedAt: gameTime,
                    position: .init(x: 0.5, y: -0.06),
                    velocity: .init(x: 0, y: 0.2)
                )
            }
            largestFruitCollection = max(largestFruitCollection, engine.fruits.count)

            if frame.isMultiple(of: 15), let fruit = engine.fruits.first(where: { $0.state == .active }) {
                let center = fruit.position(at: engine.gameTime)
                let slash = SlashSegment(
                    sessionID: UUID(),
                    roundID: engine.roundID,
                    playerSessionID: UUID(),
                    mappingVersion: 1,
                    startTime: now - 0.05,
                    endTime: now,
                    startPosition: .init(x: center.x - 0.1, y: center.y),
                    endPosition: .init(x: center.x + 0.1, y: center.y),
                    speed: 4
                )
                totalHits += engine.apply(
                    slash,
                    gameTimeRange: max(0, engine.gameTime - 0.05)...engine.gameTime
                ).count
            }
        }

        #expect(engine.isFinished)
        #expect(engine.fruits.count <= engine.configuration.maximumFruitCount)
    }

    #expect(largestFruitCollection <= 6)
    #expect(totalHits > 10_000)
}

@Test func motionStressHandlesLongRunsAndBadSamples() {
    var processor = MotionProcessor()
    let playerID = UUID()
    let sessionID = UUID()
    var time: TimeInterval = 0
    var slashCount = 0

    for index in 0..<200_000 {
        time += index.isMultiple(of: 997) ? 0.22 : 1.0 / 60.0
        let phase = Double(index) * 0.11
        var point = Vector2(
            x: 0.5 + sin(phase) * 0.35,
            y: 0.28 + cos(phase * 0.7) * 0.18
        )
        if index.isMultiple(of: 7_919) { point = .init(x: .nan, y: 0) }
        let confidence = index.isMultiple(of: 389) ? 0.2 : 0.95
        let hand = TrackedHand(
            playerSessionID: playerID,
            handSide: .right,
            mappingVersion: 1 + index / 50_000,
            sampleTime: time,
            receivedAt: time,
            mappedPosition: point,
            confidence: confidence
        )
        let processingDelay = index.isMultiple(of: 1_237) ? 0.3 : 0.02
        if let slash = processor.process(hand, sessionID: sessionID, now: time + processingDelay) {
            #expect(slash.startPosition.isFinite)
            #expect(slash.endPosition.isFinite)
            slashCount += 1
        }
    }

    #expect(slashCount > 100_000)
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
