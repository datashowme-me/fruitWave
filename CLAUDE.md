# FruitWave

Apple TV 切水果游戏:tvOS 17 / Swift 6,RealityKit 渲染,Vision 姿态追踪
(Continuity Camera)输入,确定性核心引擎 `FruitWaveCore`。

## 先读这些

- `Docs/AgentSkills-Plan.md` — Agent Skills 方案(2026-10-21 修订版 v2,含路线决定)
- `Docs/Architecture.md` — 数据流与关键契约
- `Docs/M1-Verification.md` — 真机验证框架(完成与否的唯一判据)

## 全局约束(所有任务适用)

1. **真机验证前不许说完成**:编译/单测/模拟器通过都不是完成;完成 =
   `Docs/M1-Verification.md` 对应行填入实测值。
2. **禁止占位物冒充完成**:球/方块/占位贴图不得声称素材完成;未完成显式标注
   "未验证/待实现"。
3. **Web 3D 生态仓库仅作效果参考,禁止引入依赖**(three.quarks、Drei、R3F 等)。
4. **确定性优先**:素材、构建、验证脚本固定版本/种子/输出路径。
5. **生产日志不含隐私**:视频、截图、骨骼坐标、账号、设备名不入生产日志。
6. **失败留证据**:保留日志与产物,写明失败阶段与原因,禁止虚构测试结果。

## 任务分派

| 任务 | 路径 |
|---|---|
| 素材/模型 | `.claude/skills/image-to-game-asset/`(待建;当前:`Tools/Blender/generate_apple.py`) |
| 构建/部署/工程 | `.claude/skills/tvos-game-development/` |
| 切割玩法改动 | `.claude/skills/fruit-slicing-mechanics/`(待建;先跑 `FruitWaveCoreTests` + 真机手测) |
| 相机/输入/配对 | `.claude/skills/iphone-tvos-controller/`(待建;排障见 AgentSkills-Plan 4.4 节) |
| 特效/动画 | `.claude/skills/game-vfx/`(待建) |
| 阶段收尾验收 | `.claude/skills/game-qa/`(每个 Gate 至少一次) |

## 构建要点

- 工程由 xcodegen 生成(`Scripts/bootstrap.sh`),`FruitWave.xcodeproj` 不入库。
- 本机默认 developer directory 指向 CommandLineTools;skill 脚本自动改用
  `/Applications/Xcode.app`(Xcode 26.2)。
- DerivedData 固定为 `.build/xcode`(已被 `.build/` 忽略)。
