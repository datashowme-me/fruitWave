import CoreGraphics
import Foundation
import FruitWaveCore
import ImageIO

/// Photos cut from the design-doc reference images
/// (Resources/FruitCapTextures/{skin,cap}_<kind>.png):
/// - skin = whole-fruit photo (lighting flattened), wrapped on the lathe body
/// - cap  = cut-face photo, shown on the sliced halves' flesh disc
/// A missing image falls back to the procedural texture at the call site.
/// Loaded once per kind — textures are immutable and shared by every node.
@MainActor
enum FruitTexture {
    private static var skinCache: [FruitKind: CGImage?] = [:]
    private static var capCache: [FruitKind: CGImage?] = [:]

    static func skin(_ kind: FruitKind) -> CGImage? {
        load(kind, prefix: "skin_", cache: &skinCache)
    }

    static func cap(_ kind: FruitKind) -> CGImage? {
        load(kind, prefix: "cap_", cache: &capCache)
    }

    private static func load(_ kind: FruitKind, prefix: String, cache: inout [FruitKind: CGImage?]) -> CGImage? {
        if let cached = cache[kind] { return cached }
        let name = "\(prefix)\(kind.rawValue)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            cache[kind] = nil
            return nil
        }
        cache[kind] = image
        return image
    }
}
