/**
 * SoundSynthesizer ported from FruitWaveApp/Gameplay/SoundEffects.swift
 * Uses Web Audio API procedural synthesis with:
 * - 3-layer wet slice sound: Pitch-swept tone + ripping noise + low onset thump
 * - Pitch ascension per combo (+1 semitone per combo streak)
 * - Dynamic blade whoosh on fast slashes
 * - Bomb explosion & fuse fizzing
 * - Gong / fanfare for game events
 */
export class SoundSynthesizer {
  private ctx: AudioContext | null = null;
  public volume = 0.8;
  public enabled = true;

  private initContext(): AudioContext | null {
    if (!this.enabled) return null;
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (AudioCtx) {
        this.ctx = new AudioCtx();
      }
    }
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume().catch(() => {});
    }
    return this.ctx;
  }

  /**
   * Play procedural wet slice sound
   * @param comboStreak Number of consecutive fruits sliced in streak
   */
  playSlice(comboStreak: number = 1): void {
    const ctx = this.initContext();
    if (!ctx) return;

    const now = ctx.currentTime;
    const duration = 0.16;
    const pitchMultiplier = Math.pow(1.06, Math.min(comboStreak, 10)); // ~1 semitone per combo

    // Master slice gain node
    const masterGain = ctx.createGain();
    masterGain.gain.setValueAtTime(0.7 * this.volume, now);
    masterGain.connect(ctx.destination);

    // Layer 1: Frequency sweep tone (1520Hz -> 470Hz)
    const osc = ctx.createOscillator();
    const oscGain = ctx.createGain();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(1520 * pitchMultiplier, now);
    osc.frequency.exponentialRampToValueAtTime(Math.max(40, 470 * pitchMultiplier), now + duration);

    oscGain.gain.setValueAtTime(0.001, now);
    oscGain.gain.linearRampToValueAtTime(0.35, now + 0.015);
    oscGain.gain.exponentialRampToValueAtTime(0.001, now + duration);

    osc.connect(oscGain);
    oscGain.connect(masterGain);
    osc.start(now);
    osc.stop(now + duration);

    // Layer 2: Ripping noise buffer (wet fruit texture)
    const bufferSize = Math.floor(ctx.sampleRate * 0.09);
    const noiseBuffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const output = noiseBuffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      const progress = i / bufferSize;
      const white = Math.random() * 2 - 1;
      output[i] = white * (1 - progress) * 0.45;
    }

    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuffer;

    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(2600 * pitchMultiplier, now);
    filter.Q.value = 1.2;

    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.3, now);
    noiseGain.gain.exponentialRampToValueAtTime(0.01, now + 0.09);

    noise.connect(filter);
    filter.connect(noiseGain);
    noiseGain.connect(masterGain);
    noise.start(now);

    // Layer 3: Low onset thump
    const thump = ctx.createOscillator();
    const thumpGain = ctx.createGain();
    thump.type = 'sine';
    thump.frequency.setValueAtTime(130, now);
    thump.frequency.exponentialRampToValueAtTime(45, now + 0.06);

    thumpGain.gain.setValueAtTime(0.5, now);
    thumpGain.gain.exponentialRampToValueAtTime(0.001, now + 0.06);

    thump.connect(thumpGain);
    thumpGain.connect(masterGain);
    thump.start(now);
    thump.stop(now + 0.07);
  }

  /**
   * Blade whoosh on fast slash
   */
  playWhoosh(intensity: number = 1): void {
    const ctx = this.initContext();
    if (!ctx) return;

    const now = ctx.currentTime;
    const duration = 0.14;

    const bufferSize = Math.floor(ctx.sampleRate * duration);
    const noiseBuffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const output = noiseBuffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      output[i] = Math.random() * 2 - 1;
    }

    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuffer;

    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(500, now);
    filter.frequency.exponentialRampToValueAtTime(1600, now + duration * 0.5);
    filter.frequency.exponentialRampToValueAtTime(300, now + duration);
    filter.Q.value = 2.0;

    const gain = ctx.createGain();
    const amp = Math.min(0.35, 0.18 * intensity) * this.volume;
    gain.gain.setValueAtTime(0.001, now);
    gain.gain.linearRampToValueAtTime(amp, now + 0.04);
    gain.gain.exponentialRampToValueAtTime(0.001, now + duration);

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    noise.start(now);
  }

  /**
   * Bomb explosion boom
   */
  playExplosion(): void {
    const ctx = this.initContext();
    if (!ctx) return;

    const now = ctx.currentTime;
    const duration = 1.2;

    // Sub rumble
    const osc = ctx.createOscillator();
    const oscGain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(90, now);
    osc.frequency.exponentialRampToValueAtTime(25, now + duration);

    oscGain.gain.setValueAtTime(0.9 * this.volume, now);
    oscGain.gain.exponentialRampToValueAtTime(0.001, now + duration);

    osc.connect(oscGain);
    oscGain.connect(ctx.destination);
    osc.start(now);
    osc.stop(now + duration);

    // Blast noise
    const bufferSize = Math.floor(ctx.sampleRate * 0.8);
    const buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (ctx.sampleRate * 0.25));
    }
    const noise = ctx.createBufferSource();
    noise.buffer = buffer;

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(800, now);
    filter.frequency.exponentialRampToValueAtTime(100, now + 0.8);

    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.7 * this.volume, now);
    noiseGain.gain.exponentialRampToValueAtTime(0.001, now + 0.8);

    noise.connect(filter);
    filter.connect(noiseGain);
    noiseGain.connect(ctx.destination);
    noise.start(now);
  }

  /**
   * Combo fanfare
   */
  playComboFanfare(comboCount: number): void {
    const ctx = this.initContext();
    if (!ctx) return;

    const now = ctx.currentTime;
    const baseFreq = 523.25; // C5
    const notes = [baseFreq, baseFreq * 1.25, baseFreq * 1.5, baseFreq * 2]; // C, E, G, High C

    notes.forEach((freq, idx) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      const startTime = now + idx * 0.06;

      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, startTime);

      gain.gain.setValueAtTime(0.001, startTime);
      gain.gain.linearRampToValueAtTime(0.25 * this.volume, startTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, startTime + 0.25);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(startTime);
      osc.stop(startTime + 0.26);
    });
  }

  /**
   * Round start gong
   */
  playStartChime(): void {
    const ctx = this.initContext();
    if (!ctx) return;
    const now = ctx.currentTime;

    [440, 660, 880].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, now + i * 0.08);

      gain.gain.setValueAtTime(0.001, now + i * 0.08);
      gain.gain.linearRampToValueAtTime(0.3 * this.volume, now + i * 0.08 + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, now + i * 0.08 + 0.4);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now + i * 0.08);
      osc.stop(now + i * 0.08 + 0.42);
    });
  }
}

export const soundSynthesizer = new SoundSynthesizer();
