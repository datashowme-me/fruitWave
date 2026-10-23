import Combine
import RealityKit
import SwiftUI
import UIKit

/// Isolated RealityKit acceptance surface for the Blender asset pipeline.
/// It intentionally does not touch camera or gameplay state: each fruit must
/// first pass lighting, rotation, authored-cut and device-performance review.
/// The fruit under review is selected by FW_FRUIT=<slug> (default apple).
@available(tvOS 26.0, *)
struct FruitAssetLabView: View {
    let dismiss: () -> Void
    private let fruit = AssetFruit.current
    @State private var showsSlicedAsset = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case toggle, close }

    var body: some View {
        ZStack(alignment: .bottom) {
            RealityKitFruitView(fruit: fruit, showsSlicedAsset: showsSlicedAsset)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text(showsSlicedAsset ? "\(fruit.chineseName)预制切面 · 两半分离" : "\(fruit.chineseName)完整 · 360°旋转")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                Text("Blender Python → USDZ → RealityKit 真机验收")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 22) {
                    Button(showsSlicedAsset ? "查看完整\(fruit.chineseName)" : "模拟切开") {
                        showsSlicedAsset.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .focused($focusedControl, equals: .toggle)
                    Button("返回", action: dismiss)
                        .focused($focusedControl, equals: .close)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .defaultFocus($focusedControl, .toggle)
        .onExitCommand(perform: dismiss)
    }
}

/// Which fruit the lab reviews; resolved from the launch environment so one
/// build covers every fruit in the asset pipeline.
struct AssetFruit {
    let slug: String
    let title: String
    let chineseName: String

    static let current: AssetFruit = {
        let slug = ProcessInfo.processInfo.environment["FW_FRUIT"] ?? "apple"
        let title = slug.split(separator: "_").map { $0.capitalized }.joined()
        let names: [String: String] = [
            "apple": "苹果", "orange": "橙子", "lemon": "柠檬", "banana": "香蕉",
            "watermelon": "西瓜", "kiwi": "猕猴桃", "strawberry": "草莓", "grape": "葡萄",
            "cherry": "樱桃", "peach": "桃子", "plum": "李子", "pear": "梨",
            "mango": "芒果", "pineapple": "菠萝", "coconut": "椰子", "cantaloupe": "哈密瓜",
            "blueberry": "蓝莓", "persimmon": "柿子", "pomegranate": "石榴",
            "dragon_fruit": "火龙果",
        ]
        return AssetFruit(slug: slug, title: title, chineseName: names[slug] ?? title)
    }()
}

@available(tvOS 26.0, *)
private struct RealityKitFruitView: UIViewRepresentable {
    let fruit: AssetFruit
    let showsSlicedAsset: Bool

    final class Coordinator {
        var whole: Entity?
        var sliced: Entity?
        var rotatingRoot: Entity?
        var sceneUpdate: Cancellable?
        var lastRequestedSlicedState = false
        // Acceptance sampling, active only under --asset-snapshots.
        var fpsUpdates = 0
        var fpsSeconds: Double = 0
        var fpsReported = false
        var peakResidentMB: Int64 = 0
        var snapshotsWritten = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.environment.background = ARView.Environment.Background.color(
            UIColor(red: 0.014, green: 0.020, blue: 0.044, alpha: 1)
        )

        let anchor = AnchorEntity(world: .zero)
        view.scene.addAnchor(anchor)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 34
        camera.position = [0, 0.20, 5.8]
        camera.look(at: [0, 0.10, 0], from: camera.position, relativeTo: anchor)
        anchor.addChild(camera)

        // Lab staging is tuned to the gameplay look (FruitStage3D: warm key
        // ~950 + ambient ~240 in SceneKit units), not to Blender's EEVEE.
        // An over-bright or cool fill washes the fruit toward orange/gray.
        let key = DirectionalLight()
        key.light.intensity = 3_000
        key.light.color = UIColor(red: 1.0, green: 0.93, blue: 0.86, alpha: 1)
        key.look(at: [0, 0, 0], from: [-3.2, 3.8, 4.2], relativeTo: anchor)
        anchor.addChild(key)

        let fill = PointLight()
        fill.light.intensity = 1_000
        fill.light.attenuationRadius = 8
        fill.light.color = UIColor(red: 0.85, green: 0.80, blue: 0.72, alpha: 1)
        fill.position = [3.0, 1.2, 2.8]
        anchor.addChild(fill)

        let rotatingRoot = Entity()
        rotatingRoot.name = "\(fruit.slug)_acceptance_root"
        rotatingRoot.scale = [0.62, 0.62, 0.62]
        anchor.addChild(rotatingRoot)
        context.coordinator.rotatingRoot = rotatingRoot

        do {
            let whole = try Entity.load(contentsOf: Self.assetURL(fruit: fruit, name: "\(fruit.slug)_whole"))
            let sliced = try Entity.load(contentsOf: Self.assetURL(fruit: fruit, name: "\(fruit.slug)_sliced"))
            whole.name = "whole_asset"
            sliced.name = "sliced_asset"
            sliced.isEnabled = false
            let separation = Self.halfSeparation(fruit: fruit)
            if let left = sliced.findEntity(named: "\(fruit.slug)_half_left") {
                left.position.x -= separation
                left.orientation = simd_quatf(angle: -0.30, axis: [0, 0, 1])
            }
            if let right = sliced.findEntity(named: "\(fruit.slug)_half_right") {
                right.position.x += separation
                right.orientation = simd_quatf(angle: 0.30, axis: [0, 0, 1])
            }
            rotatingRoot.addChild(whole)
            rotatingRoot.addChild(sliced)
            context.coordinator.whole = whole
            context.coordinator.sliced = sliced
        } catch {
            assertionFailure("Unable to load authored \(fruit.slug) USDZ assets: \(error)")
        }

        context.coordinator.sceneUpdate = view.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator = context.coordinator] (event: SceneEvents.Update) in
            guard let root = coordinator?.rotatingRoot else { return }
            let turn = simd_quatf(angle: Float(event.deltaTime) * 0.42, axis: [0, 1, 0])
            root.orientation = turn * root.orientation
            if let coordinator, Self.acceptsSnapshots, !coordinator.fpsReported {
                coordinator.fpsUpdates += 1
                coordinator.fpsSeconds += Double(event.deltaTime)
                if coordinator.fpsSeconds >= 12 {
                    coordinator.fpsReported = true
                    Self.sampleMemory(coordinator)
                    let report = String(format: "ASSET_FPS_SAMPLE updates=%d seconds=%.2f fps=%.1f residentMB=%lld\n",
                                        coordinator.fpsUpdates, coordinator.fpsSeconds,
                                        Double(coordinator.fpsUpdates) / coordinator.fpsSeconds,
                                        coordinator.peakResidentMB)
                    print(report)
                    Self.appendEvidence(report)
                }
            }
        }
        applyVisibility(context.coordinator)
        if Self.acceptsSnapshots {
            Self.scheduleAcceptanceSnapshots(view: view, fruit: fruit, coordinator: context.coordinator)
        }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        applyVisibility(context.coordinator)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.sceneUpdate?.cancel()
        coordinator.sceneUpdate = nil
        coordinator.rotatingRoot?.removeFromParent()
    }

    private func applyVisibility(_ coordinator: Coordinator) {
        coordinator.lastRequestedSlicedState = showsSlicedAsset
        coordinator.whole?.isEnabled = !showsSlicedAsset
        coordinator.sliced?.isEnabled = showsSlicedAsset
    }

    private static func assetURL(fruit: AssetFruit, name: String) throws -> URL {
        if let nested = Bundle.main.url(
            forResource: name,
            withExtension: "usdz",
            subdirectory: "Models/\(fruit.title)"
        ) {
            return nested
        }
        if let flattened = Bundle.main.url(forResource: name, withExtension: "usdz") {
            return flattened
        }
        throw AssetError.missing(name)
    }

    private static func halfSeparation(fruit: AssetFruit) -> Float {
        let candidates = [
            Bundle.main.url(forResource: fruit.slug, withExtension: "json", subdirectory: "Models/\(fruit.title)"),
            Bundle.main.url(forResource: fruit.slug, withExtension: "json"),
        ]
        for metadataURL in candidates.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collision = metadata["collision"] as? [String: Any],
                  let radius = collision["radius"] as? Double else { continue }
            return Float(radius * 1.15 + 0.1)
        }
        return 1.05
    }

    // MARK: - Device acceptance sampling (--asset-snapshots)

    // Env FW_SNAPSHOTS=1 is the devicectl-friendly route; dash-prefixed
    // launch arguments are consumed by devicectl's own parser.
    private static let acceptsSnapshots = ProcessInfo.processInfo.arguments.contains("--asset-snapshots")
        || ProcessInfo.processInfo.environment["FW_SNAPSHOTS"] == "1"

    private static func evidenceDirectory() -> URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        // Evidence goes through Caches: proven by AppModel.persistDiagnostics
        // on the device, while Documents writes never landed there.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func evidenceLogName() -> String {
        "evidence_\(AssetFruit.current.slug).log"
    }

    private static func scheduleAcceptanceSnapshots(view: ARView, fruit: AssetFruit, coordinator: Coordinator) {
        appendEvidence("ASSET_LAB_STARTED \(Date())\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            writeSnapshot(view, name: "evidence_\(fruit.slug)_whole.png", coordinator: coordinator)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            // Show the authored halves, matching the in-app toggle behaviour.
            coordinator.whole?.isEnabled = false
            coordinator.sliced?.isEnabled = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
            writeSnapshot(view, name: "evidence_\(fruit.slug)_sliced.png", coordinator: coordinator)
        }
        // Watchdog: the Apple TV can dim/suspend mid-run, which stalls ARView
        // callbacks without any error line. Report state so silent stalls
        // are distinguishable from real failures.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            let state = UIApplication.shared.applicationState
            appendEvidence("ASSET_WATCHDOG appState=\(state.rawValue) snapshots=\(coordinator.snapshotsWritten)\n")
        }
    }

    private static func writeSnapshot(_ view: ARView, name: String, coordinator: Coordinator) {
        view.snapshot(saveToHDR: false) { image in
            guard let image, let data = image.pngData(),
                  let url = evidenceDirectory()?.appendingPathComponent(name) else {
                let failure = "ASSET_SNAPSHOT_FAILED \(name)\n"
                print(failure)
                appendEvidence(failure)
                return
            }
            do {
                try data.write(to: url)
                coordinator.snapshotsWritten += 1
                sampleMemory(coordinator)
                let line = "ASSET_SNAPSHOT \(name) \(url.lastPathComponent) residentMB=\(coordinator.peakResidentMB)\n"
                print(line)
                appendEvidence(line)
            } catch {
                let failure = "ASSET_SNAPSHOT_FAILED \(name) \(error)\n"
                print(failure)
                appendEvidence(failure)
            }
        }
    }

    private static func appendEvidence(_ line: String) {
        guard let logURL = evidenceDirectory()?.appendingPathComponent(evidenceLogName()),
            let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logURL)
        }
    }

    private static func sampleMemory(_ coordinator: Coordinator) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let mb = Int64(info.resident_size) / 1_048_576
            if mb > coordinator.peakResidentMB {
                coordinator.peakResidentMB = mb
            }
        }
    }

    private enum AssetError: LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self { case .missing(let name): "找不到 \(name).usdz" }
        }
    }
}
