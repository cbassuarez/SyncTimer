import SwiftUI

/// iPad 2-pane Command Center that switches between Sync / Events / Settings.
/// Uses existing ContentView and SettingsWindow to avoid missing initializers.
struct CommandCenter2Pane: View {
    @State private var selection: SectionKind = .sync

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationTitle("SyncTimer")
        } detail: {
            // Detail = the main content column
            switch selection {
            case .sync:
                ContentView()
                    .navigationTitle("Sync")
            case .events:
                // TODO: replace with your real EventsWindow(...) call when you know its params
                ContentView()
                    .navigationTitle("Events")
                    .padding(20)
            case .settings:
                SettingsWindow()
                    .navigationTitle("Settings")
                    .padding(20)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar (simple buttons; no List(selection:) on iOS)
private struct Sidebar: View {
    @Binding var selection: SectionKind

    var body: some View {
        List {
            Section("Views") {
                Button {
                    selection = .sync
                } label: {
                    Label("Sync", systemImage: "clock")
                }
                Button {
                    selection = .events
                } label: {
                    Label("Events", systemImage: "sparkles")
                }
                Button {
                    selection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private enum SectionKind: Hashable {
    case sync, events, settings
}

// Stub to satisfy AdaptiveRoot references (if any)
struct CommandCenter3Pane: View {
    var body: some View { CommandCenter2Pane() }
}
