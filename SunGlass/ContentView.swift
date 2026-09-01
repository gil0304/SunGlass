import SwiftUI

struct ContentView: View {
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @AppStorage("didOfferInitialCalibration") private var didOfferInitialCalibration = false
    @State private var showInitialCalibration = false

    var body: some View {
        Group {
            if didCompleteOnboarding {
                RootTabView()
            } else {
                OnboardingView(isComplete: $didCompleteOnboarding)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: didCompleteOnboarding) {
            guard didCompleteOnboarding, !didOfferInitialCalibration else { return }
            showInitialCalibration = true
        }
        .sheet(isPresented: $showInitialCalibration, onDismiss: {
            // Camera permission may be declined. Do not trap the user in setup;
            // calibration remains available from Settings at any time.
            didOfferInitialCalibration = true
        }) {
            CalibrationGuideView {
                didOfferInitialCalibration = true
            }
        }
    }
}

private struct RootTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: 0) {
                HomeView()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel("作品")
            }
            Tab(value: 1) {
                LightJournalView()
            } label: {
                Image(systemName: "calendar")
                    .accessibilityLabel("記録")
            }
            Tab(value: 2) {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("設定")
            }
        }
        .tint(SunGlassStyle.lime)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
}
