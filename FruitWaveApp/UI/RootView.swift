import AVKit
import FruitWaveCore
import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.08), Color(red: 0.03, green: 0.14, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            content
        }
        .tint(.green)
        .continuityDevicePicker(
            isPresented: Binding(
                get: { model.showDevicePicker },
                set: { model.setDevicePickerPresented($0) }
            ),
            onDidConnect: model.connect
        )
        .onPlayPauseCommand {
            if model.state == .playing { model.pause() }
            else if model.state == .paused { model.resume() }
        }
        .onAppear {
            model.reduceMotion = reduceMotion
            model.handleInitialLaunchArguments()
        }
        .onChange(of: reduceMotion) { _, value in model.reduceMotion = value }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.handleAppBecameActive()
            case .background:
                model.handleAppBecameInactive()
            case .inactive:
                // The system Continuity Camera picker temporarily makes the
                // scene inactive while QR pairing completes. Treating that as
                // background stops the capture session just as the iPhone is
                // handed back to the app, leaving the picker stuck.
                break
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .waitingForConnection: ConnectionView(model: model)
        case .framing: FramingView(model: model)
        case .calibration: CalibrationView(model: model)
        case .ready: ReadyView(model: model)
        case .resuming: PlayingView(model: model)
        case .playing: PlayingView(model: model)
        case .paused: PauseView(model: model)
        case .results: ResultsView(model: model)
        }
    }
}

private struct ConnectionView: View {
    let model: AppModel
    @State private var showHelp = false
    // Also opened via env FW_ASSET_LAB=1: devicectl consumes dash-prefixed
    // launch arguments, so device acceptance automation uses the env route.
    // FW_FRUIT=<slug> selects which fruit the lab reviews (default apple).
    @State private var showAssetLab = ProcessInfo.processInfo.arguments.contains("--apple-asset-lab")
        || ProcessInfo.processInfo.environment["FW_ASSET_LAB"] == "1"
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case sound, help, assetLab, demo, connect }

    var body: some View {
        HStack(spacing: 90) {
            VStack(alignment: .leading, spacing: 24) {
                Text("FRUIT").font(.system(size: 96, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("WAVE").font(.system(size: 96, weight: .black, design: .rounded)).foregroundStyle(.green)
                Text("挥手，切开客厅里的水果浪潮。")
                    .font(.title2).foregroundStyle(.white.opacity(0.75))
            }
            VStack(alignment: .leading, spacing: 24) {
                Label("Apple TV 4K（第二代或更新）", systemImage: "appletv")
                Label("兼容的 iPhone，横向稳定摆放", systemImage: "iphone.gen3")
                Label("清理手臂活动范围内的物品", systemImage: "figure.arms.open")
                Label(model.statusMessage, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                Button { model.soundEnabled.toggle() } label: {
                    Label(soundLabel, systemImage: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .focused($focusedControl, equals: .sound)
                .accessibilityValue(model.soundEnabled ? "已开启" : "已关闭")
                Button("玩法与安全说明") { showHelp = true }
                    .focused($focusedControl, equals: .help)
                if #available(tvOS 26.0, *) {
                    Button("验收水果 3D 效果") { showAssetLab = true }
                        .focused($focusedControl, equals: .assetLab)
                }
                Button("直接看动画演示") { model.startAnimationDemo() }
                    .focused($focusedControl, equals: .demo)
                Button("连接 iPhone") { model.requestConnection() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .focused($focusedControl, equals: .connect)
                    .accessibilityHint("打开系统连续互通相机设备选择器")
            }
            .font(.title3).frame(width: 620, alignment: .leading)
        }
        .padding(90)
        .defaultFocus($focusedControl, .connect)
        .sheet(isPresented: $showHelp) {
            HelpView { showHelp = false }
        }
        .fullScreenCover(isPresented: $showAssetLab) {
            if #available(tvOS 26.0, *) {
                FruitAssetLabView { showAssetLab = false }
            }
        }
    }

    private var soundLabel: String { model.soundEnabled ? "切割音效：开" : "切割音效：关" }
}

private struct HelpView: View {
    let dismiss: () -> Void
    @FocusState private var dismissFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("开始之前").font(.system(size: 52, weight: .black, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.75)
            Label("把 iPhone 横向固定，确保全身上半部分和手腕清晰可见。", systemImage: "iphone.gen3")
            Label("画面中一次只保留一名玩家，周围留出挥手空间。", systemImage: "figure.arms.open")
            Label("选择左右手后立即开始，不需要姿势校准。", systemImage: "scope")
            Label("快速挥动所选手腕切水果；遮挡或断连会自动暂停。", systemImage: "hand.wave")
            Button("知道了", action: dismiss)
                .buttonStyle(.borderedProminent)
                .focused($dismissFocused)
        }
        .font(.title3)
        .padding(80)
        .defaultFocus($dismissFocused, true)
    }
}

private struct FramingView: View {
    let model: AppModel
    @State private var showDisconnectConfirmation = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case leftHand, rightHand, start, disconnect }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: model.camera.captureSession).ignoresSafeArea()
            if let wrist = model.framingWristPreviewPoint {
                PreviewWristIndicator(point: wrist, sourceSize: model.captureGeometry?.orientedPixelSize)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 18) {
                Label(model.statusMessage, systemImage: model.canBeginCalibration ? "checkmark.circle.fill" : "viewfinder.circle")
                    .font(.title2.bold())
                Text("选择左右手后立即开始；腕点短暂丢失时游戏不会退出")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.72))
                HStack(spacing: 24) {
                    handButton(.left, title: "左手")
                    handButton(.right, title: "右手")
                }
                HStack(spacing: 24) {
                    Button("开始游戏") { model.startWithAutomaticRange() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .focused($focusedControl, equals: .start)
                    Button("断开 iPhone") { showDisconnectConfirmation = true }
                        .controlSize(.large)
                        .focused($focusedControl, equals: .disconnect)
                }
            }
            .padding(32).frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .defaultFocus($focusedControl, .start)
        .onExitCommand { showDisconnectConfirmation = true }
        .alert("确定断开 iPhone？", isPresented: $showDisconnectConfirmation) {
            Button("取消", role: .cancel) {}
            Button("断开", role: .destructive) { model.exitToConnection() }
        } message: {
            Text("断开后需要重新连接，左右手选择本身不需要确认。")
        }
    }

    private func handButton(_ side: HandSide, title: String) -> some View {
        let isSelected = model.selectedHand == side
        return Button {
            model.selectHand(side)
        } label: {
            Label(title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                .frame(width: 160)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? .green : .gray)
        .controlSize(.large)
        .focused($focusedControl, equals: side == .left ? .leftHand : .rightHand)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }
}

private struct CalibrationView: View {
    let model: AppModel
    @State private var showExitConfirmation = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case exit }

    var body: some View {
        ZStack {
            CameraPreview(session: model.camera.captureSession).ignoresSafeArea()
            Color.black.opacity(0.28).ignoresSafeArea()
            if let target = model.reviewTarget {
                GeometryReader { proxy in
                    ZStack {
                        Circle().stroke(.green, lineWidth: 12).background(Circle().fill(.green.opacity(0.2)))
                        Image(systemName: "scope").font(.system(size: 54, weight: .bold))
                    }
                        .frame(width: 168, height: 168)
                        .position(x: target.x * proxy.size.width, y: (1 - target.y / (9.0 / 16.0)) * proxy.size.height)
                        .accessibilityHidden(true)
                }
            }
            if let cursor = model.calibrationCursor {
                GeometryReader { proxy in
                    ZStack {
                        Circle().fill(.white)
                        Image(systemName: model.calibrationCursorIsInside ? "checkmark" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(model.calibrationCursorIsInside ? .blue : .orange)
                    }
                        .overlay(Circle().stroke(model.calibrationCursorIsInside ? .cyan : .orange, lineWidth: 8))
                        .shadow(color: model.calibrationCursorIsInside ? .cyan : .orange, radius: 18)
                        .frame(width: 54, height: 54)
                        .position(cursorPosition(cursor, in: proxy.size))
                }
                .allowsHitTesting(false)
            }
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("校准 \(min(model.calibrationStep + 1, model.calibrationStepCount)) / \(model.calibrationStepCount)").font(.headline).foregroundStyle(.green)
                        Text(model.statusMessage).font(.title2.bold())
                    }
                    Spacer()
                    Button("退出") { showExitConfirmation = true }
                        .focused($focusedControl, equals: .exit)
                }
                Spacer()
                VStack(spacing: 12) {
                    ProgressView(value: model.calibrationProgress)
                        .tint(.green)
                        .frame(width: 520)
                        .scaleEffect(y: 2)
                    Text(model.calibrationStep < 2 ? "保持手腕稳定，锁定后会自动采集" : "将白色光标停在绿色目标内")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }.padding(54)
        }
        .onExitCommand { model.cancelCalibration() }
        .alert("退出并断开 iPhone？", isPresented: $showExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { model.exitToConnection() }
        } message: {
            Text("返回键只退出校准；此操作会断开 iPhone。")
        }
    }

    private func cursorPosition(_ cursor: Vector2, in viewport: CGSize) -> CGPoint {
        guard model.calibrationStep < 2,
              let source = model.captureGeometry?.orientedPixelSize,
              source.width > 0,
              source.height > 0 else {
            return CGPoint(x: cursor.x * viewport.width, y: cursor.y * viewport.height)
        }
        let scale = max(viewport.width / source.width, viewport.height / source.height)
        let displayed = CGSize(width: source.width * scale, height: source.height * scale)
        let origin = CGPoint(
            x: (viewport.width - displayed.width) / 2,
            y: (viewport.height - displayed.height) / 2
        )
        return CGPoint(
            x: origin.x + cursor.x * displayed.width,
            y: origin.y + cursor.y * displayed.height
        )
    }
}

private struct PreviewWristIndicator: View {
    let point: Vector2
    let sourceSize: CGSize?

    var body: some View {
        GeometryReader { proxy in
            Circle()
                .fill(.white)
                .overlay {
                    ZStack {
                        Circle().stroke(.cyan, lineWidth: 8)
                        Image(systemName: "viewfinder").font(.system(size: 22, weight: .black)).foregroundStyle(.blue)
                    }
                }
                .shadow(color: .cyan, radius: 18)
                .frame(width: 54, height: 54)
                .position(position(in: proxy.size))
        }
        .accessibilityHidden(true)
    }

    private func position(in viewport: CGSize) -> CGPoint {
        guard let sourceSize, sourceSize.width > 0, sourceSize.height > 0 else {
            return CGPoint(x: point.x * viewport.width, y: point.y * viewport.height)
        }
        let scale = max(viewport.width / sourceSize.width, viewport.height / sourceSize.height)
        let displayed = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(x: (viewport.width - displayed.width) / 2, y: (viewport.height - displayed.height) / 2)
        return CGPoint(x: origin.x + point.x * displayed.width, y: origin.y + point.y * displayed.height)
    }
}

private struct ReadyView: View {
    let model: AppModel
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case recalibrate, start }

    var body: some View {
        VStack(spacing: 28) {
            Text("准备好了吗？")
                .font(.system(size: 54, weight: .bold, design: .rounded))
            Text("按下开始后立即生成水果并开始计时。")
                .font(.title2).foregroundStyle(.secondary)
            Text(model.statusMessage)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                Button("返回定位") { model.recalibrate() }
                    .focused($focusedControl, equals: .recalibrate)
                Button("立即开始") { model.startGame() }
                    .buttonStyle(.borderedProminent)
                    .focused($focusedControl, equals: .start)
            }
        }
        .defaultFocus($focusedControl, .start)
        .onExitCommand { model.recalibrate() }
    }
}

private struct PlayingView: View {
    let model: AppModel
    var body: some View {
        ZStack(alignment: .top) {
            SceneKitGameView(renderer: model.renderer, onPanSlash: { start, end in
                model.applyRemoteSlash(from: start, to: end)
            }).ignoresSafeArea()
            HStack {
                Metric(title: "分数", value: "\(model.score)")
                if model.gameMode == .classic {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Image(systemName: index < model.livesRemaining ? "heart.fill" : "heart")
                                .foregroundStyle(index < model.livesRemaining ? .red : .secondary)
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                if model.isHandVisible {
                    Text("挥手或遥控器触控滑动 · 按 ⏯ 暂停").font(.callout).foregroundStyle(.secondary)
                } else {
                    Label("支持挥手体感或遥控器触控滑动切水果", systemImage: "hand.draw")
                        .font(.callout.bold())
                        .foregroundStyle(.cyan)
                }
                Spacer()
                Metric(title: "剩余", value: "\(model.secondsRemaining)s")
            }.padding(.horizontal, 64).padding(.top, 34)
        }
        .onExitCommand { model.pause() }
    }
}

private struct Metric: View {
    let title: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.green)
            Text(value).font(.system(size: 46, weight: .black, design: .rounded)).monospacedDigit()
        }.padding(.horizontal, 24).padding(.vertical, 14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PauseView: View {
    let model: AppModel
    @State private var showExitConfirmation = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case exit, recalibrate, restart, sound, resume }

    var body: some View {
        VStack(spacing: 22) {
            Text("已暂停").font(.system(size: 64, weight: .black, design: .rounded))
            Text(model.statusMessage).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 20) {
                Button(model.isDemoMode ? "退出演示" : "退出") { showExitConfirmation = true }
                    .focused($focusedControl, equals: .exit)
                if !model.isDemoMode {
                    Button("返回定位") { model.recalibrate() }
                        .focused($focusedControl, equals: .recalibrate)
                }
                Button("重开") { model.restart() }
                    .focused($focusedControl, equals: .restart)
                Button { model.soundEnabled.toggle() } label: {
                    Label(model.soundEnabled ? "音效：开" : "音效：关", systemImage: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .focused($focusedControl, equals: .sound)
                .accessibilityValue(model.soundEnabled ? "已开启" : "已关闭")
                Button("继续") { model.resume() }
                    .buttonStyle(.borderedProminent)
                    .focused($focusedControl, equals: .resume)
            }.padding(.top, 18)
        }
        .defaultFocus($focusedControl, .resume)
        .onExitCommand { model.resume() }
        .alert(model.isDemoMode ? "退出动画演示？" : "退出并断开 iPhone？", isPresented: $showExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { model.exitToConnection() }
        } message: {
            Text(model.isDemoMode ? "将返回开始页面。" : "当前游戏进度将结束，之后需要重新连接。")
        }
    }
}

private struct ResultsView: View {
    let model: AppModel
    @State private var showExitConfirmation = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case exit, changePlayer, restart }

    var body: some View {
        VStack(spacing: 24) {
            Text("本局完成").font(.system(size: 58, weight: .black, design: .rounded))
            Text("\(model.score)").font(.system(size: 150, weight: .black, design: .rounded)).foregroundStyle(.green)
            Text("最高分  \(model.highScore)").font(.title2).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button(model.isDemoMode ? "退出演示" : "退出") { showExitConfirmation = true }
                    .focused($focusedControl, equals: .exit)
                if !model.isDemoMode {
                    Button("换人玩") { model.changePlayer() }
                        .focused($focusedControl, equals: .changePlayer)
                }
                Button("再来一局") { model.restart() }
                    .buttonStyle(.borderedProminent)
                    .focused($focusedControl, equals: .restart)
            }
        }
        .defaultFocus($focusedControl, .restart)
        .onExitCommand { showExitConfirmation = true }
        .alert(model.isDemoMode ? "退出动画演示？" : "退出并断开 iPhone？", isPresented: $showExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { model.exitToConnection() }
        } message: {
            Text(model.isDemoMode ? "将返回开始页面。" : "退出后需要重新连接 iPhone。")
        }
    }
}
