import CoreGraphics
import FruitWaveCore
import SceneKit
import simd

/// Pure geometry construction: lathe solids/halves and procedural rind/flesh
/// textures. No node state; every result is immutable and cacheable.
enum LatheGeometry {
    struct SweepResult {
        let rim: SCNGeometry
        /// All end caps merged into one geometry (share one material).
        let cap: SCNGeometry
    }

    /// Full 2π lathe of a profile around the Y axis.
    static func solid(profile: LatheProfile, arcSegments: Int = 40) -> SCNGeometry {
        sweep(profile: profile, thetaMin: 0, thetaMax: 2 * .pi, arcSegments: arcSegments, capAngles: []).rim
    }

    /// Half fruit: sweep over [-π/2, π/2] plus the flat circular cut face
    /// (two fans, both normal (-1, 0, 0)) — the flesh cap.
    static func half(profile: LatheProfile, arcSegments: Int = 20) -> SweepResult {
        sweep(profile: profile, thetaMin: -.pi / 2, thetaMax: .pi / 2, arcSegments: arcSegments, capAngles: [-.pi / 2, .pi / 2])
    }

    /// True equator-cut half: the profile arc above its widest plane, swept a
    /// full 2π (a dome), plus the full-disc cut face at that plane. Both
    /// halves of a sliced fruit use this geometry; the bottom half flips the
    /// node (eulerAngles.x = π), which mirrors the face texture the way a
    /// real cut would. `half` (axis-cut wedge) remains for special cases.
    /// Only open bottom-to-top profiles are split.
    static func split(profile: LatheProfile, arcSegments: Int = 40) -> SweepResult {
        let points = profile.points
        let count = points.count
        guard !profile.closed, count >= 4 else { return half(profile: profile) }

        // Cut at the profile's widest plane so the face matches real halves
        // (for the strawberry the cut lands near the crown, not the middle).
        let xMax = points.map(\.x).max() ?? 1
        var ySum: Float = 0
        var yCount = 0
        for point in points where abs(point.x - xMax) < 0.01 * max(xMax, 0.001) {
            ySum += point.y
            yCount += 1
        }
        let ySplit = yCount > 0 ? ySum / Float(yCount) : (points.map(\.y).max() ?? 0) / 2

        // Upper arc: consecutive points at/above the cut plane, with the
        // lower boundary crossing interpolated to land exactly on y = ySplit.
        // The arc ends at the top pole (x = 0) — the sweep itself closes the
        // dome, so no second interpolation is needed.
        var start = 0
        while start < count, points[start].y < ySplit { start += 1 }
        guard start < count else { return half(profile: profile) }
        var upper: [SIMD2<Float>] = []
        var cursor = start
        while cursor < count, points[cursor].y >= ySplit {
            upper.append(points[cursor])
            cursor += 1
        }
        if start > 0 {
            let a = points[start - 1]
            let b = points[start]
            let denominator = b.y - a.y
            let t = denominator == 0 ? 0.5 : (ySplit - a.y) / denominator
            upper.insert(SIMD2(a.x + (b.x - a.x) * t, ySplit), at: 0)
        }

        let subProfile = LatheProfile(points: upper, closed: false)
        let dome = sweep(profile: subProfile, thetaMin: 0, thetaMax: 2 * .pi, arcSegments: arcSegments, capAngles: []).rim
        let radius = (upper[0].x + upper[upper.count - 1].x) / 2
        return SweepResult(rim: dome, cap: discCap(radius: radius, y: ySplit, arcSegments: arcSegments))
    }

    /// Full disc at y = ySplit — the cut face. Normal faces down (−y); the
    /// flipped bottom half reverses it. UVs map the full square texture across
    /// the disc: u along the x axis, v along the z axis so the image top
    /// (v = 1) points at the camera-facing side of the tilted face.
    private static func discCap(radius: Float, y: Float, arcSegments: Int) -> SCNGeometry {
        var positions: [Float] = []
        var normals: [Float] = []
        var uvs: [Float] = []
        positions.reserveCapacity((arcSegments + 1) * 3)
        positions.append(contentsOf: [0, y, 0])
        normals.append(contentsOf: [0, -1, 0])
        uvs.append(contentsOf: [0.5, 0.5])
        for k in 0..<arcSegments {
            let phi = Float(k) / Float(arcSegments) * 2 * .pi
            let px = radius * cos(phi)
            let pz = radius * sin(phi)
            positions.append(contentsOf: [px, y, pz])
            normals.append(contentsOf: [0, -1, 0])
            uvs.append(contentsOf: [(px / radius + 1) / 2, (1 - pz / radius) / 2])
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(arcSegments * 3)
        for k in 0..<arcSegments {
            let next = UInt32(k + 1 == arcSegments ? 1 : k + 2)
            indices.append(contentsOf: [0, UInt32(k + 1), next])
        }
        indices = ensureWinding(positions: positions, indices: indices, outDirection: { _ in
            SIMD3(0, -1, 0)
        })
        return makeGeometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    /// Curved capsule (banana): a limited sweep with rind-colored end caps.
    static func curved(profile: LatheProfile, arc: Float = 0.96, arcSegments: Int = 24) -> SweepResult {
        sweep(profile: profile, thetaMin: -arc, thetaMax: arc, arcSegments: arcSegments, capAngles: [-arc, arc])
    }

    // MARK: - Sweep

    private static func sweep(
        profile: LatheProfile,
        thetaMin: Float,
        thetaMax: Float,
        arcSegments: Int,
        capAngles: [Float]
    ) -> SweepResult {
        let points = profile.points
        let rows = points.count
        let rings = arcSegments + 1

        var rimPositions: [Float] = []
        var rimNormals: [Float] = []
        var rimUVs: [Float] = []
        rimPositions.reserveCapacity(rings * rows * 3)
        rimNormals.reserveCapacity(rings * rows * 3)
        rimUVs.reserveCapacity(rings * rows * 2)

        // Profile-space 2D normals (outward from the fruit, +x side). Open
        // profiles use one-sided tangents at their ends — a wrapped tangent
        // would poison the seam row (the split dome's equator) with a normal
        // pointing the wrong way.
        var profileNormals: [SIMD2<Float>] = []
        profileNormals.reserveCapacity(rows)
        for j in 0..<rows {
            let tangent: SIMD2<Float>
            if profile.closed {
                tangent = points[(j + 1) % rows] - points[(j - 1 + rows) % rows]
            } else if j == 0 {
                tangent = points[1] - points[0]
            } else if j == rows - 1 {
                tangent = points[rows - 1] - points[rows - 2]
            } else {
                tangent = points[j + 1] - points[j - 1]
            }
            profileNormals.append(simd_normalize(SIMD2(tangent.y, -tangent.x)))
        }

        for i in 0..<rings {
            let theta = thetaMin + (thetaMax - thetaMin) * Float(i) / Float(arcSegments)
            let cosTheta = cos(theta)
            let sinTheta = sin(theta)
            for j in 0..<rows {
                let point = points[j]
                let normal = profileNormals[j]
                rimPositions.append(contentsOf: [point.x * cosTheta, point.y, point.x * sinTheta])
                rimNormals.append(contentsOf: [normal.x * cosTheta, normal.y, normal.x * sinTheta])
                rimUVs.append(contentsOf: [Float(i) / Float(arcSegments), Float(j) / Float(rows - 1)])
            }
        }

        var rimIndices: [UInt32] = []
        rimIndices.reserveCapacity(arcSegments * (profile.closed ? rows : rows - 1) * 6)
        for i in 0..<arcSegments {
            for j in 0..<(profile.closed ? rows : rows - 1) {
                let nextJ = (j + 1) % rows
                let a = UInt32(i * rows + j)
                let b = UInt32((i + 1) * rows + j)
                let c = UInt32((i + 1) * rows + nextJ)
                let d = UInt32(i * rows + nextJ)
                rimIndices.append(contentsOf: [a, b, c, a, c, d])
            }
        }
        rimIndices = ensureWinding(positions: rimPositions, indices: rimIndices, outDirection: { centroid in
            SIMD3(centroid.x, centroid.y, 0) - SIMD3(0, centroid.y, 0)
        })

        // Cap fans: one fan per end angle. For a profile touching the axis
        // both fans lie in the x = 0 plane and together form the full cut
        // face; for the banana's offset ring each fan closes one rounded end.
        var capPositions: [Float] = []
        var capNormals: [Float] = []
        var capUVs: [Float] = []
        var capIndices: [UInt32] = []
        let yMin = points.map(\.y).min() ?? -1
        let yMax = points.map(\.y).max() ?? 1
        let xMax = points.map(\.x).max() ?? 1
        let xMin = points.map(\.x).min() ?? 0
        let xCenter = (xMin + xMax) / 2
        let yMid = (yMin + yMax) / 2
        var base = 0

        for endAngle in capAngles {
            let alpha = abs(endAngle)
            let capNormal = SIMD3(-sin(alpha), 0, endAngle < 0 ? -cos(alpha) : cos(alpha))
            let cosTheta = cos(endAngle)
            let sinTheta = sin(endAngle)
            let center = SIMD3(xCenter * cosTheta, yMid, xCenter * sinTheta)

            capPositions.append(contentsOf: [center.x, center.y, center.z])
            capNormals.append(contentsOf: [capNormal.x, capNormal.y, capNormal.z])
            capUVs.append(contentsOf: [0.5, 0.5])
            let centerIndex = UInt32(base)
            base += 1

            var outline: [SIMD3<Float>] = []
            outline.reserveCapacity(rows)
            for j in 0..<rows {
                let point = points[j]
                let z = point.x * sinTheta
                outline.append(SIMD3(point.x * cosTheta, point.y, z))
                capPositions.append(contentsOf: [point.x * cosTheta, point.y, z])
                capNormals.append(contentsOf: [capNormal.x, capNormal.y, capNormal.z])
                let u = z / xMax * 0.5 + 0.5
                let v = (point.y - yMin) / (yMax - yMin)
                capUVs.append(contentsOf: [u, v])
            }
            let firstOutline = UInt32(base)
            base += rows

            let span = profile.closed ? rows : rows - 1
            var fanIndices: [UInt32] = []
            for k in 0..<span {
                let nextK = (k + 1) % rows
                fanIndices.append(contentsOf: [centerIndex, firstOutline + UInt32(k), firstOutline + UInt32(nextK)])
            }
            fanIndices = ensureWinding(positions: capPositions, indices: fanIndices, outDirection: { _ in capNormal })
            capIndices.append(contentsOf: fanIndices)
        }

        return SweepResult(
            rim: makeGeometry(positions: rimPositions, normals: rimNormals, uvs: rimUVs, indices: rimIndices),
            cap: makeGeometry(positions: capPositions, normals: capNormals, uvs: capUVs, indices: capIndices)
        )
    }

    /// Verifies triangle 0's geometric normal against the expected outward
    /// direction and flips every triangle if the strip was wound inside-out.
    private static func ensureWinding(
        positions: [Float],
        indices: [UInt32],
        outDirection: (SIMD3<Float>) -> SIMD3<Float>
    ) -> [UInt32] {
        guard indices.count >= 3 else { return indices }
        func vertex(_ index: UInt32) -> SIMD3<Float> {
            let base = Int(index) * 3
            return SIMD3(positions[base], positions[base + 1], positions[base + 2])
        }
        let a = vertex(indices[0])
        let b = vertex(indices[1])
        let c = vertex(indices[2])
        let geometricNormal = simd_cross(b - a, c - a)
        let centroid = (a + b + c) / 3
        if simd_dot(geometricNormal, outDirection(centroid)) < 0 {
            var flipped = indices
            for t in stride(from: 0, to: flipped.count, by: 3) {
                flipped.swapAt(t + 1, t + 2)
            }
            return flipped
        }
        return indices
    }

    private static func makeGeometry(
        positions: [Float],
        normals: [Float],
        uvs: [Float],
        indices: [UInt32]
    ) -> SCNGeometry {
        let positionData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let normalData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let sources = [
            SCNGeometrySource(
                data: positionData, semantic: .vertex, vectorCount: positions.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3
            ),
            SCNGeometrySource(
                data: normalData, semantic: .normal, vectorCount: normals.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3
            ),
            SCNGeometrySource(
                data: uvData, semantic: .texcoord, vectorCount: uvs.count / 2,
                usesFloatComponents: true, componentsPerVector: 2,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 2
            ),
        ]
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: indices.count / 3, bytesPerIndex: MemoryLayout<UInt32>.size
        )
        return SCNGeometry(sources: sources, elements: [element])
    }
}

/// Procedurally painted 256×256 rind and flesh textures (sRGB, y-up so
/// v = 0 is the fruit bottom). Cached per kind; never mutated after creation.
@MainActor
enum ProceduralTexture {
    private static let side = 256
    private static var rindCache: [FruitKind: CGImage] = [:]
    private static var fleshCache: [FruitKind: CGImage] = [:]

    static func rind(_ kind: FruitKind) -> CGImage {
        if let cached = rindCache[kind] { return cached }
        let image = drawRind(kind)
        rindCache[kind] = image
        return image
    }

    static func flesh(_ kind: FruitKind) -> CGImage {
        if let cached = fleshCache[kind] { return cached }
        let image = drawFlesh(kind)
        fleshCache[kind] = image
        return image
    }

    // MARK: - Rind

    private static func drawRind(_ kind: FruitKind) -> CGImage {
        let spec = FruitVisualData.spec(for: kind)
        let context = makeContext()!
        fillRect(context, spec.rind)
        switch kind {
        case .watermelon:
            // Wavy meridional bands, drawn at u and u±1 so the texture tiles
            // seamlessly on the lathe seam.
            var seed: UInt64 = 0x57_A7_E2_50
            for center in stride(from: Float(-0.7), through: Float(1.3), by: Float(0.22)) {
                stripe(context, centerFraction: center, color: RGB(r: 0.14, g: 0.62, b: 0.28), rng: &seed)
            }
        case .strawberry:
            var seed: UInt64 = 0x5EED_1234
            for row in 0..<7 {
                for column in 0..<6 {
                    let u = (Float(column) + (row % 2 == 0 ? 0.5 : 0)) / 6 + 1.0 / 12
                    let v = (Float(row) + 0.5) / 8 + 0.06
                    ellipse(context, centerX: u * Float(side), centerY: v * Float(side),
                            width: 5, height: 8, rotation: (seed & 1 == 0) ? 0.4 : -0.4,
                            color: RGB(r: 1.0, g: 0.92, b: 0.5), alpha: 0.9)
                    _ = random(rng: &seed)
                }
            }
        case .pineapple:
            strokeGrid(context, spacing: 30, color: RGB(r: 0.55, g: 0.38, b: 0.12), alpha: 0.5, width: 5)
        case .apple:
            var seed: UInt64 = 0x4AB1_E000
            for center in stride(from: Float(0.1), through: Float(0.9), by: Float(0.16)) {
                stripe(context, centerFraction: center, color: RGB(r: 1.0, g: 0.45, b: 0.40),
                       alpha: 0.3, width: 20, rng: &seed)
            }
        case .orange:
            dots(context, count: 420, radiusRange: 1.5...3.0,
                color: RGB(r: 0.92, g: 0.32, b: 0.0), alpha: 0.4, seed: 0x0A_AF_6E_E0)
        case .banana:
            axialGradient(context, atTop: true, length: 60, color: RGB(r: 0.35, g: 0.20, b: 0.08))
            axialGradient(context, atTop: false, length: 60, color: RGB(r: 0.35, g: 0.20, b: 0.08))
        case .kiwi:
            dots(context, count: 2400, radiusRange: 1.0...2.2,
                color: RGB(r: 0.30, g: 0.16, b: 0.07), alpha: 0.55, seed: 0x1_1D1_0000)
        case .peach:
            radialBlush(context, centerX: 160, centerY: 140, radius: 150,
                        color: RGB(r: 1.0, g: 0.66, b: 0.55), alpha: 0.45)
            strokeLine(context, from: (128, 64), to: (128, 204), width: 5,
                       color: RGB(r: 0.85, g: 0.30, b: 0.25), alpha: 0.25)
        case .mango:
            radialBlush(context, centerX: 174, centerY: 133, radius: 128,
                        color: RGB(r: 0.95, g: 0.25, b: 0.10), alpha: 0.4)
        case .lemon:
            dots(context, count: 300, radiusRange: 1.0...2.4,
                color: RGB(r: 1.0, g: 0.95, b: 0.5), alpha: 0.35, seed: 0xE3_0F_0000)
        case .grape:
            dots(context, count: 300, radiusRange: 1.0...2.2,
                color: RGB(r: 0.85, g: 0.70, b: 0.95), alpha: 0.3, seed: 0x6A_AE_0000)
            dots(context, count: 12, radiusRange: 6...12,
                color: RGB(r: 1.0, g: 1.0, b: 1.0), alpha: 0.12, seed: 0xB_1000_0000)
        case .dragonFruit:
            var row = 0
            for v in stride(from: Float(0.10), through: Float(0.90), by: Float(0.10)) {
                let offset = Float(row % 2 == 0 ? 0 : 0.09)
                for u in stride(from: Float(0.03) + offset, through: Float(1.03), by: Float(0.16)) {
                    triangle(context, centerX: u * Float(side), centerY: v * Float(side),
                             width: 13, height: 15, color: RGB(r: 0.15, g: 0.75, b: 0.35), alpha: 0.85)
                }
                row += 1
            }
        default:
            // Photo skins cover the remaining kinds; the flat fill is the
            // procedural fallback when the photo fails to load.
            break
        }
        return context.makeImage()!
    }

    // MARK: - Flesh

    private static func drawFlesh(_ kind: FruitKind) -> CGImage {
        let spec = FruitVisualData.spec(for: kind)
        let context = makeContext()!
        fillRect(context, spec.flesh)
        switch kind {
        case .watermelon:
            radialTint(context, centerX: 128, centerY: 128, radius: 96, color: RGB(r: 0.99, g: 0.42, b: 0.45))
            seedRing(context, radius: 44, count: 9, size: 6)
            seedRing(context, radius: 82, count: 12, size: 6)
        case .kiwi:
            radialTint(context, centerX: 128, centerY: 128, radius: 46, color: RGB(r: 0.95, g: 0.95, b: 0.85))
            seedRing(context, radius: 92, count: 24, size: 5)
        case .orange, .lemon:
            spokes(context, count: 8, color: RGB(r: 1.0, g: 0.97, b: 0.85), alpha: 0.6, width: 7)
            fillCircle(context, centerX: 128, centerY: 128, radius: 12, color: RGB(r: 1.0, g: 0.97, b: 0.85))
        case .apple:
            fillEllipse(context, centerX: 128, centerY: 128, width: 26, height: 40, rotation: 0.3,
                        color: RGB(r: 0.90, g: 0.78, b: 0.50))
            fillEllipse(context, centerX: 116, centerY: 118, width: 7, height: 12, rotation: -0.6,
                        color: RGB(r: 0.30, g: 0.16, b: 0.08))
            fillEllipse(context, centerX: 140, centerY: 138, width: 7, height: 12, rotation: 0.5,
                        color: RGB(r: 0.30, g: 0.16, b: 0.08))
        case .strawberry:
            radialTint(context, centerX: 128, centerY: 128, radius: 56, color: RGB(r: 1.0, g: 0.72, b: 0.72))
        case .pineapple:
            strokeGrid(context, spacing: 36, color: RGB(r: 0.85, g: 0.66, b: 0.10), alpha: 0.16, width: 4)
        case .banana:
            fillCircle(context, centerX: 128, centerY: 128, radius: 10, color: RGB(r: 0.90, g: 0.80, b: 0.40))
        case .peach:
            radialTint(context, centerX: 128, centerY: 128, radius: 58, color: RGB(r: 0.95, g: 0.55, b: 0.40))
        case .mango:
            fillEllipse(context, centerX: 128, centerY: 128, width: 22, height: 58, rotation: 0,
                        color: RGB(r: 0.95, g: 0.90, b: 0.60))
        case .grape:
            fillEllipse(context, centerX: 108, centerY: 132, width: 6, height: 9, rotation: 0.5, color: RGB(r: 0.40, g: 0.24, b: 0.12))
            fillEllipse(context, centerX: 150, centerY: 120, width: 6, height: 9, rotation: -0.4, color: RGB(r: 0.40, g: 0.24, b: 0.12))
        case .dragonFruit:
            dots(context, count: 130, radiusRange: 1.6...3.0,
                color: RGB(r: 0.10, g: 0.10, b: 0.10), alpha: 0.85, seed: 0xD2_A6_0F00)
        default:
            // Photo caps cover the remaining kinds; the flat fill is the
            // procedural fallback when the photo fails to load.
            break
        }
        return context.makeImage()!
    }

    // MARK: - Drawing helpers

    private static func makeContext() -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func cgColor(_ color: RGB, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: alpha)
    }

    private static func fillRect(_ context: CGContext, _ color: RGB) {
        context.setFillColor(cgColor(color))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }

    private static func fillCircle(_ context: CGContext, centerX: Float, centerY: Float, radius: Float, color: RGB) {
        context.setFillColor(cgColor(color))
        context.fillEllipse(in: CGRect(x: CGFloat(centerX - radius), y: CGFloat(centerY - radius),
                                       width: CGFloat(radius * 2), height: CGFloat(radius * 2)))
    }

    private static func fillEllipse(
        _ context: CGContext, centerX: Float, centerY: Float,
        width: Float, height: Float, rotation: Float, color: RGB
    ) {
        context.saveGState()
        context.translateBy(x: CGFloat(centerX), y: CGFloat(centerY))
        context.rotate(by: CGFloat(rotation))
        context.setFillColor(cgColor(color))
        context.fillEllipse(in: CGRect(x: -CGFloat(width / 2), y: -CGFloat(height / 2),
                                       width: CGFloat(width), height: CGFloat(height)))
        context.restoreGState()
    }

    private static func ellipse(
        _ context: CGContext, centerX: Float, centerY: Float,
        width: Float, height: Float, rotation: Float, color: RGB, alpha: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: CGFloat(centerX), y: CGFloat(centerY))
        context.rotate(by: CGFloat(rotation))
        context.setFillColor(cgColor(color, alpha: alpha))
        context.fillEllipse(in: CGRect(x: -CGFloat(width / 2), y: -CGFloat(height / 2),
                                       width: CGFloat(width), height: CGFloat(height)))
        context.restoreGState()
    }

    private static func strokeLine(
        _ context: CGContext, from: (Float, Float), to: (Float, Float),
        width: Float, color: RGB, alpha: CGFloat
    ) {
        context.setStrokeColor(cgColor(color, alpha: alpha))
        context.setLineWidth(CGFloat(width))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: CGFloat(from.0), y: CGFloat(from.1)))
        context.addLine(to: CGPoint(x: CGFloat(to.0), y: CGFloat(to.1)))
        context.strokePath()
    }

    private static func stripe(
        _ context: CGContext, centerFraction: Float, color: RGB,
        alpha: CGFloat = 1, width: Float = 34, rng: inout UInt64
    ) {
        let centerX = centerFraction * Float(side)
        let phase = random(rng: &rng) * .pi * 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: CGFloat(centerX - width / 2), y: -6))
        for step in 0...8 {
            let y = Float(step) / 8 * Float(side + 12)
            let wobble = sin(Float(step) * 1.7 + phase) * 7
            path.addLine(to: CGPoint(x: CGFloat(centerX - width / 2 + wobble), y: CGFloat(y)))
        }
        for step in stride(from: 8, through: 0, by: -1) {
            let y = Float(step) / 8 * Float(side + 12)
            let wobble = sin(Float(step) * 1.7 + phase) * 7
            path.addLine(to: CGPoint(x: CGFloat(centerX + width / 2 + wobble), y: CGFloat(y)))
        }
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(cgColor(color, alpha: alpha))
        context.fillPath()
    }

    private static func dots(
        _ context: CGContext, count: Int, radiusRange: ClosedRange<Float>,
        color: RGB, alpha: CGFloat, seed: UInt64
    ) {
        var rng = seed
        for _ in 0..<count {
            let x = random(rng: &rng) * Float(side)
            let y = random(rng: &rng) * Float(side)
            let radius = radiusRange.lowerBound + random(rng: &rng) * (radiusRange.upperBound - radiusRange.lowerBound)
            context.setFillColor(cgColor(color, alpha: alpha))
            context.fillEllipse(in: CGRect(x: CGFloat(x - radius), y: CGFloat(y - radius),
                                           width: CGFloat(radius * 2), height: CGFloat(radius * 2)))
        }
    }

    private static func strokeGrid(_ context: CGContext, spacing: Float, color: RGB, alpha: CGFloat, width: Float) {
        let slope = Float(tan(35 * Double.pi / 180))
        context.setStrokeColor(cgColor(color, alpha: alpha))
        context.setLineWidth(CGFloat(width))
        for k in stride(from: -20, through: 20, by: 1) {
            let x0 = Float(k) * spacing
            context.move(to: CGPoint(x: CGFloat(x0), y: -40))
            context.addLine(to: CGPoint(x: CGFloat(x0 + Float(side) * slope), y: CGFloat(Float(side) + 40)))
            context.move(to: CGPoint(x: CGFloat(x0), y: CGFloat(Float(side) + 40)))
            context.addLine(to: CGPoint(x: CGFloat(x0 + Float(side) * slope), y: -40))
        }
        context.strokePath()
    }

    private static func radialBlush(_ context: CGContext, centerX: Float, centerY: Float, radius: Float, color: RGB, alpha: CGFloat) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [cgColor(color, alpha: alpha), cgColor(color, alpha: 0)] as CFArray,
            locations: [0, 1]
        ) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: CGFloat(centerX), y: CGFloat(centerY)), startRadius: 0,
            endCenter: CGPoint(x: CGFloat(centerX), y: CGFloat(centerY)), endRadius: CGFloat(radius),
            options: [.drawsAfterEndLocation]
        )
    }

    private static func axialGradient(_ context: CGContext, atTop: Bool, length: Float, color: RGB) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [cgColor(color, alpha: 0), cgColor(color, alpha: 0.9)] as CFArray,
            locations: [0, 1]
        ) else { return }
        let start = CGPoint(x: 0, y: atTop ? CGFloat(Float(side) - length) : CGFloat(length))
        let end = CGPoint(x: 0, y: atTop ? CGFloat(Float(side)) : 0)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    private static func radialTint(_ context: CGContext, centerX: Float, centerY: Float, radius: Float, color: RGB) {
        radialBlush(context, centerX: centerX, centerY: centerY, radius: radius, color: color, alpha: 0.55)
    }

    private static func seedRing(_ context: CGContext, radius: Float, count: Int, size: Float) {
        for index in 0..<count {
            let angle = Float(index) / Float(count) * 2 * .pi
            let x = 128 + radius * cos(angle)
            let y = 128 + radius * sin(angle)
            fillEllipse(context, centerX: x, centerY: y, width: size, height: size * 1.5,
                        rotation: angle, color: RGB(r: 0.05, g: 0.03, b: 0.03))
        }
    }

    private static func spokes(_ context: CGContext, count: Int, color: RGB, alpha: CGFloat, width: Float) {
        for index in 0..<count {
            let angle = Float(index) / Float(count) * 2 * .pi
            strokeLine(context, from: (128 + 14 * cos(angle), 128 + 14 * sin(angle)),
                       to: (128 + 120 * cos(angle), 128 + 120 * sin(angle)),
                       width: width, color: color, alpha: alpha)
        }
    }

    private static func triangle(_ context: CGContext, centerX: Float, centerY: Float, width: Float, height: Float, color: RGB, alpha: CGFloat) {
        context.setFillColor(cgColor(color, alpha: alpha))
        context.move(to: CGPoint(x: CGFloat(centerX - width / 2), y: CGFloat(centerY + height / 2)))
        context.addLine(to: CGPoint(x: CGFloat(centerX + width / 2), y: CGFloat(centerY + height / 2)))
        context.addLine(to: CGPoint(x: CGFloat(centerX), y: CGFloat(centerY - height / 2)))
        context.closePath()
        context.fillPath()
    }

    /// Deterministic xorshift-style generator so textures are stable across runs.
    private static func random(rng: inout UInt64) -> Float {
        rng ^= rng << 13
        rng ^= rng >> 7
        rng ^= rng << 17
        return Float(rng % 1_000_000) / 1_000_000
    }
}
