import SwiftUI

extension Theme {
    @MainActor var colors: [Color] { paletteTokens.map(Color.sunGlassToken) }

    var shortDescription: String {
        switch self {
        case .ocean: "水面と水平線"
        case .cumulonimbus: "雲とまぶしい青空"
        case .fireworks: "夜空にひらく光"
        case .goldfish: "水紋を泳ぐ赤"
        case .summerFestival: "提灯と祭りの夜"
        case .summerWindow: "風鈴のある窓辺"
        case .summerMemory: "言葉と写真の色"
        }
    }
}

extension TimePeriod {
    var color: Color {
        switch self {
        case .morning: SunGlassStyle.cyan
        case .day: SunGlassStyle.lime
        case .evening: SunGlassStyle.coral
        case .night: SunGlassStyle.violet
        }
    }
}

extension LightLevel {
    var color: Color {
        switch self {
        case .dark: Color(red: 0.42, green: 0.43, blue: 0.58)
        case .soft: SunGlassStyle.violet
        case .bright: SunGlassStyle.cyan
        case .strong: SunGlassStyle.lime
        case .veryStrong: SunGlassStyle.coral
        }
    }

    var patternDescription: String {
        switch self {
        case .dark: "小さな星と深い背景"
        case .soft: "透明な細かなかけら"
        case .bright: "輪郭をつくる標準のかけら"
        case .strong: "鮮やかな大きなかけら"
        case .veryStrong: "中心モチーフへ強い反射"
        }
    }
}

extension GlassProject {
    var artworkSeed: Int {
        id.uuidString.unicodeScalars.reduce(17) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fff_ffff
        }
    }

    var dominantTimePeriod: TimePeriod? {
        guard !sessions.isEmpty else { return nil }
        let grouped = Dictionary(grouping: sessions, by: \.timePeriod)
        return grouped.max { lhs, rhs in
            lhs.value.reduce(0) { $0 + $1.durationSeconds } < rhs.value.reduce(0) { $0 + $1.durationSeconds }
        }?.key
    }

    var totalMeasurementSeconds: Double {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    var averageIntensity: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.averageIntensity } / Double(sessions.count)
    }

    var daysWithLight: Int {
        Set(sessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).count
    }

    var todayCreditedSeconds: Double {
        sessions
            .filter { Calendar.current.isDateInToday($0.startedAt) }
            .reduce(0) { $0 + $1.creditedDurationSeconds }
    }

    /// The visible palette is built from the chosen theme plus the light and
    /// memories actually recorded for this project.
    @MainActor var artworkPalette: [Color] { artworkPalette(asOf: nil) }

    /// Returns the palette that existed at `cutoff`. A nil cutoff represents
    /// the current project and intentionally includes every persisted value.
    @MainActor func artworkPalette(asOf cutoff: Date?) -> [Color] {
        let snapshot = artworkSnapshot(asOf: cutoff)
        var result: [Color] = []
        if let base = Color.sunGlassHex(baseColor) {
            result.append(base)
        } else if let baseColor {
            result.append(.sunGlassToken(baseColor))
        }
        result.append(contentsOf: theme.colors)

        let memoryColors = prioritizedMemoryColorValues(snapshot.memories, limit: 4)
            .map { Color.sunGlassHex($0) ?? Color.sunGlassToken($0) }
        result.append(contentsOf: memoryColors)

        result.append(contentsOf: evenlySampled(snapshot.pieces, limit: 3).map { piece in
            if let token = piece.colorToken { return Color.sunGlassToken(token) }
            return Color(red: piece.colorRed, green: piece.colorGreen, blue: piece.colorBlue)
        })

        var sessionColors = Set(snapshot.sessions.map(\.timePeriod))
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map(\.color)
        if snapshot.sessions.contains(where: { $0.averageColorTemperature > 0 && $0.averageColorTemperature < 4_500 }) {
            sessionColors.append(.sunGlassToken("memoryAmber"))
        }
        if snapshot.sessions.contains(where: { $0.averageColorTemperature > 6_500 }) {
            sessionColors.append(.sunGlassToken("morningAqua"))
        }
        result.append(contentsOf: evenlySampled(sessionColors, limit: 3))
        result.append(contentsOf: evenlySampled(
            snapshot.members.compactMap { $0.paletteToken.map(Color.sunGlassToken) },
            limit: 2
        ))
        return Array(result.prefix(18))
    }

    /// Persisted glass pieces are the primary layer. Session and memory facets
    /// add a small, deterministic signature so time of day, temperature and a
    /// representative photo colour remain visible in viewer, AR preview and export.
    @MainActor var recordedLightFacets: [RecordedLightFacet] { recordedLightFacets(asOf: nil) }

    /// Reconstructs the persisted facets visible at `cutoff`. Category budgets
    /// keep late sessions and photos represented even when a long project has
    /// more than the renderer's 420-facet ceiling.
    @MainActor func recordedLightFacets(asOf cutoff: Date?) -> [RecordedLightFacet] {
        let snapshot = artworkSnapshot(asOf: cutoff)
        let pieceFacets = snapshot.pieces.map { piece in
            RecordedLightFacet(
                position: CGPoint(
                    x: min(max(piece.positionX, 0.04), 0.96),
                    y: min(max(piece.positionY, 0.04), 0.96)
                ),
                rotation: piece.rotation,
                scale: piece.scale,
                color: piece.colorToken.map(Color.sunGlassToken)
                    ?? Color(red: piece.colorRed, green: piece.colorGreen, blue: piece.colorBlue),
                opacity: piece.opacity,
                emission: piece.emission,
                revealProgress: min(max(piece.revealProgress, 0), 1),
                shape: piece.shapeType.recordedFacetShape
            )
        }

        var cumulativePoints = 0.0
        let sessionFacets = snapshot.sessions
            .sorted { $0.startedAt < $1.startedAt }
            .filter { $0.creditedDurationSeconds > 0 }
            .map { session -> RecordedLightFacet in
                cumulativePoints += session.earnedPoints
                let strength = Double(session.lightLevel.rawValue) / Double(max(1, LightLevel.veryStrong.rawValue))
                return RecordedLightFacet(
                    position: deterministicPosition(for: session.id, inset: 0.09),
                    rotation: deterministicUnit(for: session.id, salt: 3) * .pi * 2,
                    scale: 0.58 + strength * 0.68,
                    color: session.recordedLightColor,
                    opacity: 0.42 + strength * 0.34,
                    emission: 0.05 + strength * 0.26,
                    revealProgress: min(1, cumulativePoints / max(requiredLightPoints, 1)),
                    shape: session.lightLevel.recordedFacetShape
                )
            }

        let memoryFacetGroups = snapshot.memories
            .sorted(by: historicalMemoryOrder)
            .map { memory -> [RecordedLightFacet] in
                let values = (memory.photoPalette?.isEmpty == false
                    ? memory.photoPalette ?? []
                    : memory.representativeColor.map { [$0] } ?? [])
                guard !values.isEmpty else { return [] }
                let memoryDayEnd = Calendar.current.date(
                    byAdding: .day,
                    value: 1,
                    to: Calendar.current.startOfDay(for: memory.recordDate)
                ) ?? memory.recordDate
                let recordedProgress = memory.revealProgress ?? min(
                    1,
                    snapshot.sessions
                        .filter { $0.startedAt < memoryDayEnd }
                        .reduce(0) { $0 + $1.earnedPoints } / max(requiredLightPoints, 1)
                )
                let brightness = min(max(memory.photoBrightness ?? 0.55, 0), 1)
                let edges = min(max(memory.photoEdgeDensity ?? 0.08, 0), 1)
                let shape: RecordedLightFacet.Shape = if edges > 0.28 {
                    .shard
                } else if edges > 0.14 {
                    .quadrilateral
                } else {
                    .circle
                }
                return values.prefix(5).enumerated().map { index, value in
                    RecordedLightFacet(
                        position: deterministicPosition(
                            for: memory.id,
                            inset: 0.12,
                            saltBase: UInt64(20 + index * 2)
                        ),
                        rotation: deterministicUnit(for: memory.id, salt: UInt64(30 + index)) * .pi * 2,
                        scale: 0.56 + edges * 0.82 + brightness * 0.16,
                        color: Color.sunGlassHex(value) ?? Color.sunGlassToken(value),
                        opacity: 0.46 + brightness * 0.40,
                        emission: 0.04 + brightness * 0.24,
                        revealProgress: min(max(recordedProgress, 0), 1),
                        shape: shape
                    )
                }
            }

        let facetLimit = 420
        let memoryFacetCount = memoryFacetGroups.reduce(0) { $0 + $1.count }
        var pieceLimit = min(pieceFacets.count, 250)
        var sessionLimit = min(sessionFacets.count, 90)
        var memoryLimit = min(memoryFacetCount, 80)
        var remaining = facetLimit - pieceLimit - sessionLimit - memoryLimit

        // Persisted pieces are the primary artwork, photo colours are the most
        // semantically distinctive overlay, and sessions provide the ambient
        // signature. Each category gets unused capacity before any truncation.
        for category in 0..<3 where remaining > 0 {
            let available: Int
            switch category {
            case 0: available = pieceFacets.count - pieceLimit
            case 1: available = memoryFacetCount - memoryLimit
            default: available = sessionFacets.count - sessionLimit
            }
            let added = min(max(0, available), remaining)
            switch category {
            case 0: pieceLimit += added
            case 1: memoryLimit += added
            default: sessionLimit += added
            }
            remaining -= added
        }

        let selectedPieces = evenlySampled(pieceFacets, limit: pieceLimit)
        let selectedSessions = evenlySampled(sessionFacets, limit: sessionLimit)
        let selectedMemories = prioritizedMemoryFacets(memoryFacetGroups, limit: memoryLimit)
        return selectedPieces + selectedSessions + selectedMemories
    }
}

private struct ArtworkSnapshot {
    let sessions: [LightSession]
    let memories: [DailyMemory]
    let pieces: [GlassPiece]
    let members: [ProjectMember]
}

private extension GlassProject {
    func artworkSnapshot(asOf cutoff: Date?) -> ArtworkSnapshot {
        guard let cutoff else {
            return ArtworkSnapshot(
                sessions: sessions,
                memories: memories,
                pieces: pieces,
                members: members
            )
        }

        let visibleSessions = sessions.filter { $0.endedAt <= cutoff }
        let visiblePieceCount = min(300, visibleSessions.reduce(0) { count, session in
            guard session.creditedDurationSeconds > 0 else { return count }
            return count + min(4, max(1, Int(ceil(session.creditedDurationSeconds / 25))))
        })
        let visiblePieces = pieces
            .sorted {
                if $0.pieceIndex != $1.pieceIndex { return $0.pieceIndex < $1.pieceIndex }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(visiblePieceCount)

        let calendar = Calendar.current
        let cutoffDay = calendar.startOfDay(for: cutoff)
        return ArtworkSnapshot(
            sessions: visibleSessions,
            memories: memories.filter {
                calendar.startOfDay(for: $0.recordDate) <= cutoffDay
            },
            pieces: Array(visiblePieces),
            members: members.filter { $0.joinedAt <= cutoff }
        )
    }
}

private func historicalMemoryOrder(_ lhs: DailyMemory, _ rhs: DailyMemory) -> Bool {
    if lhs.recordDate != rhs.recordDate { return lhs.recordDate < rhs.recordDate }
    return lhs.id.uuidString < rhs.id.uuidString
}

/// Selects across the complete range (including both ends) rather than taking
/// an insertion-order prefix, so later project days remain visible.
private func evenlySampled<Element>(_ values: [Element], limit: Int) -> [Element] {
    guard limit > 0, !values.isEmpty else { return [] }
    guard values.count > limit else { return values }
    guard limit > 1 else { return [values[values.count / 2]] }

    return (0..<limit).map { index in
        let position = Double(index) * Double(values.count - 1) / Double(limit - 1)
        return values[Int(position.rounded())]
    }
}

/// The first colour from every memory is selected before second and later
/// colours. This gives every recorded day priority over extra colours from an
/// early photo while remaining deterministic.
private func prioritizedMemoryColorValues(_ memories: [DailyMemory], limit: Int) -> [String] {
    let groups = memories
        .sorted(by: historicalMemoryOrder)
        .map { memory in
            memory.photoPalette?.isEmpty == false
                ? Array((memory.photoPalette ?? []).prefix(5))
                : memory.representativeColor.map { [$0] } ?? []
        }
    return prioritizedMemoryValues(groups, limit: limit)
}

private func prioritizedMemoryFacets(
    _ groups: [[RecordedLightFacet]],
    limit: Int
) -> [RecordedLightFacet] {
    prioritizedMemoryValues(groups, limit: limit)
}

private func prioritizedMemoryValues<Element>(_ groups: [[Element]], limit: Int) -> [Element] {
    guard limit > 0, !groups.isEmpty else { return [] }
    let layerCount = groups.map(\.count).max() ?? 0
    var result: [Element] = []
    result.reserveCapacity(limit)

    for layerIndex in 0..<layerCount where result.count < limit {
        let layer = groups.compactMap { group in
            group.indices.contains(layerIndex) ? group[layerIndex] : nil
        }
        let capacity = limit - result.count
        result.append(contentsOf: evenlySampled(layer, limit: capacity))
    }
    return result
}

private extension LightSession {
    @MainActor var recordedLightColor: Color {
        if averageColorTemperature > 0, averageColorTemperature < 4_500 {
            return .sunGlassToken(timePeriod == .evening ? "sunsetRed" : "memoryAmber")
        }
        if averageColorTemperature > 6_500 {
            return .sunGlassToken(timePeriod == .night ? "deepBlue" : "morningAqua")
        }
        return timePeriod.color
    }
}

private extension LightLevel {
    var recordedFacetShape: RecordedLightFacet.Shape {
        switch self {
        case .dark: .circle
        case .soft: .arc
        case .bright: .quadrilateral
        case .strong: .triangle
        case .veryStrong: .shard
        }
    }
}

private extension GlassPieceShape {
    var recordedFacetShape: RecordedLightFacet.Shape {
        switch self {
        case .shard: .shard
        case .triangle: .triangle
        case .quadrilateral: .quadrilateral
        case .arc: .arc
        case .circle: .circle
        }
    }
}

private func deterministicPosition(for id: UUID, inset: Double, saltBase: UInt64 = 0) -> CGPoint {
    let range = max(0, 1 - inset * 2)
    return CGPoint(
        x: inset + deterministicUnit(for: id, salt: saltBase + 1) * range,
        y: inset + deterministicUnit(for: id, salt: saltBase + 2) * range
    )
}

private func deterministicUnit(for id: UUID, salt: UInt64) -> Double {
    var value: UInt64 = 14_695_981_039_346_656_037 ^ salt
    for byte in id.uuidString.utf8 {
        value ^= UInt64(byte)
        value &*= 1_099_511_628_211
    }
    value ^= value >> 33
    return Double(value % 10_000) / 9_999
}

extension Color {
    static func sunGlassToken(_ token: String) -> Color {
        switch token {
        case "oceanBlue", "dayBlue", "deepBlue": return Color(red: 0.08, green: 0.43, blue: 0.84)
        case "skyBlue", "morningAqua", "waterBlue", "memoryBlue": return Color(red: 0.20, green: 0.72, blue: 0.92)
        case "aqua", "turquoise", "glassAqua": return Color(red: 0.10, green: 0.82, blue: 0.76)
        case "foamWhite", "cloudWhite", "curtainWhite", "glassWhite", "clearGlass": return Color(red: 0.95, green: 0.96, blue: 0.89)
        case "sunYellow", "paleYellow", "sparkYellow", "festivalGold", "lampGold": return Color(red: 1.0, green: 0.78, blue: 0.17)
        case "hazeLavender", "morningLavender", "violet", "morningGloryPurple", "memoryViolet": return Color(red: 0.56, green: 0.35, blue: 0.83)
        case "nightNavy", "indigo": return Color(red: 0.055, green: 0.08, blue: 0.28)
        case "fireRed", "goldfishRed", "lanternRed", "sunsetRed": return Color(red: 0.91, green: 0.14, blue: 0.16)
        case "sunsetOrange", "memoryAmber": return Color(red: 1.0, green: 0.38, blue: 0.13)
        case "festivalPink", "yukataPink", "sunsetPink", "memoryRose": return Color(red: 0.98, green: 0.30, blue: 0.56)
        case "waterweedGreen", "leafGreen": return Color(red: 0.10, green: 0.56, blue: 0.31)
        default: return SunGlassStyle.cyan
        }
    }

    static func sunGlassHex(_ hex: String?) -> Color? {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
