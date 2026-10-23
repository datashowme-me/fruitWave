import React from 'react';
import { X, Volume2, Camera, MousePointer, Sparkles, Sliders, RotateCcw } from 'lucide-react';
import { BladeTheme, GameSettings, InputMode } from '../types/game';

interface SettingsModalProps {
  settings: GameSettings;
  onUpdateSettings: (newSettings: Partial<GameSettings>) => void;
  onClose: () => void;
  onResetHighScore: () => void;
}

export const SettingsModal: React.FC<SettingsModalProps> = ({
  settings,
  onUpdateSettings,
  onClose,
  onResetHighScore,
}) => {
  const bladeThemes: { id: BladeTheme; name: string; color: string }[] = [
    { id: 'neon-cyan', name: '霓虹青 (Neon Cyan)', color: '#38bdf8' },
    { id: 'fire-katana', name: '烈焰武士 (Fire Katana)', color: '#f97316' },
    { id: 'rainbow-wave', name: '彩虹光刃 (Rainbow Wave)', color: '#ec4899' },
    { id: 'emerald-ninja', name: '翡翠忍者 (Emerald Ninja)', color: '#10b981' },
    { id: 'electric-violet', name: '闪电紫 (Electric Violet)', color: '#a855f7' },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md">
      <div className="w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl p-6 shadow-2xl relative text-slate-100">
        <button
          onClick={onClose}
          className="absolute top-5 right-5 p-2 rounded-full hover:bg-slate-800 text-slate-400 hover:text-white transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        <h2 className="text-xl font-bold flex items-center gap-2 mb-6">
          <Sliders className="w-5 h-5 text-cyan-400" />
          游戏与体感设置 (Settings)
        </h2>

        <div className="space-y-6 max-h-[70vh] overflow-y-auto pr-1">
          {/* Input Mode */}
          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 block mb-2.5">
              控制输入方式 (Input Control)
            </label>
            <div className="grid grid-cols-3 gap-2">
              {[
                { id: 'hybrid', label: '混合模式', sub: '摄像头 + 鼠标触摸', icon: Sparkles },
                { id: 'camera', label: '纯体感', sub: '仅摄像头手势', icon: Camera },
                { id: 'mouse', label: '触控/鼠标', sub: '鼠标或屏幕滑动', icon: MousePointer },
              ].map((m) => {
                const Icon = m.icon;
                const isSelected = settings.inputMode === m.id;
                return (
                  <button
                    key={m.id}
                    onClick={() => onUpdateSettings({ inputMode: m.id as InputMode })}
                    className={`p-3 rounded-2xl border text-left transition-all ${
                      isSelected
                        ? 'bg-cyan-500/20 border-cyan-500 shadow-md shadow-cyan-950 text-cyan-300'
                        : 'bg-slate-800/40 border-slate-800 hover:bg-slate-800 text-slate-400'
                    }`}
                  >
                    <Icon className="w-4 h-4 mb-1.5" />
                    <div className="text-xs font-bold">{m.label}</div>
                    <div className="text-[10px] opacity-75">{m.sub}</div>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Blade Theme */}
          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 block mb-2.5">
              刀光斩击特效 (Blade Trail Style)
            </label>
            <div className="grid grid-cols-2 gap-2">
              {bladeThemes.map((b) => (
                <button
                  key={b.id}
                  onClick={() => onUpdateSettings({ bladeTheme: b.id })}
                  className={`p-2.5 rounded-xl border flex items-center gap-3 transition-all ${
                    settings.bladeTheme === b.id
                      ? 'bg-slate-800 border-slate-500'
                      : 'bg-slate-900 border-slate-800 hover:bg-slate-800/50'
                  }`}
                >
                  <span
                    className="w-4 h-4 rounded-full shadow-md"
                    style={{ backgroundColor: b.color }}
                  />
                  <span className="text-xs font-medium text-slate-200">{b.name}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Sensitivity */}
          <div>
            <div className="flex justify-between items-center mb-2">
              <label className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                体感起刀灵敏度
              </label>
              <span className="text-xs font-mono text-cyan-400 font-bold">
                {settings.sensitivity.toFixed(1)}x
              </span>
            </div>
            <input
              type="range"
              min="0.5"
              max="2.0"
              step="0.1"
              value={settings.sensitivity}
              onChange={(e) => onUpdateSettings({ sensitivity: parseFloat(e.target.value) })}
              className="w-full accent-cyan-400"
            />
            <div className="flex justify-between text-[10px] text-slate-500 mt-1">
              <span>稳定防误触 (0.5x)</span>
              <span>原版 tvOS (1.0x)</span>
              <span>极速起刀 (2.0x)</span>
            </div>
          </div>

          {/* Duration */}
          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 block mb-2.5">
              单局时长 (Round Duration)
            </label>
            <div className="flex gap-2">
              {[60, 90, 120].map((sec) => (
                <button
                  key={sec}
                  onClick={() => onUpdateSettings({ roundDuration: sec })}
                  className={`flex-1 py-2 rounded-xl text-xs font-bold border transition-all ${
                    settings.roundDuration === sec
                      ? 'bg-cyan-500 text-slate-950 border-cyan-400 shadow-md'
                      : 'bg-slate-800/50 border-slate-800 text-slate-300 hover:bg-slate-800'
                  }`}
                >
                  {sec} 秒 {sec === 90 && '(官方原版)'}
                </button>
              ))}
            </div>
          </div>

          {/* Volume */}
          <div>
            <div className="flex justify-between items-center mb-2">
              <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
                <Volume2 className="w-4 h-4" />
                程序化音效音量
              </label>
              <span className="text-xs font-mono text-cyan-400 font-bold">
                {Math.round(settings.sfxVolume * 100)}%
              </span>
            </div>
            <input
              type="range"
              min="0"
              max="1"
              step="0.05"
              value={settings.sfxVolume}
              onChange={(e) => onUpdateSettings({ sfxVolume: parseFloat(e.target.value) })}
              className="w-full accent-cyan-400"
            />
          </div>

          {/* Reset button */}
          <div className="pt-2 border-t border-slate-800 flex justify-between items-center">
            <span className="text-xs text-slate-500">清除本地保存的最高分</span>
            <button
              onClick={onResetHighScore}
              className="px-3 py-1.5 rounded-lg bg-rose-950/40 hover:bg-rose-900/60 border border-rose-800/50 text-xs text-rose-300 font-medium flex items-center gap-1.5 transition-colors"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              重置最高分
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
