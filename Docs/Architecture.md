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

这里的 iPhone 是 Apple Continuity Camera 视频源；`Vision` 推理运行在 tvOS
进程中。系统设备选择器只负责相机连接，不负责人体关节识别或游戏状态。

- `GameCoordinator` 是游戏状态唯一来源；相机状态单独维护。
- 视频数据连接明确保持未镜像；预览与姿态坐标分别显式镜像一次。首轮校准的光标使用与 `resizeAspectFill` 相同的裁剪映射。
- 每帧保留 PTS，并用 `AVCaptureSession.synchronizationClock` 转换到本机单调时间轴；无法转换时才退回帧到达时间。外部端到端延迟仍需另行测量。
- 输出使用 `alwaysDiscardsLateVideoFrames`，Vision 侧最多一个推理和一个最新待处理帧；`didDrop` 按 TN2445 原因分类计数。
- 每个 Vision 工作项带 `runEpoch` 和单调帧序号；暂停、重开、重新校准、退出和相机变化会提升 epoch，旧任务即使完成也不能进入当前状态。
- 方向、画面尺寸、系统首选相机或校准后的 Center Stage 状态变化会清空轨迹并要求重新校准。首次站位时允许在 Center Stage 当前状态下校准，但校准后不可切换该效果。
- 启动路径采用归一化相机活动区，不把人体姿态置信度或人工校准作为进入游戏的前置门槛。Vision 在后台提供腕点和单玩家关联，玩家选手后立即进入游戏。
- `MotionProcessor.reset()` 在失效、跳点、超时、映射变化、暂停和会话切换时断开轨迹；恢复第一点只建立起点。
- 水果位置由 `spawnedAt + velocity × gameTime` 推导；保留至少 0.5 秒采集单调时钟到游戏时钟的历史，挥砍只与相同采集时刻的水果位置碰撞。
- 每局生成新的 `roundID`，GameplayEngine 拒绝其他局的挥砍；渲染节点使用有界对象池。
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
