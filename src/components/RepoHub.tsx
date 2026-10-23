import React, { useState } from 'react';
import { GitBranch, GitCommit, FolderGit2, ArrowLeft, ExternalLink, Terminal, BookOpen, Code2, CheckCircle2 } from 'lucide-react';

interface RepoHubProps {
  onBack: () => void;
}

export const RepoHub: React.FC<RepoHubProps> = ({ onBack }) => {
  const [activeTab, setActiveTab] = useState<'overview' | 'architecture' | 'git'>('overview');

  return (
    <div className="fixed inset-0 z-40 bg-slate-950 text-slate-100 overflow-y-auto p-4 sm:p-8">
      {/* Header */}
      <div className="max-w-5xl mx-auto flex items-center justify-between pb-6 border-b border-slate-800">
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
              <FolderGit2 className="w-6 h-6 text-cyan-400" />
              GitHub 仓库配置与架构中心 (Repo Hub)
            </h1>
            <p className="text-xs text-slate-400 mt-0.5">
              已挂载：<code className="text-cyan-300">https://github.com/datashowme-me/fruitWave.git</code>
            </p>
          </div>
        </div>

        <a
          href="https://github.com/datashowme-me/fruitWave"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-xs font-semibold text-slate-200 transition-colors"
        >
          <span>在 GitHub 打开</span>
          <ExternalLink className="w-3.5 h-3.5 text-slate-400" />
        </a>
      </div>

      {/* Tabs */}
      <div className="max-w-5xl mx-auto flex gap-2 mt-6">
        <button
          onClick={() => setActiveTab('overview')}
          className={`px-4 py-2 rounded-xl text-xs font-semibold transition-colors flex items-center gap-2 ${
            activeTab === 'overview'
              ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
              : 'text-slate-400 hover:text-white bg-slate-900 border border-slate-800'
          }`}
        >
          <Code2 className="w-4 h-4" />
          项目概览与结构
        </button>
        <button
          onClick={() => setActiveTab('architecture')}
          className={`px-4 py-2 rounded-xl text-xs font-semibold transition-colors flex items-center gap-2 ${
            activeTab === 'architecture'
              ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
              : 'text-slate-400 hover:text-white bg-slate-900 border border-slate-800'
          }`}
        >
          <BookOpen className="w-4 h-4" />
          Swift 核心架构 (FruitWaveCore)
        </button>
        <button
          onClick={() => setActiveTab('git')}
          className={`px-4 py-2 rounded-xl text-xs font-semibold transition-colors flex items-center gap-2 ${
            activeTab === 'git'
              ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
              : 'text-slate-400 hover:text-white bg-slate-900 border border-slate-800'
          }`}
        >
          <GitBranch className="w-4 h-4" />
          Git 同步与分支指令
        </button>
      </div>

      <div className="max-w-5xl mx-auto mt-6">
        {activeTab === 'overview' && (
          <div className="space-y-6">
            <div className="bg-slate-900/80 rounded-2xl p-6 border border-slate-800/80">
              <h3 className="text-base font-bold text-white mb-2 flex items-center gap-2">
                <CheckCircle2 className="w-5 h-5 text-emerald-400" />
                代码库已成功同步并接入当前开发环境
              </h3>
              <p className="text-sm text-slate-300 leading-relaxed">
                你的 GitHub 仓库 <strong className="text-cyan-300">fruitWave</strong> 已完整迁入本环境。我们在保留全部 Swift/Xcode 原工程文件的同时，完成了 Web 端的移植与 60fps 实时体感渲染器，使你既可以在网页中直观调试物理、音效与手势，也可以继续修改原有 Swift/tvOS 代码。
              </p>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-6">
                <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-800">
                  <div className="text-xs text-slate-400">当前分支</div>
                  <div className="text-lg font-bold text-cyan-400 flex items-center gap-1.5 mt-1">
                    <GitBranch className="w-4 h-4" />
                    main
                  </div>
                </div>

                <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-800">
                  <div className="text-xs text-slate-400">已导入美术资产</div>
                  <div className="text-lg font-bold text-emerald-400 mt-1">
                    20 种水果 Whole & Cut
                  </div>
                </div>

                <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-800">
                  <div className="text-xs text-slate-400">核心算法移植</div>
                  <div className="text-lg font-bold text-purple-400 mt-1">
                    1€ 滤波 + 滞回起刀
                  </div>
                </div>
              </div>
            </div>

            {/* Directory tree */}
            <div className="bg-slate-900/80 rounded-2xl p-6 border border-slate-800/80">
              <h4 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-4">
                工作区目录布局 (Workspace Structure)
              </h4>
              <div className="font-mono text-xs text-slate-300 bg-slate-950 p-4 rounded-xl border border-slate-800/80 leading-relaxed overflow-x-auto">
                <div>📁 <span className="text-cyan-300">FruitWaveApp/</span> — tvOS App, 连续互通相机, Vision 姿态识别, SpriteKit/SwiftUI 界面</div>
                <div>📁 <span className="text-cyan-300">Sources/FruitWaveCore/</span> — 核心校准、OneEuroFilter、滤波、动作、状态机和碰撞引擎</div>
                <div>📁 <span className="text-cyan-300">Tests/FruitWaveCoreTests/</span> — 单元测试集</div>
                <div>📁 <span className="text-cyan-300">ArtSource/PRD-v1.0/</span> — 20 款水果纹理、Blender 生成脚本与材质规范</div>
                <div>📁 <span className="text-cyan-300">public/fruits/</span> — 网页端直接挂载的水果整果/切半纹理</div>
                <div>📁 <span className="text-cyan-300">src/core/ & src/vision/</span> — 对应移植的 Web 端 OneEuroFilter2D, 摄像头体感与物理引擎</div>
                <div>📄 <span className="text-amber-300">Package.swift</span> & <span className="text-amber-300">project.yml</span> — XcodeGen 工程构建描述</div>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'architecture' && (
          <div className="bg-slate-900/80 rounded-2xl p-6 border border-slate-800/80 space-y-6">
            <h3 className="text-base font-bold text-white flex items-center gap-2">
              <BookOpen className="w-5 h-5 text-cyan-400" />
              FruitWaveCore 核心架构与设计规范
            </h3>

            <div className="space-y-4 text-sm text-slate-300">
              <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/60">
                <h4 className="font-semibold text-cyan-300 mb-1">1. One Euro Filter 滤波设计</h4>
                <p className="text-xs text-slate-400">
                  采用自适应低通滤波器消除高频手腕抖动。静止时降低截止频率过滤噪声；当检测到高速挥击时自适应提升截止频率，消除视觉延迟。
                </p>
              </div>

              <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/60">
                <h4 className="font-semibold text-emerald-300 mb-1">2. 动作滞回与起刀保护</h4>
                <p className="text-xs text-slate-400">
                  采用 <code className="text-slate-200">startSpeed (0.72)</code> 与 <code className="text-slate-200">stopSpeed (0.30)</code> 的双阈值滞回判定。避免微小手势震颤反复触发起刀，确保斩击手感明确干净。
                </p>
              </div>

              <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/60">
                <h4 className="font-semibold text-purple-300 mb-1">3. 程序化 3 层音效架构</h4>
                <p className="text-xs text-slate-400">
                  抛弃传统死板的静态切水果音效，采用由扫频正弦波 (1520Hz→470Hz)、0.09s 撕裂白噪声与 130Hz 低频重击构成的 3 层实时程序化合成器，且每次连击音调升高半音。
                </p>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'git' && (
          <div className="bg-slate-900/80 rounded-2xl p-6 border border-slate-800/80 space-y-6">
            <h3 className="text-base font-bold text-white flex items-center gap-2">
              <GitCommit className="w-5 h-5 text-cyan-400" />
              Git 同步与继续开发
            </h3>
            <p className="text-sm text-slate-300 leading-relaxed">
              当前开发环境中的 <code className="text-cyan-300">.git</code> 已完整指向远程 <code className="text-cyan-300">https://github.com/datashowme-me/fruitWave.git</code>。
            </p>

            <div className="p-4 rounded-xl bg-slate-950 border border-slate-800 font-mono text-xs text-slate-300 space-y-3">
              <div className="flex items-center gap-2 text-slate-400">
                <Terminal className="w-4 h-4 text-emerald-400" />
                常用操作指令说明：
              </div>
              <div className="text-slate-400"># 查看当前修改状态</div>
              <div className="text-emerald-400">git status</div>
              <div className="text-slate-400 mt-2"># 拉取 GitHub 上的最新提交</div>
              <div className="text-emerald-400">git pull origin main</div>
              <div className="text-slate-400 mt-2"># 提交并推送到 GitHub（如配置了写权限 Token）</div>
              <div className="text-emerald-400">git add . && git commit -m "feat: updates" && git push origin main</div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
