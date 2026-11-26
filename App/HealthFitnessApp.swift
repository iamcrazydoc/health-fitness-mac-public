import SwiftUI

@main
struct HealthFitnessApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var recovery = RecoveryModel()

    var body: some Scene {
        WindowGroup("Health and Fitness", id: "main") {
            TabView {
                ContentView().tabItem { Label("Overview", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                TrainingView().tabItem { Label("Training", systemImage: "calendar") }
                RecoveryView().tabItem { Label("Recovery", systemImage: "cross.case") }
            }
                .environmentObject(model)
                .environmentObject(recovery)
                .frame(minWidth: 760, minHeight: 640)
                .onAppear { model.start() }
                .task {
                    // Weekly PubMed check; looks every 6 hours whether a week has passed.
                    while !Task.isCancelled {
                        await recovery.checkLiterature()
                        try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
                    }
                }
                .onOpenURL { model.handle(url: $0) }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Open Dashboard") { if let u = Profile.current.dashboardURL { NSWorkspace.shared.open(u) } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(Profile.current.dashboardURL == nil)
            }
        }

        Settings {
            SettingsView().environmentObject(model)
        }

        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: "figure.run.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
