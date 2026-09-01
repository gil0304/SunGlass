import SwiftUI

struct LightJournalView: View {
    @Environment(AppStore.self) private var store
    @State private var visibleMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var memoryDate: Date?

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()

                if let project = selectedProject {
                    ScrollView {
                        ProjectCalendarContent(
                            project: project,
                            visibleMonth: $visibleMonth,
                            selectedDate: $selectedDate,
                            onEditMemory: { memoryDate = $0 }
                        )
                        .padding(.horizontal, 18)
                        .padding(.bottom, 36)
                    }
                } else {
                    ContentUnavailableView("記録なし", systemImage: "calendar.badge.plus")
                    .foregroundStyle(SunGlassStyle.cream)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                journalHeader
            }
            .sheet(item: $memoryDate) { date in
                if let project = selectedProject {
                    MemoryEditorView(projectID: project.id, date: date)
                        .environment(store)
                }
            }
            .onAppear {
                if store.selectedProjectID == nil {
                    store.selectedProjectID = store.projects.first?.id
                }
            }
        }
    }

    private var selectedProject: GlassProject? {
        if let id = store.selectedProjectID, let project = store.project(id: id) { return project }
        return store.projects.first
    }

    private var journalHeader: some View {
        HStack(spacing: 12) {
            Text("記録")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream)
            Spacer()
            if !store.projects.isEmpty {
                Menu {
                    ForEach(store.projects) { project in
                        Button {
                            store.selectedProjectID = project.id
                            visibleMonth = Calendar.current.startOfMonth(for: Date())
                            selectedDate = Calendar.current.startOfDay(for: Date())
                        } label: {
                            Label(project.title, systemImage: project.theme.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(selectedProject?.title ?? "作品")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SunGlassStyle.lime)
                    .frame(maxWidth: 155, alignment: .trailing)
                    .padding(.vertical, 8)
                }
                .accessibilityLabel("作品を選ぶ")
                .accessibilityValue(selectedProject?.title ?? "未選択")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(SunGlassStyle.ink.opacity(0.95))
    }
}

struct ProjectCalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    @State private var visibleMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var memoryDate: Date?

    var body: some View {
        NavigationStack {
            ZStack {
                SunGlassBackground()
                if let project = store.project(id: projectID) {
                    ScrollView {
                        ProjectCalendarContent(
                            project: project,
                            visibleMonth: $visibleMonth,
                            selectedDate: $selectedDate,
                            onEditMemory: { memoryDate = $0 }
                        )
                        .padding(.horizontal, 18)
                        .padding(.bottom, 36)
                    }
                }
            }
            .navigationTitle("記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(SunGlassStyle.lime)
                    }
                    .accessibilityLabel("閉じる")
                }
            }
            .sheet(item: $memoryDate) { date in
                MemoryEditorView(projectID: projectID, date: date)
                    .environment(store)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ProjectCalendarContent: View {
    let project: GlassProject
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    let onEditMemory: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            monthHeader
            calendarGrid
            dayDetail
        }
        .padding(.top, 10)
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("前の月")

            Spacer()
            Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream)
            Spacer()

            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("次の月")
        }
        .foregroundStyle(SunGlassStyle.cream.opacity(0.7))
    }

    private var calendarGrid: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                ForEach(calendar.shortStandaloneWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SunGlassStyle.cream.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let sessions = sessions(on: date)
        let memory = memory(on: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isInProject = date >= calendar.startOfDay(for: project.startDate)
            && date <= calendar.startOfDay(for: project.endDate)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))

                HStack(spacing: 3) {
                    if !sessions.isEmpty {
                        Circle()
                            .fill(isSelected ? SunGlassStyle.ink : SunGlassStyle.lime)
                            .frame(width: 5, height: 5)
                    }
                    if memory != nil {
                        Circle()
                            .stroke(isSelected ? SunGlassStyle.ink : SunGlassStyle.cream, lineWidth: 1)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .foregroundStyle(isSelected ? SunGlassStyle.ink : SunGlassStyle.cream.opacity(isInProject ? 0.76 : 0.22))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(isSelected ? SunGlassStyle.lime : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if calendar.isDateInToday(date), !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SunGlassStyle.lime.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibility(date: date, sessions: sessions, memory: memory))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayDetail: some View {
        let sessions = sessions(on: selectedDate)
        let memory = memory(on: selectedDate)

        return VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(SunGlassStyle.cream.opacity(0.1))

            HStack {
                Text(selectedDate.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream)
                Spacer()
                Button {
                    onEditMemory(selectedDate)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SunGlassStyle.lime)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(memory == nil ? "一言を残す" : "一言を編集")
            }

            if sessions.isEmpty {
                Text("未計測")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.4))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions.sorted(by: { $0.startedAt > $1.startedAt })) { session in
                        HStack(spacing: 12) {
                            Image(systemName: session.timePeriod == .night ? "moon.stars" : "sun.max")
                                .foregroundStyle(SunGlassStyle.lime)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(session.timePeriod.displayName)・\(session.lightLevel.displayName)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SunGlassStyle.cream)
                                Text("\(session.startedAt.formatted(.dateTime.hour().minute())) ・ \(Int(session.durationSeconds))秒")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(SunGlassStyle.cream.opacity(0.4))
                            }
                            Spacer()
                            if session.location != nil {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                                    .foregroundStyle(SunGlassStyle.cream.opacity(0.35))
                                    .accessibilityLabel("位置情報あり")
                            }
                        }
                        .padding(.vertical, 9)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if let memory {
                Divider().overlay(SunGlassStyle.cream.opacity(0.08))

                HStack(alignment: .top, spacing: 12) {
                    if let image = PhotoMemoryService.load(path: memory.photoPath) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SunGlassStyle.cream.opacity(0.08))
                            .overlay {
                                Image(systemName: "quote.opening")
                                    .foregroundStyle(SunGlassStyle.cream.opacity(0.4))
                            }
                            .frame(width: 58, height: 58)
                    }

                    if !memory.comment.isEmpty {
                        Text(memory.comment)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(SunGlassStyle.cream.opacity(0.76))
                            .lineSpacing(2)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(memory.comment.isEmpty ? "一言の記録あり" : memory.comment)
            }
        }
    }

    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: visibleMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: visibleMonth)
        }
        return Array(repeating: nil, count: leading) + dates.map(Optional.some)
    }

    private func moveMonth(_ offset: Int) {
        withAnimation(.snappy) {
            visibleMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
        }
    }

    private func sessions(on date: Date) -> [LightSession] {
        project.sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    private func memory(on date: Date) -> DailyMemory? {
        project.memories.first { calendar.isDate($0.recordDate, inSameDayAs: date) }
    }

    private func dayAccessibility(date: Date, sessions: [LightSession], memory: DailyMemory?) -> String {
        var value = date.formatted(.dateTime.month().day())
        value += sessions.isEmpty ? "、計測なし" : "、\(sessions.count)回計測"
        if memory != nil { value += "、一言あり" }
        return value
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
