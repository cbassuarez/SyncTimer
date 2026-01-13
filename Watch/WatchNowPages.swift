import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WatchNowDetailsModel {
    let isFresh: Bool
    let age: TimeInterval
    let role: String?
    let link: String?
    let sheetLabel: String?
    let eventDots: [WatchEventDot]
}

enum WatchRole: String {
    case parent
    case child
    case solo

    init(wireValue: String?) {
        switch wireValue {
        case "parent":
            self = .parent
        case "child":
            self = .child
        default:
            self = .solo
        }
    }
}

enum WatchCueSheetIndexSource: String {
    case phoneIndex
    case cache
    case none
}

struct WatchCueSheetSummary: Identifiable {
    let id: UUID
    let name: String
    let cueCount: Int?
    let modifiedAt: Date?
}

struct WatchCueSheetsModel {
    let role: WatchRole
    let isConnected: Bool
    let isStale: Bool
    let loadedSheetName: String?
    let loadedSheetID: UUID?
    let isLockedFromParent: Bool
    let sheets: [WatchCueSheetSummary]
    let selectedSheetID: UUID?
    let childCount: Int?
    let cueSheetIndexSource: WatchCueSheetIndexSource
    let activationStateLabel: String
    let isReachable: Bool?
}

struct WatchTimerProviders {
    let mainValueProvider: (TimeInterval) -> TimeInterval
    let stopValueProvider: (TimeInterval) -> TimeInterval
    let formattedStringProvider: (TimeInterval) -> String
    let stopLineProvider: (TimeInterval) -> String?
    let stopDigitsProvider: (TimeInterval) -> String
    let compactMainStringProvider: (TimeInterval) -> String
    let compactStopStringProvider: (TimeInterval) -> String
}

enum WatchScheduleState: String {
    case none
    case active
    case complete
}

enum WatchNextEventKind: String {
    case cue
    case restart
    case stop
    case message
    case image
    case unknown
}

struct WatchNextEventDialModel {
    let accent: Color
    let flashColorIsRed: Bool?
    let isStale: Bool
    let scheduleState: WatchScheduleState
    let nextEventKind: WatchNextEventKind
    let nextEventInterval: TimeInterval?
    let isStepped: Bool
    let snapshotToken: UInt64
    let resetToken: UInt64
    let isStopActive: Bool
    let stopInterval: TimeInterval?
    let remainingProvider: (TimeInterval) -> TimeInterval?
    let stopRemainingProvider: (TimeInterval) -> TimeInterval
}

struct WatchEventDot: Identifiable {
    enum Kind: String {
        case stop
        case cue
        case restart
    }

    let kind: Kind
    let time: TimeInterval

    var id: String {
        "\(kind.rawValue)-\(Int(time * 100))"
    }
}

enum WatchFlashStyle: String {
    case off
    case fullTimer
    case delimiters
    case numbers
    case dot
    case tint

    static func fromWire(_ value: String?) -> WatchFlashStyle {
        guard let value else { return .off }
        switch value.lowercased() {
        case "fulltimer":
            return .fullTimer
        case "delimiters":
            return .delimiters
        case "numbers":
            return .numbers
        case "dot":
            return .dot
        case "tint":
            return .tint
        default:
            return .off
        }
    }
}

enum WatchFaceEventKind: Equatable {
    case stop
    case cue
    case restart
    case message
    case image
    case empty
}

struct WatchFaceEvent {
    let kind: WatchFaceEventKind
    let time: TimeInterval
}

struct WatchGlassCard<Content: View>: View {
    let tint: Color?
    let flashOverlay: Color?
    let content: Content

    init(tint: Color? = nil, flashOverlay: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.flashOverlay = flashOverlay
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    glassBackground(in: shape)
                    if let flashOverlay {
                        shape.fill(flashOverlay)
                    }
                }
            )
            .overlay(shape.stroke(rimColor, lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 0.5)
    }

    private var rimColor: Color {
        (tint ?? .white).opacity(0.18)
    }

    @ViewBuilder
    private func glassBackground(in shape: RoundedRectangle) -> some View {
        if #available(watchOS 26.0, *) {
            shape.fill(.thinMaterial)
            shape.fill(glassTint)
        } else {
            shape.fill(Color.white.opacity(0.12))
            shape.fill(glassTint)
        }
    }

    private var glassTint: Color {
        (tint ?? .white).opacity(0.10)
    }
}

struct WatchChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

struct WatchIconChip: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(6)
            .background(Circle().fill(tint.opacity(0.15)))
    }
}

struct WatchTimerHeader: View {
    let formattedMain: String
    let stopLine: String?
    let accent: Color
    let isStale: Bool
    let size: CGFloat
    let isLive: Bool
    let alignment: HorizontalAlignment
    let frameAlignment: Alignment
    let timerProviders: WatchTimerProviders
    let nowUptime: TimeInterval
    let snapshotToken: UInt64?
    let isFlashingNow: Bool
    let flashStyle: WatchFlashStyle
    let flashColor: Color

    var body: some View {
        headerStack
        .opacity(isStale ? 0.7 : 1.0)
    }

    @ViewBuilder
    private var headerStack: some View {
        VStack(alignment: alignment, spacing: 4) {
            Group {
                WatchTimerFlashText(
                    nowUptime: nowUptime,
                    isLive: isLive,
                    formattedProvider: timerProviders.formattedStringProvider,
                    fallback: formattedMain,
                    snapshotToken: snapshotToken,
                    isFlashingNow: isFlashingNow,
                    flashStyle: flashStyle,
                    flashColor: flashColor
                )
            }
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: frameAlignment)

            if stopLine != nil {
                Group {
                if isLive {
                    WatchTimerLiveText(
                        nowUptime: nowUptime,
                        timeProvider: timerProviders.stopValueProvider,
                        formattedProvider: { nowUptime in
                            timerProviders.stopLineProvider(nowUptime) ?? ""
                        },
                        fallback: stopLine ?? "",
                        snapshotToken: snapshotToken
                        )
                    } else if let stopLine {
                        Text(stopLine)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
    }
}

struct WatchFacePage: View {
    let renderModel: WatchNowRenderModel
    let timerProviders: WatchTimerProviders
    let nowUptime: TimeInterval
    let isLive: Bool
    let snapshotToken: UInt64
    let startStop: () -> Void
    let reset: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            WatchGlassCard(
                tint: renderModel.accent,
                flashOverlay: (renderModel.isFlashingNow && renderModel.flashStyle == .tint)
                    ? renderModel.flashColor.opacity(0.18)
                    : nil
            ) {
                VStack(alignment: .center, spacing: 8) {
                    WatchTimerHeader(
                        formattedMain: renderModel.formattedMain,
                        stopLine: nil,
                        accent: renderModel.accent,
                        isStale: renderModel.isStale,
                        size: 40,
                        isLive: isLive,
                        alignment: .center,
                        frameAlignment: .center,
                        timerProviders: timerProviders,
                        nowUptime: nowUptime,
                        snapshotToken: snapshotToken,
                        isFlashingNow: renderModel.isFlashingNow,
                        flashStyle: renderModel.flashStyle,
                        flashColor: renderModel.flashColor
                    )
                    if renderModel.isStopActive {
                        Group {
                            if isLive {
                                WatchTimerLiveText(
                                    nowUptime: nowUptime,
                                    timeProvider: timerProviders.stopValueProvider,
                                    formattedProvider: timerProviders.stopDigitsProvider,
                                    fallback: renderModel.stopDigits,
                                    snapshotToken: snapshotToken
                                )
                            } else {
                                Text(renderModel.stopDigits)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    chipRow
                    faceEventsRow
                    controlsRow
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            phaseChip
            WatchChip(
                text: renderModel.isStale ? "STALE" : "FRESH",
                tint: renderModel.isStale ? .orange : .green
            )
            if let iconName = renderModel.linkIconName {
                WatchIconChip(systemName: iconName, tint: .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var phaseChip: some View {
        WatchChip(text: renderModel.phaseLabel, tint: renderModel.accent)
            .id(renderModel.phaseLabel)
            .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1.0 : 0.98)))
            .animation(.easeInOut(duration: 0.2), value: renderModel.phaseLabel)
    }

    private var faceEventsRow: some View {
        WatchFaceEventsRow(
            eventKinds: eventKinds,
            phaseLabel: renderModel.phaseLabel,
            isStopActive: renderModel.isStopActive,
            stopDigits: renderModel.stopDigits,
            accent: renderModel.accent,
            isLive: isLive,
            nowUptime: nowUptime,
            timerProviders: timerProviders,
            snapshotToken: snapshotToken
        )
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button(action: reset) {
                Text("Reset")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(!renderModel.canReset)

            Button(action: startStop) {
                Text(renderModel.isCounting ? "Stop" : "Start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(!renderModel.canStartStop)
        }
        .tint(renderModel.accent)
    }

    private var eventKinds: [WatchFaceEventKind] {
        let kinds = renderModel.faceEvents.prefix(5).map(\.kind)
        if kinds.count >= 5 { return Array(kinds) }
        return kinds + Array(repeating: .empty, count: 5 - kinds.count)
    }
}

struct WatchTimerFocusPage: View {
    let renderModel: WatchNowRenderModel
    let timerProviders: WatchTimerProviders
    let nowUptime: TimeInterval
    let isLive: Bool
    let snapshotToken: UInt64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    timerVignette
                    timerStack
                }

                WatchFaceEventsSubtleRow(
                    eventKinds: eventKinds,
                    flashColor: renderModel.flashColor
                )
                .padding(.trailing, 6)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(8)
    }

    private var timerStack: some View {
        ZStack {
            WatchBigTimerText(
                text: mainText,
                keeper: keeperText,
                fontSize: 56
            )
            .opacity(renderModel.isStopActive ? 0 : 1)

            WatchBigTimerText(
                text: stopText,
                keeper: keeperText,
                fontSize: 56
            )
            .foregroundStyle(.red)
            .opacity(renderModel.isStopActive ? 1 : 0)
            .scaleEffect(renderModel.isStopActive ? 1.0 : (reduceMotion ? 1.0 : 0.99))
        }
        .offset(y: -8)
        .animation(.easeInOut(duration: 0.2), value: renderModel.isStopActive)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var timerVignette: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color.primary.opacity(0.12),
                Color.primary.opacity(0.02),
                Color.clear
            ]),
            center: .center,
            startRadius: 10,
            endRadius: 120
        )
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }

    private var mainText: String {
        if isLive {
            return timerProviders.compactMainStringProvider(nowUptime)
        }
        return renderModel.compactMain
    }

    private var stopText: String {
        if isLive {
            return timerProviders.compactStopStringProvider(nowUptime)
        }
        return renderModel.compactStop
    }

    private var keeperText: String {
        let display = renderModel.isStopActive ? stopText : mainText
        let trimmed = display.trimmingCharacters(in: .whitespaces)
        let colonCount = trimmed.filter { $0 == ":" }.count
        switch colonCount {
        case 2:
            return "88:88:88.88"
        case 1:
            return "88:88.88"
        default:
            return "88.88"
        }
    }

    private var eventKinds: [WatchFaceEventKind] {
        let kinds = renderModel.faceEvents.prefix(5).map(\.kind)
        if kinds.count >= 5 { return Array(kinds) }
        return kinds + Array(repeating: .empty, count: 5 - kinds.count)
    }

    private var accessibilityLabel: String {
        let freshness = renderModel.isStale ? "Stale" : "Fresh"
        let phase = renderModel.phaseLabel.capitalized
        let value = renderModel.isStopActive ? stopText : mainText
        return "\(phase), \(freshness), \(value)"
    }
}

struct WatchControlsPage: View {
    let renderModel: WatchNowRenderModel
    let timerProviders: WatchTimerProviders
    let nowUptime: TimeInterval
    let isLive: Bool
    let snapshotToken: UInt64
    let startStop: () -> Void
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            WatchGlassCard(
                tint: renderModel.accent,
                flashOverlay: (renderModel.isFlashingNow && renderModel.flashStyle == .tint)
                    ? renderModel.flashColor.opacity(0.18)
                    : nil
            ) {
                WatchTimerHeader(
                    formattedMain: renderModel.formattedMain,
                    stopLine: renderModel.stopLine,
                    accent: renderModel.accent,
                    isStale: renderModel.isStale,
                    size: 38,
                    isLive: isLive,
                    alignment: .leading,
                    frameAlignment: .leading,
                    timerProviders: timerProviders,
                    nowUptime: nowUptime,
                    snapshotToken: snapshotToken,
                    isFlashingNow: renderModel.isFlashingNow,
                    flashStyle: renderModel.flashStyle,
                    flashColor: renderModel.flashColor
                )
                .padding(.vertical, -2)
            }

            WatchGlassCard(tint: renderModel.accent) {
                VStack(spacing: 10) {
                    Button {
                        ConnectivityManager.shared.sendCommand(renderModel.isCounting ? .stop : .start)
                    } label: {
                        Text(renderModel.isCounting ? "Stop" : "Start")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!renderModel.canStartStop)

                    Button(action: reset) {
                        Text("Reset")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!renderModel.canReset)

                    if let hint = renderModel.lockHint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .tint(renderModel.accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

struct WatchCueSheetsPage: View {
    let renderModel: WatchNowRenderModel
    let cueSheetsModel: WatchCueSheetsModel
    @Binding var selectedSheetID: UUID?
    let requestCueSheetIndex: () -> Void

    #if DEBUG
    private static let showCueSheetDebugOverlay = false
    #endif

    var body: some View {
        VStack(spacing: 10) {
            WatchGlassCard(tint: renderModel.accent) {
                VStack(alignment: .leading, spacing: 8) {
                    headerRow
                    primaryPanel
                    if shouldShowFooterEvents {
                        footerRow
                    }
                    #if DEBUG
                    cueSheetDebugOverlay
                    #endif
                }
                .padding(.top, 4)
            }
            .overlay(lockedBorder)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .onAppear {
            requestCueSheetIndex()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            WatchChip(text: statusText, tint: statusTint)
            Spacer(minLength: 4)
            WatchIconChip(systemName: connectionIconName, tint: .secondary)
        }
    }

    @ViewBuilder
    private var primaryPanel: some View {
        switch cueSheetsModel.role {
        case .child:
            childPanel
        case .parent, .solo:
            if cueSheetsModel.isConnected && cueSheetsModel.role == .parent {
                parentPanel
            } else {
                localPanel
            }
        }
    }

    private var localPanel: some View {
        let interactionsDisabled = cueSheetsModel.isStale
        return VStack(alignment: .leading, spacing: 8) {
            cueSheetList(allowsSelection: false, actionLabel: "Load") { summary in
                ConnectivityManager.shared.send(ControlRequest(.loadCueSheet, cueSheetID: summary.id))
            }

            if cueSheetsModel.loadedSheetName != nil {
                Button(action: {
                    ConnectivityManager.shared.send(ControlRequest(.dismissCueSheet))
                }) {
                    Text("Dismiss Sheet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .opacity(interactionsDisabled ? 0.6 : 1.0)
        .disabled(interactionsDisabled)
        .tint(renderModel.accent)
    }

    private var parentPanel: some View {
        let interactionsDisabled = cueSheetsModel.isStale
        return VStack(alignment: .leading, spacing: 8) {
            cueSheetList(allowsSelection: true, actionLabel: "Select") { summary in
                selectedSheetID = summary.id
            }

            Button(action: {
                if let selectedSheetID {
                    ConnectivityManager.shared.send(ControlRequest(.broadcastCueSheet, cueSheetID: selectedSheetID))
                }
            }) {
                Text("Broadcast to Children")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(interactionsDisabled || selectedSheetID == nil)
        }
        .opacity(interactionsDisabled ? 0.6 : 1.0)
        .disabled(interactionsDisabled)
        .tint(renderModel.accent)
    }

    private var childPanel: some View {
        let interactionsDisabled = cueSheetsModel.isStale
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cueSheetsModel.isConnected ? "Locked to parent" : "Awaiting parent")
                    .font(.footnote.weight(.semibold))
                Text(lockedDetailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .opacity(interactionsDisabled ? 0.6 : 1.0)

            #if DEBUG
            Button(action: {
                ConnectivityManager.shared.requestSnapshot(origin: "watch.cueSheets.refresh")
            }) {
                Text("Request Refresh")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(renderModel.accent)
            #endif
        }
    }

    private func cueSheetList(
        allowsSelection: Bool,
        actionLabel: String,
        action: @escaping (WatchCueSheetSummary) -> Void
    ) -> some View {
        Group {
            if cueSheetsModel.sheets.isEmpty {
                Text("No cue sheets")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cueSheetsModel.sheets) { summary in
                            WatchCueSheetRow(
                                summary: summary,
                                accent: renderModel.accent,
                                isSelected: allowsSelection && summary.id == selectedSheetID,
                                showsSelection: allowsSelection
                            ) {
                                action(summary)
                            }
                            .accessibilityLabel(Text("\(actionLabel) \(summary.name)"))
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
    }

    private var footerRow: some View {
        HStack {
            Spacer()
            WatchFaceEventsSubtleRow(
                eventKinds: eventKinds,
                flashColor: renderModel.flashColor
            )
            .scaleEffect(0.75)
            .opacity(0.6)
        }
    }

    private var shouldShowFooterEvents: Bool {
        if cueSheetsModel.isLockedFromParent {
            return cueSheetsModel.loadedSheetName != nil
        }
        return cueSheetsModel.loadedSheetName != nil
    }

    #if DEBUG
    @ViewBuilder
    private var cueSheetDebugOverlay: some View {
        if Self.showCueSheetDebugOverlay {
            let reachableText = cueSheetsModel.isReachable.map { $0 ? "reachable" : "notReachable" } ?? "nil"
            Text("sheets:\(cueSheetsModel.sheets.count) source:\(cueSheetsModel.cueSheetIndexSource.rawValue) wc:\(cueSheetsModel.activationStateLabel) reach:\(reachableText)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
    #endif

    private var eventKinds: [WatchFaceEventKind] {
        let kinds = renderModel.faceEvents.prefix(5).map(\.kind)
        if kinds.count >= 5 { return Array(kinds) }
        return kinds + Array(repeating: .empty, count: 5 - kinds.count)
    }

    private var statusText: String {
        if cueSheetsModel.isLockedFromParent {
            return "From Parent: \(cueSheetsModel.loadedSheetName ?? "None")"
        }
        if let loaded = cueSheetsModel.loadedSheetName {
            return "Loaded: \(loaded)"
        }
        return "Cue sheets"
    }

    private var statusTint: Color {
        cueSheetsModel.isLockedFromParent ? .orange : renderModel.accent
    }

    private var connectionIconName: String {
        if cueSheetsModel.isLockedFromParent {
            return "lock.fill"
        }
        if cueSheetsModel.role == .parent && cueSheetsModel.isConnected {
            return "antenna.radiowaves.left.and.right"
        }
        if cueSheetsModel.isConnected {
            return "link"
        }
        return "iphone"
    }

    private var lockedDetailText: String {
        if let loaded = cueSheetsModel.loadedSheetName {
            return "Using \(loaded)"
        }
        return cueSheetsModel.isConnected ? "No sheet from parent yet." : "Connect to sync cue sheets."
    }

    private var lockedBorder: some View {
        Group {
            if cueSheetsModel.isLockedFromParent {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        renderModel.accent.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
        }
    }
}

struct WatchNextEventDialPage: View {
    let model: WatchNextEventDialModel
    let nowUptime: TimeInterval

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var lastQuantizedProgress: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = ringLineWidth(for: size)
            let trackColor = Color.secondary.opacity(0.18)
            let dimOpacity = (model.isStale || isLuminanceReduced) ? 0.6 : 1.0
            let isFlashColorRed = model.flashColorIsRed ?? isRedColor(model.accent)
            let normalAccent = isFlashColorRed ? Color.white.opacity(0.85) : model.accent
            let stopRemaining = model.stopRemainingProvider(nowUptime)
            let stopInterval = model.stopInterval ?? 0
            let isStopMode = model.isStopActive && stopRemaining >= 0
            let stopProgress: Double? = {
                guard isStopMode else { return nil }
                if stopInterval > 0 {
                    return (stopRemaining / stopInterval).clamped(to: 0...1)
                }
                return 0.25
            }()
            let rawProgress = isStopMode ? stopProgress : dialProgress(nowUptime: nowUptime)
            let displayProgress = isStopMode ? rawProgress : rawProgress.map { resolvedProgress($0) }

            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: lineWidth)

                if let displayProgress {
                    let trimmed = displayProgress == 0 ? 0.001 : displayProgress
                    if isStopMode {
                        let stopStroke = stopStrokeStyle(
                            lineWidth: lineWidth,
                            useStencil: isFlashColorRed
                        )
                        Circle()
                            .trim(from: 0, to: trimmed)
                            .stroke(Color.red, style: stopStroke)
                            .rotationEffect(.degrees(-90))
                            .scaleEffect(x: -1, y: 1)
                            .id(model.snapshotToken)
                    } else {
                        Circle()
                            .trim(from: 0, to: trimmed)
                            .stroke(
                                normalAccent,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: normalAccent.opacity(0.25), radius: 2, x: 0, y: 0)
                            .id(model.snapshotToken)

                        if displayProgress > 0.02 {
                            Circle()
                                .fill(normalAccent.opacity(0.9))
                                .frame(width: lineWidth * 0.45, height: lineWidth * 0.45)
                                .offset(y: -size / 2)
                                .rotationEffect(.degrees(displayProgress * 360.0))
                        }
                    }
                }

                markerGlyph
                    .offset(y: -size / 2 + lineWidth * 0.2)
            }
            .opacity(dimOpacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(12)
            .onChange(of: model.resetToken) { _ in
                lastQuantizedProgress = 0
            }
            .onChange(of: displayProgress ?? 0) { newValue in
                if model.scheduleState == .active && !isStopMode {
                    lastQuantizedProgress = max(lastQuantizedProgress, newValue)
                } else {
                    lastQuantizedProgress = 0
                }
            }
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func ringLineWidth(for size: CGFloat) -> CGFloat {
        max(6, min(9, size * 0.055))
    }

    private func dialProgress(nowUptime: TimeInterval) -> Double? {
        switch model.scheduleState {
        case .none:
            return nil
        case .complete:
            return 1
        case .active:
            guard let interval = model.nextEventInterval, interval > 0,
                  var remaining = model.remainingProvider(nowUptime) else { return nil }
            remaining = max(0, remaining)
            if model.isStepped {
                let stepSeconds: TimeInterval = 0.1
                remaining = (remaining / stepSeconds).rounded(.down) * stepSeconds
            }
            let ratio = (remaining / interval).clamped(to: 0...1)
            return 1.0 - ratio
        }
    }

    private func resolvedProgress(_ raw: Double) -> Double {
        if model.scheduleState == .active {
            return max(lastQuantizedProgress, raw)
        }
        return raw
    }

    private var markerGlyph: some View {
        let name: String? = {
            if model.isStopActive {
                return glyphName(for: .stop)
            }
            switch model.scheduleState {
            case .none:
                return "minus"
            case .complete:
                return "checkmark"
            case .active:
                return glyphName(for: model.nextEventKind)
            }
        }()
        return Group {
            if let name {
                Image(systemName: name)
                    .font(.caption2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.secondary)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 3, height: 3)
            }
        }
    }

    private func glyphName(for kind: WatchNextEventKind) -> String? {
        switch kind {
        case .cue:
            return "bolt.fill"
        case .restart:
            return "arrow.counterclockwise"
        case .stop:
            return "playpause"
        case .message:
            return "text.quote"
        case .image:
            return "mountain.2"
        case .unknown:
            return "line.3.horizontal"
        }
    }

    private var accessibilityLabel: String {
        let freshness = model.isStale ? "stale" : "fresh"
        if model.isStopActive {
            let remaining = model.stopRemainingProvider(nowUptime)
            return "Stop hold \(formatDuration(remaining)), \(freshness)"
        }
        switch model.scheduleState {
        case .none:
            return "No cue sheet loaded, \(freshness)"
        case .complete:
            return "Cue sheet complete, \(freshness)"
        case .active:
            if let remaining = model.remainingProvider(nowUptime) {
                return "Next event in \(formatDuration(remaining)), \(freshness)"
            }
            return "Next event, \(freshness)"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, seconds)) ?? "0 seconds"
    }

    private func stopStrokeStyle(lineWidth: CGFloat, useStencil: Bool) -> StrokeStyle {
        if useStencil {
            let dash = max(2, lineWidth * 0.6)
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [dash, dash])
        }
        return StrokeStyle(lineWidth: lineWidth, lineCap: .round)
    }

    private func isRedColor(_ color: Color) -> Bool {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return false
        }
        let tolerance: CGFloat = 0.2
        return r > 0.8 && g < tolerance && b < tolerance && a > 0.4
        #else
        return false
        #endif
    }
}

private struct WatchFaceEventsRow: View, Equatable {
    let eventKinds: [WatchFaceEventKind]
    let phaseLabel: String
    let isStopActive: Bool
    let stopDigits: String
    let accent: Color
    let isLive: Bool
    let nowUptime: TimeInterval
    let timerProviders: WatchTimerProviders
    let snapshotToken: UInt64

    static func == (lhs: WatchFaceEventsRow, rhs: WatchFaceEventsRow) -> Bool {
        lhs.eventKinds == rhs.eventKinds &&
        lhs.phaseLabel == rhs.phaseLabel &&
        lhs.isStopActive == rhs.isStopActive &&
        lhs.stopDigits == rhs.stopDigits &&
        lhs.snapshotToken == rhs.snapshotToken
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(Array(eventKinds.enumerated()), id: \.offset) { _, kind in
                        WatchFaceEventCircle(kind: kind, accent: accent)
                    }
                }
                if isStopActive {
                    Group {
                        if isLive {
                            WatchTimerLiveText(
                                nowUptime: nowUptime,
                                timeProvider: timerProviders.stopValueProvider,
                                formattedProvider: timerProviders.stopDigitsProvider,
                                fallback: stopDigits,
                                snapshotToken: snapshotToken
                            )
                        } else {
                            Text(stopDigits)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct WatchTimerLiveText: View {
    let nowUptime: TimeInterval
    let timeProvider: (TimeInterval) -> TimeInterval
    let formattedProvider: (TimeInterval) -> String
    let fallback: String
    let snapshotToken: UInt64?

    var body: some View {
        let text = formattedProvider(nowUptime)
        return Text(text.isEmpty ? fallback : text)
            .id(snapshotToken ?? 0)
    }
}

private struct WatchTimerFlashText: View {
    let nowUptime: TimeInterval
    let isLive: Bool
    let formattedProvider: (TimeInterval) -> String
    let fallback: String
    let snapshotToken: UInt64?
    let isFlashingNow: Bool
    let flashStyle: WatchFlashStyle
    let flashColor: Color

    var body: some View {
        let text = isLive ? formattedProvider(nowUptime) : fallback
        let display = text.isEmpty ? fallback : text
        return ZStack(alignment: .topTrailing) {
            if isFlashingNow, (flashStyle == .numbers || flashStyle == .delimiters) {
                Text(flashAttributedString(for: display))
            } else {
                Text(display)
                    .foregroundStyle(flashForeground)
            }
            if isFlashingNow, flashStyle == .dot {
                Circle()
                    .fill(flashColor)
                    .frame(width: 8, height: 8)
                    .offset(x: 6, y: -6)
            }
        }
        .id(snapshotToken ?? 0)
    }

    private var flashForeground: Color {
        guard isFlashingNow else { return .primary }
        switch flashStyle {
        case .fullTimer, .tint:
            return flashColor
        default:
            return .primary
        }
    }

    private func flashAttributedString(for text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for index in attributed.characters.indices {
            let ch = attributed.characters[index]
            let isDelimiter = ch == ":" || ch == "."
            let shouldFlash: Bool
            switch flashStyle {
            case .delimiters:
                shouldFlash = isDelimiter
            case .numbers:
                shouldFlash = !isDelimiter
            default:
                shouldFlash = false
            }
            attributed[index...index].foregroundColor = shouldFlash ? flashColor : .primary
        }
        return attributed
    }
}

private struct WatchBigTimerText: View {
    let text: String
    let keeper: String
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            Text(keeper)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .opacity(0)

            Text(styledText)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var font: Font {
        .system(size: fontSize, weight: .semibold, design: .rounded)
    }

    private var styledText: AttributedString {
        var attributed = AttributedString(text)
        if text.hasPrefix("−"), let first = attributed.characters.indices.first {
            attributed[first...first].foregroundColor = .primary.opacity(0.6)
        }
        return attributed
    }
}

private struct WatchFaceEventsSubtleRow: View {
    let eventKinds: [WatchFaceEventKind]
    let flashColor: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(eventKinds.enumerated()), id: \.offset) { _, kind in
                WatchFaceEventSubtleCircle(kind: kind, accent: flashColor)
            }
        }
    }
}

private struct WatchFaceEventSubtleCircle: View {
    let kind: WatchFaceEventKind
    let accent: Color

    var body: some View {
        ZStack {
            circle
                .frame(width: 11, height: 11)
            icon
        }
    }

    private var strokeColor: Color {
        accent.opacity(0.7)
    }

    @ViewBuilder
    private var circle: some View {
        switch kind {
        case .stop:
            Circle().fill(accent.opacity(0.85))
        case .message:
            Circle()
                .fill(accent.opacity(0.15))
                .overlay(Circle().stroke(strokeColor, lineWidth: 0.9))
        case .cue, .restart, .image:
            Circle().stroke(strokeColor, lineWidth: 0.9)
        case .empty:
            Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var icon: some View {
        let size: Font = .caption2
        switch kind {
        case .stop:
            Image(systemName: "playpause")
                .font(size.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        case .cue:
            Image(systemName: "bolt.fill")
                .font(size.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(strokeColor)
        case .restart:
            Image(systemName: "arrow.counterclockwise")
                .font(size.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(strokeColor)
        case .message:
            Image(systemName: "text.quote")
                .font(size.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(strokeColor)
        case .image:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.8)
                    .frame(width: 7, height: 5.5)
                Image(systemName: "mountain.2")
                    .font(size.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(strokeColor)
            }
        case .empty:
            EmptyView()
        }
    }
}

private struct WatchCueSheetRow: View {
    let summary: WatchCueSheetSummary
    let accent: Color
    let isSelected: Bool
    let showsSelection: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsSelection {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .opacity(isSelected ? 1.0 : 0.2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    if let cueCount = summary.cueCount {
                        Text("\(cueCount) cues")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}

private struct WatchEventDotsRow: View {
    let eventDots: [WatchEventDot]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(eventDots.prefix(5))) { dot in
                WatchEventDotView(dot: dot)
            }
            if eventDots.isEmpty {
                Text("No events")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct WatchEventDotView: View {
    let dot: WatchEventDot

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var color: Color {
        switch dot.kind {
        case .stop: return .red
        case .cue: return .orange
        case .restart: return .blue
        }
    }

    private var label: String {
        switch dot.kind {
        case .stop: return "S"
        case .cue: return "C"
        case .restart: return "R"
        }
    }
}

private struct WatchFaceEventCircle: View {
    let kind: WatchFaceEventKind
    let accent: Color

    var body: some View {
        ZStack {
            circle
                .frame(width: 22, height: 22)
            icon
        }
    }

    @ViewBuilder
    private var circle: some View {
        switch kind {
        case .stop:
            Circle().fill(accent)
        case .message:
            Circle()
                .fill(accent.opacity(0.18))
                .overlay(Circle().stroke(accent, lineWidth: 1.2))
        case .cue, .restart, .image:
            Circle().stroke(accent, lineWidth: 1.4)
        case .empty:
            Circle().stroke(Color.secondary.opacity(0.45), lineWidth: 1.2)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .stop:
            Image(systemName: "playpause")
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        case .cue:
            Image(systemName: "bolt.fill")
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
        case .restart:
            Image(systemName: "arrow.counterclockwise")
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
        case .message:
            Image(systemName: "text.quote")
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
        case .image:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(accent, lineWidth: 1.0)
                    .frame(width: 12, height: 9)
                Image(systemName: "mountain.2")
                    .font(.caption2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
        case .empty:
            EmptyView()
        }
    }
}

#Preview {
    WatchFacePage(
        renderModel: WatchNowRenderModel(
            formattedMain: "12:34.56",
            compactMain: "12:34.56",
            phaseLabel: "RUNNING",
            isStale: false,
            stopLine: nil,
            stopDigits: "00:10.00",
            compactStop: "00:10.00",
            isStopActive: true,
            isCounting: true,
            canStartStop: true,
            canReset: false,
            lockHint: "Reset available when stopped",
            linkIconName: "iphone",
            faceEvents: [
                WatchFaceEvent(kind: .stop, time: 10),
                WatchFaceEvent(kind: .cue, time: 8),
                WatchFaceEvent(kind: .restart, time: 5)
            ],
            accent: .red,
            isFlashingNow: true,
            flashStyle: .fullTimer,
            flashColor: .red
        ),
        timerProviders: WatchTimerProviders(
            mainValueProvider: { _ in 0 },
            stopValueProvider: { _ in 0 },
            formattedStringProvider: { _ in "12:34.56" },
            stopLineProvider: { _ in nil },
            stopDigitsProvider: { _ in "00:10.00" },
            compactMainStringProvider: { _ in "3.95" },
            compactStopStringProvider: { _ in "3.95" }
        ),
        nowUptime: 0,
        isLive: false,
        snapshotToken: 0,
        startStop: {},
        reset: {}
    )
}
