import FruitWaveCore
import simd

/// A color in linear sRGB, 0...1 per channel (ported from the old
/// FruitVisualNode tables; SceneKit consumes Float directly).
struct RGB: Equatable, Hashable, Sendable {
    var r: Float
    var g: Float
    var b: Float
}

/// 2D silhouette of a rotationally symmetric fruit: x = radius at height y,
/// sampled bottom (y = -1) to top (y = 1), x ≥ 0. Points feed the lathe
/// generator in FruitGeometry. A `closed` profile (e.g. the banana's offset
/// ring) wraps the triangle strip at the seam.
struct LatheProfile: Sendable {
    var points: [SIMD2<Float>]
    var closed: Bool = false
}

enum SpinAxis: Sendable { case y, z }

/// Static decoration attached to a fruit body; positions are in profile units
/// (y up, body radius ≈ 1) and scale with the fruit node.
enum AttachmentSpec: Sendable {
    case leaf(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>, color: RGB)
    case crown(position: SIMD3<Float>)
    case stem(position: SIMD3<Float>)
    case tip(position: SIMD3<Float>, color: RGB)

    var position: SIMD3<Float> {
        switch self {
        case .leaf(let position, _, _, _), .crown(let position), .stem(let position), .tip(let position, _):
            return position
        }
    }
}

struct FruitVisualSpec: Sendable {
    var kind: FruitKind
    var rind: RGB
    var flesh: RGB
    var roughness: Float
    /// nil for the banana and the grape cluster, which are built from
    /// special-case geometry instead of a plain lathe.
    var profile: LatheProfile?
    var attachments: [AttachmentSpec]
    var spinAxis: SpinAxis
    /// false for banana/grape: their slice animation is special-cased.
    var slicesIntoHalves: Bool
}

enum FruitVisualData {
    static func spec(for kind: FruitKind) -> FruitVisualSpec {
        switch kind {
        case .watermelon:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.05, g: 0.40, b: 0.16), flesh: RGB(r: 0.98, g: 0.18, b: 0.30),
                            roughness: 0.20, profile: circleProfile(), attachments: [], spinAxis: .y, slicesIntoHalves: true)
        case .strawberry:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.80, g: 0.03, b: 0.10), flesh: RGB(r: 1.0, g: 0.24, b: 0.32),
                            roughness: 0.30, profile: strawberryProfile(),
                            attachments: [.crown(position: SIMD3(0, 1.0, 0))], spinAxis: .y, slicesIntoHalves: true)
        case .pineapple:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.97, g: 0.72, b: 0.06), flesh: RGB(r: 1.0, g: 0.84, b: 0.22),
                            roughness: 0.45, profile: pineappleProfile(),
                            attachments: [.crown(position: SIMD3(0, 1.0, 0))], spinAxis: .y, slicesIntoHalves: true)
        case .apple:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.55, g: 0.02, b: 0.05), flesh: RGB(r: 1.0, g: 0.92, b: 0.68),
                            roughness: 0.25, profile: circleProfile(),
                            attachments: [
                                .stem(position: SIMD3(0, 1.0, 0)),
                                .leaf(position: SIMD3(0.30, 1.05, 0), rotation: SIMD3(0, 0, 0.7),
                                      scale: SIMD3(0.5, 0.18, 0.05), color: RGB(r: 0.16, g: 0.52, b: 0.20)),
                            ], spinAxis: .y, slicesIntoHalves: true)
        case .orange:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.97, g: 0.46, b: 0.02), flesh: RGB(r: 1.0, g: 0.58, b: 0.06),
                            roughness: 0.35, profile: circleProfile(), attachments: [], spinAxis: .y, slicesIntoHalves: true)
        case .banana:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.97, g: 0.87, b: 0.28), flesh: RGB(r: 1.0, g: 0.94, b: 0.55),
                            roughness: 0.30, profile: nil,
                            attachments: [
                                // Arc endpoints in the sweep plane (θ = ±0.96):
                                // (Rc·cosθ, 0, Rc·sinθ) ≈ (0.49, 0, ±0.70).
                                .tip(position: SIMD3(0.49, 0, 0.70), color: RGB(r: 0.35, g: 0.20, b: 0.08)),
                                .tip(position: SIMD3(0.49, 0, -0.70), color: RGB(r: 0.35, g: 0.20, b: 0.08)),
                            ], spinAxis: .z, slicesIntoHalves: false)
        case .kiwi:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.30, g: 0.14, b: 0.05), flesh: RGB(r: 0.50, g: 0.82, b: 0.20),
                            roughness: 0.60, profile: ellipseProfile(rx: 0.82, ry: 1.0), attachments: [],
                            spinAxis: .y, slicesIntoHalves: true)
        case .peach:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.97, g: 0.55, b: 0.18), flesh: RGB(r: 1.0, g: 0.76, b: 0.52),
                            roughness: 0.50, profile: peachProfile(),
                            attachments: [
                                .leaf(position: SIMD3(0.25, 1.0, 0), rotation: SIMD3(0, 0, 0.7),
                                      scale: SIMD3(0.45, 0.16, 0.05), color: RGB(r: 0.16, g: 0.52, b: 0.20)),
                            ], spinAxis: .y, slicesIntoHalves: true)
        case .mango:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.98, g: 0.60, b: 0.16), flesh: RGB(r: 1.0, g: 0.82, b: 0.28),
                            roughness: 0.25, profile: ellipseProfile(rx: 0.82, ry: 0.62),
                            attachments: [
                                .leaf(position: SIMD3(0.20, 0.62, 0), rotation: SIMD3(0, 0, 0.7),
                                      scale: SIMD3(0.45, 0.16, 0.05), color: RGB(r: 0.16, g: 0.52, b: 0.20)),
                            ], spinAxis: .y, slicesIntoHalves: true)
        case .lemon:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.97, g: 0.78, b: 0.02), flesh: RGB(r: 1.0, g: 0.94, b: 0.46),
                            roughness: 0.20, profile: ellipseProfile(rx: 0.86, ry: 0.60),
                            attachments: [
                                .tip(position: SIMD3(0, 0.60, 0), color: RGB(r: 0.98, g: 0.84, b: 0.06)),
                                .tip(position: SIMD3(0, -0.60, 0), color: RGB(r: 0.98, g: 0.84, b: 0.06)),
                            ], spinAxis: .y, slicesIntoHalves: true)
        case .grape:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.38, g: 0.12, b: 0.46), flesh: RGB(r: 0.72, g: 0.88, b: 0.52),
                            roughness: 0.35, profile: nil, attachments: [], spinAxis: .y, slicesIntoHalves: false)
        case .dragonFruit:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.86, g: 0.12, b: 0.42), flesh: RGB(r: 0.96, g: 0.96, b: 0.94),
                            roughness: 0.25, profile: ellipseProfile(rx: 0.92, ry: 0.88), attachments: [],
                            spinAxis: .y, slicesIntoHalves: true)
        case .pear:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.72, g: 0.70, b: 0.10), flesh: RGB(r: 0.97, g: 0.93, b: 0.66),
                            roughness: 0.30, profile: pearProfile(),
                            attachments: [.stem(position: SIMD3(0, 1.0, 0))], spinAxis: .y, slicesIntoHalves: true)
        case .cherry:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.62, g: 0.02, b: 0.06), flesh: RGB(r: 0.88, g: 0.10, b: 0.16),
                            roughness: 0.25, profile: circleProfile(),
                            attachments: [.stem(position: SIMD3(0, 1.0, 0))], spinAxis: .y, slicesIntoHalves: true)
        case .blueberry:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.10, g: 0.08, b: 0.38), flesh: RGB(r: 0.58, g: 0.66, b: 0.40),
                            roughness: 0.40, profile: circleProfile(), attachments: [], spinAxis: .y, slicesIntoHalves: true)
        case .plum:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.34, g: 0.05, b: 0.26), flesh: RGB(r: 0.96, g: 0.78, b: 0.22),
                            roughness: 0.30, profile: ellipseProfile(rx: 0.95, ry: 1.0), attachments: [],
                            spinAxis: .y, slicesIntoHalves: true)
        case .pomegranate:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.74, g: 0.07, b: 0.10), flesh: RGB(r: 0.86, g: 0.14, b: 0.18),
                            roughness: 0.35, profile: circleProfile(),
                            attachments: [.crown(position: SIMD3(0, 1.0, 0))], spinAxis: .y, slicesIntoHalves: true)
        case .coconut:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.42, g: 0.28, b: 0.15), flesh: RGB(r: 0.97, g: 0.96, b: 0.91),
                            roughness: 0.60, profile: ellipseProfile(rx: 0.90, ry: 0.95), attachments: [],
                            spinAxis: .y, slicesIntoHalves: true)
        case .cantaloupe:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.80, g: 0.64, b: 0.36), flesh: RGB(r: 1.0, g: 0.60, b: 0.20),
                            roughness: 0.50, profile: circleProfile(), attachments: [], spinAxis: .y, slicesIntoHalves: true)
        case .persimmon:
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.94, g: 0.32, b: 0.03), flesh: RGB(r: 1.0, g: 0.56, b: 0.12),
                            roughness: 0.30, profile: ellipseProfile(rx: 0.88, ry: 0.85),
                            attachments: [
                                .stem(position: SIMD3(0, 0.85, 0)),
                                .leaf(position: SIMD3(0.25, 0.92, 0), rotation: SIMD3(0, 0, 0.7),
                                      scale: SIMD3(0.45, 0.16, 0.05), color: RGB(r: 0.16, g: 0.52, b: 0.20)),
                            ], spinAxis: .y, slicesIntoHalves: true)
        case .bomb:
            // Classic cartoon bomb: glossy black body, lit fuse. The fuse and
            // its spark are built in FruitStage3D's assembleBody.
            FruitVisualSpec(kind: kind, rind: RGB(r: 0.10, g: 0.10, b: 0.13), flesh: RGB(r: 0.95, g: 0.55, b: 0.15),
                            roughness: 0.30, profile: circleProfile(), attachments: [],
                            spinAxis: .y, slicesIntoHalves: false)
        }
    }

    /// Semicircle: (sin φ, -cos φ) for φ ∈ [0, π].
    static func circleProfile(samples: Int = 24) -> LatheProfile {
        LatheProfile(points: (0...samples).map { index in
            let phi = Float(index) / Float(samples) * .pi
            return SIMD2(sin(phi), -cos(phi))
        })
    }

    /// Ellipse with semi-axes (rx, ry): y ∈ [-ry, ry], x = rx·sqrt(1-(y/ry)²).
    static func ellipseProfile(rx: Float, ry: Float, samples: Int = 24) -> LatheProfile {
        LatheProfile(points: (0...samples).map { index in
            let phi = Float(index) / Float(samples) * .pi
            return SIMD2(rx * sin(phi), -ry * cos(phi))
        })
    }

    /// Rounded base, widest around y ≈ 0.3, tapering to the calyx point.
    static func strawberryProfile() -> LatheProfile {
        let pairs: [(Float, Float)] = [
            (-1.00, 0.40), (-0.92, 0.54), (-0.80, 0.66), (-0.64, 0.76),
            (-0.44, 0.84), (-0.22, 0.88), (0.02, 0.89), (0.28, 0.86),
            (0.52, 0.76), (0.70, 0.62), (0.84, 0.44), (0.92, 0.26),
            (0.97, 0.12), (1.00, 0.02),
        ]
        return LatheProfile(points: pairs.map { SIMD2($0.1, $0.0) })
    }

    /// Round body with a dimpled top and a suggestion of a crease.
    static func peachProfile() -> LatheProfile {
        let pairs: [(Float, Float)] = [
            (-1.00, 0.50), (-0.84, 0.74), (-0.62, 0.92), (-0.36, 1.04),
            (-0.08, 1.10), (0.20, 1.10), (0.48, 1.00), (0.70, 0.80),
            (0.84, 0.56), (0.92, 0.32), (1.00, 0.08),
        ]
        return LatheProfile(points: pairs.map { SIMD2($0.1, $0.0) })
    }

    /// Cylindrical body with a rounded dome.
    static func pineappleProfile() -> LatheProfile {
        let pairs: [(Float, Float)] = [
            (-1.00, 0.56), (-0.80, 0.64), (-0.50, 0.70), (-0.15, 0.72),
            (0.15, 0.72), (0.40, 0.66), (0.62, 0.54), (0.78, 0.38),
            (0.90, 0.20), (1.00, 0.03),
        ]
        return LatheProfile(points: pairs.map { SIMD2($0.1, $0.0) })
    }

    /// Pear silhouette: narrow neck, wide bottom-heavy base.
    static func pearProfile() -> LatheProfile {
        let pairs: [(Float, Float)] = [
            (-1.00, 0.42), (-0.90, 0.64), (-0.75, 0.84), (-0.55, 0.96),
            (-0.30, 1.00), (-0.05, 0.96), (0.20, 0.86), (0.45, 0.70),
            (0.65, 0.53), (0.82, 0.38), (0.94, 0.27), (1.00, 0.23),
        ]
        return LatheProfile(points: pairs.map { SIMD2($0.1, $0.0) })
    }

    /// The banana is a lathe of an off-axis ring profile: a circle of radius
    /// `berry` centered at (center, 0), swept over a limited arc around Y —
    /// i.e. a curved capsule. See FruitGeometry.sweep.
    static func bananaProfile() -> LatheProfile {
        let center: Float = 0.85
        let berry: Float = 0.30
        let samples = 20
        return LatheProfile(
            points: (0..<samples).map { index in
                let psi = Float(index) / Float(samples) * 2 * .pi
                return SIMD2(center + berry * cos(psi), berry * sin(psi))
            },
            closed: true
        )
    }
}
