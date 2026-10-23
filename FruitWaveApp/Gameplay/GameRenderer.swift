import CoreGraphics
import Foundation
import FruitWaveCore

/// Facade over the 3D fruit stage and the 2D HUD overlay. AppModel talks only
/// to this type; Snapshot's member names and order mirror the old
/// GameScene.Snapshot exactly, so the AppModel call sites change by receiver
/// alone.
@MainActor
final class GameRenderer {
    struct Snapshot {
        let fruits: [Fruit]
        let gameTime: TimeInterval
        let score: Int
        let hand: Vector2?
        /// Capture time (monotonic clock) of the frame the hand came from —
        /// lets the HUD cursor compensate the network+inference pipeline age.
        let handCapturedAt: TimeInterval?
        let slash: SlashSegment?
        let hits: [HitEvent]
    }

    let stage: FruitStage3D
    let hud: GameHUDScene

    init(size: CGSize) {
        let hud = GameHUDScene(size: size)
        self.hud = hud
        self.stage = FruitStage3D(size: size, hud: hud)
        // Compile shaders/pipelines now (app launch) instead of on the first
        // in-game draw, where the stall trips the camera-frame watchdog.
        stage.prewarm()
    }

    var onTick: ((TimeInterval) -> Void)? {
        get { stage.onTick }
        set { stage.onTick = newValue }
    }

    var soundEnabled: Bool {
        get { stage.soundEnabled }
        set { stage.soundEnabled = newValue }
    }

    /// Points shown per sliced fruit popup; kept in sync with the gameplay
    /// engine configuration by AppModel.
    var pointsPerSlice: Int {
        get { stage.pointsPerSlice }
        set { stage.pointsPerSlice = newValue }
    }

    /// Routes to both layers: the stage (juice rates, slice animation) and
    /// the HUD (trail and ring durations).
    var reduceMotion: Bool {
        get { stage.reduceMotion }
        set {
            stage.reduceMotion = newValue
            hud.reduceMotion = newValue
        }
    }

    func render(_ snapshot: Snapshot) {
        stage.render(snapshot)
    }

    func clearTrail() {
        stage.clearTrail()
        hud.clearTrail()
    }
}
