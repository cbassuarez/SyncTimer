import SwiftUI
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif
import Combine

struct WatchNowRenderModel {
    let formattedMain: String
    let phaseLabel: String
    let isStale: Bool
    let stopLine: String?
    let stopDigits: String
    let isStopActive: Bool
    let isCounting: Bool
    let canStartStop: Bool
    let canReset: Bool
    let lockHint: String?
    let linkIconName: String?
    let faceEvents: [WatchFaceEvent]
    let accent: Color
    let isFlashingNow: Bool
    let flashStyle: WatchFlashStyle
    let flashColor: Color
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
    @State private var latestMessage: TimerMessage?
    @State private var pageSelection: Int = 0
    @State private var lastPokeUptime: TimeInterval = -10
    // Incremented on snapshot arrival to force a face digit refresh even if the timeline is throttled.
    @State private var snapshotToken: UInt64 = 0
    @State private var boostUntilUptime: TimeInterval = 0
    @State private var lastPhaseForBoost: String = ""
    @State private var lastSeqForBoost: UInt64 = 0
    @State private var lastHapticUptime: TimeInterval = 0
    @State private var lastSeenFlashSeq: UInt64 = 0
    @State private var lastFlashNowSeq: UInt64 = 0
    @State private var flashUntilUptime: TimeInterval = 0
    @State private var cachedFlashStyle: WatchFlashStyle = .off
    @State private var cachedFlashDuration: TimeInterval = 0.25
    @State private var cachedFlashColor: Color = .red
    @State private var cachedFlashHapticsEnabled: Bool = false

    @StateObject private var runtimeKeeper = ExtendedRuntimeKeeper()

    // User preference: show hours when enabled; otherwise auto (>=1h shows hours)
    @State private var preferHours: Bool = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")

    private var isCounting: Bool { phaseStr == "running" || phaseStr == "countdown" }
    private var isIntegratingMain: Bool { isCounting && !stopActive }
    private var resolvedShowHours: Bool {
        latestMessage?.showHours ?? preferHours
    }

    var body: some View {
        let timelineInterval = faceTickInterval(nowUptime: ProcessInfo.processInfo.systemUptime)

        TimelineView(.periodic(from: .now, by: timelineInterval)) { context in
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
                    snapshotToken: snapshotToken,
                    startStop: { ConnectivityManager.shared.sendCommand(isCounting ? .stop : .start) },
                    reset: { if !isCounting { ConnectivityManager.shared.sendCommand(.reset) } }
                )
                .tag(0)
                WatchDetailsPage(
                    renderModel: renderModel,
                    detailsModel: detailsModel,
                    timerProviders: timerProviders,
                    nowUptime: nowUptime,
                    isLive: pageSelection == 1,
                    snapshotToken: snapshotToken
                )
                .tag(1)
                WatchControlsPage(
                    renderModel: renderModel,
                    timerProviders: timerProviders,
                    nowUptime: nowUptime,
                    isLive: pageSelection == 2,
                    snapshotToken: snapshotToken,
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
                let wasStale = isStale
                let previousPhase = phaseStr
                let seq = msg.stateSeq ?? msg.actionSeq ?? 0
                lastSnapUptime = now

                // Store raw values
                phaseStr   = msg.phase
                snapMain   = msg.remaining
                stopActive = msg.isStopActive ?? false
                snapStop   = msg.stopRemainingActive ?? 0

                let shouldIntegrateMain = isIntegratingMain

                // Estimate main velocity from consecutive snapshots (local monotonic clock)
                if shouldIntegrateMain {
                    if prevSnapT > 0 {
                        let dt  = now - prevSnapT
                        let dv  = snapMain - prevSnapMain
                        var v   = dt > 0 ? dv / dt : 0
                        if abs(v) < 0.2 { // noisy/flat → fall back by phase
                            v = (phaseStr == "countdown") ? -1.0 : (phaseStr == "running" ? 1.0 : 0.0)
                        }
                        vMain = v.clamped(to: -1.05...1.05)
                    } else {
                        vMain = (phaseStr == "countdown") ? -1.0 : 1.0
                    }
                } else {
                    vMain = 0.0
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
                applyFlashConfig(from: msg)
                handleFlashTrigger(from: msg, nowUptime: now)

                updateStaleIfNeeded(nowUptime: now)

                let phaseChanged = msg.phase != lastPhaseForBoost
                let seqJumped = seq > lastSeqForBoost
                let freshRecovered = wasStale && !isStale
                if phaseChanged || seqJumped || freshRecovered {
                    boostUntilUptime = now + 6.0
                    lastPhaseForBoost = msg.phase
                    lastSeqForBoost = seq
                    updateExtendedRuntime()
                }

                // Force an immediate face digit refresh on snapshot arrival.
                snapshotToken &+= 1

                let wasCounting = previousPhase == "running" || previousPhase == "countdown"
                let isCountingNow = msg.phase == "running" || msg.phase == "countdown"
                if isLuminanceReduced && !wasCounting && isCountingNow {
                    let hapticCooldown: TimeInterval = 3.0
                    if now - lastHapticUptime > hapticCooldown {
                        lastHapticUptime = now
                        #if os(watchOS)
                        WKInterfaceDevice.current().play(.click)
                        #endif
                    }
                }
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
        .onChange(of: pageSelection) { selection in
            boostUntilUptime = ProcessInfo.processInfo.systemUptime + 6.0
            updateExtendedRuntime()
            let origin = selection == 0 ? "face.page" : "page.\(selection)"
            requestSnapshotIfNeeded(origin: origin)
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
        let isFlashingNow = nowUptime < flashUntilUptime
        let flashColor = (latestMessage?.flashColorARGB != nil) ? cachedFlashColor : appSettings.flashColor
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
            isCounting: isCounting,
            canStartStop: canStartStop,
            canReset: canReset,
            lockHint: lockHint,
            linkIconName: linkIconName(for: latestMessage),
            faceEvents: makeFaceEvents(message: latestMessage),
            accent: appSettings.flashColor,
            isFlashingNow: isFlashingNow,
            flashStyle: cachedFlashStyle,
            flashColor: flashColor
        )
    }

    private func applyFlashConfig(from message: TimerMessage) {
        if let style = message.flashStyle {
            cachedFlashStyle = WatchFlashStyle.fromWire(style)
        }
        if let durationMs = message.flashDurationMs {
            let seconds = Double(durationMs) / 1000.0
            cachedFlashDuration = seconds.clamped(to: 0.05...1.0)
        }
        if let argb = message.flashColorARGB {
            cachedFlashColor = decodeARGBColor(argb)
        }
        if let hapticsEnabled = message.flashHapticsEnabled {
            cachedFlashHapticsEnabled = hapticsEnabled
        }
    }

    private func handleFlashTrigger(from message: TimerMessage, nowUptime: TimeInterval) {
        var shouldFlash = false
        if let flashSeq = message.flashSeq, flashSeq > lastSeenFlashSeq {
            lastSeenFlashSeq = flashSeq
            shouldFlash = true
        } else if message.flashNow == true {
            let seq = message.stateSeq ?? message.actionSeq ?? 0
            if seq > lastFlashNowSeq {
                lastFlashNowSeq = seq
                shouldFlash = true
            }
        }
        guard shouldFlash else { return }
        let duration = cachedFlashDuration.clamped(to: 0.05...1.0)
        flashUntilUptime = nowUptime + duration
        #if DEBUG
        let argb = message.flashColorARGB.map { String(format: "0x%08X", $0) } ?? "nil"
        print("[watch] flash trigger seq=\(message.flashSeq ?? 0) style=\(cachedFlashStyle.rawValue) durationMs=\(Int(duration * 1000)) color=\(argb) phase=\(message.phase) luminanceReduced=\(isLuminanceReduced)")
        #endif

        if cachedFlashHapticsEnabled && (isLuminanceReduced || scenePhase == .active) {
            let hapticCooldown: TimeInterval = 0.6
            if nowUptime - lastHapticUptime > hapticCooldown {
                lastHapticUptime = nowUptime
                #if os(watchOS)
                WKInterfaceDevice.current().play(.click)
                #endif
            }
        }
    }

    private func decodeARGBColor(_ argb: UInt32) -> Color {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
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
        guard isIntegratingMain else { return baseMain }
        return baseMain + vMain * (nowUptime - baseT0)
    }

    private func currentStop(nowUptime: TimeInterval) -> TimeInterval {
        max(0, baseStop + vStop * (nowUptime - baseT0))
    }

    private func faceTickInterval(nowUptime: TimeInterval) -> TimeInterval {
        if scenePhase == .active && nowUptime < boostUntilUptime { return 0.02 }
        if isLuminanceReduced { return 0.2 }
        if isCounting { return 0.02 }
        return 0.05
    }

    private func handleTimelineTick(nowUptime: TimeInterval) {
        updateStaleIfNeeded(nowUptime: nowUptime)
    }

    private func updateStaleIfNeeded(nowUptime: TimeInterval) {
        let age = lastSnapUptime > 0 ? max(0, nowUptime - lastSnapUptime) : .infinity
        let staleThreshold = 4.0
        let freshThreshold = 1.0
        let nextStale: Bool
        if isStale {
            nextStale = age >= freshThreshold
        } else {
            nextStale = age > staleThreshold
        }
        if nextStale != isStale {
            isStale = nextStale
            if nextStale {
                requestSnapshotIfNeeded(origin: "stale")
            }
        }
    }

    private func updateExtendedRuntime() {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let shouldRun = scenePhase == .active && (isCounting || nowUptime < boostUntilUptime)
        runtimeKeeper.update(shouldRun: shouldRun)
    }

    private func requestSnapshotIfNeeded(origin: String) {
        let now = ProcessInfo.processInfo.systemUptime
        let cooldown: TimeInterval = 0.6
        guard now - lastPokeUptime >= cooldown else { return }
        lastPokeUptime = now
        ConnectivityManager.shared.requestSnapshot(origin: origin)
    }
}

// MARK: - Tiny clamp helper
private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
