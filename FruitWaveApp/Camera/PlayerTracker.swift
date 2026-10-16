import Foundation
import FruitWaveCore

struct PlayerTracker {
    private(set) var playerSessionID: UUID?
    private var lastCenter: Vector2?
    private var lastScale: Double?

    mutating func lock(candidates: [PoseCandidate]) -> PoseCandidate? {
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        playerSessionID = UUID()
        lastCenter = candidate.torsoCenter
        lastScale = candidate.torsoScale
        return candidate
    }

    mutating func track(candidates: [PoseCandidate]) -> PoseCandidate? {
        guard let lastCenter, let lastScale, playerSessionID != nil else { return nil }
        let matches = candidates.filter {
            ($0.torsoCenter - lastCenter).length <= 0.15 &&
            $0.torsoScale / max(lastScale, 0.0001) >= 0.7 &&
            $0.torsoScale / max(lastScale, 0.0001) <= 1.4
        }
        guard matches.count == 1, let candidate = matches.first else { return nil }
        self.lastCenter = candidate.torsoCenter
        self.lastScale = candidate.torsoScale
        return candidate
    }

    mutating func reset() {
        playerSessionID = nil
        lastCenter = nil
        lastScale = nil
    }
}
