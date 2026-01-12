import SwiftUI
import Combine
import WatchConnectivity

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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

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
    @State private var lastSnapUptime: TimeInterval = 0
    @State private var isStale     : Bool = true
    @State private var lastSnapSeq: UInt64 = 0

    @State private var latestMessage: TimerMessage?
    @State private var pageSelection: Int = 0
    @State private var snapCounter: UInt64 = 0
    @State private var tickBucket: Int = 0
    @State private var tickN: Int = 0
    @State private var lastPokeUptime: TimeInterval = -10

    @StateObject private var runtimeKeeper = ExtendedRuntimeKeeper()

    // User preference: show hours when enabled; otherwise auto (>=1h shows hours)
    @State private var preferHours: Bool = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")

    private var isCounting: Bool { phaseStr == "running" || phaseStr == "countdown" }
    private var resolvedShowHours: Bool {
        latestMessage?.showHours ?? preferHours
    }
    private var tickInterval: TimeInterval {
        if isLuminanceReduced { return 0.2 }
        if isCounting || stopActive { return 0.02 }
        return 0.05
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let nowUptime = ProcessInfo.processInfo.systemUptime
            let renderModel = makeRenderModel(nowUptime: nowUptime)
            let detailsModel = makeDetailsModel(nowUptime: nowUptime)
            let timerProviders = makeTimerProviders()

            TabView(selection: $pageSelection) {
                WatchFacePage(
                    renderModel: renderModel,
                    timerProviders: timerProviders,
                    nowUptime: nowUptime,
                    isLive: pageSelection == 0,
                    snapshotToken: snapCounter
                )
                #if DEBUG
                .overlay(alignment: .topLeading) {
                    WatchDebugOverlay(lines: debugLines)
                }
                #endif
                .tag(0)
                WatchDetailsPage(
                    renderModel: renderModel,
                    detailsModel: detailsModel,
                    timerProviders: timerProviders,
                    nowUptime: nowUptime,
                    isLive: pageSelection == 1
                )
                .tag(1)
                WatchControlsPage(
                    renderModel: renderModel,
                    timerProviders: timerProviders,
                    nowUptime: nowUptime,
                    isLive: pageSelection == 2,
                    startStop: { ConnectivityManager.shared.sendCommand(isCounting ? .stop : .start) },
                    reset: { if !isCounting { ConnectivityManager.shared.sendCommand(.reset) } }
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .tint(appSettings.flashColor)
            .onChange(of: context.date) { _ in
                handleTimelineTick(nowUptime: nowUptime)
            }
        }

        // Receive 4 Hz snapshots → update baseline + estimate velocity
        .onReceive(ConnectivityManager.shared.$incoming.compactMap { $0 }) { msg in
            Task { @MainActor in
                let now = ProcessInfo.processInfo.systemUptime
                lastSnapUptime = now

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
                let seq = msg.stateSeq ?? msg.actionSeq
                if let seq {
                    lastSnapSeq = seq
                } else {
                    lastSnapSeq &+= 1
                }
                snapCounter = seq ?? (snapCounter &+ 1)
            }
        }
        .onChange(of: scenePhase) { _ in
            updateExtendedRuntime()
            if scenePhase == .active {
                requestSnapshotIfNeeded(origin: "scenePhase.active")
            }
        }
        .onChange(of: phaseStr) { _ in
            updateExtendedRuntime()
        }
        .onChange(of: stopActive) { _ in
            updateExtendedRuntime()
        }
        .onChange(of: isLuminanceReduced) { reduced in
            if !reduced {
                requestSnapshotIfNeeded(origin: "luminance.full")
            }
        }
        .onAppear {
            updateExtendedRuntime()
        }
    }

    private func makeRenderModel(nowUptime: TimeInterval) -> WatchNowRenderModel {
        let phaseLabel = phaseChip(phaseStr)
        let liveMain = currentMain(nowUptime: nowUptime)
        let liveStop = currentStop(nowUptime: nowUptime)
        let stopLine = stopActive ? "Stop " + formatWithCC(liveStop, preferHours: false) : nil
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
            formattedMain: formatWithCC(liveMain, preferHours: resolvedShowHours),
            phaseLabel: phaseLabel,
            isStale: isStale,
            stopLine: stopLine,
            stopDigits: formatWithCC(liveStop, preferHours: false),
            isStopActive: stopActive,
            canStartStop: canStartStop,
            canReset: canReset,
            lockHint: lockHint,
            linkIconName: linkIconName(for: latestMessage),
            faceEvents: makeFaceEvents(message: latestMessage),
            accent: appSettings.flashColor
        )
    }

    private func makeDetailsModel(nowUptime: TimeInterval) -> WatchNowDetailsModel {
        let age = lastSnapUptime > 0 ? max(0, nowUptime - lastSnapUptime) : 0
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
            mainValueProvider: { nowUptime in
                currentMain(nowUptime: nowUptime)
            },
            stopValueProvider: { nowUptime in
                currentStop(nowUptime: nowUptime)
            },
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

    private func handleTimelineTick(nowUptime: TimeInterval) {
        updateStaleIfNeeded(nowUptime: nowUptime)
        updateTickCounter(nowUptime: nowUptime)
    }

    private func updateStaleIfNeeded(nowUptime: TimeInterval) {
        let age = lastSnapUptime > 0 ? max(0, nowUptime - lastSnapUptime) : .infinity
        let staleThreshold = 4.0
        let freshThreshold = 1.0
        if isStale {
            if age < freshThreshold {
                isStale = false
            }
        } else {
            if age > staleThreshold {
                isStale = true
                requestSnapshotIfNeeded(origin: "stale")
            }
        }
    }

    private func updateTickCounter(nowUptime: TimeInterval) {
        let bucket = Int((nowUptime / 0.2).rounded(.down))
        if bucket != tickBucket {
            tickBucket = bucket
            tickN += 1
        }
    }

    private func updateExtendedRuntime() {
        runtimeKeeper.update(
            shouldRun: isCounting || stopActive,
            scenePhase: scenePhase
        )
    }

    private func requestSnapshotIfNeeded(origin: String) {
        let now = ProcessInfo.processInfo.systemUptime
        let cooldown: TimeInterval = 0.6
        guard now - lastPokeUptime >= cooldown else { return }
        lastPokeUptime = now
        ConnectivityManager.shared.requestSnapshot(origin: origin)
    }
}

#if DEBUG
private struct WatchDebugOverlay: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { line in
                Text(line)
            }
        }
        .font(.system(size: 8, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(4)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .padding(.leading, 6)
        .padding(.top, 4)
    }
}
#endif

private extension NowView {
    var debugLines: [String] {
        #if DEBUG
        let now = ProcessInfo.processInfo.systemUptime
        let ageMs = Int(max(0, now - lastSnapUptime) * 1000)
        let session = ConnectivityManager.shared.session
        let activation = session.map { String(describing: $0.activationState) } ?? "nil"
        let reachable = session?.isReachable ?? false
        let seqText = lastSnapSeq
        return [
            "scene:\(scenePhase) lum:\(isLuminanceReduced)",
            "wc:\(activation) reach:\(reachable)",
            "ageMs:\(ageMs) lastSnapSeq:\(seqText)",
            "tickN:\(tickN) phase:\(phaseStr)"
        ]
        #else
        return []
        #endif
    }
}

// MARK: - Tiny clamp helper
private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
