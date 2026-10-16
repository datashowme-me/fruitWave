import Foundation

public struct OneEuroFilter2D: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var minCutoff: Double
        public var beta: Double
        public var derivativeCutoff: Double

        public init(minCutoff: Double = 1, beta: Double = 0, derivativeCutoff: Double = 1) {
            self.minCutoff = minCutoff
            self.beta = beta
            self.derivativeCutoff = derivativeCutoff
        }
    }

    private var previousRaw: Vector2?
    private var previousFiltered: Vector2?
    private var filteredDerivative = Vector2.zero
    private var previousTime: TimeInterval?
    public var configuration: Configuration

    public init(configuration: Configuration = .init()) { self.configuration = configuration }

    public mutating func reset() {
        previousRaw = nil
        previousFiltered = nil
        filteredDerivative = .zero
        previousTime = nil
    }

    public mutating func filter(_ point: Vector2, at time: TimeInterval) -> Vector2 {
        guard let previousTime, let previousRaw, let previousFiltered else {
            self.previousTime = time
            self.previousRaw = point
            self.previousFiltered = point
            return point
        }
        let dt = max(time - previousTime, 0.000_1)
        let derivative = (point - previousRaw) / dt
        let derivativeAlpha = alpha(cutoff: configuration.derivativeCutoff, dt: dt)
        filteredDerivative = lowPass(current: derivative, previous: filteredDerivative, alpha: derivativeAlpha)
        let adaptiveCutoff = configuration.minCutoff + configuration.beta * filteredDerivative.length
        let filtered = lowPass(current: point, previous: previousFiltered, alpha: alpha(cutoff: adaptiveCutoff, dt: dt))
        self.previousTime = time
        self.previousRaw = point
        self.previousFiltered = filtered
        return filtered
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * max(cutoff, 0.000_1))
        return 1 / (1 + tau / dt)
    }

    private func lowPass(current: Vector2, previous: Vector2, alpha: Double) -> Vector2 {
        current * alpha + previous * (1 - alpha)
    }
}
