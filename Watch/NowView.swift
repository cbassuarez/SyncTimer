import SwiftUI
import Combine

struct WatchNowRenderModel {
    let formattedMain: String
    let phaseLabel: String
    let isStale: Bool
    let stopLine: String?
    let canStartStop: Bool
    let canReset: Bool
    let lockHint: String?
    let linkIconName: String?
    let accent: Color
}

// MARK: - Drift-free NowView with .CC formatting (uses monotonic systemUptime)
struct NowView: View {
    @EnvironmentObject private var appSettings: AppSettings

    // Raw snapshot payload
    @State private var phaseStr: String = "idle"      // "idle" | "countdown" | "running" | "paused"
    @State private var snapMain: TimeInterval = 0     // value from the last snapshot
    @State private var snapStop: TimeInterval = 0
    @State private var stopActive: Bool = false

    // Local integration baseline (set on each snapshot)
    @State private var baseMain: TimeInterval = 0
    @State private var baseStop: TimeInterval = 0
    @State private var baseT0  : TimeInterval = ProcessInfo.processInfo.systemUptime
    @State private var vMain   : Double = 0.0         // seconds advanced per second (+1, -1, or 0)
    @State private var vStop   : Double = 0.0         // -1 while a Stop is active, else 0

    // Freshness & velocity estimation
    @State private var prevSnapMain: TimeInterval = 0
    @State private var prevSnapT   : TimeInterval = 0
    @State private var lastSnapT   : TimeInterval = 0
    @State private var isStale     : Bool = true

    // Display values (updated by a 20 Hz ticker)
    @State private var displayMain : TimeInterval = 0
    @State private var displayStop : TimeInterval = 0

    @State private var latestMessage: TimerMessage?

    // Tickers
    private let staleTick  = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    private let renderTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect() // 20 Hz

    // User preference: show hours when enabled; otherwise auto (>=1h shows hours)
    @State private var preferHours: Bool = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")

    private var isCounting: Bool { phaseStr == "running" || phaseStr == "countdown" }

    var body: some View {
        let renderModel = makeRenderModel()
        let detailsModel = makeDetailsModel()

        TabView {
            WatchFacePage(renderModel: renderModel)
            WatchDetailsPage(
                renderModel: renderModel,
                detailsModel: detailsModel
            )
            WatchControlsPage(
                renderModel: renderModel,
                startStop: { ConnectivityManager.shared.sendCommand(isCounting ? .stop : .start) },
                reset: { if !isCounting { ConnectivityManager.shared.sendCommand(.reset) } }
            )
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .tint(appSettings.flashColor)

        // Receive 4 Hz snapshots → update baseline + estimate velocity
        .onReceive(ConnectivityManager.shared.$incoming.compactMap { $0 }) { msg in
            let now = ProcessInfo.processInfo.systemUptime
            isStale   = false
            lastSnapT = now

            // Store raw values
            phaseStr   = msg.phase
            snapMain   = msg.remaining
            stopActive = msg.isStopActive ?? false
            snapStop   = msg.stopRemainingActive ?? 0

            // Estimate main velocity from consecutive snapshots (local monotonic clock)
            if prevSnapT > 0 {
                let dt  = now - prevSnapT
                let dv  = snapMain - prevSnapMain
                var v   = dt > 0 ? dv / dt : 0
                if abs(v) < 0.2 { // noisy/flat → fall back by phase
                    v = (phaseStr == "countdown") ? -1.0 : (phaseStr == "running" ? 1.0 : 0.0)
                }
                vMain = (phaseStr == "paused" || phaseStr == "idle") ? 0.0 : v.clamped(to: -1.05...1.05)
            } else {
                vMain = (phaseStr == "countdown") ? -1.0 : (phaseStr == "running" ? 1.0 : 0.0)
            }

            // Stop velocity: count down if active
            vStop = stopActive ? -1.0 : 0.0

            // Set new integration baseline
            baseMain = snapMain
            baseStop = snapStop
            baseT0   = now

            // Seed display immediately
            displayMain = baseMain
            displayStop = baseStop

            // Save for next velocity estimate
            prevSnapMain = snapMain
            prevSnapT    = now

            latestMessage = msg
        }

        // Mark stale if no snapshot for > 0.5 s
        .onReceive(staleTick) { _ in
            let age = ProcessInfo.processInfo.systemUptime - lastSnapT
            isStale = age > 0.5
        }

        // Render at 20 Hz using local integration → no drift
        .onReceive(renderTick) { _ in
            let dt = ProcessInfo.processInfo.systemUptime - baseT0
            displayMain = baseMain + vMain * dt
            displayStop = max(0, baseStop + vStop * dt)
        }
    }

    private func makeRenderModel() -> WatchNowRenderModel {
        let phaseLabel = phaseChip(phaseStr)
        let stopLine = stopActive ? "Stop " + formatWithCC(max(0, displayStop), preferHours: false) : nil
        let controlsEnabled = latestMessage?.controlsEnabled
        let canStartStop = !isStale && (controlsEnabled ?? true)
        let canReset = !isStale && !isCounting
        let lockHint: String? = {
            if isStale { return "Waiting for sync" }
            if canStartStop == false { return "Controls available on iPhone" }
            if canReset == false { return "Reset available when stopped" }
            return nil
        }()

        return WatchNowRenderModel(
            formattedMain: formatWithCC(displayMain, preferHours: preferHours),
            phaseLabel: phaseLabel,
            isStale: isStale,
            stopLine: stopLine,
            canStartStop: canStartStop,
            canReset: canReset,
            lockHint: lockHint,
            linkIconName: linkIconName(for: latestMessage),
            accent: appSettings.flashColor
        )
    }

    private func makeDetailsModel() -> WatchNowDetailsModel {
        let now = ProcessInfo.processInfo.systemUptime
        let age = lastSnapT > 0 ? max(0, now - lastSnapT) : 0
        return WatchNowDetailsModel(
            isFresh: !isStale,
            age: age,
            role: latestMessage?.role,
            link: latestMessage?.link,
            sheetLabel: latestMessage?.sheetLabel,
            eventDots: makeEventDots(message: latestMessage)
        )
    }

    // MARK: - Formatting
    private func phaseChip(_ s: String) -> String {
        switch s {
        case "running": return "RUNNING"
        case "countdown": return "COUNTDOWN"
        case "paused": return "PAUSED"
        default: return "IDLE"
        }
    }

    /// HH:MM:SS.CC if hours or preference; otherwise MM:SS.CC. Supports negative values.
    private func formatWithCC(_ t: TimeInterval, preferHours: Bool) -> String {
        var value = t
        let neg = value < 0
        value = abs(value)

        let totalCs = Int((value * 100).rounded())
        let cs  = totalCs % 100
        let s   = (totalCs / 100) % 60
        let m   = (totalCs / 6000) % 60
        let h   = totalCs / 360000

        let body: String
        if preferHours || h > 0 {
            body = String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
        } else {
            body = String(format: "%02d:%02d.%02d", m, s, cs)
        }
        return neg ? "−" + body : body
    }

    private func linkIconName(for message: TimerMessage?) -> String? {
        if message?.parentLockEnabled == true { return "iphone.and.arrow.forward" }
        if message?.role == "child" { return "iphone" }
        if let link = message?.link {
            switch link {
            case "unreachable":
                return "link.slash"
            default:
                return "link"
            }
        }
        return nil
    }

    private func makeEventDots(message: TimerMessage?) -> [WatchEventDot] {
        guard let message else { return [] }
        let stops = message.stopEvents.map { WatchEventDot(kind: .stop, time: $0.eventTime) }
        let cues = (message.cueEvents ?? []).map { WatchEventDot(kind: .cue, time: $0.cueTime) }
        let restarts = (message.restartEvents ?? []).map { WatchEventDot(kind: .restart, time: $0.restartTime) }
        return (stops + cues + restarts).sorted { $0.time < $1.time }
    }
}

// MARK: - Tiny clamp helper
private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
