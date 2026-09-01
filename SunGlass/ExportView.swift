import SwiftUI
import UIKit

private enum ExportKind: String, CaseIterable, Identifiable {
    case image = "画像"
    case video = "動画"

    var id: Self { self }
}

private enum VideoExportMode: String, CaseIterable, Identifiable {
    case creationTimelapse
    case lightTransmission
    case dailyRecord

    var id: Self { self }

    var title: String {
        switch self {
        case .creationTimelapse: "制作"
        case .lightTransmission: "透過"
        case .dailyRecord: "日別"
        }
    }

}

private enum StillImageMode: String, CaseIterable, Identifiable {
    case poster
    case wallpaper

    var id: Self { self }
    var title: String { self == .poster ? "ポスター" : "壁紙" }
}

private enum WallpaperPreset: String, CaseIterable, Identifiable {
    case lockScreen
    case homeScreen
    case depthLayers

    var id: Self { self }

    var title: String {
        switch self {
        case .lockScreen: "ロック"
        case .homeScreen: "ホーム"
        case .depthLayers: "奥行き"
        }
    }

    /// A device-independent 9:19.5 master suitable for modern iPhone cropping.
    var renderSize: CGSize { CGSize(width: 1290, height: 2795) }
}

private enum WallpaperLayer: Equatable {
    case composite
    case background
    case foreground
}

private struct VideoFrameConfiguration {
    var project: GlassProject
    var progress: Double
    var highlight: Double
    var includesWords: Bool
    var memoryPhotoPath: String? = nil
}

struct ExportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    @State private var format: PosterFormat = .story
    @State private var includesFrame = true
    @State private var includesPeriod = true
    @State private var includesWords = false
    @State private var transparentBackground = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var isRenderingVideo = false
    @State private var error: String?
    @State private var exportTask: Task<Void, Never>?
    @State private var videoMode: VideoExportMode = .creationTimelapse
    @State private var stillImageMode: StillImageMode = .poster
    @State private var wallpaperPreset: WallpaperPreset = .lockScreen
    @State private var exportKind: ExportKind = .image
    @State private var showAdvancedOptions = false

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()
                if let project = store.project(id: projectID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("書き出し形式", selection: $exportKind) {
                                ForEach(ExportKind.allCases) { kind in
                                    Text(kind.rawValue).tag(kind)
                                }
                            }
                            .pickerStyle(.segmented)

                            preview(project)
                            if exportKind == .image {
                                formatPicker
                            } else {
                                videoModePicker
                            }
                            options(project)
                            exportButtons(project)
                        }
                        .padding(20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("書き出し")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                        .foregroundStyle(SunGlassStyle.lime)
                        .accessibilityLabel("閉じる")
                }
            }
            .sheet(isPresented: $showShare) {
                ActivitySheet(items: shareItems)
                    .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
            isRenderingVideo = false
        }
    }

    private func preview(_ project: GlassProject) -> some View {
        Group {
            if stillImageMode == .poster {
                ArtworkPosterView(
                    project: project,
                    artworkProgress: project.progress,
                    includesFrame: includesFrame,
                    includesPeriod: includesPeriod,
                    includesWords: includesWords,
                    transparentBackground: transparentBackground
                )
                .aspectRatio(format.renderSize.width / format.renderSize.height, contentMode: .fit)
            } else {
                WallpaperArtworkView(
                    project: project,
                    preset: wallpaperPreset,
                    layer: .composite,
                    includesFrame: includesFrame,
                    includesPeriod: includesPeriod,
                    includesWords: includesWords
                )
                .aspectRatio(
                    wallpaperPreset.renderSize.width / wallpaperPreset.renderSize.height,
                    contentMode: .fit
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 440)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .animation(.snappy, value: format)
        .animation(.snappy, value: stillImageMode)
        .animation(.snappy, value: wallpaperPreset)
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("画像タイプ", selection: $stillImageMode) {
                ForEach(StillImageMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if stillImageMode == .poster {
                HStack {
                    Image(systemName: "aspectratio")
                        .accessibilityHidden(true)
                    Spacer()
                    Picker("サイズ", selection: $format) {
                        ForEach(PosterFormat.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else {
                HStack {
                    Image(systemName: "iphone")
                        .accessibilityHidden(true)
                    Spacer()
                    Picker("壁紙", selection: $wallpaperPreset) {
                        ForEach(WallpaperPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(SunGlassStyle.cream)
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.snappy, value: stillImageMode)
        .animation(.snappy, value: wallpaperPreset)
    }

    private func options(_ project: GlassProject) -> some View {
        DisclosureGroup(isExpanded: $showAdvancedOptions) {
            VStack(spacing: 0) {
                exportToggle("枠", icon: "window.casement", isOn: $includesFrame)
                Divider().overlay(.white.opacity(0.09))
                exportToggle("期間", icon: "calendar", isOn: $includesPeriod)
                Divider().overlay(.white.opacity(0.09))
                exportToggle("一言", icon: "quote.bubble", isOn: $includesWords)
                    .disabled(project.note == nil && project.memories.allSatisfy(\.comment.isEmpty))
                Divider().overlay(.white.opacity(0.09))
                if exportKind == .image {
                    exportToggle("透過", icon: "square.dashed", isOn: $transparentBackground)
                        .disabled(stillImageMode == .wallpaper)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel("詳細設定")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(SunGlassStyle.cream.opacity(0.74))
        .padding(13)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func exportButtons(_ project: GlassProject) -> some View {
        VStack(spacing: 8) {
            if exportKind == .image {
                Button {
                    renderImage(project)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 19, weight: .bold))
                        .frame(height: 30)
                }
                .buttonStyle(SunGlassPrimaryButtonStyle())
                .accessibilityLabel("画像を書き出す")
            } else {
                Button {
                    renderTimelapse(project)
                } label: {
                    Group {
                        if isRenderingVideo {
                            ProgressView()
                                .tint(SunGlassStyle.ink)
                        } else {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 19, weight: .bold))
                        }
                    }
                    .frame(height: 30)
                }
                .buttonStyle(SunGlassPrimaryButtonStyle())
                .disabled(isRenderingVideo)
                .accessibilityLabel(isRenderingVideo ? "動画を作成中" : "10秒の動画を書き出す")
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(SunGlassStyle.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var videoModePicker: some View {
        HStack {
            Image(systemName: "film.stack")
                .accessibilityHidden(true)
            Spacer()
            Picker("動画モード", selection: $videoMode) {
                ForEach(VideoExportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(SunGlassStyle.cream)
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(isRenderingVideo)
    }

    private func exportToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream.opacity(0.78))
        }
        .tint(SunGlassStyle.lime)
        .padding(.vertical, 13)
    }

    private func renderImage(_ project: GlassProject) {
        error = nil

        if stillImageMode == .wallpaper {
            renderWallpaper(project)
            return
        }

        let poster = ArtworkPosterView(
            project: project,
            artworkProgress: project.progress,
            includesFrame: includesFrame,
            includesPeriod: includesPeriod,
            includesWords: includesWords,
            transparentBackground: transparentBackground
        )
        guard let image = ImageExportService.render(
            poster,
            size: format.renderSize,
            isOpaque: !transparentBackground
        ) else {
            error = "画像を生成できませんでした。"
            return
        }
        shareItems = [image]
        showShare = true
    }

    private func renderWallpaper(_ project: GlassProject) {
        let size = wallpaperPreset.renderSize

        do {
            if wallpaperPreset == .depthLayers {
                let backgroundView = WallpaperArtworkView(
                    project: project,
                    preset: wallpaperPreset,
                    layer: .background,
                    includesFrame: includesFrame,
                    includesPeriod: includesPeriod,
                    includesWords: includesWords
                )
                let foregroundView = WallpaperArtworkView(
                    project: project,
                    preset: wallpaperPreset,
                    layer: .foreground,
                    includesFrame: includesFrame,
                    includesPeriod: includesPeriod,
                    includesWords: includesWords
                )
                let compositeView = WallpaperArtworkView(
                    project: project,
                    preset: wallpaperPreset,
                    layer: .composite,
                    includesFrame: includesFrame,
                    includesPeriod: includesPeriod,
                    includesWords: includesWords
                )

                guard let background = ImageExportService.render(backgroundView, size: size),
                      let foreground = ImageExportService.render(foregroundView, size: size, isOpaque: false),
                      let composite = ImageExportService.render(compositeView, size: size) else {
                    error = "奥行き壁紙のレイヤーを生成できませんでした。"
                    return
                }

                shareItems = try ImageExportService.temporaryPNGs([
                    ("SUN-GLASS-DEPTH-BACKGROUND.png", background),
                    ("SUN-GLASS-DEPTH-FOREGROUND.png", foreground),
                    ("SUN-GLASS-DEPTH-COMPOSITE.png", composite)
                ])
            } else {
                let wallpaper = WallpaperArtworkView(
                    project: project,
                    preset: wallpaperPreset,
                    layer: .composite,
                    includesFrame: includesFrame,
                    includesPeriod: includesPeriod,
                    includesWords: includesWords
                )
                guard let image = ImageExportService.render(wallpaper, size: size) else {
                    error = "壁紙を生成できませんでした。"
                    return
                }
                let fileName = wallpaperPreset == .lockScreen
                    ? "SUN-GLASS-LOCK-SCREEN.png"
                    : "SUN-GLASS-HOME-SCREEN.png"
                shareItems = try ImageExportService.temporaryPNGs([(fileName, image)])
            }
            showShare = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func renderTimelapse(_ project: GlassProject) {
        guard exportTask == nil else { return }

        error = nil
        isRenderingVideo = true
        let projectSnapshot = project
        let frameSnapshot = includesFrame
        let periodSnapshot = includesPeriod
        let wordsSnapshot = includesWords
        let modeSnapshot = videoMode

        exportTask = Task { @MainActor in
            defer {
                isRenderingVideo = false
                exportTask = nil
            }

            do {
                let size = CGSize(width: 720, height: 1280)
                var cachedPhoto: (path: String, image: UIImage)?
                let url = try await TimelapseExportService.makeVideo(size: size) { fraction in
                    let frame = videoFrame(
                        mode: modeSnapshot,
                        fraction: fraction,
                        project: projectSnapshot,
                        includesWords: wordsSnapshot
                    )
                    let memoryPhoto: UIImage?
                    if let path = frame.memoryPhotoPath {
                        if cachedPhoto?.path == path {
                            memoryPhoto = cachedPhoto?.image
                        } else {
                            memoryPhoto = PhotoMemoryService.load(path: path)
                            cachedPhoto = memoryPhoto.map { (path, $0) }
                        }
                    } else {
                        cachedPhoto = nil
                        memoryPhoto = nil
                    }
                    let view = ArtworkPosterView(
                        project: frame.project,
                        artworkProgress: frame.progress,
                        includesFrame: frameSnapshot,
                        includesPeriod: periodSnapshot,
                        includesWords: frame.includesWords,
                        transparentBackground: false,
                        highlight: frame.highlight,
                        memoryPhoto: memoryPhoto
                    )
                    return ImageExportService.render(view, size: size)
                }
                try Task.checkCancellation()
                shareItems = [url]
                showShare = true
            } catch is CancellationError {
                // Dismissing the exporter intentionally cancels the in-flight render.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private func videoFrame(
    mode: VideoExportMode,
    fraction: Double,
    project: GlassProject,
    includesWords: Bool
) -> VideoFrameConfiguration {
    let fraction = min(max(fraction, 0), 1)

    switch mode {
    case .creationTimelapse:
        return VideoFrameConfiguration(
            project: project,
            progress: project.progress * fraction,
            highlight: 0.24 + fraction * 0.46,
            includesWords: includesWords
        )

    case .lightTransmission:
        // Keep the glass fully formed while a deliberate pulse strengthens and
        // softens the renderer's moving light sweep.
        let lightWave = 0.5 - cos(fraction * .pi * 2) * 0.5
        return VideoFrameConfiguration(
            project: project,
            progress: project.progress,
            highlight: 0.12 + lightWave * 0.88,
            includesWords: includesWords
        )

    case .dailyRecord:
        return dailyVideoFrame(fraction: fraction, project: project, includesWords: includesWords)
    }
}

private func dailyVideoFrame(
    fraction: Double,
    project: GlassProject,
    includesWords: Bool
) -> VideoFrameConfiguration {
    let calendar = Calendar.autoupdatingCurrent
    let recordedDays = Set(
        project.sessions.map { calendar.startOfDay(for: $0.startedAt) }
            + project.memories.map { calendar.startOfDay(for: $0.recordDate) }
    ).sorted()

    guard !recordedDays.isEmpty else {
        return VideoFrameConfiguration(
            project: project,
            progress: project.progress * fraction,
            highlight: 0.36 + fraction * 0.30,
            includesWords: includesWords
        )
    }

    let completedDayCount = fraction == 0
        ? 0
        : min(recordedDays.count, Int(ceil(fraction * Double(recordedDays.count))))
    var frameProject = project

    guard completedDayCount > 0 else {
        frameProject.sessions = []
        frameProject.memories = []
        frameProject.pieces = []
        frameProject.currentLightPoints = 0
        frameProject.note = nil
        return VideoFrameConfiguration(
            project: frameProject,
            progress: 0,
            highlight: 0.30,
            includesWords: false
        )
    }

    let selectedDay = recordedDays[completedDayCount - 1]
    let cutoff = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
    frameProject.sessions = project.sessions.filter { $0.startedAt < cutoff }
    frameProject.memories = project.memories.filter { $0.recordDate < cutoff }

    let allEarnedPoints = project.sessions.reduce(0) { $0 + $1.earnedPoints }
    let earnedPointsThroughDay = frameProject.sessions.reduce(0) { $0 + $1.earnedPoints }
    let chronologicalFraction: Double
    if allEarnedPoints > 0 {
        chronologicalFraction = min(1, earnedPointsThroughDay / allEarnedPoints)
    } else {
        chronologicalFraction = Double(completedDayCount) / Double(recordedDays.count)
    }
    let progress = project.progress * chronologicalFraction
    frameProject.currentLightPoints = frameProject.requiredLightPoints * progress
    frameProject.pieces = project.pieces.filter { $0.revealProgress <= progress + 0.000_001 }

    let selectedDayMemories = project.memories
        .filter { calendar.isDate($0.recordDate, inSameDayAs: selectedDay) }
        .sorted { $0.updatedAt > $1.updatedAt }
    let latestWords = selectedDayMemories
        .map(\.comment)
        .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let memoryPhotoPath = selectedDayMemories
        .compactMap(\.photoPath)
        .first { !$0.isEmpty }
    frameProject.note = latestWords

    return VideoFrameConfiguration(
        project: frameProject,
        progress: progress,
        highlight: 0.38 + chronologicalFraction * 0.32,
        includesWords: latestWords != nil || (includesWords && frameProject.note != nil),
        memoryPhotoPath: memoryPhotoPath
    )
}

struct ArtworkPosterView: View {
    let project: GlassProject
    let artworkProgress: Double
    let includesFrame: Bool
    let includesPeriod: Bool
    let includesWords: Bool
    let transparentBackground: Bool
    let highlight: Double
    let memoryPhoto: UIImage?

    init(
        project: GlassProject,
        artworkProgress: Double,
        includesFrame: Bool,
        includesPeriod: Bool,
        includesWords: Bool,
        transparentBackground: Bool,
        highlight: Double = 0.6,
        memoryPhoto: UIImage? = nil
    ) {
        self.project = project
        self.artworkProgress = artworkProgress
        self.includesFrame = includesFrame
        self.includesPeriod = includesPeriod
        self.includesWords = includesWords
        self.transparentBackground = transparentBackground
        self.highlight = highlight
        self.memoryPhoto = memoryPhoto
    }

    var body: some View {
        GeometryReader { proxy in
            let minimum = min(proxy.size.width, proxy.size.height)
            let margin = minimum * 0.075
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                if !transparentBackground {
                    LinearGradient(
                        colors: [SunGlassStyle.ink, Color(red: 0.05, green: 0.17, blue: 0.13)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                if let memoryPhoto {
                    Image(uiImage: memoryPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0.62)
                        .blur(radius: max(14, minimum * 0.028))
                        .opacity(0.34)

                    LinearGradient(
                        colors: [
                            SunGlassStyle.ink.opacity(0.52),
                            SunGlassStyle.ink.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                if isLandscape {
                    HStack(spacing: margin * 0.65) {
                        artwork(minimum: minimum)
                            .frame(width: proxy.size.width * 0.58)
                        metadata(minimum: minimum, showsPeriod: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(margin)
                } else {
                    VStack(spacing: margin * 0.55) {
                        metadata(minimum: minimum, showsPeriod: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        artwork(minimum: minimum)
                        footer(minimum: minimum)
                    }
                    .padding(margin)
                }
            }
        }
    }

    private func artwork(minimum: CGFloat) -> some View {
        GlassArtworkView(
            themeID: project.theme.rawValue,
            seed: project.artworkSeed,
            progress: artworkProgress,
            palette: artworkPalette,
            leadLines: true,
            highlight: highlight,
            recordedFacets: project.recordedLightFacets
        )
        .aspectRatio(0.82, contentMode: .fit)
        .padding(includesFrame ? minimum * 0.035 : 0)
        .background(includesFrame ? Color(red: 0.055, green: 0.045, blue: 0.038) : .clear)
        .overlay {
            if includesFrame {
                Rectangle()
                    .stroke(Color(red: 0.32, green: 0.25, blue: 0.16), lineWidth: minimum * 0.012)
            }
        }
        .shadow(color: .black.opacity(includesFrame ? 0.45 : 0), radius: minimum * 0.04)
    }

    private func metadata(minimum: CGFloat, showsPeriod: Bool) -> some View {
        VStack(alignment: .leading, spacing: minimum * 0.018) {
            Text(project.title)
                .font(.system(size: minimum * 0.075, weight: .semibold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream)
                .lineLimit(2)
                .minimumScaleFactor(0.65)

            if includesPeriod && showsPeriod {
                Label {
                    Text("\(project.startDate.formatted(.dateTime.year().month().day())) — \(project.endDate.formatted(.dateTime.year().month().day()))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.system(size: minimum * 0.019, weight: .bold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream.opacity(0.45))
                .padding(.top, minimum * 0.006)
            }

            if includesWords, let words {
                Text("“\(words)”")
                    .font(.system(size: minimum * 0.031, weight: .medium, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.78))
                    .lineLimit(3)
                    .padding(.top, minimum * 0.018)
            }
        }
    }

    private func footer(minimum: CGFloat) -> some View {
        HStack {
            if includesPeriod {
                Text("\(project.startDate.formatted(.dateTime.year().month().day())) — \(project.endDate.formatted(.dateTime.year().month().day()))")
            }
            Spacer()
        }
        .font(.system(size: minimum * 0.018, weight: .bold, design: .rounded))
        .tracking(minimum * 0.0015)
        .foregroundStyle(SunGlassStyle.cream.opacity(0.45))
    }

    private var artworkPalette: [Color] {
        project.artworkPalette
    }

    private var words: String? {
        if let note = project.note, !note.isEmpty { return note }
        return project.memories.sorted(by: { $0.recordDate > $1.recordDate }).first(where: { !$0.comment.isEmpty })?.comment
    }
}

private struct WallpaperArtworkView: View {
    let project: GlassProject
    let preset: WallpaperPreset
    let layer: WallpaperLayer
    let includesFrame: Bool
    let includesPeriod: Bool
    let includesWords: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if layer != .foreground {
                    wallpaperBackground(size: proxy.size)
                }

                if layer != .background {
                    wallpaperForeground(size: proxy.size)
                }

                if layer == .composite, preset == .homeScreen {
                    LinearGradient(
                        colors: [
                            SunGlassStyle.ink.opacity(0.24),
                            .clear,
                            SunGlassStyle.ink.opacity(0.34)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func wallpaperBackground(size: CGSize) -> some View {
        let palette = project.artworkPalette
        let primary = palette.first ?? SunGlassStyle.cyan
        let secondary = palette.dropFirst().first ?? SunGlassStyle.violet

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.07, blue: 0.055),
                    Color(red: 0.035, green: 0.13, blue: 0.105),
                    SunGlassStyle.ink
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [primary.opacity(0.42), .clear],
                center: UnitPoint(x: 0.18, y: 0.32),
                startRadius: 0,
                endRadius: size.width * 0.92
            )

            RadialGradient(
                colors: [secondary.opacity(0.26), .clear],
                center: UnitPoint(x: 0.86, y: 0.72),
                startRadius: 0,
                endRadius: size.width * 0.78
            )

            GlassArtworkView(
                themeID: project.theme.rawValue,
                seed: project.artworkSeed &+ 71,
                progress: project.progress,
                palette: palette,
                leadLines: false,
                highlight: 0.16,
                recordedFacets: project.recordedLightFacets
            )
            .scaleEffect(1.85)
            .blur(radius: size.width * 0.075)
            .opacity(preset == .homeScreen ? 0.11 : 0.17)

            Color.black.opacity(preset == .homeScreen ? 0.20 : 0.08)
        }
    }

    @ViewBuilder
    private func wallpaperForeground(size: CGSize) -> some View {
        let width = size.width
        let height = size.height

        switch preset {
        case .lockScreen:
            VStack(spacing: height * 0.018) {
                Color.clear.frame(height: height * 0.27)
                glassArtwork(minimum: width)
                    .frame(width: width * 0.78)
                wallpaperMetadata(size: size, alignment: .center)
                Spacer(minLength: height * 0.035)
            }
            .padding(.horizontal, width * 0.09)

        case .homeScreen:
            VStack(spacing: height * 0.025) {
                Spacer(minLength: height * 0.11)
                glassArtwork(minimum: width)
                    .frame(width: width * 0.86)
                    .opacity(0.78)
                Spacer(minLength: height * 0.08)
                wallpaperMetadata(size: size, alignment: .center)
                Spacer(minLength: height * 0.035)
            }
            .padding(.horizontal, width * 0.07)

        case .depthLayers:
            VStack(spacing: height * 0.022) {
                Color.clear.frame(height: height * 0.20)
                glassArtwork(minimum: width)
                    .frame(width: width * 0.91)
                wallpaperMetadata(size: size, alignment: .center)
                Spacer(minLength: height * 0.045)
            }
            .padding(.horizontal, width * 0.045)
        }
    }

    private func glassArtwork(minimum: CGFloat) -> some View {
        GlassArtworkView(
            themeID: project.theme.rawValue,
            seed: project.artworkSeed,
            progress: project.progress,
            palette: project.artworkPalette,
            leadLines: true,
            highlight: preset == .homeScreen ? 0.36 : 0.68,
            recordedFacets: project.recordedLightFacets
        )
        .aspectRatio(0.82, contentMode: .fit)
        .padding(includesFrame ? minimum * 0.026 : 0)
        .background(includesFrame ? Color(red: 0.045, green: 0.035, blue: 0.028) : .clear)
        .overlay {
            if includesFrame {
                Rectangle()
                    .stroke(Color(red: 0.34, green: 0.26, blue: 0.16), lineWidth: minimum * 0.009)
            }
        }
        .shadow(color: .black.opacity(includesFrame ? 0.52 : 0.28), radius: minimum * 0.035, y: minimum * 0.018)
    }

    private func wallpaperMetadata(size: CGSize, alignment: TextAlignment) -> some View {
        VStack(spacing: size.width * 0.016) {
            Text(project.title)
                .font(.system(size: size.width * 0.051, weight: .semibold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            if includesPeriod {
                Text("\(project.startDate.formatted(.dateTime.year().month().day())) — \(project.endDate.formatted(.dateTime.year().month().day()))")
                    .font(.system(size: size.width * 0.019, weight: .bold, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.48))
            }

            if includesWords, let words {
                Text("“\(words)”")
                    .font(.system(size: size.width * 0.026, weight: .medium, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.72))
                    .lineLimit(2)
                    .padding(.top, size.width * 0.006)
            }
        }
        .multilineTextAlignment(alignment)
        .frame(maxWidth: .infinity)
    }

    private var words: String? {
        if let note = project.note, !note.isEmpty { return note }
        return project.memories
            .sorted(by: { $0.recordDate > $1.recordDate })
            .first(where: { !$0.comment.isEmpty })?
            .comment
    }
}
