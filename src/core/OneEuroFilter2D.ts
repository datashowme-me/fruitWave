import { Vector2 } from './Vector2';

export interface OneEuroFilterConfig {
  minCutoff: number;
  beta: number;
  derivativeCutoff: number;
}

/**
 * Direct port of Sources/FruitWaveCore/OneEuroFilter.swift
 * Adaptive low-pass filter to eliminate jitter while minimizing lag on fast strokes.
 */
export class OneEuroFilter2D {
  public config: OneEuroFilterConfig;
  private previousRaw: Vector2 | null = null;
  private previousFiltered: Vector2 | null = null;
  private filteredDerivative: Vector2 = Vector2.zero();
  private previousTime: number | null = null;

  constructor(
    config: OneEuroFilterConfig = {
      minCutoff: 2.2,
      beta: 0.9,
      derivativeCutoff: 1.5,
    }
  ) {
    this.config = config;
  }

  reset(): void {
    this.previousRaw = null;
    this.previousFiltered = null;
    this.filteredDerivative = Vector2.zero();
    this.previousTime = null;
  }

  filter(point: Vector2, time: number): Vector2 {
    if (this.previousTime === null || this.previousRaw === null || this.previousFiltered === null) {
      this.previousTime = time;
      this.previousRaw = point;
      this.previousFiltered = point;
      return point;
    }

    const dt = Math.max(time - this.previousTime, 0.0001);
    const derivative = point.sub(this.previousRaw).div(dt);
    const derivativeAlpha = this.alpha(this.config.derivativeCutoff, dt);
    this.filteredDerivative = this.lowPass(derivative, this.filteredDerivative, derivativeAlpha);

    const adaptiveCutoff = this.config.minCutoff + this.config.beta * this.filteredDerivative.length;
    const filtered = this.lowPass(point, this.previousFiltered, this.alpha(adaptiveCutoff, dt));

    this.previousTime = time;
    this.previousRaw = point;
    this.previousFiltered = filtered;
    return filtered;
  }

  private alpha(cutoff: number, dt: number): number {
    const tau = 1 / (2 * Math.PI * Math.max(cutoff, 0.0001));
    return 1 / (1 + tau / dt);
  }

  private lowPass(current: Vector2, previous: Vector2, alpha: number): Vector2 {
    return current.mul(alpha).add(previous.mul(1 - alpha));
  }
}
