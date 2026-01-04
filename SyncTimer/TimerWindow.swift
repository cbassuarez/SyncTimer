import SwiftUI

/// Primary iPad window: runs the main timer UI in a resizable window
struct TimerWindow: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings
    @Environment(\.openWindow) private var openWindow

    /// Optional model identifier if you later multi-instance timers
    let timerID: UUID?

    var body: some View {
        // Reuse your existing content (keeps 100% of current behavior)
        ContentView()
            .frame(minWidth: 640, minHeight: 480)   // a sane resizable canvas
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        openWindow(id: "events", value: timerID ?? UUID())
                    } label: {
                        Label("Events", systemImage: "list.bullet.rectangle")
                    }
                    .keyboardShortcut("e", modifiers: [.command])

                    Button {
                        openWindow(id: "settings")
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: [.command])
                }
            }
    }
}
