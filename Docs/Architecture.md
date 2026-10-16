# 架构与关键契约

```text
Continuity Camera → CameraSessionManager → FramePacket
                                      ↓（最新帧背压）
                              PoseTrackingEngine
                                      ↓ 所有候选人
                  PlayerTracker → CalibrationMapper
                                      ↓ TrackedHand
                              MotionProcessor
                                      ↓ SlashSegment
                              GameplayEngine
                                      ↓ Snapshot / HitEvent
                              GameScene + SwiftUI
```

- `GameCoordinator` 是游戏状态唯一来源；相机状态单独维护。
- 预览与姿态点都只镜像一次。输入方向当前以横向 `.up` 起步，必须在真机针对实际连接方向验证；方向或裁剪变化时应触发重新校准。
- `TrackedHand.sampleTime` 使用帧到达 Apple TV 的单调时间，不直接与相机 PTS 相减。外部端到端延迟另行测量。
- `MotionProcessor.reset()` 在失效、跳点、超时、映射变化、暂停和会话切换时断开轨迹；恢复第一点只建立起点。
- 水果位置由 `spawnedAt + velocity × gameTime` 推导，显示和碰撞使用同一时间线。
- 命中由 `active → sliced` 的单向状态迁移保证幂等。
- 生产日志不得包含视频、截图、骨骼坐标、账号或设备名称。

## 原型初值

| 参数 | 初值 |
|---|---:|
| 手腕置信度 | 0.5 |
| 最大连续点间隔 | 100ms |
| 最大结果年龄（到达后） | 150ms |
| 起刀 / 停刀 | 1.2 / 0.6 W/s |
| 跳点 | 6 W/s |
| One Euro | minCutoff 1Hz, dCutoff 1Hz, beta 0 |
| 水果 / 刀刃半径 | 0.055W / 0.005W |
| 生成间隔 / 上限 | 0.8s / 6 |

这些值只用于启动原型；必须依据 M1/M2 样本调优并保留变更记录。
