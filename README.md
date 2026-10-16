# FruitWave

FruitWave 是一个面向 tvOS 17+ 的单人单手体感切水果技术原型。它通过 Apple TV 的连续互通相机连接 iPhone，在 Apple TV 本地用 Vision 提取人体姿态，再由校准、动作和碰撞模块完成挥砍判定。

> 当前状态：源码级 M1/M2 原型。尚未完成 Apple TV + iPhone 真机编译、连接稳定性、动作体验和性能验收，不能视为可发布版本。

## 已实现

- SwiftUI 的连接、取景、左右手选择、双点校准、五点复核、准备、游戏、暂停、恢复、结算流程。
- `continuityDevicePicker` 设备选择和 `AVCaptureSession` 720p 优先采集；配置和帧回调使用独立串行队列。
- Vision 人体姿态推理；最多一个推理在途和一个最新待处理帧，避免无限排队。
- 会话内单人锁定；以躯干中心和肩宽连续性关联候选人，不使用 `observations.first` 接管玩家。
- 校准窗口有效率、中位数与稳定度判断；映射版本变化会断开动作轨迹。
- One Euro Filter、起刀/停刀滞回、过期帧、时间倒退、点间隔与跳点保护。
- 物理坐标统一为可玩区域宽度 W；碰撞使用手和水果的同时间轴位置，并保证重复命中不重复计分。
- 90 秒、每个水果 10 分、0.8 秒生成、同时最多 6 个、三种普通水果、最高分本地保存。
- Play/Pause 暂停、Back 退出/暂停、恢复倒计时、重新校准、重开和退出。
- 不采集麦克风；权限文案说明仅在本地识别手腕动作。

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

测试覆盖校准矩形、物理比例映射、映射版本断刀、起刀阈值、过期/跳点拒绝、命中幂等、暂停计时和非法状态迁移。

## 已完成的自动验证

- Xcode 26.2 / Swift 6.2.3：`swift test` 通过，共 6 个测试。
- XcodeGen 2.46.0：成功生成 `FruitWave.xcodeproj`。
- AppleTVOS 26.2 SDK：`CODE_SIGNING_ALLOWED=NO` 无签名构建成功。
- `Info.plist`、资产 JSON 和 YAML 均通过格式检查。

当前资源目录只包含强调色，未包含正式 App Icon 与 Top Shelf 素材，因此构建会出现相应警告；发布前必须补齐授权素材。Simulator 服务在自动化沙箱中不可用，但设备 SDK 编译不依赖该服务并已成功。

## 当前验证限制

真机性能门槛、连接成功率、端到端延迟、漏切率/误切率与最低有效识别频率仍须按 `Docs/M1-Verification.md` 实测并冻结，不能用推测值代填。
