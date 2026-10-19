# FruitWave

FruitWave 是一个面向 tvOS 17+ 的单人单手体感切水果技术原型。它通过 Apple TV 的连续互通相机连接 iPhone，在 Apple TV 本地用 Vision 提取人体姿态，再由校准、动作和碰撞模块完成挥砍判定。

> 当前状态：已在 Apple TV 4K（第 3 代）完成签名构建、安装和启动；完整连接成功率、动作体验、外部延迟与 60 分钟稳定性验收仍在进行，尚不能视为最终发布版本。

## 已实现

- SwiftUI 的连接、取景、左右手选择、立即开始、游戏、暂停、恢复和结算流程；不再要求玩家完成精确姿势校准。
- 显式相机授权、`continuityDevicePicker` 设备选择和 `AVCaptureSession` 系统协商采集格式；配置和帧回调使用独立串行队列。
- 采用 720p 优先预设、最新帧背压、TN2445 丢帧分类统计，并把采集 PTS 转换到游戏单调时间轴。
- Vision 人体姿态推理；最多一个推理在途和一个最新待处理帧，避免无限排队。
- `runEpoch`、按相机会话/运行分区的单调帧序号门与 `roundID` 隔离暂停、重开、重新校准、重复/乱序结果和跨局迟到回调。
- 监听系统首选相机、设备断开和 Center Stage；几何变化时拒绝沿用旧校准。
- 会话内单人锁定；以躯干中心和肩宽连续性关联候选人，不使用 `observations.first` 接管玩家。
- 使用安全的归一化相机活动区直接开始，不以前置姿势检测或人工校准阻断用户；映射版本变化会断开旧动作轨迹。
- One Euro Filter、起刀/停刀滞回、过期帧、时间倒退、点间隔与跳点保护。
- 物理坐标统一为可玩区域宽度 W；碰撞使用手和水果的同时间轴位置，并保证重复命中不重复计分。
- 90 秒、每个水果 10 分、0.8 秒生成、同时最多 6 个、12 种水果（西瓜/草莓/菠萝/苹果/橙子/香蕉/猕猴桃/桃子/芒果/柠檬/葡萄/火龙果）、渐变立体贴图与旋转动画、最高分本地保存；刀光、水果和切片节点使用有界对象池。
- 本地合成切割音效（音调随连击升高、不同水果起音不同）及可关闭音效设置，不请求麦克风权限。
- Play/Pause 暂停、Back 退出/暂停、即时恢复、重新校准、重开和退出。
- 不采集麦克风；权限文案说明仅在本地识别手腕动作。
- 包含 Apple 隐私清单：不跟踪、不收集数据，仅声明本地最高分 `UserDefaults` 与游戏单调计时所需的 Required Reason API。

## 目录

```text
FruitWaveApp/             tvOS App、相机、Vision、SpriteKit 与 SwiftUI 界面
Sources/FruitWaveCore/    无 UI 的校准、滤波、动作、状态机和碰撞引擎
Tests/FruitWaveCoreTests/ 核心正确性测试
Docs/                     真机验证与阶段记录模板
project.yml               XcodeGen 工程定义
Package.swift             macOS 上验证核心模块的 Swift Package
```

## 生成并运行 tvOS 工程

需要完整 Xcode（仅 Command Line Tools 不够）、Apple TV 4K 第二代或更新机型，以及 iOS 17+ 的兼容 iPhone。本机已安装 XcodeGen；其他机器缺少时可用 Homebrew 安装。

```sh
cd /Users/me/Documents/fruitWave
brew install xcodegen
./Scripts/bootstrap.sh
open FruitWave.xcodeproj
```

在 Xcode 中：

1. 为 `FruitWave` 选择自己的 Development Team 和唯一 Bundle Identifier。
2. 选择 Apple TV 真机作为运行目标。
3. iPhone 与 Apple TV 满足连续互通相机条件后运行。
4. 首次连接时允许相机权限；应用不会请求麦克风。

Simulator 可检查状态机和 SpriteKit 表现，但 Apple 官方说明它不包含连续互通相机所需组件，因此不能替代真机测试。

## 核心测试

```sh
swift test
```

测试覆盖校准矩形与稳定窗口、物理比例映射、映射版本断刀、起刀阈值、过期/跳点拒绝、跨局隔离、采集时钟历史、命中幂等、暂停计时、压力运行和非法状态迁移。

## 已完成的自动验证

- Xcode 26.2 / Swift 6.2.3：`swift test` 通过，共 26 个测试；覆盖校准低置信度容错、真实 30fps 时间/位置抖动与偶发坏帧。
- 注意：命令行 `swift test` 需要 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（xcode-select 指向 CommandLineTools 时会报 TestingMacros 插件缺失）。
- tvOS 26.2 模拟器（Apple TV 4K 第 3 代）：此前 22 项测试通过，0 失败、0 跳过；新增两项校准保护用例已在 macOS Swift Package 通过。
- XcodeGen 2.46.0：成功生成 `FruitWave.xcodeproj`。
- AppleTVOS 26.2 SDK：`CODE_SIGNING_ALLOWED=NO` 无签名构建成功。
- Xcode `analyze` 静态分析通过，无诊断。
- 已为真实 Apple TV 完成开发签名、覆盖安装并成功启动，启动后无新增崩溃日志。

App Icon 已包含在应用资产中。Simulator 可用于非相机界面检查，但不能替代连续互通相机真机测试。

## 当前验证限制

真机性能门槛、连接成功率、端到端延迟、漏切率/误切率与最低有效识别频率仍须按 `Docs/M1-Verification.md` 实测并冻结，不能用推测值代填。
