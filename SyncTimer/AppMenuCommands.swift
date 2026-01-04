import SwiftUI

/// Global app commands (iPad + Mac idiom) for desktop-class flow
struct AppMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Timer Window") {
                openWindow(id: "timer")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandMenu("Window") {
            Button("Show Events") {
                openWindow(id: "events", value: UUID())
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("Settings") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
