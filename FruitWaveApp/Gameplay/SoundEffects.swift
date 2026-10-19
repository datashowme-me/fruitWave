import AVFoundation
import FruitWaveCore
import OSLog

@MainActor
final class SoundEffects {
    private static let logger = Logger(subsystem: "com.example.FruitWave", category: "Audio")
    private let engine = AVAudioEngine()
    /// 切中主体(真实采样或程序合成兜底)
    private let player = AVAudioPlayerNode()
    /// 程序合成的短促噪声撕裂层,模拟刀刃划过果肉的"湿"声
    private let ripPlayer = AVAudioPlayerNode()
    /// 连击彩头:玻璃脆响/钟声
    private let chimePlayer = AVAudioPlayerNode()

    /// Kenney CC0 采样,按文件名前缀分组(impactSoft_medium = 轻果多汁
    /// 软撞击,impactSoft_heavy = 西瓜/菠萝等大果,玻璃/钟 = 连击彩头)。
    private var bodyBanks: [String: [AVAudioPCMBuffer]] = [:]
    private var chimeBanks: [String: [AVAudioPCMBuffer]] = [:]
    /// 采样缺失时的程序合成兜底(与旧版一致的完整切音)
    private let proceduralBuffers: [AVAudioPCMBuffer]
    private let ripBuffers: [AVAudioPCMBuffer]

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        proceduralBuffers = Self.makeSliceBuffers(format: format, variantCount: 6)
        ripBuffers = Self.makeRipBuffers(format: format, variantCount: 3)
        engine.attach(player)
        engine.attach(ripPlayer)
        engine.attach(chimePlayer)
        if let format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.connect(ripPlayer, to: engine.mainMixerNode, format: format)
            engine.connect(chimePlayer, to: engine.mainMixerNode, format: format)
        }
        player.volume = 0.9
        ripPlayer.volume = 0.35
        chimePlayer.volume = 0.55
        loadSamples()
        engine.prepare()
        // When the Apple TV's audio route appears or changes (TV/AVR waking
        // up), an engine that failed to start earlier gets another chance
        // immediately instead of waiting for the next retry tick.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logAudio("route change -> \(self.routeDescription())")
                if !self.engine.isRunning { _ = self.ensureAudioReady() }
            }
        }
        _ = ensureAudioReady()
    }

    /// 大果用重采样(低频更沉),小果用轻采样
    private static let heavyKinds: Set<FruitKind> = [
        .watermelon, .pineapple, .coconut, .pomegranate, .cantaloupe
    ]

    func playSlice(kind: FruitKind, combo: Int) {
        guard ensureAudioReady() else { return }
        let kindOffset = Self.kindIndex(kind) % 2
        let bankName = Self.heavyKinds.contains(kind) ? "impactSoft_heavy" : "impactSoft_medium"
        if let bank = bodyBanks[bankName], !bank.isEmpty {
            // 连击越高音调越高,营造爬升感;上限防卡通化
            let buffer = bank[(kindOffset + max(0, combo - 1)) % bank.count]
            player.rate = Float(min(1.35, 1.0 + 0.06 * Double(min(combo, 6))))
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } else {
            guard !proceduralBuffers.isEmpty else { return }
            let index = min(proceduralBuffers.count - 1, kindOffset + max(0, combo - 1))
            player.rate = 1
            player.scheduleBuffer(proceduralBuffers[index], at: nil, options: .interrupts)
            player.play()
        }
        // 撕裂层与主体同发:纯合成,音调随水果种微调防重复感
        if !ripBuffers.isEmpty {
            let rip = ripBuffers[Self.kindIndex(kind) % ripBuffers.count]
            ripPlayer.rate = Float(0.92 + 0.16 * Double(Self.kindIndex(kind) % 7) / 7.0)
            ripPlayer.scheduleBuffer(rip, at: nil, options: .interrupts)
            ripPlayer.play()
        }
        // 连击彩头:3+ 玻璃脆响,5+ 换低频钟声,音高随连击爬升
        if combo >= 3 {
            let bankName = combo >= 5 ? "impactBell_heavy" : "impactGlass_light"
            if let bank = chimeBanks[bankName], !bank.isEmpty {
                let buffer = bank[min(combo - 3, bank.count - 1)]
                chimePlayer.rate = Float(min(1.4, 1.0 + 0.05 * Double(min(combo, 10))))
                chimePlayer.scheduleBuffer(buffer, at: nil, options: [])
                chimePlayer.play()
            }
        }
    }

    /// Soft pop as a fruit spawns; the pitch varies by kind so a mixed wave
    /// of fruit sounds like a little arpeggio instead of one repeated beep.
    func playSpawn(kind: FruitKind) {
        guard !sliceBuffersEmpty(), ensureAudioReady() else { return }
        let base = Double(Self.kindIndex(kind) % 6)
        if let buffer = spawnBuffer(for: base) {
            player.scheduleBuffer(buffer, at: nil, options: [])
            player.play()
        }
    }

    /// Preview blip when the player toggles sound on.
    func playPreview() {
        guard ensureAudioReady() else { return }
        if let bank = bodyBanks["impactSoft_medium"], !bank.isEmpty {
            player.rate = 1
            player.scheduleBuffer(bank[0], at: nil, options: .interrupts)
            player.play()
        } else if !proceduralBuffers.isEmpty {
            player.rate = 1
            player.scheduleBuffer(proceduralBuffers[proceduralBuffers.count / 2], at: nil, options: .interrupts)
            player.play()
        }
    }

    private func sliceBuffersEmpty() -> Bool {
        let body = bodyBanks["impactSoft_medium"] ?? []
        let heavy = bodyBanks["impactSoft_heavy"] ?? []
        return body.isEmpty && heavy.isEmpty && proceduralBuffers.isEmpty
    }

    // MARK: - Sample loading

    /// 从 Bundle 的 Audio/ 子目录加载 Kenney CC0 采样。任一缺失只降级到
    /// 程序合成,不影响引擎生命周期。
    private func loadSamples() {
        let bundle = Bundle.main
        for prefix in ["impactSoft_medium", "impactSoft_heavy"] {
            let bank = Self.loadBank(bundle, prefix: prefix, count: 5)
            if !bank.isEmpty { bodyBanks[prefix] = bank }
        }
        for prefix in ["impactGlass_light", "impactBell_heavy"] {
            let count = prefix == "impactGlass_light" ? 3 : 2
            let bank = Self.loadBank(bundle, prefix: prefix, count: count)
            if !bank.isEmpty { chimeBanks[prefix] = bank }
        }
        logAudio("samples loaded -> body:\(bodyBanks.mapValues(\.count)), chime:\(chimeBanks.mapValues(\.count))")
    }

    private static func loadBank(_ bundle: Bundle, prefix: String, count: Int) -> [AVAudioPCMBuffer] {
        var bank: [AVAudioPCMBuffer] = []
        for index in 0..<count {
            let name = String(format: "%@_%03d", prefix, index)
            // XcodeGen 目录式源会把资源平铺到 bundle 根目录(无 Audio/ 子目录)
            guard let url = bundle.url(forResource: name, withExtension: "caf"),
                  let file = try? AVAudioFile(forReading: url) else { continue }
            let capacity = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity),
                  (try? file.read(into: buffer)) != nil else { continue }
            bank.append(buffer)
        }
        return bank
    }

    // MARK: - Procedural buffers

    // Spawn pops are quiet; they queue behind slice sounds instead of
    // interrupting them.
    private var spawnBuffers: [Double: AVAudioPCMBuffer] = [:]
    private func spawnBuffer(for pitchOffset: Double) -> AVAudioPCMBuffer? {
        if let cached = spawnBuffers[pitchOffset] { return cached }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 0.09)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(format.sampleRate * 0.09)
        let pitch = 0.85 + 0.08 * pitchOffset
        var phase = 0.0
        for index in 0..<Int(buffer.frameLength) {
            let progress = Double(index) / Double(buffer.frameLength)
            let frequency = (560 + 380 * progress) * pitch
            phase += 2 * .pi * frequency / format.sampleRate
            let envelope = sin(.pi * progress) * 0.22
            let sample = Float(sin(phase) * envelope)
            for channel in 0..<Int(format.channelCount) {
                channels[channel][index] = sample
            }
        }
        spawnBuffers[pitchOffset] = buffer
        return buffer
    }

    /// 撕裂层:0.08s 噪声扫频(3k→1k),独立于主体音量,只提供"湿"的质感
    private static func makeRipBuffers(format: AVAudioFormat?, variantCount: Int) -> [AVAudioPCMBuffer] {
        guard let format else { return [] }
        let frameCount = AVAudioFrameCount(format.sampleRate * 0.08)
        var buffers: [AVAudioPCMBuffer] = []
        for variant in 0..<variantCount {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                  let channels = buffer.floatChannelData else { continue }
            buffer.frameLength = frameCount
            var sweepPhase = 0.0
            var noiseState: UInt64 = 0xC0FF_EE01 &+ UInt64(variant) &* 0x9E37_79B9
            for index in 0..<Int(frameCount) {
                let progress = Double(index) / Double(frameCount)
                let sweepFrequency = (3_100 - 2_100 * progress) * (0.9 + 0.08 * Double(variant))
                sweepPhase += 2 * .pi * sweepFrequency / format.sampleRate
                noiseState = noiseState &* 6_364_136_223_846_793_005 &+ 1
                let noise = Double(Int64(bitPattern: noiseState) >> 40) / Double(1 << 23)
                let envelope = sin(.pi * progress)
                let sample = Float((sin(sweepPhase) * 0.35 + noise * 0.5) * envelope)
                for channel in 0..<Int(format.channelCount) {
                    channels[channel][index] = sample
                }
            }
            buffers.append(buffer)
        }
        return buffers
    }

    // MARK: - Engine lifecycle

    private var sessionConfigured = false
    private var retryScheduled = false

    /// AVAudioSession setup is done at most once per launch — repeating it on
    /// every play call can block the main thread (and with it SceneKit's
    /// render loop) when the engine is in a bad state.
    private func configureSessionOnce() -> Bool {
        if sessionConfigured { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            sessionConfigured = true
            logAudio("session configured (.playback) -> \(routeDescription())")
        } catch {
            Self.logger.error("session setup failed: \(error.localizedDescription, privacy: .public)")
            logAudio("session setup failed: \(error.localizedDescription)")
            return false
        }
        return true
    }

    /// Starts the engine if it isn't running. Failures keep retrying every
    /// 4 s for the whole session: at launch the Apple TV may have no live
    /// audio route (TV asleep / receiver off), and the engine typically
    /// starts fine once the route appears.
    @discardableResult
    private func ensureAudioReady() -> Bool {
        if engine.isRunning { return true }
        guard configureSessionOnce() else {
            scheduleRetry()
            return false
        }
        do {
            try engine.start()
            logAudio("engine started -> \(routeDescription())")
        } catch {
            Self.logger.error("engine start failed: \(error.localizedDescription, privacy: .public)")
            logAudio("engine start failed: \(error.localizedDescription)")
            scheduleRetry()
            return false
        }
        return engine.isRunning
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            if !self.engine.isRunning { _ = self.ensureAudioReady() }
        }
    }

    /// Output port types only — never port names (device names stay out of
    /// the logs).
    private func routeDescription() -> String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard !outputs.isEmpty else { return "no outputs" }
        return outputs.map(\.portType.rawValue).joined(separator: ",")
    }

    /// Appends one line to Library/Caches/fruitwave-audio-log.txt (DEBUG only)
    /// and mirrors it to the unified log so it can be captured from the
    /// console. Caches is used because Documents writes fail silently on
    /// tvOS.
    private func logAudio(_ message: String) {
        Self.logger.debug("\(message, privacy: .public)")
        #if DEBUG
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fruitwave-audio-log.txt")
        let line = message + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) { handle.write(data) }
            try? handle.close()
        } else if let data = line.data(using: .utf8) {
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }

    /// FruitKind → 稳定索引(hashValue 每次启动随机,音效要跨启动一致)
    private static func kindIndex(_ kind: FruitKind) -> Int {
        Int(kind.rawValue.unicodeScalars.reduce(0) { $0 &+ $1.value } % 64)
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
