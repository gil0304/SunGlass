import SwiftUI

struct NewProjectDraft {
    var title = ""
    var theme: Theme = .ocean
    var duration: DurationPreset = .sevenDays
    var startDate = Date()
    var customEndDate = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
    var baseColor: String? = nil
    var note = ""
    var usesPhotos = false
    var recordsLocation = false
    var isCollaborative = false

    var endDate: Date {
        duration.endDate(from: startDate, customEndDate: customEndDate)
    }
}

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NewProjectDraft()
    @State private var step = 0
    @State private var creationError: String?

    let onCreate: (NewProjectDraft) -> Bool

    private let baseColors: [(String?, Color, String)] = [
        (nil, .white.opacity(0.55), "光に任せる"),
        ("#25BFC8", SunGlassStyle.cyan, "水色"),
        ("#E6FF61", SunGlassStyle.lime, "若草"),
        ("#FF624B", SunGlassStyle.coral, "夕焼け"),
        ("#8067DB", SunGlassStyle.violet, "薄紫"),
        ("#FFC52F", Color(red: 1, green: 0.76, blue: 0.18), "ひまわり")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()

                VStack(spacing: 0) {
                    header

                    currentStep
                        .id(step)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .animation(.snappy, value: step)

                    footer
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(step > 0)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 0: basicsStep
        case 1: themeStep
        case 2: durationStep
        default: previewStep
        }
    }

    private var header: some View {
        HStack {
            Button {
                if step == 0 { dismiss() } else { withAnimation { step -= 1 } }
            } label: {
                Image(systemName: step == 0 ? "xmark" : "arrow.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SunGlassStyle.cream)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(step == 0 ? "閉じる" : "前へ")
            Spacer()
            Image(systemName: stepSymbols[step])
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SunGlassStyle.lime)
                .accessibilityHidden(true)
            Spacer()
            Text("\(step + 1) / 4")
                .font(SunGlassStyle.label(10))
                .foregroundStyle(SunGlassStyle.cream.opacity(0.5))
                .monospacedDigit()
                .frame(width: 40)
                .accessibilityLabel("作成ステップ \(step + 1) / 4")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private var basicsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("作品名", required: true)
                    TextField("例：八月の海", text: $draft.title)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream)
                        .padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .textInputAutocapitalization(.never)
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("最初の一言", required: false)
                    TextField("この夏に残したいこと", text: $draft.note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream)
                        .padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                }

                toggleRow(
                    title: "共同制作",
                    isOn: $draft.isCollaborative
                )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var themeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Theme.allCases) { theme in
                        Button {
                            withAnimation(.snappy) { draft.theme = theme }
                        } label: {
                            ThemeChoiceCard(theme: theme, selected: draft.theme == theme)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private var durationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("期間", required: true)
                    FlowLayout(spacing: 8) {
                        ForEach(DurationPreset.allCases) { preset in
                            Button {
                                draft.duration = preset
                            } label: {
                                HStack(spacing: 5) {
                                    Text(preset.displayName)
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(draft.duration == preset ? SunGlassStyle.ink : SunGlassStyle.cream.opacity(0.72))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .background(
                                    draft.duration == preset ? SunGlassStyle.lime : .white.opacity(0.07),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 10) {
                    dateRow(title: "開始日", date: $draft.startDate)
                    if draft.duration == .custom {
                        dateRow(title: "完成予定日", date: $draft.customEndDate)
                    } else {
                        HStack {
                            Text("完成予定日")
                            Spacer()
                            Text(draft.endDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(SunGlassStyle.lime)
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.65))
                        .padding(16)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("基調色", required: false)
                    HStack(spacing: 11) {
                        ForEach(Array(baseColors.enumerated()), id: \.offset) { _, option in
                            Button {
                                draft.baseColor = option.0
                            } label: {
                                Circle()
                                    .fill(option.1)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle().stroke(SunGlassStyle.cream, lineWidth: draft.baseColor == option.0 ? 3 : 0)
                                    }
                                    .overlay {
                                        if option.0 == nil {
                                            Image(systemName: "wand.and.stars")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(SunGlassStyle.ink)
                                        }
                                    }
                            }
                            .accessibilityLabel(option.2)
                        }
                    }
                }

                toggleRow(
                    title: "写真を残す",
                    isOn: $draft.usesPhotos
                )

                toggleRow(
                    title: "場所を記録",
                    caption: "約100m・端末内",
                    isOn: $draft.recordsLocation
                )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private var previewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GlassArtworkView(
                    themeID: draft.theme.rawValue,
                    seed: draft.title.unicodeScalars.reduce(29) { $0 &* 31 &+ Int($1.value) },
                    progress: 0.06,
                    palette: previewPalette,
                    leadLines: true,
                    highlight: 0.38
                )
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.title.isEmpty ? "名前のない夏" : draft.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream)
                    Text("\(draft.theme.displayName) ・ \(dateRange)\(draft.isCollaborative ? " ・ 共同制作" : "")")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.55))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let creationError {
                Label(creationError, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(SunGlassStyle.coral)
                    .multilineTextAlignment(.center)
            }
            Button {
                if step < 3 {
                    withAnimation(.snappy) { step += 1 }
                } else if onCreate(draft) {
                    dismiss()
                } else {
                    creationError = "作品を端末へ保存できませんでした。空き容量を確認して、もう一度お試しください。"
                }
            } label: {
                Image(systemName: step == 3 ? "checkmark" : "arrow.right")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SunGlassPrimaryButtonStyle())
            .accessibilityLabel(step == 3 ? "作品をつくる" : "次へ")
            .disabled(step == 0 && draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(step == 0 && draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(SunGlassStyle.ink.opacity(0.94))
    }

    private var previewPalette: [Color] {
        if let base = Color.sunGlassHex(draft.baseColor) {
            return [base] + draft.theme.colors
        }
        return draft.theme.colors
    }

    private var dateRange: String {
        "\(draft.startDate.formatted(.dateTime.month().day()))–\(draft.endDate.formatted(.dateTime.month().day()))"
    }

    private var stepSymbols: [String] {
        ["text.cursor", "square.grid.2x2", "calendar", "checkmark"]
    }

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        Text(required ? text : "\(text)（任意）")
        .font(SunGlassStyle.label(11))
        .foregroundStyle(SunGlassStyle.cream.opacity(0.65))
    }

    private func dateRow(title: String, date: Binding<Date>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DatePicker(title, selection: date, displayedComponents: .date)
                .labelsHidden()
                .tint(SunGlassStyle.lime)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(SunGlassStyle.cream.opacity(0.65))
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toggleRow(
        title: String,
        caption: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.46))
                }
            }
        }
        .tint(SunGlassStyle.lime)
        .padding(.vertical, 4)
    }
}

private struct ThemeChoiceCard: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: theme.symbol)
                .foregroundStyle(selected ? SunGlassStyle.lime : SunGlassStyle.cream.opacity(0.55))
                .frame(width: 22)
            Text(theme.displayName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(SunGlassStyle.lime)
            }
        }
        .foregroundStyle(SunGlassStyle.cream)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(selected ? SunGlassStyle.lime.opacity(0.12) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
