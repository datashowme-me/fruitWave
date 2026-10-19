import Foundation
import FruitWaveCore

struct PlayerTracker {
    private var tracker = SinglePlayerIdentityTracker()
    var playerSessionID: UUID? { tracker.playerSessionID }

    mutating func lock(candidates: [PoseCandidate]) -> PoseCandidate? {
        let identities = candidates.map { PlayerIdentityCandidate(torsoCenter: $0.torsoCenter, torsoScale: $0.torsoScale) }
        guard let index = tracker.lock(candidates: identities) else { return nil }
        return candidates[index]
    }

    mutating func track(candidates: [PoseCandidate]) -> PoseCandidate? {
        let identities = candidates.map { PlayerIdentityCandidate(torsoCenter: $0.torsoCenter, torsoScale: $0.torsoScale) }
        guard let index = tracker.track(candidates: identities) else { return nil }
        return candidates[index]
    }

    mutating func reset() {
        tracker.reset()
    }
}
