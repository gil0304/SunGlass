import SwiftUI

struct ProjectDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    @State private var showMeasurement = false
    @State private var memoryDate: Date?
    @State private var showCalendar = false
    @State private var showViewer = false
    @State private var showAR = false
    @State private var showExport = false
    @State private var showCollaboration = false
    @State private var pendingProjectAction: ProjectAction?

    var body: some View {
        ZStack {
            SunGlassBackground()

            if let project = store.project(id: projectID) {
                ScrollView {
                    VStack(spacing: 22) {
                        artwork(project)
                        quickActions(project)
                        recentLight(project)
                        exportLink
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("作品が見つかりません", systemImage: "square.slash")
                    .foregroundStyle(SunGlassStyle.cream)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SunGlassWordmark(compact: true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let project = store.project(id: projectID) {
                    projectMenu(project)
                }
            }
        }
        .alert(item: $pendingProjectAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.confirmTitle)) {
                    perform(action)
                },
                secondaryButton: .cancel()
            )
        }
        .fullScreenCover(isPresented: $showMeasurement) {
            LightMeasurementView(projectID: projectID)
                .environment(store)
        }
        .sheet(item: $memoryDate) { date in
            MemoryEditorView(projectID: projectID, date: date)
                .environment(store)
        }
        .sheet(isPresented: $showCalendar) {
            ProjectCalendarView(projectID: projectID)
                .environment(store)
        }
        .fullScreenCover(isPresented: $showViewer) {
            ArtworkViewerView(projectID: projectID)
                .environment(store)
        }
        .fullScreenCover(isPresented: $showAR) {
            ARExperienceView(projectID: projectID)
                .environment(store)
        }
        .sheet(isPresented: $showExport) {
            ExportView(projectID: projectID)
                .environment(store)
        }
        .sheet(isPresented: $showCollaboration) {
            CollaborationView(projectID: projectID)
                .environment(store)
        }
    }

    private func projectMenu(_ project: GlassProject) -> some View {
        Menu {
            Button("光の記録", systemImage: "calendar") {
                showCalendar = true
            }
            if project.isCollaborative {
                Button("共同制作", systemImage: "person.2") {
                    showCollaboration = true
                }
            }

            Divider()

            if project.sessions.contains(where: { $0.location != nil }) {
                Button("記録した位置情報を削除", systemImage: "location.slash", role: .destructive) {
                    pendingProjectAction = .removeLocations
                }
            }
            if project.status != .archived {
                Button("作品をアーカイブ", systemImage: "archivebox") {
                    pendingProjectAction = .archive
                }
            }
            Button("作品を削除", systemImage: "trash", role: .destructive) {
                pendingProjectAction = .delete
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("作品のメニュー")
    }

    private func artwork(_ project: GlassProject) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            GlassArtworkView(
                themeID: project.theme.rawValue,
                seed: project.artworkSeed,
                progress: project.progress,
                palette: project.artworkPalette,
                leadLines: true,
                highlight: 0.32,
                recordedFacets: project.recordedLightFacets
            )
            .aspectRatio(0.94, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                Text(project.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream)
                    .lineLimit(2)
                Spacer()
                Image(systemName: statusIcon(project.status))
                    .foregroundStyle(SunGlassStyle.lime)
                    .accessibilityLabel(project.status.displayName)
                if project.isCollaborative {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.5))
                        .accessibilityLabel("共同制作")
                }
            }

            HStack(spacing: 10) {
                LightProgressBar(value: project.progress, height: 6)
                Text("\(project.progressPercentage)%")
                if project.status != .completed {
                    Text("\(project.remainingDays())日")
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(SunGlassStyle.cream.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title)、\(project.status.displayName)、\(project.status == .completed ? "着色率" : "完成度")\(project.progressPercentage)パーセント")
    }

    private func quickActions(_ project: GlassProject) -> some View {
        let canCollectLight = store.canCollectLight(projectID: project.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DetailAction(icon: "camera.aperture", title: "光を集める", isPrimary: true) {
                    guard store.canCollectLight(projectID: project.id) else { return }
                    showMeasurement = true
                }
                .disabled(!canCollectLight)
                .opacity(canCollectLight ? 1 : 0.38)
                .accessibilityHint(canCollectLight ? "" : lightCollectionUnavailableReason(project))

                DetailAction(icon: "quote.bubble", title: "一言を残す") {
                    memoryDate = Date()
                }
                DetailAction(icon: "viewfinder", title: "作品を鑑賞") {
                    showViewer = true
                }
                DetailAction(icon: "arkit", title: "ARで見る") {
                    showAR = true
                }
            }

        }
    }

    private func lightCollectionUnavailableReason(_ project: GlassProject) -> String {
        switch project.status {
        case .scheduled: "開始日になると光を集められます"
        case .completed: "制作期間が終了した作品です"
        case .archived: "アーカイブした作品では計測できません"
        case .active: "現在は制作期間外です"
        }
    }

    private func recentLight(_ project: GlassProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(SunGlassStyle.cream)
                    .accessibilityLabel("最近の記録")
                Spacer()
                Button { showCalendar = true } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(SunGlassStyle.lime)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("すべての記録")
            }

            Divider().overlay(SunGlassStyle.cream.opacity(0.1))

            if project.sessions.isEmpty {
                Image(systemName: "minus")
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.44))
                    .padding(.vertical, 10)
                    .accessibilityLabel("記録なし")
            } else {
                ForEach(Array(project.sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(3).enumerated()), id: \.element.id) { index, session in
                    HStack(spacing: 12) {
                        Image(systemName: session.timePeriod == .night ? "moon.stars" : "sun.max")
                            .foregroundStyle(SunGlassStyle.lime)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(session.timePeriod.displayName)・\(session.lightLevel.displayName)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(SunGlassStyle.cream)
                            HStack(spacing: 7) {
                                Text(session.startedAt.formatted(.dateTime.month().day().hour().minute()))
                                Text("\(Int(session.durationSeconds))秒")
                                if session.location != nil {
                                    Image(systemName: "location.fill")
                                        .accessibilityLabel("位置情報あり")
                                }
                            }
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(SunGlassStyle.cream.opacity(0.4))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)

                    if index < min(project.sessions.count, 3) - 1 {
                        Divider().overlay(SunGlassStyle.cream.opacity(0.07))
                    }
                }
            }
        }
    }

    private var exportLink: some View {
        Button { showExport = true } label: {
            HStack {
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(SunGlassStyle.lime)
                    .frame(width: 44, height: 44)
                Spacer()
            }
            .overlay(alignment: .top) {
                SunGlassStyle.cream.opacity(0.1)
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("作品を書き出す")
    }

    private func statusIcon(_ status: ProjectStatus) -> String {
        switch status {
        case .scheduled: "calendar"
        case .active: "sun.max"
        case .completed: "checkmark.seal.fill"
        case .archived: "archivebox"
        }
    }

    private func perform(_ action: ProjectAction) {
        switch action {
        case .removeLocations:
            _ = store.removeRecordedLocations(projectID: projectID)
        case .archive:
            store.archiveProject(id: projectID)
            if store.project(id: projectID)?.status == .archived { dismiss() }
        case .delete:
            store.deleteProject(id: projectID)
            if store.project(id: projectID) == nil { dismiss() }
        }
    }
}

private enum ProjectAction: String, Identifiable {
    case removeLocations
    case archive
    case delete

    var id: String { rawValue }
    var title: String {
        switch self {
        case .removeLocations: "位置情報を削除しますか？"
        case .archive: "作品をアーカイブしますか？"
        case .delete: "作品を削除しますか？"
        }
    }
    var message: String {
        switch self {
        case .removeLocations: "この作品の全セッションから座標だけを削除します。光や作品は残ります。"
        case .archive: "光の計測はできなくなります。作品の鑑賞と書き出しは続けられます。"
        case .delete: "作品、光の記録、写真、一言をこの端末から削除します。この操作は取り消せません。"
        }
    }
    var confirmTitle: String {
        switch self {
        case .removeLocations: "位置情報を削除"
        case .archive: "アーカイブ"
        case .delete: "作品を削除"
        }
    }
}

private struct DetailAction: View {
    let icon: String
    let title: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isPrimary ? SunGlassStyle.ink : SunGlassStyle.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isPrimary ? SunGlassStyle.lime : SunGlassStyle.cream.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
