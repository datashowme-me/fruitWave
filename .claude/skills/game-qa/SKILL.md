---
name: game-qa
description: >
  Gate checkpoint for the FruitWave tvOS game: build, unit tests,
  on-device deploy and evidence archiving. Run at the end of every
  stage, before anything is claimed complete. GPU effects, camera
  communication and interaction latency are only accepted with
  real-device evidence.
---
# game-qa

## Objective
每个 Gate 收尾的强制检查点:用证据证明"完成",未证明的一律标记未验证。

## When to use
- 每个阶段(Gate)收尾、声称任何功能完成之前。
- 改动涉及 GPU 效果、相机通信、交互延迟时(必须真机取证,编译通过不算)。

## Workflow
1. `scripts/verify-device.sh [--skip-tests] [设备标识]`
   — 构建 → 单测(tvOS 模拟器)→ 真机部署 + 启动,证据归档 `Docs/Evidence/`。
2. 对照 `Docs/M1-Verification.md` 填写本轮涉及的行:设备、系统、构建、样本量、
   测量方式缺一不可。
3. 未执行的用例保持"未执行",并写明阻塞原因;不得悄悄删行。

## Quality gates
- 对应 M1 表格行有实测值(或显式"未执行 + 原因")。
- GPU 效果 / 相机通信 / 交互延迟只认真机证据。
- 冻结记录(阈值)未形成前,不自动进入下一阶段。

## Failure handling
- 保留失败日志与诊断快照;报告失败阶段。
- 禁止伪造测试结果、禁止用占位物截图冒充完成。
- 单测失败不得绕过:修复或回滚,不允许跳过测试通过 Gate。
