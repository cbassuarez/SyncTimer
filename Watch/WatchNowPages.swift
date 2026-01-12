import Foundation
import SwiftUI

struct WatchNowDetailsModel {
    let isFresh: Bool
    let age: TimeInterval
    let role: String?
    let link: String?
    let sheetLabel: String?
    let eventDots: [WatchEventDot]
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
            .overlay(shape.stroke(rimColor, lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 0.5)
    }

    private var rimColor: Color {
        (tint ?? .white).opacity(0.14)
    }

    @ViewBuilder
    private func glassBackground(in shape: RoundedRectangle) -> some View {
        if #available(watchOS 26.0, *) {
            shape.fill(.ultraThinMaterial)
        } else {
            shape.fill(Color.white.opacity(0.08))
        }
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
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
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
