# 工程布局与构建约束

## Targets(project.yml)

| target | 类型 | 平台 | 说明 |
|---|---|---|---|
| FruitWave | application | tvOS 17 | App 入口 + UI + 相机/Vision |
| FruitWaveCore | framework | tvOS 17 | 确定性游戏引擎(无 UI 依赖) |
| FruitWaveCoreTests | bundle.unit-test | tvOS 17 | 引擎与动作处理单测 |

- Swift 6;bundle id `com.example.FruitWave`;DEVELOPMENT_TEAM `7T5TZY885W`,自动签名。
- `FruitWave.xcodeproj` 由 xcodegen 生成且被 gitignore;改 `project.yml` 后必须
  `Scripts/bootstrap.sh` 重新生成。
- DerivedData 固定 `.build/xcode`(被 `.build/` 忽略)。

## 资源约定
- `Resources/FruitCapTextures/` — 20 种水果 skin/cap 贴图。
- `Resources/Models/Apple/` — Blender 产出的 usdz 对 + 预览;`.blend` / `_preview.png` /
  `_basecolor.png` 不打包(project.yml excludes)。
- `Resources/Audio/` — Kenney CC0 采样 + 程序音效。

## 已知真机(2026-10-21)
- 客厅:Apple TV 4K(第 3 代,AppleTV14,1),tvOS 27.0,
  identifier `CC71D430-6B29-5E60-9267-DB8417387ED2`。
- 部署用 devicectl,设备标识接受 uuid / name(`客厅`)。

## 本机环境(2026-10-21 实测)
- Xcode 26.2(`/Applications/Xcode.app`);xcodegen 2.46.0。
- 系统默认 developer directory 是 CommandLineTools,直接跑 xcodebuild 会报
  "requires Xcode";所有脚本自动 `export DEVELOPER_DIR=/Applications/Xcode.app`。
