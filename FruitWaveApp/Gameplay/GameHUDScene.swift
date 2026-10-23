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
    // The newest hand samples in scene space, used to extrapolate the cursor
    // at the 60 Hz scene rate instead of the ~30 Hz pose-sample rate.
    private struct HandSample {
        let point: CGPoint
        /// Capture time on the phone (monotonic clock, shared with the TV) —
        /// stable even when network delivery jitters, so velocity estimates
        /// from it don't jump.
        let capturedAt: TimeInterval
    }
    private var handSamples: [HandSample] = []

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

    func pushHandSample(_ point: CGPoint, capturedAt: TimeInterval, now: TimeInterval) {
        handNode.isHidden = false
        let sample = HandSample(point: point, capturedAt: capturedAt)
        if let last = handSamples.last {
            if last.point != point {
                handSamples = [last, sample]
            } else {
                // Stationary hand: stop extrapolating and hold in place.
                handSamples = [sample]
            }
        } else {
            handSamples = [sample]
        }
    }

    func clearHand() {
        handNode.isHidden = true
        handSamples.removeAll()
    }

    /// Extrapolates the newest sample forward by the age of the pose pipeline
    /// (capture on the phone → network → Vision → render). Velocity is
    /// measured on capture times, so network jitter doesn't inject jumps;
    /// the look-ahead is capped to bound error when the hand reverses.
    func updateCursor(at now: TimeInterval) {
        guard !handNode.isHidden, let latest = handSamples.last else { return }
        guard handSamples.count > 1, let previous = handSamples.first else {
            handNode.position = latest.point
            return
        }
        let interval = latest.capturedAt - previous.capturedAt
        guard interval > 0, interval < 0.25 else {
            handNode.position = latest.point
            return
        }
        let velocity = CGPoint(
            x: (latest.point.x - previous.point.x) / CGFloat(interval),
            y: (latest.point.y - previous.point.y) / CGFloat(interval)
        )
        let age = now - latest.capturedAt
        let ahead = min(max(age, 0), 0.11)
        handNode.position = CGPoint(
            x: latest.point.x + velocity.x * CGFloat(ahead),
            y: latest.point.y + velocity.y * CGFloat(ahead)
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

    // MARK: - Cut flash

    private var cutFlashPool: [SKShapeNode] = []

    /// One-frame white blade flash along the cut direction at the contact
    /// point — the "impact moment" of every slice.
    func spawnCutFlash(at point: CGPoint, direction: CGPoint) {
        let length = hypot(direction.x, direction.y)
        let dx = length > 0.000_1 ? direction.x / length : 1
        let dy = length > 0.000_1 ? direction.y / length : 0
        let node = cutFlashPool.popLast() ?? SKShapeNode()
        node.removeAllActions()
        node.path = nil
        let path = CGMutablePath()
        path.move(to: CGPoint(x: point.x - dx * 46, y: point.y - dy * 46))
        path.addLine(to: CGPoint(x: point.x + dx * 46, y: point.y + dy * 46))
        node.path = path
        node.strokeColor = .white
        node.lineWidth = 9
        node.lineCap = .round
        node.glowWidth = 22
        node.blendMode = .add
        node.alpha = 1
        effectsLayer.addChild(node)
        node.run(.fadeOut(withDuration: reduceMotion ? 0.07 : 0.13)) { [weak self, weak node] in
            guard let self, let node, node.parent != nil else { return }
            self.recycleCutFlash(node)
        }
    }

    private func recycleCutFlash(_ node: SKShapeNode) {
        node.removeFromParent()
        node.path = nil
        if cutFlashPool.count < 8, !cutFlashPool.contains(where: { $0 === node }) { cutFlashPool.append(node) }
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

    /// Combo announcement (2+ chain). The per-hit "+N" score popup is a
    /// separate pooled label so a multi-fruit slash shows one per fruit.
    func showCombo(count: Int, at position: CGPoint, radius: CGFloat) {
        guard count >= 2 else { return }
        comboLabel.removeAllActions()
        comboLabel.isHidden = false
        comboLabel.alpha = 1
        comboLabel.setScale(0.65)
        comboLabel.position = CGPoint(x: position.x, y: min(size.height - 80, position.y + radius * 1.35))
        comboLabel.text = "\(count) 连击！"
        comboLabel.fontColor = count >= 5 ? .systemOrange : (count >= 3 ? .systemYellow : .white)
        comboLabel.run(.sequence([
            .group([.scale(to: 1.15, duration: 0.10), .moveBy(x: 0, y: 18, duration: 0.10)]),
            .wait(forDuration: 0.22),
            .group([.fadeOut(withDuration: 0.18), .moveBy(x: 0, y: 34, duration: 0.18)]),
            .hide()
        ]))
        if count >= 3 { pulseCombo() }
    }

    private var scorePopupPool: [SKLabelNode] = []

    /// Per-fruit "+N" popup floating up from the blade contact point.
    func showScorePopup(at point: CGPoint, points: Int) {
        let label = scorePopupPool.popLast() ?? SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.removeAllActions()
        label.isHidden = false
        label.alpha = 1
        label.setScale(0.7)
        label.position = point
        label.text = "+\(points)"
        label.fontSize = 36
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        effectsLayer.addChild(label)
        label.run(.sequence([
            .group([.scale(to: 1.12, duration: 0.09), .moveBy(x: 0, y: 24, duration: 0.09)]),
            .group([.fadeOut(withDuration: 0.30), .moveBy(x: 0, y: 62, duration: 0.30)])
        ])) { [weak self, weak label] in
            guard let self, let label, label.parent != nil else { return }
            self.recyclePopup(label)
        }
    }

    private func recyclePopup(_ label: SKLabelNode) {
        label.removeFromParent()
        if scorePopupPool.count < 6, !scorePopupPool.contains(where: { $0 === label }) {
            scorePopupPool.append(label)
        }
    }

    /// Bomb shockwave: a filled additive disc slamming outward from the blast
    /// point plus the full-screen combo pulse.
    func spawnBombFlash(at point: CGPoint) {
        let ring = SKShapeNode(circleOfRadius: 46)
        ring.position = point
        ring.fillColor = .white
        ring.strokeColor = .clear
        ring.glowWidth = reduceMotion ? 0 : 26
        ring.blendMode = .add
        ring.alpha = 0.85
        effectsLayer.addChild(ring)
        ring.run(.group([
            .scale(to: 7, duration: reduceMotion ? 0.22 : 0.38),
            .fadeOut(withDuration: reduceMotion ? 0.22 : 0.38)
        ])) { [weak ring] in ring?.removeFromParent() }
        pulseCombo()
    }

    private var pulseNodes: [SKShapeNode] = []

    /// Full-screen additive flash on 3+ combos — the screen itself reacts.
    private func pulseCombo() {
        let node = pulseNodes.popLast() ?? SKShapeNode(rectOf: CGSize(width: 1920, height: 1080))
        node.removeAllActions()
        node.fillColor = .white
        node.strokeColor = .clear
        node.blendMode = .add
        node.alpha = reduceMotion ? 0.06 : 0.11
        node.position = CGPoint(x: 960, y: 540)
        effectsLayer.addChild(node)
        node.run(.fadeOut(withDuration: reduceMotion ? 0.18 : 0.30)) { [weak self, weak node] in
            guard let self, let node, node.parent != nil else { return }
            self.recyclePulse(node)
        }
    }

    private func recyclePulse(_ node: SKShapeNode) {
        node.removeFromParent()
        if pulseNodes.count < 2, !pulseNodes.contains(where: { $0 === node }) {
            pulseNodes.append(node)
        }
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
