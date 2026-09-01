import SwiftUI

/// A persisted or derived fragment of collected light. Keeping this value-only
/// lets the renderer consume real session data without owning app state.
struct RecordedLightFacet {
    enum Shape: String {
        case shard, triangle, quadrilateral, arc, circle
    }

    let position: CGPoint
    let rotation: Double
    let scale: Double
    let color: Color
    let opacity: Double
    let emission: Double
    let revealProgress: Double
    let shape: Shape
}

/// A model-independent, procedurally generated SUN GLASS artwork.
///
/// `progress` and `highlight` are clamped to `0...1`. Passing an empty palette
/// uses the selected theme's built-in palette. The same inputs always produce
/// the same glass layout and colouring.
struct GlassArtworkView: View {
    let themeID: String
    let seed: Int
    let progress: Double
    let palette: [Color]
    let leadLines: Bool
    let highlight: Double
    let recordedFacets: [RecordedLightFacet]

    @AppStorage("reduceLightEffects") private var reduceLightEffects = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        themeID: String,
        seed: Int,
        progress: Double,
        palette: [Color] = [],
        leadLines: Bool = true,
        highlight: Double = 0.6,
        recordedFacets: [RecordedLightFacet] = []
    ) {
        self.themeID = themeID
        self.seed = seed
        self.progress = progress
        self.palette = palette
        self.leadLines = leadLines
        self.highlight = highlight
        self.recordedFacets = recordedFacets
    }

    var body: some View {
        Group {
            if reduceMotion || reduceLightEffects || clampedHighlight == 0 {
                artwork(phase: staticPhase)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { timeline in
                    artwork(
                        phase: timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 8) / 8
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(theme.accessibilityName)のステンドグラス"))
        .accessibilityValue(Text("着色率 \(Int((clampedProgress * 100).rounded()))パーセント"))
        .accessibilityHint(Text(accessibilityHint))
        .accessibilityAddTraits(.isImage)
    }

    private var clampedProgress: Double { progress.clamped(to: 0...1) }
    private var clampedHighlight: Double {
        min(highlight.clamped(to: 0...1), reduceLightEffects ? 0.18 : 1)
    }
    private var theme: GlassTheme { GlassTheme(id: themeID) }
    private var staticPhase: Double {
        Double(UInt64(bitPattern: Int64(seed)) % 1_000) / 1_000
    }

    private var accessibilityHint: String {
        switch clampedProgress {
        case 1: "すべてのガラス片が色づいた完成作品です"
        case 0..<0.31: "透明なガラスに、光で色のかけらが焼き付き始めています"
        case 0.31..<0.71: "鉛線と夏のモチーフが少しずつ現れています"
        default: "中央に最後の透明なガラス片を残した、完成間近の作品です"
        }
    }

    private func artwork(phase: Double) -> some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            guard size.width > 1, size.height > 1 else { return }

            GlassArtworkRenderer(
                theme: theme,
                seed: seed,
                progress: clampedProgress,
                palette: palette.isEmpty ? theme.defaultPalette : palette,
                leadLines: leadLines,
                highlight: clampedHighlight,
                phase: phase,
                reduceTransparency: reduceTransparency,
                strengthenedOutlines: differentiateWithoutColor || colorSchemeContrast == .increased,
                recordedFacets: recordedFacets
            ).draw(in: &context, size: size)
        }
    }
}

/// A polygon described in normalized (`0...1`) artwork coordinates.
struct StainedGlassShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first.scaled(to: rect))
        for point in points.dropFirst() {
            path.addLine(to: point.scaled(to: rect))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Renderer

private struct GlassArtworkRenderer {
    let theme: GlassTheme
    let seed: Int
    let progress: Double
    let palette: [Color]
    let leadLines: Bool
    let highlight: Double
    let phase: Double
    let reduceTransparency: Bool
    let strengthenedOutlines: Bool
    let recordedFacets: [RecordedLightFacet]

    private var leadColor: Color { Color(red: 0.035, green: 0.055, blue: 0.075) }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let inset = max(1, min(size.width, size.height) * 0.012)
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        let radius = max(4, min(size.width, size.height) * 0.035)
        let pane = Path(roundedRect: rect, cornerRadius: radius)
        let lineScale = min(size.width, size.height)

        context.fill(
            pane,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(reduceTransparency ? 0.20 : 0.08),
                    Color(red: 0.76, green: 0.90, blue: 0.96).opacity(reduceTransparency ? 0.16 : 0.045),
                    Color.white.opacity(reduceTransparency ? 0.12 : 0.025)
                ]),
                startPoint: rect.origin,
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )

        var clipped = context
        clipped.clip(to: pane)
        let pieces = makePieces()

        for piece in pieces {
            let path = StainedGlassShape(points: piece.points).path(in: rect)
            let reveal = progress >= 0.999 ? 1 : smoothstep(
                edge0: piece.revealAt - 0.055,
                edge1: piece.revealAt + 0.025,
                value: progress
            )

            let clearAlpha = reduceTransparency ? 0.16 : 0.025 + (1 - reveal) * 0.035
            clipped.fill(path, with: .color(Color.white.opacity(clearAlpha)))

            if reveal > 0.001 {
                let color = palette[piece.colorIndex % palette.count]
                let alpha = (reduceTransparency ? 0.64 : 0.30) + reveal * (reduceTransparency ? 0.28 : 0.50)
                let bounds = path.boundingRect
                clipped.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            color.opacity(alpha * (0.74 + piece.tone * 0.12)),
                            color.opacity(alpha),
                            Color.white.opacity(alpha * (0.08 + highlight * 0.13))
                        ]),
                        startPoint: CGPoint(x: bounds.minX, y: bounds.maxY),
                        endPoint: CGPoint(x: bounds.maxX, y: bounds.minY)
                    )
                )
            }

            let forming = smoothstep(edge0: 0.25, edge1: 0.68, value: progress)
            let initialOutline = strengthenedOutlines ? 0.30 : 0.11
            let leadAlpha = leadLines ? initialOutline + forming * (strengthenedOutlines ? 0.68 : 0.57) : initialOutline
            clipped.stroke(
                path,
                with: .color((leadLines ? leadColor : Color.white).opacity(leadAlpha)),
                lineWidth: max(0.35, lineScale * (leadLines ? 0.0042 : 0.0015))
            )

            if highlight > 0, reveal > 0.1, piece.tone > 0.72 {
                clipped.stroke(
                    path,
                    with: .color(Color.white.opacity(highlight * reveal * 0.17)),
                    lineWidth: max(0.25, lineScale * 0.0016)
                )
            }
        }

        drawRecordedFacets(in: &clipped, rect: rect, lineScale: lineScale)
        drawThemeMotif(in: &clipped, rect: rect, lineScale: lineScale)
        drawLightSweep(in: &clipped, rect: rect)

        context.stroke(
            pane,
            with: .color(leadColor.opacity(leadLines ? 0.83 : 0.22)),
            lineWidth: max(0.8, lineScale * (leadLines ? 0.012 : 0.003))
        )
        context.stroke(
            pane,
            with: .color(Color.white.opacity(0.24 + highlight * 0.18)),
            lineWidth: max(0.3, lineScale * 0.0025)
        )
    }

    private func drawRecordedFacets(
        in context: inout GraphicsContext,
        rect: CGRect,
        lineScale: Double
    ) {
        for facet in recordedFacets where progress + 0.002 >= facet.revealProgress {
            let normalizedSize = (0.028 + facet.scale.clamped(to: 0.25...2.4) * 0.027)
            let center = facet.position.scaled(to: rect)
            let width = normalizedSize * rect.width
            let height = normalizedSize * rect.height * (facet.shape == .shard ? 1.45 : 1)
            let bounds = CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            )
            let path = recordedFacetPath(facet, in: bounds)
            let alpha = facet.opacity.clamped(to: 0.18...0.96)

            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        facet.color.opacity(alpha * 0.72),
                        facet.color.opacity(alpha),
                        Color.white.opacity(0.08 + facet.emission.clamped(to: 0...1) * 0.22)
                    ]),
                    startPoint: CGPoint(x: bounds.minX, y: bounds.maxY),
                    endPoint: CGPoint(x: bounds.maxX, y: bounds.minY)
                )
            )
            context.stroke(
                path,
                with: .color(leadColor.opacity(leadLines ? 0.78 : 0.18)),
                lineWidth: max(0.35, lineScale * (leadLines ? 0.0034 : 0.0012))
            )
            if facet.emission > 0.15, highlight > 0 {
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(facet.emission * highlight * 0.34)),
                    lineWidth: max(0.3, lineScale * 0.0017)
                )
            }
        }
    }

    private func recordedFacetPath(_ facet: RecordedLightFacet, in rect: CGRect) -> Path {
        if facet.shape == .circle {
            return Path(ellipseIn: rect)
        }

        let normalized: [CGPoint]
        switch facet.shape {
        case .triangle:
            normalized = [CGPoint(x: 0.50, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0.82)]
        case .quadrilateral:
            normalized = [CGPoint(x: 0.12, y: 0), CGPoint(x: 1, y: 0.18), CGPoint(x: 0.82, y: 1), CGPoint(x: 0, y: 0.72)]
        case .arc:
            normalized = [CGPoint(x: 0.06, y: 0.42), CGPoint(x: 0.43, y: 0), CGPoint(x: 1, y: 0.18), CGPoint(x: 0.72, y: 1), CGPoint(x: 0.18, y: 0.88)]
        case .shard:
            normalized = [CGPoint(x: 0.48, y: 0), CGPoint(x: 0.92, y: 0.67), CGPoint(x: 0.56, y: 1), CGPoint(x: 0.08, y: 0.57)]
        case .circle:
            normalized = []
        }

        let angle = facet.rotation
        let cosine = Foundation.cos(angle)
        let sine = Foundation.sin(angle)
        let transformed = normalized.map { point -> CGPoint in
            let x = point.x - 0.5
            let y = point.y - 0.5
            return CGPoint(
                x: rect.midX + (x * cosine - y * sine) * rect.width,
                y: rect.midY + (x * sine + y * cosine) * rect.height
            )
        }
        var path = Path()
        guard let first = transformed.first else { return path }
        path.move(to: first)
        for point in transformed.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func makePieces() -> [ProceduralGlassPiece] {
        let columns = 9
        let rows = 13
        var random = GlassSeededGenerator(seed: stableSeed)
        var vertices = Array(
            repeating: Array(repeating: CGPoint.zero, count: columns + 1),
            count: rows + 1
        )

        for row in 0...rows {
            for column in 0...columns {
                let edgeX = column == 0 || column == columns
                let edgeY = row == 0 || row == rows
                let jitterX = edgeX ? 0 : random.signedUnit() * 0.027
                let jitterY = edgeY ? 0 : random.signedUnit() * 0.020
                vertices[row][column] = CGPoint(
                    x: Double(column) / Double(columns) + jitterX,
                    y: Double(row) / Double(rows) + jitterY
                )
            }
        }

        var pieces: [ProceduralGlassPiece] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let topLeft = vertices[row][column]
                let topRight = vertices[row][column + 1]
                let bottomRight = vertices[row + 1][column + 1]
                let bottomLeft = vertices[row + 1][column]
                let split = random.unit() < 0.46
                let alternate = random.unit() < 0.5
                let polygons: [[CGPoint]]

                if split, alternate {
                    polygons = [[topLeft, topRight, bottomLeft], [topRight, bottomRight, bottomLeft]]
                } else if split {
                    polygons = [[topLeft, topRight, bottomRight], [topLeft, bottomRight, bottomLeft]]
                } else {
                    polygons = [[topLeft, topRight, bottomRight, bottomLeft]]
                }

                for polygon in polygons {
                    let center = polygon.center
                    let tone = random.unit()
                    let sample = theme.sample(at: center, noise: tone, seedPhase: seedPhase)
                    let revealAt = (sample.revealBase + random.unit() * sample.revealSpread).clamped(to: 0.025...0.95)
                    let colorOffset = Int(random.next() % 2)
                    pieces.append(
                        ProceduralGlassPiece(
                            points: polygon,
                            colorIndex: max(0, sample.colorIndex + colorOffset),
                            revealAt: revealAt,
                            tone: tone
                        )
                    )
                }
            }
        }

        // The keystone makes the 91–99% stage visually meaningful.
        if let index = pieces.indices.min(by: {
            pieces[$0].points.center.distance(to: CGPoint(x: 0.5, y: 0.48)) <
                pieces[$1].points.center.distance(to: CGPoint(x: 0.5, y: 0.48))
        }) {
            pieces[index].revealAt = 0.985
        }
        return pieces
    }

    private var stableSeed: UInt64 {
        UInt64(bitPattern: Int64(seed)) ^ theme.stableHash &* 0x9E37_79B9_7F4A_7C15
    }

    private var seedPhase: Double {
        Double((stableSeed >> 12) % 10_000) / 10_000
    }

    private func drawThemeMotif(in context: inout GraphicsContext, rect: CGRect, lineScale: Double) {
        let formation = smoothstep(edge0: 0.30, edge1: 0.72, value: progress)
        guard formation > 0.01 else { return }
        let width = max(0.55, lineScale * (leadLines ? 0.0056 : 0.0022))
        let alpha = formation * (strengthenedOutlines ? 0.82 : (leadLines ? 0.62 : 0.28))
        let stroke = leadLines ? leadColor.opacity(alpha) : Color.white.opacity(alpha)

        for motif in theme.motifPaths(seedPhase: seedPhase) {
            context.stroke(motif.path(in: rect), with: .color(stroke), lineWidth: width)
        }

        if theme == .fireworks || theme == .festival {
            drawFireworkRays(in: &context, rect: rect, lineWidth: width, alpha: alpha)
        }
    }

    private func drawFireworkRays(
        in context: inout GraphicsContext,
        rect: CGRect,
        lineWidth: Double,
        alpha: Double
    ) {
        let centers: [CGPoint] = theme == .festival
            ? [CGPoint(x: 0.20, y: 0.22), CGPoint(x: 0.82, y: 0.25)]
            : [CGPoint(x: 0.30, y: 0.31), CGPoint(x: 0.72, y: 0.39), CGPoint(x: 0.53, y: 0.18)]
        var rays = Path()
        for (centerIndex, center) in centers.enumerated() {
            let radius = centerIndex == 2 ? 0.11 : 0.15
            for ray in 0..<12 {
                let angle = Double(ray) * .pi / 6 + seedPhase * 0.3
                let inner = CGPoint(x: center.x + cos(angle) * radius * 0.28, y: center.y + sin(angle) * radius * 0.20)
                let outer = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius * 0.72)
                rays.move(to: inner.scaled(to: rect))
                rays.addLine(to: outer.scaled(to: rect))
            }
        }
        context.stroke(rays, with: .color(Color.white.opacity(alpha * 0.58)), lineWidth: lineWidth * 0.7)
    }

    private func drawLightSweep(in context: inout GraphicsContext, rect: CGRect) {
        guard highlight > 0.001 else { return }
        let travel = phase * 1.7 - 0.35
        let x = rect.minX + travel * rect.width
        var sweep = Path()
        sweep.move(to: CGPoint(x: x - rect.width * 0.18, y: rect.maxY))
        sweep.addLine(to: CGPoint(x: x + rect.width * 0.06, y: rect.maxY))
        sweep.addLine(to: CGPoint(x: x + rect.width * 0.34, y: rect.minY))
        sweep.addLine(to: CGPoint(x: x + rect.width * 0.10, y: rect.minY))
        sweep.closeSubpath()

        var light = context
        light.blendMode = .screen
        light.fill(
            sweep,
            with: .linearGradient(
                Gradient(colors: [.clear, Color.white.opacity(highlight * 0.20), .clear]),
                startPoint: CGPoint(x: x - rect.width * 0.18, y: rect.midY),
                endPoint: CGPoint(x: x + rect.width * 0.34, y: rect.midY)
            )
        )
    }
}

private struct ProceduralGlassPiece {
    let points: [CGPoint]
    let colorIndex: Int
    var revealAt: Double
    let tone: Double
}

// MARK: - Themes

private enum GlassTheme: Equatable {
    case sea, cloud, fireworks, goldfish, festival, window, memory

    init(id: String) {
        let value = id.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        switch value {
        case let value where value.contains("cloud") || value.contains("cumulonimbus") || value.contains("nimbus") || value.contains("kumo") || value.contains("雲"):
            self = .cloud
        case let value where value.contains("firework") || value.contains("hanabi") || value.contains("花火"):
            self = .fireworks
        case let value where value.contains("goldfish") || value.contains("kingyo") || value.contains("金魚"):
            self = .goldfish
        case let value where value.contains("festival") || value.contains("matsuri") || value.contains("祭"):
            self = .festival
        case let value where value.contains("window") || value.contains("mado") || value.contains("窓"):
            self = .window
        case let value where value.contains("memory") || value.contains("kioku") || value.contains("記憶"):
            self = .memory
        default:
            self = .sea
        }
    }

    var accessibilityName: String {
        switch self {
        case .sea: "海"
        case .cloud: "入道雲"
        case .fireworks: "花火"
        case .goldfish: "金魚"
        case .festival: "夏祭り"
        case .window: "夏の窓"
        case .memory: "夏の記憶"
        }
    }

    var stableHash: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in accessibilityName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    var defaultPalette: [Color] {
        switch self {
        case .sea:
            [Color(hex: 0x176B9C), Color(hex: 0x38B9C8), Color(hex: 0x8EDDE1), Color(hex: 0xEDF8E8), Color(hex: 0xF7C84B)]
        case .cloud:
            [Color(hex: 0x247BC1), Color(hex: 0x78C8E8), Color(hex: 0xF4F5E8), Color(hex: 0xC7B7DF), Color(hex: 0xF5CC58)]
        case .fireworks:
            [Color(hex: 0x152852), Color(hex: 0x5F3B8F), Color(hex: 0xE94A66), Color(hex: 0xF4B943), Color(hex: 0xF28EC1)]
        case .goldfish:
            [Color(hex: 0xE8462F), Color(hex: 0xF38A35), Color(hex: 0x2E91B3), Color(hex: 0x45A36B), Color(hex: 0xDFF4EC)]
        case .festival:
            [Color(hex: 0x17254D), Color(hex: 0xC9353D), Color(hex: 0xEF8537), Color(hex: 0xF4C951), Color(hex: 0x754487)]
        case .window:
            [Color(hex: 0x66BBD4), Color(hex: 0xEAF5EC), Color(hex: 0x7B66AE), Color(hex: 0xEFA7B6), Color(hex: 0xF2D56A)]
        case .memory:
            [Color(hex: 0x4C8FA8), Color(hex: 0xE49A6B), Color(hex: 0xDCC7E8), Color(hex: 0xF1D17D), Color(hex: 0x6DAE8D)]
        }
    }

    func sample(at point: CGPoint, noise: Double, seedPhase: Double) -> ThemeSample {
        switch self {
        case .sea: seaSample(point, noise: noise, seedPhase: seedPhase)
        case .cloud: cloudSample(point, noise: noise)
        case .fireworks: fireworksSample(point, noise: noise)
        case .goldfish: goldfishSample(point, noise: noise)
        case .festival: festivalSample(point, noise: noise)
        case .window: windowSample(point, noise: noise)
        case .memory: memorySample(point, noise: noise, seedPhase: seedPhase)
        }
    }

    func motifPaths(seedPhase: Double) -> [NormalizedMotifPath] {
        switch self {
        case .sea:
            return [
                .ellipse(center: CGPoint(x: 0.77, y: 0.19), radius: CGSize(width: 0.10, height: 0.075)),
                .wave(y: 0.43, amplitude: 0.012), .wave(y: 0.58, amplitude: 0.035),
                .wave(y: 0.70, amplitude: 0.028), .wave(y: 0.82, amplitude: 0.024)
            ]
        case .cloud:
            return [
                .ellipse(center: CGPoint(x: 0.30, y: 0.46), radius: CGSize(width: 0.17, height: 0.095)),
                .ellipse(center: CGPoint(x: 0.50, y: 0.40), radius: CGSize(width: 0.23, height: 0.15)),
                .ellipse(center: CGPoint(x: 0.69, y: 0.47), radius: CGSize(width: 0.17, height: 0.10)),
                .polyline([CGPoint(x: 0.08, y: 0.85), CGPoint(x: 0.08, y: 0.79), CGPoint(x: 0.18, y: 0.79), CGPoint(x: 0.18, y: 0.83), CGPoint(x: 0.30, y: 0.83), CGPoint(x: 0.30, y: 0.76), CGPoint(x: 0.40, y: 0.76), CGPoint(x: 0.40, y: 0.85), CGPoint(x: 0.92, y: 0.85)])
            ]
        case .fireworks:
            return [.ellipse(center: CGPoint(x: 0.30, y: 0.31), radius: CGSize(width: 0.15, height: 0.11)), .ellipse(center: CGPoint(x: 0.72, y: 0.39), radius: CGSize(width: 0.16, height: 0.12)), .wave(y: 0.79, amplitude: 0.018)]
        case .goldfish:
            return [
                .ellipse(center: CGPoint(x: 0.57, y: 0.48), radius: CGSize(width: 0.22, height: 0.13)),
                .polygon([CGPoint(x: 0.37, y: 0.48), CGPoint(x: 0.19, y: 0.35), CGPoint(x: 0.23, y: 0.58)]),
                .wave(y: 0.22, amplitude: 0.018),
                .ellipse(center: CGPoint(x: 0.77, y: 0.28), radius: CGSize(width: 0.035, height: 0.026)),
                .ellipse(center: CGPoint(x: 0.84, y: 0.19), radius: CGSize(width: 0.022, height: 0.017))
            ]
        case .festival:
            return [
                .polygon([CGPoint(x: 0.24, y: 0.38), CGPoint(x: 0.76, y: 0.38), CGPoint(x: 0.72, y: 0.45), CGPoint(x: 0.28, y: 0.45)]),
                .polygon([CGPoint(x: 0.33, y: 0.46), CGPoint(x: 0.43, y: 0.46), CGPoint(x: 0.40, y: 0.90), CGPoint(x: 0.34, y: 0.90)]),
                .polygon([CGPoint(x: 0.57, y: 0.46), CGPoint(x: 0.67, y: 0.46), CGPoint(x: 0.66, y: 0.90), CGPoint(x: 0.60, y: 0.90)]),
                .polyline([CGPoint(x: 0.16, y: 0.52), CGPoint(x: 0.84, y: 0.52)])
            ]
        case .window:
            return [
                .polyline([CGPoint(x: 0.5, y: 0.02), CGPoint(x: 0.5, y: 0.98)]),
                .polyline([CGPoint(x: 0.02, y: 0.55), CGPoint(x: 0.98, y: 0.55)]),
                .ellipse(center: CGPoint(x: 0.73, y: 0.29), radius: CGSize(width: 0.09, height: 0.07)),
                .polyline([CGPoint(x: 0.73, y: 0.36), CGPoint(x: 0.73, y: 0.54)]),
                .ellipse(center: CGPoint(x: 0.22, y: 0.73), radius: CGSize(width: 0.10, height: 0.08))
            ]
        case .memory:
            return [
                .ellipse(center: CGPoint(x: 0.50, y: 0.48), radius: CGSize(width: 0.31, height: 0.23)),
                .ellipse(center: CGPoint(x: 0.50, y: 0.48), radius: CGSize(width: 0.18, height: 0.13)),
                .wave(y: 0.34 + seedPhase * 0.08, amplitude: 0.07),
                .wave(y: 0.70 - seedPhase * 0.06, amplitude: 0.05)
            ]
        }
    }

    private func seaSample(_ p: CGPoint, noise: Double, seedPhase: Double) -> ThemeSample {
        if p.inEllipse(center: CGPoint(x: 0.77, y: 0.19), rx: 0.11, ry: 0.085) { return .init(4, 0.48, 0.28) }
        let wave = 0.49 + sin((p.x * 2.2 + seedPhase) * .pi * 2) * 0.035
        if abs(p.y - wave) < 0.075 { return .init(noise > 0.55 ? 3 : 2, 0.20, 0.40) }
        return p.y < 0.43 ? .init(noise > 0.72 ? 3 : 0, 0.08, 0.42) : .init(noise > 0.52 ? 1 : 0, 0.12, 0.50)
    }

    private func cloudSample(_ p: CGPoint, noise: Double) -> ThemeSample {
        let cloud = p.inEllipse(center: CGPoint(x: 0.30, y: 0.46), rx: 0.18, ry: 0.10)
            || p.inEllipse(center: CGPoint(x: 0.50, y: 0.39), rx: 0.24, ry: 0.16)
            || p.inEllipse(center: CGPoint(x: 0.69, y: 0.47), rx: 0.18, ry: 0.11)
        if cloud { return .init(noise > 0.76 ? 3 : 2, 0.34, 0.42) }
        if p.y > 0.82 { return .init(3, 0.28, 0.48) }
        return .init(noise > 0.8 ? 4 : (noise > 0.46 ? 1 : 0), 0.07, 0.46)
    }

    private func fireworksSample(_ p: CGPoint, noise: Double) -> ThemeSample {
        let bursts = [(CGPoint(x: 0.30, y: 0.31), 0.15), (CGPoint(x: 0.72, y: 0.39), 0.16), (CGPoint(x: 0.53, y: 0.18), 0.11)]
        for (index, burst) in bursts.enumerated() {
            let distance = p.distance(to: burst.0)
            if distance < burst.1 { return .init(2 + (index + Int(noise * 2)) % 3, 0.38, 0.42) }
            if p.y > 0.72, abs(p.x - burst.0.x) < 0.05 { return .init(2 + index % 3, 0.44, 0.42) }
        }
        return .init(noise > 0.82 ? 1 : 0, 0.06, 0.54)
    }

    private func goldfishSample(_ p: CGPoint, noise: Double) -> ThemeSample {
        let body = p.inEllipse(center: CGPoint(x: 0.57, y: 0.48), rx: 0.23, ry: 0.14)
        let tail = p.inTriangle(CGPoint(x: 0.38, y: 0.48), CGPoint(x: 0.18, y: 0.34), CGPoint(x: 0.23, y: 0.59))
        if body || tail { return .init(noise > 0.5 ? 1 : 0, 0.38, 0.42) }
        if p.y > 0.69, (sin(p.x * 31) + cos(p.y * 19)) > 0.3 { return .init(3, 0.26, 0.44) }
        return .init(noise > 0.8 ? 4 : 2, 0.07, 0.52)
    }

    private func festivalSample(_ p: CGPoint, noise: Double) -> ThemeSample {
        let beam = p.y > 0.37 && p.y < 0.47 && p.x > 0.23 && p.x < 0.77
        let posts = p.y > 0.44 && p.y < 0.91 && ((p.x > 0.33 && p.x < 0.43) || (p.x > 0.57 && p.x < 0.67))
        let lantern = p.y > 0.48 && p.y < 0.62 && Int(p.x * 10).isMultiple(of: 2)
        if beam || posts { return .init(noise > 0.68 ? 2 : 1, 0.38, 0.40) }
        if lantern { return .init(noise > 0.5 ? 3 : 2, 0.31, 0.38) }
        return .init(noise > 0.8 ? 4 : 0, 0.07, 0.52)
    }

    private func windowSample(_ p: CGPoint, noise: Double) -> ThemeSample {
        if p.inEllipse(center: CGPoint(x: 0.73, y: 0.29), rx: 0.10, ry: 0.075) { return .init(4, 0.46, 0.30) }
        if p.inEllipse(center: CGPoint(x: 0.22, y: 0.73), rx: 0.11, ry: 0.09) { return .init(noise > 0.5 ? 3 : 2, 0.42, 0.36) }
        let curtain = p.x < 0.16 + sin(p.y * 18) * 0.035 || p.x > 0.84 + sin(p.y * 17) * 0.035
        if curtain { return .init(noise > 0.55 ? 3 : 1, 0.24, 0.44) }
        return .init(noise > 0.72 ? 1 : 0, 0.07, 0.48)
    }

    private func memorySample(_ p: CGPoint, noise: Double, seedPhase: Double) -> ThemeSample {
        let center = CGPoint(x: 0.47 + seedPhase * 0.08, y: 0.49 - seedPhase * 0.05)
        let ring = p.distance(to: center)
        let wave = Foundation.sin(Double(p.x + p.y) * 9 + seedPhase * 6)
        let bands = Int((ring * 18 + wave).magnitude)
        return .init((bands + Int(noise * 3)) % 5, 0.10 + ring * 0.38, 0.48)
    }
}

private struct ThemeSample {
    let colorIndex: Int
    let revealBase: Double
    let revealSpread: Double

    init(_ colorIndex: Int, _ revealBase: Double, _ revealSpread: Double) {
        self.colorIndex = colorIndex
        self.revealBase = revealBase
        self.revealSpread = revealSpread
    }
}

private enum NormalizedMotifPath {
    case ellipse(center: CGPoint, radius: CGSize)
    case polygon([CGPoint])
    case polyline([CGPoint])
    case wave(y: Double, amplitude: Double)

    func path(in rect: CGRect) -> Path {
        switch self {
        case let .ellipse(center, radius):
            return Path(ellipseIn: CGRect(
                x: rect.minX + (center.x - radius.width) * rect.width,
                y: rect.minY + (center.y - radius.height) * rect.height,
                width: radius.width * 2 * rect.width,
                height: radius.height * 2 * rect.height
            ))
        case let .polygon(points):
            return StainedGlassShape(points: points).path(in: rect)
        case let .polyline(points):
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: first.scaled(to: rect))
            for point in points.dropFirst() { path.addLine(to: point.scaled(to: rect)) }
            return path
        case let .wave(y, amplitude):
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + y * rect.height))
            for step in 1...24 {
                let x = Double(step) / 24
                let waveY = y + sin(x * .pi * 4) * amplitude
                path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY + waveY * rect.height))
            }
            return path
        }
    }
}

// MARK: - Determinism and geometry

private struct GlassSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xA076_1D64_78BD_642F : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992
    }

    mutating func signedUnit() -> Double { unit() * 2 - 1 }
}

private extension CGPoint {
    nonisolated func scaled(to rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    func distance(to other: CGPoint) -> Double {
        hypot(x - other.x, y - other.y)
    }

    func inEllipse(center: CGPoint, rx: Double, ry: Double) -> Bool {
        pow((x - center.x) / rx, 2) + pow((y - center.y) / ry, 2) <= 1
    }

    func inTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let d1 = signedArea(self, a, b)
        let d2 = signedArea(self, b, c)
        let d3 = signedArea(self, c, a)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }

    private func signedArea(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Double {
        (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
    }
}

private extension Array where Element == CGPoint {
    var center: CGPoint {
        guard !isEmpty else { return .zero }
        let sum = reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: sum.x / Double(count), y: sum.y / Double(count))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private func smoothstep(edge0: Double, edge1: Double, value: Double) -> Double {
    guard edge0 != edge1 else { return value < edge0 ? 0 : 1 }
    let amount = ((value - edge0) / (edge1 - edge0)).clamped(to: 0...1)
    return amount * amount * (3 - 2 * amount)
}

#Preview("SUN GLASS themes") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
            ForEach(["海", "入道雲", "花火", "金魚", "夏祭り", "夏の窓", "夏の記憶"], id: \.self) { theme in
                GlassArtworkView(themeID: theme, seed: 20260714, progress: 0.72)
                    .frame(height: 220)
                    .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
}
