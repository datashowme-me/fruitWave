import AVKit
import FruitWaveCore
import SpriteKit
import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.08), Color(red: 0.03, green: 0.14, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            content
        }
        .tint(.green)
        .continuityDevicePicker(
            isPresented: Binding(get: { model.showDevicePicker }, set: { model.showDevicePicker = $0 }),
            onDidConnect: model.connect
        )
        .onPlayPauseCommand {
            if model.state == .playing { model.pause() }
            else if model.state == .paused { model.resume() }
        }
        .onExitCommand {
            if model.state == .playing { model.pause() }
            else if model.state != .waitingForConnection { model.exitToConnection() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .waitingForConnection: ConnectionView(model: model)
        case .framing: FramingView(model: model)
        case .calibration: CalibrationView(model: model)
        case .ready, .resuming: CountdownView(model: model)
        case .playing: PlayingView(model: model)
        case .paused: PauseView(model: model)
        case .results: ResultsView(model: model)
        }
    }
}

private struct ConnectionView: View {
    let model: AppModel
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
                Text(model.statusMessage).foregroundStyle(.secondary)
                Button("连接 iPhone") { model.requestConnection() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityHint("打开系统连续互通相机设备选择器")
            }
            .font(.title3).frame(width: 620, alignment: .leading)
        }
        .padding(90)
    }
}

private struct FramingView: View {
    let model: AppModel
    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: model.camera.captureSession).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(model.statusMessage).font(.title2.bold())
                Picker("使用哪只手", selection: Binding(get: { model.selectedHand }, set: { model.selectedHand = $0 })) {
                    Text("左手").tag(HandSide.left)
                    Text("右手").tag(HandSide.right)
                }
                .pickerStyle(.segmented).frame(width: 420)
                HStack(spacing: 24) {
                    Button("退出") { model.exitToConnection() }
                    Button("开始校准") { model.beginCalibration() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(32).frame(maxWidth: .infinity)
            .background(.black.opacity(0.72))
        }
    }
}

private struct CalibrationView: View {
    let model: AppModel
    var body: some View {
        ZStack {
            CameraPreview(session: model.camera.captureSession).ignoresSafeArea()
            Color.black.opacity(0.28).ignoresSafeArea()
            if let target = model.reviewTarget {
                GeometryReader { proxy in
                    Circle().stroke(.green, lineWidth: 12).background(Circle().fill(.green.opacity(0.2)))
                        .frame(width: 90, height: 90)
                        .position(x: target.x * proxy.size.width, y: (1 - target.y / (9.0 / 16.0)) * proxy.size.height)
                }
            }
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("校准 (min(model.calibrationStep + 1, 7)) / 7").font(.headline).foregroundStyle(.green)
                        Text(model.statusMessage).font(.title2.bold())
                    }
                    Spacer()
                    Button("退出") { model.exitToConnection() }
                }
                Spacer()
                Button(model.calibrationStep < 2 ? "确认这个位置" : "确认已触达") { model.confirmCalibrationPoint() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(54)
        }
    }
}

private struct CountdownView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 28) {
            Text(model.isResumeCountdown ? "继续游戏" : "准备好了吗？")
                .font(.system(size: 54, weight: .bold, design: .rounded))
            Text(model.isResumeCountdown ? "保持站位，倒计时期间不会计分。" : "倒计时结束后才会生成水果。")
                .font(.title2).foregroundStyle(.secondary)
            if model.state == .ready {
                HStack(spacing: 24) {
                    Button("重新校准") { model.recalibrate() }
                    Button("开始 90 秒游戏") { model.startGame() }.buttonStyle(.borderedProminent)
                }
            } else {
                Text("\(model.countdown)").font(.system(size: 150, weight: .black, design: .rounded)).foregroundStyle(.green)
            }
        }
    }
}

private struct PlayingView: View {
    let model: AppModel
    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: model.scene, options: [.allowsTransparency]).ignoresSafeArea()
            HStack {
                Metric(title: "分数", value: "\(model.score)")
                Spacer()
                Text("按 ⏯ 暂停").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Metric(title: "剩余", value: "\(model.secondsRemaining)s")
            }.padding(.horizontal, 64).padding(.top, 34)
        }
    }
}

private struct Metric: View {
    let title: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.green)
            Text(value).font(.system(size: 46, weight: .black, design: .rounded)).monospacedDigit()
        }.padding(.horizontal, 24).padding(.vertical, 14).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PauseView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            Text("已暂停").font(.system(size: 64, weight: .black, design: .rounded))
            Text(model.statusMessage).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 20) {
                Button("退出") { model.exitToConnection() }
                Button("重新校准") { model.recalibrate() }
                Button("重开") { model.restart() }
                Button("继续") { model.resume() }.buttonStyle(.borderedProminent)
            }.padding(.top, 18)
        }
    }
}

private struct ResultsView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 24) {
            Text("本局完成").font(.system(size: 58, weight: .black, design: .rounded))
            Text("\(model.score)").font(.system(size: 150, weight: .black, design: .rounded)).foregroundStyle(.green)
            Text("最高分  \(model.highScore)").font(.title2).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button("退出") { model.exitToConnection() }
                Button("再来一局") { model.restart() }.buttonStyle(.borderedProminent)
            }
        }
    }
}
