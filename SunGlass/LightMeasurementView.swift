import SwiftUI
import UIKit

struct LightMeasurementView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let projectID: UUID

    @State private var meter: LightMeterController
    @State private var locationCapture = LocationCaptureController()
    @State private var committedSession: LightSession?
    @State private var showSafety = false
    @State private var showMemory = false
    @State private var initialProgress = 0.0
    @State private var liveProgress: Double?
    @State private var measurementDate = Date()
    @State private var lastLiveProgressUpdate = Date.distantPast
    @State private var hasAttemptedCommit = false
    @State private var waitingForLocation = false
    @State private var saveError: String?

    init(projectID: UUID) {
        self.projectID = projectID
        let storedScale = UserDefaults.standard.double(forKey: "intensityCalibrationScale")
        let scale = storedScale > 0 ? storedScale : 1
        _meter = State(initialValue: LightMeterController(
            maximumDuration: 30,
            intensityCalibrationScale: scale,
            draftProjectID: projectID
        ))
    }

    var body: some View {
        ZStack {
            LightCaptureCameraView(controller: meter)
                .ignoresSafeArea()

            cameraTreatment

            if committedSession != nil {
                resultView
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                measurementOverlay
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            beginMeasurement()
        }
        .onChange(of: meter.state) { _, state in
            if state == .completed { commitMeasurement() }
        }
        .onChange(of: meter.validSampleDuration) { _, _ in
            updateLiveProgress()
        }
        .onChange(of: meter.averageIntensity) { _, _ in
            updateLiveProgress()
        }
        .onChange(of: meter.acceptedSampleCount) { _, _ in
            updateLiveProgress()
        }
        .onChange(of: locationCapture.state) { _, _ in
            guard waitingForLocation, !locationCapture.isRequesting else { return }
            waitingForLocation = false
            commitMeasurement()
        }
        .onChange(of: store.project(id: projectID)?.status) { _, _ in
            guard !store.canCollectLight(projectID: projectID) else { return }
            meter.cancel()
            dismiss()
        }
        .onDisappear {
            if meter.isRunning { meter.cancel() }
            locationCapture.cancel()
        }
        .sheet(isPresented: $showSafety) {
            SafetyAndPrivacyView()
        }
        .sheet(isPresented: $showMemory) {
            MemoryEditorView(projectID: projectID, date: Date())
                .environment(store)
        }
    }

    private var project: GlassProject? { store.project(id: projectID) }

    private var cameraTreatment: some View {
        ZStack {
            Color.black.opacity(0.20)
            LinearGradient(
                colors: [.black.opacity(0.8), .clear, .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [meter.lightLevel.color.opacity(0.17), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 310
            )
            .animation(.easeInOut(duration: 0.6), value: meter.lightLevel)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var measurementOverlay: some View {
        VStack(spacing: 0) {
            topBar

            if meter.shouldShowThermalWarning {
                thermalWarning
                    .padding(.horizontal, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 20)

            if meter.state == .permissionDenied {
                permissionDenied
            } else if meter.state == .unavailable {
                unavailableCard
            } else if case .failed(let message) = meter.state {
                failureCard(message)
            } else {
                lightReading
            }

            Spacer(minLength: 24)

            bottomControls
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                meter.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.38), in: Circle())
            }
            .accessibilityLabel("閉じる")
            Spacer()
            Menu {
                measurementMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.38), in: Circle())
            }
            .accessibilityLabel("その他")
        }
        .foregroundStyle(SunGlassStyle.cream)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var measurementMenu: some View {
        Button {
            showSafety = true
        } label: {
            Label("安全とプライバシー", systemImage: "info.circle")
        }

        if project?.recordsLocation == true {
            Divider()
            switch locationCapture.state {
            case .permissionDenied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("位置情報の設定を開く", systemImage: "location.slash")
                }
            case .failed:
                Button { locationCapture.capture() } label: {
                    Label("位置情報を再試行", systemImage: "arrow.clockwise")
                }
            case .captured:
                Label("場所を端末内に記録", systemImage: "location.fill")
            case .requestingAuthorization, .locating:
                Label("場所を確認中", systemImage: "location.magnifyingglass")
            case .restricted:
                Label("位置情報は制限中", systemImage: "location.slash")
            case .idle:
                Label("場所は任意", systemImage: "location")
            }
        }
    }

    private var thermalWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "thermometer.high")
            Text(meter.latestMeasurement?.endReason == .thermalProtection
                 ? "高温のため停止"
                 : "端末が高温です")
            Spacer()
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(SunGlassStyle.cream)
        .padding(12)
        .background(SunGlassStyle.coral.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var lightReading: some View {
        VStack(spacing: 12) {
            if let project {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.black.opacity(0.28))

                    AnimatedMeasurementArtwork(
                        themeID: project.theme.rawValue,
                        seed: project.artworkSeed,
                        progress: displayedProgress,
                        palette: project.artworkPalette,
                        highlight: artworkHighlight,
                        recordedFacets: project.recordedLightFacets
                    )

                    burningLight
                        .animation(.easeInOut(duration: 0.45), value: burnStrength)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .aspectRatio(0.82, contentMode: .fit)
                .frame(maxWidth: 340)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [SunGlassStyle.amber.opacity(0.72), .white.opacity(0.2), SunGlassStyle.coral.opacity(0.62)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: SunGlassStyle.amber.opacity(0.18 + burnAmount * 0.30), radius: 30)
                .animation(.easeInOut(duration: 0.45), value: artworkHighlight)
                .accessibilityLabel("\(project.title)の計測中の作品")
                .accessibilityValue("着色率 \(Int((displayedProgress * 100).rounded()))パーセント")
            }

            HStack(spacing: 8) {
                Image(systemName: lightSymbol)
                    .accessibilityHidden(true)
                Text(meter.lightLevelLabel)
                    .lineLimit(1)
                Spacer(minLength: 10)
                Text("\(Int(meter.remainingDuration.rounded(.up)))秒")
                    .monospacedDigit()
                if meter.recoveredDraft {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(SunGlassStyle.cream.opacity(0.72))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.black.opacity(0.48), in: Capsule())
            .frame(maxWidth: 340)
        }
        .padding(.horizontal, 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(project?.title ?? "作品")、着色率\(Int((displayedProgress * 100).rounded()))パーセント、"
            + "\(meter.lightLevelLabel)、残り\(Int(meter.remainingDuration.rounded(.up)))秒"
            + (meter.recoveredDraft ? "、途中から再開" : "")
        )
    }

    @ViewBuilder
    private var burningLight: some View {
        if reduceMotion {
            burningLightLayer(phase: 0.55)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3.8) / 3.8
                burningLightLayer(phase: phase)
            }
        }
    }

    private func burningLightLayer(phase: Double) -> some View {
        let center = UnitPoint(
            x: CGFloat(0.14 + phase * 0.72),
            y: CGFloat(0.48 + sin(phase * .pi * 2) * 0.22)
        )
        return ZStack {
            RadialGradient(
                colors: [
                    .white.opacity(0.68),
                    SunGlassStyle.amber.opacity(0.74),
                    SunGlassStyle.coral.opacity(0.38),
                    .clear
                ],
                center: center,
                startRadius: 0,
                endRadius: 155
            )
            .blur(radius: 5)

            LinearGradient(
                colors: [.clear, SunGlassStyle.amber.opacity(0.44), SunGlassStyle.coral.opacity(0.24), .clear],
                startPoint: UnitPoint(x: CGFloat(phase - 0.35), y: 1),
                endPoint: UnitPoint(x: CGFloat(phase + 0.35), y: 0)
            )
            .blur(radius: 10)
        }
        .blendMode(.plusLighter)
        .opacity(meter.isRunning ? 0.10 + burnStrength * 0.56 : 0.08)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            if meter.state == .requestingPermission {
                ProgressView("カメラ確認中")
                    .tint(SunGlassStyle.lime)
                    .font(.system(size: 11, design: .rounded))
            } else if meter.isRunning {
                Button {
                    meter.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 19, weight: .bold))
                        .frame(width: 62, height: 62)
                        .foregroundStyle(SunGlassStyle.ink)
                        .background(
                            meter.validSampleDuration < 3
                                ? SunGlassStyle.cream.opacity(0.45)
                                : SunGlassStyle.lime,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(meter.validSampleDuration < 3)
                .accessibilityLabel(meter.validSampleDuration < 3 ? "光を安定させています" : "停止して保存")
            } else if meter.state == .completed {
                if waitingForLocation {
                    ProgressView("位置確認中")
                        .tint(SunGlassStyle.lime)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                } else if let saveError {
                    Text("保存できません")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.coral)
                        .accessibilityLabel("保存できません。\(saveError)")
                    Button {
                        hasAttemptedCommit = false
                        self.saveError = nil
                        commitMeasurement()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(SunGlassPrimaryButtonStyle())
                    .accessibilityLabel("保存を再試行")
                } else if isMeasurementValid {
                    ProgressView("保存中")
                        .tint(SunGlassStyle.lime)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                } else {
                    Text("光が不足しています")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.coral)
                    Button {
                        restartMeasurement()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(SunGlassPrimaryButtonStyle())
                    .accessibilityLabel("もう一度計測")
                }
            } else {
                Button { resumeMeasurementIfPossible() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 54, height: 54)
                }
                    .buttonStyle(SunGlassPrimaryButtonStyle())
                    .accessibilityLabel("もう一度試す")
            }
        }
    }

    private var resultView: some View {
        ZStack {
            SunGlassBackground()
            VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .frame(width: 42, height: 42)
                        }
                            .foregroundStyle(SunGlassStyle.lime)
                            .accessibilityLabel("閉じる")
                    }

                    Text("保存しました")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(SunGlassStyle.cream)

                    if let project {
                        ZStack {
                            GlassArtworkView(
                                themeID: project.theme.rawValue,
                                seed: project.artworkSeed,
                                progress: project.progress,
                                palette: project.artworkPalette,
                                leadLines: true,
                                highlight: 0.95,
                                recordedFacets: project.recordedLightFacets
                            )
                            .aspectRatio(0.82, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .shadow(color: meter.lightLevel.color.opacity(0.34), radius: 30)
                        }
                        .frame(maxHeight: 500)
                    }

                    Text("+\(Int(committedSession?.earnedPoints ?? 0)) pt")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.lime)

                    Button {
                        showMemory = true
                    } label: {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(SunGlassSecondaryButtonStyle())
                    .accessibilityLabel("一言を残す")
            }
            .padding(20)
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 15) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(SunGlassStyle.coral)
            Text("カメラ許可が必要")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(SunGlassPrimaryButtonStyle())
            .accessibilityLabel("設定を開く")
        }
        .foregroundStyle(SunGlassStyle.cream)
        .padding(21)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(20)
    }

    private var unavailableCard: some View {
        failureCard("ARKitに対応していません")
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 33))
                .foregroundStyle(SunGlassStyle.coral)
            Text("計測できません")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(message)
                .font(.system(size: 10, design: .rounded))
                .opacity(0.56)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button { resumeMeasurementIfPossible() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
            }
                .buttonStyle(SunGlassPrimaryButtonStyle())
                .accessibilityLabel("もう一度試す")
        }
        .foregroundStyle(SunGlassStyle.cream)
        .padding(20)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(20)
    }

    private var displayedProgress: Double {
        liveProgress ?? project?.progress ?? 0
    }

    private var projectedProgress: Double {
        guard let project,
              project.requiredLightPoints > 0,
              meter.validSampleDuration >= 3,
              meter.acceptedSampleCount >= 5 else { return initialProgress }
        let predictedPoints = store.estimatedLightPoints(
            projectID: projectID,
            date: measurementDate,
            duration: meter.validSampleDuration,
            averageIntensity: meter.averageIntensity
        )
        return min(1, initialProgress + predictedPoints / project.requiredLightPoints)
    }

    private var burnAmount: Double {
        min(max(meter.validSampleDuration / meter.maximumDuration, 0), 1)
    }

    private var burnStrength: Double {
        let intensity = min(max(meter.averageIntensity / 2_600, 0), 1)
        return min(1, 0.12 + burnAmount * 0.58 + intensity * 0.30)
    }

    private var artworkHighlight: Double {
        min(1, 0.30 + burnAmount * 0.66)
    }

    private var lightSymbol: String {
        switch meter.lightLevel {
        case .dark: "moon.stars.fill"
        case .soft: "cloud.sun.fill"
        case .bright: "sun.min.fill"
        case .strong: "sun.max.fill"
        case .veryStrong: "sun.max.trianglebadge.exclamationmark.fill"
        }
    }

    private var isMeasurementValid: Bool {
        guard let measurement = meter.latestMeasurement else { return false }
        return measurement.duration >= 3
            && measurement.elapsedDuration <= 30.05
            && measurement.duration <= measurement.elapsedDuration
            && measurement.acceptedSampleCount >= 5
            && measurement.averageIntensity > 0
    }

    private func beginMeasurement() {
        guard store.canCollectLight(projectID: projectID) else {
            meter.discardDraft()
            dismiss()
            return
        }
        initialProgress = project?.progress ?? 0
        liveProgress = initialProgress
        if project?.recordsLocation == true { locationCapture.capture() }
        let now = Date()
        let draft = LightMeasurementDraftStore.load(projectID: projectID, now: now)
        measurementDate = draft?.startedAt ?? now
        meter.start(resuming: draft)
        updateLiveProgress(force: true)
        // Restoring a completed checkpoint does not produce an onChange transition.
        if meter.state == .completed { commitMeasurement() }
    }

    private func resumeMeasurementIfPossible() {
        guard store.canCollectLight(projectID: projectID) else {
            meter.discardDraft()
            dismiss()
            return
        }
        if project?.recordsLocation == true,
           !locationCapture.isRequesting,
           locationCapture.capturedLocation == nil {
            locationCapture.capture()
        }
        if liveProgress == nil {
            initialProgress = project?.progress ?? 0
            liveProgress = initialProgress
        }
        let now = Date()
        let draft = LightMeasurementDraftStore.load(projectID: projectID, now: now)
        measurementDate = draft?.startedAt ?? now
        meter.start(resuming: draft)
        updateLiveProgress(force: true)
    }

    private func commitMeasurement() {
        guard !hasAttemptedCommit,
              let measurement = meter.latestMeasurement,
              isMeasurementValid else { return }
        if project?.recordsLocation == true, locationCapture.isRequesting {
            waitingForLocation = true
            return
        }
        hasAttemptedCommit = true
        guard let session = store.addLightSession(
            from: measurement,
            to: projectID,
            location: project?.recordsLocation == true ? locationCapture.capturedLocation : nil
        ) else {
            saveError = store.lastErrorMessage ?? "光を端末へ保存できませんでした。"
            return
        }
        meter.discardDraft()
        locationCapture.reset()
        withAnimation(.easeInOut(duration: 0.6)) {
            committedSession = session
        }
        if UserDefaults.standard.bool(forKey: "measurementHaptics") {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func restartMeasurement() {
        hasAttemptedCommit = false
        waitingForLocation = false
        saveError = nil
        liveProgress = initialProgress
        measurementDate = Date()
        lastLiveProgressUpdate = .distantPast
        if project?.recordsLocation == true { locationCapture.capture() }
        meter.start()
    }

    private func updateLiveProgress(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastLiveProgressUpdate) >= 0.2 else { return }
        lastLiveProgressUpdate = now
        let target = projectedProgress
        let current = liveProgress ?? initialProgress
        guard target > current else { return }
        withAnimation(reduceMotion ? nil : .linear(duration: 0.28)) {
            liveProgress = target
        }
    }

}

private struct AnimatedMeasurementArtwork: View, Animatable {
    let themeID: String
    let seed: Int
    var progress: Double
    let palette: [Color]
    var highlight: Double
    let recordedFacets: [RecordedLightFacet]

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, highlight) }
        set {
            progress = newValue.first
            highlight = newValue.second
        }
    }

    var body: some View {
        GlassArtworkView(
            themeID: themeID,
            seed: seed,
            progress: progress,
            palette: palette,
            leadLines: true,
            highlight: highlight,
            recordedFacets: recordedFacets
        )
    }
}
