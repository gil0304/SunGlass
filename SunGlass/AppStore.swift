//
//  AppStore.swift
//  SunGlass
//
//  Main-actor app state with immediate, atomic JSON persistence.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private static let currentSchemaVersion = 2
    static let maximumSessionDuration: TimeInterval = 30
    static let dailyCreditedSecondsLimit: TimeInterval = 90
    static let targetPointsPerDay: Double = 100
    static let maximumMembers = 10
    static let maximumPiecesPerProject = 300

    private struct PersistenceEnvelope: Codable {
        var schemaVersion: Int
        var localUserID: UUID
        var didSeedSamples: Bool
        var projects: [GlassProject]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, localUserID, didSeedSamples, projects
        }

        init(
            schemaVersion: Int,
            localUserID: UUID,
            didSeedSamples: Bool,
            projects: [GlassProject]
        ) {
            self.schemaVersion = schemaVersion
            self.localUserID = localUserID
            self.didSeedSamples = didSeedSamples
            self.projects = projects
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            // `projects` is the payload, not optional metadata. Treat a missing or
            // malformed value as corruption so it can never be rewritten as an
            // apparently valid empty store.
            projects = try container.decode([GlassProject].self, forKey: .projects)
            localUserID = try container.decodeIfPresent(UUID.self, forKey: .localUserID)
                ?? projects.first?.ownerUserID
                ?? UUID()
            didSeedSamples = try container.decodeIfPresent(Bool.self, forKey: .didSeedSamples) ?? !projects.isEmpty
        }
    }

    private struct SchemaProbe: Decodable {
        var schemaVersion: Int?
    }

    private enum PersistenceError: Error {
        case unsupportedFutureSchema(Int)
    }

    private(set) var projects: [GlassProject] = []
    var selectedProjectID: UUID?
    var pendingInviteCode: String?
    private(set) var localUserID: UUID
    private(set) var lastErrorMessage: String?

    @ObservationIgnored private let persistenceURL: URL
    @ObservationIgnored private var calendar: Calendar
    @ObservationIgnored private var didSeedSamples = false
    /// A newer app may have written fields this binary cannot preserve. Once
    /// detected, keep the store read-only instead of downgrading that payload.
    @ObservationIgnored private var persistenceIsReadOnly = false

    var selectedProject: GlassProject? {
        guard let selectedProjectID else { return nil }
        return project(id: selectedProjectID)
    }

    var activeProjects: [GlassProject] {
        projects
            .filter { $0.status == .active || $0.status == .scheduled }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var completedProjects: [GlassProject] {
        projects
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    var collaborativeProjects: [GlassProject] {
        projects.filter(\.isCollaborative).sorted { $0.updatedAt > $1.updatedAt }
    }

    init(
        persistenceURL: URL? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        seedSampleData: Bool = true
    ) {
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL()
        self.calendar = calendar
        self.localUserID = UUID()

        load()
        refreshProjectStatuses(persistChanges: false)

        if seedSampleData, !didSeedSamples {
            projects = [Self.makeSampleProject(ownerUserID: localUserID, now: .now, calendar: calendar)]
            selectedProjectID = projects.first?.id
            didSeedSamples = true
            persist()
        }
    }

    func project(id: UUID) -> GlassProject? {
        projects.first { $0.id == id }
    }

    func project(withID id: UUID) -> GlassProject? { project(id: id) }

    @discardableResult
    func receiveDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "sunglass",
              url.host?.lowercased() == "join" else { return false }
        let code = url.pathComponents
            .filter { $0 != "/" }
            .first?
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard let code, code.count == 6 else { return false }
        pendingInviteCode = code
        return true
    }

    func projects(with status: ProjectStatus) -> [GlassProject] {
        projects.filter { $0.status == status }
    }

    @discardableResult
    func createProject(
        title: String,
        theme: Theme,
        duration: DurationPreset,
        startDate: Date = .now,
        customEndDate: Date? = nil,
        baseColor: String? = nil,
        note: String? = nil,
        isCollaborative: Bool = false,
        ownerDisplayName: String = "わたし",
        usesPhotos: Bool = false,
        recordsLocation: Bool = false
    ) -> GlassProject {
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        let normalizedStart = calendar.startOfDay(for: startDate)
        let end = duration.endDate(
            from: normalizedStart,
            customEndDate: customEndDate,
            calendar: calendar
        )
        let dayCount = inclusiveDayCount(from: normalizedStart, through: end)
        let id = UUID()
        let owner = ProjectMember(
            projectID: id,
            userID: localUserID,
            displayName: normalizedName(ownerDisplayName, fallback: "わたし"),
            role: .owner,
            assignedRegion: isCollaborative ? theme.displayName : nil,
            paletteToken: theme.paletteTokens.first
        )
        let today = calendar.startOfDay(for: .now)
        let status: ProjectStatus = today < normalizedStart ? .scheduled : .active
        let project = GlassProject(
            id: id,
            ownerUserID: localUserID,
            title: normalizedName(title, fallback: "夏の光"),
            theme: theme,
            durationPreset: duration,
            baseColor: normalizedOptional(baseColor),
            note: normalizedOptional(note),
            startDate: normalizedStart,
            endDate: end,
            requiredLightPoints: Double(dayCount) * Self.targetPointsPerDay,
            status: status,
            members: [owner],
            isCollaborative: isCollaborative,
            inviteCode: isCollaborative ? uniqueInviteCode() : nil,
            usesPhotos: usesPhotos,
            recordsLocation: recordsLocation
        )

        projects.insert(project, at: 0)
        selectedProjectID = project.id
        _ = persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        )
        return project
    }

    /// Label-compatible overload for forms that call the field `durationPreset`.
    @discardableResult
    func createProject(
        title: String,
        theme: Theme,
        durationPreset: DurationPreset,
        baseColor: String? = nil,
        startDate: Date = .now,
        endDate: Date? = nil,
        isCollaborative: Bool = false
    ) -> GlassProject {
        createProject(
            title: title,
            theme: theme,
            duration: durationPreset,
            startDate: startDate,
            customEndDate: endDate,
            baseColor: baseColor,
            isCollaborative: isCollaborative
        )
    }

    func updateProject(_ project: GlassProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        var updated = project
        updated.title = normalizedName(project.title, fallback: "夏の光")
        updated.updatedAt = .now
        projects[index] = updated
        refreshProjectStatuses(persistChanges: false)
        _ = persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        )
    }

    func deleteProject(id: UUID) {
        guard projects.contains(where: { $0.id == id }) else { return }
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        projects.removeAll { $0.id == id }
        if selectedProjectID == id { selectedProjectID = projects.first?.id }
        if persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        ) {
            PhotoMemoryService.removeAll(projectID: id)
            LightMeasurementDraftStore.remove(projectID: id)
        }
    }

    func archiveProject(id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        projects[index].status = .archived
        projects[index].updatedAt = .now
        if persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        ) {
            LightMeasurementDraftStore.remove(projectID: id)
        }
    }

    @discardableResult
    func removeRecordedLocations(projectID: UUID) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        guard projects[index].sessions.contains(where: { $0.location != nil }) else { return true }
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        for sessionIndex in projects[index].sessions.indices {
            projects[index].sessions[sessionIndex].location = nil
        }
        projects[index].updatedAt = .now
        return persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        )
    }

    // MARK: - Light collection

    func canCollectLight(projectID: UUID, at date: Date = .now) -> Bool {
        guard let project = project(id: projectID), project.status == .active else { return false }
        return isWithinProjectDates(date, project: project)
    }

    @discardableResult
    func recordLightSession(
        id: UUID = UUID(),
        projectID: UUID,
        startedAt: Date,
        endedAt: Date,
        averageIntensity: Double,
        maximumIntensity: Double,
        averageColorTemperature: Double,
        thermalState: DeviceThermalState = .unknown,
        location: LightSessionLocation? = nil,
        userID: UUID? = nil
    ) -> LightSession? {
        let session = LightSession(
            id: id,
            projectID: projectID,
            userID: userID ?? localUserID,
            startedAt: startedAt,
            endedAt: endedAt,
            averageIntensity: averageIntensity,
            maximumIntensity: maximumIntensity,
            averageColorTemperature: averageColorTemperature,
            deviceThermalState: thermalState,
            location: location
        )
        return addLightSession(session, to: projectID)
    }

    @discardableResult
    func addLightSession(_ newSession: LightSession, to projectID: UUID? = nil) -> LightSession? {
        let resolvedProjectID = projectID ?? newSession.projectID
        guard let projectIndex = projects.firstIndex(where: { $0.id == resolvedProjectID }) else {
            reportError("作品が見つかりませんでした。")
            return nil
        }
        if let existing = projects[projectIndex].sessions.first(where: { $0.id == newSession.id }) {
            return existing
        }

        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        var project = projects[projectIndex]
        guard project.status == .active,
              isWithinProjectDates(.now, project: project),
              isWithinProjectDates(newSession.startedAt, project: project) else {
            reportError("この作品の制作期間外では光を集められません。")
            return nil
        }
        var session = newSession
        session.projectID = project.id
        // A caller cannot attach a coordinate unless this specific project was
        // explicitly created with location recording enabled.
        if !project.recordsLocation { session.location = nil }
        session.durationSeconds = min(
            Self.maximumSessionDuration,
            max(0, session.durationSeconds.isFinite ? session.durationSeconds : 0)
        )
        session.endedAt = session.startedAt.addingTimeInterval(session.durationSeconds)
        session.averageIntensity = max(0, session.averageIntensity.isFinite ? session.averageIntensity : 0)
        session.maximumIntensity = max(0, session.maximumIntensity.isFinite ? session.maximumIntensity : 0)
        session.averageColorTemperature = max(
            0,
            session.averageColorTemperature.isFinite ? session.averageColorTemperature : 0
        )
        session.timePeriod = .period(for: session.startedAt, calendar: calendar)
        session.lightLevel = .level(for: session.averageIntensity)

        guard session.durationSeconds >= 3, session.averageIntensity > 0 else {
            reportError("有効な光を3秒以上計測できませんでした。もう一度お試しください。")
            return nil
        }

        let existingCredited = project.sessions
            .filter {
                $0.userID == session.userID
                    && calendar.isDate($0.startedAt, inSameDayAs: session.startedAt)
            }
            .reduce(0) { $0 + $1.creditedDurationSeconds }
        let remainingSeconds = max(0, Self.dailyCreditedSecondsLimit - existingCredited)
        let insideProjectDates = isWithinProjectDates(session.startedAt, project: project)
        session.creditedDurationSeconds = insideProjectDates
            ? min(session.durationSeconds, remainingSeconds)
            : 0
        let sameUserSessions = project.sessions.filter { $0.userID == session.userID }
        let existingDailyPoints = sameUserSessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: session.startedAt) }
            .reduce(0) { $0 + $1.earnedPoints }
        let remainingDailyPoints = max(0, Self.targetPointsPerDay - existingDailyPoints)
        session.earnedPoints = min(
            remainingDailyPoints,
            points(for: session, existingSessions: sameUserSessions)
        )
        guard session.creditedDurationSeconds > 0, session.earnedPoints > 0 else {
            reportError("今日集められる光は上限に達しています。記録は追加されませんでした。")
            return nil
        }

        project.sessions.append(session)
        project.currentLightPoints += session.earnedPoints
        appendPieces(for: session, to: &project)
        project.updatedAt = .now
        refreshStatus(of: &project, referenceDate: .now)
        projects[projectIndex] = project
        guard persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        ) else { return nil }
        return session
    }

    /// Records the value-only result produced by LightMeterController.
    @discardableResult
    func addLightSession(
        from measurement: LightMeasurement,
        to projectID: UUID,
        userID: UUID? = nil,
        location: LightSessionLocation? = nil
    ) -> LightSession? {
        guard measurement.elapsedDuration.isFinite,
              measurement.elapsedDuration <= Self.maximumSessionDuration + 0.05,
              measurement.duration.isFinite,
              measurement.duration >= 3,
              measurement.duration <= measurement.elapsedDuration,
              measurement.acceptedSampleCount >= 5,
              measurement.firstAcceptedSampleAt != nil,
              measurement.lastAcceptedSampleAt != nil,
              measurement.sampleDensity.isFinite,
              measurement.sampleDensity > 0,
              measurement.averageIntensity.isFinite,
              measurement.averageIntensity > 0 else {
            reportError("十分な光を計測できませんでした。3秒以上、カメラを光へ向けてもう一度お試しください。")
            return nil
        }
        let duration = min(Self.maximumSessionDuration, measurement.duration)
        return recordLightSession(
            id: measurement.id,
            projectID: projectID,
            startedAt: measurement.startedAt,
            endedAt: measurement.startedAt.addingTimeInterval(duration),
            averageIntensity: measurement.averageIntensity,
            maximumIntensity: measurement.maximumIntensity,
            averageColorTemperature: measurement.averageColorTemperature,
            thermalState: DeviceThermalState(measurement.thermalLevel),
            location: location,
            userID: userID
        )
    }

    func creditedSeconds(on date: Date = .now, projectID: UUID, userID: UUID? = nil) -> Double {
        guard let project = project(id: projectID) else { return 0 }
        let resolvedUserID = userID ?? localUserID
        return project.sessions
            .filter { $0.userID == resolvedUserID && calendar.isDate($0.startedAt, inSameDayAs: date) }
            .reduce(0) { $0 + $1.creditedDurationSeconds }
    }

    func remainingCreditedSeconds(on date: Date = .now, projectID: UUID, userID: UUID? = nil) -> Double {
        max(0, Self.dailyCreditedSecondsLimit - creditedSeconds(on: date, projectID: projectID, userID: userID))
    }

    func creditedPoints(on date: Date = .now, projectID: UUID, userID: UUID? = nil) -> Double {
        guard let project = project(id: projectID) else { return 0 }
        let resolvedUserID = userID ?? localUserID
        return project.sessions
            .filter { $0.userID == resolvedUserID && calendar.isDate($0.startedAt, inSameDayAs: date) }
            .reduce(0) { $0 + $1.earnedPoints }
    }

    func remainingCreditedPoints(on date: Date = .now, projectID: UUID, userID: UUID? = nil) -> Double {
        max(0, Self.targetPointsPerDay - creditedPoints(on: date, projectID: projectID, userID: userID))
    }

    func estimatedLightPoints(
        projectID: UUID,
        date: Date = .now,
        duration: TimeInterval,
        averageIntensity: Double,
        userID: UUID? = nil
    ) -> Double {
        guard averageIntensity.isFinite,
              averageIntensity > 0,
              let project = project(id: projectID),
              project.status == .active,
              isWithinProjectDates(date, project: project) else { return 0 }
        let resolvedUserID = userID ?? localUserID
        let existing = project.sessions.filter { $0.userID == resolvedUserID }
        let creditedDuration = min(
            max(0, duration),
            remainingCreditedSeconds(on: date, projectID: projectID, userID: resolvedUserID),
            Self.maximumSessionDuration
        )
        let candidate = LightSession(
            projectID: projectID,
            userID: resolvedUserID,
            startedAt: date,
            endedAt: date.addingTimeInterval(creditedDuration),
            durationSeconds: creditedDuration,
            creditedDurationSeconds: creditedDuration,
            averageIntensity: max(0, averageIntensity),
            maximumIntensity: max(0, averageIntensity),
            averageColorTemperature: 6_500
        )
        return min(
            remainingCreditedPoints(on: date, projectID: projectID, userID: resolvedUserID),
            points(for: candidate, existingSessions: existing)
        )
    }

    // MARK: - Daily memories

    @discardableResult
    func saveMemory(
        projectID: UUID,
        date: Date = .now,
        comment: String,
        photoPath: String? = nil,
        representativeColor: String? = nil,
        photoPalette: [String]? = nil,
        photoBrightness: Double? = nil,
        photoEdgeDensity: Double? = nil,
        userID: UUID? = nil
    ) -> DailyMemory? {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            reportError("作品が見つかりませんでした。")
            return nil
        }
        let resolvedUserID = userID ?? localUserID
        let day = calendar.startOfDay(for: date)
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        var project = projects[projectIndex]
        let previousPhotoPath = project.memories.first(where: {
            $0.userID == resolvedUserID && calendar.isDate($0.recordDate, inSameDayAs: day)
        })?.photoPath
        let newPhotoPath = PhotoMemoryService.portablePath(photoPath)
        let normalizedPalette = photoPalette.map {
            Array($0.compactMap(normalizedOptional).prefix(5))
        }
        let memoryRevealProgress = progress(of: project, through: day)

        let memory: DailyMemory
        if let memoryIndex = project.memories.firstIndex(where: {
            $0.userID == resolvedUserID && calendar.isDate($0.recordDate, inSameDayAs: day)
        }) {
            project.memories[memoryIndex].comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            project.memories[memoryIndex].photoPath = newPhotoPath
            project.memories[memoryIndex].representativeColor = normalizedOptional(representativeColor)
            project.memories[memoryIndex].photoPalette = normalizedPalette
            project.memories[memoryIndex].photoBrightness = normalizedUnit(photoBrightness)
            project.memories[memoryIndex].photoEdgeDensity = normalizedUnit(photoEdgeDensity)
            project.memories[memoryIndex].revealProgress = memoryRevealProgress
            project.memories[memoryIndex].updatedAt = .now
            memory = project.memories[memoryIndex]
        } else {
            memory = DailyMemory(
                projectID: project.id,
                userID: resolvedUserID,
                recordDate: day,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                photoPath: newPhotoPath,
                representativeColor: normalizedOptional(representativeColor),
                photoPalette: normalizedPalette,
                photoBrightness: normalizedUnit(photoBrightness),
                photoEdgeDensity: normalizedUnit(photoEdgeDensity),
                revealProgress: memoryRevealProgress
            )
            project.memories.append(memory)
        }
        project.updatedAt = .now
        projects[projectIndex] = project
        guard persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        ) else {
            let wasPreviouslyReferenced = previousProjects
                .flatMap(\.memories)
                .contains { $0.photoPath == newPhotoPath }
            if newPhotoPath != previousPhotoPath, !wasPreviouslyReferenced {
                PhotoMemoryService.remove(path: newPhotoPath)
            }
            return nil
        }
        if previousPhotoPath != newPhotoPath {
            let remainsReferenced = project.memories.contains { $0.photoPath == previousPhotoPath }
            if !remainsReferenced { PhotoMemoryService.remove(path: previousPhotoPath) }
        }
        return memory
    }

    func memory(on date: Date, projectID: UUID, userID: UUID? = nil) -> DailyMemory? {
        let resolvedUserID = userID ?? localUserID
        return project(id: projectID)?.memories.first {
            $0.userID == resolvedUserID && calendar.isDate($0.recordDate, inSameDayAs: date)
        }
    }

    func deleteMemory(id: UUID, projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        let photoPath = projects[index].memories.first(where: { $0.id == id })?.photoPath
        projects[index].memories.removeAll { $0.id == id }
        projects[index].updatedAt = .now
        if persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        ) {
            PhotoMemoryService.remove(path: photoPath)
        }
    }

    // MARK: - Collaboration

    @discardableResult
    func enableCollaboration(for projectID: UUID) -> String? {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        projects[index].isCollaborative = true
        if projects[index].inviteCode == nil { projects[index].inviteCode = uniqueInviteCode() }
        projects[index].updatedAt = .now
        guard persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        ) else { return nil }
        return projects[index].inviteCode
    }

    @discardableResult
    func joinProject(
        inviteCode: String,
        displayName: String,
        userID: UUID? = nil
    ) -> GlassProject? {
        let code = inviteCode.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let index = projects.firstIndex(where: { $0.inviteCode?.uppercased() == code }) else {
            reportError("招待コードに一致する作品がありません。")
            return nil
        }
        var project = projects[index]
        let joiningUserID = userID ?? localUserID
        if project.members.contains(where: { $0.userID == joiningUserID }) {
            selectedProjectID = project.id
            return project
        }
        guard project.members.count < Self.maximumMembers else {
            reportError("この共同作品は10人に達しています。")
            return nil
        }
        let previousProjects = projects
        let previousSelectedProjectID = selectedProjectID
        let memberIndex = project.members.count
        project.members.append(
            ProjectMember(
                projectID: project.id,
                userID: joiningUserID,
                displayName: normalizedName(displayName, fallback: "参加者\(memberIndex + 1)"),
                role: .contributor,
                assignedRegion: collaborationRegions(for: project.theme)[memberIndex % collaborationRegions(for: project.theme).count],
                paletteToken: project.theme.paletteTokens[memberIndex % project.theme.paletteTokens.count]
            )
        )
        project.updatedAt = .now
        projects[index] = project
        selectedProjectID = project.id
        guard persistOrRollback(
            previousProjects: previousProjects,
            previousSelectedProjectID: previousSelectedProjectID
        ) else { return nil }
        return project
    }

    func refreshProjectStatuses(referenceDate: Date = .now) {
        refreshProjectStatuses(referenceDate: referenceDate, persistChanges: true)
    }

    func save() { persist() }

    func clearLastError() { lastErrorMessage = nil }

    // MARK: - Persistence

    private func load() {
        let fileManager = FileManager.default
        let primaryExists = fileManager.fileExists(atPath: persistenceURL.path)
        let backupURL = backupPersistenceURL
        guard primaryExists || fileManager.fileExists(atPath: backupURL.path) else { return }
        do {
            let envelope = try decodeEnvelope(from: primaryExists ? persistenceURL : backupURL)
            apply(envelope)
        } catch PersistenceError.unsupportedFutureSchema(let version) {
            protectFutureSchema(version)
        } catch {
            do {
                let envelope = try decodeEnvelope(from: backupURL)
                apply(envelope)
                reportError("保存データの一部を読み込めなかったため、直前のバックアップから復旧しました。")
            } catch PersistenceError.unsupportedFutureSchema(let version) {
                protectFutureSchema(version)
            } catch {
                protectUnreadableStore()
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !persistenceIsReadOnly else {
            reportError("既存の保存データを保護中のため、上書きできません。")
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let envelope = PersistenceEnvelope(
                schemaVersion: Self.currentSchemaVersion,
                localUserID: localUserID,
                didSeedSamples: didSeedSamples,
                projects: projects
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(envelope)
            // A future-generation backup is data too. Preserve it during a
            // downgrade even when the primary happens to be readable here.
            if FileManager.default.fileExists(atPath: backupPersistenceURL.path) {
                do {
                    _ = try decodeEnvelope(from: backupPersistenceURL)
                } catch PersistenceError.unsupportedFutureSchema(let version) {
                    protectFutureSchema(version)
                    return false
                } catch {
                    // A corrupt backup can be replaced with a decodable primary.
                }
            }
            // Preserve the previously decodable primary as the actual last-good
            // generation before replacing it with the new atomic payload.
            if FileManager.default.fileExists(atPath: persistenceURL.path) {
                do {
                    _ = try decodeEnvelope(from: persistenceURL)
                    if let previousData = try? Data(contentsOf: persistenceURL) {
                        try? previousData.write(to: backupPersistenceURL, options: .atomic)
                    }
                } catch PersistenceError.unsupportedFutureSchema(let version) {
                    protectFutureSchema(version)
                    return false
                } catch {
                    // A corrupt primary may be replaced by the in-memory state,
                    // but it must never be promoted to the last-good backup.
                }
            }
            try data.write(to: persistenceURL, options: .atomic)
            // First save has no previous generation, so seed the backup with the
            // complete payload. Later saves keep the preceding generation above.
            if !FileManager.default.fileExists(atPath: backupPersistenceURL.path) {
                try? data.write(to: backupPersistenceURL, options: .atomic)
            }
            lastErrorMessage = nil
            return true
        } catch {
            reportError("作品を端末へ保存できませんでした。")
            return false
        }
    }

    private var backupPersistenceURL: URL {
        persistenceURL
            .deletingPathExtension()
            .appendingPathExtension("backup")
            .appendingPathExtension(persistenceURL.pathExtension.isEmpty ? "json" : persistenceURL.pathExtension)
    }

    private func decodeEnvelope(from url: URL) throws -> PersistenceEnvelope {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Probe the version before decoding the payload. Future schemas may use
        // enum cases or shapes that this version cannot decode at all.
        if let probe = try? decoder.decode(SchemaProbe.self, from: data),
           let version = probe.schemaVersion,
           version > Self.currentSchemaVersion {
            throw PersistenceError.unsupportedFutureSchema(version)
        }
        let envelope: PersistenceEnvelope
        do {
            envelope = try decoder.decode(PersistenceEnvelope.self, from: data)
        } catch {
            // Very early development builds stored the project array directly.
            // Keeping this fallback makes those files migratable too.
            let projects = try decoder.decode([GlassProject].self, from: data)
            envelope = PersistenceEnvelope(
                schemaVersion: 0,
                localUserID: projects.first?.ownerUserID ?? UUID(),
                didSeedSamples: !projects.isEmpty,
                projects: projects
            )
        }
        guard envelope.schemaVersion <= Self.currentSchemaVersion else {
            throw PersistenceError.unsupportedFutureSchema(envelope.schemaVersion)
        }
        return envelope
    }

    private func protectFutureSchema(_ version: Int) {
        persistenceIsReadOnly = true
        didSeedSamples = true
        reportError("保存データは将来バージョン（v\(version)）で作成されているため、上書きせず保護しました。")
    }

    private func protectUnreadableStore() {
        persistenceIsReadOnly = true
        didSeedSamples = true
        reportError("保存データとバックアップを読み込めませんでした。既存ファイルは上書きせず保護しています。")
    }

    private func apply(_ envelope: PersistenceEnvelope) {
        var migratedProjects = envelope.projects
        for projectIndex in migratedProjects.indices {
            let projectID = migratedProjects[projectIndex].id
            for sessionIndex in migratedProjects[projectIndex].sessions.indices {
                migratedProjects[projectIndex].sessions[sessionIndex].projectID = projectID
            }
            for memoryIndex in migratedProjects[projectIndex].memories.indices {
                migratedProjects[projectIndex].memories[memoryIndex].projectID = projectID
                migratedProjects[projectIndex].memories[memoryIndex].photoPath = PhotoMemoryService.portablePath(
                    migratedProjects[projectIndex].memories[memoryIndex].photoPath
                )
            }
            for pieceIndex in migratedProjects[projectIndex].pieces.indices {
                migratedProjects[projectIndex].pieces[pieceIndex].projectID = projectID
            }
            for memberIndex in migratedProjects[projectIndex].members.indices {
                migratedProjects[projectIndex].members[memberIndex].projectID = projectID
            }
        }
        let needsRewrite = envelope.schemaVersion != Self.currentSchemaVersion
            || migratedProjects != envelope.projects
        projects = migratedProjects
        localUserID = envelope.localUserID
        didSeedSamples = envelope.didSeedSamples
        selectedProjectID = projects.first?.id
        lastErrorMessage = nil
        if needsRewrite { _ = persist() }
    }

    private func persistOrRollback(
        previousProjects: [GlassProject],
        previousSelectedProjectID: UUID?
    ) -> Bool {
        guard persist() else {
            projects = previousProjects
            selectedProjectID = previousSelectedProjectID
            return false
        }
        return true
    }

    private static func defaultPersistenceURL() -> URL {
        let fileManager = FileManager.default
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "SunGlass",
            isDirectory: true
        )
        return directory.appendingPathComponent("sun-glass-projects.json")
    }

    // MARK: - Calculation and normalization

    private func points(for session: LightSession, existingSessions: [LightSession]) -> Double {
        guard session.creditedDurationSeconds > 0 else { return 0 }
        // Light quality changes the glass character more than the score: keep the
        // multiplier useful but narrow enough to avoid rewarding brightness races.
        let intensityFactor = min(1.10, max(0.80, 0.80 + session.averageIntensity / 5_000))
        let continuityFactor = 1 + min(0.14, Double(consecutiveDays(before: session.startedAt, in: existingSessions)) * 0.02)
        let raw = session.creditedDurationSeconds / Self.dailyCreditedSecondsLimit
            * Self.targetPointsPerDay
            * intensityFactor
            * continuityFactor
        return (raw * 100).rounded() / 100
    }

    private func consecutiveDays(before date: Date, in sessions: [LightSession]) -> Int {
        let activeDays = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        let day = calendar.startOfDay(for: date)
        var count = 0
        for offset in 1...7 {
            guard let previous = calendar.date(byAdding: .day, value: -offset, to: day), activeDays.contains(previous) else { break }
            count += 1
        }
        return count
    }

    private func appendPieces(for session: LightSession, to project: inout GlassProject) {
        guard session.creditedDurationSeconds > 0, project.pieces.count < Self.maximumPiecesPerProject else { return }
        let wanted = min(4, max(1, Int(ceil(session.creditedDurationSeconds / 25))))
        var random = StableRandom(seed: session.id)
        for _ in 0..<min(wanted, Self.maximumPiecesPerProject - project.pieces.count) {
            let shape = GlassPieceShape.allCases[Int(random.next() % UInt64(GlassPieceShape.allCases.count))]
            var tokenPool = session.timePeriod.paletteTokens
            let temperatureTokens: [String]
            if session.averageColorTemperature < 4_500 {
                temperatureTokens = ["sunsetOrange", "sunsetRed", "memoryAmber"]
            } else if session.averageColorTemperature > 6_500 {
                temperatureTokens = ["morningAqua", "dayBlue", "deepBlue"]
            } else {
                temperatureTokens = []
            }
            tokenPool.append(contentsOf: temperatureTokens.filter { !tokenPool.contains($0) })
            if let contributorToken = project.members
                .first(where: { $0.userID == session.userID })?
                .paletteToken,
               !tokenPool.contains(contributorToken) {
                tokenPool.append(contributorToken)
            }
            project.pieces.append(
                GlassPiece(
                    projectID: project.id,
                    pieceIndex: project.pieces.count,
                    shapeType: shape,
                    positionX: random.unit,
                    positionY: random.unit,
                    rotation: random.unit * .pi * 2,
                    scale: 0.65 + random.unit * (0.35 + Double(session.lightLevel.rawValue) * 0.09),
                    colorToken: tokenPool[Int(random.next() % UInt64(tokenPool.count))],
                    opacity: min(0.95, 0.38 + Double(session.lightLevel.rawValue) * 0.1),
                    emission: Double(session.lightLevel.rawValue) * 0.08,
                    revealProgress: project.progress,
                    contributorUserID: session.userID
                )
            )
        }
    }

    private func refreshProjectStatuses(referenceDate: Date = .now, persistChanges: Bool) {
        let oldProjects = projects
        for index in projects.indices { refreshStatus(of: &projects[index], referenceDate: referenceDate) }
        if persistChanges, oldProjects != projects, !persist() {
            projects = oldProjects
        }
    }

    private func refreshStatus(of project: inout GlassProject, referenceDate: Date) {
        guard project.status != .archived else { return }
        let today = calendar.startOfDay(for: referenceDate)
        if today < calendar.startOfDay(for: project.startDate) {
            project.status = .scheduled
            project.completedAt = nil
        } else if today > calendar.startOfDay(for: project.endDate) {
            project.status = .completed
            project.completedAt = project.completedAt ?? referenceDate
        } else {
            project.status = .active
            project.completedAt = nil
        }
    }

    private func isWithinProjectDates(_ date: Date, project: GlassProject) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: project.startDate)
            && day <= calendar.startOfDay(for: project.endDate)
    }

    private func inclusiveDayCount(from start: Date, through end: Date) -> Int {
        max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private func progress(of project: GlassProject, through date: Date) -> Double {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let points = project.sessions
            .filter { $0.startedAt < endOfDay }
            .reduce(0) { $0 + $1.earnedPoints }
        return min(max(points / max(project.requiredLightPoints, 1), 0), project.progress)
    }

    private func uniqueInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var code = ""
        repeat { code = String((0..<6).map { _ in alphabet.randomElement()! }) }
        while projects.contains(where: { $0.inviteCode == code })
        return code
    }

    private func collaborationRegions(for theme: Theme) -> [String] {
        switch theme {
        case .ocean: ["海", "空", "太陽", "水平線", "装飾"]
        case .cumulonimbus: ["空", "雲", "日差し", "街", "装飾"]
        case .fireworks: ["夜空", "花火", "水面", "提灯", "装飾"]
        case .goldfish: ["金魚", "水面", "水草", "波紋", "装飾"]
        case .summerFestival: ["鳥居", "提灯", "屋台", "浴衣", "装飾"]
        case .summerWindow: ["窓", "空", "風鈴", "朝顔", "装飾"]
        case .summerMemory: ["光", "色", "輪郭", "記憶", "装飾"]
        }
    }

    private func normalizedName(_ value: String, fallback: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((normalized.isEmpty ? fallback : normalized).prefix(80))
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else { return nil }
        return normalized
    }

    private func normalizedUnit(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    private func reportError(_ message: String) { lastErrorMessage = message }

    private static func makeSampleProject(ownerUserID: UUID, now: Date, calendar: Calendar) -> GlassProject {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -3, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let projectID = UUID()
        let owner = ProjectMember(
            projectID: projectID,
            userID: ownerUserID,
            displayName: "わたし",
            role: .owner,
            paletteToken: Theme.ocean.paletteTokens.first,
            joinedAt: start
        )
        var sessions: [LightSession] = []
        for (offset, intensity, periodHour) in [(-3, 720.0, 8), (-2, 1_080.0, 13), (-1, 1_380.0, 17)] {
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let started = calendar.date(bySettingHour: periodHour, minute: 15, second: 0, of: day) ?? day
            sessions.append(
                LightSession(
                    projectID: projectID,
                    userID: ownerUserID,
                    startedAt: started,
                    endedAt: started.addingTimeInterval(28),
                    creditedDurationSeconds: 28,
                    averageIntensity: intensity,
                    maximumIntensity: intensity * 1.18,
                    averageColorTemperature: periodHour >= 16 ? 4_300 : 6_100,
                    earnedPoints: intensity / 1_000 * 28 / 90 * 100,
                    deviceThermalState: .nominal,
                    createdAt: started
                )
            )
        }
        let points = sessions.reduce(0) { $0 + $1.earnedPoints }
        return GlassProject(
            id: projectID,
            ownerUserID: ownerUserID,
            title: "サンプル：海辺の夏休み",
            theme: .ocean,
            durationPreset: .sevenDays,
            baseColor: "oceanBlue",
            note: "光を集めて、今年の海を残そう。",
            startDate: start,
            endDate: end,
            requiredLightPoints: 700,
            currentLightPoints: points,
            sessions: sessions,
            memories: [
                DailyMemory(
                    projectID: projectID,
                    userID: ownerUserID,
                    recordDate: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                    comment: "夕立のあとの空がきれいだった",
                    representativeColor: "sunsetOrange"
                )
            ],
            members: [owner],
            createdAt: start,
            updatedAt: now
        )
    }
}

private extension DeviceThermalState {
    init(_ level: DeviceThermalLevel) {
        switch level {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        }
    }
}

private struct StableRandom {
    private var state: UInt64

    init(seed: UUID) {
        let bytes = withUnsafeBytes(of: seed.uuid) { Array($0) }
        self.state = bytes.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    var unit: Double {
        mutating get { Double(next() >> 11) / Double(1 << 53) }
    }
}
