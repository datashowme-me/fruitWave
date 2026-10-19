import SceneKit
import SpriteKit
import SwiftUI

/// Hosts the 3D fruit stage with the 2D HUD layered on top.
/// `overlaySKScene` is macOS-only, so on tvOS the HUD is a transparent SKView
/// stacked above the SCNView (allowsTransparency). Continuous rendering and
/// isPlaying are mandatory: SCNView sleeps when nothing animates, and the
/// game clock is driven by the stage's CADisplayLink while this view is
/// mounted.
struct SceneKitGameView: UIViewRepresentable {
    let renderer: GameRenderer

    final class Coordinator {
        let renderer: GameRenderer
        init(renderer: GameRenderer) { self.renderer = renderer }
    }

    func makeCoordinator() -> Coordinator { Coordinator(renderer: renderer) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)

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

        skView.presentScene(renderer.hud)
        renderer.stage.startFrameDriver()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Break the views' references so the model-owned stage and HUD can
        // outlive this view instance (PlayingView recreates the view on
        // every mount).
        guard let scnView = uiView.subviews.compactMap({ $0 as? SCNView }).first,
              let skView = uiView.subviews.compactMap({ $0 as? SKView }).first else { return }
        coordinator.renderer.stage.stopFrameDriver()
        scnView.scene = nil
        skView.presentScene(nil)
    }
}
