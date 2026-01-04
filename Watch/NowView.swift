import SwiftUI
import Combine

// MARK: - Watch-only mini components (no external deps)
private struct WT_TimerCard: View {
    let formattedMain: String
    let phaseLabel   : String
    let stopLine     : String?   // "Stop 00:12.34" or nil

    var body: some View {
        VStack(spacing: 4) {
            Text(formattedMain)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)

            HStack(spacing: 6) {
                Capsule().fill(phaseLabel == "RUNNING" ? Color.green :
                               phaseLabel == "COUNTDOWN" ? Color.orange : Color.gray)
                    .frame(width: 8, height: 8)
                Text(phaseLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let stopLine {
                Text(stopLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WT_SyncBar: View {
    let status: String   // e.g. "Fresh" / "Stale"
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(status == "Fresh" ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(0.6)   // visible but controls live on phone
        }
        .padding(.horizontal, 2)
    }
}

private struct WT_SyncBottomButtons: View {
    let isCounting: Bool
    let enabled   : Bool
    let startStop : () -> Void
    let reset     : () -> Void
    var body: some View {
        HStack {
            Button("Reset", action: reset)
                .disabled(isCounting || !enabled)

            Spacer(minLength: 12)

            Button(isCounting ? "Stop" : "Start", action: startStop)
                .disabled(!enabled)
        }
        .font(.callout)
    }
}

// MARK: - Drift-free NowView with .CC formatting (uses monotonic systemUptime)
struct NowView: View {
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

    // Tickers
    private let staleTick  = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    private let renderTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect() // 20 Hz

    // User preference: show hours when enabled; otherwise auto (>=1h shows hours)
    @State private var preferHours: Bool = UserDefaults.standard.bool(forKey: "SyncTimerPreferHours")

    private var isCounting: Bool { phaseStr == "running" || phaseStr == "countdown" }

    var body: some View {
        VStack(spacing: 8) {
            // 1) TimerCard (drift-free; shows .CC)
            WT_TimerCard(
                formattedMain: formatWithCC(displayMain, preferHours: preferHours),
                phaseLabel: phaseChip(phaseStr),
                stopLine: stopActive ? "Stop " + formatWithCC(max(0, displayStop), preferHours: false) : nil
            )
            .opacity(isStale ? 0.7 : 1.0)

            // 2) SyncBar (informational)
            WT_SyncBar(status: isStale ? "Stale" : "Fresh")
                .opacity(0.9)

            // 3) Bottom buttons (watch sends; phone gates authority)
            WT_SyncBottomButtons(
                isCounting: (phaseStr == "running"),
                enabled: !isStale,
                startStop: { ConnectivityManager.shared.sendCommand(isCounting ? .stop : .start) },
                reset:     { if !isCounting { ConnectivityManager.shared.sendCommand(.reset) } }
            )
        }
        .padding(.horizontal, 8)

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
}

// MARK: - Tiny clamp helper
private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
