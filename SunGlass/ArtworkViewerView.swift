import CoreMotion
import Observation
import SwiftUI

@MainActor
@Observable
private final class DeviceTiltController {
    private let manager = CMMotionManager()
    private(set) var pitch = 0.0
    private(set) var roll = 0.0

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor [weak self] in
                self?.pitch = min(max(motion.attitude.pitch, -0.45), 0.45)
                self?.roll = min(max(motion.attitude.roll, -0.45), 0.45)
            }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

struct ArtworkViewerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let projectID: UUID

    @State private var tilt = DeviceTiltController()
    @State private var zoom = 1.0
    @State private var lastZoom = 1.0
    @State private var drag = CGSize.zero
    @State private var lastDrag = CGSize.zero
    @State private var showLeadLines = true
    @State private var historyIndex = 0.0
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ambientBackground

            if let project = store.project(id: projectID) {
                artwork(project)

                if showControls {
                    controls(project)
                        .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            historyIndex = Double(store.project(id: projectID)?.sessions.count ?? 0)
            tilt.start()
        }
        .onDisappear { tilt.stop() }
    }

    private var ambientBackground: some View {
        ZStack {
            RadialGradient(
                colors: [SunGlassStyle.forest.opacity(0.7), .black],
                center: UnitPoint(x: 0.5 + tilt.roll * 0.18, y: 0.45 - tilt.pitch * 0.15),
                startRadius: 10,
                endRadius: 570
            )
            Circle()
                .fill(SunGlassStyle.lime.opacity(0.08))
                .frame(width: 330, height: 330)
                .blur(radius: 80)
                .offset(x: CGFloat(tilt.roll * 220), y: CGFloat(tilt.pitch * 220))
        }
        .ignoresSafeArea()
    }

    private func artwork(_ project: GlassProject) -> some View {
        let cutoff = historyCutoff(project)
        let palette = project.artworkPalette(asOf: cutoff)
        return GlassArtworkView(
            themeID: project.theme.rawValue,
            seed: project.artworkSeed,
            progress: playbackProgress(project),
            palette: palette,
            leadLines: showLeadLines,
            highlight: highlight,
            recordedFacets: project.recordedLightFacets(asOf: cutoff)
        )
        .aspectRatio(0.82, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(showLeadLines ? 0.28 : 0.08), lineWidth: 1)
        }
        .shadow(color: palette.first?.opacity(0.32) ?? .clear, radius: 32, x: CGFloat(tilt.roll * 20), y: CGFloat(tilt.pitch * 20))
        .scaleEffect(zoom)
        .offset(drag)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : tilt.roll * 9 + Double(drag.width / 36)), axis: (x: 0, y: 1, z: 0), perspective: 0.42)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : -tilt.pitch * 9 - Double(drag.height / 45)), axis: (x: 1, y: 0, z: 0), perspective: 0.42)
        .padding(.horizontal, 28)
        .gesture(dragGesture.simultaneously(with: magnificationGesture))
        .onLongPressGesture(minimumDuration: 0.18, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.2)) { showLeadLines = !pressing }
        }, perform: {})
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
        .accessibilityHint("ドラッグで角度変更、ピンチで拡大、長押しで鉛線を隠します")
        .accessibilityAction(named: Text(showLeadLines ? "鉛線を隠す" : "鉛線を表示")) {
            showLeadLines.toggle()
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: zoom = min(zoom + 0.25, 4)
            case .decrement: zoom = max(zoom - 0.25, 0.7)
            @unknown default: break
            }
            lastZoom = zoom
        }
    }

    private func controls(_ project: GlassProject) -> some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 43, height: 43)
                        .background(.black.opacity(0.46), in: Circle())
                }
                .accessibilityLabel("閉じる")
                Spacer()
                Menu {
                    Button {
                        withAnimation(.snappy) {
                            zoom = 1
                            lastZoom = 1
                            drag = .zero
                            lastDrag = .zero
                        }
                    } label: {
                        Label("表示を戻す", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        showLeadLines.toggle()
                    } label: {
                        Label(showLeadLines ? "鉛線を隠す" : "鉛線を表示", systemImage: "square.grid.3x3")
                    }

                    Button {
                        historyIndex = Double(project.sessions.count)
                    } label: {
                        Label("最新の状態", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 43, height: 43)
                        .background(.black.opacity(0.46), in: Circle())
                }
                .accessibilityLabel("表示メニュー")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .accessibilityHidden(true)
                Text(historyLabel(project))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Slider(
                    value: $historyIndex,
                    in: 0...Double(max(project.sessions.count, 1)),
                    step: 1
                )
                .tint(SunGlassStyle.lime)
                .accessibilityLabel("日付までの作品状態")
                .accessibilityValue("\(Int(playbackProgress(project) * 100))パーセント")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.58), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .foregroundStyle(SunGlassStyle.cream)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                drag = CGSize(
                    width: lastDrag.width + value.translation.width,
                    height: lastDrag.height + value.translation.height
                )
            }
            .onEnded { _ in lastDrag = drag }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(max(lastZoom * value.magnification, 0.7), 4) }
            .onEnded { _ in lastZoom = zoom }
    }

    private var highlight: Double {
        reduceMotion ? 0.3 : min(max(0.42 + tilt.roll * 0.45 - tilt.pitch * 0.25, 0), 1)
    }

    private func playbackProgress(_ project: GlassProject) -> Double {
        let count = min(max(Int(historyIndex.rounded()), 0), project.sessions.count)
        guard count > 0 else { return 0.03 }
        let ordered = project.sessions.sorted(by: { $0.startedAt < $1.startedAt })
        let points = ordered.prefix(count).reduce(0) { $0 + $1.earnedPoints }
        return min(max(points / project.requiredLightPoints, 0.03), project.progress)
    }

    /// Nil means the slider is at the live/latest position. Historical
    /// positions use the selected measurement's end time consistently across
    /// sessions, pieces, memories and contributor colours.
    private func historyCutoff(_ project: GlassProject) -> Date? {
        let count = min(max(Int(historyIndex.rounded()), 0), project.sessions.count)
        guard count < project.sessions.count else { return nil }
        guard count > 0 else { return project.startDate }
        return project.sessions
            .sorted(by: { $0.startedAt < $1.startedAt })[count - 1]
            .endedAt
    }

    private func historyLabel(_ project: GlassProject) -> String {
        let count = min(max(Int(historyIndex.rounded()), 0), project.sessions.count)
        guard count > 0 else { return "開始" }
        return project.sessions.sorted(by: { $0.startedAt < $1.startedAt })[count - 1].startedAt
            .formatted(.dateTime.year().month().day())
    }

}

struct ARExperienceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let projectID: UUID
    @StateObject private var arController = ARExperienceController()

    var body: some View {
        ZStack {
            if let project = store.project(id: projectID) {
                ARPlacementView(
                    themeColors: project.artworkPalette,
                    recordedFacets: project.recordedLightFacets,
                    artworkSeed: project.artworkSeed,
                    progress: project.progress,
                    controller: arController
                )
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.52), in: Circle())
                    }
                    .accessibilityLabel("閉じる")
                    Spacer()
                }
                .padding(16)

                statusCard

                Spacer()

                if arController.canCapture {
                    captureControls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                }
            }
            .foregroundStyle(SunGlassStyle.cream)
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $arController.shareSnapshot) { snapshot in
            ActivitySheet(items: [snapshot.image])
        }
        .alert(item: $arController.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, arController.status == .cameraPermissionDenied {
                arController.retrySession()
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch arController.status {
        case .preparing:
            ARStatusCard(icon: "camera.aperture", title: "準備中")
        case .unsupported:
            ARStatusCard(
                icon: "arkit",
                title: "AR非対応",
                message: "3D表示"
            )
        case .cameraPermissionDenied:
            ARStatusCard(
                icon: "camera.fill",
                title: "カメラ許可が必要",
                actionIcon: "gearshape.fill",
                actionLabel: "設定を開く"
            ) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
        case .searchingPlane:
            ARStatusCard(
                icon: "viewfinder",
                title: "平面を検索中",
                showsProgress: true
            )
        case .planeNotFound:
            ARStatusCard(
                icon: "rectangle.dashed",
                title: "平面なし",
                actionIcon: "viewfinder.circle",
                actionLabel: "目の前に仮配置"
            ) {
                arController.placeInFront()
            }
        case .interrupted:
            ARStatusCard(
                icon: "pause.circle.fill",
                title: "一時停止中"
            )
        case let .failed(message):
            ARStatusCard(
                icon: "exclamationmark.triangle.fill",
                title: "ARエラー",
                message: message,
                actionIcon: "arrow.clockwise",
                actionLabel: "もう一度試す"
            ) {
                arController.retrySession()
            }
        case .simulatorPreview:
            ARStatusCard(
                icon: "iphone.gen3",
                title: "プレビュー"
            )
        case .placed:
            EmptyView()
        }
    }

    private var captureControls: some View {
        HStack(spacing: 12) {
            Button {
                arController.addAnother()
            } label: {
                Image(systemName: "square.on.square")
                    .frame(width: 48, height: 44)
            }
            .accessibilityLabel("作品をもう1枚追加")
            .accessibilityHint("今の作品を残して、目の前に同じ作品を追加します")

            Button {
                arController.captureSnapshot()
            } label: {
                Image(systemName: "camera.fill")
                    .frame(width: 48, height: 44)
            }
            .accessibilityLabel("写真を撮る")
            .accessibilityHint("AR作品を撮影して共有します")

            Button {
                arController.toggleRecording()
            } label: {
                Image(systemName: arController.isRecording ? "stop.circle.fill" : "record.circle")
                    .frame(width: 48, height: 44)
            }
            .foregroundStyle(arController.isRecording ? Color.red : SunGlassStyle.cream)
            .accessibilityLabel(arController.isRecording ? "録画を停止" : "録画を開始")
            .accessibilityHint(arController.isRecording ? "録画を停止してプレビューを開きます" : "AR画面の録画を開始します")
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .padding(8)
        .background(.black.opacity(0.62), in: Capsule())
        .buttonStyle(.bordered)
        .tint(SunGlassStyle.cream.opacity(0.18))
        .overlay(alignment: .topTrailing) {
            if arController.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .offset(x: 4, y: -7)
                    .accessibilityHidden(true)
            }
        }
    }

}

private struct ARStatusCard: View {
    let icon: String
    let title: String
    let message: String
    let actionIcon: String?
    let actionLabel: String?
    let showsProgress: Bool
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String = "",
        actionIcon: String? = nil,
        actionLabel: String? = nil,
        showsProgress: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionIcon = actionIcon
        self.actionLabel = actionLabel
        self.showsProgress = showsProgress
        self.action = action
    }

    var body: some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView()
                    .tint(SunGlassStyle.lime)
                    .frame(width: 30)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SunGlassStyle.cream)
                    .frame(width: 30)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if let actionIcon, let actionLabel {
                Button { action?() } label: {
                    Image(systemName: actionIcon)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(SunGlassStyle.cream.opacity(0.2))
                    .accessibilityLabel(actionLabel)
            }
        }
        .padding(11)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
