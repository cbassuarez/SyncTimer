import SwiftUI
import WatchConnectivity
import WatchKit

// MARK: - Watch UI
struct WatchMainView: View {
    @ObservedObject private var cm = ConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var current: TimerMessage?
    @State private var lastUpdated: Date?

    var body: some View {
        NavigationStack {
            GlanceTimerView(
                message: current,
                lastUpdated: lastUpdated,
                onCommand: sendCommand(_:),
                onRefresh: loadFromContext
            )
        }
        .onReceive(cm.$incoming.compactMap { $0 }) { msg in
            current = msg
            lastUpdated = Date()
        }
        .onAppear { loadFromContext() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { loadFromContext() }
        }
    }

    private func loadFromContext() {
        if let data = WCSession.default.receivedApplicationContext["timer"] as? Data,
           let msg = try? JSONDecoder().decode(TimerMessage.self, from: data) {
            current = msg
            lastUpdated = Date()
        }
    }

    private func sendCommand(_ command: ControlRequest.Command) {
        ConnectivityManager.shared.sendCommand(command)
    }
}

// MARK: - Glance
private struct GlanceTimerView: View {
    let message: TimerMessage?
    let lastUpdated: Date?
    let onCommand: (ControlRequest.Command) -> Void
    let onRefresh: () -> Void

    private var isCounting: Bool {
        guard let message else { return false }
        return message.phase == "running" || message.phase == "countdown"
    }

    private var controlsEnabled: Bool {
        guard let message else { return false }
        if let enabled = message.controlsEnabled { return enabled }
        if message.role == "parent" { return !(message.parentLockEnabled ?? false) }
        return false
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                header
                heroTimer
                controlRail
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            NavigationLink {
                SyncStatusView(message: message, lastUpdated: lastUpdated, onRefresh: onRefresh)
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .padding(.trailing, 6)
        }
        .onAppear(perform: onRefresh)
    }

    private var header: some View {
        HStack(spacing: 6) {
            SyncLampView(message: message)
            Text(headerTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            LiveIndicatorView(isLive: isCounting)
        }
    }

    private var headerTitle: String {
        guard let message else { return "Sync • Off" }
        let role = roleLabel(for: message.role)
        let method = methodLabel(for: message.link)
        return "\(role) • \(method)"
    }

    private var heroTimer: some View {
        NavigationLink {
            TimerDetailView(message: message, lastUpdated: lastUpdated)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Text("88:88:88.88")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .opacity(0)
                    Text(displayMainTime)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isCountdown ? Color.red : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var controlRail: some View {
        VStack(spacing: 8) {
            Button {
                playClick()
                onCommand(isCounting ? .stop : .start)
            } label: {
                Label(isCounting ? "Stop" : "Start", systemImage: isCounting ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controlsEnabled)

            Button {
                playClick()
                onCommand(.reset)
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isCounting || !controlsEnabled)
            .opacity(isCounting || !controlsEnabled ? 0.5 : 1.0)
        }
        .font(.footnote.weight(.semibold))
        .padding(10)
        .glassPanel()
    }

    private var displayMainTime: String {
        guard let message else { return "--:--.--" }
        if let formatted = message.formattedMainTime { return formatted }
        let preferHours = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")
        return formatTimerString(message.remaining, alwaysShowHours: preferHours)
    }

    private var isCountdown: Bool {
        message?.phase == "countdown"
    }
}

// MARK: - Detail
private struct TimerDetailView: View {
    let message: TimerMessage?
    let lastUpdated: Date?

    private var isCountdown: Bool { message?.phase == "countdown" }

    var body: some View {
        VStack(spacing: 10) {
            Text(mainTimeString)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isCountdown ? Color.red : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(isCountdown ? "Countdown" : "Stopwatch")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let sub = message?.formattedSubTime {
                Text(sub)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var mainTimeString: String {
        guard let message else { return "--:--.--" }
        if let formatted = message.formattedMainTime { return formatted }
        let preferHours = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")
        return formatTimerString(message.remaining, alwaysShowHours: preferHours)
    }
}

// MARK: - Sync/Status
private struct SyncStatusView: View {
    let message: TimerMessage?
    let lastUpdated: Date?
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                SyncLampView(message: message)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }

            statusRow(title: "Role", value: roleLabel(for: message?.role))
            statusRow(title: "Method", value: methodLabel(for: message?.link))
            statusRow(title: "Lock", value: lockText)

            if let lastUpdated {
                statusRow(title: "Last Updated", value: lastUpdated.formatted(date: .omitted, time: .standard))
            }

            Spacer()
        }
        .padding()
        .onAppear(perform: onRefresh)
    }

    private var statusText: String {
        switch message?.syncLamp {
        case "green": return "Connected"
        case "amber": return "Connecting"
        case "red": return "Off"
        default: return "Unknown"
        }
    }

    private var lockText: String {
        guard let message else { return "Unknown" }
        if message.parentLockEnabled == true { return "Locked" }
        if message.controlsEnabled == false { return "Locked" }
        return "Unlocked"
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.semibold))
        }
    }
}

// MARK: - Small components
private struct SyncLampView: View {
    let message: TimerMessage?

    var body: some View {
        Circle()
            .fill(lampColor)
            .frame(width: 8, height: 8)
    }

    private var lampColor: Color {
        switch message?.syncLamp {
        case "green": return .green
        case "amber": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

private struct LiveIndicatorView: View {
    let isLive: Bool

    var body: some View {
        Group {
            if isLive {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            } else {
                Color.clear.frame(width: 32, height: 12)
            }
        }
    }
}

// MARK: - Styling helpers
private extension View {
    @ViewBuilder
    func glassPanel() -> some View {
        if #available(watchOS 26.0, *) {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        } else {
            self
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private func roleLabel(for role: String?) -> String {
    switch role {
    case "parent": return "Parent"
    case "child": return "Child"
    default: return "Sync"
    }
}

private func methodLabel(for link: String?) -> String {
    switch link {
    case "nearby": return "Nearby"
    case "bonjour": return "Bonjour"
    case "network": return "Network"
    case "unreachable": return "Off"
    default: return "Unknown"
    }
}

private func playClick() {
    WKInterfaceDevice.current().play(.click)
}

/// Matches TimerCard's formatting (HH:MM:SS.CC or MM:SS.CC).
private func formatTimerString(_ t: TimeInterval, alwaysShowHours: Bool) -> String {
    let v = abs(t)
    let cs = Int((v * 100).rounded())
    let h  = cs / 360_000
    let m  = (cs / 6_000) % 60
    let s  = (cs / 100) % 60
    let c  = cs % 100

    if alwaysShowHours || v >= 3600.0 {
        return String(format: "%02d:%02d:%02d.%02d", h, m, s, c)
    } else {
        let mm = cs / 6_000
        return String(format: "%02d:%02d.%02d", mm, s, c)
    }
}
