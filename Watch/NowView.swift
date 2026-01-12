import Foundation
import SwiftUI
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif
import Combine

struct WatchNowRenderModel {
    let formattedMain: String
    let compactMain: String
    let phaseLabel: String
    let isStale: Bool
    let stopLine: String?
    let stopDigits: String
    let compactStop: String
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
    @State private var stopIntervalActive: TimeInterval = 0

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
    @State private var flashColorIsRed: Bool? = nil
    @State private var scheduleState: WatchScheduleState = .none
    @State private var nextEventKind: WatchNextEventKind = .unknown
    @State private var nextEventInterval: TimeInterval?
    @State private var nextEventStepped: Bool = false
    @State private var baseNextRemaining: TimeInterval = 0
    @State private var baseNextRemainingT0: TimeInterval = ProcessInfo.processInfo.systemUptime
    @State private var vNextRemaining: Double = 0
    @State private var nextEventResetToken: UInt64 = 0
    @State private var lastNextRemaining: TimeInterval?
    @State private var lastScheduleStateForBoost: WatchScheduleState = .none
    @State private var lastScheduleStateForHaptic: WatchScheduleState = .none
    @State private var lastCompleteHapticUptime: TimeInterval = 0
    @State private var cueSheetIndexSummary: CueSheetIndexSummary?
    @State private var cueSheetIndexSource: WatchCueSheetIndexSource = .none
    @State private var lastCueSheetIndexSeq: UInt64 = 0
    @State private var selectedCueSheetID: UUID? = nil

    @StateObject private var runtimeKeeper = ExtendedRuntimeKeeper()

    // User preference: show hours when enabled; otherwise auto (>=1h shows hours)
    @State private var preferHours: Bool = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")

    private var isCounting: Bool { phaseStr == "running" || phaseStr == "countdown" }
    private var isIntegratingMain: Bool { isCounting && !stopActive }
    private var resolvedShowHours: Bool {
        latestMessage?.showHours ?? preferHours
    }

    var body: some View {
        timelineViewWithHandlers
    }

    private var timelineViewWithHandlers: AnyView {
        AnyView(timelineView
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
                    if stopActive {
                        stopIntervalActive = msg.stopIntervalActive ?? stopIntervalActive
                    } else {
                        stopIntervalActive = 0
                    }

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
                    applyNextEventSnapshot(from: msg, nowUptime: now)

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
            .onReceive(ConnectivityManager.shared.$incomingSyncEnvelope.compactMap { $0 }) { envelope in
                if case let .cueSheetIndexSummary(summary) = envelope.message {
                    handleCueSheetIndex(summary, source: .phoneIndex)
                }
            }
            .onReceive(ConnectivityManager.shared.$incomingCueSheetIndexSummary.compactMap { $0 }) { summary in
                handleCueSheetIndex(summary, source: .applicationContext)
            }
            .onChange(of: scenePhase) { _ in
                updateExtendedRuntime()
                if scenePhase == .active {
                    requestSnapshotIfNeeded(origin: "scenePhase.active")
                    ConnectivityManager.shared.requestCueSheetIndexIfNeeded(origin: "scenePhase.active")
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
                if selection == 4 {
                    ConnectivityManager.shared.requestCueSheetIndex(origin: "page.cueSheets")
                }
            }
            .onAppear {
                updateExtendedRuntime()
                if let cached = loadCueSheetIndexCache() {
                    cueSheetIndexSummary = cached
                    lastCueSheetIndexSeq = cached.seq
                    cueSheetIndexSource = cached.items.isEmpty ? .none : .cache
                } else {
                    cueSheetIndexSource = .none
                }
                ConnectivityManager.shared.requestCueSheetIndex(origin: "onAppear")
            })
    }

    private var timelineView: some View {
        let timelineInterval: TimeInterval = faceTickInterval(nowUptime: ProcessInfo.processInfo.systemUptime)

        return TimelineView(.periodic(from: .now, by: timelineInterval)) { context in
            let nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
            let renderModel: WatchNowRenderModel = makeRenderModel(nowUptime: nowUptime)
            let timerProviders: WatchTimerProviders = makeTimerProviders()
            let nextEventDialModel: WatchNextEventDialModel = makeNextEventDialModel()
            let cueSheetsModel: WatchCueSheetsModel = makeCueSheetsModel()

            timelineTabViewContent(
                renderModel: renderModel,
                timerProviders: timerProviders,
                nextEventDialModel: nextEventDialModel,
                cueSheetsModel: cueSheetsModel,
                nowUptime: nowUptime,
                contextDate: context.date
            )
        }
    }

    @ViewBuilder
    private func timelineTabViewContent(
        renderModel: WatchNowRenderModel,
        timerProviders: WatchTimerProviders,
        nextEventDialModel: WatchNextEventDialModel,
        cueSheetsModel: WatchCueSheetsModel,
        nowUptime: TimeInterval,
        contextDate: Date
    ) -> some View {
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

            WatchTimerFocusPage(
                renderModel: renderModel,
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

            WatchNextEventDialPage(model: nextEventDialModel, nowUptime: nowUptime)
                .tag(3)

            WatchCueSheetsPage(
                renderModel: renderModel,
                cueSheetsModel: cueSheetsModel,
                selectedSheetID: $selectedCueSheetID,
                requestCueSheetIndex: { ConnectivityManager.shared.requestCueSheetIndex(origin: "watch.cueSheets.auto") }
            )
            .tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .tint(appSettings.flashColor)
        .onChange(of: contextDate) { _ in
            handleTimelineTick(nowUptime: nowUptime)
        }
    }

    private func makeRenderModel(nowUptime: TimeInterval) -> WatchNowRenderModel {
        let phaseLabel = phaseChip(phaseStr)
        let liveMain = currentMain(nowUptime: nowUptime)
        let liveStop = currentStop(nowUptime: nowUptime)
        let stopLine = stopActive ? "Stop " + formatWithCC(liveStop, preferHours: false) : nil
        let isFlashingNow = nowUptime < flashUntilUptime
        let hasFlashColor = (latestMessage?.flashRGBA != nil) || (latestMessage?.flashColorARGB != nil)
        let flashColor = hasFlashColor ? cachedFlashColor : appSettings.flashColor
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
            compactMain: formatCompactWithCC(liveMain, showHours: resolvedShowHours),
            phaseLabel: phaseLabel,
            isStale: isStale,
            stopLine: stopLine,
            stopDigits: formatWithCC(liveStop, preferHours: false),
            compactStop: formatCompactWithCC(liveStop, showHours: resolvedShowHours),
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
        if let rgba = message.flashRGBA, let color = decodeRGBAColor(rgba) {
            cachedFlashColor = color
            appSettings.flashColor = color
        } else if let argb = message.flashColorARGB {
            let color = decodeARGBColor(argb)
            cachedFlashColor = color
            appSettings.flashColor = color
        }
        if let hapticsEnabled = message.flashHapticsEnabled {
            cachedFlashHapticsEnabled = hapticsEnabled
        }
        if let isRed = message.flashColorIsRed {
            flashColorIsRed = isRed
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

    private func applyNextEventSnapshot(from message: TimerMessage, nowUptime: TimeInterval) {
        // UI-only: next-event dial snapshot for watch; no timer semantics change.
        var resolvedState = resolveScheduleState(from: message)
        var remaining = message.nextEventRemaining
        var interval = message.nextEventInterval

        if resolvedState == .active {
            if let intervalValue = interval, intervalValue > 0, let remainingValue = remaining {
                interval = intervalValue
                remaining = remainingValue
            } else {
                resolvedState = .none
                remaining = nil
                interval = nil
            }
        } else {
            remaining = nil
            interval = nil
        }

        let kind = WatchNextEventKind(rawValue: message.nextEventKind ?? "") ?? .unknown
        let stepped = message.nextEventStepped ?? false
        let stateChanged = resolvedState != scheduleState
        let intervalChanged = interval != nextEventInterval
        let remainingJumped = (remaining ?? 0) > (lastNextRemaining ?? 0) + 0.2

        if stateChanged || intervalChanged || remainingJumped {
            nextEventResetToken &+= 1
        }

        scheduleState = resolvedState
        nextEventKind = kind
        nextEventInterval = interval
        nextEventStepped = stepped
        lastNextRemaining = remaining

        baseNextRemaining = max(0, remaining ?? 0)
        baseNextRemainingT0 = nowUptime
        vNextRemaining = (resolvedState == .active && phaseStr == "running") ? -1.0 : 0.0

        if resolvedState != lastScheduleStateForBoost,
           resolvedState == .active || resolvedState == .complete {
            boostUntilUptime = nowUptime + 6.0
            lastScheduleStateForBoost = resolvedState
            updateExtendedRuntime()
        }

        if resolvedState == .complete && lastScheduleStateForHaptic != .complete {
            let hapticCooldown: TimeInterval = 5.0
            if isLuminanceReduced, (nowUptime - lastCompleteHapticUptime) > hapticCooldown {
                lastCompleteHapticUptime = nowUptime
                #if os(watchOS)
                WKInterfaceDevice.current().play(.click)
                #endif
            }
        }
        lastScheduleStateForHaptic = resolvedState
    }

    private func resolveScheduleState(from message: TimerMessage) -> WatchScheduleState {
        if let raw = message.scheduleState, let state = WatchScheduleState(rawValue: raw) {
            return state
        }
        if message.nextEventRemaining != nil, message.nextEventInterval != nil {
            return .active
        }
        return .none
    }

    private func decodeARGBColor(_ argb: UInt32) -> Color {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private func decodeRGBAColor(_ rgba: [Double]) -> Color? {
        guard rgba.count == 4 else { return nil }
        return Color(.sRGB,
                     red: rgba[0].clamped(to: 0...1),
                     green: rgba[1].clamped(to: 0...1),
                     blue: rgba[2].clamped(to: 0...1),
                     opacity: rgba[3].clamped(to: 0...1))
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
            },
            compactMainStringProvider: { nowUptime in
                formatCompactWithCC(currentMain(nowUptime: nowUptime), showHours: resolvedShowHours)
            },
            compactStopStringProvider: { nowUptime in
                formatCompactWithCC(currentStop(nowUptime: nowUptime), showHours: resolvedShowHours)
            }
        )
    }

    private func makeNextEventDialModel() -> WatchNextEventDialModel {
        WatchNextEventDialModel(
            accent: appSettings.flashColor,
            flashColorIsRed: flashColorIsRed,
            isStale: isStale,
            scheduleState: scheduleState,
            nextEventKind: nextEventKind,
            nextEventInterval: nextEventInterval,
            isStepped: nextEventStepped,
            snapshotToken: snapshotToken,
            resetToken: nextEventResetToken,
            isStopActive: stopActive,
            stopInterval: stopIntervalActive,
            remainingProvider: { nowUptime in
                currentNextEventRemaining(nowUptime: nowUptime)
            },
            stopRemainingProvider: { nowUptime in
                currentStop(nowUptime: nowUptime)
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

    /// H:MM:SS.CC if showHours and hours > 0, else M:SS.CC, else SS.CC. Supports negative values.
    private func formatCompactWithCC(_ t: TimeInterval, showHours: Bool) -> String {
        var value = t
        let neg = value < 0
        value = abs(value)

        let totalCs = Int((value * 100).rounded())
        let cs  = totalCs % 100
        let s   = (totalCs / 100) % 60
        let m   = (totalCs / 6000) % 60
        let h   = totalCs / 360000

        let body: String
        if showHours && h > 0 {
            body = String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
        } else if (h > 0) || m > 0 {
            let minutes = (h * 60) + m
            body = String(format: "%d:%02d.%02d", minutes, s, cs)
        } else {
            body = String(format: "%02d.%02d", s, cs)
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

    private func currentNextEventRemaining(nowUptime: TimeInterval) -> TimeInterval? {
        guard scheduleState == .active else { return nil }
        return max(0, baseNextRemaining + vNextRemaining * (nowUptime - baseNextRemainingT0))
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
        let shouldRun = scenePhase == .active
            && pageSelection == 3
            && (scheduleState == .active || stopActive || nowUptime < boostUntilUptime)
        runtimeKeeper.update(shouldRun: shouldRun)
    }

    private func makeCueSheetsModel() -> WatchCueSheetsModel {
        let role = WatchRole(wireValue: latestMessage?.role)
        let isConnected = isConnected(link: latestMessage?.link)
        let loadedSheetID = latestMessage?.sheetID.flatMap(UUID.init)
        let loadedSheetName = resolveLoadedSheetName(
            label: latestMessage?.sheetLabel,
            sheetID: loadedSheetID
        )
        let items = cueSheetIndexSummary?.items ?? []
        let sheets = items.map {
            WatchCueSheetSummary(
                id: $0.id,
                name: $0.name,
                cueCount: $0.cueCount,
                modifiedAt: $0.modifiedAt.map { Date(timeIntervalSince1970: $0) }
            )
        }
        let selection = selectedCueSheetID.flatMap { id in
            sheets.contains(where: { $0.id == id }) ? id : nil
        }
        let activationStateLabel = activationStateDescription()
        let isReachable = ConnectivityManager.shared.session?.isReachable

        return WatchCueSheetsModel(
            role: role,
            isConnected: isConnected,
            isStale: isStale,
            loadedSheetName: loadedSheetName,
            loadedSheetID: loadedSheetID,
            isLockedFromParent: role == .child && isConnected,
            sheets: sheets,
            selectedSheetID: selection,
            childCount: nil,
            cueSheetIndexSource: cueSheetIndexSource,
            activationStateLabel: activationStateLabel,
            isReachable: isReachable
        )
    }

    private func activationStateDescription() -> String {
        #if canImport(WatchConnectivity)
        guard let state = ConnectivityManager.shared.session?.activationState else {
            return "unknown"
        }
        switch state {
        case .activated:
            return "activated"
        case .inactive:
            return "inactive"
        case .notActivated:
            return "notActivated"
        @unknown default:
            return "unknown"
        }
        #else
        return "unsupported"
        #endif
    }

    private func resolveLoadedSheetName(label: String?, sheetID: UUID?) -> String? {
        if let label = normalizedLabel(label) {
            return label
        }
        if let sheetID,
           let match = cueSheetIndexSummary?.items.first(where: { $0.id == sheetID }) {
            return match.name
        }
        return nil
    }

    private func normalizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isConnected(link: String?) -> Bool {
        guard let link else { return false }
        return link != "unreachable"
    }

    private func handleCueSheetIndex(_ summary: CueSheetIndexSummary, source: WatchCueSheetIndexSource) {
        if summary.seq > 0, summary.seq < lastCueSheetIndexSeq {
            return
        }
        lastCueSheetIndexSeq = max(lastCueSheetIndexSeq, summary.seq)
        cueSheetIndexSummary = summary
        cueSheetIndexSource = source
        storeCueSheetIndexCache(summary)
        if let selectedCueSheetID,
           !summary.items.contains(where: { $0.id == selectedCueSheetID }) {
            self.selectedCueSheetID = nil
        }
    }

    private func loadCueSheetIndexCache() -> CueSheetIndexSummary? {
        let key = "CueSheetIndexSummaryCache"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CueSheetIndexSummary.self, from: data)
    }

    private func storeCueSheetIndexCache(_ summary: CueSheetIndexSummary) {
        let key = "CueSheetIndexSummaryCache"
        guard let data = try? JSONEncoder().encode(summary) else { return }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "CueSheetIndexSummaryCacheUpdatedAt")
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
