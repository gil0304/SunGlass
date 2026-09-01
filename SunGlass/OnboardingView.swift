import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var page = 0

    private let pages = [
        OnboardingPage(
            title: "光を集める",
            body: nil,
            symbol: "sun.max.fill"
        ),
        OnboardingPage(
            title: "光が作品になる",
            body: nil,
            symbol: "circle.lefthalf.filled"
        ),
        OnboardingPage(
            title: "映像は残さない",
            body: "明るさと色だけを端末に保存します。",
            symbol: "hand.raised.fill"
        )
    ]

    var body: some View {
        ZStack {
            SunGlassBackground()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        isComplete = true
                    }
                } label: {
                    Image(systemName: page == pages.count - 1 ? "checkmark" : "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SunGlassPrimaryButtonStyle())
                .accessibilityLabel(page == pages.count - 1 ? "はじめる" : "次へ")
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct OnboardingPage {
    let title: String
    let body: String?
    let symbol: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: page.symbol)
                .font(.system(size: 88, weight: .light))
                .foregroundStyle(SunGlassStyle.lime)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(page.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(SunGlassStyle.cream)
                .multilineTextAlignment(.center)

            if let body = page.body {
                Text(body)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(SunGlassStyle.cream.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}

#Preview {
    OnboardingView(isComplete: .constant(false))
}
