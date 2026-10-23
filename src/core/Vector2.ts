/**
 * Ported directly from Sources/FruitWaveCore/Geometry.swift
 */
export class Vector2 {
  public x: number;
  public y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }

  static zero(): Vector2 {
    return new Vector2(0, 0);
  }

  add(other: Vector2): Vector2 {
    return new Vector2(this.x + other.x, this.y + other.y);
  }

  sub(other: Vector2): Vector2 {
    return new Vector2(this.x - other.x, this.y - other.y);
  }

  mul(scalar: number): Vector2 {
    return new Vector2(this.x * scalar, this.y * scalar);
  }

  div(scalar: number): Vector2 {
    return new Vector2(this.x / scalar, this.y / scalar);
  }

  get length(): number {
    return Math.hypot(this.x, this.y);
  }

  get isFinite(): boolean {
    return Number.isFinite(this.x) && Number.isFinite(this.y);
  }

  get normalized(): Vector2 {
    const mag = this.length;
    return mag > 0.000001 ? this.div(mag) : Vector2.zero();
  }

  interpolated(other: Vector2, fraction: number): Vector2 {
    return this.add(other.sub(this).mul(fraction));
  }

  distanceTo(other: Vector2): number {
    return Math.hypot(this.x - other.x, this.y - other.y);
  }
}

export class Geometry {
  /**
   * Distance from a point p to line segment from a to b
   */
  static distanceToSegment(p: Vector2, a: Vector2, b: Vector2): number {
    const ab = b.sub(a);
    const denominator = ab.x * ab.x + ab.y * ab.y;
    if (denominator <= 0) {
      return p.distanceTo(a);
    }
    const ap = p.sub(a);
    const t = Math.max(0, Math.min(1, (ap.x * ab.x + ap.y * ab.y) / denominator));
    const projection = a.add(ab.mul(t));
    return p.distanceTo(projection);
  }
}
