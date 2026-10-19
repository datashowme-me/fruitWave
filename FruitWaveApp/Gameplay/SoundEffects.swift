import AVFoundation
import FruitWaveCore
import OSLog

@MainActor
final class SoundEffects {
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

    /// Soft pop as a fruit spawns; the pitch varies by kind so a mixed wave
    /// of fruit sounds like a little arpeggio instead of one repeated beep.
    func playSpawn(kind: FruitKind) {
        guard !sliceBuffers.isEmpty, ensureAudioReady() else { return }
        let base = Double(abs(kind.hashValue % 6))
        if let buffer = spawnBuffer(for: base) {
            player.scheduleBuffer(buffer, at: nil, options: [])
            player.play()
        }
    }

    /// Preview blip when the player toggles sound on.
    func playPreview() {
        guard !sliceBuffers.isEmpty, ensureAudioReady() else { return }
        player.scheduleBuffer(sliceBuffers[sliceBuffers.count / 2], at: nil, options: .interrupts)
        player.play()
    }

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

    private var startAttempts = 0
    private var sessionConfigured = false

    /// AVAudioSession setup is done at most once per launch — repeating it on
    /// every play call can block the main thread (and with it SceneKit's
    /// render loop) when the engine is in a bad state.
    private func configureSessionOnce() -> Bool {
        if sessionConfigured { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            sessionConfigured = true
        } catch {
            Self.logger.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }

    @discardableResult
    private func ensureAudioReady() -> Bool {
        if engine.isRunning { return true }
        guard configureSessionOnce() else { return false }
        do {
            try engine.start()
            startAttempts = 0
            logAudio("engine started (attempts reset)")
        } catch {
            // The engine sometimes can't start during app launch on tvOS;
            // retry lazily instead of blocking. Spaced widely so repeated
            // failures can't stall the main thread.
            startAttempts += 1
            Self.logger.error("Engine start attempt \(self.startAttempts) failed: \(error.localizedDescription, privacy: .public)")
            logAudio("engine start failed: \(error.localizedDescription)")
            if startAttempts <= 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    guard let self, !self.engine.isRunning else { return }
                    _ = self.ensureAudioReady()
                }
            }
            return false
        }
        return engine.isRunning
    }

    /// Appends one line to Library/Caches/fruitwave-audio-log.txt (DEBUG only)
    /// so the on-device audio state can be pulled after a session. Caches is
    /// used because Documents writes fail silently on tvOS.
    private func logAudio(_ message: String) {
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
