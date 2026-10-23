import SwiftUI

@main
struct FruitWaveApp: App {
    @State private var model = AppModel()

    /// Acceptance instrumentation runs only under --asset-snapshots or
    /// FW_SNAPSHOTS=1 so production launches write nothing.
    private static let acceptanceInstrumentation = ProcessInfo.processInfo.arguments.contains("--asset-snapshots")
        || ProcessInfo.processInfo.environment["FW_SNAPSHOTS"] == "1"

    init() {
        _model = State(initialValue: AppModel())
        // Device acceptance marker, written from the earliest point that
        // runs on every instrumented launch regardless of scene restoration.
        // Caches is the channel proven by AppModel.persistDiagnostics;
        // Documents writes were never observed to land on the device.
        Self.appendStartupMarker()
    }

    private static var evidenceLogURL: URL? {
        let slug = ProcessInfo.processInfo.environment["FW_FRUIT"] ?? "apple"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("evidence_\(slug).log")
    }

    private static func appendStartupMarker() {
        guard acceptanceInstrumentation,
              let logURL = evidenceLogURL else { return }
        let envKeys = ProcessInfo.processInfo.environment.keys.filter { $0.hasPrefix("FW_") }
        let line = "APP_STARTED \(Date()) args=\(ProcessInfo.processInfo.arguments) envKeys=\(envKeys)\n"
        do {
            try line.write(to: logURL, atomically: true, encoding: .utf8)
        } catch {
            print("APP_STARTED_WRITE_FAILED \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Acceptance marker: records that RootView actually
                    // appeared, appended to the same Caches log so launch
                    // behaviour can be reconstructed from a single file.
                    Self.appendViewAppearedMarker()
                }
        }
    }

    private static func appendViewAppearedMarker() {
        guard acceptanceInstrumentation,
              let url = evidenceLogURL,
              let data = "APP_VIEW_APPEARED \(Date())\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
