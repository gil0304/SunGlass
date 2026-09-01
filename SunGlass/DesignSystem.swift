import SwiftUI

enum SunGlassStyle {
    static let ink = Color(red: 0.025, green: 0.075, blue: 0.065)
    static let forest = Color(red: 0.035, green: 0.15, blue: 0.12)
    static let cream = Color(red: 0.96, green: 0.95, blue: 0.89)
    static let lime = Color(red: 0.84, green: 1.0, blue: 0.38)
    static let amber = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let cyan = Color(red: 0.20, green: 0.83, blue: 0.82)
    static let coral = Color(red: 1.0, green: 0.38, blue: 0.29)
    static let violet = Color(red: 0.56, green: 0.43, blue: 0.94)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold)
    }
}

struct SunGlassBackground: View {
    var body: some View {
        SunGlassStyle.ink
            .ignoresSafeArea()
    }
}

struct SunGlassWordmark: View {
    var compact = false

    var body: some View {
        Image(systemName: "circle.hexagongrid.fill")
            .font(.system(size: compact ? 19 : 24, weight: .semibold))
            .foregroundStyle(SunGlassStyle.cream)
            .accessibilityLabel("SUN GLASS")
    }
}

struct SunGlassPrimaryButtonStyle: ButtonStyle {
    var tint: Color = SunGlassStyle.lime
    var foreground: Color = SunGlassStyle.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(foreground)
            .background(tint.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SunGlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(SunGlassStyle.cream.opacity(configuration.isPressed ? 0.6 : 1))
            .background(.white.opacity(configuration.isPressed ? 0.11 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LightProgressBar: View {
    let value: Double
    var tint: Color = SunGlassStyle.lime
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("着色の進み")
        .accessibilityValue("\(Int(value * 100))パーセント")
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .init(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
