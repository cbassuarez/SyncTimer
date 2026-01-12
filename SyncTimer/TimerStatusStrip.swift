import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif


@inline(__always)
private func normalizeRSSI01(_ rssi: Int) -> Double {
    // clamp typical BLE/Wi-Fi range
    let r = max(-95, min(-45, rssi))
    return (Double(r) + 95.0) / 50.0
}

@inline(__always)
private func normalizeRTT01(_ rttMs: Double) -> Double {
    // 0ms → 1.0 (great), 200ms+ → 0.0 (bad)
    let r = max(0.0, min(200.0, rttMs))
    return 1.0 - (r / 200.0)
}

// MARK: - Status model fed from TimerCard
struct TimerConnectivityStatus {
    enum SyncMode { case off, bluetooth, lan }

    // Transport (from CONNECT tab)
    var syncMode: SyncMode          // which tab is selected (BT or LAN). .off = none
    var isStreaming: Bool           // scanning/advertising on
    var isConnected: Bool           // one or more peers established

    // Role / peers
    var isParent: Bool
    var childCount: Int

    // Peripherals
    var isWatchConnected: Bool

    // Link quality (0…1) — will be mapped to dBm for display
    var strength01: Double?

    // Clock
    var driftMs: Double

    // Accessibility
    var highContrast: Bool
}

// MARK: - Strip
struct TimerStatusStrip: View {
    
    @Environment(\.padMetrics) private var MX
    @Environment(\.colorScheme) private var colorScheme   // ← add

    var status: TimerConnectivityStatus

    // Visual style
    private let iconSize: CGFloat = 12
    private let spacing: CGFloat  = 4

    var body: some View {
        HStack(spacing: MX.bp == .compact ? 6 : 10) {
            transportBadge()   // Wi-Fi / Bluetooth (tab-selected), pulses while streaming until connected
            parentBadge()      // Parent/child count badge
            watchBadge()       // Apple Watch
            signalChip()       // “−67 dBm” (text only when connected)
            driftChip()        // “±1.8 ms” (text only when connected)
        }
        .font(.system(size: iconSize, weight: .semibold, design: .rounded))
        .fixedSize(horizontal: true, vertical: true) // never affect card sizing
        .allowsHitTesting(false)                     // don’t steal taps
    }
}

// MARK: - Building blocks
private extension TimerStatusStrip {

    // Levels used for color + HC overlays
    enum Level { case off, ok, warn, error }

    // Transport (selected interface) — pulses while streaming and not yet connected
    @ViewBuilder
    func transportBadge() -> some View {
        let symbol: String = {
            switch status.syncMode {
            case .bluetooth: return "antenna.radiowaves.left.and.right"
            case .lan:       return "wifi"
            case .off:       return "wifi" // neutral visual, will be dimmed
            }
        }()

        let pulsing  = status.isStreaming && !status.isConnected
        let level: Level = status.isConnected ? .ok : (pulsing ? .warn : .off)

        TransportIcon(symbol: symbol,
                      level: level,
                      pulsing: pulsing,
                      size: iconSize,
                      highContrast: status.highContrast)
    }

    // Role + child count badge (only when parent)
    @ViewBuilder
    func parentBadge() -> some View {
        let isParent   = status.isParent
        let children   = max(0, status.childCount)
        let showBubble = isParent && children > 0
        let level: Level = .ok   // role indicator is always “on”

        ZStack(alignment: .topTrailing) {
            // Arrow icon: up = parent, down = child
            Image(systemName: isParent ? "arrow.up.circle" : "arrow.down.circle")
                .foregroundColor(iconColor(for: level))
                .opacity(1.0)

            if showBubble {
                Text(badgeText(for: children))            // “1…9” or “9+”
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Capsule().fill(Color.black))
                    .foregroundColor(.white)
                    .offset(x: 6, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) { hcMark(for: level) }
        .accessibilityLabel(isParent
                            ? (children > 0 ? "Parent, \(children) children" : "Parent")
                            : "Child")
    }


    // Watch (lights up if you pass true OR if WCSession is active/paired/reachable)
    @ViewBuilder
    func watchBadge() -> some View {
        let active: Bool = {
            #if canImport(WatchConnectivity)
            if WCSession.isSupported() {
                let s = WCSession.default
                #if os(iOS)
                if s.activationState == .activated, (s.isPaired || s.isReachable) { return true }
                #else
                if s.activationState == .activated, s.isReachable { return true }
                #endif
            }
            #endif
            return status.isWatchConnected
        }()

        let level: Level = active ? .ok : .off
        Image(systemName: "applewatch")
            .foregroundColor(iconColor(for: level))
            .opacity(baseOpacity(for: level))
            .overlay(alignment: .topTrailing) { hcMark(for: level) }
            .accessibilityLabel(active ? "Watch connected" : "Watch disconnected")
    }

    // Signal chip — shows number when connected or when we have a strength value
    @ViewBuilder
    func signalChip() -> some View {
        if !status.isConnected && status.strength01 == nil {
            Image(systemName: "waveform")
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .opacity(0.25)
                .accessibilityLabel("Signal not connected")
        } else {
            let dbm = effectiveDbm(from: status.strength01) // nil → “— dBm”
            let level = levelForSignal(dBm: dbm)

            Text(signalLabel(dBm: dbm))
                .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(chipColor(for: level))
                .overlay(alignment: .topTrailing) { hcMark(for: level) }
                .accessibilityLabel(dbm != nil ? "Signal \(dbm!) dBm" : "Signal unknown")
        }
    }


    // Drift chip — robust to unknown/NaN; shows “— ms” until you feed a real value
    @ViewBuilder
    
    func driftChip() -> some View {
        let hasNumericDrift = status.driftMs.isFinite && !status.driftMs.isNaN
        
        if !(status.isConnected || hasNumericDrift) {
            Image(systemName: "gauge")
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .opacity(0.25)
                .accessibilityLabel("Clock drift not connected")
        } else if hasNumericDrift {
            Text(driftLabel(ms: status.driftMs))
                .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                .foregroundColor(chipColor(for: levelForDrift(ms: status.driftMs)))
                .opacity(1.0)
                .overlay(alignment: .topTrailing) { hcMark(for: levelForDrift(ms: status.driftMs)) }
                .accessibilityLabel(String(format: "Clock drift %.1f milliseconds", status.driftMs))
        } else {
            Text("— ms")
                .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                .foregroundColor(chipColor(for: .off))
                .opacity(1.0)
                .overlay(alignment: .topTrailing) { hcMark(for: .off) }
                .accessibilityLabel("Clock drift unknown")
        }
    }
}

// MARK: - Helpers / Labels / Levels
private extension TimerStatusStrip {

    func badgeText(for count: Int) -> String { count <= 9 ? String(count) : "9+" }

    func signalLabel(dBm: Int?) -> String {
        guard let v = dBm else { return "— dBm" }
        return "\(v) dBm"
    }

    func driftLabel(ms: Double) -> String {
        String(format: "±%.1f ms", ms)
    }

    // Strength 0…1 → map to −95…−45 dBm
    func effectiveDbm(from q: Double?) -> Int? {
        guard let q = q else { return nil }
        let clamped = max(0.0, min(1.0, q))
        let mapped  = -95.0 + (clamped * 50.0)
        return Int(mapped.rounded())
    }

    func levelForSignal(dBm: Int?) -> Level {
        guard let r = dBm else { return .off }
        if r >= -60 { return .ok }     // strong
        if r >= -75 { return .warn }   // usable
        return .error                  // weak
    }

    func levelForDrift(ms: Double) -> Level {
        if ms <= 2   { return .ok }    // tight
        if ms <= 10  { return .warn }  // watch it
        return .error                  // too high
    }

    // Icons (transport/watch/role) follow the global color spec
    func iconColor(for level: Level) -> Color {
        switch level {
        case .ok:    return colorScheme == .dark ? .white : .black  // black/white when OK
        case .warn:  return .orange
        case .error: return .red
        case .off:   return colorScheme == .dark ? .white : .black     // dim via opacity
        }
    }

    // Chips (signal/drift) follow the revised spec: OK=gray, Warn=black, Error=red
    func chipColor(for level: Level) -> Color {
        switch level {
        case .ok:    return colorScheme == .dark ? .white : .gray
            case .warn:  return colorScheme == .dark ? .white : .black
            case .error: return .red
            case .off:   return colorScheme == .dark ? .white : .gray
        }
    }

    func baseOpacity(for level: Level) -> CGFloat {
        level == .off ? 0.25 : 1.0      // .25 when inactive
    }

    // High-contrast overlay
    @ViewBuilder
    func hcMark(for level: Level) -> some View {
        if status.highContrast {
            switch level {
            case .ok:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .opacity(0.9)
            case .warn:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(colorScheme == .dark ? .white : .black) // HC mark stays visible even on black text
                    .opacity(0.9)
            case .error:
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .opacity(0.9)
            case .off:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Tiny transport view with pulse
private struct TransportIcon: View {
    typealias Level = TimerStatusStrip.Level
    @Environment(\.colorScheme) private var colorScheme   // ← add

    let symbol: String
    let level: Level
    let pulsing: Bool
    let size: CGFloat
    let highContrast: Bool

    @State private var pulse = false

    var body: some View {
        let base = Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
            .foregroundColor(color)
            .opacity(opacity)

        base
            .scaleEffect(pulsing && pulse ? 1.12 : 1.0)
            .animation(pulsing
                       ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                       : .default, value: pulse)
            .onAppear { if pulsing { pulse = true } }
            .onChange(of: pulsing) { on in pulse = on }
            .overlay(alignment: .topTrailing) {
                if highContrast {
                    switch level {
                    case .ok:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: size))
                            .foregroundColor(colorScheme == .dark ? .white : .black).opacity(0.9)
                    case .warn:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: size))
                            .foregroundColor(colorScheme == .dark ? .white : .black).opacity(0.9)
                    case .error:
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: size))
                            .foregroundColor(.red).opacity(0.9)
                    case .off:
                        EmptyView()
                    }
                }
            }
            .accessibilityLabel(accessibilityText)
    }

    private var color: Color {
        switch level {
        case .ok:    return colorScheme == .dark ? .white : .black
           case .warn:  return .orange
           case .error: return .red
       case .off:   return colorScheme == .dark ? .white : .black
        }
    }

    private var opacity: CGFloat { level == .off ? 0.25 : 1.0 }

    private var accessibilityText: String {
        switch level {
        case .ok:   return "Connected"
        case .warn: return "Connecting"
        case .error:return "Transport error"
        case .off:  return "Transport off"
        }
    }
}
