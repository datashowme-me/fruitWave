---
name: tvos-game-development
description: >
  Build, deploy and verify the FruitWave tvOS app on a real Apple TV.
  Use when the project needs to be built, a build failure needs
  diagnosis, or a change must reach the Apple TV for on-device
  verification. Build-only success is never completion.
---
# tvos-game-development

## Objective
可复现地构建、部署、启动 FruitWave,并留下证据;任何改动在真机验证前不得声称完成。

## Preconditions
1. XcodeGen 已安装(`brew install xcodegen`,当前 2.46.0)。
2. 完整 Xcode 在 `/Applications/Xcode.app`(当前 26.2;脚本自动定位,
   系统默认 developer directory 是 CommandLineTools)。
3. 目标 Apple TV 可达且唤醒(`xcrun devicectl list devices` 显示
   `available (paired)`);睡眠中先唤醒再部署。
4. 依赖变更必须记录版本,不得静默安装。

## Workflow
1. `scripts/build.sh [destination]` — 重新生成工程 + 编译
   (默认 `generic/platform=tvOS`,不签名;验证编译链)。
2. `scripts/deploy.sh [设备标识]` — 设备签名构建 → devicectl 安装 → 启动 →
   证据归档 `Docs/Evidence/deploy-<时间戳>.log`。
3. 需要完整验收(构建 + 单测 + 真机)时用 `game-qa` 的 `verify-device.sh`。

## Quality gates
- 构建成功 **且** 真机安装 **且** 启动,证据落 `Docs/Evidence/`。
- 仅编译通过 ≠ 完成。
- 部署失败时日志必须说明失败阶段(构建/签名/安装/启动)。

## Failure handling
- 保留完整失败日志;报告失败阶段与可操作原因。
- 设备睡眠/不可达:先唤醒再重试,不得无限重试。
- 禁止伪造部署成功证据。

## Verified commands(2026-10-21 实测,Xcode 26.2 / xcodegen 2.46.0)
- `Scripts/bootstrap.sh` → OK
- `xcodebuild -project FruitWave.xcodeproj -scheme FruitWave -destination 'generic/platform=tvOS' -derivedDataPath .build/xcode build` → BUILD SUCCEEDED
