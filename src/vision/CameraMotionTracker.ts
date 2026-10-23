import { Vector2 } from '../core/Vector2';
import { OneEuroFilter2D } from '../core/OneEuroFilter2D';

export interface MotionTrackResult {
  hasMotion: boolean;
  rawPoint: Vector2;
  filteredPoint: Vector2;
  speed: number;
  isSlashing: boolean;
  activityLevel: number; // 0 to 1
}

export class CameraMotionTracker {
  private video: HTMLVideoElement | null = null;
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  private prevFrameData: Uint8ClampedArray | null = null;
  private stream: MediaStream | null = null;
  private filter: OneEuroFilter2D;
  private isSlashing = false;
  private lastTime = 0;
  private lastPoint: Vector2 = Vector2.zero();

  // Settings
  public sensitivity = 1.0;
  public mirror = true;
  public leftHandOnly = false;
  public rightHandOnly = false;
  public threshold = 28; // pixel difference threshold

  // Debug data
  public debugPoints: { x: number; y: number; weight: number }[] = [];

  constructor() {
    this.filter = new OneEuroFilter2D({
      minCutoff: 1.8,
      beta: 0.8,
      derivativeCutoff: 1.5,
    });
  }

  async startCamera(videoElement: HTMLVideoElement): Promise<boolean> {
    try {
      this.video = videoElement;
      this.canvas = document.createElement('canvas');
      // Subsampled grid for high-speed 60fps difference calculation
      this.canvas.width = 96;
      this.canvas.height = 72;
      this.ctx = this.canvas.getContext('2d', { willReadFrequently: true });

      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          width: { ideal: 640 },
          height: { ideal: 480 },
          facingMode: 'user',
        },
        audio: false,
      });

      this.stream = stream;
      this.video.srcObject = stream;
      await this.video.play();
      this.filter.reset();
      this.lastTime = performance.now() / 1000;
      return true;
    } catch (err) {
      console.warn('Camera access error:', err);
      return false;
    }
  }

  stopCamera(): void {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop());
      this.stream = null;
    }
    if (this.video) {
      this.video.srcObject = null;
    }
    this.prevFrameData = null;
  }

  processFrame(viewportWidth: number, viewportHeight: number): MotionTrackResult {
    const defaultResult: MotionTrackResult = {
      hasMotion: false,
      rawPoint: this.lastPoint,
      filteredPoint: this.lastPoint,
      speed: 0,
      isSlashing: false,
      activityLevel: 0,
    };

    if (!this.video || !this.ctx || !this.canvas || this.video.readyState < 2) {
      return defaultResult;
    }

    const now = performance.now() / 1000;
    const dt = Math.max(0.001, now - this.lastTime);
    this.lastTime = now;

    const w = this.canvas.width;
    const h = this.canvas.height;

    // Draw current video frame to small offscreen canvas
    this.ctx.drawImage(this.video, 0, 0, w, h);
    const frame = this.ctx.getImageData(0, 0, w, h);
    const data = frame.data;

    if (!this.prevFrameData) {
      this.prevFrameData = new Uint8ClampedArray(data);
      return defaultResult;
    }

    let motionCount = 0;
    let sumX = 0;
    let sumY = 0;
    let maxDiff = 0;

    const xMin = this.leftHandOnly ? 0 : this.rightHandOnly ? Math.floor(w * 0.4) : 0;
    const xMax = this.leftHandOnly ? Math.floor(w * 0.6) : w;

    this.debugPoints = [];

    // Optical difference detection
    for (let y = 0; y < h; y += 2) {
      for (let x = xMin; x < xMax; x += 2) {
        const i = (y * w + x) * 4;
        const rDiff = Math.abs(data[i] - this.prevFrameData[i]);
        const gDiff = Math.abs(data[i + 1] - this.prevFrameData[i + 1]);
        const bDiff = Math.abs(data[i + 2] - this.prevFrameData[i + 2]);
        const diff = (rDiff + gDiff + bDiff) / 3;

        const effectiveThreshold = this.threshold / Math.max(0.2, this.sensitivity);

        if (diff > effectiveThreshold) {
          motionCount++;
          // Weight towards higher movement intensity
          const weight = diff * diff;
          sumX += x * weight;
          sumY += y * weight;
          if (diff > maxDiff) maxDiff = diff;

          if (this.debugPoints.length < 50 && Math.random() < 0.25) {
            this.debugPoints.push({
              x: this.mirror ? 1 - x / w : x / w,
              y: y / h,
              weight: diff,
            });
          }
        }
      }
    }

    // Save previous frame for next tick
    this.prevFrameData.set(data);

    const activity = Math.min(1, motionCount / 160);

    if (motionCount < 6) {
      // Little or no movement
      this.isSlashing = false;
      return {
        hasMotion: false,
        rawPoint: this.lastPoint,
        filteredPoint: this.lastPoint,
        speed: 0,
        isSlashing: false,
        activityLevel: activity,
      };
    }

    // Centroid of moving pixels (normalized 0 to 1)
    let normX = sumX / (motionCount * (maxDiff * maxDiff || 1)) / w;
    normX = Math.max(0, Math.min(1, normX));
    let normY = sumY / (motionCount * (maxDiff * maxDiff || 1)) / h;
    normY = Math.max(0, Math.min(1, normY));

    if (this.mirror) {
      normX = 1 - normX;
    }

    // Convert to viewport pixel coordinates
    const rawPoint = new Vector2(normX * viewportWidth, normY * viewportHeight);
    const filteredPoint = this.filter.filter(rawPoint, now);

    const displacement = filteredPoint.sub(this.lastPoint).length;
    const speed = displacement / dt; // pixels per second

    // Slicing hysteresis (ported from MotionProcessor.swift)
    const startThreshold = 450 * this.sensitivity;
    const stopThreshold = 180 * this.sensitivity;

    if (this.isSlashing) {
      if (speed < stopThreshold) {
        this.isSlashing = false;
      }
    } else {
      if (speed >= startThreshold) {
        this.isSlashing = true;
      }
    }

    this.lastPoint = filteredPoint;

    return {
      hasMotion: true,
      rawPoint,
      filteredPoint,
      speed,
      isSlashing: this.isSlashing,
      activityLevel: activity,
    };
  }
}
