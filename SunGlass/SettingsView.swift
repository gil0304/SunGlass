import SwiftUI

struct SettingsView: View {
    @AppStorage("reduceLightEffects") private var reduceLightEffects = false
    @AppStorage("measurementHaptics") private var measurementHaptics = true
    @State private var showSafety = false
    @State private var showCalibration = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $reduceLightEffects) {
                        Label("発光を軽減", systemImage: "sparkles")
                    }
                    Toggle(isOn: $measurementHaptics) {
                        Label("計測時の触覚", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("位置情報は作品ごと", systemImage: "location")
                        Text("約100m・端末内")
                            .font(.caption)
                            .foregroundStyle(SunGlassStyle.cream.opacity(0.5))
                            .padding(.leading, 28)
                    }

                    Button {
                        showSafety = true
                    } label: {
                        Label("プライバシーと安全", systemImage: "hand.raised")
                    }
                    .foregroundStyle(SunGlassStyle.cream)
                }

                Section {
                    Button {
                        showCalibration = true
                    } label: {
                        Label("光を調整", systemImage: "dial.medium")
                    }
                    .foregroundStyle(SunGlassStyle.cream)
                }

                Section {
                    Text("紫外線量、日焼け量、肌への影響は測定しません。")
                        .font(.footnote)
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.55))
                }
            }
            .tint(SunGlassStyle.lime)
            .scrollContentBackground(.hidden)
            .background { SunGlassBackground() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(SunGlassStyle.cream)
                        .accessibilityLabel("設定")
                }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showSafety) {
                SafetyAndPrivacyView()
            }
            .sheet(isPresented: $showCalibration) {
                CalibrationGuideView()
            }
        }
    }

}

struct SafetyAndPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    private let privacyItems = [
        ("video.slash", "映像は保存・送信しません"),
        ("location", "位置は任意・約100m・端末内"),
        ("sun.max.trianglebadge.exclamationmark", "太陽へ向けない・直射日光下に放置しない"),
        ("thermometer.high", "高温時は自動停止します"),
        ("clock", "1回10〜30秒・1日90秒まで"),
        ("house", "室内光も記録できます")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(privacyItems.enumerated()), id: \.offset) { _, item in
                        Label(item.1, systemImage: item.0)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SunGlassStyle.cream)
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Text("作品用の相対値です。医療・健康・気象値ではありません。")
                        .font(.footnote)
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.55))
                }
            }
            .scrollContentBackground(.hidden)
            .background { SunGlassBackground() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(systemName: "hand.raised")
                        .foregroundStyle(SunGlassStyle.cream)
                        .accessibilityLabel("プライバシーと安全")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("閉じる")
                }
            }
        }
        .tint(SunGlassStyle.lime)
        .preferredColorScheme(.dark)
    }
}

struct CalibrationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("intensityCalibrationScale") private var calibrationScale = 1.0
    @State private var meter = LightMeterController(maximumDuration: 10)
    @State private var step = 0
    @State private var indoorIntensity: Double?
    @State private var completed = false
    @State private var message: String?
    var onComplete: () -> Void = {}

    private var instruction: String {
        if completed { return "調整完了" }
        if step == 0 { return "端末をゆっくり持ち、室内で10秒間測ります。" }
        return "太陽へ直接向けず、明るい窓辺で10秒間測ります。"
    }

    private var actionTitle: String {
        if completed { return "完了" }
        if meter.isRunning { return "計測を終了" }
        return step == 0 ? "室内を計測" : "窓辺を計測"
    }

    private var actionSymbol: String {
        if completed { return "checkmark" }
        return meter.isRunning ? "stop.fill" : "camera.aperture"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LightCaptureCameraView(controller: meter)
                    .ignoresSafeArea()
                    .opacity(meter.isRunning ? 0.2 : 0)
                SunGlassBackground()
                    .opacity(meter.isRunning ? 0.88 : 1)

                VStack(spacing: 22) {
                    Spacer()

                    Image(systemName: completed ? "checkmark" : (step == 0 ? "lamp.table.fill" : "window.vertical.open"))
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(completed ? SunGlassStyle.lime : SunGlassStyle.cream)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        if !completed {
                            Text("\(step + 1) / 2")
                                .font(SunGlassStyle.label(11))
                                .foregroundStyle(SunGlassStyle.cream.opacity(0.5))
                                .monospacedDigit()
                        }
                        Text(instruction)
                            .font(.system(size: completed ? 24 : 15, weight: completed ? .bold : .medium, design: .rounded))
                            .foregroundStyle(SunGlassStyle.cream)
                            .multilineTextAlignment(.center)
                    }

                    if meter.isRunning {
                        VStack(spacing: 8) {
                            ProgressView(value: min(meter.duration / 10, 1))
                                .tint(SunGlassStyle.lime)
                                .accessibilityLabel("計測の進捗")
                            Text("残り \(Int(ceil(meter.remainingDuration)))秒")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SunGlassStyle.lime)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(SunGlassStyle.coral)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    Button {
                        if completed {
                            onComplete()
                            dismiss()
                        } else if meter.isRunning {
                            meter.stop()
                        } else {
                            message = nil
                            meter.start()
                        }
                    } label: {
                        Image(systemName: actionSymbol)
                            .font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SunGlassPrimaryButtonStyle())
                    .accessibilityLabel(actionTitle)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(SunGlassStyle.cream.opacity(0.7))
                    }
                    .accessibilityLabel("閉じる")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: meter.state) { _, state in
            if state == .permissionDenied {
                message = "カメラの許可が必要です。設定アプリでSUN GLASSのカメラを許可してください。"
                return
            }
            if state == .unavailable {
                message = "この端末では光の調整を利用できません。"
                return
            }
            if case .failed(let reason) = state {
                message = reason
                return
            }
            guard state == .completed, let result = meter.latestMeasurement else { return }
            guard result.duration >= 3,
                  result.acceptedSampleCount >= 5,
                  result.averageIntensity > 0 else {
                message = "光を安定して取得できませんでした。端末を固定して、もう一度お試しください。"
                return
            }
            if step == 0 {
                indoorIntensity = result.averageIntensity
                step = 1
            } else if let indoorIntensity {
                guard result.averageIntensity > indoorIntensity * 1.08 else {
                    message = "室内との差が小さいようです。より明るい窓辺で、太陽へ直接向けずに再計測してください。"
                    return
                }
                let referenceProduct = 600.0 * 1_800.0
                let measuredProduct = max(1, indoorIntensity * result.averageIntensity)
                calibrationScale = min(max(sqrt(referenceProduct / measuredProduct), 0.5), 2)
                completed = true
            }
        }
        .onDisappear { meter.cancel() }
    }
}

#Preview {
    SettingsView()
}
