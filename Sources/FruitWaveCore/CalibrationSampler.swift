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

    public var windowDuration: TimeInterval = 0.5
    public var minimumValidRatio = 0.8
    public var stableRadius = 0.03
    public var minimumStableRatio = 0.9
    private var samples: [TimedPoint] = []

    public init() {}

    public mutating func append(_ sample: TimedPoint) {
        samples.append(sample)
        samples.removeAll { sample.time - $0.time > windowDuration }
    }

    public mutating func reset() { samples.removeAll(keepingCapacity: true) }

    public func stableMedian(at now: TimeInterval) -> Vector2? {
        let window = samples.filter { now - $0.time <= windowDuration }
        guard !window.isEmpty else { return nil }
        let valid = window.filter { $0.isValid && $0.point.isFinite }
        guard Double(valid.count) / Double(window.count) >= minimumValidRatio else { return nil }
        let median = Vector2(x: medianOf(valid.map(\.point.x)), y: medianOf(valid.map(\.point.y)))
        let stableCount = valid.lazy.filter { ($0.point - median).length <= stableRadius }.count
        guard Double(stableCount) / Double(valid.count) >= minimumStableRatio else { return nil }
        return median
    }

    private func medianOf(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
