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
    let formattedStringProvider: (TimeInterval) -> String
    let stopLineProvider: (TimeInterval) -> String?
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
        Group {
            if isLive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    let nowUptime = timerProviders.nowUptimeProvider()
                    let liveMain = timerProviders.formattedStringProvider(nowUptime)
                    let liveStopLine = timerProviders.stopLineProvider(nowUptime)
                    headerStack(formattedMain: liveMain, stopLine: liveStopLine)
                }
            } else {
                headerStack(formattedMain: formattedMain, stopLine: stopLine)
            }
        }
        .opacity(isStale ? 0.7 : 1.0)
    }

    @ViewBuilder
    private func headerStack(formattedMain: String, stopLine: String?) -> some View {
        VStack(spacing: 4) {
            Text(formattedMain)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let stopLine {
                Text(stopLine)
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
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            WatchGlassCard(tint: renderModel.accent) {
                ZStack {
                    ringView
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 6) {
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
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .onAppear {
            guard shouldPulse else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
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

    private var shouldPulse: Bool {
        renderModel.phaseLabel == "RUNNING" && !reduceMotion && !isLuminanceReduced
    }

    private var ringView: some View {
        Circle()
            .stroke(renderModel.accent.opacity(ringOpacity), lineWidth: 3)
            .padding(4)
            .opacity(shouldPulse ? (pulse ? 0.5 : 0.9) : 0.8)
    }

    private var ringOpacity: Double {
        switch renderModel.phaseLabel {
        case "COUNTDOWN":
            return 0.65
        case "RUNNING":
            return 0.7
        default:
            return 0.35
        }
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

#Preview {
    WatchFacePage(
        renderModel: WatchNowRenderModel(
            formattedMain: "12:34.56",
            phaseLabel: "RUNNING",
            isStale: false,
            stopLine: nil,
            canStartStop: true,
            canReset: false,
            lockHint: "Reset available when stopped",
            linkIconName: "iphone",
            accent: .red
        ),
        timerProviders: WatchTimerProviders(
            nowUptimeProvider: { 0 },
            formattedStringProvider: { _ in "12:34.56" },
            stopLineProvider: { _ in nil }
        ),
        isLive: false
    )
}
