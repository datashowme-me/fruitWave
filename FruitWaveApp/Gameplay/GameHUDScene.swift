import FruitWaveCore
import SpriteKit

/// Transparent 2D overlay rendered on top of the 3D fruit stage
/// (SCNView.overlaySKScene). Owns the hand cursor, slash trails, impact ring
/// and combo label — ported from the old GameScene's HUD sections. Per-frame
/// cursor interpolation is driven from the 3D stage's renderer delegate via
/// `updateCursor(at:)`, not from this scene's own `update(_:)`.
@MainActor
final class GameHUDScene: SKScene {
    var reduceMotion = false

    private var trailPool: [SKShapeNode] = []
    private let handNode = SKShapeNode(circleOfRadius: 13)
    private let trailLayer = SKNode()
    private let effectsLayer = SKNode()
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    // The newest hand samples in scene space, used to interpolate the cursor
    // at the 60 Hz scene rate instead of the ~30 Hz pose-sample rate.
    private var handSamples: [(time: TimeInterval, point: CGPoint)] = []

    override init(size: CGSize = CGSize(width: 1920, height: 1080)) {
        super.init(size: size)
        scaleMode = .resizeFill
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// didMove fires on every (re)present — the host SKView detaches the
    /// scene on view dismantle and presents it again on remount. The node
    /// tree must be built once; re-adding a parented node throws an
    /// NSException in SpriteKit.
    private var didBuildTree = false

    override func didMove(to view: SKView) {
        guard !didBuildTree else { return }
        didBuildTree = true
        backgroundColor = .clear
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

    // MARK: - Hand cursor

    func pushHandSample(_ point: CGPoint, now: TimeInterval) {
        handNode.isHidden = false
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
    }

    func clearHand() {
        handNode.isHidden = true
        handSamples.removeAll()
    }

    /// Places the hand cursor between the two newest samples and extrapolates
    /// a short distance ahead of the newest one, so the cursor follows the
    /// real hand instead of trailing the pose pipeline by a sample.
    func updateCursor(at now: TimeInterval) {
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

    // MARK: - Slash trails

    func drawSlash(from start: CGPoint, to end: CGPoint) {
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

    private func recycleTrail(_ node: SKShapeNode) {
        node.removeFromParent()
        node.path = nil
        if trailPool.count < 32, !trailPool.contains(where: { $0 === node }) { trailPool.append(node) }
    }

    // MARK: - Impact ring and combo label

    func spawnRing(at position: CGPoint, kind: FruitKind, radius: CGFloat) {
        let juiceColor = SKColor(
            red: CGFloat(FruitVisualData.spec(for: kind).flesh.r),
            green: CGFloat(FruitVisualData.spec(for: kind).flesh.g),
            blue: CGFloat(FruitVisualData.spec(for: kind).flesh.b),
            alpha: 1
        )
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
    }

    func showCombo(count: Int, at position: CGPoint, radius: CGFloat) {
        comboLabel.removeAllActions()
        comboLabel.isHidden = false
        comboLabel.alpha = 1
        comboLabel.setScale(0.65)
        comboLabel.position = CGPoint(x: position.x, y: min(size.height - 80, position.y + radius * 1.35))
        comboLabel.text = count >= 2 ? "\(count) 连击！" : "+10"
        comboLabel.fontColor = count >= 3 ? .systemYellow : .white
        comboLabel.run(.sequence([
            .group([.scale(to: 1.15, duration: 0.10), .moveBy(x: 0, y: 18, duration: 0.10)]),
            .wait(forDuration: 0.22),
            .group([.fadeOut(withDuration: 0.18), .moveBy(x: 0, y: 34, duration: 0.18)]),
            .hide()
        ]))
    }

    /// Clears trails and hides the combo label. Combo *counting* lives in the
    /// 3D stage (it owns lastHitGameTime); this only resets visuals.
    func clearTrail() {
        for case let node as SKShapeNode in trailLayer.children {
            node.removeAllActions()
            recycleTrail(node)
        }
        comboLabel.removeAllActions()
        comboLabel.isHidden = true
    }
}
