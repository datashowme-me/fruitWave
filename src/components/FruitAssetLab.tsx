import React, { useState } from 'react';
import { FRUIT_CATALOG, REGULAR_FRUITS } from '../data/fruitCatalog';
import { FruitKind } from '../types/game';
import { soundSynthesizer } from '../core/SoundSynthesizer';
import { Play, Volume2, Sparkles, Layers, Sliders, ArrowLeft } from 'lucide-react';

interface FruitAssetLabProps {
  onBack: () => void;
}

export const FruitAssetLab: React.FC<FruitAssetLabProps> = ({ onBack }) => {
  const [selectedFruit, setSelectedFruit] = useState<FruitKind>('watermelon');
  const [isSlicedPreview, setIsSlicedPreview] = useState(false);
  const [comboCount, setComboCount] = useState(1);

  const fruit = FRUIT_CATALOG[selectedFruit];

  const handleTestCut = () => {
    soundSynthesizer.playSlice(comboCount);
    setIsSlicedPreview(true);
    setTimeout(() => setIsSlicedPreview(false), 900);
  };

  const handleTestWhoosh = () => {
    soundSynthesizer.playWhoosh(1.4);
  };

  const handleTestExplosion = () => {
    soundSynthesizer.playExplosion();
  };

  const handleTestFanfare = () => {
    soundSynthesizer.playComboFanfare(comboCount);
  };

  return (
    <div className="fixed inset-0 z-40 bg-slate-950 text-slate-100 overflow-y-auto p-4 sm:p-8">
      {/* Top Bar */}
      <div className="max-w-6xl mx-auto flex items-center justify-between pb-6 border-b border-slate-800">
        <div className="flex items-center gap-4">
          <button
            onClick={onBack}
            className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 transition-colors font-medium text-sm"
          >
            <ArrowLeft className="w-4 h-4" />
            返回游戏
          </button>
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2.5">
              <Sparkles className="w-6 h-6 text-amber-400" />
              FruitWave 资产与物理实验室 (Asset Lab)
            </h1>
            <p className="text-xs text-slate-400 mt-0.5">
              对应 Swift 原型中的 <code className="text-cyan-300">FruitAssetLabView.swift</code> 与 PRD v1.0 资产规格
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <span className="text-xs text-slate-400 bg-slate-900 px-3 py-1.5 rounded-lg border border-slate-800">
            共 <strong className="text-emerald-400">{REGULAR_FRUITS.length}</strong> 种水果资产就绪
          </span>
        </div>
      </div>

      <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-8 mt-6">
        {/* Left: Fruits Grid Selection */}
        <div className="lg:col-span-1 bg-slate-900/80 rounded-2xl p-5 border border-slate-800/80">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-400 mb-3 flex items-center gap-2">
            <Layers className="w-4 h-4 text-cyan-400" />
            水果模型库 (Fruit Catalog)
          </h2>
          <div className="grid grid-cols-2 gap-2.5 max-h-[620px] overflow-y-auto pr-1">
            {REGULAR_FRUITS.map((kind) => {
              const item = FRUIT_CATALOG[kind];
              const isSelected = selectedFruit === kind;
              return (
                <button
                  key={kind}
                  onClick={() => {
                    setSelectedFruit(kind);
                    setIsSlicedPreview(false);
                    soundSynthesizer.playSlice(1);
                  }}
                  className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all ${
                    isSelected
                      ? 'bg-cyan-950/60 border-cyan-500 shadow-lg shadow-cyan-950/50 scale-[1.02]'
                      : 'bg-slate-800/40 border-slate-800 hover:bg-slate-800 hover:border-slate-700'
                  }`}
                >
                  <img
                    src={item.imageWhole}
                    alt={item.displayName}
                    className="w-12 h-12 object-contain drop-shadow-md"
                  />
                  <div className="text-center">
                    <div className="text-xs font-bold text-slate-200">{item.displayName}</div>
                    <div className="text-[10px] text-slate-400">{item.kind}</div>
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Middle: 3D/2D Visual Inspection Stage */}
        <div className="lg:col-span-2 flex flex-col gap-6">
          <div className="bg-slate-900/80 rounded-2xl p-6 border border-slate-800/80 relative overflow-hidden flex flex-col items-center justify-center min-h-[360px]">
            {/* Stage Spotlight Glow */}
            <div
              className="absolute w-72 h-72 rounded-full blur-3xl opacity-20 pointer-events-none"
              style={{ backgroundColor: fruit.color }}
            />

            <div className="relative z-10 flex flex-col items-center">
              <div className="text-center mb-4">
                <span className="text-xs font-semibold px-2.5 py-1 rounded-full uppercase tracking-wider bg-slate-800 text-slate-300">
                  {fruit.displayName} · {fruit.kind}
                </span>
              </div>

              {/* Fruit Display Stage */}
              <div className="relative w-48 h-48 flex items-center justify-center">
                {!isSlicedPreview ? (
                  <img
                    src={fruit.imageWhole}
                    alt="Whole"
                    className="w-40 h-40 object-contain drop-shadow-2xl animate-pulse"
                  />
                ) : (
                  <div className="relative flex items-center gap-4 animate-bounce">
                    <div className="overflow-hidden w-20 h-40 flex items-center justify-end">
                      <img
                        src={fruit.imageCut}
                        alt="Cut Left"
                        className="w-40 h-40 max-w-none -translate-x-10 object-contain drop-shadow-2xl"
                      />
                    </div>
                    <div className="overflow-hidden w-20 h-40 flex items-center justify-start">
                      <img
                        src={fruit.imageCut}
                        alt="Cut Right"
                        className="w-40 h-40 max-w-none translate-x-0 object-contain drop-shadow-2xl"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Action Buttons */}
              <div className="flex items-center gap-3 mt-6">
                <button
                  onClick={handleTestCut}
                  className="px-5 py-2 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-600 hover:from-emerald-400 hover:to-teal-500 text-white font-semibold shadow-lg shadow-emerald-900/40 flex items-center gap-2 transition-all"
                >
                  <Play className="w-4 h-4 fill-current" />
                  模拟切割音画 (Slice Trigger)
                </button>
              </div>
            </div>
          </div>

          {/* Sound & Physical Parameters Card */}
          <div className="bg-slate-900/80 rounded-2xl p-6 border border-slate-800/80">
            <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-400 mb-4 flex items-center gap-2">
              <Sliders className="w-4 h-4 text-amber-400" />
              程序化音效与物理测试 (Procedural Audio & Physics)
            </h2>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
              <div>
                <label className="text-xs text-slate-300 font-medium block mb-2">
                  连击音调阶梯 (Combo Pitch Level: {comboCount}x)
                </label>
                <input
                  type="range"
                  min="1"
                  max="10"
                  value={comboCount}
                  onChange={(e) => setComboCount(parseInt(e.target.value))}
                  className="w-full accent-cyan-400"
                />
                <p className="text-[11px] text-slate-500 mt-1">
                  每连续命中一个水果，音高递增半音 (Ported from SoundEffects.swift)
                </p>

                <div className="flex gap-2 mt-4">
                  <button
                    onClick={() => soundSynthesizer.playSlice(comboCount)}
                    className="flex-1 py-1.5 px-3 rounded-lg bg-slate-800 hover:bg-slate-700 text-xs font-semibold text-cyan-300 flex items-center justify-center gap-1.5"
                  >
                    <Volume2 className="w-3.5 h-3.5" />
                    测试切割声
                  </button>
                  <button
                    onClick={handleTestFanfare}
                    className="flex-1 py-1.5 px-3 rounded-lg bg-slate-800 hover:bg-slate-700 text-xs font-semibold text-amber-300 flex items-center justify-center gap-1.5"
                  >
                    <Sparkles className="w-3.5 h-3.5" />
                    测试连击号角
                  </button>
                </div>
              </div>

              <div>
                <label className="text-xs text-slate-300 font-medium block mb-2">其他物理音效</label>
                <div className="flex flex-col gap-2">
                  <button
                    onClick={handleTestWhoosh}
                    className="py-1.5 px-3 rounded-lg bg-slate-800 hover:bg-slate-700 text-xs font-semibold text-slate-200 flex items-center justify-between"
                  >
                    <span>起刀风声 (Slash Whoosh)</span>
                    <Play className="w-3 h-3 text-slate-400" />
                  </button>
                  <button
                    onClick={handleTestExplosion}
                    className="py-1.5 px-3 rounded-lg bg-rose-950/40 hover:bg-rose-900/60 border border-rose-800/40 text-xs font-semibold text-rose-300 flex items-center justify-between"
                  >
                    <span>炸弹引爆 (Bomb Detonate)</span>
                    <Play className="w-3 h-3 text-rose-400" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
