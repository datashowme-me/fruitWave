import Foundation

public struct GameCoordinator: Sendable {
    public private(set) var state: GameState = .waitingForConnection
    public private(set) var pauseReason: PauseReason?

    public init() {}

    @discardableResult
    public mutating func transition(to target: GameState, reason: PauseReason? = nil) -> Bool {
        guard Self.allowed[state, default: []].contains(target) else { return false }
        state = target
        pauseReason = target == .paused ? reason : nil
        return true
    }

    private static let allowed: [GameState: Set<GameState>] = [
        .waitingForConnection: [.framing],
        .framing: [.calibration, .waitingForConnection],
        .calibration: [.ready, .framing, .waitingForConnection],
        .ready: [.playing, .paused, .calibration, .resuming],
        .playing: [.paused, .results],
        .paused: [.resuming, .calibration, .ready, .waitingForConnection],
        .resuming: [.playing, .paused],
        .results: [.ready, .waitingForConnection]
    ]
}
