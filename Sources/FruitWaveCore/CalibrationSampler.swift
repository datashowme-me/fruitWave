import Foundation

public struct CalibrationSampler: Sendable {
    public struct TimedPoint: Sendable, Equatable {
        public let time: TimeInterval
        public let point: Vector2
        public let isValid: Bool
        public init(time: TimeInterval, point: Vector2, isValid: Bool) {
            self.time = time; self.point = point; self.isValid = isValid
        }
    }

    // Keep a window longer than the required hold. With a 30 fps camera, a
    // window equal to the hold duration can evict the oldest frame before the
    // remaining samples span the full duration because frame cadence jitters.
    public var windowDuration: TimeInterval = 0.75
    public var minimumValidRatio = 0.70
    public var stableRadius = 0.045
    public var minimumStableRatio = 0.80
    public var minimumSampleCount = 4
    public var minimumCoveredDuration: TimeInterval = 0.45
    private var samples: [TimedPoint] = []

    public init() {}

    public mutating func append(_ sample: TimedPoint) {
        samples.append(sample)
        samples.removeAll { sample.time - $0.time > windowDuration }
    }

    public mutating func reset() { samples.removeAll(keepingCapacity: true) }

    public func stableMedian(at now: TimeInterval) -> Vector2? {
        let window = samples.filter { now - $0.time <= windowDuration }
        guard window.count >= minimumSampleCount,
              let firstTime = window.first?.time,
              let lastTime = window.last?.time,
              lastTime - firstTime >= minimumCoveredDuration else { return nil }
        let valid = window.filter { $0.isValid && $0.point.isFinite }
        guard Double(valid.count) / Double(window.count) >= minimumValidRatio else { return nil }
        let median = Vector2(x: medianOf(valid.map(\.point.x)), y: medianOf(valid.map(\.point.y)))
        let stableCount = valid.lazy.filter { ($0.point - median).length <= stableRadius }.count
        guard Double(stableCount) / Double(valid.count) >= minimumStableRatio else { return nil }
        return median
    }

    public func stabilityProgress(at now: TimeInterval) -> Double {
        let window = samples.filter { now - $0.time <= windowDuration }
        guard !window.isEmpty else { return 0 }
        let valid = window.filter { $0.isValid && $0.point.isFinite }
        guard !valid.isEmpty else { return 0 }

        let sampleProgress = min(1, Double(window.count) / Double(minimumSampleCount))
        let coveredDuration = max(0, (window.last?.time ?? now) - (window.first?.time ?? now))
        let durationProgress = min(1, coveredDuration / minimumCoveredDuration)
        let validRatio = Double(valid.count) / Double(window.count)
        let validProgress = min(1, validRatio / minimumValidRatio)

        let median = Vector2(x: medianOf(valid.map(\.point.x)), y: medianOf(valid.map(\.point.y)))
        let stableCount = valid.lazy.filter { ($0.point - median).length <= stableRadius }.count
        let stableRatio = Double(stableCount) / Double(valid.count)
        let stableProgress = min(1, stableRatio / minimumStableRatio)

        return max(0, min(sampleProgress, durationProgress, validProgress, stableProgress))
    }

    private func medianOf(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
