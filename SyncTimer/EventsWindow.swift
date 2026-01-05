import SwiftUI
import Combine
/// Compact “tool” window for event creation & browsing.
/// If `timerID` is provided, you can later scope events to that timer.


struct EventsWindow: View {
    
        // Sheet state (if not already declared here)
    @EnvironmentObject private var appSettings: AppSettings

    // Value-scene binding from WindowGroup(for: UUID.self)
    @Binding var timerID: UUID?
    @State private var events: [Event] = []
    @State private var eventMode: EventMode = .stop
    @State private var isCounting: Bool = false
    @State private var isPaused: Bool = false
    @StateObject private var cueStore = CueLibraryStore.shared

    var body: some View {
        VStack(spacing: 8) {
            // Top control bar: cycle mode & add events
            EventsBar(
                            events: $events,
                            eventMode: $eventMode,
                            isPaused: isPaused,                       // NEW: gate opening
                            unsavedChanges: hasUnsaved,               // NEW: red dot if true
                            onOpenCueSheets: nil,
                            isCounting: isCounting,
                            onAddStop: {
                                let t = (events.last?.fireTime ?? 0) + 5
                                events.append(.stop(StopEvent(eventTime: t, duration: 2)))
                            },
                            onAddCue: {
                                let t = (events.last?.fireTime ?? 0) + 5
                                events.append(.cue(CueEvent(cueTime: t)))
                            },
                            onAddRestart: {
                                let t = (events.last?.fireTime ?? 0) + 5
                                events.append(.restart(RestartEvent(restartTime: t)))
                        },
                        cueSheetAccent: appSettings.flashColor
                        )
                        .frame(height: 64)
                        .padding(.horizontal, 8)

            // Existing carousel renderer from your codebase
            EventsCarousel(events: $events, isCounting: isCounting)
                .frame(minHeight: 180)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
                .frame(minWidth: 420, minHeight: 320)
                .navigationTitle("Events")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button { events.removeAll() } label: { Label("Clear", systemImage: "trash") }
                    }
                }
                // When a CueSheet is loaded, map to your Event model here
                .onReceive(NotificationCenter.default.publisher(for: .didLoadCueSheet)) { note in
                    guard let sheet = note.object as? CueSheet else { return }
                    let sorted = sheet.events.sorted { $0.at < $1.at }
                    // Map to your enum with associated values
                    self.events = sorted.map { e in
                        switch e.kind {
                        case .cue:
                            return .cue(CueEvent(cueTime: e.at))
                        case .stop:
                            return .stop(StopEvent(eventTime: e.at, duration: e.holdSeconds ?? 0))
                        case .restart:
                            return .restart(RestartEvent(restartTime: e.at))
                        default:
                            // Safety fallback if new kinds are added; treat as cue.
                            return .cue(CueEvent(cueTime: e.at))
                        }
                    }
                }
                }
        
    // MARK: - Dirty state for dot (wire to your editor state)
       private var hasUnsaved: Bool {
            // TODO: return true when current timer’s event list differs from the loaded sheet
            false
        }
}
// Minimal placeholder so you can compile/run now.
// Replace this sheet with your full library UI (XML import/export, folders, tags, etc.).
private struct CueSheetsMediumDetentPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).frame(width: 36, height: 5).opacity(0.2)
            Text("Cue Sheets").font(.headline)
            Text("Long-press the STOP/CUE/RESTART button (paused only) to open this sheet.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding()
    }
}

