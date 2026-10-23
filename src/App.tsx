/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useRef } from 'react';
import {
  Play,
  Pause,
  RotateCcw,
  Sparkles,
  Trophy,
  Flame,
  Settings,
  FolderGit2,
  Layers,
  Camera,
  ShieldAlert,
} from 'lucide-react';
import confetti from 'canvas-confetti';
import { FruitCanvas } from './components/FruitCanvas';
import { CameraPreviewWidget } from './components/CameraPreviewWidget';
import { FruitAssetLab } from './components/FruitAssetLab';
import { RepoHub } from './components/RepoHub';
import { SettingsModal } from './components/SettingsModal';
import { CameraMotionTracker } from './vision/CameraMotionTracker';
import { soundSynthesizer } from './core/SoundSynthesizer';
import { GameSettings, GameStats } from './types/game';

const DEFAULT_SETTINGS: GameSettings = {
  inputMode: 'hybrid',
  bladeTheme: 'neon-cyan',
  sfxVolume: 0.8,
  sensitivity: 1.0,
  cameraMirror: true,
  leftHanded: false,
  roundDuration: 90,
  showMotionDebug: false,
};

export default function App() {
  // Views
  const [activeView, setActiveView] = useState<'game' | 'lab' | 'repo'>('game');
  const [showSettings, setShowSettings] = useState(false);

  // Game States
  const [gameState, setGameState] = useState<'menu' | 'playing' | 'paused' | 'gameover'>('menu');
  const [score, setScore] = useState(0);
  const [timeLeft, setTimeLeft] = useState(90);
  const [combo, setCombo] = useState(0);
  const [maxCombo, setMaxCombo] = useState(0);
  const [highScore, setHighScore] = useState(0);
  const [finalStats, setFinalStats] = useState<GameStats | null>(null);

  // Settings
  const [settings, setSettings] = useState<GameSettings>(() => {
    try {
      const saved = localStorage.getItem('fruitwave_settings');
      return saved ? { ...DEFAULT_SETTINGS, ...JSON.parse(saved) } : DEFAULT_SETTINGS;
    } catch {
      return DEFAULT_SETTINGS;
    }
  });

  // Camera & Motion Tracker
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const motionTrackerRef = useRef<CameraMotionTracker>(new CameraMotionTracker());
  const [cameraActive, setCameraActive] = useState(false);

  // Load High Score on boot
  useEffect(() => {
    try {
      const savedHighScore = localStorage.getItem('fruitwave_high_score');
      if (savedHighScore) {
        setHighScore(parseInt(savedHighScore, 10));
      }
    } catch {
      // ignore
    }
  }, []);

  // Sync settings with audio & motion tracker
  useEffect(() => {
    soundSynthesizer.volume = settings.sfxVolume;
    motionTrackerRef.current.sensitivity = settings.sensitivity;
    motionTrackerRef.current.mirror = settings.cameraMirror;
    motionTrackerRef.current.leftHandOnly = settings.leftHanded;
    localStorage.setItem('fruitwave_settings', JSON.stringify(settings));
  }, [settings]);

  // Toggle Camera
  const toggleCamera = async () => {
    if (cameraActive) {
      motionTrackerRef.current.stopCamera();
      setCameraActive(false);
    } else if (videoRef.current) {
      const ok = await motionTrackerRef.current.startCamera(videoRef.current);
      setCameraActive(ok);
    }
  };

  // Start game round
  const handleStartGame = async () => {
    // If hybrid or camera mode and camera not yet started, attempt starting
    if (settings.inputMode !== 'mouse' && !cameraActive && videoRef.current) {
      await motionTrackerRef.current.startCamera(videoRef.current).then((ok) => setCameraActive(ok));
    }
    setScore(0);
    setTimeLeft(settings.roundDuration);
    setCombo(0);
    setMaxCombo(0);
    setFinalStats(null);
    setGameState('playing');
  };

  const handlePauseToggle = () => {
    if (gameState === 'playing') {
      setGameState('paused');
    } else if (gameState === 'paused') {
      setGameState('playing');
    }
  };

  const handleGameOver = (stats: GameStats) => {
    setGameState('gameover');
    setFinalStats(stats);

    if (stats.score > highScore) {
      setHighScore(stats.score);
      localStorage.setItem('fruitwave_high_score', stats.score.toString());
      confetti({ particleCount: 80, spread: 100, origin: { y: 0.6 } });
    }
  };

  const handleResetHighScore = () => {
    setHighScore(0);
    localStorage.removeItem('fruitwave_high_score');
  };

  // Rank calculation
  const getRank = (scoreVal: number) => {
    if (scoreVal >= 450) return { letter: 'S+', color: 'text-amber-400' };
    if (scoreVal >= 350) return { letter: 'S', color: 'text-yellow-400' };
    if (scoreVal >= 250) return { letter: 'A', color: 'text-emerald-400' };
    if (scoreVal >= 150) return { letter: 'B', color: 'text-cyan-400' };
    return { letter: 'C', color: 'text-slate-400' };
  };

  return (
    <div className="relative w-screen h-screen overflow-hidden bg-black text-slate-100 font-sans select-none">
      {/* Top Navigation & HUD Bar */}
      <header className="absolute top-0 left-0 right-0 z-30 flex items-center justify-between px-4 sm:px-6 py-3 bg-gradient-to-b from-black/80 via-black/40 to-transparent backdrop-blur-xs">
        {/* Logo & Title */}
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-tr from-rose-500 via-amber-500 to-emerald-400 flex items-center justify-center shadow-lg shadow-rose-950/50">
            <Sparkles className="w-5 h-5 text-white" />
          </div>
          <div>
            <div className="text-base font-black tracking-wider flex items-center gap-2">
              <span className="bg-gradient-to-r from-emerald-400 via-teal-300 to-cyan-400 bg-clip-text text-transparent">
                FruitWave
              </span>
              <span className="text-[10px] uppercase font-bold tracking-widest px-2 py-0.5 rounded-full bg-cyan-950/80 border border-cyan-800/60 text-cyan-300">
                Web & Vision
              </span>
            </div>
            <div className="text-[11px] text-slate-400 hidden sm:block">
              体感手势切水果 · 还原 tvOS 核心物理与程序化音效
            </div>
          </div>
        </div>

        {/* Live In-Game HUD Elements */}
        {gameState === 'playing' && (
          <div className="flex items-center gap-5 sm:gap-8 animate-fade-in">
            {/* Score */}
            <div className="text-center">
              <div className="text-[10px] uppercase tracking-wider text-slate-400 font-semibold">分数</div>
              <div className="text-2xl font-black text-amber-400 font-mono tracking-tight drop-shadow-md">
                {score}
              </div>
            </div>

            {/* Time Left */}
            <div className="text-center">
              <div className="text-[10px] uppercase tracking-wider text-slate-400 font-semibold">倒计时</div>
              <div
                className={`text-2xl font-black font-mono tracking-tight drop-shadow-md ${
                  timeLeft <= 10 ? 'text-rose-500 animate-pulse' : 'text-cyan-400'
                }`}
              >
                {timeLeft}s
              </div>
            </div>

            {/* Streak / Combo */}
            <div className="text-center hidden sm:block">
              <div className="text-[10px] uppercase tracking-wider text-slate-400 font-semibold">最高连击</div>
              <div className="text-2xl font-black text-emerald-400 font-mono tracking-tight flex items-center gap-1">
                <Flame className="w-5 h-5 text-rose-500 fill-rose-500" />
                {maxCombo}x
              </div>
            </div>

            {/* Pause Button */}
            <button
              onClick={handlePauseToggle}
              className="p-2 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-200 transition-colors"
              title="暂停"
            >
              <Pause className="w-4 h-4" />
            </button>
          </div>
        )}

        {/* Right Menu & Feature Buttons */}
        <div className="flex items-center gap-2">
          {/* High Score Trophy */}
          <div className="hidden md:flex items-center gap-1.5 px-3 py-1 rounded-xl bg-amber-950/40 border border-amber-800/40 text-amber-300 text-xs font-bold">
            <Trophy className="w-3.5 h-3.5 text-amber-400 fill-amber-400" />
            <span>纪录: {highScore}</span>
          </div>

          {/* Asset Lab */}
          <button
            onClick={() => setActiveView('lab')}
            className={`p-2 rounded-xl border text-xs font-semibold flex items-center gap-1.5 transition-colors ${
              activeView === 'lab'
                ? 'bg-cyan-500/20 border-cyan-500 text-cyan-300'
                : 'bg-slate-900/80 border-slate-800 text-slate-300 hover:bg-slate-800'
            }`}
            title="水果资产与物理测试实验室"
          >
            <Layers className="w-4 h-4" />
            <span className="hidden sm:inline">资产实验室</span>
          </button>

          {/* Repo Hub */}
          <button
            onClick={() => setActiveView('repo')}
            className={`p-2 rounded-xl border text-xs font-semibold flex items-center gap-1.5 transition-colors ${
              activeView === 'repo'
                ? 'bg-purple-500/20 border-purple-500 text-purple-300'
                : 'bg-slate-900/80 border-slate-800 text-slate-300 hover:bg-slate-800'
            }`}
            title="GitHub 仓库配置与架构"
          >
            <FolderGit2 className="w-4 h-4" />
            <span className="hidden sm:inline">GitHub 仓库</span>
          </button>

          {/* Settings */}
          <button
            onClick={() => setShowSettings(true)}
            className="p-2 rounded-xl bg-slate-900/80 border border-slate-800 text-slate-300 hover:bg-slate-800 transition-colors"
            title="设置"
          >
            <Settings className="w-4 h-4" />
          </button>
        </div>
      </header>

      {/* Main Game Canvas Container */}
      <main className="w-full h-full relative">
        <FruitCanvas
          isPlaying={gameState === 'playing'}
          isPaused={gameState === 'paused'}
          settings={settings}
          motionTracker={motionTrackerRef.current}
          onGameOver={handleGameOver}
          onUpdateHUD={({ score: sc, timeLeft: tl, combo: cb, maxCombo: mc }) => {
            setScore(sc);
            setTimeLeft(tl);
            setCombo(cb);
            setMaxCombo(mc);
          }}
        />

        {/* Start Menu Overlay */}
        {gameState === 'menu' && (
          <div className="absolute inset-0 z-20 flex flex-col items-center justify-center p-4 bg-black/60 backdrop-blur-xs">
            <div className="max-w-md w-full text-center space-y-6">
              {/* Badge */}
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-slate-900/90 border border-cyan-500/30 text-cyan-300 text-xs font-semibold shadow-lg">
                <Sparkles className="w-3.5 h-3.5 text-cyan-400" />
                90 秒官方经典模式 · 20 款真实水果
              </div>

              {/* Title Header */}
              <div>
                <h1 className="text-4xl sm:text-5xl font-black tracking-tight text-white drop-shadow-lg">
                  准备好挥砍了吗？
                </h1>
                <p className="text-sm text-slate-300 mt-2 leading-relaxed">
                  开启摄像头通过手腕与手臂体感起刀，亦可使用鼠标或屏幕触控滑动畅快切割！
                </p>
              </div>

              {/* Action Buttons */}
              <div className="flex flex-col sm:flex-row items-center justify-center gap-3 pt-2">
                <button
                  onClick={handleStartGame}
                  className="w-full sm:w-auto px-8 py-3.5 rounded-2xl bg-gradient-to-r from-emerald-500 via-teal-500 to-cyan-500 hover:from-emerald-400 hover:to-cyan-400 text-slate-950 font-black text-lg tracking-wide shadow-xl shadow-emerald-950/60 flex items-center justify-center gap-2.5 transition-all transform hover:scale-105 active:scale-95"
                >
                  <Play className="w-5 h-5 fill-current" />
                  立即开始 (START)
                </button>

                <button
                  onClick={toggleCamera}
                  className={`w-full sm:w-auto px-5 py-3.5 rounded-2xl border text-sm font-bold flex items-center justify-center gap-2 transition-all ${
                    cameraActive
                      ? 'bg-cyan-950/80 border-cyan-500 text-cyan-300'
                      : 'bg-slate-900/90 border-slate-700 text-slate-300 hover:bg-slate-800'
                  }`}
                >
                  <Camera className="w-4 h-4" />
                  {cameraActive ? '体感摄像头就绪' : '启用体感摄像头'}
                </button>
              </div>

              {/* Quick instructions */}
              <div className="grid grid-cols-3 gap-2.5 pt-4 text-[11px] text-slate-400 font-medium">
                <div className="p-2.5 rounded-xl bg-slate-900/60 border border-slate-800/80">
                  <div className="text-slate-200 font-bold mb-0.5">🍎 10分/水果</div>
                  <div>切中连续得分</div>
                </div>
                <div className="p-2.5 rounded-xl bg-slate-900/60 border border-slate-800/80">
                  <div className="text-amber-300 font-bold mb-0.5">⚡ 连击加成</div>
                  <div>3+ 水果倍数翻倍</div>
                </div>
                <div className="p-2.5 rounded-xl bg-slate-900/60 border border-slate-800/80">
                  <div className="text-rose-400 font-bold mb-0.5">💣 危险炸弹</div>
                  <div>触碰引爆扣50分</div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Pause Overlay */}
        {gameState === 'paused' && (
          <div className="absolute inset-0 z-20 flex flex-col items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
            <div className="max-w-sm w-full bg-slate-900 border border-slate-800 rounded-3xl p-6 text-center shadow-2xl space-y-4">
              <h2 className="text-2xl font-black text-white">游戏已暂停</h2>
              <p className="text-xs text-slate-400">深呼吸，准备下一波水果风暴！</p>

              <div className="flex flex-col gap-2.5 pt-2">
                <button
                  onClick={handlePauseToggle}
                  className="w-full py-3 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 hover:from-emerald-400 hover:to-teal-400 text-slate-950 font-bold flex items-center justify-center gap-2 transition-colors"
                >
                  <Play className="w-4 h-4 fill-current" />
                  继续本局 (Resume)
                </button>

                <button
                  onClick={handleStartGame}
                  className="w-full py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold flex items-center justify-center gap-2 transition-colors"
                >
                  <RotateCcw className="w-3.5 h-3.5" />
                  重新开始 (Restart)
                </button>

                <button
                  onClick={() => setGameState('menu')}
                  className="w-full py-2 rounded-xl text-slate-400 hover:text-white text-xs font-medium transition-colors"
                >
                  退出至主菜单
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Game Over / Settlement Modal */}
        {gameState === 'gameover' && finalStats && (
          <div className="absolute inset-0 z-20 flex flex-col items-center justify-center p-4 bg-black/80 backdrop-blur-md">
            <div className="max-w-md w-full bg-slate-900 border border-slate-800 rounded-3xl p-6 sm:p-8 text-center shadow-2xl space-y-6">
              {/* Rank Header */}
              <div>
                <div className="text-xs uppercase font-bold tracking-widest text-slate-400 mb-1">
                  本局结算 · ROUND COMPLETED
                </div>
                <div className="text-6xl font-black font-mono tracking-tight text-amber-400 drop-shadow-md">
                  {finalStats.score}
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  评级：<span className={`text-lg font-black ${getRank(finalStats.score).color}`}>{getRank(finalStats.score).letter}</span>
                  {finalStats.score >= highScore && finalStats.score > 0 && (
                    <span className="ml-2 text-emerald-400 font-bold">✨ 新历史纪录！</span>
                  )}
                </div>
              </div>

              {/* Stats Summary Grid */}
              <div className="grid grid-cols-3 gap-2.5 py-3 border-y border-slate-800 text-left">
                <div className="bg-slate-800/40 p-2.5 rounded-xl border border-slate-800">
                  <div className="text-[10px] text-slate-400">斩获水果</div>
                  <div className="text-base font-bold text-slate-100">{finalStats.fruitsSliced} 个</div>
                </div>

                <div className="bg-slate-800/40 p-2.5 rounded-xl border border-slate-800">
                  <div className="text-[10px] text-slate-400">最高连击</div>
                  <div className="text-base font-bold text-rose-400">{finalStats.maxCombo}x</div>
                </div>

                <div className="bg-slate-800/40 p-2.5 rounded-xl border border-slate-800">
                  <div className="text-[10px] text-slate-400">引爆炸弹</div>
                  <div className="text-base font-bold text-amber-400">{finalStats.bombsHit} 次</div>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex gap-3">
                <button
                  onClick={handleStartGame}
                  className="flex-1 py-3.5 rounded-xl bg-gradient-to-r from-emerald-500 to-cyan-500 hover:from-emerald-400 hover:to-cyan-400 text-slate-950 font-bold text-sm flex items-center justify-center gap-2 shadow-lg shadow-emerald-950/50 transition-all"
                >
                  <RotateCcw className="w-4 h-4" />
                  再来一局 (Play Again)
                </button>

                <button
                  onClick={() => setGameState('menu')}
                  className="px-4 py-3.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-sm font-semibold transition-colors"
                >
                  主菜单
                </button>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* Floating Camera Preview PIP Widget */}
      <CameraPreviewWidget
        videoRef={videoRef}
        motionTracker={motionTrackerRef.current}
        cameraActive={cameraActive}
        onToggleCamera={toggleCamera}
        mirror={settings.cameraMirror}
        onToggleMirror={() => setSettings((s) => ({ ...s, cameraMirror: !s.cameraMirror }))}
      />

      {/* Fruit & Asset Lab View */}
      {activeView === 'lab' && <FruitAssetLab onBack={() => setActiveView('game')} />}

      {/* Git Repository Hub View */}
      {activeView === 'repo' && <RepoHub onBack={() => setActiveView('game')} />}

      {/* Settings Modal */}
      {showSettings && (
        <SettingsModal
          settings={settings}
          onUpdateSettings={(newSettings) => setSettings((prev) => ({ ...prev, ...newSettings }))}
          onClose={() => setShowSettings(false)}
          onResetHighScore={handleResetHighScore}
        />
      )}
    </div>
  );
}
