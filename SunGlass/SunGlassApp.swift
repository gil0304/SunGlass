//
//  SunGlassApp.swift
//  SunGlass
//
//  Created by 落合遼梧 on 2026/07/14.
//

import SwiftUI

@main
struct SunGlassApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onOpenURL { url in
                    _ = store.receiveDeepLink(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshProjectStatuses() }
                }
                .task {
                    while !Task.isCancelled {
                        store.refreshProjectStatuses()
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
    }
}
