import SpriteKit
import FruitWaveCore

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
    private var fruitNodes: [UUID: SKShapeNode] = [:]
    private let handNode = SKShapeNode(circleOfRadius: 13)
    private let trailLayer = SKNode()

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.025, green: 0.04, blue: 0.085, alpha: 1)
        scaleMode = .resizeFill
        handNode.fillColor = .white
        handNode.strokeColor = .cyan
        handNode.lineWidth = 5
        handNode.glowWidth = 8
        handNode.isHidden = true
        addChild(trailLayer)
        addChild(handNode)
    }

    override func update(_ currentTime: TimeInterval) { onTick?(ProcessInfo.processInfo.systemUptime) }

    func render(_ snapshot: Snapshot) {
        let activeIDs = Set(snapshot.fruits.filter { $0.state == .active }.map(\.id))
        for (id, node) in fruitNodes where !activeIDs.contains(id) {
            node.removeFromParent(); fruitNodes[id] = nil
        }
        for fruit in snapshot.fruits where fruit.state == .active {
            let node = fruitNodes[fruit.id] ?? makeFruitNode(fruit)
            node.position = scenePoint(fruit.position(at: snapshot.gameTime))
            fruitNodes[fruit.id] = node
        }
        if let hand = snapshot.hand {
            handNode.isHidden = false
            handNode.position = scenePoint(hand)
        } else {
            handNode.isHidden = true
        }
        if let slash = snapshot.slash { drawTrail(from: scenePoint(slash.startPosition), to: scenePoint(slash.endPosition)) }
        for hit in snapshot.hits { animateSlice(id: hit.fruitID) }
    }

    func clearTrail() { trailLayer.removeAllChildren() }

    private func makeFruitNode(_ fruit: Fruit) -> SKShapeNode {
        let radius = max(24, size.width * fruit.radius)
        let node = SKShapeNode(circleOfRadius: radius)
        switch fruit.kind {
        case .watermelon: node.fillColor = .systemGreen
        case .strawberry: node.fillColor = .systemPink
        case .pineapple: node.fillColor = .systemYellow
        }
        node.strokeColor = .white.withAlphaComponent(0.75)
        node.lineWidth = 4
        addChild(node)
        return node
    }

    private func animateSlice(id: UUID) {
        guard let original = fruitNodes.removeValue(forKey: id) else { return }
        let color = original.fillColor
        let position = original.position
        original.removeFromParent()
        for direction in [-1.0, 1.0] {
            let half = SKShapeNode(rectOf: CGSize(width: original.frame.width * 0.42, height: original.frame.height * 0.9), cornerRadius: 14)
            half.fillColor = color; half.strokeColor = .white; half.position = position
            addChild(half)
            half.run(.sequence([.group([.moveBy(x: 90 * direction, y: -110, duration: 0.42), .rotate(byAngle: direction * 1.4, duration: 0.42), .fadeOut(withDuration: 0.42)]), .removeFromParent()]))
        }
    }

    private func drawTrail(from start: CGPoint, to end: CGPoint) {
        let path = CGMutablePath(); path.move(to: start); path.addLine(to: end)
        let node = SKShapeNode(path: path)
        node.strokeColor = .cyan; node.lineWidth = 16; node.lineCap = .round; node.glowWidth = 12; node.blendMode = .add
        trailLayer.addChild(node)
        node.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
    }

    private func scenePoint(_ point: Vector2) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.width)
    }
}
