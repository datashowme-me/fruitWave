import SceneKit
import SpriteKit
import SwiftUI
import UIKit

/// Hosts the 3D fruit stage with the 2D HUD layered on top.
/// `overlaySKScene` is macOS-only, so on tvOS the HUD is a transparent SKView
/// stacked above the SCNView (allowsTransparency). Continuous rendering and
/// isPlaying are mandatory: SCNView sleeps when nothing animates, and the
/// game clock is driven by the stage's CADisplayLink while this view is
/// mounted.
/// Also supports Siri Remote clickpad pan gestures for sofa/controller play.
struct SceneKitGameView: UIViewRepresentable {
    let renderer: GameRenderer
    var onPanSlash: ((CGPoint, CGPoint) -> Void)? = nil

    final class Coordinator: NSObject {
        let renderer: GameRenderer
        var onPanSlash: ((CGPoint, CGPoint) -> Void)?
        private var previousLocation: CGPoint?

        init(renderer: GameRenderer, onPanSlash: ((CGPoint, CGPoint) -> Void)?) {
            self.renderer = renderer
            self.onPanSlash = onPanSlash
            super.init()
        }

        @objc func handleRemotePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began:
                previousLocation = point
            case .changed:
                if let prev = previousLocation {
                    let dist = hypot(point.x - prev.x, point.y - prev.y)
                    if dist > 14 {
                        onPanSlash?(prev, point)
                    }
                }
                previousLocation = point
            case .ended, .cancelled:
                previousLocation = nil
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, onPanSlash: onPanSlash)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.isUserInteractionEnabled = true

        let scnView = SCNView(frame: .zero)
        scnView.translatesAutoresizingMaskIntoConstraints = false
        let skView = SKView(frame: .zero)
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.allowsTransparency = true
        skView.isUserInteractionEnabled = false
        container.addSubview(scnView)
        container.addSubview(skView)
        NSLayoutConstraint.activate([
            scnView.topAnchor.constraint(equalTo: container.topAnchor),
            scnView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scnView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            skView.topAnchor.constraint(equalTo: container.topAnchor),
            skView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            skView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            skView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        scnView.scene = renderer.stage.scene
        scnView.pointOfView = renderer.stage.cameraNode
        scnView.isPlaying = true
        scnView.rendersContinuously = true
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .none
        #if DEBUG
        scnView.showsStatistics = true
        #endif

        // Siri Remote Clickpad Pan Gesture Recognizer
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRemotePan(_:)))
        container.addGestureRecognizer(pan)

        skView.presentScene(renderer.hud)
        renderer.stage.startFrameDriver()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPanSlash = onPanSlash
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        guard let scnView = uiView.subviews.compactMap({ $0 as? SCNView }).first,
              let skView = uiView.subviews.compactMap({ $0 as? SKView }).first else { return }
        coordinator.renderer.stage.stopFrameDriver()
        scnView.scene = nil
        skView.presentScene(nil)
    }
}
