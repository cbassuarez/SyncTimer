import SwiftUI
import Combine

struct WatchNowRenderModel {
    let formattedMain: String
    let phaseLabel: String
    let isStale: Bool
    let stopLine: String?
    let stopDigits: String
    let isStopActive: Bool
    let canStartStop: Bool
    let canReset: Bool
    let lockHint: String?
    let linkIconName: String?
    let faceEvents: [WatchFaceEvent]
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
    @State private var lastReceiveUptime: TimeInterval = 0
    @State private var snapIntervalEMA: TimeInterval = 0
    @State private var isStale     : Bool = true

    @State private var latestMessage: TimerMessage?
    @State private var pageSelection: Int = 0

    // Tickers
    private let staleTick  = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    // User preference: show hours when enabled; otherwise auto (>=1h shows hours)
    @State private var preferHours: Bool = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")

    private var isCounting: Bool { phaseStr == "running" || phaseStr == "countdown" }
    private var resolvedShowHours: Bool {
        latestMessage?.showHours ?? preferHours
    }

    var body: some View {
        let renderModel = makeRenderModel()
        let detailsModel = makeDetailsModel()
        let timerProviders = makeTimerProviders()

        TabView(selection: $pageSelection) {
            WatchFacePage(renderModel: renderModel, timerProviders: timerProviders, isLive: pageSelection == 0)
                .tag(0)
            WatchDetailsPage(
                renderModel: renderModel,
                detailsModel: detailsModel,
                timerProviders: timerProviders,
                isLive: pageSelection == 1
            )
            .tag(1)
            WatchControlsPage(
                renderModel: renderModel,
                timerProviders: timerProviders,
                isLive: pageSelection == 2,
                startStop: { ConnectivityManager.shared.sendCommand(isCounting ? .stop : .start) },
                reset: { if !isCounting { ConnectivityManager.shared.sendCommand(.reset) } }
            )
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .tint(appSettings.flashColor)

        // Receive 4 Hz snapshots → update baseline + estimate velocity
        .onReceive(ConnectivityManager.shared.$incoming.compactMap { $0 }) { msg in
            let now = ProcessInfo.processInfo.systemUptime
            isStale   = false

            if lastReceiveUptime > 0 {
                let rawDt = now - lastReceiveUptime
                let dt = rawDt.clamped(to: 0.05...2.0)
                snapIntervalEMA = snapIntervalEMA == 0 ? dt : (0.85 * snapIntervalEMA + 0.15 * dt)
            }
            lastReceiveUptime = now

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

            // Save for next velocity estimate
            prevSnapMain = snapMain
            prevSnapT    = now

            latestMessage = msg
        }

        // Mark stale if no snapshot for an adaptive timeout
        .onReceive(staleTick) { _ in
            let age = ProcessInfo.processInfo.systemUptime - lastReceiveUptime
            let ema = snapIntervalEMA == 0 ? 0.25 : snapIntervalEMA
            let staleAfter = max(1.5, min(4.0, ema * 6.0))
            let freshHold = max(0.8, min(2.0, ema * 3.0))
            if age > staleAfter && age > freshHold {
                isStale = true
            }
        }
    }

    private func makeRenderModel() -> WatchNowRenderModel {
        let phaseLabel = phaseChip(phaseStr)
        let stopLine = stopActive ? "Stop " + formatWithCC(max(0, baseStop), preferHours: false) : nil
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
            formattedMain: formatWithCC(baseMain, preferHours: resolvedShowHours),
            phaseLabel: phaseLabel,
            isStale: isStale,
            stopLine: stopLine,
            stopDigits: formatWithCC(max(0, baseStop), preferHours: false),
            isStopActive: stopActive,
            canStartStop: canStartStop,
            canReset: canReset,
            lockHint: lockHint,
            linkIconName: linkIconName(for: latestMessage),
            faceEvents: makeFaceEvents(message: latestMessage),
            accent: appSettings.flashColor
        )
    }

    private func makeDetailsModel() -> WatchNowDetailsModel {
        let now = ProcessInfo.processInfo.systemUptime
        let age = lastReceiveUptime > 0 ? max(0, now - lastReceiveUptime) : 0
        return WatchNowDetailsModel(
            isFresh: !isStale,
            age: age,
            role: latestMessage?.role,
            link: latestMessage?.link,
            sheetLabel: latestMessage?.sheetLabel,
            eventDots: makeEventDots(message: latestMessage)
        )
    }

    private func makeTimerProviders() -> WatchTimerProviders {
        WatchTimerProviders(
            nowUptimeProvider: { ProcessInfo.processInfo.systemUptime },
            formattedStringProvider: { nowUptime in
                formatWithCC(currentMain(nowUptime: nowUptime), preferHours: resolvedShowHours)
            },
            stopLineProvider: { nowUptime in
                guard stopActive else { return nil }
                return "Stop " + formatWithCC(currentStop(nowUptime: nowUptime), preferHours: false)
            },
            stopDigitsProvider: { nowUptime in
                formatWithCC(currentStop(nowUptime: nowUptime), preferHours: false)
            }
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

    private func makeFaceEvents(message: TimerMessage?) -> [WatchFaceEvent] {
        guard let message else { return [] }
        var events = [WatchFaceEvent]()
        events.append(contentsOf: message.stopEvents.map { WatchFaceEvent(kind: .stop, time: $0.eventTime) })
        events.append(contentsOf: (message.cueEvents ?? []).map { WatchFaceEvent(kind: .cue, time: $0.cueTime) })
        events.append(contentsOf: (message.restartEvents ?? []).map { WatchFaceEvent(kind: .restart, time: $0.restartTime) })
        if let display = message.display {
            switch display.kind {
            case .message:
                events.append(WatchFaceEvent(kind: .message, time: message.timestamp))
            case .image:
                events.append(WatchFaceEvent(kind: .image, time: message.timestamp))
            case .none:
                break
            }
        }
        return events.sorted { $0.time > $1.time }
    }

    private func currentMain(nowUptime: TimeInterval) -> TimeInterval {
        baseMain + vMain * (nowUptime - baseT0)
    }

    private func currentStop(nowUptime: TimeInterval) -> TimeInterval {
        max(0, baseStop + vStop * (nowUptime - baseT0))
    }
}

// MARK: - Tiny clamp helper
private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
