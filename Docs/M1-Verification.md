# M1 真机验证记录

所有结果初始均为“未执行”。填写实测值时同时记录设备、系统、构建、环境、样本量和测量方式。

## 构建与设备

| 字段 | 记录 |
|---|---|
| 构建版本 / Git commit | Release 0.1 (1) / `65c5ecc` + 当前交付工作区；2026-10-18 18:05 已彻底移除校准与腕点识别的启动门槛，直接开始版签名构建已覆盖安装并启动 |
| Apple TV 型号 / tvOS | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 (24J361) |
| iPhone 型号 / iOS | 未执行 |
| 实际视频尺寸 / 帧间隔 | 1280×720；900 帧窗口 P50/P95/P99 = 33.33/39.85/43.90ms；2026-10-18 17:08 首次真机采样 |
| 房间光线 / 距离 / 摆放 | 未执行 |

## 连接（每组至少 10 次）

| 用例 | 成功数 / 样本数 | 耗时 P50 / P95 | 失败原因 |
|---|---:|---:|---|
| 冷启动连接 | 未执行 | 未执行 | 未执行 |
| 中断与重连 | 未执行 | 未执行 | 未执行 |
| 取消选择 | 未执行 | 不计为故障 | 未执行 |
| 权限拒绝 | 未执行 | 不适用 | 未执行 |
| 退出后无残留采集 | 未执行 | 不适用 | 未执行 |

当前部署证据：`com.example.FruitWave` Release 候选版已于 2026-10-18 15:51（Asia/Shanghai）覆盖安装并成功启动；启动后进程持续存在，设备未产生新的 FruitWave 崩溃日志。此证据只证明安装与启动，不替代上表各路径的 10 次人工验收。

## 延迟与吞吐

- 应用内：排队、推理、结果到场景消费分别记录 P50/P95/P99。
- 外部：至少 120fps 相机同时拍真实手部与电视反馈，至少 30 次动作，报告中位数、P95、样本数和约 ±1 拍摄帧不确定性。
- 不把“收到帧之后的耗时”描述为完整端到端延迟。

| 指标 | 结果 |
|---|---|
| 推理耗时 P50 / P95 | 16.48 / 17.77ms（900 帧窗口） |
| 排队耗时 P50 / P95 | 0.13 / 0.17ms（900 帧窗口） |
| 场景消费耗时 P50 / P95 | 未执行 |
| 外部端到端延迟中位数 / P95 | 未执行 |
| 有效识别频率 | 未执行 |

首份内部诊断：Vision 推理 P50/P95 = 16.48/17.77ms，结果年龄 P50/P95 = 16.61/17.91ms，帧间隔超过 33.3ms 比例 50%，`frameWasLate` 1 次。原始快照保存在 `Docs/Evidence/FruitWaveDiagnostics-2026-10-18-1708.json`。这些数值证明内部处理未积压，但不等同于相机曝光到电视显示的端到端延迟。

约 3.5 分钟后的第二份 900 帧滚动窗口保持稳定：Vision 推理 P50/P95 = 16.55/17.78ms，结果年龄 P50/P95 = 16.69/17.94ms，排队 P95 = 0.15ms，`frameWasLate` 仍为 1 次。原始快照保存在 `Docs/Evidence/FruitWaveDiagnostics-2026-10-18-1712.json`。

## 准确性和安全正确性

| 用例 | 样本 | 结果 |
|---|---:|---|
| 预设穿越动作 | ≥50 | 未执行 |
| 慢移、静止、遮挡恢复对照 | ≥50 | 未执行 |
| 遮挡恢复 | ≥10 | 未执行 |
| 身份不确定 / 旁人入镜 | ≥10 | 未执行 |
| 区外重入 | ≥10 | 未执行 |
| 断连恢复 | ≥10 | 未执行 |
| 暂停 / 结算迟到回调 | ≥10 | 未执行 |

- 漏切率 = 应命中但未命中次数 / 有效穿越次数。
- 误切率 = 出现非预期命中的对照试次数 / 对照试次数。
- 跨失效区间连线、错误接管、重复计分均为阻断缺陷。

## 稳定性

- 两个基线 Apple TV 代际与至少两款 iPhone。
- 每个基线组合连续运行 60 分钟。
- 记录帧间隔 P50/P95/P99、超过 33.3ms 比例、丢帧、CPU、内存走势、崩溃、死锁与退出失败。
- 自动化补充证据（不能替代真机）：核心引擎已连续模拟 100 局、每局 90 秒（合计 150 分钟游戏时间），水果集合始终不超过 6；动作处理器已承受 20 万个含低置信度、NaN、延迟和映射变化的样本。2026-10-18 macOS Swift Package 与 tvOS 26.2 模拟器同一组 22 项测试均通过，0 失败、0 跳过；包含按相机会话与 `runEpoch` 分区的重复/乱序帧拒绝；Xcode 静态分析无诊断。

## 冻结记录

M1 结束后，产品负责人和开发负责人共同填写：指标定义、阈值、设备与场景、测量方式、样本量、制定理由、负责人、日期、构建版本。未形成可接受且可复现的阈值时，不自动进入下一阶段。

## 素材与渲染验收（apple 资产）

- 验收台：`FruitWaveApp/UI/AppleAssetLabView.swift`（RealityKit 独立场景，不触碰相机/玩法状态）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1"}' com.example.FruitWave` 启动（flags 必须在 bundle id 之前），app 自动打开验收台、t+3s 整果快照、t+6s 切半、t+9s 切面快照、12 秒渲染窗口计 FPS 与常驻内存，证据写入设备 `Library/Caches/evidence_apple.*`（Caches 通道经实测可靠；Documents 写入从未在设备落盘）。
- 证据归档：`Docs/Evidence/apple-acceptance/`（日志 + 整果/切面 PNG + 四图同口径像素分析 JSON）。
- 像素测量仅为无视觉环境下的量化代理，**不替代人眼复核**。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 00:06 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-000649.log` |
| 整果帧率 | 49.5 fps（12.00s，594 帧） | `evidence_apple.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 215 MB | 同上 |
| 整果肤色均值 RGB | (201,68,52)，PRD 参考 (195,27,24)，Blender 预览 (167,55,37) | 像素分析 JSON |
| 切面果肉均值 RGB | (240,218,184)，创作值 (240,217,179) | 像素分析 JSON |
| 整果包围盒 | 横向 40.7–59.4%、纵向 35.6–70.2%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 31.2–66.6%（两半分离、宽度近整果两倍） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 164（PRD 148） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_apple_whole.png` / `evidence_apple_sliced.png` |
| gameplay 集成 | 未做：apple 资产仅用于验收台，`apple.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `apple_half_left` / `apple_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`apple_reference.json` 中如实标注 observed / inferred 与 inspection_method）。

## 素材与渲染验收（orange 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=orange` 选择水果，资产与证据按水果命名，两半分离距离读 `orange.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"orange"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_orange.*`。
- 证据归档：`Docs/Evidence/orange-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 09:28 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-092803.log` |
| 整果帧率 | 49.5 fps（12.01s，594 帧） | `evidence_orange.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 217 MB | 同上 |
| 整果肤色均值 RGB | (218,121,32)，PRD 肤家族 #e65508/#a34507/#d6810f，Blender 预览 (183,107,31) | 像素分析 JSON |
| 切面果肉均值 RGB | (244,148,41)，PRD 果肉 #f6a620/#fa7e0f | 像素分析 JSON |
| 切面瓤（pith）均值 RGB | (246,194,145)，PRD 瓤 #fbe69a | 像素分析 JSON |
| 整果包围盒 | 横向 40.7–59.6%、纵向 37.0–68.0%（居中，近圆形） | 像素分析 JSON |
| 切面包围盒 | 横向 31.0–67.0%（两半分离、宽度近整果两倍），瓤/果肉结构占比 7.2%/36.7% | 像素分析 JSON |
| 人眼复核（瓣膜/瓤/无穿插/整体观感） | **待用户确认** | 看 `evidence_orange_whole.png` / `evidence_orange_sliced.png` |
| gameplay 集成 | 未做：orange 资产仅用于验收台，`orange.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `orange_half_left` / `orange_half_right`。
- 已知限制：同上（无视觉模型，像素测量为量化代理）；瓣数 9 与楔形半径取自典型橙子结构，PRD 切面中无种子可见，故无种子。

## 素材与渲染验收（lemon 资产）

- 生成器 `Tools/Blender/generate_lemon.py`（citrus 共享模块 `fruitgen/citrus.py`；orange 保持自带副本以免已冻结资产漂移）。
- 采样方式与 apple/orange 相同，`FW_FRUIT=lemon`；证据归档 `Docs/Evidence/lemon-acceptance/`。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 09:33 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-093306.log` |
| 整果帧率 | 49.4 fps（12.01s，594 帧） | `evidence_lemon.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 215 MB | 同上 |
| 整果肤色均值 RGB | (221,180,34)，PRD 肤家族 #d99408/#e8b614/#fcde12，Blender 预览 (179,142,47) | 像素分析 JSON |
| 切面果肉均值 RGB | (231,179,30)，PRD 果肉 #f1cd4b/#e9b61d | 像素分析 JSON |
| 切面瓤（pith）均值 RGB | (249,224,148)，PRD 瓤 #f7e6a4 | 像素分析 JSON |
| 整果包围盒 | 横向 40.9–58.8%、纵向 36.5–67.0%（居中，近方形，两端带果脐） | 像素分析 JSON |
| 切面包围盒 | 横向 31.4–64.6%（两半分离、宽度近整果两倍） | 像素分析 JSON |
| 人眼复核（瓣膜/瓤/光泽/整体观感） | **待用户确认** | 看 `evidence_lemon_whole.png` / `evidence_lemon_sliced.png` |
| gameplay 集成 | 未做：lemon 资产仅用于验收台，`lemon.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `lemon_half_left` / `lemon_half_right`。
- 已知限制：同上；果皮高光按实测 8.8% 调亮（roughness 0.22 / specular 0.65，橙为 0.30/0.48）。

## 批量验收（2026-10-22 · 17 种水果）

- 构建/部署：Docs/Evidence/deploy-2026-10-22-100753.log（设备签名构建 + 安装 + 启动成功），app 含全部 20 种水果资产。
- 流程：每果 `FW_FRUIT=<slug>` 独立启动验收台（整果 t+3s 快照、切半 t+6s、切面 t+9s、12s FPS 窗口、15s watchdog），证据拉取 `Docs/Evidence/<slug>-acceptance/`。
- 慢加载发现：plum / pear / dragon_fruit 首次启动 >22s 才写入快照（日志停在 ASSET_LAB_STARTED，无 watchdog 行）；45s 窗口复测全部正常——非崩溃，属首次加载较慢。采样脚本 `.claude/skills/tvos-game-development/scripts/fruit-acceptance-loop.sh` 默认 22s，失败时按 45s 复测。
- 像素分析：`Tools/analyze_acceptance.py`（AST 提取各生成器 classify_skin/is_flesh 谓词，flesh 亮度上限放宽适配真机/PRD 光照；四图同口径，apple 校准对比归档值一致）；汇总 `Tools/acceptance_summary.jsonl`。
- 像素测量仅为无视觉环境下的量化代理，**不替代人眼复核**；17 果人眼复核均待用户确认。

## 素材与渲染验收（banana 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=banana` 选择水果，资产与证据按水果命名，两半分离距离读 `banana.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"banana"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_banana.*`。
- 证据归档：`Docs/Evidence/banana-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.01s，594 帧） | `evidence_banana.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 212 MB | 同上 |
| 整果肤色均值 RGB | (217,178,59)，PRD 参考 (234,185,43)，Blender 预览 (181,141,56) | 像素分析 JSON |
| 切面果肉均值 RGB | (239,218,140)，创作值 (247,229,153) | 像素分析 JSON |
| 整果包围盒 | 横向 45.8–54.5%、纵向 30.4–70.9%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 33.0–63.6%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 233.4（PRD 231.6） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_banana_whole.png` / `evidence_banana_sliced.png` |
| gameplay 集成 | 未做：banana 资产仅用于验收台，`banana.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `banana_half_left` / `banana_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`banana_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：纵向剖切（y=0），两半各保留完整果弧与种子带；两半分离轴自适应长形果。

## 素材与渲染验收（blueberry 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=blueberry` 选择水果，资产与证据按水果命名，两半分离距离读 `blueberry.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"blueberry"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_blueberry.*`。
- 证据归档：`Docs/Evidence/blueberry-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.4 fps（12.00s，593 帧） | `evidence_blueberry.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 211 MB | 同上 |
| 整果肤色均值 RGB | (99,117,168)，PRD 参考 (78,103,172)，Blender 预览 (98,119,158) | 像素分析 JSON |
| 切面果肉均值 RGB | (184,182,209)，创作值 (198,183,204) | 像素分析 JSON |
| 整果包围盒 | 横向 44.8–55.1%、纵向 44.6–62.4%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 38.5–60.4%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 181.0（PRD 193.1） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_blueberry_whole.png` / `evidence_blueberry_sliced.png` |
| gameplay 集成 | 未做：blueberry 资产仅用于验收台，`blueberry.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `blueberry_half_left` / `blueberry_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`blueberry_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 已知限制：果皮深蓝近黑，真机暗背景下皮肤像素占比低（1.5%），均值仍与 PRD 一致；其余同通用限制。

## 素材与渲染验收（cantaloupe 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=cantaloupe` 选择水果，资产与证据按水果命名，两半分离距离读 `cantaloupe.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"cantaloupe"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_cantaloupe.*`。
- 证据归档：`Docs/Evidence/cantaloupe-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.3 fps（12.01s，592 帧） | `evidence_cantaloupe.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 216 MB | 同上 |
| 整果肤色均值 RGB | (207,164,97)，PRD 参考 (210,164,97)，Blender 预览 (179,141,94) | 像素分析 JSON |
| 切面果肉均值 RGB | (207,159,85)，创作值 (229,158,61) | 像素分析 JSON |
| 整果包围盒 | 横向 39.4–60.4%、纵向 33.9–71.7%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 27.0–69.0%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 215.2（PRD 232.7） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_cantaloupe_whole.png` / `evidence_cantaloupe_sliced.png` |
| gameplay 集成 | 未做：cantaloupe 资产仅用于验收台，`cantaloupe.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `cantaloupe_half_left` / `cantaloupe_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`cantaloupe_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 已知限制：果皮与果肉同为暖橙家族，flesh 均值混入邻近皮肤像素；其余同通用限制。

## 素材与渲染验收（cherry 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=cherry` 选择水果，资产与证据按水果命名，两半分离距离读 `cherry.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"cherry"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_cherry.*`。
- 证据归档：`Docs/Evidence/cherry-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.00s，594 帧） | `evidence_cherry.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 213 MB | 同上 |
| 整果肤色均值 RGB | (196,92,57)，PRD 参考 (211,86,53)，Blender 预览 (172,83,52) | 像素分析 JSON |
| 切面果肉均值 RGB | (195,49,35)，创作值 (198,38,30) | 像素分析 JSON |
| 整果包围盒 | 横向 44.6–55.4%、纵向 41.1–63.0%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 37.8–60.9%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 190.4（PRD 222.9） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_cherry_whole.png` / `evidence_cherry_sliced.png` |
| gameplay 集成 | 未做：cherry 资产仅用于验收台，`cherry.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `cherry_half_left` / `cherry_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`cherry_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：核与空腔各居一侧（pitHalf right / cavityHalf left），两半分离后一核一腔。

## 素材与渲染验收（coconut 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=coconut` 选择水果，资产与证据按水果命名，两半分离距离读 `coconut.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"coconut"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_coconut.*`。
- 证据归档：`Docs/Evidence/coconut-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.01s，594 帧） | `evidence_coconut.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 213 MB | 同上 |
| 整果肤色均值 RGB | (181,113,68)，PRD 参考 (172,103,55)，Blender 预览 (172,121,83) | 像素分析 JSON |
| 切面果肉均值 RGB | (237,226,216)，创作值 (229,221,214) | 像素分析 JSON |
| 整果包围盒 | 横向 41.6–58.2%、纵向 38.5–69.1%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 31.9–65.4%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 182.2（PRD 209.9） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_coconut_whole.png` / `evidence_coconut_sliced.png` |
| gameplay 集成 | 未做：coconut 资产仅用于验收台，`coconut.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `coconut_half_left` / `coconut_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`coconut_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面为白肉环（r 0.30–0.74）与中空腔。

## 素材与渲染验收（dragon_fruit 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=dragon_fruit` 选择水果，资产与证据按水果命名，两半分离距离读 `dragon_fruit.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"dragon_fruit"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_dragon_fruit.*`。
- 证据归档：`Docs/Evidence/dragon_fruit-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.02s，595 帧） | `evidence_dragon_fruit.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 234 MB | 同上 |
| 整果肤色均值 RGB | (220,91,106)，PRD 参考 (216,64,93)，Blender 预览 (191,114,124) | 像素分析 JSON |
| 切面果肉均值 RGB | (229,209,195)，创作值 (216,198,178) | 像素分析 JSON |
| 整果包围盒 | 横向 41.5–58.4%、纵向 41.3–65.0%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 36.2–61.8%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 200.3（PRD 214.5） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_dragon_fruit_whole.png` / `evidence_dragon_fruit_sliced.png` |
| gameplay 集成 | 未做：dragon_fruit 资产仅用于验收台，`dragon_fruit.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `dragon_fruit_half_left` / `dragon_fruit_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`dragon_fruit_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面白肉 + 四圈细黑籽（52 颗/半）；20 片鳞叶贴在整果表面。

## 素材与渲染验收（grape 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=grape` 选择水果，资产与证据按水果命名，两半分离距离读 `grape.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"grape"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_grape.*`。
- 证据归档：`Docs/Evidence/grape-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.01s，594 帧） | `evidence_grape.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 212 MB | 同上 |
| 整果肤色均值 RGB | (124,79,131)，PRD 参考 (136,85,162)，Blender 预览 (66,65,78) | 像素分析 JSON |
| 切面果肉均值 RGB | (129,83,138)，创作值 (132,66,96) | 像素分析 JSON |
| 整果包围盒 | 横向 44.1–55.9%、纵向 44.1–64.4%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 37.1–61.7%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 160.5（PRD 206.9） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_grape_whole.png` / `evidence_grape_sliced.png` |
| gameplay 集成 | 未做：grape 资产仅用于验收台，`grape.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `grape_half_left` / `grape_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`grape_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面 2 颗籽。
- 已知限制：果皮深紫，真机暗背景下皮肤像素占比低（0.7%），均值仍与 PRD 一致。

## 素材与渲染验收（kiwi 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=kiwi` 选择水果，资产与证据按水果命名，两半分离距离读 `kiwi.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"kiwi"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_kiwi.*`。
- 证据归档：`Docs/Evidence/kiwi-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.4 fps（12.01s，593 帧） | `evidence_kiwi.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 222 MB | 同上 |
| 整果肤色均值 RGB | (153,100,53)，PRD 参考 (157,99,40)，Blender 预览 (153,114,58) | 像素分析 JSON |
| 切面果肉均值 RGB | (197,178,74)，创作值 (191,198,71) | 像素分析 JSON |
| 整果包围盒 | 横向 42.8–57.0%、纵向 39.8–66.5%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 34.6–63.2%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 186.9（PRD 206.6） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_kiwi_whole.png` / `evidence_kiwi_sliced.png` |
| gameplay 集成 | 未做：kiwi 资产仅用于验收台，`kiwi.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `kiwi_half_left` / `kiwi_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`kiwi_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面绿肉 + 26 颗黑籽 + 白芯。

## 素材与渲染验收（mango 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=mango` 选择水果，资产与证据按水果命名，两半分离距离读 `mango.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"mango"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_mango.*`。
- 证据归档：`Docs/Evidence/mango-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.01s，594 帧） | `evidence_mango.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 212 MB | 同上 |
| 整果肤色均值 RGB | (234,163,53)，PRD 参考 (232,146,35)，Blender 预览 (184,136,56) | 像素分析 JSON |
| 切面果肉均值 RGB | (243,169,56)，创作值 (242,183,45) | 像素分析 JSON |
| 整果包围盒 | 横向 43.8–55.6%、纵向 40.7–65.0%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 36.4–61.7%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 204.3（PRD 227.6） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_mango_whole.png` / `evidence_mango_sliced.png` |
| gameplay 集成 | 未做：mango 资产仅用于验收台，`mango.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `mango_half_left` / `mango_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`mango_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面橙肉 + 扁核（两半均含，刀锋穿过果核）。

## 素材与渲染验收（peach 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=peach` 选择水果，资产与证据按水果命名，两半分离距离读 `peach.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"peach"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_peach.*`。
- 证据归档：`Docs/Evidence/peach-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.00s，594 帧） | `evidence_peach.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 213 MB | 同上 |
| 整果肤色均值 RGB | (220,127,89)，PRD 参考 (233,149,102)，Blender 预览 (185,129,105) | 像素分析 JSON |
| 切面果肉均值 RGB | (223,135,90)，创作值 (237,198,89) | 像素分析 JSON |
| 整果包围盒 | 横向 40.8–58.9%、纵向 39.3–68.7%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 30.7–66.2%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 195.2（PRD 232.9） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_peach_whole.png` / `evidence_peach_sliced.png` |
| gameplay 集成 | 未做：peach 资产仅用于验收台，`peach.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `peach_half_left` / `peach_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`peach_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：核与空腔各居一侧（pitHalf right / cavityHalf left）。
- 已知限制：果皮与果肉同为暖橙家族，flesh 均值混入邻近皮肤像素。

## 素材与渲染验收（pear 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=pear` 选择水果，资产与证据按水果命名，两半分离距离读 `pear.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"pear"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_pear.*`。
- 证据归档：`Docs/Evidence/pear-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.02s，595 帧） | `evidence_pear.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 213 MB | 同上 |
| 整果肤色均值 RGB | (204,195,80)，PRD 参考 (187,182,46)，Blender 预览 (166,153,65) | 像素分析 JSON |
| 切面果肉均值 RGB | (241,231,166)，创作值 (244,232,198) | 像素分析 JSON |
| 整果包围盒 | 横向 43.9–56.0%、纵向 39.3–69.6%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 36.4–61.5%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 231.7（PRD 240.4） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_pear_whole.png` / `evidence_pear_sliced.png` |
| gameplay 集成 | 未做：pear 资产仅用于验收台，`pear.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `pear_half_left` / `pear_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`pear_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面种室环 + 深色果核。

## 素材与渲染验收（persimmon 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=persimmon` 选择水果，资产与证据按水果命名，两半分离距离读 `persimmon.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"persimmon"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_persimmon.*`。
- 证据归档：`Docs/Evidence/persimmon-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.01s，594 帧） | `evidence_persimmon.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 212 MB | 同上 |
| 整果肤色均值 RGB | (230,126,48)，PRD 参考 (234,108,26)，Blender 预览 (188,109,41) | 像素分析 JSON |
| 切面果肉均值 RGB | (243,142,54)，创作值 (237,160,51) | 像素分析 JSON |
| 整果包围盒 | 横向 42.7–56.6%、纵向 43.3–62.2%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 34.4–63.1%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 203.0（PRD 212.4） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_persimmon_whole.png` / `evidence_persimmon_sliced.png` |
| gameplay 集成 | 未做：persimmon 资产仅用于验收台，`persimmon.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `persimmon_half_left` / `persimmon_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`persimmon_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面均匀果肉，无核。
- 已知限制：果皮与果肉同为暖橙家族，flesh 均值混入邻近皮肤像素。

## 素材与渲染验收（pineapple 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=pineapple` 选择水果，资产与证据按水果命名，两半分离距离读 `pineapple.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"pineapple"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_pineapple.*`。
- 证据归档：`Docs/Evidence/pineapple-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.3 fps（12.02s，593 帧） | `evidence_pineapple.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 214 MB | 同上 |
| 整果肤色均值 RGB | (193,128,45)，PRD 参考 (203,124,27)，Blender 预览 (158,102,32) | 像素分析 JSON |
| 切面果肉均值 RGB | (234,194,86)，创作值 (239,204,76) | 像素分析 JSON |
| 整果包围盒 | 横向 42.5–57.4%、纵向 39.6–66.7%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 33.4–64.3%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 190.4（PRD 219.1） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_pineapple_whole.png` / `evidence_pineapple_sliced.png` |
| gameplay 集成 | 未做：pineapple 资产仅用于验收台，`pineapple.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `pineapple_half_left` / `pineapple_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`pineapple_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面黄肉 + 浅色果芯 + 棕皮环。

## 素材与渲染验收（plum 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=plum` 选择水果，资产与证据按水果命名，两半分离距离读 `plum.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"plum"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_plum.*`。
- 证据归档：`Docs/Evidence/plum-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.5 fps（12.01s，594 帧） | `evidence_plum.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 212 MB | 同上 |
| 整果肤色均值 RGB | (160,114,154)，PRD 参考 (124,94,146)，Blender 预览 (140,116,144) | 像素分析 JSON |
| 切面果肉均值 RGB | (234,179,81)，创作值 (234,178,71) | 像素分析 JSON |
| 整果包围盒 | 横向 42.0–57.8%、纵向 40.4–67.0%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 32.7–64.9%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 196.0（PRD 222.3） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_plum_whole.png` / `evidence_plum_sliced.png` |
| gameplay 集成 | 未做：plum 资产仅用于验收台，`plum.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `plum_half_left` / `plum_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`plum_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：核与空腔各居一侧（pitHalf right / cavityHalf left）。
- 已知限制：首次启动 >22s 才写入快照，45s 窗口复测正常（`evidence_plum.log` 即复测日志）。

## 素材与渲染验收（pomegranate 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=pomegranate` 选择水果，资产与证据按水果命名，两半分离距离读 `pomegranate.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"pomegranate"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_pomegranate.*`。
- 证据归档：`Docs/Evidence/pomegranate-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.4 fps（12.00s，593 帧） | `evidence_pomegranate.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 246 MB | 同上 |
| 整果肤色均值 RGB | (184,60,55)，PRD 参考 (200,79,66)，Blender 预览 (164,62,47) | 像素分析 JSON |
| 切面果肉均值 RGB | (247,197,169)，创作值 (239,198,165) | 像素分析 JSON |
| 整果包围盒 | 横向 42.1–57.6%、纵向 39.6–67.0%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 33.2–64.1%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 181.6（PRD 223.8） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_pomegranate_whole.png` / `evidence_pomegranate_sliced.png` |
| gameplay 集成 | 未做：pomegranate 资产仅用于验收台，`pomegranate.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `pomegranate_half_left` / `pomegranate_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`pomegranate_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面为红籽环带（80 颗/半）落在白膜上；果肉行测白膜均值。

## 素材与渲染验收（strawberry 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=strawberry` 选择水果，资产与证据按水果命名，两半分离距离读 `strawberry.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"strawberry"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_strawberry.*`。
- 证据归档：`Docs/Evidence/strawberry-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.4 fps（12.01s，593 帧） | `evidence_strawberry.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 218 MB | 同上 |
| 整果肤色均值 RGB | (214,52,36)，PRD 参考 (218,54,19)，Blender 预览 (179,54,31) | 像素分析 JSON |
| 切面果肉均值 RGB | (218,63,44)，创作值 (224,51,40) | 像素分析 JSON |
| 整果包围盒 | 横向 43.9–55.7%、纵向 42.2–67.6%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 35.8–62.3%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 161.4（PRD 185.8） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_strawberry_whole.png` / `evidence_strawberry_sliced.png` |
| gameplay 集成 | 未做：strawberry 资产仅用于验收台，`strawberry.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `strawberry_half_left` / `strawberry_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`strawberry_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面粉红瓤 + 28 粒表面籽 + 白芯。

## 素材与渲染验收（watermelon 资产）

- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT=watermelon` 选择水果，资产与证据按水果命名，两半分离距离读 `watermelon.json` 碰撞半径）。
- 采样方式：`--terminate-existing -e '{"FW_ASSET_LAB":"1","FW_SNAPSHOTS":"1","FW_FRUIT":"watermelon"}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_watermelon.*`。
- 证据归档：`Docs/Evidence/watermelon-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。

| 指标 | 实测值 | 记录 |
|---|---|---|
| 设备 / tvOS / 构建 | Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建 | `Docs/Evidence/deploy-2026-10-22-100753.log` |
| 整果帧率 | 49.4 fps（12.01s，593 帧） | `evidence_watermelon.log` ASSET_FPS_SAMPLE |
| 峰值常驻内存（整果+切面同载） | 216 MB | 同上 |
| 整果肤色均值 RGB | (88,125,50)，PRD 参考 (81,124,31)，Blender 预览 (79,104,42) | 像素分析 JSON |
| 切面果肉均值 RGB | (226,49,36)，创作值 (209,40,30) | 像素分析 JSON |
| 整果包围盒 | 横向 37.8–62.0%、纵向 32.2–75.9%（居中） | 像素分析 JSON |
| 切面包围盒 | 横向 23.3–71.7%（两半分离） | 像素分析 JSON |
| 高光 | 肤像素 95 分位亮度 182.6（PRD 196.3） | 像素分析 JSON |
| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_watermelon_whole.png` / `evidence_watermelon_sliced.png` |
| gameplay 集成 | 未做：watermelon 资产仅用于验收台，`watermelon.json` 注明 acceptance-lab-only | 见素材契约 |

- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `watermelon_half_left` / `watermelon_half_right`。
- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`watermelon_reference.json` 中如实标注 observed / inferred 与 inspection_method）。
- 结构：切面红瓤 + 8 颗黑籽 + 白皮环。
