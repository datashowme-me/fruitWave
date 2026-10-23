# Apple TV 切水果游戏:Agent Skills 设计方案(修订版 v2)

修订日期:2026-10-21
修订依据:仓库现状核实(Gate 对照)+ 路线决定(输入维持 Continuity Camera)
上一版(v1)的核心原则、Gate 骨架、验收驱动思想全部保留;本版把内容从
"绿地剧本"改写为"仓库真实流程的固化"。

## 0. v2 相对 v1 的决策记录

| # | v1 内容 | v2 决定 | 理由 |
|---|---|---|---|
| 1 | iPhone 触屏 → MultipeerConnectivity 为第一版输入 | **维持 Continuity Camera + Vision 路线**,MC 搁置 | 仓库已实现相机路线;2026-10-20 系统层配对卡死与输入通道选型无关,不因此换路线 |
| 2 | image-to-game-asset 以 TripoSR 单图重建为核心 | 以 `Tools/Blender/generate_apple.py` 确定性管线为核心,TripoSR 降级为 references 备选(默认不启用) | 仓库资产形态是 Blender 预制模型 + 贴图,不是单图重建;TripoSR 6GB 显存、Apple Silicon 未验证 |
| 3 | game-dev-router 为独立 Skill | 降级为 CLAUDE.md 级分派说明,不做成 Skill | Claude Code 的主 agent 本身就是 router;多一层 Skill 只增加不执行的空壳 |
| 4 | 第一轮先实现工程基线、再素材、再切割 | 第一轮改为**固化 game-qa + tvos-game-development** | Gate 1-3 已达成,当前风险不是"写不出来"而是"改坏、没验证" |
| 5 | "第一轮只做一个苹果端到端" | 苹果端到端已基本达成(贴图 20 种、3D 模型 1 种) | 第一轮真实缺口是输入通道的验证,不是素材 |

## 1. 六条核心设计原则(保留)

任务原子化 / 依赖真实仓库 / 输入输出契约 / 可执行优先 / 验收驱动 / 渐进式开发。
每条原则在本仓库的落地形式见各 Skill 的"验收"小节。

## 2. 现状基线:Gate 对照

| Gate | v1 假设 | 仓库现状(2026-10-21 核实) | 结论 |
|---|---|---|---|
| 1 工程基线 | 需新建 Swift/tvOS 工程 | `project.yml` + xcodegen,tvOS 17 / Swift 6;App、Core 框架、单测三 target;`Scripts/bootstrap.sh` 生成工程 | ✅ 已达成 |
| 2 水果素材 | TripoSR 单图重建一个苹果 | `Tools/Blender/generate_apple.py` 确定性生成 `apple_whole.usdz` / `apple_sliced.usdz`(预制两半+果肉+种子)/ `apple_preview.png`;`FruitCapTextures/` 有 20 种水果 skin/cap 贴图,**但贴图生成脚本未落库** | ✅ 基本达成;管线脚本化待补 |
| 3 切割 | 双层机制待实现 | `GameplayEngine` 确定性命中(`SlashSegment` → `HitEvent`,`active→sliced` 单向迁移)+ 渲染层整果换预制两半(注释明示不做运行时 boolean) | ✅ 已达成 |
| 4 输入 | iPhone 触屏 → MC | Continuity Camera → `CameraSessionManager` → `PoseTrackingEngine` → `MotionProcessor` → `SlashSegment`(见 `Docs/Architecture.md`);2026-10-20 系统层配对卡死,app 侧自证清白,待电视唤醒后真机验证 | ⚠️ 未闭环 |
| 5 VFX | 待建 | 已有 juice rates / slice animation 路由 | 🟡 缺性能预算与降级 |
| 6 QA | 待建 | 确定性引擎单测 + `Docs/M1-Verification.md` 框架 + `Docs/Evidence/` 诊断快照;大量用例仍"未执行" | 🟡 缺真机取证脚本化 |

## 3. 全局约束(所有 Skill 必须遵守,优先级最高)

1. **真机验证前不许说完成**:编译通过、模拟器通过、单测通过都只是中间证据;"完成"以
   `Docs/M1-Verification.md` 对应表格填入实测值为准。
2. **禁止占位物冒充完成**:不得以球/方块等占位几何或占位贴图声称素材任务完成;未完成
   必须显式标注"未验证/待实现"。
3. **Web 3D 生态仓库仅作效果参考,禁止作为依赖引入**:three.quarks、React Postprocessing、
   Drei、R3F 属于效果设计参考;tvOS 实现只用 RealityKit / Metal / 系统 API。
4. **确定性优先**:与 `GameplayEngine` 同风格,素材生成、构建、验证脚本必须确定性可复现
   (固定版本、固定种子、固定输出路径)。
5. **生产日志不含隐私**:视频、截图、骨骼坐标、账号、设备名一律不入生产日志
   (与 `Architecture.md` 一致)。
6. **失败必须留下证据**:失败报告保留日志与产物,写明失败阶段与可操作原因,禁止虚构测试结果。

## 4. Skill 体系

### 4.0 任务分派(替代 game-dev-router,不单独成 Skill)

写入 CLAUDE.md(本仓库)/ AGENTS.md(Codex 场景)的分派说明:

- 素材/模型任务 → image-to-game-asset
- 工程/构建/部署任务 → tvos-game-development
- 切割玩法改动 → fruit-slicing-mechanics
- 相机/输入/配对 → iphone-tvos-controller
- 特效/动画 → game-vfx
- 任何阶段收尾 → game-qa(每个 Gate 至少执行一次)

### 4.1 tvos-game-development

- **目标**:工程基线、Swift 代码、RealityKit 加载与生命周期的**可复现构建 + 真机部署验证**。
- **现状**:已达成 Gate 1;skill 的作用是固化命令链,防止"编译通过 = 完成"。
- **落地内容**:
  - `scripts/build.sh`:`Scripts/bootstrap.sh`(xcodegen)→ `xcodebuild -project FruitWave.xcodeproj -scheme FruitWave -destination 'platform=tvOS,name=<设备名>' build`
  - `scripts/deploy.sh`:devicectl 安装到目标 Apple TV + 启动 + 取证(进程存活、崩溃日志、启动日志)
  - `references/project-layout.md`:三 target 职责、tvOS 17 / Swift 6 约束、签名(DEVELOPMENT_TEAM 7T5TZY885W)
- **验收**:真机安装并启动成功,且证据(日志/截图)落 `Docs/Evidence/`。只构建不部署不算完成。

### 4.2 image-to-game-asset

- **目标**:把水果素材流程固化为确定性脚本:输入水果规格 → 输出模型对(整果 + 预制两半)+
  贴图 + 预览 + validation 报告。
- **现状**:`Tools/Blender/generate_apple.py` 已实现苹果全流程(headless 运行:
  `Blender --background --python Tools/Blender/generate_apple.py`,产出 .blend 源、
  whole/sliced usdz、preview.png);20 种贴图已在 `FruitCapTextures/`,但**贴图生成脚本未落库**。
- **落地内容**(按 v1 脚本四件套参数化):
  - `scripts/validate_input.py`:输入 PNG/规格校验
  - `scripts/generate_mesh.py` → 参数化 Blender 脚本(面数预算、尺寸、两半规格)
  - `scripts/process_mesh.py`:网格/材质/贴图修复
  - `scripts/validate_output.py`:单位、中心点、正反面几何、加载检查
  - `references/asset-spec.md`:单位、坐标、pivot、贴图命名(skin_*/cap_*)约定
  - `references/upstream-repos.md`:Blender(版本锁定)、TripoSR(**备选,默认不启用**)
- **验收**:新水果(第一个扩展目标:第二种水果)按同一契约产出并通过 validate_output,
  且真机加载渲染验证;单张 PNG 的背面与果肉属推断/预制,不得承诺自动真实还原。

### 4.3 fruit-slicing-mechanics

- **目标**:切割玩法的**回归保护**,而非重新实现。
- **现状**:双层机制已达成——引擎层确定性命中 + 渲染层整果换预制两半
  (art-directable,帧成本可预测);运行时任意角度 mesh 裁剪明确为**范围外**。
- **落地内容**:
  - `references/mechanics-contract.md`:SlashSegment/HitEvent 契约、roundID 隔离、
    `active→sliced` 幂等迁移、预制两半 swap 流程(与 `Architecture.md` 一致)
  - `tests/`:切割相关单测(命中判定、幂等、两半分离)
  - 真机手测清单:切面朝向、两半分离动画、连击命中
- **验收**:改切割逻辑后 `FruitWaveCoreTests` 全绿 + 真机手测清单勾选 + 证据落档。

### 4.4 iphone-tvos-controller

- **目标**:Continuity Camera + Vision 姿态追踪的连接、校准、排障与验证。
- **路线决定(2026-10-21)**:维持相机路线;MC 触屏通道搁置(不作为第一版)。
- **现状**:数据流已实现(`Architecture.md`);2026-10-20 系统层配对卡死:app 侧代码
  与能连版本逐字节相同,两台 iPhone / FaceTime 交叉验证指向电视侧系统层;断电重启后
  推进到"唤醒 Apple TV"阶段;`pendingPreferredCamera` 接管逻辑**待真机验证**。
- **落地内容**:
  - `references/state-machine.md`:Disconnected → Discovering → Connecting → Connected →
    Calibrated → Playing,含超时(90s)、退避(1.5→12s)、失败处理
  - `references/troubleshooting.md`:**固化卡死事件经验**——先唤醒电视再扫码、
    拉 `fruitwave-camera-log.txt` 找 `preferredCameraChange retained` /
    `activating camera published during picker` 行、不重复已排除假设(账号、网络、
    版本差、手机侧、app 代码)
  - 配对路径 10 次验收用例(对应 `M1-Verification.md` 连接表)
- **验收**:电视唤醒后重新扫码真机通过;或按排障文档定位到系统层并记录,不把系统层
  故障说成 app 侧完成。

### 4.5 game-vfx

- **目标**:切割反馈品质,不损害帧率。
- **现状**:已有 juice rates / slice animation 路由;音效层已完成(Kenney CC0 + 程序撕裂层)。
- **落地内容**:
  - `references/vfx-params.md`:粒子数量、寿命、颜色、飞散速度、音效触发参数表
  - **性能预算**:Apple TV 4K(第 3 代)上帧间隔 P95 阈值(以 `M1-Verification.md` 冻结记录
    为准,当前未冻结)
  - 降级策略:超预算时按粒子密度 → 果汁 → 切面特效逐级关闭
- **验收**:VFX 开启/关闭两组真机帧率采样,均满足预算;超出预算时降级策略生效。

### 4.6 game-qa

- **目标**:每个 Gate 收尾的强制检查点,防止"未验证"冒充"完成"。
- **现状**:`Docs/M1-Verification.md` 框架已建(构建、连接、延迟、准确性、稳定性、冻结记录),
  `Docs/Evidence/` 有诊断快照;大量用例"未执行"。
- **落地内容**:
  - `scripts/verify-device.sh`:构建 → 部署 → 启动 → 采集日志/截图 → 归档到 `Docs/Evidence/`
  - 静态验证:Swift 单测(`FruitWaveCoreTests`)+ xcodebuild analyze
  - **真机验收标准**:GPU 效果、相机通信、交互延迟不能仅凭编译通过认定
- **验收**:本轮 Gate 对应的 `M1-Verification.md` 表格行填入实测值(设备、系统、构建、
  样本量、测量方式),未执行行保持"未执行"并说明阻塞原因。

## 5. 目录组织与双 agent 兼容

主目录采用 Claude Code 约定 `.claude/skills/<name>/`;若启用 Codex,在 `.agents/skills`
建立 symlink 指向同一目录,避免两份内容漂移。结构沿用 v1:

```text
.claude/skills/
└── <skill-name>/
    ├── SKILL.md
    ├── references/   # 契约、上游仓库版本、排障手册
    ├── scripts/      # 确定性执行脚本
    └── tests/        # 脚本行为与产物正确性验证
```

SKILL.md 范例(以 tvos-game-development 为例,注意命令必须真实、不虚构):

```markdown
---
name: tvos-game-development
description: >
  Build, deploy and verify the FruitWave tvOS app on a real Apple TV.
  Use before claiming any change works on device.
---
# tvos-game-development
## Objective
Reproducible build, deploy and on-device verification.
## Preconditions
1. xcodegen installed (brew install xcodegen).
2. Target Apple TV reachable and awake (devicectl list devices).
3. No dependency changes without recording versions.
## Workflow
1. Scripts/bootstrap.sh          # regenerate project
2. xcodebuild -project FruitWave.xcodeproj -scheme FruitWave \
   -destination 'platform=tvOS,name=<device>' build
3. Deploy via devicectl; launch; capture logs.
4. Archive evidence to Docs/Evidence/.
## Quality gates
- Build succeeds AND app launches on the Apple TV AND evidence archived.
- Build-only success is NOT completion.
## Failure handling
- Keep the failed build log; report the failing stage.
- Never fabricate device verification results.
```

## 6. 依赖管理(三类)

- **运行依赖**:Blender(headless,版本锁定);xcodegen;Xcode。需真正安装并记录版本。
- **算法参考**:UnitySliceOpenFracture、React Three Rapier 等——只读原理,Swift 侧重新设计,
  禁止移植代码。
- **Skill 规范参考**:Gamedev Agent Skills——学习 Router/触发条件/验收框架,不克隆仓库混合使用。

`references/upstream-repos.md` 每项记录:完整 URL、固定 Commit SHA 或版本、许可证、用途、
安装方式、平台兼容性、替代方案、最后验证日期。本仓库当前清单:

| 仓库/工具 | 类别 | 状态 |
|---|---|---|
| Blender | 运行依赖 | 已用(`generate_apple.py`) |
| TripoSR | 备选参考 | 默认不启用(6GB 显存、Apple Silicon 未验证) |
| BlenderProc | 备选参考 | 未用 |
| MultipeerKit | 搁置 | 输入维持相机路线 |
| three.quarks / Drei / R3F / React Postprocessing | 效果参考 | 禁止引入依赖 |
| UnitySliceOpenFracture / R3 Rapier | 算法参考 | 仅原理 |

## 7. 阶段 Gate(修正版)

| 阶段 | Skill | 状态 | 通过条件 |
|---|---|---|---|
| Gate 1 | tvos-game-development | ✅ 已达 | 真机启动最小场景(2026-10-18 已证据化) |
| Gate 2 | image-to-game-asset | ✅ 基本达 | 苹果 usdz 真机加载;**补:贴图管线脚本落库** |
| Gate 3 | fruit-slicing-mechanics | ✅ 已达 | 模拟挥砍切开水果(引擎确定性 + 两半 swap) |
| Gate 4 | iphone-tvos-controller | ⚠️ 未闭环 | 相机配对成功 + 真机手部动作触发切割 |
| Gate 5 | game-vfx | 🟡 部分 | 果肉/果汁/动画达标且帧率预算满足 |
| Gate 6 | game-qa | 🟡 持续 | `M1-Verification.md` 本轮表格填实测值 |

game-qa 不是只在最后执行,而是每个 Gate 收尾都跑一次。

## 8. 开发优先级(修正版)

1. **第一轮:固化 game-qa + tvos-game-development**——skill 体系本身先跑通最小闭环,
   验证"SKILL.md + 脚本 + 验收"在这个仓库真实可用。
2. **第二轮:image-to-game-asset 扩展到第二种水果 + fruit-slicing-mechanics 回归 skill**——
   用新水果检验资产管线参数化;给切割逻辑挂上回归保护。
3. **第三轮:iphone-tvos-controller 验证 skill + game-vfx**——先按排障手册解决相机
   配对验证(唤醒电视 → 扫码 → 取证),再补 VFX 预算与降级。
4. 本轮不做:20 种水果全 3D 化、摄像头之外的输入通道、任意角度实时 mesh 切割。

## 9. 未竟事项(交接给后续执行)

- 贴图生成脚本落库(20 种贴图存在但生成过程未脚本化)。
- `M1-Verification.md` 中所有"未执行"用例的排期与执行。
- 配对卡死验证:电视唤醒 → 重新扫码 → `fruitwave-camera-log.txt` 取证
  (排障路径见 4.4 节的 troubleshooting.md 内容)。
- 冻结记录:指标阈值未冻结前,不得自动进入下一阶段(与 M1 规范一致)。
