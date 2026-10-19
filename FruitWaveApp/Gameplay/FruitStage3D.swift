import CoreGraphics
import FruitWaveCore
import Metal
import OSLog
import SceneKit
import UIKit

private extension SCNVector3 {
    /// CGFloat-friendly memberwise init; computed positions/radii are
    /// CGFloat and the C-struct init only accepts Float.
    init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        self.init(x: Float(x), y: Float(y), z: Float(z))
    }

    init(_ v: SIMD3<Float>) {
        self.init(x: v.x, y: v.y, z: v.z)
    }
}

/// SceneKit fruit stage: orthographic camera, lit 3D fruits, slice halves,
/// juice particles, combo counting, sound, camera shake — and the frame
/// driver that keeps the game clock and HUD cursor running. The frame driver
/// is a main-thread CADisplayLink (the SceneKit renderer delegate fires on a
/// background render queue, which traps against MainActor state). The hand
/// cursor, slash trails, impact ring and combo label live in the 2D
/// `GameHUDScene`, layered over this view via a transparent SKView.
@MainActor
final class FruitStage3D: NSObject {
    private static let logger = Logger(subsystem: "com.example.FruitWave", category: "Stage")
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let size: CGSize
    private let hud: GameHUDScene
    private let baseCameraPosition: SCNVector3

    var onTick: ((TimeInterval) -> Void)?
    var soundEnabled = true {
        didSet {
            // Turning sound back on doubles as an immediate output check,
            // instead of making the player wait until the next successful hit.
            if soundEnabled, !oldValue { soundEffects.playPreview() }
        }
    }
    var reduceMotion = false {
        didSet {
            guard oldValue != reduceMotion else { return }
            // Particle system emission rates bake in reduceMotion; rebuild.
            juiceSystems.removeAll()
            juiceCursor.removeAll()
        }
    }

    // MARK: - Pools

    private final class FruitNode3D: SCNNode {
        var kind: FruitKind = .watermelon
        var radius: CGFloat = 24
    }

    /// Slice half container. `recycled` guards against double-pooling when
    /// both the SCNAction completion and the watchdog fire.
    private final class SlicePieceNode: SCNNode {
        var recycled = false
    }

    private var fruitNodes: [UUID: FruitNode3D] = [:]
    private var fruitPool: [FruitNode3D] = []
    private var slicePool: [SlicePieceNode] = []
    private var juiceNodePool: [SCNNode] = []

    private let soundEffects = SoundEffects()
    private var comboCount = 0
    private var lastHitGameTime: TimeInterval?

    // MARK: - Shared caches (immutable once built)

    private var rindMaterials: [FruitKind: SCNMaterial] = [:]
    private var fleshMaterials: [FruitKind: SCNMaterial] = [:]
    private var attachmentMaterials: [RGB: SCNMaterial] = [:]
    private var solidGeometries: [FruitKind: SCNGeometry] = [:]
    private var splitGeometries: [FruitKind: LatheGeometry.SweepResult] = [:]
    private let bananaSweep: LatheGeometry.SweepResult
    private let grapeBerrySolid: SCNGeometry
    private let grapeBerrySplit: LatheGeometry.SweepResult
    private var juiceSystems: [FruitKind: [SCNParticleSystem]] = [:]
    private var juiceCursor: [FruitKind: Int] = [:]

    // Shared attachment geometries; per-node scale/rotation/color via
    // materials. Sizes are in profile units (fruit body radius ≈ 1).
    private let leafGeometry = SCNSphere(radius: 1)
    private let stemGeometry = SCNCylinder(radius: 0.07, height: 0.4)
    private let tipGeometry = SCNSphere(radius: 0.18)

    init(size: CGSize, hud: GameHUDScene) {
        self.size = size
        self.hud = hud
        self.baseCameraPosition = SCNVector3(size.width / 2, size.height / 2, 600)
        bananaSweep = LatheGeometry.curved(profile: FruitVisualData.bananaProfile())
        let circle = FruitVisualData.circleProfile()
        grapeBerrySolid = LatheGeometry.solid(profile: circle)
        grapeBerrySplit = LatheGeometry.split(profile: circle)
        super.init()
        configureScene()
    }

    // MARK: - Scene setup

    private func configureScene() {
        scene.background.contents = CGColor(srgbRed: 0.025, green: 0.04, blue: 0.085, alpha: 1)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        // Same square play space as the 2D scenePoint mapping: height/2 units
        // of world space fill the screen, anchored to the width.
        camera.orthographicScale = size.height / 2
        camera.zNear = 100
        camera.zFar = 2000
        cameraNode.camera = camera
        cameraNode.position = baseCameraPosition
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 950
        keyLight.castsShadow = false
        let keyLightNode = SCNNode()
        keyLightNode.light = keyLight
        keyLightNode.eulerAngles = SCNVector3(-0.9, -0.5, 0)
        scene.rootNode.addChildNode(keyLightNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 240
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Image-based lighting: a procedural studio cube map gives glossy
        // rinds (apple, grape, lemon) photographic reflections instead of the
        // flat look of pure analytic lights. Kept below 1 so reflections
        // read as sheen, not a wet/oily film.
        scene.lightingEnvironment.contents = Self.studioFaces
        scene.lightingEnvironment.intensity = 0.5
    }

    /// Bright ceiling, dark floor, neutral walls. Built once.
    private static let studioFaces: [CGImage] = {
        let side = 128
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func face(top: CGFloat, bottom: CGFloat) -> CGImage {
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            let colors = [
                CGColor(srgbRed: top, green: top, blue: top * 0.97, alpha: 1),
                CGColor(srgbRed: bottom, green: bottom, blue: bottom, alpha: 1),
            ] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: CGFloat(side) / 2, y: CGFloat(side)),
                end: CGPoint(x: CGFloat(side) / 2, y: 0),
                options: []
            )
            return context.makeImage()!
        }
        let ceiling = face(top: 0.95, bottom: 0.95)
        let floor = face(top: 0.07, bottom: 0.07)
        let wall = face(top: 0.70, bottom: 0.16)
        return [wall, wall, ceiling, floor, wall, wall]
    }()

    // MARK: - Frame driver

    private var displayLink: CADisplayLink?

    /// Started by the host view on mount and stopped on dismantle, so the
    /// game clock runs only while PlayingView is on screen — the same
    /// lifecycle SKScene.update had in the 2D version.
    func startFrameDriver() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopFrameDriver() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private var tickCount = 0

    @objc private func frameTick(_ link: CADisplayLink) {
        tickCount += 1
        if tickCount % 300 == 0 {
            Self.logger.info("stage heartbeat alive (\(self.tickCount))")
        }
        let now = ProcessInfo.processInfo.systemUptime
        hud.updateCursor(at: now)
        onTick?(now)
    }

    // MARK: - Snapshot rendering

    func render(_ snapshot: GameRenderer.Snapshot) {
        // Sliced fruit no longer appears in the active snapshot, so animate it
        // before the inactive-node cleanup removes its backing node.
        for hit in snapshot.hits { animateSlice(id: hit.fruitID, gameTime: snapshot.gameTime) }
        let activeIDs = Set(snapshot.fruits.filter { $0.state == .active }.map(\.id))
        for (id, node) in fruitNodes where !activeIDs.contains(id) {
            recycleFruit(node); fruitNodes[id] = nil
        }
        for fruit in snapshot.fruits where fruit.state == .active {
            let node = fruitNodes[fruit.id] ?? makeFruitNode(fruit)
            node.position = sceneVector(fruit.position(at: snapshot.gameTime))
            fruitNodes[fruit.id] = node
        }
        if let hand = snapshot.hand {
            hud.pushHandSample(scenePoint(hand), now: ProcessInfo.processInfo.systemUptime)
        } else {
            hud.clearHand()
        }
        if let slash = snapshot.slash {
            hud.drawSlash(from: scenePoint(slash.startPosition), to: scenePoint(slash.endPosition))
        }
    }

    /// Resets combo counting. HUD visuals are cleared by GameRenderer.clearTrail.
    func clearTrail() {
        comboCount = 0
        lastHitGameTime = nil
    }

    // MARK: - Fruit nodes

    // MARK: - Pipeline warm-up

    /// Pre-renders one fruit of every kind plus a slice half and a juice
    /// burst through an offscreen SCNRenderer, so SceneKit compiles its PBR,
    /// lathe and particle pipelines before the game's SCNView first draws.
    /// Without this, the first fruit / first slice / first juice each stall
    /// the main thread for hundreds of milliseconds — long enough to trip the
    /// 0.5 s camera-frame watchdog and pause the game the moment it starts.
    func prewarm() {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        var spawned: [SCNNode] = []
        let kinds = FruitKind.allCases
        for (index, kind) in kinds.enumerated() {
            let fruit = Fruit(
                kind: kind, spawnedAt: 0,
                position: .init(x: 0.15 + Double(index % 4) * 0.2, y: 0.15 + Double(index / 4) * 0.3),
                velocity: .init(x: 0, y: 0)
            )
            spawned.append(makeFruitNode(fruit))
        }
        if let sweep = splitSweep(for: .watermelon) {
            let watermelon = spawned.compactMap { $0 as? FruitNode3D }.first { $0.kind == .watermelon }
            spawned.append(spawnSlicePiece(
                sweep: sweep, kind: .watermelon,
                at: SCNVector3(size.width * 0.3, size.width * 0.15, -120),
                radius: watermelon?.radius ?? max(24, size.width * 0.12), flip: false, scaleFactor: 1,
                attachments: []
            ))
        }
        spawnJuice(at: SCNVector3(size.width * 0.5, size.width * 0.15, -120), kind: .watermelon)
        _ = renderer.snapshot(atTime: 0, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
        // Recycle everything the warm-up spawned. The juice node's 0.7 s
        // recycle action is canceled here so it doesn't double-pool.
        for node in scene.rootNode.childNodes where spawned.contains(node) || !(node.particleSystems?.isEmpty ?? true) {
            node.removeAllActions()
            let hadParticles = !(node.particleSystems?.isEmpty ?? true)
            node.removeAllParticleSystems()
            node.removeFromParentNode()
            if let fruit = node as? FruitNode3D {
                if fruitPool.count < 8 { fruitPool.append(fruit) }
            } else if hadParticles {
                if juiceNodePool.count < 18 { juiceNodePool.append(node) }
            } else if let slice = node as? SlicePieceNode, slicePool.count < 16 {
                slice.recycled = true
                slicePool.append(slice)
            }
        }
    }

    private func makeFruitNode(_ fruit: Fruit) -> FruitNode3D {
        let radius = max(24, size.width * fruit.radius)
        let node = fruitPool.popLast() ?? FruitNode3D()
        node.removeAllActions()
        node.opacity = 1
        node.removeFromParentNode()
        node.kind = fruit.kind
        node.radius = radius
        node.scale = SCNVector3(1, 1, 1)
        // Recycled nodes still carry the previous body; rebuild from scratch.
        for child in node.childNodes { child.removeFromParentNode() }

        let scaleNode = SCNNode()
        scaleNode.scale = SCNVector3(radius, radius, radius)
        node.addChildNode(scaleNode)
        assembleBody(kind: fruit.kind, spec: FruitVisualData.spec(for: fruit.kind), scaleNode: scaleNode)

        scene.rootNode.addChildNode(node)
        // Pop in, then keep spinning so the fruit reads as a lit body rather
        // than a flat sticker. Spin speed and direction are stable per fruit.
        node.scale = SCNVector3(0.55, 0.55, 0.55)
        let hash = UInt32(truncatingIfNeeded: fruit.id.hashValue)
        let direction: CGFloat = hash & 1 == 0 ? 1 : -1
        let spinSpeed = 2.0 + CGFloat(hash % 400) / 400 * 1.8
        let spinAxis: SCNVector3 = FruitVisualData.spec(for: fruit.kind).spinAxis == .y
            ? SCNVector3(0, 1, 0) : SCNVector3(0, 0, 1)
        node.runAction(.group([
            .sequence([.scale(to: 1.0, duration: 0.18)]),
            .repeatForever(.rotate(by: direction * .pi * 2, around: spinAxis, duration: .pi * 2 / spinSpeed))
        ]))
        // If the scale action never ticks (stalled render loop), don't leave
        // the fruit stuck at 55% size.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak node] in
            guard let node, node.parent != nil, node.scale.x < 0.99 else { return }
            node.scale = SCNVector3(1, 1, 1)
        }
        if soundEnabled { soundEffects.playSpawn(kind: fruit.kind) }
        return node
    }

    private func recycleFruit(_ node: FruitNode3D) {
        guard node.parent != nil || !fruitPool.contains(where: { $0 === node }) else { return }
        node.removeAllActions()
        node.removeFromParentNode()
        if fruitPool.count < 8, !fruitPool.contains(where: { $0 === node }) { fruitPool.append(node) }
    }

    /// Builds the per-kind body under `scaleNode` (which carries the radius
    /// scale). Banana and grape cluster are special-cased; everything else is
    /// a lathe solid plus attachments.
    private func assembleBody(kind: FruitKind, spec: FruitVisualSpec, scaleNode: SCNNode) {
        switch kind {
        case .banana:
            // Lathe of the offset ring profile: a curved capsule. The sweep
            // plane is rotated into the screen plane so the arc faces the
            // camera; the parent spin around z turns it in-plane like 2D.
            let bodyNode = SCNNode()
            let rimNode = SCNNode(geometry: bananaSweep.rim)
            rimNode.geometry?.materials = [rindMaterial(for: kind)]
            let capNode = SCNNode(geometry: bananaSweep.cap)
            capNode.geometry?.materials = [rindMaterial(for: kind)]
            bodyNode.addChildNode(rimNode)
            bodyNode.addChildNode(capNode)
            bodyNode.eulerAngles.x = -.pi / 2
            scaleNode.addChildNode(bodyNode)
            for attachment in spec.attachments { scaleNode.addChildNode(makeAttachment(attachment)) }
        case .grape:
            // Cluster: one main berry, four satellite berries, a stem.
            let rind = [rindMaterial(for: kind)]
            let main = SCNNode(geometry: grapeBerrySolid)
            main.geometry?.materials = rind
            scaleNode.addChildNode(main)
            let offsets = [
                SIMD3(0.62, -0.10, 0.18), SIMD3(-0.60, -0.18, 0.12),
                SIMD3(0.28, -0.62, -0.10), SIMD3(-0.18, 0.42, -0.15),
            ]
            for offset in offsets {
                let berry = SCNNode(geometry: grapeBerrySolid)
                berry.geometry?.materials = rind
                berry.scale = SCNVector3(0.4, 0.4, 0.4)
                berry.position = SCNVector3(offset)
                scaleNode.addChildNode(berry)
            }
            let stem = SCNNode(geometry: stemGeometry)
            stem.geometry?.materials = [attachmentMaterial(for: RGB(r: 0.35, g: 0.22, b: 0.10))]
            stem.position = SCNVector3(0, 1.05, 0)
            scaleNode.addChildNode(stem)
        default:
            let bodyNode = SCNNode()
            let rimNode = SCNNode(geometry: solidGeometry(for: kind))
            rimNode.geometry?.materials = [rindMaterial(for: kind)]
            bodyNode.addChildNode(rimNode)
            if kind == .mango { bodyNode.eulerAngles.z = 0.5 }
            scaleNode.addChildNode(bodyNode)
            for attachment in spec.attachments { scaleNode.addChildNode(makeAttachment(attachment)) }
        }
    }

    private func makeAttachment(_ attachment: AttachmentSpec) -> SCNNode {
        switch attachment {
        case .leaf(let position, let rotation, let scale, let color):
            let node = SCNNode(geometry: leafGeometry)
            node.geometry?.materials = [attachmentMaterial(for: color)]
            node.position = SCNVector3(position)
            node.eulerAngles = SCNVector3(rotation)
            node.scale = SCNVector3(scale)
            return node
        case .crown(let position):
            // Five flattened leaves fanned around the calyx point.
            let node = SCNNode()
            let color = RGB(r: 0.16, g: 0.52, b: 0.20)
            for index in 0..<5 {
                let leaf = SCNNode(geometry: leafGeometry)
                leaf.geometry?.materials = [attachmentMaterial(for: color)]
                let angle = Float(index) / 5 * 2 * .pi
                leaf.position = SCNVector3(sin(angle) * 0.28, 0.04, cos(angle) * 0.28)
                leaf.eulerAngles = SCNVector3(0.55, angle, -0.6)
                leaf.scale = SCNVector3(0.34, 0.13, 0.045)
                node.addChildNode(leaf)
            }
            node.position = SCNVector3(position)
            return node
        case .stem(let position):
            let node = SCNNode(geometry: stemGeometry)
            node.geometry?.materials = [attachmentMaterial(for: RGB(r: 0.35, g: 0.22, b: 0.10))]
            node.position = SCNVector3(position)
            return node
        case .tip(let position, let color):
            let node = SCNNode(geometry: tipGeometry)
            node.geometry?.materials = [attachmentMaterial(for: color)]
            node.position = SCNVector3(position)
            return node
        }
    }

    // MARK: - Slicing

    private func animateSlice(id: UUID, gameTime: TimeInterval) {
        guard let original = fruitNodes.removeValue(forKey: id) else { return }
        let kind = original.kind
        let position = original.position
        let radius = original.radius
        switch kind {
        case .banana:
            // No clean halves: the whole banana fades in place while juice
            // bursts from the cut point.
            original.runAction(.fadeOut(duration: 0.30)) { [weak self, weak original] in
                guard let self, let original else { return }
                self.recycleFruit(original)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak original] in
                guard let self, let original, original.parent != nil else { return }
                self.recycleFruit(original)
            }
        case .grape:
            // The cluster bursts into a few loose berry halves.
            recycleFruit(original)
            let berries: [(SIMD3<Float>, Float)] = [
                (SIMD3(0.35, 0.30, 0), 0.5), (SIMD3(-0.30, 0.10, 0), 0.4), (SIMD3(0.05, -0.25, 0), 0.45),
            ]
            for (offset, _) in berries {
                let berry = spawnSlicePiece(
                    sweep: grapeBerrySplit, kind: kind,
                    at: SCNVector3(
                        CGFloat(position.x) + radius * CGFloat(offset.x),
                        CGFloat(position.y) + radius * CGFloat(offset.y),
                        CGFloat(position.z)
                    ),
                    radius: radius, flip: false, scaleFactor: 0.4, attachments: []
                )
                finishSlicePiece(berry, action: .group([
                    .moveBy(x: 0, y: -60, z: 0, duration: 0.42),
                    .fadeOut(duration: 0.42)
                ]))
            }
        default:
            recycleFruit(original)
            guard let sweep = splitSweep(for: kind) else { break }
            let spec = FruitVisualData.spec(for: kind)
            for direction in [-1.0, 1.0] {
                // Both halves use the same cached equator-cut dome; the lower
                // half flips (eulerAngles.x = π) so its face mirrors the
                // photo texture the way a real cut would. Attachments stay
                // with the upper half.
                let isUpper = direction > 0
                let half = spawnSlicePiece(
                    sweep: sweep, kind: kind,
                    at: SCNVector3(
                        CGFloat(position.x) + radius * 0.16 * direction,
                        CGFloat(position.y) + radius * 0.5 * (isUpper ? -1 : 1),
                        CGFloat(position.z)
                    ),
                    radius: radius, flip: !isUpper, scaleFactor: 1,
                    attachments: isUpper ? spec.attachments : []
                )
                finishSlicePiece(half, action: sliceAction(direction: direction))
            }
        }
        spawnImpactEffects(at: position, kind: kind, radius: radius, gameTime: gameTime)
        // Played after spawnImpactEffects so comboCount reflects this hit.
        if soundEnabled { soundEffects.playSlice(kind: kind, combo: comboCount) }
        Self.logger.info("slice spawned kind=\(kind.rawValue, privacy: .public) combo=\(self.comboCount)")
    }

    private func sliceAction(direction: Double) -> SCNAction {
        if reduceMotion {
            .fadeOut(duration: 0.16)
        } else {
            .group([
                .moveBy(x: 90 * direction, y: -110, z: 0, duration: 0.42),
                .rotateBy(x: 0.9 * direction, y: 0.7 * direction, z: 1.4 * direction, duration: 0.42),
                .fadeOut(duration: 0.42)
            ])
        }
    }

    /// Builds (or recycles) a slice container carrying rim + cap children for
    /// the given split sweep. Both halves share the equator-cut dome geometry;
    /// the x-tilt turns each cut face toward the camera (upper half −0.8, lower
    /// half π+0.8 so the shared face normal points front). Attachments above
    /// the cut plane ride along (kept only on the upper half).
    private func spawnSlicePiece(
        sweep: LatheGeometry.SweepResult,
        kind: FruitKind,
        at position: SCNVector3,
        radius: CGFloat,
        flip: Bool,
        scaleFactor: CGFloat,
        attachments: [AttachmentSpec]
    ) -> SlicePieceNode {
        let piece = slicePool.popLast() ?? SlicePieceNode()
        piece.removeAllActions()
        piece.removeFromParentNode()
        piece.opacity = 1
        piece.recycled = false
        for child in piece.childNodes { child.removeFromParentNode() }
        let rimNode = SCNNode(geometry: sweep.rim)
        rimNode.geometry?.materials = [rindMaterial(for: kind)]
        let capNode = SCNNode(geometry: sweep.cap)
        capNode.geometry?.materials = [fleshMaterial(for: kind)]
        piece.addChildNode(rimNode)
        piece.addChildNode(capNode)
        piece.scale = SCNVector3(radius * scaleFactor, radius * scaleFactor, radius * scaleFactor)
        piece.position = position
        piece.eulerAngles.x = flip ? .pi + 0.8 : -0.8
        for attachment in attachments where attachment.position.y > 0 {
            piece.addChildNode(makeAttachment(attachment))
        }
        scene.rootNode.addChildNode(piece)
        return piece
    }

    private func finishSlicePiece(_ piece: SlicePieceNode, action: SCNAction) {
        piece.runAction(action) { [weak self, weak piece] in
            guard let self, let piece else { return }
            self.recycleSlicePiece(piece, path: "action")
        }
        // Watchdog: even if the render loop stalls or the action completion
        // never fires on device, the piece is guaranteed to leave the screen
        // shortly after its animation window ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak piece] in
            guard let self, let piece else { return }
            self.recycleSlicePiece(piece, path: "watchdog")
        }
    }

    private func recycleSlicePiece(_ piece: SlicePieceNode, path: String) {
        guard !piece.recycled else { return }
        piece.recycled = true
        piece.removeAllActions()
        piece.removeFromParentNode()
        if slicePool.count < 16 { slicePool.append(piece) }
        Self.logger.info("slice piece recycled via \(path, privacy: .public)")
    }

    private func spawnImpactEffects(
        at position: SCNVector3,
        kind: FruitKind,
        radius: CGFloat,
        gameTime: TimeInterval
    ) {
        spawnJuice(at: position, kind: kind)
        let point = CGPoint(x: CGFloat(position.x), y: CGFloat(position.y))
        hud.spawnRing(at: point, kind: kind, radius: radius)
        if let lastHitGameTime, gameTime - lastHitGameTime <= 0.8 {
            comboCount += 1
        } else {
            comboCount = 1
        }
        self.lastHitGameTime = gameTime
        hud.showCombo(count: comboCount, at: point, radius: radius)

        guard !reduceMotion else { return }
        cameraNode.removeAction(forKey: "impactShake")
        cameraNode.position = baseCameraPosition
        cameraNode.runAction(.sequence([
            .moveBy(x: 8, y: -5, z: 0, duration: 0.025),
            .moveBy(x: -14, y: 8, z: 0, duration: 0.03),
            .moveBy(x: 9, y: -4, z: 0, duration: 0.03),
            .move(to: baseCameraPosition, duration: 0.025)
        ]), forKey: "impactShake")
    }

    // MARK: - Juice particles

    private func spawnJuice(at position: SCNVector3, kind: FruitKind) {
        let systems = juiceSystems(for: kind)
        guard !systems.isEmpty else { return }
        // Round-robin among the prebuilt systems so back-to-back slices don't
        // fight over one emitter.
        let index = (juiceCursor[kind] ?? 0) % systems.count
        juiceCursor[kind] = index + 1
        let node = juiceNodePool.popLast() ?? SCNNode()
        node.removeAllActions()
        node.removeFromParentNode()
        node.position = position
        scene.rootNode.addChildNode(node)
        node.addParticleSystem(systems[index])
        node.runAction(.wait(duration: 0.7)) { [weak self, weak node] in
            guard let self, let node else { return }
            self.recycleJuiceNode(node)
        }
        // Watchdog, same rationale as the slice pieces.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak node] in
            guard let self, let node, node.parent != nil else { return }
            self.recycleJuiceNode(node)
        }
    }

    private func recycleJuiceNode(_ node: SCNNode) {
        node.removeAllActions()
        node.removeFromParentNode()
        node.removeAllParticleSystems()
        if juiceNodePool.count < 18, !juiceNodePool.contains(where: { $0 === node }) {
            juiceNodePool.append(node)
        }
    }

    private func juiceSystems(for kind: FruitKind) -> [SCNParticleSystem] {
        if let cached = juiceSystems[kind] { return cached }
        let spec = FruitVisualData.spec(for: kind)
        var systems: [SCNParticleSystem] = []
        for _ in 0..<3 {
            let system = SCNParticleSystem()
            system.loops = false
            system.emissionDuration = reduceMotion ? 0.08 : 0.12
            system.birthRate = reduceMotion ? 60 : 140
            system.particleLifeSpan = 0.45
            system.particleLifeSpanVariation = 0.15
            system.particleSize = 7
            system.particleSizeVariation = 4
            system.particleColor = UIColor(
                red: CGFloat(spec.flesh.r), green: CGFloat(spec.flesh.g),
                blue: CGFloat(spec.flesh.b), alpha: 1
            )
            system.particleColorVariation = SCNVector4(0.15, 0.15, 0.15, 0)
            system.spreadingAngle = 360
            system.emittingDirection = SCNVector3(0, 1, 0)
            system.particleVelocity = 110
            system.speedFactor = 0.5
            system.isAffectedByGravity = false
            system.acceleration = SCNVector3(0, -650, 0)
            system.particleImage = Self.particleImage
            system.blendMode = .alpha
            systems.append(system)
        }
        juiceSystems[kind] = systems
        return systems
    }

    /// Soft white disc; particleColor tints it per fruit kind.
    private static let particleImage: CGImage = {
        let side = 32
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let colors = [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: side / 2, y: side / 2), startRadius: 0,
            endCenter: CGPoint(x: side / 2, y: side / 2), endRadius: CGFloat(side) / 2,
            options: []
        )
        return context.makeImage()!
    }()

    // MARK: - Shared geometry and materials

    private func solidGeometry(for kind: FruitKind) -> SCNGeometry {
        if let cached = solidGeometries[kind] { return cached }
        let profile = FruitVisualData.spec(for: kind).profile ?? FruitVisualData.circleProfile()
        let geometry = LatheGeometry.solid(profile: profile)
        solidGeometries[kind] = geometry
        return geometry
    }

    private func splitSweep(for kind: FruitKind) -> LatheGeometry.SweepResult? {
        if let cached = splitGeometries[kind] { return cached }
        guard let profile = FruitVisualData.spec(for: kind).profile else { return nil }
        let sweep = LatheGeometry.split(profile: profile)
        splitGeometries[kind] = sweep
        return sweep
    }

    /// Shared materials are immutable once cached: fades always go through
    /// node opacity, never material-level transparency.
    private func rindMaterial(for kind: FruitKind) -> SCNMaterial {
        if let cached = rindMaterials[kind] { return cached }
        let spec = FruitVisualData.spec(for: kind)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        // Whole-fruit photo when available (lighting flattened, so the real
        // lights here provide the highlights); procedural otherwise.
        material.diffuse.contents = FruitTexture.skin(kind) ?? ProceduralTexture.rind(kind)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.maxAnisotropy = 4
        material.roughness.contents = spec.roughness
        material.metalness.contents = 0
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        rindMaterials[kind] = material
        return material
    }

    private func fleshMaterial(for kind: FruitKind) -> SCNMaterial {
        if let cached = fleshMaterials[kind] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = FruitTexture.cap(kind) ?? ProceduralTexture.flesh(kind)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.maxAnisotropy = 4
        material.roughness.contents = 0.6
        material.metalness.contents = 0
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        fleshMaterials[kind] = material
        return material
    }

    private func attachmentMaterial(for color: RGB) -> SCNMaterial {
        if let cached = attachmentMaterials[color] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(
            red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1
        )
        material.roughness.contents = 0.5
        material.metalness.contents = 0
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        attachmentMaterials[color] = material
        return material
    }

    // MARK: - Coordinate mapping

    /// Same square play space as the 2D scenePoint: normalized coordinates
    /// scaled by the width, y up, fruit plane at z = 0.
    private func sceneVector(_ point: Vector2) -> SCNVector3 {
        SCNVector3(CGFloat(point.x) * size.width, CGFloat(point.y) * size.width, 0)
    }

    private func scenePoint(_ point: Vector2) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.width)
    }
}
