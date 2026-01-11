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
    let nowUptimeProvider: () -> TimeInterval
    let mainValueProvider: (TimeInterval) -> TimeInterval
    let stopValueProvider: (TimeInterval) -> TimeInterval
    let formattedStringProvider: (TimeInterval) -> String
    let stopLineProvider: (TimeInterval) -> String?
    let stopDigitsProvider: (TimeInterval) -> String
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

enum WatchFaceEventKind {
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
    let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(glassBackground(in: shape))
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
    let timerProviders: WatchTimerProviders

    var body: some View {
        headerStack
        .opacity(isStale ? 0.7 : 1.0)
    }

    @ViewBuilder
    private var headerStack: some View {
        VStack(spacing: 4) {
            Group {
                if isLive {
                    WatchTimerLiveText(
                        nowUptimeProvider: timerProviders.nowUptimeProvider,
                        timeProvider: timerProviders.mainValueProvider,
                        formattedProvider: timerProviders.formattedStringProvider,
                        fallback: formattedMain
                    )
                } else {
                    Text(formattedMain)
                }
            }
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            if stopLine != nil {
                Group {
                    if isLive {
                        WatchTimerLiveText(
                            nowUptimeProvider: timerProviders.nowUptimeProvider,
                            timeProvider: timerProviders.stopValueProvider,
                            formattedProvider: { nowUptime in
                                timerProviders.stopLineProvider(nowUptime) ?? ""
                            },
                            fallback: stopLine ?? ""
                        )
                    } else if let stopLine {
                        Text(stopLine)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WatchFacePage: View {
    let renderModel: WatchNowRenderModel
    let timerProviders: WatchTimerProviders
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            WatchGlassCard(tint: renderModel.accent) {
                VStack(alignment: .leading, spacing: 8) {
                    WatchTimerHeader(
                        formattedMain: renderModel.formattedMain,
                        stopLine: nil,
                        accent: renderModel.accent,
                        isStale: renderModel.isStale,
                        size: 40,
                        isLive: isLive,
                        timerProviders: timerProviders
                    )
                    chipRow
                    faceEventsRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(eventKinds.enumerated()), id: \.offset) { _, kind in
                    WatchFaceEventCircle(kind: kind, accent: renderModel.accent)
                }
            }
            Spacer(minLength: 4)
            Group {
                if isLive {
                    WatchTimerLiveText(
                        nowUptimeProvider: timerProviders.nowUptimeProvider,
                        timeProvider: timerProviders.stopValueProvider,
                        formattedProvider: timerProviders.stopDigitsProvider,
                        fallback: renderModel.stopDigits
                    )
                } else {
                    Text(renderModel.stopDigits)
                }
            }
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(renderModel.isStopActive ? renderModel.accent : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    private var eventKinds: [WatchFaceEventKind] {
        let kinds = renderModel.faceEvents.prefix(5).map(\.kind)
        if kinds.count >= 5 { return Array(kinds) }
        return kinds + Array(repeating: .empty, count: 5 - kinds.count)
    }
}

struct WatchDetailsPage: View {
    let renderModel: WatchNowRenderModel
    let detailsModel: WatchNowDetailsModel
    let timerProviders: WatchTimerProviders
    let isLive: Bool

    var body: some View {
        VStack(spacing: 8) {
            WatchGlassCard(tint: renderModel.accent) {
                WatchTimerHeader(
                    formattedMain: renderModel.formattedMain,
                    stopLine: renderModel.stopLine,
                    accent: renderModel.accent,
                    isStale: renderModel.isStale,
                    size: 32,
                    isLive: isLive,
                    timerProviders: timerProviders
                )
            }

            ScrollView {
                VStack(spacing: 10) {
                    WatchGlassCard(tint: renderModel.accent) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Events")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            WatchEventDotsRow(eventDots: detailsModel.eventDots)
                            if let sheetLabel = detailsModel.sheetLabel, !sheetLabel.isEmpty {
                                Text(sheetLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    WatchGlassCard(tint: renderModel.accent) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Connection")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(connectionStatusLine)
                                .font(.footnote)
                            if let role = detailsModel.role {
                                Text("Role: \(role.capitalized)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let link = detailsModel.link {
                                Text("Link: \(link.capitalized)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var connectionStatusLine: String {
        let status = detailsModel.isFresh ? "Fresh" : "Stale"
        return "\(status) · \(formatAge(detailsModel.age))"
    }

    private func formatAge(_ age: TimeInterval) -> String {
        let tenths = Int((age * 10).rounded())
        return String(format: "%.1fs", Double(tenths) / 10)
    }
}

struct WatchControlsPage: View {
    let renderModel: WatchNowRenderModel
    let timerProviders: WatchTimerProviders
    let isLive: Bool
    let startStop: () -> Void
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            WatchGlassCard(tint: renderModel.accent) {
                WatchTimerHeader(
                    formattedMain: renderModel.formattedMain,
                    stopLine: renderModel.stopLine,
                    accent: renderModel.accent,
                    isStale: renderModel.isStale,
                    size: 30,
                    isLive: isLive,
                    timerProviders: timerProviders
                )
            }

            WatchGlassCard(tint: renderModel.accent) {
                VStack(spacing: 10) {
                    Button(action: startStop) {
                        Text(renderModel.phaseLabel == "RUNNING" || renderModel.phaseLabel == "COUNTDOWN" ? "Stop" : "Start")
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

private struct WatchTimerLiveText: View {
    let nowUptimeProvider: () -> TimeInterval
    let timeProvider: (TimeInterval) -> TimeInterval
    let formattedProvider: (TimeInterval) -> String
    let fallback: String

    @State private var lastRenderedCs: Int
    @State private var cachedString: String

    init(
        nowUptimeProvider: @escaping () -> TimeInterval,
        timeProvider: @escaping (TimeInterval) -> TimeInterval,
        formattedProvider: @escaping (TimeInterval) -> String,
        fallback: String
    ) {
        self.nowUptimeProvider = nowUptimeProvider
        self.timeProvider = timeProvider
        self.formattedProvider = formattedProvider
        self.fallback = fallback
        _lastRenderedCs = State(initialValue: Int.min)
        _cachedString = State(initialValue: fallback)
    }

    var body: some View {
        TimelineView(.animation) { _ in
            let nowUptime = nowUptimeProvider()
            let timeValue = timeProvider(nowUptime)
            let currentCs = Int((abs(timeValue) * 100).rounded())
            WatchTimerCachedText(
                currentCs: currentCs,
                nowUptime: nowUptime,
                formatter: formattedProvider,
                lastRenderedCs: $lastRenderedCs,
                cachedString: $cachedString
            )
        }
    }
}

private struct WatchTimerCachedText: View {
    let currentCs: Int
    let nowUptime: TimeInterval
    let formatter: (TimeInterval) -> String
    @Binding var lastRenderedCs: Int
    @Binding var cachedString: String

    var body: some View {
        Text(cachedString)
            .onAppear { updateIfNeeded(nowUptime: nowUptime) }
            .onChange(of: currentCs) { _ in
                updateIfNeeded(nowUptime: nowUptime)
            }
    }

    private func updateIfNeeded(nowUptime: TimeInterval) {
        guard currentCs != lastRenderedCs else { return }
        lastRenderedCs = currentCs
        cachedString = formatter(nowUptime)
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
            phaseLabel: "RUNNING",
            isStale: false,
            stopLine: nil,
            stopDigits: "00:10.00",
            isStopActive: true,
            canStartStop: true,
            canReset: false,
            lockHint: "Reset available when stopped",
            linkIconName: "iphone",
            faceEvents: [
                WatchFaceEvent(kind: .stop, time: 10),
                WatchFaceEvent(kind: .cue, time: 8),
                WatchFaceEvent(kind: .restart, time: 5)
            ],
            accent: .red
        ),
        timerProviders: WatchTimerProviders(
            nowUptimeProvider: { 0 },
            mainValueProvider: { _ in 0 },
            stopValueProvider: { _ in 0 },
            formattedStringProvider: { _ in "12:34.56" },
            stopLineProvider: { _ in nil },
            stopDigitsProvider: { _ in "00:10.00" }
        ),
        isLive: false
    )
}
