import Foundation

public struct CalibrationMapper: Sendable {
    public private(set) var sourceRect: Rect2?
    public private(set) var mappingVersion = 0
    public var playableRect: Rect2
    public var minimumWidth = 0.20
    public var minimumHeight = 0.15

    public init(playableAspectRatio: Double = 9.0 / 16.0) {
        self.playableRect = Rect2(min: .zero, max: .init(x: 1, y: playableAspectRatio))
    }

    @discardableResult
    public mutating func calibrate(lowerLeft: Vector2, upperRight: Vector2) -> Bool {
        let candidate = Rect2(min: lowerLeft, max: upperRight)
        guard candidate.isPositive,
              candidate.width >= minimumWidth,
              candidate.height >= minimumHeight else { return false }
        sourceRect = candidate
        mappingVersion += 1
        return true
    }

    public func map(_ point: Vector2) -> (position: Vector2, isInside: Bool)? {
        guard let sourceRect else { return nil }
        let normalized = Vector2(
            x: (point.x - sourceRect.min.x) / sourceRect.width,
            y: (point.y - sourceRect.min.y) / sourceRect.height
        )
        let mapped = Vector2(
            x: playableRect.min.x + normalized.x * playableRect.width,
            y: playableRect.min.y + normalized.y * playableRect.height
        )
        return (playableRect.clamped(mapped), sourceRect.contains(point))
    }

    public mutating func invalidate() {
        sourceRect = nil
        mappingVersion += 1
    }
}
