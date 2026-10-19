import AVFoundation
import SpriteKit
import FruitWaveCore
import OSLog

@MainActor
final class GameScene: SKScene {
    struct Snapshot {
        let fruits: [Fruit]
        let gameTime: TimeInterval
        let score: Int
        let hand: Vector2?
        let slash: SlashSegment?
        let hits: [HitEvent]
    }

    var onTick: ((TimeInterval) -> Void)?
    var soundEnabled = true {
        didSet {
            // Turning sound back on doubles as an immediate output check,
            // instead of making the player wait until the next successful hit.
            if soundEnabled, !oldValue { soundEffects.playPreview() }
        }
    }
    var reduceMotion = false
    private var fruitNodes: [UUID: FruitVisualNode] = [:]
    private var fruitPool: [FruitVisualNode] = []
    private var trailPool: [SKShapeNode] = []
    private var fragmentPool: [SKShapeNode] = []
    private var juicePool: [SKShapeNode] = []
    private let handNode = SKShapeNode(circleOfRadius: 13)
    private let trailLayer = SKNode()
    private let effectsLayer = SKNode()
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let soundEffects = GameSceneSoundEffects()
    private var comboCount = 0
    private var lastHitGameTime: TimeInterval?
    // The newest hand samples in scene space, used to interpolate the cursor
    // at the 60 Hz scene rate instead of the ~30 Hz pose-sample rate.
    private var handSamples: [(time: TimeInterval, point: CGPoint)] = []

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.025, green: 0.04, blue: 0.085, alpha: 1)
        scaleMode = .resizeFill
        handNode.fillColor = .white
        handNode.strokeColor = .cyan
        handNode.lineWidth = 5
        handNode.glowWidth = 8
        handNode.isHidden = true
        trailLayer.zPosition = 20
        effectsLayer.zPosition = 24
        handNode.zPosition = 30
        comboLabel.fontSize = 44
        comboLabel.fontColor = .white
        comboLabel.verticalAlignmentMode = .center
        comboLabel.isHidden = true
        effectsLayer.addChild(comboLabel)
        addChild(trailLayer)
        addChild(effectsLayer)
        addChild(handNode)
    }

    override func update(_ currentTime: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        onTick?(now)
        updateHandNode(now: now)
    }

    /// Places the hand cursor between the two newest samples and extrapolates
    /// a short distance ahead of the newest one, so the cursor follows the
    /// real hand instead of trailing the pose pipeline by a sample.
    private func updateHandNode(now: TimeInterval) {
        guard !handNode.isHidden, let latest = handSamples.last else { return }
        guard handSamples.count > 1 else { handNode.position = latest.point; return }
        let previous = handSamples[0]
        let interval = latest.time - previous.time
        guard interval > 0 else { handNode.position = latest.point; return }
        let elapsed = min(0.045, max(0, now - latest.time))
        let velocity = CGPoint(
            x: (latest.point.x - previous.point.x) / CGFloat(interval),
            y: (latest.point.y - previous.point.y) / CGFloat(interval)
        )
        handNode.position = CGPoint(
            x: latest.point.x + velocity.x * CGFloat(elapsed),
            y: latest.point.y + velocity.y * CGFloat(elapsed)
        )
    }

    func render(_ snapshot: Snapshot) {
        // Sliced fruit no longer appears in the active snapshot, so animate it
        // before the inactive-node cleanup removes its backing node.
        for hit in snapshot.hits { animateSlice(id: hit.fruitID, gameTime: snapshot.gameTime) }
        let activeIDs = Set(snapshot.fruits.filter { $0.state == .active }.map(\.id))
        for (id, node) in fruitNodes where !activeIDs.contains(id) {
            recycleFruit(node); fruitNodes[id] = nil
        }
        for fruit in snapshot.fruits where fruit.state == .active {
            let node = fruitNodes[fruit.id] ?? makeFruitNode(fruit)
            node.position = scenePoint(fruit.position(at: snapshot.gameTime))
            fruitNodes[fruit.id] = node
        }
        if let hand = snapshot.hand {
            handNode.isHidden = false
            let now = ProcessInfo.processInfo.systemUptime
            let point = scenePoint(hand)
            if let last = handSamples.last {
                if last.point != point {
                    handSamples = [(time: last.time, point: last.point), (time: now, point: point)]
                } else {
                    // Stationary hand: stop extrapolating and hold in place.
                    handSamples = [(time: now, point: point)]
                }
            } else {
                handSamples = [(time: now, point: point)]
            }
        } else {
            handNode.isHidden = true
            handSamples.removeAll()
        }
        if let slash = snapshot.slash { drawTrail(from: scenePoint(slash.startPosition), to: scenePoint(slash.endPosition)) }
    }

    func clearTrail() {
        for case let node as SKShapeNode in trailLayer.children {
            node.removeAllActions()
            recycleTrail(node)
        }
        comboCount = 0
        lastHitGameTime = nil
        comboLabel.removeAllActions()
        comboLabel.isHidden = true
    }

    private func makeFruitNode(_ fruit: Fruit) -> FruitVisualNode {
        let radius = max(24, size.width * fruit.radius)
        let node = fruitPool.popLast() ?? FruitVisualNode()
        node.removeAllActions()
        node.alpha = 1
        node.zRotation = 0
        node.setScale(1)
        node.configure(kind: fruit.kind, radius: radius)
        addChild(node)
        // Pop in, then keep spinning so the fruit reads as a lit body rather
        // than a flat sticker. Spin speed and direction are stable per fruit.
        node.setScale(0.55)
        let hash = UInt32(truncatingIfNeeded: fruit.id.hashValue)
        let direction: CGFloat = hash & 1 == 0 ? 1 : -1
        let spinSpeed = 2.0 + CGFloat(hash % 400) / 400 * 1.8
        node.run(.group([
            .sequence([.scale(to: 1.0, duration: 0.18)]),
            .repeatForever(.rotate(byAngle: direction * .pi * 2, duration: .pi * 2 / spinSpeed))
        ]))
        return node
    }

    private func recycleFruit(_ node: FruitVisualNode) {
        node.removeAllActions()
        node.removeFromParent()
        if fruitPool.count < 8 { fruitPool.append(node) }
    }

    private func animateSlice(id: UUID, gameTime: TimeInterval) {
        guard let original = fruitNodes.removeValue(forKey: id) else { return }
        let kind = original.kind
        let position = original.position
        let radius = original.radius
        recycleFruit(original)
        spawnImpactEffects(at: position, kind: kind, radius: radius, gameTime: gameTime)
        // Played after spawnImpactEffects so comboCount reflects this hit.
        if soundEnabled { soundEffects.playSlice(kind: kind, combo: comboCount) }
        for direction in [-1.0, 1.0] {
            let half = fragmentPool.popLast() ?? SKShapeNode()
            half.removeAllActions()
            half.removeAllChildren()
            half.path = FruitVisualNode.halfPath(radius: radius, rightHalf: direction > 0)
            half.alpha = 1; half.zRotation = 0
            if let shading = FruitVisualNode.shadingTexture(for: kind) {
                half.fillTexture = shading
                half.fillColor = .white
            } else {
                half.fillColor = FruitVisualNode.fleshColor(for: kind)
            }
            half.strokeColor = FruitVisualNode.rindColor(for: kind)
            half.lineWidth = max(5, radius * 0.09)
            half.position = CGPoint(x: position.x + radius * 0.16 * direction, y: position.y)
            FruitVisualNode.addSliceDetails(to: half, kind: kind, radius: radius, direction: direction)
            addChild(half)
            let action: SKAction = if reduceMotion {
                .fadeOut(withDuration: 0.16)
            } else {
                .group([
                    .moveBy(x: 90 * direction, y: -110, duration: 0.42),
                    .rotate(byAngle: direction * 1.4, duration: 0.42),
                    .fadeOut(withDuration: 0.42)
                ])
            }
            half.run(action) { [weak self, weak half] in
                guard let self, let half else { return }
                half.removeFromParent()
                if self.fragmentPool.count < 16 { self.fragmentPool.append(half) }
            }
        }
    }

    private func drawTrail(from start: CGPoint, to end: CGPoint) {
        let path = CGMutablePath(); path.move(to: start); path.addLine(to: end)
        addTrail(path: path, color: .cyan, width: 24, glow: reduceMotion ? 0 : 16, duration: reduceMotion ? 0.10 : 0.20)
        addTrail(path: path, color: .white, width: 7, glow: reduceMotion ? 0 : 5, duration: reduceMotion ? 0.08 : 0.14)
    }

    private func addTrail(path: CGPath, color: SKColor, width: CGFloat, glow: CGFloat, duration: TimeInterval) {
        let node = trailPool.popLast() ?? SKShapeNode()
        node.removeAllActions(); node.path = path; node.alpha = 1
        node.strokeColor = color; node.lineWidth = width; node.lineCap = .round
        node.glowWidth = glow
        node.blendMode = .add
        trailLayer.addChild(node)
        node.run(.group([.fadeOut(withDuration: duration), .scale(to: 0.86, duration: duration)])) { [weak self, weak node] in
            guard let self, let node, node.parent != nil else { return }
            node.setScale(1)
            self.recycleTrail(node)
        }
    }

    private func spawnImpactEffects(
        at position: CGPoint,
        kind: FruitKind,
        radius: CGFloat,
        gameTime: TimeInterval
    ) {
        let juiceColor = FruitVisualNode.fleshColor(for: kind)
        let dropletCount = reduceMotion ? 7 : 18
        for index in 0..<dropletCount {
            let droplet = juicePool.popLast() ?? SKShapeNode(circleOfRadius: 6)
            droplet.removeAllActions()
            droplet.path = CGPath(
                ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12),
                transform: nil
            )
            droplet.fillColor = juiceColor
            droplet.strokeColor = .white.withAlphaComponent(0.35)
            droplet.lineWidth = 1.5
            droplet.alpha = 0.95
            droplet.setScale(CGFloat.random(in: 0.55...1.45))
            droplet.position = position
            effectsLayer.addChild(droplet)

            let angle = (CGFloat(index) / CGFloat(dropletCount)) * .pi * 2 + CGFloat.random(in: -0.18...0.18)
            let distance = radius * CGFloat.random(in: 0.75...1.75)
            let destination = CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance - radius * 0.24)
            let duration = reduceMotion ? 0.18 : Double.random(in: 0.32...0.52)
            droplet.run(.group([
                .move(by: destination, duration: duration),
                .fadeOut(withDuration: duration),
                .scale(to: 0.15, duration: duration)
            ])) { [weak self, weak droplet] in
                guard let self, let droplet else { return }
                droplet.removeFromParent()
                if self.juicePool.count < 48 { self.juicePool.append(droplet) }
            }
        }

        let ring = SKShapeNode(circleOfRadius: radius * 0.58)
        ring.position = position
        ring.fillColor = .clear
        ring.strokeColor = juiceColor
        ring.lineWidth = max(6, radius * 0.08)
        ring.glowWidth = reduceMotion ? 0 : 14
        ring.blendMode = .add
        effectsLayer.addChild(ring)
        ring.run(.group([
            .scale(to: reduceMotion ? 1.25 : 2.0, duration: reduceMotion ? 0.12 : 0.24),
            .fadeOut(withDuration: reduceMotion ? 0.12 : 0.24)
        ])) { [weak ring] in ring?.removeFromParent() }

        if let lastHitGameTime, gameTime - lastHitGameTime <= 0.8 {
            comboCount += 1
        } else {
            comboCount = 1
        }
        self.lastHitGameTime = gameTime
        comboLabel.removeAllActions()
        comboLabel.isHidden = false
        comboLabel.alpha = 1
        comboLabel.setScale(0.65)
        comboLabel.position = CGPoint(x: position.x, y: min(size.height - 80, position.y + radius * 1.35))
        comboLabel.text = comboCount >= 2 ? "\(comboCount) 连击！" : "+10"
        comboLabel.fontColor = comboCount >= 3 ? .systemYellow : .white
        comboLabel.run(.sequence([
            .group([.scale(to: 1.15, duration: 0.10), .moveBy(x: 0, y: 18, duration: 0.10)]),
            .wait(forDuration: 0.22),
            .group([.fadeOut(withDuration: 0.18), .moveBy(x: 0, y: 34, duration: 0.18)]),
            .hide()
        ]))

        guard !reduceMotion else { return }
        removeAction(forKey: "impactShake")
        self.position = .zero
        run(.sequence([
            .moveBy(x: 8, y: -5, duration: 0.025),
            .moveBy(x: -14, y: 8, duration: 0.03),
            .moveBy(x: 9, y: -4, duration: 0.03),
            .move(to: .zero, duration: 0.025)
        ]), withKey: "impactShake")
    }

    private func recycleTrail(_ node: SKShapeNode) {
        node.removeFromParent()
        node.path = nil
        if trailPool.count < 32, !trailPool.contains(where: { $0 === node }) { trailPool.append(node) }
    }

    private func scenePoint(_ point: Vector2) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.width)
    }
}

@MainActor
private final class FruitVisualNode: SKNode {
    private(set) var kind: FruitKind = .watermelon
    private(set) var radius: CGFloat = 24

    func configure(kind: FruitKind, radius: CGFloat) {
        self.kind = kind
        self.radius = radius
        removeAllChildren()

        let body = SKShapeNode(path: Self.wholePath(kind: kind, radius: radius))
        if let shading = Self.shadingTexture(for: kind) {
            body.fillTexture = shading
            body.fillColor = .white
        } else {
            body.fillColor = Self.rindColor(for: kind)
        }
        body.strokeColor = Self.shadedRindColor(for: kind)
        body.lineWidth = max(4, radius * 0.055)
        body.glowWidth = max(2, radius * 0.035)
        addChild(body)

        switch kind {
        case .watermelon:
            addWatermelonDetails(radius: radius)
        case .strawberry:
            addStrawberryDetails(radius: radius)
        case .pineapple:
            addPineappleDetails(radius: radius)
        case .apple:
            addAppleDetails(radius: radius)
        case .orange:
            addOrangeDetails(radius: radius)
        case .banana:
            addBananaDetails(radius: radius)
        case .kiwi:
            addKiwiDetails(radius: radius)
        case .peach:
            addPeachDetails(radius: radius)
        case .mango:
            addMangoDetails(radius: radius)
        case .lemon:
            addLemonDetails(radius: radius)
        case .grape:
            addGrapeDetails(radius: radius)
        case .dragonFruit:
            addDragonFruitDetails(radius: radius)
        default:
            break
        }

        // Bottom inner shadow and upper-left gloss give the flat path a
        // shaded, ball-like volume. Both spin with the fruit, which reads as
        // a lit body rather than a static icon.
        let rimShade = SKShapeNode(ellipseOf: CGSize(width: radius * 1.62, height: radius * 0.86))
        rimShade.fillColor = .black.withAlphaComponent(0.14)
        rimShade.strokeColor = .clear
        rimShade.position = CGPoint(x: radius * 0.08, y: -radius * 0.46)
        addChild(rimShade)

        let highlight = SKShapeNode(ellipseOf: CGSize(width: radius * 0.26, height: radius * 0.44))
        highlight.fillColor = .white.withAlphaComponent(0.30)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -radius * 0.28, y: radius * 0.26)
        highlight.zRotation = -0.45
        addChild(highlight)
    }

    private static var shadingTextures: [FruitKind: SKTexture] = [:]

    /// A cached radial gradient (light upper-left to dark edge) per fruit
    /// kind, used to fake volume on the flat shape path.
    static func shadingTexture(for kind: FruitKind) -> SKTexture? {
        if let cached = shadingTextures[kind] { return cached }
        let size = 128
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let base = rindColor(for: kind)
        let baseComponents = rgbComponents(of: base)
        let light = SKColor(
            red: min(1, baseComponents.red + 0.30),
            green: min(1, baseComponents.green + 0.30),
            blue: min(1, baseComponents.blue + 0.30),
            alpha: 1
        )
        let dark = SKColor(
            red: baseComponents.red * 0.55,
            green: baseComponents.green * 0.55,
            blue: baseComponents.blue * 0.55,
            alpha: 1
        )
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [light.cgColor, base.cgColor, dark.cgColor] as CFArray,
            locations: [0, 0.52, 1]
        ) else { return nil }
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: CGFloat(size) * 0.38, y: CGFloat(size) * 0.62),
            startRadius: 6,
            endCenter: CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.5),
            endRadius: CGFloat(size) * 0.68,
            options: []
        )
        guard let image = context.makeImage() else { return nil }
        let texture = SKTexture(cgImage: image)
        shadingTextures[kind] = texture
        return texture
    }

    static func shadedRindColor(for kind: FruitKind) -> SKColor {
        let base = rindColor(for: kind)
        let components = rgbComponents(of: base)
        return SKColor(
            red: components.red * 0.52,
            green: components.green * 0.52,
            blue: components.blue * 0.52,
            alpha: 1
        )
    }

    /// tvOS's SKColor is UIColor, which exposes components only through
    /// `getRed(_:green:blue:alpha:)` instead of NSColor's component getters.
    private static func rgbComponents(of color: SKColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    static func rindColor(for kind: FruitKind) -> SKColor {
        switch kind {
        case .watermelon: SKColor(red: 0.10, green: 0.68, blue: 0.27, alpha: 1)
        case .strawberry: SKColor(red: 0.95, green: 0.12, blue: 0.23, alpha: 1)
        case .pineapple: SKColor(red: 0.98, green: 0.68, blue: 0.10, alpha: 1)
        case .apple: SKColor(red: 0.88, green: 0.08, blue: 0.12, alpha: 1)
        case .orange: SKColor(red: 1.0, green: 0.43, blue: 0.04, alpha: 1)
        case .banana: SKColor(red: 0.98, green: 0.82, blue: 0.16, alpha: 1)
        case .kiwi: SKColor(red: 0.42, green: 0.24, blue: 0.10, alpha: 1)
        case .peach: SKColor(red: 1.0, green: 0.48, blue: 0.39, alpha: 1)
        case .mango: SKColor(red: 1.0, green: 0.64, blue: 0.10, alpha: 1)
        case .lemon: SKColor(red: 0.98, green: 0.84, blue: 0.06, alpha: 1)
        case .grape: SKColor(red: 0.56, green: 0.24, blue: 0.78, alpha: 1)
        case .dragonFruit: SKColor(red: 0.96, green: 0.26, blue: 0.55, alpha: 1)
        default: SKColor(white: 0.5, alpha: 1)
        }
    }

    static func fleshColor(for kind: FruitKind) -> SKColor {
        switch kind {
        case .watermelon: SKColor(red: 0.98, green: 0.18, blue: 0.30, alpha: 1)
        case .strawberry: SKColor(red: 1.0, green: 0.24, blue: 0.32, alpha: 1)
        case .pineapple: SKColor(red: 1.0, green: 0.84, blue: 0.22, alpha: 1)
        case .apple: SKColor(red: 1.0, green: 0.92, blue: 0.68, alpha: 1)
        case .orange: SKColor(red: 1.0, green: 0.58, blue: 0.06, alpha: 1)
        case .banana: SKColor(red: 1.0, green: 0.94, blue: 0.55, alpha: 1)
        case .kiwi: SKColor(red: 0.50, green: 0.82, blue: 0.20, alpha: 1)
        case .peach: SKColor(red: 1.0, green: 0.76, blue: 0.52, alpha: 1)
        case .mango: SKColor(red: 1.0, green: 0.82, blue: 0.28, alpha: 1)
        case .lemon: SKColor(red: 1.0, green: 0.94, blue: 0.46, alpha: 1)
        case .grape: SKColor(red: 0.72, green: 0.88, blue: 0.52, alpha: 1)
        case .dragonFruit: SKColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        default: SKColor(white: 0.8, alpha: 1)
        }
    }

    static func halfPath(radius: CGFloat, rightHalf: Bool) -> CGPath {
        let path = CGMutablePath()
        if rightHalf {
            path.move(to: CGPoint(x: 0, y: -radius))
            path.addArc(center: .zero, radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        } else {
            path.move(to: CGPoint(x: 0, y: radius))
            path.addArc(center: .zero, radius: radius, startAngle: .pi / 2, endAngle: .pi * 1.5, clockwise: false)
        }
        path.closeSubpath()
        return path
    }

    static func addSliceDetails(
        to node: SKShapeNode,
        kind: FruitKind,
        radius: CGFloat,
        direction: CGFloat
    ) {
        let sign: CGFloat = direction < 0 ? -1 : 1
        switch kind {
        case .watermelon:
            for y in [-0.34, 0, 0.34] as [CGFloat] {
                let seed = SKShapeNode(ellipseOf: CGSize(width: radius * 0.10, height: radius * 0.17))
                seed.fillColor = SKColor(white: 0.08, alpha: 1)
                seed.strokeColor = .clear
                seed.position = CGPoint(x: sign * radius * 0.36, y: radius * y)
                seed.zRotation = sign * 0.3
                node.addChild(seed)
            }
        case .strawberry:
            for y in [-0.3, 0.05, 0.36] as [CGFloat] {
                let seed = SKShapeNode(ellipseOf: CGSize(width: radius * 0.08, height: radius * 0.13))
                seed.fillColor = SKColor(red: 1, green: 0.9, blue: 0.42, alpha: 1)
                seed.strokeColor = .clear
                seed.position = CGPoint(x: sign * radius * 0.34, y: radius * y)
                node.addChild(seed)
            }
        case .pineapple:
            for y in [-0.38, 0, 0.38] as [CGFloat] {
                let line = SKShapeNode()
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: radius * y - radius * 0.18))
                path.addLine(to: CGPoint(x: sign * radius * 0.62, y: radius * y + radius * 0.18))
                line.path = path
                line.strokeColor = SKColor(red: 0.74, green: 0.42, blue: 0.06, alpha: 0.75)
                line.lineWidth = max(2, radius * 0.035)
                node.addChild(line)
            }
        case .apple:
            let core = SKShapeNode(ellipseOf: CGSize(width: radius * 0.14, height: radius * 0.55))
            core.fillColor = SKColor(red: 0.65, green: 0.42, blue: 0.18, alpha: 1)
            core.strokeColor = .clear
            core.position.x = sign * radius * 0.16
            node.addChild(core)
            for y in [-0.12, 0.15] as [CGFloat] {
                let seed = SKShapeNode(ellipseOf: CGSize(width: radius * 0.07, height: radius * 0.13))
                seed.fillColor = SKColor(white: 0.16, alpha: 1)
                seed.strokeColor = .clear
                seed.position = CGPoint(x: sign * radius * 0.34, y: radius * y)
                node.addChild(seed)
            }
        case .orange:
            for angle in [-0.55, 0, 0.55] as [CGFloat] {
                let segment = SKShapeNode()
                let path = CGMutablePath()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: sign * cos(angle) * radius * 0.76, y: sin(angle) * radius * 0.76))
                segment.path = path
                segment.strokeColor = .white.withAlphaComponent(0.55)
                segment.lineWidth = max(2, radius * 0.025)
                node.addChild(segment)
            }
        case .banana:
            let center = SKShapeNode(ellipseOf: CGSize(width: radius * 0.13, height: radius * 0.13))
            center.fillColor = SKColor(red: 0.55, green: 0.35, blue: 0.12, alpha: 0.8)
            center.strokeColor = .clear
            center.position.x = sign * radius * 0.32
            node.addChild(center)
        case .kiwi:
            let core = SKShapeNode(ellipseOf: CGSize(width: radius * 0.18, height: radius * 0.40))
            core.fillColor = .white.withAlphaComponent(0.78)
            core.strokeColor = .clear
            core.position.x = sign * radius * 0.18
            node.addChild(core)
            for y in [-0.42, -0.14, 0.14, 0.42] as [CGFloat] {
                let seed = SKShapeNode(ellipseOf: CGSize(width: radius * 0.055, height: radius * 0.10))
                seed.fillColor = SKColor(white: 0.05, alpha: 1)
                seed.strokeColor = .clear
                seed.position = CGPoint(x: sign * radius * 0.42, y: radius * y)
                node.addChild(seed)
            }
        case .peach:
            let pit = SKShapeNode(ellipseOf: CGSize(width: radius * 0.32, height: radius * 0.52))
            pit.fillColor = SKColor(red: 0.58, green: 0.20, blue: 0.09, alpha: 1)
            pit.strokeColor = SKColor(red: 0.35, green: 0.10, blue: 0.04, alpha: 1)
            pit.lineWidth = max(2, radius * 0.03)
            pit.position.x = sign * radius * 0.18
            node.addChild(pit)
        case .mango:
            let seed = SKShapeNode(ellipseOf: CGSize(width: radius * 0.30, height: radius * 0.78))
            seed.fillColor = SKColor(red: 0.82, green: 0.62, blue: 0.22, alpha: 1)
            seed.strokeColor = SKColor(red: 0.55, green: 0.38, blue: 0.10, alpha: 1)
            seed.lineWidth = max(2, radius * 0.03)
            seed.position.x = sign * radius * 0.24
            node.addChild(seed)
        case .lemon:
            for angle in [-0.6, 0, 0.6] as [CGFloat] {
                let segment = SKShapeNode()
                let path = CGMutablePath()
                path.move(to: CGPoint(x: sign * radius * 0.10, y: 0))
                path.addLine(to: CGPoint(x: sign * radius * 0.72, y: sin(angle) * radius * 0.40))
                segment.path = path
                segment.strokeColor = .white.withAlphaComponent(0.75)
                segment.lineWidth = max(2, radius * 0.028)
                node.addChild(segment)
            }
        case .grape:
            let core = SKShapeNode(ellipseOf: CGSize(width: radius * 0.42, height: radius * 0.62))
            core.fillColor = .white.withAlphaComponent(0.45)
            core.strokeColor = .clear
            core.position.x = sign * radius * 0.22
            node.addChild(core)
        case .dragonFruit:
            for (index, count) in (0..<14).enumerated() {
                let angle = Double(index) / Double(count) * .pi * 2
                let seed = SKShapeNode(ellipseOf: CGSize(width: radius * 0.035, height: radius * 0.05))
                seed.fillColor = SKColor(white: 0.10, alpha: 1)
                seed.strokeColor = .clear
                seed.position = CGPoint(
                    x: sign * cos(angle) * radius * (0.32 + 0.30 * Double(index % 3)),
                    y: sin(angle) * radius * (0.32 + 0.30 * Double((index + 1) % 3))
                )
                node.addChild(seed)
            }
        default:
            break
        }
    }

    private static func wholePath(kind: FruitKind, radius: CGFloat) -> CGPath {
        switch kind {
        case .watermelon:
            return CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        case .strawberry:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -radius))
            path.addCurve(
                to: CGPoint(x: -radius * 0.88, y: radius * 0.32),
                control1: CGPoint(x: -radius * 0.22, y: -radius * 0.62),
                control2: CGPoint(x: -radius * 0.82, y: -radius * 0.18)
            )
            path.addCurve(
                to: CGPoint(x: 0, y: radius * 0.62),
                control1: CGPoint(x: -radius * 0.92, y: radius * 0.82),
                control2: CGPoint(x: -radius * 0.35, y: radius * 0.86)
            )
            path.addCurve(
                to: CGPoint(x: radius * 0.88, y: radius * 0.32),
                control1: CGPoint(x: radius * 0.35, y: radius * 0.86),
                control2: CGPoint(x: radius * 0.92, y: radius * 0.82)
            )
            path.addCurve(
                to: CGPoint(x: 0, y: -radius),
                control1: CGPoint(x: radius * 0.82, y: -radius * 0.18),
                control2: CGPoint(x: radius * 0.22, y: -radius * 0.62)
            )
            path.closeSubpath()
            return path
        case .pineapple:
            return CGPath(
                ellipseIn: CGRect(x: -radius * 0.72, y: -radius, width: radius * 1.44, height: radius * 2),
                transform: nil
            )
        case .apple, .orange, .kiwi:
            let xScale: CGFloat = kind == .kiwi ? 0.82 : 1
            return CGPath(
                ellipseIn: CGRect(x: -radius * xScale, y: -radius, width: radius * xScale * 2, height: radius * 2),
                transform: nil
            )
        case .banana:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -radius * 0.92, y: radius * 0.34))
            path.addCurve(
                to: CGPoint(x: radius * 0.92, y: radius * 0.34),
                control1: CGPoint(x: -radius * 0.35, y: -radius * 0.98),
                control2: CGPoint(x: radius * 0.35, y: -radius * 0.98)
            )
            path.addCurve(
                to: CGPoint(x: -radius * 0.92, y: radius * 0.34),
                control1: CGPoint(x: radius * 0.30, y: -radius * 0.30),
                control2: CGPoint(x: -radius * 0.30, y: -radius * 0.30)
            )
            path.closeSubpath()
            return path
        case .peach:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: radius * 0.72))
            path.addCurve(
                to: CGPoint(x: 0, y: -radius),
                control1: CGPoint(x: -radius * 1.12, y: radius * 1.02),
                control2: CGPoint(x: -radius * 0.92, y: -radius * 0.62)
            )
            path.addCurve(
                to: CGPoint(x: 0, y: radius * 0.72),
                control1: CGPoint(x: radius * 0.92, y: -radius * 0.62),
                control2: CGPoint(x: radius * 1.12, y: radius * 1.02)
            )
            path.closeSubpath()
            return path
        case .mango:
            // A tilted, bean-shaped oval.
            var tilt = CGAffineTransform(rotationAngle: 0.5)
            return CGPath(
                ellipseIn: CGRect(x: -radius * 0.82, y: -radius * 0.62, width: radius * 1.64, height: radius * 1.24),
                transform: &tilt
            )
        case .lemon:
            return CGPath(
                ellipseIn: CGRect(x: -radius * 0.86, y: -radius * 0.60, width: radius * 1.72, height: radius * 1.20),
                transform: nil
            )
        case .grape:
            return CGPath(
                ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                transform: nil
            )
        case .dragonFruit:
            return CGPath(
                ellipseIn: CGRect(x: -radius * 0.92, y: -radius * 0.88, width: radius * 1.84, height: radius * 1.76),
                transform: nil
            )
        default:
            return CGPath(
                ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                transform: nil
            )
        }
    }

    private func addWatermelonDetails(radius: CGFloat) {
        for x in [-0.48, 0, 0.48] as [CGFloat] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: radius * x, y: -radius * 0.78))
            path.addCurve(
                to: CGPoint(x: radius * x, y: radius * 0.78),
                control1: CGPoint(x: radius * (x + 0.18), y: -radius * 0.25),
                control2: CGPoint(x: radius * (x - 0.18), y: radius * 0.25)
            )
            let stripe = SKShapeNode(path: path)
            stripe.strokeColor = SKColor(red: 0.03, green: 0.37, blue: 0.16, alpha: 0.82)
            stripe.lineWidth = max(4, radius * 0.075)
            stripe.lineCap = .round
            addChild(stripe)
        }
    }

    private func addStrawberryDetails(radius: CGFloat) {
        let seedPositions: [CGPoint] = [
            .init(x: -0.38, y: 0.28), .init(x: 0.38, y: 0.28),
            .init(x: -0.22, y: -0.05), .init(x: 0.22, y: -0.05),
            .init(x: 0, y: -0.42)
        ]
        for position in seedPositions {
            let seed = SKShapeNode(ellipseOf: CGSize(width: radius * 0.10, height: radius * 0.16))
            seed.fillColor = SKColor(red: 1, green: 0.88, blue: 0.3, alpha: 1)
            seed.strokeColor = .clear
            seed.position = CGPoint(x: position.x * radius, y: position.y * radius)
            addChild(seed)
        }
        addCrown(radius: radius, y: radius * 0.65, leafColor: .systemGreen)
    }

    private func addPineappleDetails(radius: CGFloat) {
        for offset in [-0.42, 0, 0.42] as [CGFloat] {
            for direction in [-1.0, 1.0] as [CGFloat] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -radius * 0.48, y: radius * (offset - 0.22 * direction)))
                path.addLine(to: CGPoint(x: radius * 0.48, y: radius * (offset + 0.22 * direction)))
                let line = SKShapeNode(path: path)
                line.strokeColor = SKColor(red: 0.68, green: 0.40, blue: 0.05, alpha: 0.72)
                line.lineWidth = max(2, radius * 0.035)
                addChild(line)
            }
        }
        addCrown(radius: radius, y: radius * 0.92, leafColor: SKColor(red: 0.12, green: 0.68, blue: 0.25, alpha: 1))
    }

    private func addAppleDetails(radius: CGFloat) {
        let stem = SKShapeNode(rectOf: CGSize(width: radius * 0.10, height: radius * 0.42), cornerRadius: radius * 0.04)
        stem.fillColor = SKColor(red: 0.34, green: 0.16, blue: 0.06, alpha: 1)
        stem.strokeColor = .clear
        stem.position = CGPoint(x: radius * 0.06, y: radius * 0.96)
        stem.zRotation = -0.18
        addChild(stem)
        addLeaf(radius: radius, position: CGPoint(x: radius * 0.32, y: radius * 0.92), rotation: -0.5)
    }

    private func addOrangeDetails(radius: CGFloat) {
        let dimple = SKShapeNode(circleOfRadius: radius * 0.08)
        dimple.fillColor = SKColor(red: 0.62, green: 0.26, blue: 0.02, alpha: 1)
        dimple.strokeColor = .clear
        dimple.position = CGPoint(x: 0, y: radius * 0.90)
        addChild(dimple)
        addLeaf(radius: radius, position: CGPoint(x: radius * 0.24, y: radius * 0.94), rotation: -0.42)
        for index in 0..<12 {
            let pore = SKShapeNode(circleOfRadius: max(1.5, radius * 0.018))
            pore.fillColor = SKColor(red: 0.75, green: 0.25, blue: 0.01, alpha: 0.55)
            pore.strokeColor = .clear
            let angle = CGFloat(index) * .pi * 0.62
            let distance = radius * (0.26 + CGFloat(index % 4) * 0.15)
            pore.position = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
            addChild(pore)
        }
    }

    private func addBananaDetails(radius: CGFloat) {
        let inner = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -radius * 0.64, y: radius * 0.20))
        path.addCurve(
            to: CGPoint(x: radius * 0.64, y: radius * 0.20),
            control1: CGPoint(x: -radius * 0.24, y: -radius * 0.50),
            control2: CGPoint(x: radius * 0.24, y: -radius * 0.50)
        )
        inner.path = path
        inner.strokeColor = SKColor(red: 0.76, green: 0.56, blue: 0.06, alpha: 0.72)
        inner.lineWidth = max(3, radius * 0.045)
        inner.lineCap = .round
        addChild(inner)
        for x in [-0.88, 0.88] as [CGFloat] {
            let tip = SKShapeNode(circleOfRadius: radius * 0.08)
            tip.fillColor = SKColor(red: 0.35, green: 0.22, blue: 0.05, alpha: 1)
            tip.strokeColor = .clear
            tip.position = CGPoint(x: radius * x, y: radius * 0.34)
            addChild(tip)
        }
    }

    private func addKiwiDetails(radius: CGFloat) {
        for index in 0..<18 {
            let hair = SKShapeNode()
            let angle = CGFloat(index) * (.pi * 2 / 18)
            let path = CGMutablePath()
            let start = CGPoint(x: cos(angle) * radius * 0.82, y: sin(angle) * radius * 0.94)
            path.move(to: start)
            path.addLine(to: CGPoint(x: start.x + cos(angle) * radius * 0.10, y: start.y + sin(angle) * radius * 0.10))
            hair.path = path
            hair.strokeColor = SKColor(red: 0.23, green: 0.12, blue: 0.05, alpha: 0.7)
            hair.lineWidth = max(1, radius * 0.012)
            addChild(hair)
        }
    }

    private func addPeachDetails(radius: CGFloat) {
        let groove = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: radius * 0.66))
        path.addCurve(
            to: CGPoint(x: radius * 0.08, y: -radius * 0.72),
            control1: CGPoint(x: -radius * 0.18, y: radius * 0.25),
            control2: CGPoint(x: radius * 0.20, y: -radius * 0.18)
        )
        groove.path = path
        groove.strokeColor = SKColor(red: 0.72, green: 0.16, blue: 0.16, alpha: 0.72)
        groove.lineWidth = max(3, radius * 0.04)
        groove.lineCap = .round
        addChild(groove)
        addLeaf(radius: radius, position: CGPoint(x: radius * 0.22, y: radius * 0.82), rotation: -0.52)
    }

    private func addMangoDetails(radius: CGFloat) {
        let blush = SKShapeNode(ellipseOf: CGSize(width: radius * 0.72, height: radius * 0.56))
        blush.fillColor = SKColor(red: 0.94, green: 0.32, blue: 0.10, alpha: 0.5)
        blush.strokeColor = .clear
        blush.position = CGPoint(x: radius * 0.30, y: -radius * 0.06)
        blush.zRotation = 0.5
        addChild(blush)
        addLeaf(radius: radius, position: CGPoint(x: -radius * 0.58, y: radius * 0.42), rotation: -0.9)
    }

    private func addLemonDetails(radius: CGFloat) {
        for direction in [-1.0, 1.0] as [CGFloat] {
            let tip = SKShapeNode(ellipseOf: CGSize(width: radius * 0.22, height: radius * 0.36))
            tip.fillColor = rindColor
            tip.strokeColor = .clear
            tip.position = CGPoint(x: direction * radius * 0.78, y: 0)
            addChild(tip)
        }
        for position in [CGPoint(x: 0.34, y: 0.20), .init(x: -0.10, y: -0.28), .init(x: -0.42, y: 0.16)] {
            let dimple = SKShapeNode(circleOfRadius: max(1.5, radius * 0.022))
            dimple.fillColor = .white.withAlphaComponent(0.5)
            dimple.strokeColor = .clear
            dimple.position = CGPoint(x: position.x * radius, y: position.y * radius)
            addChild(dimple)
        }
    }

    private func addGrapeDetails(radius: CGFloat) {
        // A loose cluster: side berries behind the main body edge.
        for position in [CGPoint(x: -0.62, y: 0.52), .init(x: 0.62, y: 0.48), .init(x: 0.20, y: 0.80)] {
            let berry = SKShapeNode(circleOfRadius: radius * 0.40)
            berry.fillColor = rindColor
            berry.strokeColor = .clear
            berry.position = CGPoint(x: position.x * radius, y: position.y * radius)
            berry.zPosition = -1
            addChild(berry)
        }
        let stem = SKShapeNode(rectOf: CGSize(width: radius * 0.08, height: radius * 0.30), cornerRadius: radius * 0.03)
        stem.fillColor = SKColor(red: 0.30, green: 0.20, blue: 0.06, alpha: 1)
        stem.strokeColor = .clear
        stem.position = CGPoint(x: 0, y: radius * 0.94)
        addChild(stem)
    }

    private func addDragonFruitDetails(radius: CGFloat) {
        // Green scale flames around the upper edge.
        for (index, count) in (0..<9).enumerated() {
            let angle = .pi * (0.15 + 0.77 * Double(index) / Double(count - 1))
            let scale = SKShapeNode()
            let path = CGMutablePath()
            let baseX = cos(angle) * radius * 0.80
            let baseY = sin(angle) * radius * 0.76
            let tipX = cos(angle) * radius * 1.16
            let tipY = sin(angle) * radius * 1.12
            path.move(to: CGPoint(x: baseX - radius * 0.10, y: baseY - radius * 0.08))
            path.addLine(to: CGPoint(x: tipX, y: tipY))
            path.addLine(to: CGPoint(x: baseX + radius * 0.10, y: baseY + radius * 0.08))
            path.closeSubpath()
            scale.path = path
            scale.fillColor = SKColor(red: 0.30, green: 0.74, blue: 0.24, alpha: 0.92)
            scale.strokeColor = .clear
            addChild(scale)
        }
    }

    private var rindColor: SKColor { Self.rindColor(for: kind) }

    private func addLeaf(radius: CGFloat, position: CGPoint, rotation: CGFloat) {
        let leaf = SKShapeNode(ellipseOf: CGSize(width: radius * 0.52, height: radius * 0.20))
        leaf.fillColor = SKColor(red: 0.12, green: 0.62, blue: 0.22, alpha: 1)
        leaf.strokeColor = SKColor(red: 0.04, green: 0.34, blue: 0.10, alpha: 1)
        leaf.lineWidth = max(2, radius * 0.02)
        leaf.position = position
        leaf.zRotation = rotation
        addChild(leaf)
    }

    private func addCrown(radius: CGFloat, y: CGFloat, leafColor: SKColor) {
        for angle in [-0.7, -0.34, 0, 0.34, 0.7] as [CGFloat] {
            let leaf = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y - radius * 0.12))
            path.addLine(to: CGPoint(x: sin(angle) * radius * 0.54, y: y + cos(angle) * radius * 0.58))
            path.addLine(to: CGPoint(x: sin(angle) * radius * 0.12, y: y + radius * 0.04))
            path.closeSubpath()
            leaf.path = path
            leaf.fillColor = leafColor
            leaf.strokeColor = leafColor.withAlphaComponent(0.8)
            leaf.lineWidth = 2
            addChild(leaf)
        }
    }
}

/// Old private copy, superseded by SoundEffects.swift. Renamed so both can
/// coexist until GameScene.swift is deleted after the SceneKit acceptance.
@MainActor
private final class GameSceneSoundEffects {
    private static let logger = Logger(subsystem: "com.example.FruitWave", category: "Audio")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// Pitch-ordered slice variants; higher indexes sound brighter and are
    /// picked as the combo grows, with the fruit kind shifting the starting
    /// point so consecutive slices don't sound like one looped clip.
    private let sliceBuffers: [AVAudioPCMBuffer]

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        sliceBuffers = Self.makeSliceBuffers(format: format, variantCount: 6)
        engine.attach(player)
        if let format { engine.connect(player, to: engine.mainMixerNode, format: format) }
        player.volume = 0.85
        engine.prepare()
        _ = ensureAudioReady()
    }

    func playSlice(kind: FruitKind, combo: Int) {
        guard !sliceBuffers.isEmpty, ensureAudioReady() else { return }
        let kindOffset = abs(kind.hashValue % 2)
        let index = min(sliceBuffers.count - 1, kindOffset + max(0, combo - 1))
        player.scheduleBuffer(sliceBuffers[index], at: nil, options: .interrupts)
        player.play()
    }

    /// Preview blip when the player toggles sound on.
    func playPreview() {
        guard !sliceBuffers.isEmpty, ensureAudioReady() else { return }
        player.scheduleBuffer(sliceBuffers[sliceBuffers.count / 2], at: nil, options: .interrupts)
        player.play()
    }

    @discardableResult
    private func ensureAudioReady() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            return engine.isRunning
        } catch {
            Self.logger.error("Unable to start game audio: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func makeSliceBuffers(format: AVAudioFormat?, variantCount: Int) -> [AVAudioPCMBuffer] {
        guard let format else { return [] }
        let frameCount = AVAudioFrameCount(format.sampleRate * 0.16)
        var buffers: [AVAudioPCMBuffer] = []
        for variant in 0..<variantCount {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                  let channels = buffer.floatChannelData else { continue }
            buffer.frameLength = frameCount
            let pitch = 0.8 + 0.14 * Double(variant)
            var sweepPhase = 0.0
            var thumpPhase = 0.0
            var noiseState: UInt64 = 0xF17A_5EED &+ UInt64(variant) &* 0x9E37_79B9
            for index in 0..<Int(frameCount) {
                let progress = Double(index) / Double(frameCount)
                let sweepFrequency = (1_520 - 1_050 * progress) * pitch
                sweepPhase += 2 * .pi * sweepFrequency / format.sampleRate
                let thumpFrequency = 118 + 46 * (1 - progress)
                thumpPhase += 2 * .pi * thumpFrequency / format.sampleRate
                noiseState = noiseState &* 6_364_136_223_846_793_005 &+ 1
                let noise = Double(Int64(bitPattern: noiseState) >> 40) / Double(1 << 23)
                let attack = min(1, progress / 0.02)
                let body = attack * exp(-7.5 * progress)
                // Three layers: pitch-swept tone, ripping noise, low onset
                // thump — reads as a wet cut instead of a bare beep.
                let tone = sin(sweepPhase) * 0.30
                let rip = noise * (1 - progress) * 0.16
                let thump = sin(thumpPhase) * exp(-34 * progress) * 0.34
                let sample = Float((tone + rip + thump) * body)
                for channel in 0..<Int(format.channelCount) {
                    channels[channel][index] = channel == 0 ? sample : sample * 0.92
                }
            }
            buffers.append(buffer)
        }
        return buffers
    }
}
