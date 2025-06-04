//
//  SyncTimerApp.swift   – 2025-06-01, compile-clean
//


import SwiftUI
import Combine
import AudioToolbox
import CoreText
import Network
import SystemConfiguration



//───────────────────
// MARK: – tiny helpers
//───────────────────
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red  : Double((hex & 0xFF0000) >> 16) / 255,
                  green: Double((hex & 0x00FF00) >>  8) / 255,
                  blue : Double( hex & 0x0000FF       ) / 255,
                  opacity: 1)
    }
}
extension AppSettings {
    /// `.black` in light theme, `.white` in dark theme
    var themeTextColor: Color {
        appTheme == .dark ? .white : .black
    }
}
@inline(__always) func lightHaptic() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}
private func registerRoboto() {
    let faces = [
        ("Roboto-Thin",      "ttf"),
        ("Roboto-Light",     "ttf"),
        ("Roboto-Regular",   "ttf"),
        ("Roboto-SemiBold",  "ttf")
    ]
    for (name, ext) in faces {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        } else {
            print("⚠️  Roboto face “\(name)” not found in bundle")
        }
    }
}
final class HidingHostingController<Content: View>: UIHostingController<Content> {
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}


/// Returns the first non‐loopback IPv4 address on Wi-Fi (en0), or nil if none found.
func getLocalIPAddress() -> String? {
    var address: String?
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>? = nil
    defer { freeifaddrs(ifaddrPtr) }

    guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
        return nil
    }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let flags = Int32(ptr.pointee.ifa_flags)
        let addrFamily = ptr.pointee.ifa_addr.pointee.sa_family
        // we only want IPv4, up interfaces, not loopback (en0 is typically Wi-Fi)
        if addrFamily == UInt8(AF_INET) && (flags & (IFF_UP|IFF_RUNNING)) == (IFF_UP|IFF_RUNNING) {
            let name = String(cString: ptr.pointee.ifa_name)
            if name == "en0" {  // Wi-Fi on iPhone
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let saLen = socklen_t(ptr.pointee.ifa_addr.pointee.sa_len)
                if getnameinfo(ptr.pointee.ifa_addr, saLen, &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                    break
                }
            }
        }
    }
    return address
}

//───────────────────
// MARK: – Re-usable themed backdrop
//───────────────────
struct AppBackdrop: View {
    let imageName: String          // pass the chosen image name in
    
    var body: some View {
        ZStack {
            // (Optional) a soft vignette so edges feel bounded
            RadialGradient(
                colors: [Color.black.opacity(0.05), Color.clear],
                center: .center, startRadius: 120, endRadius: 480
            )
            
            // The actual themed artwork
            Image(imageName)
                .resizable()
                .scaledToFill()
                // Dim the “night” art; keep others full-strength
                .opacity(imageName == "MainBG2" ? 1.0 : 1.0)
                .opacity(imageName == "MainBG1" ? 0.35 : 1.0)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()          // covers the whole screen
    }
}

//───────────────────
// MARK: – app models
//───────────────────
enum FlashStyle: String, CaseIterable, Identifiable {
    case dot, borderAround, borderUnder, fullTimer, delimiters, numbers
    var id: String { rawValue }
}
enum Phase { case idle, countdown, running, paused }
enum CountdownResetMode: Int, CaseIterable, Identifiable { case off = 0, manual = 1 ; var id: Int { rawValue } }
enum SyncRole: String, CaseIterable, Identifiable { case parent, child ; var id: String { rawValue } }
enum ViewMode { case sync, stop }                       // ← lives at top level

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
}

enum ResetConfirmationMode: String, CaseIterable, Identifiable {
    case off             = "Off"
    case doubleTap       = "Double Tap"
    case popup           = "Popup Confirmation"

    var id: String { rawValue }
}

final class AppSettings: ObservableObject {
    @Published var flashStyle: FlashStyle           = .fullTimer
    @Published var flashDurationOption: Int         = 100        // ms
    @Published var flashColor: Color                = Color(hex: 0xCE2029)
    @Published var appTheme: AppTheme = .light
    @Published var countdownResetMode: CountdownResetMode = .off
    @Published var requireSyncResetConfirm: Bool    = false
    @Published var resetConfirmationMode: ResetConfirmationMode = .off
    @Published var stopConfirmationMode: ResetConfirmationMode = .off

}


final class SyncSettings: ObservableObject {
    enum Role { case parent, child }
    
    @Published var parentLockEnabled: Bool = true
    /// true when this device is a child AND sync is currently on AND parent-lock is enabled
        var isLocked: Bool {
            role == .child && isEnabled && parentLockEnabled
        }


    // ── PUBLICLY BINDABLE STATES ─────────────────────────
    @Published var role: Role = .parent
    @Published var isEnabled = false          // “Sync” toggle on/off
    @Published private(set) var isEstablished = false
    @Published private(set) var statusMessage: String = "Not connected"

    // Port/IP settings (entered via pop-ups)
    @Published var listenPort: String = "50000"    // parent-side port string
    @Published var peerIP:     String = ""         // child-side IP string
    @Published var peerPort:   String = "50000"    // child-side port string

    // ── INTERNAL SOCKETS ─────────────────────────────────
    private var listener: NWListener?
    private var childConnections: [NWConnection] = []   // for parent
    private var clientConnection: NWConnection?         // for child

    // When child receives a TimerMessage JSON, we invoke this callback:
    var onReceiveTimer: ((TimerMessage) -> Void)? = nil

    // ── START PARENT (LISTEN) ────────────────────────────
    func startParent() {
        guard listener == nil else { return }
        guard let portNum = UInt16(listenPort), portNum > 0 else {
            statusMessage = "Invalid port"
            print("❌ startParent: “\(listenPort)” is not a valid port")
            return
        }

        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: portNum)!)
        } catch {
            listener = nil
            statusMessage = "Listen failed: \(error.localizedDescription)"
            print("❌ startParent: failed to create listener on port \(portNum): \(error.localizedDescription)")
            return
        }

        statusMessage = "Waiting for children…"
        isEstablished = false

        listener?.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            switch newState {
            case .ready:
                let myIP = getLocalIPAddress() ?? "Unknown"
                DispatchQueue.main.async {
                    self.statusMessage = "Listening on port \(portNum)"
                }
                print("🔊 Parent is listening on port \(portNum), IP = \(myIP)")
            case .failed(let err):
                DispatchQueue.main.async {
                    self.statusMessage = "Listener error: \(err.localizedDescription)"
                }
                print("❌ Parent listener failed: \(err.localizedDescription)")
                self.stopParent()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] newConn in
            guard let self = self else { return }
            print("👶 Parent: new incoming connection arrived, setting up …")
            self.childConnections.append(newConn)
            self.setupParentConnection(newConn)
        }

        listener?.start(queue: .global(qos: .background))
        print("⌛ Parent: NWListener started (waiting for .ready callback).")
    }


    private func setupParentConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                // Child has connected successfully
                DispatchQueue.main.async {
                    self.isEstablished = true
                    self.statusMessage = "Child connected"
                }
                self.receiveLoop(on: conn)   // parent might ignore incoming, so we can skip
            case .failed, .cancelled:
                // Remove from our array
                DispatchQueue.main.async {
                    self.childConnections.removeAll { $0 === conn }
                    if self.childConnections.isEmpty {
                        self.isEstablished = false
                        self.statusMessage = "No children"
                    }
                }
            default: break
            }
        }
        conn.start(queue: .global(qos: .background))
    }

    // ── STOP PARENT (CANCEL LISTENER+CONNS) ───────────────
    func stopParent() {
        listener?.cancel()
        listener = nil
        for c in childConnections { c.cancel() }
        childConnections.removeAll()
        DispatchQueue.main.async {
            self.isEstablished = false
            self.statusMessage = "Not listening"
        }
    }

    // ── CONNECT AS CHILD ───────────────────────────────────
    func startChild() {
        guard clientConnection == nil else {
            print("⚠️ startChild: there is already a clientConnection, ignoring.")
            return
        }

        let ipString = peerIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ipString.isEmpty else {
            statusMessage = "Enter parent IP"
            print("❌ startChild: peerIP is empty")
            return
        }
        guard let portNum = UInt16(peerPort), portNum > 0 else {
            statusMessage = "Invalid port"
            print("❌ startChild: “\(peerPort)” is not a valid port")
            return
        }

        let endpoint = NWEndpoint.Host(ipString)
        let port     = NWEndpoint.Port(rawValue: portNum)!
        let conn     = NWConnection(host: endpoint, port: port, using: .tcp)
        clientConnection = conn

        statusMessage = "Connecting…"
        isEstablished = false
        print("👉 Child attempting connection to \(ipString):\(portNum)…")

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .waiting(let err):
                DispatchQueue.main.async {
                    self.statusMessage = "Waiting: \(err.localizedDescription)"
                }
                print("⌛ Child waiting to connect: \(err.localizedDescription)")
            case .preparing:
                print("… Child preparing connection …")
            case .ready:
                DispatchQueue.main.async {
                    self.isEstablished = true
                    self.statusMessage = "Connected to \(ipString):\(portNum)"
                }
                print("✅ Child connected!")
                self.receiveLoop(on: conn)
            case .failed(let err):
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Connect failed: \(err.localizedDescription)"
                }
                print("❌ Child failed to connect: \(err.localizedDescription)")
                conn.cancel()
                self.clientConnection = nil
            case .cancelled:
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Disconnected"
                }
                print("🛑 Child connection cancelled")
                self.clientConnection = nil
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .background))
        print("⌛ Child: NWConnection.start(queue:) called; now waiting up to 30s …")

        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, let c = self.clientConnection else { return }
            if c.state != .ready {
                c.cancel()
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Timeout"
                }
                print("⌛ Child timed out after 30 s")
                self.clientConnection = nil
            }
        }
    }

    func stopChild() {
        clientConnection?.cancel()
        clientConnection = nil
        DispatchQueue.main.async {
            self.isEstablished = false
            self.statusMessage = "Not connected"
        }
    }

    // ── BROADCAST A JSON‐ENCODED MESSAGE TO “ALL CHILDREN” (parent only) ───
    func broadcastToChildren(_ msg: TimerMessage) {
        guard role == .parent else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(msg) else { return }
        let framed = data + Data([0x0A])   // newline-delimit each JSON packet

        for conn in childConnections {
            conn.send(content: framed, completion: .contentProcessed({ _ in }))
        }
    }

    // ── SEND JSON TO PARENT (child only) ─────────────────────────────────
    func sendToParent(_ msg: TimerMessage) {
        guard role == .child, let conn = clientConnection else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(msg) else { return }
        let framed = data + Data([0x0A])
        conn.send(content: framed, completion: .contentProcessed({ _ in }))
    }

    // ── RECEIVE LOOP (both parent and child reuse) ───────────────────────
    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                // Split on newline, decode each JSON chunk
                let pieces = data.split(separator: 0x0A)   // newline (10)
                let decoder = JSONDecoder()
                for piece in pieces {
                    if let msg = try? decoder.decode(TimerMessage.self, from: Data(piece)) {
                        DispatchQueue.main.async {
                            self.onReceiveTimer?(msg)
                        }
                    }
                }
            }

            if isComplete == false && error == nil {
                // Keep reading
                self.receiveLoop(on: connection)
            } else {
                // Connection closed or errored
                connection.cancel()
            }
        }
    }
}



// ── 1) Your event types ─────────────────────────────────────────
struct StopEvent: Identifiable, Equatable {
    let id = UUID()
    var eventTime: TimeInterval
    var duration : TimeInterval
    static func == (lhs: StopEvent, rhs: StopEvent) -> Bool {
        return lhs.id == rhs.id
    }
}


/// A single cue‐event (fires at a single time, with no duration)
struct CueEvent: Identifiable, Equatable {
    let id = UUID()
    var cueTime: TimeInterval
    static func == (lhs: CueEvent, rhs: CueEvent) -> Bool {
        return lhs.id == rhs.id
    }
}


/// Either a StopEvent or a CueEvent, so that we can sort them in one array.
enum Event: Identifiable, Equatable {
    case stop(StopEvent)
    case cue (CueEvent)


    var id: UUID {
        switch self {
        case .stop(let s): return s.id
        case .cue(let c):  return c.id
        }
    }
    /// Helper for sorting chronologically by the time‐at‐which they fire.
    var fireTime: TimeInterval {
        switch self {
        case .stop(let s): return s.eventTime
        case .cue(let c):  return c.cueTime
        }
    }

    /// Helper readable property for the TimerCard’s circles
    var isStop: Bool {
        switch self {
        case .stop: return true
        case .cue:  return false
        }
    }
}

/// A single stop‐event over the wire
struct StopEventWire: Codable {
    let eventTime: TimeInterval
    let duration:  TimeInterval
}

/// The top‐level JSON message we send/receive on sync links
struct TimerMessage: Codable {
    enum Action: String, Codable {
        case update     // continuous tick
        case start      // start or resume
        case pause      // pause or stop
        case reset      // full reset
        case addEvent   // new stop‐event added
    }

    let action:    Action
    let timestamp: TimeInterval       // for “update” == current elapsed/remaining
    let phase:     String             // “idle”/“countdown”/“running”/“paused”
    let remaining: TimeInterval       // countdownRemaining or elapsed
    let stopEvents: [StopEventWire]   // full list of upcoming events
}

private extension TimeInterval {
    var csString: String {
        let cs = Int((self*100).rounded())
        let h  = cs / 360000
        let m  = (cs / 6000) % 60
        let s  = (cs / 100) % 60
        let c  = cs % 100
        return String(format: "%02d:%02d:%02d.%02d", h,m,s,c)
    }
}


//──────────────────────────────────────────────────────────────
// MARK: – NumPad  (tight rows, no backgrounds)
//──────────────────────────────────────────────────────────────
struct NumPadView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings

    enum Key: Hashable { case digit(Int), backspace, settings }

    /// Called for digit/backspace taps
    let onKey: (Key) -> Void

    /// Called when the gear is tapped
    let onSettings: () -> Void

    /// true when we want to disable digit/backspace (but keep gear active)
    var lockActive: Bool = false

    private let hGap: CGFloat = 20
    private let vGap: CGFloat = 12
    private let keys: [Key] = [
        .digit(1), .digit(2), .digit(3),
        .digit(4), .digit(5), .digit(6),
        .digit(7), .digit(8), .digit(9),
        .settings, .digit(0), .backspace
    ]

    @ViewBuilder
    private func label(_ k: Key) -> some View {
        let isDark = (colorScheme == .dark)

        switch k {
        case .digit(let n):
            Text("\(n)")
                .font(.custom("Roboto-Regular", size: 52))
                .foregroundColor(
                    lockActive
                        ? .secondary            // digits fade when locked
                        : (isDark ? .white : .primary)
                )

        case .backspace:
            Image(systemName: "delete.left")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(
                    lockActive
                        ? .secondary            // backspace fades when locked
                        : (isDark ? .white : .primary)
                )

        case .settings:
            // gear is always tappable & not faded
            Image(systemName: "gearshape.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(isDark ? .white : .primary)
        }
    }

    var body: some View {
        GeometryReader { g in
            let side = (g.size.width - 2 * hGap) / 3
            let keyH = side * 0.88

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(side), spacing: hGap), count: 3),
                spacing: vGap
            ) {
                ForEach(keys, id: \.self) { k in
                    Button {
                        switch k {
                        case .settings:
                            onSettings()            // always allowed
                        default:
                            if !lockActive {
                                onKey(k)           // digits/backspace only when not locked
                            }
                        }
                    } label: {
                        label(k)
                            .frame(width: side, height: keyH)
                    }
                    .buttonStyle(.plain)
                    .opacity(
                        (lockActive && k != .settings)
                            ? (settings.appTheme == .dark ? 0.99 : 0.6)
                            : 1
                    )
                }
            }
        }
        .frame(height: calcH(for: UIScreen.main.bounds.width - 64))
        .padding(.horizontal, 32)
    }

    private func calcH(for w: CGFloat) -> CGFloat {
        let side = (w - 2 * hGap) / 3
        let keyH = side * 0.88
        return keyH * 4 + vGap * 3
    }
}


//──────────────────────────────────────────────────────────────
// MARK: – Sync / Stop bars
//──────────────────────────────────────────────────────────────
struct SyncBar: View {
    @EnvironmentObject private var syncSettings: SyncSettings
    @Environment(\.colorScheme) private var colorScheme


    /// True when either a countdown or the stopwatch is active.
    var isCounting: Bool


    /// Called when the “parent/child” button is tapped.
    let onRoleTap: () -> Void


    var body: some View {
        let isDark = (colorScheme == .dark)
        let textColor: Color = isDark ? .white : .black


        HStack(spacing: 0) {
            // ── Left column: Role toggle ─────────────────────────
            Button(syncSettings.role == .parent ? "parent" : "child") {
                // Don’t allow switching roles while the timer is running
                guard !isCounting else { return }
                onRoleTap()
            }
            .font(.custom("Roboto-SemiBold", size: 24))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, alignment: .center)


            // ── Right column: “sync” / “desync” + connection lamp ─
            HStack(spacing: 8) {
                Button(syncSettings.isEnabled ? "sync" : "sync") {
                    // Don’t change sync‐state while the timer is running
                    guard !isCounting else { return }
                    if syncSettings.isEnabled {
                        // Currently synced → desync
                        syncSettings.stopParent()
                        syncSettings.stopChild()
                        syncSettings.isEnabled = false
                    } else {
                        // Currently desynced → start parent or child
                        if syncSettings.role == .parent {
                            syncSettings.startParent()
                        } else {
                            syncSettings.startChild()
                        }
                        syncSettings.isEnabled = true
                    }
                }
                .font(.custom("Roboto-SemiBold", size: 24))
                .foregroundColor(textColor)


                // Lamp: green when connected, red when not.
                Circle()
                    .fill(syncSettings.isEstablished ? .green : .red)
                    .frame(width: 18, height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
struct EventsBar: View {
    @Binding var events: [Event]
    @Binding var isCueMode: Bool    // true = Cue mode, false = Stop mode
    var isCounting: Bool            // disables toggle while counting
    let onAddStop: () -> Void
    let onAddCue: () -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 8) {
                // ─── CUE / STOP toggle button ─────────────────────
                Button {
                    isCueMode.toggle()
                } label: {
                    Text(isCueMode ? "CUE" : "STOP")
                        .font(.custom("Roboto-SemiBold", size: 18))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isCueMode ? Color.black : Color.red)
                        .cornerRadius(8)
                }
                .disabled(isCounting)
                // Allocate one-third of the width to the button
                .frame(width: geo.size.width * (1.0 / 3.0),
                       height: geo.size.height)

                // ─── Event carousel occupies the remaining two-thirds ───────
                EventsCarousel(events: $events, isCounting: isCounting)
                    .frame(width: geo.size.width * (2.0 / 3.0),
                           height: geo.size.height)
            }
            // Center vertically by default (HStack’s alignment is .center)
        }
        // Fix the overall bar height (e.g. 60 points)
        .frame(height: 60)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.clear)
    }
}
/// Horizontally scrolling carousel of stop‐events, with “◀️/▶️” arrows
/// and an “✕” to delete.  Always kept in chronological order.
// ─────────────────────────────────────────────────────────────────
// MARK: – Horizontal Stop-Events Carousel
// ─────────────────────────────────────────────────────────────────
private func formatted(event: StopEvent, index: Int) -> String {
    // Convert total duration (or eventTime) into centiseconds
    let totalCs = Int((event.eventTime * 100).rounded())
    let cs      = totalCs % 100
    let totalSec = totalCs / 100
    let sec     = totalSec % 60
    let totalMin = totalSec / 60
    let min     = totalMin % 60
    let hr      = totalMin / 60

    var parts: [String] = []
    if hr  > 0 { parts.append("\(hr)hr") }
    if min > 0 { parts.append("\(min)m")  }
    if sec > 0 { parts.append("\(sec)s")  }
    if cs  > 0 { parts.append("\(cs)c")   }
    // If everything was zero (unlikely for a real event), at least show “0s”:
    let startString = parts.isEmpty ? "0s" : parts.joined()

    // Now do the same for the duration:
    let dTotalCs   = Int((event.duration * 100).rounded())
    let dCs        = dTotalCs % 100
    let dTotalSec  = dTotalCs / 100
    let dSec       = dTotalSec % 60
    let dTotalMin  = dTotalSec / 60
    let dMin       = dTotalMin % 60
    let dHr        = dTotalMin / 60

    var dParts: [String] = []
    if dHr  > 0 { dParts.append("\(dHr)hr") }
    if dMin > 0 { dParts.append("\(dMin)m")  }
    if dSec > 0 { dParts.append("\(dSec)s")  }
    if dCs  > 0 { dParts.append("\(dCs)c")   }
    let durString = dParts.isEmpty ? "0s" : dParts.joined()

    return "\(index). at \(startString) for \(durString)"
}

/// Horizontally scrolling carousel of mixed `.stop(...)` and `.cue(...)` events.
/// Always kept in chronological order. The small text says either
///   “1. Stop event at 2m54s”  or  “2. Cue event at 1m15s”
struct EventsCarousel: View {
    @Binding var events: [Event]
    var isCounting: Bool
    @State private var currentIndex: Int = 0


    var body: some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let keyWidth  = (fullWidth - 40) / 3
            let leftX     = 32 + keyWidth / 2
            let rightX    = fullWidth - (32 + keyWidth / 2)
            let midY      = (geo.size.height / 2) - 8


            ZStack {
                if !events.isEmpty {
                    // ─ Centered text + delete “×”
                    HStack(spacing: 4) {
                        Text(formattedText(for: events[currentIndex], index: currentIndex + 1))
                            .font(.custom("Roboto-Light", size: 20))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)


                        Button {
                            events.remove(at: currentIndex)
                            if currentIndex >= events.count && currentIndex > 0 {
                                currentIndex = events.count - 1
                            }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.black)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCounting)
                    }
                    .position(x: fullWidth / 2, y: midY)
                } else {
                    // “No events” placeholder
                    Text("No events")
                        .font(.custom("Roboto-Light", size: 20))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .position(x: fullWidth / 2, y: midY)
                }


                // ← LEFT ARROW if we can page backward
                if currentIndex > 0 {
                    Button {
                        currentIndex -= 1
                    } label: {
                        Image(systemName: "arrow.left")
                            .resizable()
                            .frame(width: 18, height: 16)
                            .foregroundColor(.black)
                    }
                    .position(x: leftX, y: midY)
                    .disabled(isCounting)
                }


                // → RIGHT ARROW if we can page forward
                if currentIndex < events.count - 1 {
                    Button {
                        currentIndex += 1
                    } label: {
                        Image(systemName: "arrow.right")
                            .resizable()
                            .frame(width: 18, height: 16)
                            .foregroundColor(.black)
                    }
                    .position(x: rightX, y: midY)
                    .disabled(isCounting)
                }
            }
        }
        .frame(height: 160) // same “fixed height” as before
        .onChange(of: events) { _ in
            if currentIndex >= events.count && currentIndex > 0 {
                currentIndex = events.count - 1
            }
        }
    }

    /// Formats either:
    ///   “1. Stop event at 2m54s30c”  or  “2. Cue event at 1m15s”
    private func formattedText(for event: Event, index: Int) -> String {
            func timeString(_ total: TimeInterval) -> String {
                let totalCs = Int((total * 100).rounded())
                let cs      = totalCs % 100
                let totalS  = totalCs / 100
                let s       = totalS % 60
                let totalM  = totalS / 60
                let m       = totalM % 60
                let h       = totalM / 60
                var parts: [String] = []
                if h > 0  { parts.append("\(h)h") }
                if m > 0  { parts.append("\(m)m") }
                if s > 0  { parts.append("\(s)s") }
                if cs > 0 { parts.append("\(cs)c") }
                if parts.isEmpty {
                    parts.append("0s")
                }
                return parts.joined()
            }


            switch event {
            case .stop(let s):
                let startText = timeString(s.eventTime)
                return "\(index). Stop event at \(startText)"
            case .cue(let c):
                let cueText = timeString(c.cueTime)
                return "\(index). Cue event at \(cueText)"
            }
        }
    }

//──────────────────────────────────────────────────────────────
// MARK: – Bottom button rows
//──────────────────────────────────────────────────────────────
struct SyncBottomButtons: View {
    @EnvironmentObject private var settings: AppSettings
    
    /// true when countdown or run loop is active
    var isCounting: Bool
    
    /// callback to actually perform either “start” or “stop”
    let startStop: () -> Void
    
    /// callback to actually perform “reset”
    let reset: () -> Void
    
    @State private var showResetConfirm: Bool      = false
    @State private var awaitingSecondTap: Bool     = false
    
    // ── NEW for “stop” confirmation ──────────────────────────────
    @State private var showStopConfirm: Bool       = false
    @State private var awaitingStopSecondTap: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // ── Left: either “stop” or “start” ────────────────────
            Button(isCounting ? "stop" : "start") {
                if isCounting {
                    handleStopTap()
                } else {
                    // Immediately start (no confirmation needed on “start”)
                    startStop()
                }
                lightHaptic()
            }
            .font(.custom("Roboto-SemiBold", size: 28))
            .foregroundColor(settings.themeTextColor)
            .frame(maxWidth: .infinity, alignment: .center)
            
            // ── Right: “reset” with its existing confirmation logic ──
            Button(action: handleResetTap) {
                Text("reset")
                    .font(.custom("Roboto-SemiBold", size: 28))
            }
            .foregroundColor(settings.themeTextColor)
            .disabled(isCounting)
            .opacity(isCounting ? 0.3 : 1)
            .frame(maxWidth: .infinity, alignment: .center)
            .alert("Confirm Reset", isPresented: $showResetConfirm) {
                Button("Yes, reset", role: .destructive) {
                    performReset()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to reset the timer?")
            }
        }
        .padding(.vertical, 4)
        // ── NEW: Popup for “stop” confirmation ───────────────
        .alert("Confirm Stop", isPresented: $showStopConfirm) {
            Button("Yes, stop", role: .destructive) {
                performStop()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to stop the timer?")
        }
    }
    
    // ── handleResetTap remains unchanged ───────────────────────────
    private func handleResetTap() {
        guard !isCounting else { return }
        switch settings.resetConfirmationMode {
        case .off:
            performReset()
        case .popup:
            showResetConfirm = true
        case .doubleTap:
            if awaitingSecondTap {
                performReset()
            } else {
                awaitingSecondTap = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    awaitingSecondTap = false
                }
            }
        }
    }
    private func performReset() {
        reset()
        awaitingSecondTap = false
    }
    
    // ── NEW: “stop” confirmation logic ─────────────────────────────
    private func handleStopTap() {
        switch settings.stopConfirmationMode {
        case .off:
            performStop()
        case .popup:
            showStopConfirm = true
        case .doubleTap:
            if awaitingStopSecondTap {
                performStop()
            } else {
                awaitingStopSecondTap = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    awaitingStopSecondTap = false
                }
            }
        }
    }
    
    private func performStop() {
        startStop()               // actually pause/stop the timer
        awaitingStopSecondTap = false
        
        // Pull this directly from AppSettings (unchanged):
        @EnvironmentObject var settings: AppSettings
        var resetConfirmationMode: ResetConfirmationMode {
            settings.resetConfirmationMode
        }
    }
}

struct StopBottomButtons: View {
    @Environment(\.colorScheme) private var colorScheme
    var canAdd: Bool          // true when the “Add” step is available
    let add: () -> Void
    let reset: () -> Void

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left column – Next / Add
            Button(canAdd ? "add" : "next") {
                add()
                lightHaptic()
            }
            .font(.custom("Roboto-SemiBold", size: 28))
            .foregroundColor(textColor)
            .disabled(!canAdd)   // disable only when no “add” possible
            .frame(maxWidth: .infinity, alignment: .center)

            // Right column – Reset
            Button("reset") {
                reset()
                lightHaptic()
            }
            .font(.custom("Roboto-SemiBold", size: 28))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 4)
    }
}


// ─── Outside MainScreen ──────────────────────────────────────────────
// You can put this right after the struct MainScreen declaration.
//extension MainScreen {
//    enum ViewMode { case sync, stop }
//}


// ─── Utility for nicely-formatted centiseconds ───────────────────────
private extension TimeInterval {
    var formattedCS: String {
        let cs = Int((self * 100).rounded())
        let h  = cs / 360000
        let m  = (cs / 6000) % 60
        let s  = (cs / 100) % 60
        let c  = cs % 100
        return String(format: "%02d:%02d:%02d.%02d", h, m, s, c)
    }
}
// ─────────────────────────────────────────────────────────────────────
// MARK: - TimerCard   (single-Text flash — no ghosting)
// ─────────────────────────────────────────────────────────────────────
private struct TimerCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings
    // ─────────────── NEW STATES for “ERR” flash ───────────────
    @State private var isErrFlashing: Bool = false
    @State private var showErr:       Bool = false


    // ── Bindings / parameters ──────────────────────────────────────────
    @Binding var mode: ViewMode
    @Binding var flashZero: Bool
    let isRunning: Bool
    var flashStyle: FlashStyle
    var flashColor: Color
    var syncDigits: [Int]
    var stopDigits: [Int]
    var phase: Phase
    var mainTime: TimeInterval
    var stopActive: Bool
    var stopRemaining: TimeInterval
    var leftHint: String
    var rightHint: String
    var stopStep: Int
    var makeFlashed: () -> AttributedString
    var isCountdownActive: Bool
    var events: [Event]    // ← all pending stop events

    private let viewLeft  = "STOP VIEW"
    private let viewRight = "SYNC VIEW"

    // ── Derived styling ─────────────────────────────────────────────
    private var isDark: Bool  { colorScheme == .dark }
    private var txtMain: Color { isDark ? .white : .primary }
    private var txtSec:  Color { isDark ? Color.white.opacity(0.6) : .secondary }
    private var leftTint : Color {
        (mode == .stop && stopStep == 0) ? txtMain : txtSec
    }
    private var rightTint: Color {
        (mode == .stop && stopStep == 1) ? txtMain : txtSec
    }

    // ── Helper: render raw digits as “HH:MM:SS.CC” without normalizing ─
    private func rawString(from digits: [Int]) -> String {
        var a = digits
        while a.count < 8 { a.insert(0, at: 0) }
        let h  = a[0] * 10 + a[1]
        let m  = a[2] * 10 + a[3]
        let s  = a[4] * 10 + a[5]
        let cs = a[6] * 10 + a[7]
        return String(format: "%02d:%02d:%02d.%02d", h, m, s, cs)
    }

    var body: some View {
        GeometryReader { geo in
            let innerW = geo.size.width - 28
            let fs     = innerW / 5.2

            ZStack {
                // ── (A) Card background ─────────────────────────────
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDark ? .thinMaterial : .ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(isDark ? 0.25 : 0))
                    )
                    .ignoresSafeArea(edges: .horizontal)

                // ── (B) Full vertical stack ──────────────────────────
                VStack(spacing: 0) {
                    // B.1) Top hints “START POINT” / “DURATION”
                    ZStack {
                        HStack {
                            Text(leftHint)
                                .foregroundColor(leftTint)
                            Spacer()
                            Text(rightHint)
                                .foregroundColor(rightTint)
                        }
                        .font(.custom("Roboto-Regular", size: 24))
                        .padding(.horizontal, 14)
                        .padding(.top, 6)


                        // ── NEW: “ERR” flashes, if needed ────────────────────────
                        if showErr {
                            Text("ERR")
                                .font(.custom("Roboto-Regular", size: 24))
                                .foregroundColor(txtMain)        // same color logic as other timer text
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                        }
                    }
                    .onChange(of: syncSettings.statusMessage) { newMsg in
                        // Only treat “Invalid…”, “…failed…”, or “Timeout” as a flashable error.
                        // (You can tweak these substrings to match your own error‐text conventions.)
                        if newMsg.contains("Invalid")
                           || newMsg.contains("failed")
                           || newMsg.contains("Timeout")
                        {
                            triggerErrFlash()
                        }
                    }
                

                    // B.2) Main time + dash + flash overlays (no ghost layer)
                    HStack(spacing: 4) {
                        // ── (1) DASH INDICATOR ───────────────────────────
                        Text("-")
                          .font(.custom("Roboto-Light", size: fs))
                          .foregroundColor(isCountdownActive ? .black : .gray)

                        // ── (2) Sharp, on-top timer Text (or raw‐digits if editing)
                        ZStack {
                            let fullString = mainTime.formattedCS

                            if mode == .stop && (phase == .idle || phase == .paused) && !stopDigits.isEmpty {
                                // Stop‐mode raw editing
                                Text(rawString(from: stopDigits))
                                    .font(.custom("Roboto-Regular", size: fs))
                                    .minimumScaleFactor(0.5)
                                    .foregroundColor(txtMain)
                            }
                            else if mode == .sync && phase == .idle && !syncDigits.isEmpty {
                                // Sync‐mode raw editing
                                Text(rawString(from: syncDigits))
                                    .font(.custom("Roboto-Regular", size: fs))
                                    .minimumScaleFactor(0.5)
                                    .foregroundColor(txtMain)
                            }
                            else {
                                // Normal formatted time
                                Text(fullString)
                                    .font(.custom("Roboto-Regular", size: fs))
                                    .minimumScaleFactor(0.5)
                                    .foregroundColor(
                                        (flashStyle == .fullTimer && flashZero)
                                            ? flashColor
                                            : txtMain
                                    )
                            }

                            // 2.3) Delimiters / Numbers flash overlay
                            if flashStyle == .delimiters || flashStyle == .numbers {
                                Text(makeFlashed())
                                    .font(.custom("Roboto-Regular", size: fs * 0.92))
                            }

                            // 2.4) Dot flash
                            if flashStyle == .dot && flashZero {
                                Circle()
                                    .fill(flashColor)
                                    .frame(width: 10, height: 10)
                                    .offset(x: innerW / 2, y: -fs * 0.45)
                            }

                            // 2.5) Border Under flash
                            if flashStyle == .borderUnder {
                                Rectangle()
                                    .fill(flashColor.opacity(flashZero ? 1 : 0))
                                    .frame(height: 3)
                                    .offset(y: fs * 0.55)
                            }
                        }
                    }
                    .padding(.horizontal, 14)

                    Spacer(minLength: 4)

                    // B.3) STOP EVENTS + small stop‐timer on same baseline
                    HStack(spacing: 6) {
                        let outlineColor: Color = isDark ? .white : .black
                                ForEach(0..<5) { idx in
                                    if idx < events.count {
                                        // If this index corresponds to a `Stop` or to a `Cue`…
                                        let ev = events[idx]
                                        Circle()
                                          .stroke(outlineColor, lineWidth: 1)
                                          .frame(width: 18, height: 18)
                                          .overlay(
                                              Text(ev.isStop ? "S" : "C")
                                                .font(.custom("Roboto-Light", size: 12))
                                                .foregroundColor(outlineColor)
                                          )
                                    }
                                    else {
                                        // empty placeholder
                                        Circle()
                                          .stroke(Color.gray, lineWidth: 1)
                                          .frame(width: 18, height: 18)
                                    }
                                }

                        // Plus icon if more than 5 events
                        if events.count > 5 {
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .frame(width: 14, height: 14)
                                .foregroundColor(.black)
                        }

                        Spacer()

                        // Small “stop‐timer” under main digits
                        Text(stopActive ? stopRemaining.formattedCS : "00:00:00.00")
                            .font(.custom("Roboto-Regular", size: 24))
                            .foregroundColor(
                                stopActive
                                    ? flashColor
                                    : (mode == .sync ? txtSec : txtMain)
                            )
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                    Spacer(minLength: 4)

                    // B.4) Bottom labels “STOP VIEW” / “SYNC VIEW”
                    HStack {
                        Text(viewLeft)
                            .foregroundColor(mode == .stop ? txtMain : txtSec)
                        Spacer()
                        Text(viewRight)
                            .foregroundColor(mode == .sync ? txtMain : txtSec)
                    }
                    .font(.custom("Roboto-Regular", size: 24))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }

                // ── (C) Invisible tap zones to switch mode ──────────
                HStack(spacing: 0) {
                    // Left half: tap → go to STOP
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            mode = .stop
                            lightHaptic()
                        }
                    // Right half: tap → go to SYNC
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            mode = .sync
                            lightHaptic()
                        }
                }
                // Make sure this overlay spans the entire card
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 190)
        .padding(.horizontal, 16)
    }
}
extension TimerCard {
    /// Flickers “ERR” on/off three times (0.3 sec on, 0.3 sec off, etc.),
    /// then leaves it invisible again.  While animating, it ignores additional error‐triggers.
    private func triggerErrFlash() {
        // If we’re already in the middle of an “ERR” sequence, do nothing.
        guard !isErrFlashing else { return }


        isErrFlashing = true
        showErr = true


        // We want exactly 3 full “on→off→on” cycles.
        // Each “toggle” happens every 0.3 seconds.  That is 6 toggles total:
        //   1: 0.3 s → off
        //   2: 0.6 s → on
        //   3: 0.9 s → off
        //   4: 1.2 s → on
        //   5: 1.5 s → off
        //   6: 1.8 s → on (final) → then we hide.
        var toggleCount = 0


        func doToggle() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showErr.toggle()
                toggleCount += 1


                if toggleCount < 6 {
                    doToggle()
                } else {
                    // After the 6th toggle, hide completely and reset.
                    showErr = false
                    isErrFlashing = false
                }
            }
        }


        doToggle()
    }
}

//──────────────────────────────────────────────────────────────
// MARK: – MainScreen  (everything in one struct)
//──────────────────────────────────────────────────────────────
struct MainScreen: View {
    
    // env
    @EnvironmentObject private var settings   : AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings
    
    // UI mode
    @Binding var parentMode: ViewMode
    @State private var previousMode: ViewMode = .sync   // track old mode
    
    // state
    @State private var phase              = Phase.idle
    @State private var flashZero          = false
    @State private var countdownDigits: [Int] = []
    @State private var countdownDuration  : TimeInterval = 0
    @State private var countdownRemaining : TimeInterval = 0
    @State private var elapsed            : TimeInterval = 0
    @State private var startDate          : Date?
    @State private var ticker             : AnyCancellable?
    @State private var justEditedAfterPause: Bool = false
    
    // sync
    @State private var showingRoleConfig = false
    @State private var targetRole: SyncRole = .parent
    private var lockActive: Bool { syncSettings.isLocked }
    
    // stop-event buffers + unified events + rawStops
    @State private var stopDigits: [Int] = []
    @State private var cueDigits: [Int] = []
    @State private var stopStep: Int = 0       // 0 = start, 1 = duration
    @State private var tempStart: TimeInterval = 0
    @State private var events: [Event] = []
    @State private var rawStops: [StopEvent] = []
    @State private var stopActive = false
    @State private var stopRemaining: TimeInterval = 0
    @State private var editedAfterFinish = false
    @State private var isCueMode: Bool = false

    
    @Binding var showSettings: Bool
    
    // derived
    private var isCounting: Bool { phase == .countdown || phase == .running }
    
    var body: some View {
        VStack(spacing: 8) {
            
            // ── (A) TIMER CARD – always same position/size
            TimerCard(
                mode:              $parentMode,
                flashZero:         $flashZero,
                isRunning:         (phase == .running),
                flashStyle:        settings.flashStyle,
                flashColor:        settings.flashColor,
                syncDigits:        countdownDigits,
                stopDigits:        stopDigits,
                phase:             phase,
                mainTime:          displayMainTime(),
                stopActive:        stopActive,
                stopRemaining:     stopRemaining,
                leftHint:          "START POINT",
                rightHint:         "DURATION",
                stopStep:          stopStep,
                makeFlashed:       makeFlashedOverlay,
                isCountdownActive:
                    phase == .countdown
                    || (phase == .paused && countdownRemaining > 0)
                    || (phase == .idle && countdownRemaining > 0)
                    || (phase == .idle && !countdownDigits.isEmpty),
                events:            events    // ← pass your [Event] here
            )
            .allowsHitTesting(!lockActive) // if you were disabling touches when parent-lock is on
            .padding(.top, -32)
            // Detect SYNC → STOP transitions:
            .onChange(of: parentMode) { newMode in
                if newMode == .stop && previousMode == .sync {
                    // Populate stopDigits from whatever displayMainTime() currently is:
                    let digits = timeToDigits(displayMainTime())
                    stopDigits = digits
                    stopStep = 0
                }
                previousMode = newMode
            }
            // In MainScreen:
            .onAppear {
                syncSettings.onReceiveTimer = { msg in
                    applyIncomingTimerMessage(msg)
                }
            }
            
            // ▸ (B) MODE BAR – height pinned so the card never shifts
            ZStack {
                // 1) Exactly the same SyncBar, in exactly the same spot:
                SyncBar(
                    isCounting: isCounting,
                    onRoleTap: {
                        let next = (syncSettings.role == .parent ? SyncRole.child : SyncRole.parent)
                        targetRole = next
                        showingRoleConfig = true
                    }
                )
                .environmentObject(syncSettings)
                .padding(.top, -60)                   // ← same vertical offset
                .opacity(parentMode == .sync ? 1 : 0)  // ← only visible in “sync” mode


                // 2) Put your new EventsBar in exactly the same slot, with the same offset:
                EventsBar(
                    events:     $events,
                    isCueMode:  $isCueMode,
                    isCounting: isCounting,
                    onAddStop:  { commitStopEntry() },
                    onAddCue:   { commitCueEntry() }
                )
                .padding(.top, -60)                   // ← same vertical offset
                .opacity(parentMode == .stop ? 1 : 0)  // ← only visible in “stop” (events) mode
            }
            .frame(height: 160)  // ← identical container height so nothing “below” shifts
            .sheet(isPresented: $showingRoleConfig) {
                RoleConfigView(
                    initialRole: targetRole,
                    listenPort:  $syncSettings.listenPort,
                    peerIP:      $syncSettings.peerIP,
                    peerPort:    $syncSettings.peerPort
                ) { chosenRole in
                    showingRoleConfig = false
                    syncSettings.role = (chosenRole == .parent ? .parent : .child)
                    if chosenRole == .parent {
                        syncSettings.startParent()
                    } else {
                        syncSettings.startChild()
                    }
                } onCancel: {
                    showingRoleConfig = false
                }
            }
            
            // ── (C) NUMPAD ────────────────────────────────────
            //
            // We pass `lockActive` down so that digits/backspace get disabled,
            // but the Settings (gear) button remains tappable at all times.
            //
            NumPadView(
                onKey:      parentMode == .sync ? handleCountdownKey : handleStopKey,
                onSettings: { showSettings = true },
                lockActive: lockActive
            )
            .padding(.top, -80)
            
            // ── (D) BOTTOM BUTTONS ─────────────────────────────
            ZStack {
                // 1) SYNC-mode buttons (start/stop, reset).  When locked,
                //    we disable only these, not the entire view.
                SyncBottomButtons(
                    isCounting: isCounting,
                    startStop:  toggleStart,
                    reset:      resetAll
                )
                .disabled(lockActive)
                .opacity(parentMode == .sync ? 1 : 0)
                
                // 2) STOP-mode buttons (add/reset).  Also disable only these.
                StopBottomButtons(
                    canAdd: !stopDigits.isEmpty,
                    add:    commitStopEntry,
                    reset:  clearStopDraft
                )
                .disabled(lockActive)
                .opacity(parentMode == .stop ? 1 : 0)
            }
            .frame(height: 44)
        }
        .padding(.bottom, 8)
        .onDisappear { ticker?.cancel() }
    }
    
    //──────────────────── Helper: convert TimeInterval → [Int] for HHMMSScc
    private func timeToDigits(_ time: TimeInterval) -> [Int] {
        let totalCs = Int((time * 100).rounded())
        let cs = totalCs % 100
        let s  = (totalCs / 100) % 60
        let m  = (totalCs / 6000) % 60
        let h  = totalCs / 360000
        var arr = [
            h / 10, h % 10,
            m / 10, m % 10,
            s / 10, s % 10,
            cs / 10, cs % 10
        ]
        // drop leading zeros until only one digit remains or a nonzero appears
        while arr.first == 0 && arr.count > 1 {
            arr.removeFirst()
        }
        return arr
    }
    
    //──────────────────── formatted overlay
    private func makeFlashedOverlay() -> AttributedString {
        let raw = displayMainTime().csString
        var a   = AttributedString(raw)
        for i in a.characters.indices {
            let ch = a.characters[i]
            let delim = (ch == ":" || ch == ".")
            let doFlash: Bool
            switch settings.flashStyle {
            case .delimiters: doFlash =  delim && flashZero
            case .numbers   : doFlash = !delim && flashZero
            default         : doFlash = false
            }
            a[i...i].foregroundColor = doFlash ? settings.flashColor : .primary
        }
        return a
    }
    
    //──────────────────── main-time chooser
    private func displayMainTime() -> TimeInterval {
        switch phase {
        case .idle:
            // If the user is actively typing digits, show those raw digits.
            if !countdownDigits.isEmpty {
                return digitsToTime(countdownDigits)
            }
            return countdownRemaining
        case .countdown:
            return countdownRemaining
        case .running:
            return elapsed
        case .paused:
            // If we’re paused but still in the middle of a countdown:
            //    show countdownRemaining.
            // Otherwise (we already hit zero and are paused), show elapsed.
            if countdownRemaining > 0 {
                return countdownRemaining
            }
            return elapsed
        }
    }
    
    //──────────────────── timer engine
    private let dt: TimeInterval = 1.0 / 120.0
    private func startLoop() {
        ticker?.cancel()
        ticker = Timer.publish(every: dt, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                switch phase {
                case .countdown: tickCountdown()
                case .running:   tickRunning()
                default:         break
                }
            }
    }
    private func tickCountdown() {
        countdownRemaining = max(0, countdownRemaining - dt)
        if countdownRemaining == 0 {
            phase     = .running
            startDate = Date()
            flashZero = true
            DispatchQueue.main.asyncAfter(deadline: .now() +
                                          Double(settings.flashDurationOption)/1000) {
                flashZero = false
            }
        }
        let msg = TimerMessage(
                action:    .update,
                timestamp: Date().timeIntervalSince1970,
                phase:     phase == .countdown ? "countdown" : "running",
                remaining: countdownRemaining,
                stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                         duration: $0.duration) }
            )
        syncSettings.broadcastToChildren(msg)
    }
    private func tickRunning() {
        if stopActive {
            stopRemaining -= dt
            if stopRemaining <= 0 { stopActive = false }
        } else {
            elapsed = Date().timeIntervalSince(startDate ?? Date())
            // 1) Check the next *StopEvent* in rawStops (ignore cues):
            if let nextStop = rawStops.first, elapsed >= nextStop.eventTime {
                stopActive     = true
                stopRemaining  = nextStop.duration
                rawStops.removeFirst()
                // 2) ALSO remove the corresponding .stop(...) from the `events` array
                if let idx = events.firstIndex(where: {
                    if case .stop(let s) = $0, s.id == nextStop.id { return true }
                    else { return false }
                }) {
                    events.remove(at: idx)
                }
            }
        }
        let msg = TimerMessage(
            action:    .update,
            timestamp: Date().timeIntervalSince1970,
            phase:     "running",
            remaining: elapsed,
            stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                     duration: $0.duration) }
        )
        syncSettings.broadcastToChildren(msg)
    }
    
    //──────────────────── num-pad helpers
    private func digitsToTime(_ d: [Int]) -> TimeInterval {
        var a = d
        while a.count < 8 { a.insert(0, at: 0) }  // left-pad to 8
        let h  = a[0] * 10 + a[1]
        let m  = a[2] * 10 + a[3]
        let s  = a[4] * 10 + a[5]
        let cs = a[6] * 10 + a[7]
        return TimeInterval(h * 3600 + m * 60 + s) + TimeInterval(cs) / 100.0
    }
    /// Given an array of up to 8 “digit” Ints (0..9),
    /// left-pad to exactly 8, then render as “HH:MM:SS.CC”
    /// *without* normalizing.
    private func rawString(from digits: [Int]) -> String {
        var a = digits
        while a.count < 8 { a.insert(0, at: 0) }
        let h  = a[0] * 10 + a[1]
        let m  = a[2] * 10 + a[3]
        let s  = a[4] * 10 + a[5]
        let cs = a[6] * 10 + a[7]
        return String(format: "%02d:%02d:%02d.%02d", h, m, s, cs)
    }
    private func handleCountdownKey(_ key: NumPadView.Key) {
        switch key {
        case .digit(let n):
            // 1) If we were not already editing, pull in whatever is on-screen:
            if phase != .idle {
                if phase == .paused && countdownRemaining == 0 && elapsed > 0 {
                    editedAfterFinish = true
                }
                let baseDigits = timeToDigits(displayMainTime())
                countdownDigits = baseDigits
                phase = .idle
            }
            // 2) Append new digit (up to 8 digits)
            if countdownDigits.count < 8 {
                countdownDigits.append(n)
            }
            // 3) Update countdownRemaining so display shows exactly those raw digits
            countdownRemaining = digitsToTime(countdownDigits)
        case .backspace:
            // 1a) If we were in .countdown/.running/.paused, drop to .idle and load on-screen digits
            if phase != .idle {
                if phase == .paused && countdownRemaining == 0 && elapsed > 0 {
                    editedAfterFinish = true
                }
                countdownDigits = timeToDigits(displayMainTime())
                phase = .idle
            }
            // 1b) If we’re already in .idle but no buffer yet, and there *is* a nonzero remaining,
            //     load that into countdownDigits so we can backspace it.
            else if countdownDigits.isEmpty && countdownRemaining > 0 {
                countdownDigits = timeToDigits(countdownRemaining)
            }
            // 2) Remove rightmost digit if any
            if !countdownDigits.isEmpty {
                _ = countdownDigits.popLast()
                // 3) Reflect the new raw-digit value
                if !countdownDigits.isEmpty {
                    countdownRemaining = digitsToTime(countdownDigits)
                }
            }
        default:
            break
        }
    }
    private func handleStopKey(_ k: NumPadView.Key) {
        switch k {
        case .digit(let n) where stopDigits.count < 8:
            stopDigits.append(n)
        case .backspace:
            _ = stopDigits.popLast()
        default:
            break
        }
    }
    
    
    
    
    // ── 3) commitStopEntry() now appends a .stop(...) into `events` ───
    private func commitStopEntry() {
        // 1) Bail if no digits typed
        guard !stopDigits.isEmpty else { return }


        if stopStep == 0 {
            // Step 0: user typed a “start‐point” for a STOP
            tempStart = digitsToTime(stopDigits)
            // Move to entering “duration”
            stopStep = 1
            // Prefill duration with whatever the SYNC view is currently showing:
            stopDigits = timeToDigits(displayMainTime())
        }
        else {
            // Step 1: user typed a “duration” → finalize StopEvent
            let dur = digitsToTime(stopDigits)
            let newStop = StopEvent(eventTime: tempStart, duration: dur)
            events.append(.stop(newStop))


            // Sort the combined array so stops and cues interleave by fireTime
            events.sort { $0.fireTime < $1.fireTime }


            // If parent+sync is on, broadcast only the StopEvents to children
            if syncSettings.role == .parent && syncSettings.isEnabled {
                let stopWires: [StopEventWire] = events.compactMap {
                    switch $0 {
                    case .stop(let s):
                        return StopEventWire(eventTime: s.eventTime, duration: s.duration)
                    case .cue:
                        return nil
                    }
                }
                let m = TimerMessage(
                    action:     .addEvent,
                    timestamp:  Date().timeIntervalSince1970,
                    phase:      (phase == .running ? "running" : "idle"),
                    remaining:  (phase == .running ? elapsed : countdownRemaining),
                    stopEvents: stopWires
                )
                syncSettings.broadcastToChildren(m)
            }


            // Reset to step 0
            stopDigits.removeAll()
            stopStep = 0
        }


        lightHaptic()
    }


    // ── 4) commitCueEntry() now appends a .cue(...) into `events` ─────────
    private func commitCueEntry() {
        // 1) Bail if no digits typed
        guard !cueDigits.isEmpty else { return }


        // 2) Convert raw digits to TimeInterval
        let cueTime = digitsToTime(cueDigits)


        // 3) Create & append a CueEvent
        let newCue = CueEvent(cueTime: cueTime)
        events.append(.cue(newCue))


        // 4) Sort entire array
        events.sort { $0.fireTime < $1.fireTime }


        // 5) If parent+sync is on, still broadcast only the StopEvents part
        if syncSettings.role == .parent && syncSettings.isEnabled {
            let stopWires: [StopEventWire] = events.compactMap {
                switch $0 {
                case .stop(let s):
                    return StopEventWire(eventTime: s.eventTime, duration: s.duration)
                case .cue:
                    return nil
                }
            }
            let m = TimerMessage(
                action:     .addEvent,
                timestamp:  Date().timeIntervalSince1970,
                phase:      (phase == .running ? "running" : "idle"),
                remaining:  (phase == .running ? elapsed : countdownRemaining),
                stopEvents: stopWires
            )
            syncSettings.broadcastToChildren(m)
        }


        // 6) Clear cue buffer
        cueDigits.removeAll()
        lightHaptic()
    }

    private func clearStopDraft() {
        stopDigits.removeAll()
        stopStep = 0
    }
    
    private func applyIncomingTimerMessage(_ msg: TimerMessage) {
        // Only if we’re a child:
        guard syncSettings.role == .child else { return }
        // 1) Rebuild rawStops from the wire:
        rawStops = msg.stopEvents.map { StopEvent(eventTime: $0.eventTime,
                                                   duration:  $0.duration) }
        // 2) Reset the mixed events array to only contain those StopEvents (no cues,
        //    since cues never come over the wire).
        events = rawStops.map { Event.stop($0) }
        // 3) Update countdown & running-state exactly as before:
        switch msg.action {
        case .start:
            if msg.phase == "countdown" {
                countdownRemaining = msg.remaining
                phase = .countdown
                startLoop()
            } else if msg.phase == "running" {
                elapsed = msg.remaining
                phase = .running
                startDate = Date().addingTimeInterval(-elapsed)
                startLoop()
            }
        case .pause:
            ticker?.cancel()
            phase = .paused
            countdownRemaining = msg.remaining
            elapsed = msg.remaining
        case .reset:
            ticker?.cancel()
            phase = .idle
            countdownDigits.removeAll()
            countdownDuration = 0
            countdownRemaining = 0
            elapsed = 0
            rawStops.removeAll()
            events.removeAll()
            stopActive = false
            stopRemaining = 0
        case .update:
            if msg.phase == "countdown" {
                countdownRemaining = msg.remaining
                phase = .countdown
            } else {
                elapsed = msg.remaining
                phase = .running
            }
        case .addEvent:
            // We already set rawStops & events above, so nothing more to do
            break
        }
    }
    
    //──────────────────── buttons
    private func toggleStart() {
        switch phase {
        case .idle:
            // ① If we just edited after a countdown finished, go into count-up:
            if editedAfterFinish {
                // Start counting up from what we typed:
                let startValue = digitsToTime(countdownDigits)
                phase = .running
                elapsed = startValue
                startDate = Date().addingTimeInterval(-elapsed)
                startLoop()
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: (phase == .countdown || phase == .running) ? .start : .pause,
                        timestamp: Date().timeIntervalSince1970,
                        phase: phase == .countdown ? "countdown" : "running",
                        remaining: (phase == .countdown ? countdownRemaining : elapsed),
                        stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                                 duration: $0.duration) }
                    )
                    syncSettings.broadcastToChildren(m)
                }
                editedAfterFinish = false
                // Clear countdownRemaining so future pauses won’t think this is "still a countdown"
                countdownRemaining = 0
                return
            }
            // ② Otherwise: commit raw digits (if any) into countdownDuration/Remaining:
            if !countdownDigits.isEmpty {
                let newSeconds = digitsToTime(countdownDigits)
                countdownDuration = newSeconds
                countdownRemaining = newSeconds
                countdownDigits.removeAll()
            } else {
                // No new digits typed → restore “remaining” to the stored duration
                countdownRemaining = countdownDuration
            }
            // ③ Now decide countdown vs immediate run:
            if countdownDuration > 0 {
                phase = .countdown
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: (phase == .countdown || phase == .running) ? .start : .pause,
                        timestamp: Date().timeIntervalSince1970,
                        phase: phase == .countdown ? "countdown" : "running",
                        remaining: (phase == .countdown ? countdownRemaining : elapsed),
                        stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                                 duration: $0.duration) }
                    )
                    syncSettings.broadcastToChildren(m)
                }
                startLoop()
            } else {
                phase = .running
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: (phase == .countdown || phase == .running) ? .start : .pause,
                        timestamp: Date().timeIntervalSince1970,
                        phase: phase == .countdown ? "countdown" : "running",
                        remaining: (phase == .countdown ? countdownRemaining : elapsed),
                        stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                                 duration: $0.duration) }
                    )
                    syncSettings.broadcastToChildren(m)
                }
                startDate = Date()
                startLoop()
            }
        case .countdown:
            // user hit pause mid-countdown
            ticker?.cancel()
            if settings.countdownResetMode == .manual {
                phase = .paused
                // leave countdownRemaining as-is
            } else {
                phase = .idle
                countdownRemaining = countdownDuration
            }
        case .running:
            // Pause a running stopwatch
            ticker?.cancel()
            phase = .paused
            if syncSettings.role == .parent && syncSettings.isEnabled {
                let m = TimerMessage(
                    action: (phase == .countdown || phase == .running) ? .start : .pause,
                    timestamp: Date().timeIntervalSince1970,
                    phase: phase == .countdown ? "countdown" : "running",
                    remaining: (phase == .countdown ? countdownRemaining : elapsed),
                    stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                             duration: $0.duration) }
                )
                syncSettings.broadcastToChildren(m)
            }
        case .paused:
            // If there’s still countdownRemaining, resume countdown:
            if countdownRemaining > 0 {
                phase = .countdown
                startLoop()
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: (phase == .countdown || phase == .running) ? .start : .pause,
                        timestamp: Date().timeIntervalSince1970,
                        phase: phase == .countdown ? "countdown" : "running",
                        remaining: (phase == .countdown ? countdownRemaining : elapsed),
                        stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                                 duration: $0.duration) }
                    )
                    syncSettings.broadcastToChildren(m)
                }
            } else {
                // Otherwise resume a running stopwatch
                phase = .running
                startDate = Date().addingTimeInterval(-elapsed)
                startLoop()
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: (phase == .countdown || phase == .running) ? .start : .pause,
                        timestamp: Date().timeIntervalSince1970,
                        phase: phase == .countdown ? "countdown" : "running",
                        remaining: (phase == .countdown ? countdownRemaining : elapsed),
                        stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime,
                                                                 duration: $0.duration) }
                    )
                    syncSettings.broadcastToChildren(m)
                }
            }
        }
    }
    
    private func resetAll() {
        guard phase == .idle || phase == .paused else { return }
        ticker?.cancel()
        phase               = .idle
        if syncSettings.role == .parent && syncSettings.isEnabled {
            let m = TimerMessage(
                action:     .reset,
                timestamp:  Date().timeIntervalSince1970,
                phase:      "idle",
                remaining:  0,
                stopEvents: []
            )
            syncSettings.broadcastToChildren(m)
        }
        countdownDigits.removeAll()
        countdownDuration   = 0
        countdownRemaining  = 0
        elapsed             = 0
        startDate           = nil
        stopActive          = false
        stopRemaining       = 0
        stopDigits.removeAll()
        stopStep            = 0
        lightHaptic()
    }
}


// MARK: – SoleConfigView

struct RoleConfigView: View {
    @State private var selectedRole: SyncRole
    @Binding var listenPort: String
    @Binding var peerIP: String
    @Binding var peerPort: String

    let onOK: (SyncRole) -> Void
    let onCancel: () -> Void

    // Initialize from the caller’s “targetRole”
    init(
        initialRole: SyncRole,
        listenPort: Binding<String>,
        peerIP: Binding<String>,
        peerPort: Binding<String>,
        onOK: @escaping (SyncRole) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._selectedRole = State(initialValue: initialRole)
        self._listenPort = listenPort
        self._peerIP = peerIP
        self._peerPort = peerPort
        self.onOK = onOK
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Role Picker ─────────────────────────────────────
                Section {
                    Picker("Role", selection: $selectedRole) {
                        Text("Parent").tag(SyncRole.parent)
                        Text("Child").tag(SyncRole.child)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                // ── When “Parent” is selected ───────────────────────
                if selectedRole == .parent {
                    Section("Parent Configuration") {
                        HStack {
                            Text("Your IP:")
                            Spacer()
                            Text(getLocalIPAddress() ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                        TextField("Port", text: $listenPort)
                            .keyboardType(.numberPad)
                    }
                }
                // ── When “Child” is selected ────────────────────────
                else {
                    Section("Child Configuration") {
                        TextField("Parent IP", text: $peerIP)
                            .keyboardType(.decimalPad)
                        TextField("Port", text: $peerPort)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Configure Role")
            .presentationDetents([.medium])
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onOK(selectedRole)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

//──────────────────────────────────────────────────────────────
// MARK: – SettingsView
//──────────────────────────────────────────────────────────────
struct SettingsView: View {
    @EnvironmentObject private var appSettings : AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    ColorPicker("flash color", selection: $appSettings.flashColor)
                        .font(.custom("Roboto-Light", size: 20))
                    Picker("Flash Style", selection: $appSettings.flashStyle) {
                        ForEach(FlashStyle.allCases) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                    .padding(.top, 4)

                    Picker("Flash Duration", selection: $appSettings.flashDurationOption) {
                        Text("100 ms").tag(100)
                        Text("250 ms").tag(250)
                        Text("500 ms").tag(500)
                        Text("1000 ms").tag(1000)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                }

                Section("Timer Behavior") {
                    // Toggle drives countdownResetMode directly:
                    Toggle("Countdown Failsafe", isOn: Binding(
                        get: {
                            appSettings.countdownResetMode == .manual
                        },
                        set: { newValue in
                            appSettings.countdownResetMode = newValue ? .manual : .off
                        }
                    ))
                    .font(.custom("Roboto-Regular", size: 20))

                    Text("""
                         When ON, pausing a countdown preserves its remaining time.
                         When OFF, pausing resets the countdown.
                         """)
                        .font(.custom("Roboto-Light", size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    Picker("Reset Confirmation", selection: $appSettings.resetConfirmationMode) {
                        ForEach(ResetConfirmationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .font(.custom("Roboto-Regular", size: 20))
                    .padding(.top, 8)

                    Text("""
                         • Off: tapping “reset” immediately resets the SYNC timer.  
                         • Double Tap: must tap “reset” twice (within 1 second).  
                         • Popup Confirmation: shows “Are you sure?” before resetting.  
                         """)
                    .font(.custom("Roboto-Light", size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    
                    // ── NEW SECTION: “Stop Confirmation” ──────────────────
                    Picker("Stop Confirmation", selection: $appSettings.stopConfirmationMode) {
                        ForEach(ResetConfirmationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .font(.custom("Roboto-Regular", size: 20))
                    .padding(.top, 16)

                    Text("""
                    • Off: tapping “stop” immediately pauses/stops the SYNC timer.  
                    • Double Tap: must tap “stop” twice (within 1 second).  
                    • Popup Confirmation: shows “Are you sure?” before stopping.  
                    """)
                    .font(.custom("Roboto-Light", size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }

                Section("sync status") {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(syncSettings.isEstablished ? .green : .red)
                            .frame(width: 16, height: 16)
                        Text(syncSettings.statusMessage)
                            .font(.custom("Roboto-Light", size: 20))
                    }
                    // ── NEW: Parent Lock Toggle ─────────────────────────
                    Toggle("Parent Lock (children locked)", isOn: $syncSettings.parentLockEnabled)
                        .font(.custom("Roboto-Regular", size: 20))
                    Text("""
                        When ON (default), any child device that is connected and sync is on will have most of its UI disabled, 
                        except for “desync” and Settings.
                        """)
                        .font(.custom("Roboto-Light", size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                }

                Section("theme") {
                    Picker("background", selection: $appSettings.appTheme) {
                        ForEach(AppTheme.allCases) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                }
            }
            .navigationTitle("settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("done") { dismiss() }
                        .font(.custom("Roboto-Regular", size: 20))
                }
            }
        }
        .presentationDetents([.medium])
    }
}


//──────────────────────────────────────────────────────────────
// MARK: – ContentView
//──────────────────────────────────────────────────────────────
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings = false
    @State private var mainMode: ViewMode = .sync

    var body: some View {
        // Decide regular SYNC backdrop
        let bgImageName: String = {
            switch settings.appTheme {
            case .light: return "MainBG1"
            case .dark:  return "MainBG2"
            }
        }()

        ZStack(alignment: .bottomLeading) {
            // 1) If STOP mode, draw a full-screen red behind everything
            if mainMode == .stop {
                AppBackdrop(imageName: bgImageName)
            }
            // 2) Otherwise, draw your normal AppBackdrop
            else {
                AppBackdrop(imageName: bgImageName)
            }

            // 3) Main stack (TimerCard, NumPad, etc.)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                MainScreen(
                    parentMode: $mainMode,
                    showSettings: $showSettings
                )
                Spacer(minLength: 12)
            }
            // 4) Force “dark appearance” whenever mainMode == .stop
            .preferredColorScheme(
                mainMode == .stop
                    ? .dark
                    : (settings.appTheme == .dark ? .dark : .light)
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

//──────────────────────────────────────────────────────────────
// MARK: – @main
//──────────────────────────────────────────────────────────────
private struct HidingHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) ->
        HidingHostingController<EmptyView> {
            HidingHostingController(rootView: EmptyView())
    }
    func updateUIViewController(_ vc: HidingHostingController<EmptyView>,
                                context: Context) {}
}

@main
struct SyncTimerApp: App {
    @StateObject private var appSettings  = AppSettings()
    @StateObject private var syncSettings = SyncSettings()


    init() {
        // 1) Register Roboto faces explicitly (as you already do).
        registerRoboto()
        
        // 2) PREPARE A HAPTIC GENERATOR
        // Creating & preparing one here ensures the first .impactOccurred() isn't delayed.
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.prepare()
        // (We don't need to keep `haptic` around—just calling prepare() is enough.)

        // 3) PRELOAD A DUMMY TIMER PUBLISHER
        // Create a “fire‐and‐cancel” publisher so your actual timer pipeline is already loaded.
        //
        // We publish one value immediately and then cancel; that forces Timer.publish to
        // compile & link its machinery in advance.
        // new: fire once, let Combine auto‐cancel (no need to capture `self`)
        _ = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in /* nothing else needed – it auto‐completes */ }


        // 4) PRE-INSTANTIATE THE SETTINGS SHEET
        // Construct the SettingsView off-screen so presenting it later isn’t delayed.
        //
        // We don’t show it immediately—this merely forces SwiftUI to allocate & compile it.
        let _ = SettingsView()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
                .environmentObject(syncSettings)
                // We still respect the user’s chosen appTheme here…
                .preferredColorScheme(appSettings.appTheme == .dark
                    ? .dark
                    : .light)
                .background(HidingHost())
        }
    }
}


