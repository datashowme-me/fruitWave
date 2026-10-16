import Foundation

public struct Vector2: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(x: 0, y: 0)
    public static func + (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    public static func - (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public static func * (lhs: Self, rhs: Double) -> Self { .init(x: lhs.x * rhs, y: lhs.y * rhs) }
    public static func / (lhs: Self, rhs: Double) -> Self { .init(x: lhs.x / rhs, y: lhs.y / rhs) }
    public var length: Double { hypot(x, y) }
    public var isFinite: Bool { x.isFinite && y.isFinite }

    public func interpolated(to other: Self, fraction: Double) -> Self {
        self + (other - self) * fraction
    }
}

public struct Rect2: Sendable, Equatable, Codable {
    public var min: Vector2
    public var max: Vector2

    public init(min: Vector2, max: Vector2) {
        self.min = min
        self.max = max
    }

    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }
    public var isPositive: Bool { width > 0 && height > 0 }
    public func contains(_ point: Vector2) -> Bool {
        point.x >= min.x && point.x <= max.x && point.y >= min.y && point.y <= max.y
    }

    public func clamped(_ point: Vector2) -> Vector2 {
        .init(x: Swift.max(min.x, Swift.min(max.x, point.x)),
              y: Swift.max(min.y, Swift.min(max.y, point.y)))
    }
}

public enum Geometry {
    public static func distanceFromOrigin(toSegmentFrom a: Vector2, to b: Vector2) -> Double {
        let ab = b - a
        let denominator = ab.x * ab.x + ab.y * ab.y
        guard denominator > 0 else { return a.length }
        let t = Swift.max(0, Swift.min(1, -(a.x * ab.x + a.y * ab.y) / denominator))
        return (a + ab * t).length
    }
}
