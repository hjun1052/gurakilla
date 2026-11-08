import SwiftUI

@main
struct GuraKillaApp: App {
    @State private var model = AppModel()

    init() { ScanReport.runIfRequested() }

    var body: some Scene {
        Window("GuraKilla", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 540)
                .task { model.start() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { Task { await model.scan() } }
                    .keyboardShortcut("r")
            }
            CommandMenu("Actions") {
                Button("Quit Selected") { model.quitSelected() }
                    .keyboardShortcut("q", modifiers: [.command, .shift])
                    .disabled(model.selection.isEmpty)
                Button("Quit All Detected") { model.quitAll() }
                Divider()
                Button("Manage Startup…") { model.showStartupManager = true }
                Button("Restore Settings…") { model.showRestore = true }
                Button("Audit Log") { model.showAuditLog = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
