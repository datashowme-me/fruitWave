export type FruitKind =
  | 'watermelon'
  | 'strawberry'
  | 'pineapple'
  | 'apple'
  | 'orange'
  | 'banana'
  | 'kiwi'
  | 'peach'
  | 'mango'
  | 'lemon'
  | 'grape'
  | 'dragon_fruit'
  | 'pear'
  | 'cherry'
  | 'blueberry'
  | 'plum'
  | 'pomegranate'
  | 'coconut'
  | 'cantaloupe'
  | 'persimmon'
  | 'bomb';

export interface FruitConfig {
  kind: FruitKind;
  displayName: string;
  isBomb?: boolean;
  basePoints: number;
  radius: number; // in pixels at normal resolution
  color: string; // Hex color for juice & glow
  fleshColor: string;
  imageWhole: string;
  imageCut: string;
}

export interface ActiveFruit {
  id: string;
  kind: FruitKind;
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  rotation: number;
  vRot: number;
  state: 'active' | 'sliced' | 'expired';
  config: FruitConfig;
  spawnTime: number;
}

export interface SlicedHalf {
  id: string;
  kind: FruitKind;
  x: number;
  y: number;
  vx: number;
  vy: number;
  rotation: number;
  vRot: number;
  half: 'left' | 'right';
  opacity: number;
  config: FruitConfig;
  createdAt: number;
}

export interface JuiceParticle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  color: string;
  alpha: number;
  gravity: number;
  life: number;
  maxLife: number;
}

export interface SplatterDecal {
  x: number;
  y: number;
  size: number;
  color: string;
  alpha: number;
  rotation: number;
  droplets: { x: number; y: number; r: number }[];
}

export interface BladePoint {
  x: number;
  y: number;
  time: number;
}

export type InputMode = 'hybrid' | 'camera' | 'mouse';

export type BladeTheme = 'neon-cyan' | 'fire-katana' | 'rainbow-wave' | 'emerald-ninja' | 'electric-violet';

export interface GameSettings {
  inputMode: InputMode;
  bladeTheme: BladeTheme;
  sfxVolume: number;
  sensitivity: number; // 0.5 to 2.0
  cameraMirror: boolean;
  leftHanded: boolean;
  roundDuration: number; // default 90s
  showMotionDebug: boolean;
}

export interface GameStats {
  score: number;
  maxCombo: number;
  fruitsSliced: number;
  bombsHit: number;
  sliceAcc: number;
  byFruit: Record<string, number>;
}
