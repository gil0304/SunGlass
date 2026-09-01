import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showNewProject = false
    @State private var showJoin = false
    @State private var showLightProjectPicker = false
    @State private var pendingLightPickerAction: LightPickerAction?
    @State private var measuringProjectID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header

                        if let message = store.lastErrorMessage {
                            errorMessage(message)
                        }

                        LightCaptureEntrance {
                            showLightProjectPicker = true
                        }

                        projectSection(title: "制作", symbol: "hammer", projects: store.activeProjects)

                        if !store.completedProjects.isEmpty {
                            projectSection(title: "完成", symbol: "checkmark", projects: store.completedProjects)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                ProjectDetailView(projectID: id)
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectView { draft in
                    let project = store.createProject(
                        title: draft.title,
                        theme: draft.theme,
                        duration: draft.duration,
                        startDate: draft.startDate,
                        customEndDate: draft.customEndDate,
                        baseColor: draft.baseColor,
                        note: draft.note,
                        isCollaborative: draft.isCollaborative,
                        usesPhotos: draft.usesPhotos,
                        recordsLocation: draft.recordsLocation
                    )
                    return store.project(id: project.id) != nil
                }
            }
            .sheet(isPresented: $showJoin, onDismiss: {
                store.pendingInviteCode = nil
            }) {
                JoinProjectView(initialCode: store.pendingInviteCode ?? "")
                    .id(store.pendingInviteCode)
                    .environment(store)
            }
            .sheet(isPresented: $showLightProjectPicker, onDismiss: finishLightPickerAction) {
                LightProjectPickerView(
                    projects: eligibleLightProjects,
                    onSelect: { projectID in
                        pendingLightPickerAction = .measure(projectID)
                        showLightProjectPicker = false
                    },
                    onCreate: {
                        pendingLightPickerAction = .create
                        showLightProjectPicker = false
                    },
                    onClose: {
                        showLightProjectPicker = false
                    }
                )
            }
            .fullScreenCover(item: $measuringProjectID) { id in
                LightMeasurementView(projectID: id)
                    .environment(store)
            }
            .onChange(of: store.pendingInviteCode) { _, code in
                if code != nil { showJoin = true }
            }
            .onAppear {
                if store.pendingInviteCode != nil { showJoin = true }
            }
        }
    }

    private var eligibleLightProjects: [GlassProject] {
        store.activeProjects.filter { store.canCollectLight(projectID: $0.id) }
    }

    private func finishLightPickerAction() {
        defer { pendingLightPickerAction = nil }
        switch pendingLightPickerAction {
        case let .measure(projectID):
            measuringProjectID = projectID
        case .create:
            showNewProject = true
        case nil:
            break
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SunGlassWordmark()
            Spacer()
            Button {
                showJoin = true
            } label: {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SunGlassStyle.cream)
                    .frame(width: 42, height: 42)
                    .background(SunGlassStyle.cream.opacity(0.06), in: Circle())
            }
            .accessibilityLabel("共同作品に参加")
            .accessibilityHint("招待コードを入力します")

            Button {
                showNewProject = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SunGlassStyle.ink)
                    .frame(width: 42, height: 42)
                    .background(SunGlassStyle.lime, in: Circle())
            }
            .accessibilityLabel("新しい作品を作る")
        }
    }

    private func errorMessage(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SunGlassStyle.coral)
            Text(message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { store.clearLastError() } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.5))
            }
            .accessibilityLabel("保存メッセージを閉じる")
        }
    }

    @ViewBuilder
    private func projectSection(title: String, symbol: String, projects: [GlassProject]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream)
                .accessibilityLabel(title)

            if projects.isEmpty {
                EmptyGalleryRow { showNewProject = true }
            } else {
                VStack(spacing: 0) {
                    ForEach(projects) { project in
                        NavigationLink(value: project.id) {
                            ProjectRow(project: project)
                        }
                        .buttonStyle(.plain)

                        if project.id != projects.last?.id {
                            Divider()
                                .overlay(SunGlassStyle.cream.opacity(0.09))
                        }
                    }
                }
            }
        }
    }

}

private enum LightPickerAction {
    case measure(UUID)
    case create
}

private struct LightCaptureEntrance: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SunGlassStyle.cream, SunGlassStyle.amber, SunGlassStyle.coral],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: SunGlassStyle.amber.opacity(0.42), radius: 24)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(SunGlassStyle.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(
                LinearGradient(
                    colors: [SunGlassStyle.amber.opacity(0.15), SunGlassStyle.coral.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("光を焼き付ける")
        .accessibilityHint("光を集める作品を選びます")
    }
}

private struct LightProjectPickerView: View {
    let projects: [GlassProject]
    let onSelect: (UUID) -> Void
    let onCreate: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()

                if projects.isEmpty {
                    Button(action: onCreate) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(SunGlassStyle.ink)
                    }
                    .buttonStyle(SunGlassPrimaryButtonStyle())
                    .padding(22)
                    .accessibilityLabel("新しい作品を作る")
                    .accessibilityHint("光を集める作品を作成します")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(projects) { project in
                                Button {
                                    onSelect(project.id)
                                } label: {
                                    LightProjectChoice(project: project)
                                }
                                .buttonStyle(.plain)

                                if project.id != projects.last?.id {
                                    Divider()
                                        .overlay(SunGlassStyle.cream.opacity(0.09))
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(systemName: "camera.aperture")
                        .foregroundStyle(SunGlassStyle.lime)
                        .accessibilityLabel("光を焼き付ける作品を選ぶ")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(SunGlassStyle.lime)
                    }
                    .accessibilityLabel("閉じる")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}

private struct LightProjectChoice: View {
    let project: GlassProject

    var body: some View {
        HStack(spacing: 14) {
            GlassArtworkView(
                themeID: project.theme.rawValue,
                seed: project.artworkSeed,
                progress: project.progress,
                palette: project.artworkPalette,
                leadLines: true,
                highlight: 0,
                recordedFacets: project.recordedLightFacets
            )
            .frame(width: 72, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(project.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream)
                    .lineLimit(2)

                HStack(spacing: 9) {
                    LightProgressBar(value: project.progress, height: 5)
                    Text("\(project.progressPercentage)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.64))
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(project.title)、完成度\(project.progressPercentage)パーセント")
        .accessibilityHint("この作品に光を焼き付けます")
    }
}

struct ProjectRow: View {
    let project: GlassProject

    var body: some View {
        HStack(spacing: 14) {
            GlassArtworkView(
                themeID: project.theme.rawValue,
                seed: project.artworkSeed,
                progress: project.progress,
                palette: project.artworkPalette,
                leadLines: true,
                highlight: 0,
                recordedFacets: project.recordedLightFacets
            )
            .frame(width: 84, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: statusIcon)
                        .font(.caption)
                        .foregroundStyle(project.status == .completed ? SunGlassStyle.lime : SunGlassStyle.cream.opacity(0.5))
                        .accessibilityLabel(statusLabel)
                    Text(project.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream)
                        .lineLimit(2)
                    if project.isCollaborative {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(SunGlassStyle.cream.opacity(0.5))
                    }
                }

                if project.status != .completed {
                    Text("\(project.remainingDays())日")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.42))
                }

                HStack(spacing: 9) {
                    LightProgressBar(value: project.progress, height: 5)
                    Text("\(project.progressPercentage)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.65))
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(SunGlassStyle.cream.opacity(0.28))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(project.title)、\(statusLabel)、\(project.theme.displayName)、\(project.status == .completed ? "着色率" : "完成度")\(project.progressPercentage)パーセント")
    }

    private var statusIcon: String {
        switch project.status {
        case .scheduled: "calendar"
        case .active: project.hasCollectedLightToday ? "checkmark.circle.fill" : "sun.max"
        case .completed: "checkmark.seal.fill"
        case .archived: "archivebox"
        }
    }

    private var statusLabel: String {
        switch project.status {
        case .scheduled: "開始前"
        case .active: project.hasCollectedLightToday ? "今日計測済み" : "今日未計測"
        case .completed: "完成"
        case .archived: "アーカイブ"
        }
    }
}

private struct EmptyGalleryRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle")
                .font(.system(size: 24))
                .foregroundStyle(SunGlassStyle.lime)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("最初の作品を作る")
    }
}

private struct JoinProjectView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var name = ""
    @State private var error: String?

    init(initialCode: String = "") {
        _code = State(initialValue: String(initialCode.uppercased().prefix(6)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()

                VStack(alignment: .leading, spacing: 18) {
                    Text("参加")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream)

                    TextField("ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 25, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }

                    TextField("表示名（任意）", text: $name)
                        .font(.system(size: 14, design: .rounded))
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(SunGlassStyle.coral)
                    }

                    Button {
                        if store.joinProject(inviteCode: code, displayName: name) != nil {
                            dismiss()
                        } else {
                            error = store.lastErrorMessage ?? "参加できませんでした。"
                        }
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .buttonStyle(SunGlassPrimaryButtonStyle())
                    .disabled(code.count != 6)
                    .opacity(code.count == 6 ? 1 : 0.42)
                    .accessibilityLabel("共同作品に参加")
                    .accessibilityHint("入力した招待コードで参加します")

                    Spacer()
                }
                .padding(22)
                .padding(.top, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(SunGlassStyle.lime)
                    }
                    .accessibilityLabel("閉じる")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
