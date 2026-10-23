import React, { useEffect, useRef, useState, useCallback } from 'react';
import confetti from 'canvas-confetti';
import { FRUIT_CATALOG, REGULAR_FRUITS } from '../data/fruitCatalog';
import {
  ActiveFruit,
  BladePoint,
  BladeTheme,
  FruitKind,
  GameSettings,
  GameStats,
  JuiceParticle,
  SlicedHalf,
  SplatterDecal,
} from '../types/game';
import { Vector2, Geometry } from '../core/Vector2';
import { soundSynthesizer } from '../core/SoundSynthesizer';
import { CameraMotionTracker, MotionTrackResult } from '../vision/CameraMotionTracker';

interface FruitCanvasProps {
  isPlaying: boolean;
  isPaused: boolean;
  settings: GameSettings;
  motionTracker: CameraMotionTracker;
  onGameOver: (stats: GameStats) => void;
  onUpdateHUD: (data: { score: number; timeLeft: number; combo: number; maxCombo: number }) => void;
}

interface FloatingText {
  id: string;
  text: string;
  x: number;
  y: number;
  vy: number;
  alpha: number;
  color: string;
  size: number;
}

export const FruitCanvas: React.FC<FruitCanvasProps> = ({
  isPlaying,
  isPaused,
  settings,
  motionTracker,
  onGameOver,
  onUpdateHUD,
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  // Game state refs (kept in refs for 60fps loop performance)
  const fruitsRef = useRef<ActiveFruit[]>([]);
  const slicedHalvesRef = useRef<SlicedHalf[]>([]);
  const juiceParticlesRef = useRef<JuiceParticle[]>([]);
  const splattersRef = useRef<SplatterDecal[]>([]);
  const bladePointsRef = useRef<BladePoint[]>([]);
  const floatingTextsRef = useRef<FloatingText[]>([]);
  const activeHandPosRef = useRef<Vector2 | null>(null);

  const scoreRef = useRef(0);
  const timeLeftRef = useRef(settings.roundDuration);
  const maxComboRef = useRef(0);
  const totalFruitsSlicedRef = useRef(0);
  const bombsHitRef = useRef(0);
  const fruitCountsRef = useRef<Record<string, number>>({});
  const comboStreakRef = useRef(0);
  const lastSliceTimeRef = useRef(0);

  const [activeComboBanner, setActiveComboBanner] = useState<{ text: string; score: number } | null>(null);
  const [screenShake, setScreenShake] = useState(0);

  // Preloaded image cache
  const imageCacheRef = useRef<Record<string, HTMLImageElement>>({});

  // Pointer position for mouse / touch
  const pointerActiveRef = useRef(false);
  const lastPointerPosRef = useRef<Vector2 | null>(null);

  // Preload fruit assets eagerly
  useEffect(() => {
    Object.values(FRUIT_CATALOG).forEach((fruit) => {
      if (fruit.imageWhole) {
        const imgWhole = new Image();
        imgWhole.src = fruit.imageWhole;
        imgWhole.decode?.().catch(() => {});
        imageCacheRef.current[`${fruit.kind}_whole`] = imgWhole;
      }
      if (fruit.imageCut) {
        const imgCut = new Image();
        imgCut.src = fruit.imageCut;
        imgCut.decode?.().catch(() => {});
        imageCacheRef.current[`${fruit.kind}_cut`] = imgCut;
      }
    });
  }, []);

  // Reset or restart round
  useEffect(() => {
    if (isPlaying && !isPaused) {
      fruitsRef.current = [];
      slicedHalvesRef.current = [];
      juiceParticlesRef.current = [];
      splattersRef.current = [];
      bladePointsRef.current = [];
      scoreRef.current = 0;
      timeLeftRef.current = settings.roundDuration;
      maxComboRef.current = 0;
      totalFruitsSlicedRef.current = 0;
      bombsHitRef.current = 0;
      fruitCountsRef.current = {};
      comboStreakRef.current = 0;
      lastSliceTimeRef.current = 0;
      soundSynthesizer.playStartChime();
    }
  }, [isPlaying, isPaused, settings.roundDuration]);

  // Spawn a fruit or bomb
  const spawnFruit = useCallback((canvasWidth: number, canvasHeight: number) => {
    const isBomb = Math.random() < 0.12; // 12% bomb spawn chance
    const kind: FruitKind = isBomb
      ? 'bomb'
      : REGULAR_FRUITS[Math.floor(Math.random() * REGULAR_FRUITS.length)];
    const config = FRUIT_CATALOG[kind];

    // Launch from bottom edge
    const margin = canvasWidth * 0.15;
    const x = margin + Math.random() * (canvasWidth - margin * 2);
    const y = canvasHeight + config.radius;

    // Upward parabolic velocity
    const targetCenterX = canvasWidth * 0.5;
    const horizontalAim = (targetCenterX - x) * 0.35 + (Math.random() - 0.5) * 120;
    const vx = horizontalAim;
    const vy = -(canvasHeight * 0.95 + Math.random() * 180);

    const activeFruit: ActiveFruit = {
      id: Math.random().toString(36).substring(2, 9),
      kind,
      x,
      y,
      vx,
      vy,
      radius: config.radius,
      rotation: Math.random() * Math.PI * 2,
      vRot: (Math.random() - 0.5) * 4,
      state: 'active',
      config,
      spawnTime: performance.now(),
    };

    fruitsRef.current.push(activeFruit);
  }, []);

  // Slice a fruit
  const handleFruitSlice = useCallback(
    (fruit: ActiveFruit, sliceAngle: number, canvasWidth: number, canvasHeight: number) => {
      fruit.state = 'sliced';
      const now = performance.now();

      if (fruit.config.isBomb) {
        // Bomb detonated!
        bombsHitRef.current += 1;
        soundSynthesizer.playExplosion();
        setScreenShake(24);

        // Flash screen and lose points
        scoreRef.current = Math.max(0, scoreRef.current - 50);

        // Floating bomb text
        floatingTextsRef.current.push({
          id: Math.random().toString(36).substring(2, 7),
          text: '-50 💥 炸弹!',
          x: fruit.x,
          y: fruit.y - 15,
          vy: -60,
          alpha: 1,
          color: '#ef4444',
          size: 26,
        });

        // Explode bomb particles
        for (let i = 0; i < 40; i++) {
          const angle = Math.random() * Math.PI * 2;
          const speed = 180 + Math.random() * 520;
          juiceParticlesRef.current.push({
            x: fruit.x,
            y: fruit.y,
            vx: Math.cos(angle) * speed,
            vy: Math.sin(angle) * speed,
            size: 4 + Math.random() * 6,
            color: Math.random() < 0.5 ? '#f97316' : '#ef4444',
            alpha: 1,
            gravity: 400,
            life: 0,
            maxLife: 0.8 + Math.random() * 0.5,
          });
        }
        return;
      }

      // Regular fruit slice
      totalFruitsSlicedRef.current += 1;
      fruitCountsRef.current[fruit.kind] = (fruitCountsRef.current[fruit.kind] || 0) + 1;

      // Combo streak logic
      if (now - lastSliceTimeRef.current < 450) {
        comboStreakRef.current += 1;
      } else {
        comboStreakRef.current = 1;
      }
      lastSliceTimeRef.current = now;

      if (comboStreakRef.current > maxComboRef.current) {
        maxComboRef.current = comboStreakRef.current;
      }

      const comboMultiplier = comboStreakRef.current >= 3 ? comboStreakRef.current : 1;
      const pointsAdded = fruit.config.basePoints * comboMultiplier;
      scoreRef.current += pointsAdded;

      // Floating score popup at fruit cut position
      floatingTextsRef.current.push({
        id: Math.random().toString(36).substring(2, 7),
        text: comboMultiplier >= 3 ? `+${pointsAdded} 🔥${comboMultiplier}x` : `+${pointsAdded}`,
        x: fruit.x,
        y: fruit.y - 10,
        vy: -90,
        alpha: 1,
        color: comboMultiplier >= 3 ? '#facc15' : '#ffffff',
        size: comboMultiplier >= 3 ? 24 : 18,
      });

      // Play sound with dynamic combo pitch
      soundSynthesizer.playSlice(comboStreakRef.current);

      if (comboStreakRef.current >= 3) {
        soundSynthesizer.playComboFanfare(comboStreakRef.current);
        setActiveComboBanner({
          text: comboStreakRef.current >= 5 ? `MEGA SLICE! ${comboStreakRef.current}x` : `COMBO ${comboStreakRef.current}x`,
          score: pointsAdded,
        });
        setTimeout(() => setActiveComboBanner(null), 1200);

        if (comboStreakRef.current >= 4) {
          confetti({
            particleCount: 25,
            spread: 60,
            origin: { x: fruit.x / canvasWidth, y: fruit.y / canvasHeight },
          });
        }
      }

      // Spawn 2 sliced halves
      const normalAngle = sliceAngle + Math.PI / 2;
      const pushSpeed = 160 + Math.random() * 90;

      const halfLeft: SlicedHalf = {
        id: Math.random().toString(36).substring(2, 9),
        kind: fruit.kind,
        x: fruit.x,
        y: fruit.y,
        vx: fruit.vx + Math.cos(normalAngle) * pushSpeed,
        vy: fruit.vy + Math.sin(normalAngle) * pushSpeed - 60,
        rotation: fruit.rotation,
        vRot: -3.5 - Math.random() * 2,
        half: 'left',
        opacity: 1,
        config: fruit.config,
        createdAt: now,
      };

      const halfRight: SlicedHalf = {
        id: Math.random().toString(36).substring(2, 9),
        kind: fruit.kind,
        x: fruit.x,
        y: fruit.y,
        vx: fruit.vx - Math.cos(normalAngle) * pushSpeed,
        vy: fruit.vy - Math.sin(normalAngle) * pushSpeed - 60,
        rotation: fruit.rotation,
        vRot: 3.5 + Math.random() * 2,
        half: 'right',
        opacity: 1,
        config: fruit.config,
        createdAt: now,
      };

      slicedHalvesRef.current.push(halfLeft, halfRight);

      // Juice droplets & particles
      const particleCount = 24 + Math.floor(Math.random() * 12);
      for (let i = 0; i < particleCount; i++) {
        const pAngle = sliceAngle + (Math.random() - 0.5) * 1.8;
        const pSpeed = 120 + Math.random() * 420;
        juiceParticlesRef.current.push({
          x: fruit.x + (Math.random() - 0.5) * 20,
          y: fruit.y + (Math.random() - 0.5) * 20,
          vx: Math.cos(pAngle) * pSpeed * (Math.random() < 0.5 ? 1 : -1),
          vy: Math.sin(pAngle) * pSpeed - 80,
          size: 3 + Math.random() * 5,
          color: Math.random() < 0.65 ? fruit.config.color : fruit.config.fleshColor,
          alpha: 1,
          gravity: 580,
          life: 0,
          maxLife: 0.7 + Math.random() * 0.4,
        });
      }

      // Background organic juice splash (soft droplets that dissipate naturally)
      if (splattersRef.current.length < 15) {
        const droplets = [];
        const numDrops = 4 + Math.floor(Math.random() * 5);
        for (let p = 0; p < numDrops; p++) {
          const a = (p / numDrops) * Math.PI * 2 + (Math.random() - 0.5) * 0.8;
          const dist = fruit.config.radius * 0.4 + Math.random() * (fruit.config.radius * 0.65);
          const r = 2.5 + Math.random() * 4.5;
          droplets.push({ x: Math.cos(a) * dist, y: Math.sin(a) * dist, r });
        }
        splattersRef.current.push({
          x: fruit.x,
          y: fruit.y,
          size: fruit.config.radius * 0.8,
          color: fruit.config.color,
          alpha: 0.65,
          rotation: Math.random() * Math.PI * 2,
          droplets,
        });
      }
    },
    []
  );

  // Process blade collision
  const checkBladeCollision = useCallback(
    (p1: Vector2, p2: Vector2, canvasWidth: number, canvasHeight: number) => {
      const segLength = p1.distanceTo(p2);
      if (segLength < 6) return;

      const sliceAngle = Math.atan2(p2.y - p1.y, p2.x - p1.x);

      fruitsRef.current.forEach((fruit) => {
        if (fruit.state !== 'active') return;
        const fruitPos = new Vector2(fruit.x, fruit.y);
        const dist = Geometry.distanceToSegment(fruitPos, p1, p2);

        if (dist <= fruit.radius) {
          handleFruitSlice(fruit, sliceAngle, canvasWidth, canvasHeight);
        }
      });
    },
    [handleFruitSlice]
  );

  // Mouse & touch interaction listeners
  const handlePointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (settings.inputMode === 'camera') return;
    pointerActiveRef.current = true;
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const pt = new Vector2(x, y);
    lastPointerPosRef.current = pt;
    bladePointsRef.current.push({ x, y, time: performance.now() });
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (settings.inputMode === 'camera') return;
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const currentPt = new Vector2(x, y);

    if (pointerActiveRef.current && lastPointerPosRef.current && canvasRef.current) {
      checkBladeCollision(lastPointerPosRef.current, currentPt, canvasRef.current.width, canvasRef.current.height);
      const speed = currentPt.distanceTo(lastPointerPosRef.current) / 0.016;
      if (speed > 550) {
        soundSynthesizer.playWhoosh(Math.min(2, speed / 800));
      }
    }

    lastPointerPosRef.current = currentPt;
    bladePointsRef.current.push({ x, y, time: performance.now() });
  };

  const handlePointerUp = () => {
    pointerActiveRef.current = false;
    lastPointerPosRef.current = null;
  };

  // Main 60fps render & physics loop
  useEffect(() => {
    let animId: number;
    let lastTime = performance.now();
    let spawnTimer = 0;

    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Handle high DPI retina display
    const resizeCanvas = () => {
      const rect = canvas.getBoundingClientRect();
      if (canvas.width !== rect.width || canvas.height !== rect.height) {
        canvas.width = rect.width;
        canvas.height = rect.height;
      }
    };
    resizeCanvas();
    window.addEventListener('resize', resizeCanvas);

    const loop = (currentTime: number) => {
      animId = requestAnimationFrame(loop);
      const dt = Math.min(0.04, (currentTime - lastTime) / 1000);
      lastTime = currentTime;

      resizeCanvas();
      const w = canvas.width;
      const h = canvas.height;

      // Update timer when playing
      if (isPlaying && !isPaused) {
        timeLeftRef.current = Math.max(0, timeLeftRef.current - dt);
        onUpdateHUD({
          score: scoreRef.current,
          timeLeft: Math.ceil(timeLeftRef.current),
          combo: comboStreakRef.current,
          maxCombo: maxComboRef.current,
        });

        if (timeLeftRef.current <= 0) {
          // Game Over!
          onGameOver({
            score: scoreRef.current,
            maxCombo: maxComboRef.current,
            fruitsSliced: totalFruitsSlicedRef.current,
            bombsHit: bombsHitRef.current,
            sliceAcc: Math.round(
              (totalFruitsSlicedRef.current /
                Math.max(1, totalFruitsSlicedRef.current + fruitsRef.current.length)) *
                100
            ),
            byFruit: { ...fruitCountsRef.current },
          });
          return;
        }

        // Fruit Spawner
        spawnTimer += dt;
        const activeFruitsCount = fruitsRef.current.filter((f) => f.state === 'active').length;
        if (spawnTimer >= 0.75 && activeFruitsCount < 6) {
          spawnTimer = 0;
          spawnFruit(w, h);
          // Sometimes launch double fruits
          if (Math.random() < 0.35 && activeFruitsCount < 5) {
            setTimeout(() => spawnFruit(w, h), 160);
          }
        }
      }

      // Camera motion tracking tick
      if (settings.inputMode !== 'mouse') {
        const motionResult: MotionTrackResult = motionTracker.processFrame(w, h);
        if (motionResult.hasMotion) {
          activeHandPosRef.current = motionResult.filteredPoint;
          if (motionResult.isSlashing) {
            const pt = motionResult.filteredPoint;
            bladePointsRef.current.push({ x: pt.x, y: pt.y, time: currentTime });
            if (bladePointsRef.current.length >= 2) {
              const p1 = bladePointsRef.current[bladePointsRef.current.length - 2];
              const p2 = bladePointsRef.current[bladePointsRef.current.length - 1];
              checkBladeCollision(new Vector2(p1.x, p1.y), new Vector2(p2.x, p2.y), w, h);
            }
            if (motionResult.speed > 600) {
              soundSynthesizer.playWhoosh(Math.min(2, motionResult.speed / 900));
            }
          }
        } else {
          activeHandPosRef.current = null;
        }
      } else {
        activeHandPosRef.current = null;
      }

      // Prune old blade points
      bladePointsRef.current = bladePointsRef.current.filter(
        (p) => currentTime - p.time < 190
      );

      // Physics: Gravity & Fruit Kinematics
      const gravity = 620; // px/s^2

      if (isPlaying && !isPaused) {
        fruitsRef.current.forEach((fruit) => {
          if (fruit.state === 'active') {
            fruit.vy += gravity * dt;
            fruit.x += fruit.vx * dt;
            fruit.y += fruit.vy * dt;
            fruit.rotation += fruit.vRot * dt;

            // Remove expired fruits that drop below canvas
            if (fruit.y > h + fruit.radius + 60 && fruit.vy > 0) {
              fruit.state = 'expired';
            }
          }
        });
        // Remove non-active fruits
        fruitsRef.current = fruitsRef.current.filter((f) => f.state === 'active');

        // Physics: Sliced Halves
        slicedHalvesRef.current.forEach((half) => {
          half.vy += gravity * 1.05 * dt;
          half.x += half.vx * dt;
          half.y += half.vy * dt;
          half.rotation += half.vRot * dt;
          half.opacity = Math.max(0, 1 - (currentTime - half.createdAt) / 1200);
        });
        slicedHalvesRef.current = slicedHalvesRef.current.filter(
          (h) => h.opacity > 0.05
        );

        // Physics: Juice Particles
        juiceParticlesRef.current.forEach((p) => {
          p.vy += p.gravity * dt;
          p.x += p.vx * dt;
          p.y += p.vy * dt;
          p.life += dt;
          p.alpha = Math.max(0, 1 - p.life / p.maxLife);
        });
        juiceParticlesRef.current = juiceParticlesRef.current.filter(
          (p) => p.life < p.maxLife
        );

        // Splatters decay cleanly and rapidly (~1.8 seconds) to keep the arena clean
        splattersRef.current.forEach((s) => {
          s.alpha = Math.max(0, s.alpha - dt * 0.35);
        });
        splattersRef.current = splattersRef.current.filter((s) => s.alpha > 0.02);

        // Floating texts decay
        floatingTextsRef.current.forEach((ft) => {
          ft.y += ft.vy * dt;
          ft.alpha = Math.max(0, ft.alpha - dt * 1.5);
        });
        floatingTextsRef.current = floatingTextsRef.current.filter((ft) => ft.alpha > 0.05);
      }

      // Screen shake recovery
      setScreenShake((prev) => Math.max(0, prev * 0.88 - 0.2));

      // --- RENDERING ---
      ctx.save();
      ctx.clearRect(0, 0, w, h);

      if (screenShake > 0.5) {
        const shakeX = (Math.random() - 0.5) * screenShake;
        const shakeY = (Math.random() - 0.5) * screenShake;
        ctx.translate(shakeX, shakeY);
      }

      // 1. Draw Clean Organic Juice Splatters (Soft translucent droplet spray)
      splattersRef.current.forEach((s) => {
        ctx.save();
        ctx.translate(s.x, s.y);
        ctx.rotate(s.rotation);
        ctx.fillStyle = s.color;
        ctx.globalAlpha = s.alpha * 0.35; // Translucent and soft

        // Central soft splash droplet
        ctx.beginPath();
        ctx.arc(0, 0, s.size * 0.4, 0, Math.PI * 2);
        ctx.fill();

        // Radiating satellite drops
        s.droplets.forEach((d) => {
          ctx.beginPath();
          ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
          ctx.fill();
        });

        ctx.restore();
      });

      // 2. Draw Active Fruits
      fruitsRef.current.forEach((fruit) => {
        ctx.save();
        ctx.translate(fruit.x, fruit.y);
        ctx.rotate(fruit.rotation);

        if (fruit.config.isBomb) {
          // Draw High Quality Bomb
          const r = fruit.radius;

          // Shadow / Outer glow
          const grad = ctx.createRadialGradient(-r * 0.3, -r * 0.3, r * 0.1, 0, 0, r);
          grad.addColorStop(0, '#64748b');
          grad.addColorStop(0.5, '#1e293b');
          grad.addColorStop(1, '#020617');

          ctx.fillStyle = grad;
          ctx.beginPath();
          ctx.arc(0, 0, r, 0, Math.PI * 2);
          ctx.fill();

          // Cap & Fuse
          ctx.fillStyle = '#94a3b8';
          ctx.fillRect(-6, -r - 8, 12, 9);

          // Burning fuse spark
          const fuseProgress = (currentTime * 0.008) % 1;
          const sparkX = Math.sin(fuseProgress * Math.PI * 2) * 5;
          const sparkY = -r - 12;

          ctx.strokeStyle = '#ea580c';
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.moveTo(0, -r - 7);
          ctx.quadraticCurveTo(sparkX, sparkY - 6, sparkX * 1.5, sparkY - 10);
          ctx.stroke();

          // Spark flame
          ctx.fillStyle = '#facc15';
          ctx.beginPath();
          ctx.arc(sparkX * 1.5, sparkY - 10, 4 + Math.random() * 3, 0, Math.PI * 2);
          ctx.fill();

          // Warning Red Glow Pulse
          const pulse = (Math.sin(currentTime * 0.012) + 1) * 0.5;
          ctx.strokeStyle = `rgba(239, 68, 68, ${0.4 + pulse * 0.6})`;
          ctx.lineWidth = 4;
          ctx.beginPath();
          ctx.arc(0, 0, r + 4, 0, Math.PI * 2);
          ctx.stroke();

          // Danger skull or cross mark
          ctx.strokeStyle = '#f87171';
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.moveTo(-10, -10);
          ctx.lineTo(10, 10);
          ctx.moveTo(10, -10);
          ctx.lineTo(-10, 10);
          ctx.stroke();
        } else {
          // Check cached image
          const img = imageCacheRef.current[`${fruit.kind}_whole`];
          const r = fruit.radius;

          if (img && img.complete && img.naturalWidth > 0) {
            // Draw repository fruit texture
            ctx.shadowColor = 'rgba(0, 0, 0, 0.45)';
            ctx.shadowBlur = 12;
            ctx.shadowOffsetY = 6;
            ctx.drawImage(img, -r, -r, r * 2, r * 2);
            ctx.shadowColor = 'transparent';
          } else {
            // Fallback Vector Render with 3D gradient
            const grad = ctx.createRadialGradient(-r * 0.35, -r * 0.35, r * 0.1, 0, 0, r);
            grad.addColorStop(0, '#ffffff');
            grad.addColorStop(0.3, fruit.config.color);
            grad.addColorStop(1, '#0f172a');

            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.arc(0, 0, r, 0, Math.PI * 2);
            ctx.fill();

            // Leaf or stem
            ctx.fillStyle = '#15803d';
            ctx.beginPath();
            ctx.ellipse(0, -r, 8, 4, Math.PI / 4, 0, Math.PI * 2);
            ctx.fill();
          }
        }
        ctx.restore();
      });

      // 3. Draw Sliced Halves
      slicedHalvesRef.current.forEach((half) => {
        ctx.save();
        ctx.globalAlpha = half.opacity;
        ctx.translate(half.x, half.y);
        ctx.rotate(half.rotation);

        const imgCut = imageCacheRef.current[`${half.kind}_cut`];
        const r = half.config.radius;

        // Clip to half
        ctx.beginPath();
        if (half.half === 'left') {
          ctx.rect(-r - 10, -r - 10, r + 10, (r + 10) * 2);
        } else {
          ctx.rect(0, -r - 10, r + 10, (r + 10) * 2);
        }
        ctx.clip();

        if (imgCut && imgCut.complete && imgCut.naturalWidth > 0) {
          ctx.drawImage(imgCut, -r, -r, r * 2, r * 2);
        } else {
          // Fallback flesh render
          ctx.fillStyle = half.config.fleshColor;
          ctx.beginPath();
          ctx.arc(0, 0, r, 0, Math.PI * 2);
          ctx.fill();
          ctx.strokeStyle = half.config.color;
          ctx.lineWidth = 5;
          ctx.stroke();
        }

        ctx.restore();
      });

      // 4. Draw Juice Particles
      juiceParticlesRef.current.forEach((p) => {
        ctx.save();
        ctx.globalAlpha = p.alpha;
        ctx.fillStyle = p.color;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
      });

      // 5. Draw Blade Trail with Glowing Visual Styles
      const points = bladePointsRef.current;
      if (points.length >= 2) {
        ctx.save();
        const theme = settings.bladeTheme;

        for (let i = 1; i < points.length; i++) {
          const p1 = points[i - 1];
          const p2 = points[i];
          const progress = i / points.length;
          const lineWidth = Math.max(2, progress * 14);

          ctx.beginPath();
          ctx.moveTo(p1.x, p1.y);
          ctx.lineTo(p2.x, p2.y);

          // Blade styling
          if (theme === 'fire-katana') {
            ctx.strokeStyle = `rgba(249, 115, 22, ${progress * 0.9})`;
            ctx.shadowColor = '#ef4444';
          } else if (theme === 'rainbow-wave') {
            const hue = (currentTime * 0.2 + progress * 240) % 360;
            ctx.strokeStyle = `hsla(${hue}, 100%, 60%, ${progress * 0.9})`;
            ctx.shadowColor = `hsl(${hue}, 100%, 50%)`;
          } else if (theme === 'emerald-ninja') {
            ctx.strokeStyle = `rgba(16, 185, 129, ${progress * 0.9})`;
            ctx.shadowColor = '#10b981';
          } else if (theme === 'electric-violet') {
            ctx.strokeStyle = `rgba(168, 85, 247, ${progress * 0.9})`;
            ctx.shadowColor = '#c084fc';
          } else {
            // Neon Cyan (default)
            ctx.strokeStyle = `rgba(56, 189, 248, ${progress * 0.9})`;
            ctx.shadowColor = '#38bdf8';
          }

          ctx.shadowBlur = 16 * progress;
          ctx.lineWidth = lineWidth;
          ctx.lineCap = 'round';
          ctx.stroke();

          // Bright white blade core
          ctx.beginPath();
          ctx.moveTo(p1.x, p1.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.strokeStyle = `rgba(255, 255, 255, ${progress * 0.95})`;
          ctx.lineWidth = Math.max(1, lineWidth * 0.35);
          ctx.shadowBlur = 0;
          ctx.stroke();
        }
        ctx.restore();
      }

      // 6. Draw Floating Score Texts (+10, +30 COMBO!)
      floatingTextsRef.current.forEach((ft) => {
        ctx.save();
        ctx.globalAlpha = ft.alpha;
        ctx.font = `900 ${ft.size}px Outfit, system-ui, sans-serif`;
        ctx.fillStyle = ft.color;
        ctx.shadowColor = 'rgba(0, 0, 0, 0.9)';
        ctx.shadowBlur = 10;
        ctx.shadowOffsetY = 2;
        ctx.textAlign = 'center';
        ctx.fillText(ft.text, ft.x, ft.y);
        ctx.restore();
      });

      // 7. Draw Active Hand Cursor Indicator (when using Camera Motion)
      if (settings.inputMode !== 'mouse' && activeHandPosRef.current) {
        const hand = activeHandPosRef.current;
        ctx.save();
        ctx.translate(hand.x, hand.y);
        ctx.strokeStyle = 'rgba(56, 189, 248, 0.75)';
        ctx.lineWidth = 2.5;
        ctx.shadowColor = '#38bdf8';
        ctx.shadowBlur = 12;
        ctx.beginPath();
        ctx.arc(0, 0, 14, 0, Math.PI * 2);
        ctx.stroke();

        ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
        ctx.beginPath();
        ctx.arc(0, 0, 3.5, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
      }

      ctx.restore();
    };

    animId = requestAnimationFrame(loop);

    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener('resize', resizeCanvas);
    };
  }, [
    isPlaying,
    isPaused,
    settings.bladeTheme,
    settings.inputMode,
    motionTracker,
    onGameOver,
    onUpdateHUD,
    screenShake,
    spawnFruit,
    checkBladeCollision,
  ]);

  return (
    <div className="relative w-full h-full overflow-hidden select-none bg-radial from-slate-900 via-slate-950 to-black">
      {/* Wooden cutting board Dojo ambient texture */}
      <div
        className="absolute inset-0 opacity-15 pointer-events-none"
        style={{
          backgroundImage: `radial-gradient(circle at 50% 50%, rgba(245, 158, 11, 0.2) 0%, transparent 70%), repeating-linear-gradient(0deg, transparent, transparent 35px, rgba(255, 255, 255, 0.03) 36px)`,
        }}
      />

      {/* Main Interactive Game Canvas */}
      <canvas
        ref={canvasRef}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerLeave={handlePointerUp}
        className="relative z-10 w-full h-full touch-none cursor-crosshair"
      />

      {/* Combo Banner Popup */}
      {activeComboBanner && (
        <div className="absolute top-28 left-1/2 -translate-x-1/2 z-20 pointer-events-none animate-bounce">
          <div className="px-6 py-2.5 rounded-2xl bg-gradient-to-r from-amber-500 via-rose-500 to-purple-600 text-white font-black text-2xl tracking-wider shadow-2xl shadow-rose-500/50 flex items-center gap-3 border border-amber-300/40">
            <span>⚡</span>
            <span>{activeComboBanner.text}</span>
            <span className="text-yellow-200">+{activeComboBanner.score}</span>
          </div>
        </div>
      )}
    </div>
  );
};
