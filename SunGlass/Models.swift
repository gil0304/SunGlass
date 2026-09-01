//
//  Models.swift
//  SunGlass
//
//  Local, persistence-friendly domain models for SUN GLASS.
//

import Foundation

enum Theme: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case ocean
    case cumulonimbus
    case fireworks
    case goldfish
    case summerFestival
    case summerWindow
    case summerMemory

    var id: Self { self }

    var displayName: String {
        switch self {
        case .ocean: "海"
        case .cumulonimbus: "入道雲"
        case .fireworks: "花火"
        case .goldfish: "金魚"
        case .summerFestival: "夏祭り"
        case .summerWindow: "夏の窓"
        case .summerMemory: "夏の記憶"
        }
    }

    var symbol: String {
        switch self {
        case .ocean: "water.waves"
        case .cumulonimbus: "cloud.sun.fill"
        case .fireworks: "sparkles"
        case .goldfish: "fish.fill"
        case .summerFestival: "fan.fill"
        case .summerWindow: "window.casement"
        case .summerMemory: "photo.on.rectangle.angled"
        }
    }

    /// Semantic color names. Views are free to map these tokens to their own Color assets.
    var paletteTokens: [String] {
        switch self {
        case .ocean: ["oceanBlue", "aqua", "foamWhite", "turquoise", "sunYellow"]
        case .cumulonimbus: ["skyBlue", "cloudWhite", "hazeLavender", "sunYellow"]
        case .fireworks: ["nightNavy", "violet", "fireRed", "sparkYellow", "festivalPink"]
        case .goldfish: ["goldfishRed", "sunsetOrange", "waterBlue", "waterweedGreen", "clearGlass"]
        case .summerFestival: ["lanternRed", "indigo", "festivalGold", "yukataPink", "nightNavy"]
        case .summerWindow: ["skyBlue", "curtainWhite", "morningGloryPurple", "leafGreen", "glassAqua"]
        case .summerMemory: ["memoryBlue", "memoryAmber", "memoryRose", "memoryViolet", "clearGlass"]
        }
    }

    var description: String {
        switch self {
        case .ocean: "波や水面、水平線が光を受けて育つ、透明感のある海の景色。"
        case .cumulonimbus: "青空に立ち上がる大きな雲と、まっすぐな夏の日差し。"
        case .fireworks: "夜空と水面へ、集めた光が色鮮やかな花火として広がる。"
        case .goldfish: "水草や波紋の間を、赤や橙の金魚が涼やかに泳ぐ。"
        case .summerFestival: "提灯、屋台、鳥居、浴衣の模様を重ねた賑やかな夏の夜。"
        case .summerWindow: "風鈴やカーテン越しに、朝顔と青空を眺める静かな窓辺。"
        case .summerMemory: "写真や一言の色と雰囲気を、抽象的な光のかけらへ変える。"
        }
    }
}

enum DurationPreset: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case oneDay
    case threeDays
    case sevenDays
    case fourteenDays
    case thirtyDays
    case julyThroughAugust
    case summerVacation
    case custom

    var id: Self { self }

    var displayName: String {
        switch self {
        case .oneDay: "1日"
        case .threeDays: "3日間"
        case .sevenDays: "7日間"
        case .fourteenDays: "14日間"
        case .thirtyDays: "30日間"
        case .julyThroughAugust: "7月から8月末まで"
        case .summerVacation: "夏休み全体"
        case .custom: "カスタム期間"
        }
    }

    var recommended: Bool {
        switch self {
        case .sevenDays, .fourteenDays, .thirtyDays, .julyThroughAugust, .summerVacation: true
        default: false
        }
    }

    func endDate(
        from startDate: Date,
        customEndDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Date {
        let start = calendar.startOfDay(for: startDate)
        switch self {
        case .oneDay: return start
        case .threeDays: return calendar.date(byAdding: .day, value: 2, to: start) ?? start
        case .sevenDays: return calendar.date(byAdding: .day, value: 6, to: start) ?? start
        case .fourteenDays: return calendar.date(byAdding: .day, value: 13, to: start) ?? start
        case .thirtyDays: return calendar.date(byAdding: .day, value: 29, to: start) ?? start
        case .summerVacation:
            return calendar.date(byAdding: .day, value: 41, to: start) ?? start
        case .julyThroughAugust:
            let year = calendar.component(.year, from: start)
            let thisAugust = calendar.date(from: DateComponents(year: year, month: 8, day: 31)) ?? start
            if start <= thisAugust { return thisAugust }
            return calendar.date(from: DateComponents(year: year + 1, month: 8, day: 31)) ?? start
        case .custom:
            return max(start, calendar.startOfDay(for: customEndDate ?? start))
        }
    }
}

enum TimePeriod: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case morning
    case day
    case evening
    case night

    var id: Self { self }

    var displayName: String {
        switch self {
        case .morning: "朝"
        case .day: "昼"
        case .evening: "夕方"
        case .night: "夜"
        }
    }

    var paletteTokens: [String] {
        switch self {
        case .morning: ["morningAqua", "morningLavender", "paleYellow", "glassWhite"]
        case .day: ["dayBlue", "sunYellow", "glassWhite", "turquoise"]
        case .evening: ["sunsetOrange", "sunsetRed", "sunsetPink", "violet"]
        case .night: ["nightNavy", "violet", "deepBlue", "lampGold"]
        }
    }

    static func period(for date: Date, calendar: Calendar = .current) -> Self {
        switch calendar.component(.hour, from: date) {
        case 5..<10: .morning
        case 10..<16: .day
        case 16..<19: .evening
        default: .night
        }
    }
}

// LightLevel's base declaration lives beside the AR light meter. These model-facing
// conveniences keep one qualitative scale shared by capture, persistence and UI.
extension LightLevel: Identifiable, Hashable, Comparable {
    var id: Self { self }
    var displayName: String { label }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    static func level(for intensity: Double) -> Self {
        switch max(0, intensity.isFinite ? intensity : 0) {
        case ..<250: .dark
        case ..<650: .soft
        case ..<1_300: .bright
        case ..<2_600: .strong
        default: .veryStrong
        }
    }
}

enum ProjectStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case scheduled
    case active
    case completed
    case archived

    var id: Self { self }

    var displayName: String {
        switch self {
        case .scheduled: "開始前"
        case .active: "制作中"
        case .completed: "完成"
        case .archived: "アーカイブ"
        }
    }
}

enum DeviceThermalState: String, Codable, CaseIterable, Hashable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

enum GlassPieceShape: String, Codable, CaseIterable, Hashable, Sendable {
    case shard
    case triangle
    case quadrilateral
    case arc
    case circle
}

enum ProjectMemberRole: String, Codable, CaseIterable, Hashable, Sendable {
    case owner
    case contributor
    case viewer

    var displayName: String {
        switch self {
        case .owner: "オーナー"
        case .contributor: "参加者"
        case .viewer: "閲覧者"
        }
    }
}

struct LightSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var userID: UUID
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Double
    var creditedDurationSeconds: Double
    var averageIntensity: Double
    var maximumIntensity: Double
    var averageColorTemperature: Double
    var timePeriod: TimePeriod
    var lightLevel: LightLevel
    var earnedPoints: Double
    var deviceThermalState: DeviceThermalState
    /// An intentionally coarse, optional coordinate captured for this session.
    /// Optional decoding keeps sessions written before location support readable.
    var location: LightSessionLocation?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        userID: UUID,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double? = nil,
        creditedDurationSeconds: Double = 0,
        averageIntensity: Double,
        maximumIntensity: Double,
        averageColorTemperature: Double,
        timePeriod: TimePeriod? = nil,
        lightLevel: LightLevel? = nil,
        earnedPoints: Double = 0,
        deviceThermalState: DeviceThermalState = .unknown,
        location: LightSessionLocation? = nil,
        createdAt: Date = .now
    ) {
        let measuredDuration = max(0, endedAt.timeIntervalSince(startedAt))
        self.id = id
        self.projectID = projectID
        self.userID = userID
        self.startedAt = startedAt
        self.endedAt = max(startedAt, endedAt)
        self.durationSeconds = max(0, durationSeconds ?? measuredDuration)
        self.creditedDurationSeconds = max(0, creditedDurationSeconds)
        self.averageIntensity = max(0, averageIntensity.isFinite ? averageIntensity : 0)
        self.maximumIntensity = max(0, maximumIntensity.isFinite ? maximumIntensity : 0)
        self.averageColorTemperature = max(0, averageColorTemperature.isFinite ? averageColorTemperature : 0)
        self.timePeriod = timePeriod ?? .period(for: startedAt)
        self.lightLevel = lightLevel ?? .level(for: averageIntensity)
        self.earnedPoints = max(0, earnedPoints.isFinite ? earnedPoints : 0)
        self.deviceThermalState = deviceThermalState
        self.location = location
        self.createdAt = createdAt
    }
}

/// A privacy-preserving place attached to a light session.
///
/// Coordinates supplied by `LocationCaptureController` are quantized to an
/// approximately 100-metre grid before this value is created. No place name,
/// address, route or continuous location history is stored.
struct LightSessionLocation: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double
    var capturedAt: Date

    init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        capturedAt: Date = .now
    ) {
        self.latitude = latitude.isFinite ? min(max(latitude, -90), 90) : 0
        self.longitude = longitude.isFinite ? min(max(longitude, -180), 180) : 0
        self.horizontalAccuracyMeters = horizontalAccuracyMeters.isFinite
            ? max(100, horizontalAccuracyMeters)
            : 100
        self.capturedAt = capturedAt
    }
}

struct DailyMemory: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var userID: UUID
    var recordDate: Date
    var comment: String
    var photoPath: String?
    var representativeColor: String?
    /// A compact, locally extracted palette. Optional keeps memories created by
    /// earlier app versions fully decodable.
    var photoPalette: [String]?
    /// Perceptual luminance in the closed range 0...1.
    var photoBrightness: Double?
    /// Approximate ratio of high-contrast edges in the closed range 0...1.
    var photoEdgeDensity: Double?
    /// Project progress when this memory entered the artwork. Optional keeps
    /// memories written by schema v1 decodable.
    var revealProgress: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        userID: UUID,
        recordDate: Date,
        comment: String = "",
        photoPath: String? = nil,
        representativeColor: String? = nil,
        photoPalette: [String]? = nil,
        photoBrightness: Double? = nil,
        photoEdgeDensity: Double? = nil,
        revealProgress: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.userID = userID
        self.recordDate = recordDate
        self.comment = comment
        self.photoPath = photoPath
        self.representativeColor = representativeColor
        self.photoPalette = photoPalette
        self.photoBrightness = photoBrightness.map { min(max($0, 0), 1) }
        self.photoEdgeDensity = photoEdgeDensity.map { min(max($0, 0), 1) }
        self.revealProgress = revealProgress.map { min(max($0, 0), 1) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GlassPiece: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var pieceIndex: Int
    var shapeType: GlassPieceShape
    var positionX: Double
    var positionY: Double
    var rotation: Double
    var scale: Double
    var colorRed: Double
    var colorGreen: Double
    var colorBlue: Double
    var colorToken: String?
    var opacity: Double
    var emission: Double
    var revealProgress: Double
    var contributorUserID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        pieceIndex: Int,
        shapeType: GlassPieceShape,
        positionX: Double,
        positionY: Double,
        rotation: Double = 0,
        scale: Double = 1,
        colorRed: Double = 1,
        colorGreen: Double = 1,
        colorBlue: Double = 1,
        colorToken: String? = nil,
        opacity: Double = 0,
        emission: Double = 0,
        revealProgress: Double = 0,
        contributorUserID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.pieceIndex = pieceIndex
        self.shapeType = shapeType
        self.positionX = positionX.clamped(to: 0...1)
        self.positionY = positionY.clamped(to: 0...1)
        self.rotation = rotation
        self.scale = max(0.01, scale)
        self.colorRed = colorRed.clamped(to: 0...1)
        self.colorGreen = colorGreen.clamped(to: 0...1)
        self.colorBlue = colorBlue.clamped(to: 0...1)
        self.colorToken = colorToken
        self.opacity = opacity.clamped(to: 0...1)
        self.emission = max(0, emission)
        self.revealProgress = revealProgress.clamped(to: 0...1)
        self.contributorUserID = contributorUserID
        self.createdAt = createdAt
    }
}

struct ProjectMember: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var userID: UUID
    var displayName: String
    var role: ProjectMemberRole
    var assignedRegion: String?
    var paletteToken: String?
    var joinedAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        userID: UUID,
        displayName: String,
        role: ProjectMemberRole,
        assignedRegion: String? = nil,
        paletteToken: String? = nil,
        joinedAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.userID = userID
        self.displayName = displayName
        self.role = role
        self.assignedRegion = assignedRegion
        self.paletteToken = paletteToken
        self.joinedAt = joinedAt
    }
}

struct GlassProject: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var ownerUserID: UUID
    var title: String
    var theme: Theme
    var durationPreset: DurationPreset
    var baseColor: String?
    var note: String?
    var startDate: Date
    var endDate: Date
    var requiredLightPoints: Double
    var currentLightPoints: Double
    var status: ProjectStatus
    var sessions: [LightSession]
    var memories: [DailyMemory]
    var pieces: [GlassPiece]
    var members: [ProjectMember]
    var isCollaborative: Bool
    var inviteCode: String?
    var usesPhotos: Bool
    var recordsLocation: Bool
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, ownerUserID, title, theme, durationPreset, baseColor, note
        case startDate, endDate, requiredLightPoints, currentLightPoints, status
        case sessions, memories, pieces, members, isCollaborative, inviteCode
        case usesPhotos, recordsLocation, createdAt, updatedAt, completedAt
    }

    var progress: Double {
        guard requiredLightPoints > 0 else { return 0 }
        return (currentLightPoints / requiredLightPoints).clamped(to: 0...1)
    }

    var progressPercentage: Int { Int((progress * 100).rounded()) }

    var hasCollectedLightToday: Bool {
        let calendar = Calendar.autoupdatingCurrent
        return sessions.contains { calendar.isDateInToday($0.startedAt) }
    }

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        title: String,
        theme: Theme,
        durationPreset: DurationPreset,
        baseColor: String? = nil,
        note: String? = nil,
        startDate: Date,
        endDate: Date,
        requiredLightPoints: Double,
        currentLightPoints: Double = 0,
        status: ProjectStatus = .active,
        sessions: [LightSession] = [],
        memories: [DailyMemory] = [],
        pieces: [GlassPiece] = [],
        members: [ProjectMember] = [],
        isCollaborative: Bool = false,
        inviteCode: String? = nil,
        usesPhotos: Bool = false,
        recordsLocation: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.title = title
        self.theme = theme
        self.durationPreset = durationPreset
        self.baseColor = baseColor
        self.note = note
        self.startDate = startDate
        self.endDate = max(startDate, endDate)
        self.requiredLightPoints = max(1, requiredLightPoints)
        self.currentLightPoints = max(0, currentLightPoints)
        self.status = status
        self.sessions = sessions
        self.memories = memories
        self.pieces = pieces
        self.members = members
        self.isCollaborative = isCollaborative
        self.inviteCode = inviteCode
        self.usesPhotos = usesPhotos
        self.recordsLocation = recordsLocation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    /// Defaults for fields introduced after the first local schema keep an
    /// otherwise healthy project readable during version migration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Missing collections are valid for schema v1, while malformed existing
        // collections must fail the load. Swallowing that error would discard the
        // whole collection as `[]` and later persist the data loss.
        let sessions = try container.decodeIfPresent([LightSession].self, forKey: .sessions) ?? []
        let memories = try container.decodeIfPresent([DailyMemory].self, forKey: .memories) ?? []
        let pieces = try container.decodeIfPresent([GlassPiece].self, forKey: .pieces) ?? []
        let members = try container.decodeIfPresent([ProjectMember].self, forKey: .members) ?? []
        let projectID = try container.decodeIfPresent(UUID.self, forKey: .id)
            ?? sessions.first?.projectID
            ?? memories.first?.projectID
            ?? pieces.first?.projectID
            ?? UUID()
        let ownerID = try container.decodeIfPresent(UUID.self, forKey: .ownerUserID)
            ?? members.first?.userID
            ?? sessions.first?.userID
            ?? UUID()
        let start = try container.decodeIfPresent(Date.self, forKey: .startDate)
            ?? (try container.decodeIfPresent(Date.self, forKey: .createdAt))
            ?? .now
        let end = try container.decodeIfPresent(Date.self, forKey: .endDate) ?? start
        let earnedPoints = sessions.reduce(0) { $0 + $1.earnedPoints }

        self.init(
            id: projectID,
            ownerUserID: ownerID,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "夏の光",
            theme: try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .summerMemory,
            durationPreset: try container.decodeIfPresent(DurationPreset.self, forKey: .durationPreset) ?? .custom,
            baseColor: try container.decodeIfPresent(String.self, forKey: .baseColor),
            note: try container.decodeIfPresent(String.self, forKey: .note),
            startDate: start,
            endDate: end,
            requiredLightPoints: try container.decodeIfPresent(Double.self, forKey: .requiredLightPoints) ?? 100,
            currentLightPoints: try container.decodeIfPresent(Double.self, forKey: .currentLightPoints) ?? earnedPoints,
            status: try container.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .active,
            sessions: sessions,
            memories: memories,
            pieces: pieces,
            members: members,
            isCollaborative: try container.decodeIfPresent(Bool.self, forKey: .isCollaborative) ?? (members.count > 1),
            inviteCode: try container.decodeIfPresent(String.self, forKey: .inviteCode),
            usesPhotos: try container.decodeIfPresent(Bool.self, forKey: .usesPhotos) ?? memories.contains { $0.photoPath != nil },
            recordsLocation: try container.decodeIfPresent(Bool.self, forKey: .recordsLocation) ?? false,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? start,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? start,
            completedAt: try container.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }

    func remainingDays(from date: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: endDate)
        guard today <= end else { return 0 }
        return max(0, (calendar.dateComponents([.day], from: today, to: end).day ?? 0) + 1)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
