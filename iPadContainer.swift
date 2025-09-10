// New file suggestion: iPadContainer.swift
import SwiftUI

enum iPadSection: Hashable, CaseIterable {
    case timer, events, connect, about
    var title: String {
        switch self {
        case .timer:   return "Timer"
        case .events:  return "Events"
        case .connect: return "Connect"
        case .about:   return "About"
        }
    }
    var icon: String {
        switch self {
        case .timer:   return "timer"
        case .events:  return "list.bullet.rectangle"
        case .connect: return "antenna.radiowaves.left.and.right"
        case .about:   return "info.circle"
        }
    }
}

struct iPadContainer: View {
    @EnvironmentObject private var app: AppSettings
    @EnvironmentObject private var sync: SyncSettings

    @State private var selection: iPadSection? = .timer
    @State private var mainMode: ViewMode = .sync
    @State private var settingsPage: Int = 0
    @State private var showSettingsInspector = false

    var body: some View {
        NavigationSplitView(preferredCompactColumn: .sidebar) {
            // Sidebar
            List(iPadSection.allCases, selection: $selection) {
                ForEach(iPadSection.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section as iPadSection?)
                }
            }
            .navigationTitle("SyncTimer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettingsInspector.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        } content: {
            // Center column – main content
            Group {
                switch selection {
                case .timer, .none:
                    ContentForTimer(mainMode: $mainMode)
                case .events:
                    ContentForEvents(mainMode: $mainMode)
                case .connect:
                    ContentForConnect()
                case .about:
                    AboutPage()
                }
            }
            .navigationTitle(selection?.title ?? "Timer")
        } detail: {
            // Inspector column – peers / lobby etc.
            InspectorPane(selection: selection)
        }
        // iPadOS 16+ inspector panel (slides on the right)
        .inspector(isPresented: $showSettingsInspector) {
            SettingsPagerCard(
                page: Binding(get: { settingsPage }, set: { settingsPage = $0 }),
                editingTarget: .constant(nil),
                inputText: .constant(""),
                isEnteringField: .constant(false),
                showBadPortError: .constant(false)
            )
            .environmentObject(app)
            .environmentObject(sync)
            .frame(minWidth: 320)
        }
    }
}

// MARK: - Center column pages

private struct ContentForTimer: View {
    @EnvironmentObject private var app: AppSettings
    @EnvironmentObject private var sync: SyncSettings
    @Binding var mainMode: ViewMode

    var body: some View {
        // Reuse your existing MainScreen, but let it breathe horizontally
        MainScreen(parentMode: $mainMode, showSettings: .constant(false))
            .padding(.horizontal, 12)
            .toolbar {
                RoleAndSyncToolbar()
            }
    }
}

private struct ContentForEvents: View {
    @EnvironmentObject private var app: AppSettings
    @EnvironmentObject private var sync: SyncSettings
    @State private var mainMode: ViewMode = .stop

    var body: some View {
        // Drive MainScreen into .stop to emphasize event editing
        MainScreen(parentMode: $mainMode, showSettings: .constant(false))
            .onAppear { mainMode = .stop }
            .toolbar {
                RoleAndSyncToolbar()
            }
    }
}

private struct ContentForConnect: View {
    @EnvironmentObject private var app: AppSettings
    @EnvironmentObject private var sync: SyncSettings
    @State private var page = 2
    var body: some View {
        SettingsPagerCard(
            page: $page,
            editingTarget: .constant(nil),
            inputText: .constant(""),
            isEnteringField: .constant(false),
            showBadPortError: .constant(false)
        )
    }
}

// MARK: - Inspector column

private struct InspectorPane: View {
    @EnvironmentObject private var app: AppSettings
    @EnvironmentObject private var sync: SyncSettings
    let selection: iPadSection?

    var body: some View {
        VStack(spacing: 12) {
            if selection == .connect || sync.connectionMethod == .bonjour {
                // Show live lobby / peers
                LobbyView()
                    .environmentObject(sync)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding()
            } else {
                // Show a compact events list as an inspector
                EventsQuickInspector()
            }
        }
        .navigationTitle("Inspector")
        .toolbar {
            RoleAndSyncToolbar()
        }
    }
}

// Small inspector that mirrors your carousel in a list form
private struct EventsQuickInspector: View {
    @EnvironmentObject private var app: AppSettings
    @EnvironmentObject private var sync: SyncSettings
    @State private var mainMode: ViewMode = .stop
    @State private var events: [Event] = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Upcoming Events")
                .font(.headline)
            List {
                ForEach(events.indices, id: \.self) { i in
                    switch events[i] {
                    case .stop(let s):
                        Label("Stop at \(s.eventTime.formattedCS)", systemImage: "pause.circle")
                    case .cue(let c):
                        Label("Cue at \(c.cueTime.formattedCS)", systemImage: "bolt.circle")
                    case .restart(let r):
                        Label("Restart at \(r.restartTime.formattedCS)", systemImage: "arrow.clockwise.circle")
                    }
                }
            }
        }
        .padding()
    }
}

// Toolbar shared between center + inspector
private struct RoleAndSyncToolbar: ToolbarContent {
    @EnvironmentObject private var sync: SyncSettings
    @EnvironmentObject private var app: AppSettings

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Role toggle
            Button {
                sync.role = (sync.role == .parent ? .child : .parent)
            } label: {
                Label(sync.role == .parent ? "Parent" : "Child",
                      systemImage: "person.2.circle")
            }

            // Sync toggle
            Button {
                // reuse your existing toggle logic by calling into MainScreen or a shared method
                // You can also expose a small helper in SyncSettings if you prefer.
                if sync.isEnabled {
                    if sync.role == .parent { sync.stopParent() } else { sync.stopChild() }
                    sync.isEnabled = false
                } else {
                    if sync.role == .parent { sync.startParent() } else { sync.startChild() }
                    sync.isEnabled = true
                }
            } label: {
                Label(sync.isEnabled ? "Stop" : "Sync",
                      systemImage: sync.isEstablished ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
            }
        }
    }
}
