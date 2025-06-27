
//
//  SyncTimerApp.swift   – 2025-06-01, compile-clean
//


import SwiftUI
import Combine
import AudioToolbox
import CoreText
import Network
import SystemConfiguration
import WatchConnectivity
import CoreImage.CIFilterBuiltins
import CoreBluetooth
import SpriteKit


//───────────────────
// MARK: – tiny helpers
//───────────────────
extension SyncSettings.SyncConnectionMethod: SegmentedOption {
  var icon: String {
    switch self {
    case .network:   return "network"      // pick your SF Symbol
    case .bluetooth: return "dot.radiowaves.left.and.right"
    case .bonjour:   return "antenna.radiowaves.left.and.right"
    }
  }
  var label: String { rawValue }
}
extension AnyTransition {
  static var settingsSlide: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .top).combined(with: .opacity),
      removal:   .move(edge: .top).combined(with: .opacity)
    )
  }
}

extension View {
    /// Simple inner‐shadow for any `Shape` (e.g. Circle())
    func innerShadow<S: Shape>(
        _ shape: S,
        color: Color = .black.opacity(0.3),
        lineWidth: CGFloat = 2,
        blur: CGFloat = 2,
        x: CGFloat = 0,
        y: CGFloat = 1
    ) -> some View {
        overlay(
            shape
                .stroke(color, lineWidth: lineWidth)
                .blur(radius: blur)
                .offset(x: x, y: y)
                .mask(shape.fill(
                    LinearGradient(
                        gradient: Gradient(colors: [.black, .clear]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ))
        )
    }
}


enum FeedbackType: String, CaseIterable, Identifiable, SegmentedOption {
  case feedback        = "Haptics"
  case safety = "Failsafes"

  // Identifiable
  var id: String { rawValue }

  // SegmentedOption
  var icon: String {
    switch self {
    case .feedback:        return "bell.and.waves.left.and.right.fill"
    case .safety: return "lock.fill"
    }
  }
  var label: String { rawValue }
}
protocol SegmentedOption: CaseIterable, Identifiable {
  /// SF Symbol name for this segment
  var icon: String { get }
  /// Text label for this segment
  var label: String { get }
}

enum SafetyLevel: String, CaseIterable, Identifiable, SegmentedOption {
  case low    = "Low"
  case medium = "Medium"
  case high   = "High"

  // Identifiable
  var id: String { rawValue }

  // SegmentedOption
  var icon: String {
    switch self {
    case .low:    return "shield.lefthalf.fill"
    case .medium: return "shield.fill"
    case .high:   return "shield.checkerboard"
    }
  }
  var label: String { rawValue }
}


private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self)}
}
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red  : Double((hex & 0xFF0000) >> 16) / 255,
                  green: Double((hex & 0x00FF00) >>  8) / 255,
                  blue : Double( hex & 0x0000FF       ) / 255,
                  opacity: 1)
    }
}


/// Centralized app-level settings (themes, preferences, etc.)
final class AppSettings: ObservableObject {
    @Published var roleSwitchConfirmationMode: RoleSwitchConfirmationMode = .popup

    /// Light or dark overall theme
    @Published var appTheme: AppTheme = .light

    /// Overlay color for light theme (ignored if .clear)
    @Published var customThemeOverlayColor: Color = .clear

    /// In low-power mode, UI effects/materials are reduced
    @Published var lowPowerMode: Bool = false

    /// Use high-contrast sync indicator (checkmark/x instead of lamp)
    @Published var highContrastSyncIndicator: Bool = false

    /// Vibrate when a flash fires
    @Published var vibrateOnFlash: Bool = true

    /// Flash duration (in milliseconds)
    @Published var flashDurationOption: Int = 250

    /// Which flash style to use
    @Published var flashStyle: FlashStyle = .fullTimer

    /// Color of the flash effect
    @Published var flashColor: Color = .red

    /// Countdown reset lock mode
    @Published var countdownResetMode: CountdownResetMode = .off

    /// Confirmation mode for resets
    @Published var resetConfirmationMode: ResetConfirmationMode = .off

    /// Confirmation mode for stop actions
    @Published var stopConfirmationMode: ResetConfirmationMode = .off
}

extension AppSettings {
    /// `.black` in light theme, `.white` in dark theme
    var themeTextColor: Color {
        appTheme == .dark ? .white : .black
    }
}
private func nextEventMode(after mode: EventMode) -> EventMode {
    switch mode {
    case .stop:  return .cue
    case .cue:   return .restart
    case .restart: return .stop
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

struct EventBottomButtons: View {
    let canAdd: Bool
    let eventMode: EventMode
    let add: () -> Void
    let reset: () -> Void
    
    private var primaryLabel: String {
        switch eventMode {
        case .stop:
            return canAdd ? "ADD" : "NEXT"
        case .cue, .restart:
            return "ADD"
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // ── Left: “CLEAR”
            Button("CLEAR") {
                reset()
            }
            .font(.custom("Roboto-SemiBold", size: 28))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)


            // ── Right: “ADD” or “NEXT”
            Button(primaryLabel) {
                add()
            }
            .font(.custom("Roboto-SemiBold", size: 28))
            .disabled(!canAdd)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 36)
        .offset(y: 8)
    }
}
//───────────────────
// MARK: – Re-usable themed backdrop
//───────────────────
struct AppBackdrop: View {
    @EnvironmentObject private var appSettings: AppSettings
    
    let imageName: String          // pass the chosen image name in
    
    var body: some View {
        ZStack {
            if appSettings.lowPowerMode {
                // pure black or white
                Color(appSettings.appTheme == .dark ? .black : .white)
                    .ignoresSafeArea()
            } else {
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
        }
    }
}
public struct TimerMessage: Codable, Equatable {
    public enum Action: String, Codable {
        case update, start, pause, reset, addEvent
    }

    public var action   : Action
    public var timestamp: TimeInterval
    public var phase    : String
    public var remaining: TimeInterval
    public var stopEvents: [StopEventWire]

    public init(action: Action,
                timestamp: TimeInterval,
                phase: String,
                remaining: TimeInterval,
                stopEvents: [StopEventWire])
    {
        self.action     = action
        self.timestamp  = timestamp
        self.phase      = phase
        self.remaining  = remaining
        self.stopEvents = stopEvents
    }
}
//───────────────────
// MARK: – app models
//───────────────────
/// “Network” vs. “Bluetooth” sync
enum SyncConnectionMethod: String, CaseIterable, Identifiable {
    case network
    case bluetooth
    case bonjour

    var id: String { rawValue }
}
enum FlashStyle: String, CaseIterable, Identifiable {
    case dot, fullTimer, delimiters, numbers, tint
    var id: String { rawValue }
}
enum Phase { case idle, countdown, running, paused }
enum CountdownResetMode: Int, CaseIterable, Identifiable { case off = 0, manual = 1 ; var id: Int { rawValue } }
enum SyncRole: String, CaseIterable, Identifiable { case parent, child ; var id: String { rawValue } }
enum ViewMode { case sync, stop, settings }                       // ← lives at top level

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
}
public enum ResetConfirmationMode: String, CaseIterable, Identifiable {
    case off             = "Off"
    case doubleTap       = "Double Tap"
    case popup           = "Popup Confirmation"

    public var id: String { rawValue }
}

enum RoleSwitchConfirmationMode: String, CaseIterable, Identifiable {
  case off       = "Off"
  case doubleTap = "Double Tap"
  case popup     = "Popup Confirmation"
  var id: String { rawValue }
}


final class SyncSettings: ObservableObject {
    // ── Auto-generate a lobby code on init if none exists
        init() {
            // ensure we never start with an empty code
            generateCodeIfNeeded()
        }
    @AppStorage("localNickname") var localNickname: String = NicknameGenerator.make()
    @Published var pairingServiceUUID: CBUUID?        = nil
    @Published var pairingCharacteristicUUID: CBUUID? = nil
    @Published var pairingDeviceName: String?         = nil

    // Parent’s listener endpoint (populated when you startParent())
    @Published var listenerIPAddress: String = ""
    @Published var listenerPort:      UInt16 = 50000

    // Child’s copy of parent info (filled from QR scan)
    @Published var parentIPAddress: String?
    @Published var parentPort:      UInt16?

    // MARK: — Lobby properties
    /// Current 5-digit code for lobby join
    @Published var currentCode: String = ""
    /// Whether new peers are prevented from joining
    @Published var isLobbyLocked: Bool = false
    /// Unique ID for this device in lobby
    let localPeerID: UUID = UIDevice.current.identifierForVendor ?? UUID()
    /// List of peers in lobby (sorted by join time)
    @Published private(set) var peers: [Peer] = []
    
    /// Lazily replace a peer’s RSSI and trigger SwiftUI updates
      func updateSignalStrength(peerID: UUID, to rssi: Int) {
        guard let idx = peers.firstIndex(where: { $0.id == peerID }) else { return }
        peers[idx].signalStrength = rssi
      }
    

    /// Model representing a lobby participant
    struct Peer: Identifiable, Equatable {
        let id: UUID
        let name: String
        let role: Role
        let joinTs: UInt64
        var signalStrength: Int    // ← make this `var` not `let`

        static func ==(a: Peer, b: Peer) -> Bool {
          return a.id == b.id
            && a.name == b.name
            && a.role == b.role
            && a.joinTs == b.joinTs
            // note: you can choose whether or not to include `signalStrength` in the equality check
        }
    }



    /// Generate a new, collision-resistant 5-digit numeric lobby code
    func generateCode() {
        var code: String
        repeat {
            code = String(format: "%05d", Int.random(in: 0...99999))
        } while code == currentCode
        currentCode = code
    }

    /// Only generate a code if `currentCode` is empty
        private func generateCodeIfNeeded() {
            if currentCode.isEmpty {
                generateCode()
            }
        }
    
    /// Keys for parsing Bonjour TXT records
    private enum TXTKey {
        static let lobbyCode = "lobby"
        static let lock      = "lock"
        static let role      = "role"
        static let timestamp = "ts"
    }

    /// Called by BonjourSyncManager when a service is resolved
    func handleResolvedService(_ service: NetService, txt: [String: Data]) {
        // Extract the incoming lobby code first, just for logging:
        let incomingCode = txt[TXTKey.lobbyCode]
            .flatMap { String(data: $0, encoding: .utf8) } ?? "(nil)"
        
        // ─── add this line ───────────────────────────────
        print("[BR] \(role == .parent ? "Parent" : "Child") resolved \(service.name) – code =", incomingCode,
              "expecting", currentCode)

        
        // 1) Must match current lobby code
        guard
            let codeData = txt[TXTKey.lobbyCode],
            let code     = String(data: codeData, encoding: .utf8),
            code == currentCode
        else { return }

        // 2) Respect lock
        if let lockData = txt[TXTKey.lock],
           String(data: lockData, encoding: .utf8) == "1" {
            return
        }

        // 3) Parse role
        let peerRole: Role = {
            if let rData = txt[TXTKey.role],
               let rString = String(data: rData, encoding: .utf8),
               rString == "parent" {
                return .parent
            }
            return .child
        }()

        // 4) Parse timestamp
        let peerTs: UInt64 = {
            if let tData = txt[TXTKey.timestamp],
               let s     = String(data: tData, encoding: .utf8),
               let val   = UInt64(s) {
                return val
            }
            return 0
        }()

        // 5) Parse mnemonic name (fall back to strip-and-replace)
        let peerName: String = {
            if let nameData = txt["name"],
               let n = String(data: nameData, encoding: .utf8),
               !n.isEmpty {
                return n
            }
            // fallback: strip your service prefix
            return service.name
                .replacingOccurrences(of: "SyncTimer Parent – ", with: "")
        }()

        // 6) Build the Peer
        let peerID = service.name.hashValueAsUUID
        let peer = Peer(
            id:              peerID,
            name:            peerName,
            role:            peerRole,
            joinTs:          peerTs,
            signalStrength:  3
        )

        // 7) Insert & sort on the main thread
        DispatchQueue.main.async {
            if !self.peers.contains(where: { $0.id == peer.id }) {
                self.peers.append(peer)
                self.peers.sort { $0.joinTs < $1.joinTs }
            }
        }
    }

    enum Role { case parent, child }

    enum SyncConnectionMethod: String, CaseIterable, Identifiable {
        case network   = "LAN"
        case bluetooth = "Bluetooth"
        case bonjour   = "Auto"
        var id: String { rawValue }
    }

    enum SyncErrorCode: String, CaseIterable {
        case timeout      = "ERR01"
        case noWiFi       = "ERR02"
        case bluetoothOff = "ERR03"
        case noPartners   = "ERR04"
        case invalidPort  = "ERR05"
        case invalidIP    = "ERR06"
        case bleDenied    = "ERR07"
        case unknown      = "ERR08"

        var message: String {
            switch self {
            case .timeout:      return "No devices found"
            case .noWiFi:       return "No Wi-Fi connected"
            case .bluetoothOff: return "Bluetooth is off"
            case .noPartners:   return "No partners found, retrying"
            case .invalidPort:  return "Invalid port: must be ephemeral"
            case .invalidIP:    return "Invalid IP address"
            case .bleDenied:    return "BLE permission denied"
            case .unknown:      return "Unknown error"
            }
        }
    }

    @Published var errorCode: SyncErrorCode? = nil
    @Published var connectionMethod: SyncConnectionMethod = .network
    @Published var parentLockEnabled = false
    @Published var discoveredPeers: [Peer]   = []
    @Published var stopWires: [StopEventWire] = []

    /// Existing API to add prior-discovered BLE/Bonjour peers
    func addDiscoveredService(name: String, role: Role, signal: Int) {
        let peer = Peer(id: UUID(), name: name, role: role, joinTs: UInt64(Date().timeIntervalSince1970*1000), signalStrength: 3)
        DispatchQueue.main.async {
            if let idx = self.discoveredPeers.firstIndex(of: peer) {
                self.discoveredPeers[idx] = peer
            } else {
                self.discoveredPeers.append(peer)
            }
        }
    }

    lazy var bleDriftManager = BLEDriftManager(owner: self)
    lazy var bonjourManager  = BonjourSyncManager(owner: self)

    var isLocked: Bool {
        role == .child && isEnabled && parentLockEnabled
    }

    @Published var role: Role         = .parent
    @Published var isEnabled          = false
    @Published var isEstablished      = false
    @Published var statusMessage: String = "Not connected"
    @Published var listenPort: String = "50000"
    @Published var peerIP:     String = ""
    @Published var peerPort:   String = "50000"

    private var listener: NWListener?
    private var childConnections: [NWConnection] = []
    private var clientConnection: NWConnection?

    var onReceiveTimer: ((TimerMessage)->Void)? = nil

    func integrateBonjourConnection(_ conn: NWConnection) {
        clientConnection?.cancel()
        clientConnection = conn
        DispatchQueue.main.async {
            self.isEstablished  = true
            self.statusMessage  = "Bonjour: connected"
        }
        receiveLoop(on: conn)
    }

    func getCurrentElapsed() -> TimeInterval { 0 }
    func getElapsedAt(timestamp: TimeInterval) -> TimeInterval { 0 }

    func setRawStops(_ rawStops: [StopEvent]) {
        let wires = rawStops.map {
            StopEventWire(eventTime: $0.eventTime, duration: $0.duration)
        }
        DispatchQueue.main.async { self.stopWires = wires }
    }
    /// Insert or replace a peer, then sort + publish
    func insertOrUpdate(_ peer: Peer) {
      if let idx = peers.firstIndex(where: { $0.id == peer.id }) {
        peers[idx] = peer
      } else {
        peers.append(peer)
      }
      peers.sort { $0.joinTs < $1.joinTs }
    }
    


    // ── START PARENT ───────────────────────────────────
    func startParent() {
        guard listener == nil else { return }
        guard let portNum = UInt16(listenPort), portNum > 0 else {
            statusMessage = "Invalid port"
            return
        }

        // never re-assign listenerPort here – wait until we know .ready
        do {
            listener = try NWListener(using: .tcp, on: .init(rawValue: portNum)!)
        } catch {
            listener = nil
            statusMessage = "Listen failed: \(error.localizedDescription)"
            return
        }

        isEstablished  = false
        statusMessage  = "Waiting for children…"

        listener?.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            switch newState {
            case .ready:
                let myIP = getLocalIPAddress() ?? "Unknown"
                DispatchQueue.main.async {
                    self.listenerIPAddress = myIP
                    self.listenerPort      = portNum
                    self.statusMessage     = "Listening on \(myIP):\(portNum)"
                }
            case .failed(let err):
                DispatchQueue.main.async {
                    self.statusMessage = "Listener error: \(err.localizedDescription)"
                }
                self.stopParent()
            default: break
            }
        }

        listener?.newConnectionHandler = { [weak self] newConn in
            guard let self = self else { return }
            self.childConnections.append(newConn)
            self.setupParentConnection(newConn)
        }

        listener?.start(queue: .global(qos: .background))

        switch connectionMethod {
        case .network:   break
        case .bluetooth: bleDriftManager.start()
        case .bonjour:
            bonjourManager.startAdvertising()
            statusMessage = "Bonjour: advertising"
        }
    }

    private func setupParentConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.isEstablished = true
                    self.statusMessage = "Child connected"
                }
                self.receiveLoop(on: conn)
            case .failed, .cancelled:
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

    func stopParent() {
        listener?.cancel()
        listener = nil
        childConnections.forEach { $0.cancel() }
        childConnections.removeAll()
        DispatchQueue.main.async {
            self.isEstablished = false
            self.statusMessage = "Not listening"
        }
        switch connectionMethod {
        case .network:   break
        case .bluetooth: bleDriftManager.stop()
        case .bonjour:   bonjourManager.stopAdvertising()
        }
    }


    // ── BLUETOOTH HELPER ────────────────────────────────
    func connectToParent(host: String, port: UInt16) {
        guard clientConnection == nil else {
            print("⚠️ connectToParent: already have clientConnection")
            return
        }

        let endpoint = NWEndpoint.Host(host)
        let nwPort   = NWEndpoint.Port(rawValue: port)!
        let conn     = NWConnection(host: endpoint, port: nwPort, using: .tcp)
        clientConnection = conn

        DispatchQueue.main.async {
            self.statusMessage   = "Connecting…"
            self.isEstablished   = false
        }
        print("👉 Child (BT) connecting to \(host):\(port)…")

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.isEstablished = true
                    self.statusMessage = "Connected to \(host):\(port)"
                }
                self.receiveLoop(on: conn)

            case .failed(let err):
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Connect failed: \(err.localizedDescription)"
                }
                conn.cancel()
                self.clientConnection = nil

            case .cancelled:
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Disconnected"
                }
                self.clientConnection = nil

            default: break
            }
        }

        conn.start(queue: .global(qos: .background))

        // 30 s timeout
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, let c = self.clientConnection else { return }
            if c.state != .ready {
                c.cancel()
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Timeout"
                }
                self.clientConnection = nil
            }
        }
    }


    // ── START CHILD ───────────────────────────────────
    func startChild() {
        switch connectionMethod {
        case .network:
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
            
        case .bluetooth:
                    guard let h = parentIPAddress,
                          let p = parentPort else {
                        print("🔴 no parent endpoint, can’t startChild()")
                        return
                    }
                    connectToParent(host: h, port: p)
                    bleDriftManager.start()

                case .bonjour:
                    bonjourManager.startBrowsing()
                    statusMessage = "Bonjour: searching…"
                }
            }

            func stopChild() {
                switch connectionMethod {
                case .network:
                    clientConnection?.cancel()
                    clientConnection = nil
                    DispatchQueue.main.async {
                        self.isEstablished = false
                        self.statusMessage = "Not connected"
                    }

                case .bluetooth:
                    bleDriftManager.stop()

                case .bonjour:
                    bonjourManager.stopBrowsing()
                    clientConnection?.cancel()
                    clientConnection = nil
                    DispatchQueue.main.async {
                        self.isEstablished = false
                        self.statusMessage = "Not connected"
                    }
                }
            }
    
    // ── BROADCAST A JSON-ENCODED MESSAGE TO “ALL CHILDREN” (parent only) ──
    func broadcastToChildren(_ msg: TimerMessage) {
        guard role == .parent else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(msg) else { return }
        let framed = data + Data([0x0A])   // newline-delimit each JSON packet
        
        for conn in childConnections {
            conn.send(content: framed, completion: .contentProcessed({ _ in }))
        }
        
        ConnectivityManager.shared.send(msg)

    }
    
    // ── SEND JSON TO PARENT (child only) ─────────────────────────────────
    func sendToParent(_ msg: TimerMessage) {
        guard role == .child, let conn = clientConnection else { return }
        let encoder = JSONEncoder()
        ConnectivityManager.shared.send(msg)
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


// MARK: — Helpers
private extension String {
    /// Generate a stable UUID from this string’s hash
    var hashValueAsUUID: UUID {
        var hasher = Hasher()
        hasher.combine(self)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        let data = withUnsafeBytes(of: hash.bigEndian) { Data($0) } + Data(repeating: 0, count: 8)
        return UUID(uuid: (
            data[0], data[1], data[2], data[3],
            data[4], data[5], data[6], data[7],
            data[8], data[9], data[10], data[11],
            data[12], data[13], data[14], data[15]
        ))
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

struct RestartEvent: Identifiable, Equatable {
    let id = UUID()
    var restartTime: TimeInterval   // when to “reset” (fire) in seconds

    static func ==(lhs: RestartEvent, rhs: RestartEvent) -> Bool {
        return lhs.id == rhs.id
    }
}


enum Event: Identifiable, Equatable {
    case stop(StopEvent)
    case cue(CueEvent)
    case restart(RestartEvent)

    var id: UUID {
        switch self {
        case .stop(let s):   return s.id
        case .cue(let c):    return c.id
        case .restart(let r):  return r.id
        }
    }

    var fireTime: TimeInterval {
        switch self {
        case .stop(let s):   return s.eventTime
        case .cue(let c):    return c.cueTime
        case .restart(let r):  return r.restartTime
        }
    }

    /// Helper readable property for the TimerCard’s circles
    var isStop: Bool {
        switch self {
        case .stop:   return true
        case .cue:    return false
        case .restart:  return false
        }
    }
}

/// “Which type of event‐entry UI are we in?”
enum EventMode {
    case stop
    case cue
    case restart
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
    enum Key: Hashable {
        case digit(Int), backspace
        case settings, chevronLeft, chevronRight
        case dot, enter
    }
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings
    
    @Binding var parentMode: ViewMode
    @Binding var settingsPage: Int
    @Binding var isEntering: Bool      // new: true when we're editing an IP/port
    let onKey: (Key) -> Void
    let onSettings: () -> Void
    var lockActive: Bool = false
    
    
    private var hGap: CGFloat { isVerySmallPhone ? 16 : 20 }
    private var vGap: CGFloat { isVerySmallPhone ?  8 : 12 }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)
    private var isVerySmallPhone: Bool {
        UIScreen.main.bounds.width <= 376
    }
    
    // bottom row keys switch based on `isEntering`
    private var allKeys: [Key] {
        // top 3 rows are always 1–9
        var keys = (1...9).map { Key.digit($0) }
        
        
        // bottom row:
        if isEntering {
            // when editing IP/Port: “.”, “0”, “⏎”
            keys += [.dot, .digit(0), .enter]
        } else if parentMode == .settings {
            // in Settings pages (non-editing): gear + arrows
            keys += [.settings, .chevronLeft, .chevronRight]
        } else {
            // normal Sync/Events view: gear + 0 + backspace
            keys += [.settings, .digit(0), .backspace]
        }
        
        
        return keys
    }
    
    
    
    // For iPhones up to ~6.1", shrink some spacing
    private var isSmallPhone: Bool {
        UIScreen.main.bounds.height < 930
    }
    
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: vGap) {
            ForEach(allKeys, id: \.self) { key in
                Button {
                    handle(key)
                } label: {
                    icon(for: key)
                        .frame(maxWidth: .infinity, minHeight: calcKeyHeight())
                }
                .buttonStyle(.plain)
                // disable all except settings when locked
                .disabled(
                    lockActive
                    && (key == .digit(0)    // but this won’t match all cases neatly...
                        || key == .backspace)
                )
            }
        }
        .padding(.horizontal, hGap)
        .onChange(of: isEntering) { newValue in
            print("Numpad saw isEntering = \(newValue)")
        }
        
    }
    
    
    
    // MARK: – key handling
    private func handle(_ key: Key) {
        switch key {
        case .digit, .backspace:
            guard !lockActive else { return }
            onKey(key)
            
            
        case .dot:
            guard isEntering else { return }
            onKey(.dot)
            
            
        case .enter:
            guard isEntering else { return }
            onKey(.enter)
            isEntering = false
            
            
        case .settings:
            onSettings()
            
            
        case .chevronLeft:
            guard parentMode == .settings else { return }
            settingsPage = (settingsPage + 3) % 4
            
            
        case .chevronRight:
            guard parentMode == .settings else { return }
            settingsPage = (settingsPage + 1) % 4
        }
    }
    
    
    // MARK: – icon builder
    @ViewBuilder
    private func icon(for key: Key) -> some View {
        let dark = (colorScheme == .dark)
        switch key {
        case .digit(let n):
            Text("\(n)")
                .font(.custom("Roboto-Regular", size: isSmallPhone ? 44 : 52))
                .foregroundColor(dark ? .white : .primary)
            
            
        case .backspace:
            Image(systemName: "delete.left")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(dark ? .white : .primary)
                .accessibilityLabel("Backspace")
            
            
        case .settings:
            let isActive = (parentMode == .settings)
            Image(systemName: isActive ? "gearshape.fill" : "gearshape")
                .font(.system(size: 48, weight: .medium))
                .accessibilityLabel("Settings")
                .foregroundColor(dark ? .white : .primary)
                .rotationEffect(
                    .degrees(!appSettings.lowPowerMode && isActive ? 360 : 0)
                )
                .animation(
                    .easeInOut(duration: 0.5),
                    value: isActive
                )
            
            
        case .chevronLeft:
            Image(systemName: "arrow.left")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(dark ? .white : .primary)
                .accessibilityLabel("Previous page")
            
            
        case .chevronRight:
            Image(systemName: "arrow.right")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(dark ? .white : .primary)
                .accessibilityLabel("Next page")
            
            
        case .dot:
            Text(".")
                .font(.custom("Roboto-Regular", size: 52))
                .foregroundColor(dark ? .white : .primary)
            
            
        case .enter:
            Image(systemName: "return")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(dark ? .white : .primary)
                .accessibilityLabel("Enter")
        }
    }
    
    
    // MARK: – sizing helpers
    // screen dimensions in “portrait” points
    private func calcKeyHeight() -> CGFloat {
        let screenSize = UIScreen.main.bounds.size
        let pW = min(screenSize.width, screenSize.height)
        let pH = max(screenSize.width, screenSize.height)
        
        let isVerySmallPhone = (pW == 320 && pH == 568)    // iPhone 5 / SE (1st gen)
                            || (pW == 375 && pH == 667)
        let isMiniPhone      = (pW == 375 && pH == 812)
        
        let totalWidth = UIScreen.main.bounds.width - 2*hGap
        let side       = (totalWidth - 2*20) / 3
        
        let heightMultiplier: CGFloat = isVerySmallPhone ? 0.4
        : isMiniPhone      ? 0.75
        : 0.825
        
        let keyH = side * heightMultiplier
        let totalVgaps = vGap * 3
        return (keyH * 4 + totalVgaps) / 4
    }
}



//──────────────────────────────────────────────────────────────
// MARK: – Sync / Stop bars
//──────────────────────────────────────────────────────────────

struct SyncBar: View {
    @EnvironmentObject private var syncSettings: SyncSettings
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    /// True when either a countdown or the stopwatch is active.
    var isCounting: Bool
    
    var isSyncEnabled: Bool
    let onToggleSync: () -> Void

    /// Called when the role switch is finally confirmed.
    let onRoleConfirmed: (SyncSettings.Role) -> Void

    @State private var awaitingSecondTap = false
    @State private var showRoleAlert      = false
    @State private var targetRole: SyncSettings.Role?

    private var isSmallPhone: Bool {
        UIScreen.main.bounds.height < 930
    }

    var body: some View {
        let isDark        = (colorScheme == .dark)
        let activeColor   = isDark ? Color.white : Color.black
        let inactiveColor = Color.gray

        HStack(spacing: 0) {
            // ── Role toggle ────────────────────────────
            Button {
                guard !isCounting else { return }
                switch settings.roleSwitchConfirmationMode {
                case .off:
                    let newRole: SyncSettings.Role = syncSettings.role == .parent ? .child : .parent
                    onRoleConfirmed(newRole)

                case .doubleTap:
                    if awaitingSecondTap {
                        awaitingSecondTap = false
                        onRoleConfirmed(syncSettings.role == .parent ? .child : .parent)
                    } else {
                        awaitingSecondTap = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            awaitingSecondTap = false
                        }
                    }

                case .popup:
                    targetRole   = syncSettings.role == .parent ? .child : .parent
                    showRoleAlert = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("CHILD")
                        .font(.custom("Roboto-SemiBold", size: 24))
                        .foregroundColor(syncSettings.role == .child ? activeColor : inactiveColor)
                    Text("/")
                        .font(.custom("Roboto-SemiBold", size: 24))
                        .foregroundColor(inactiveColor)
                    Text("PARENT")
                        .font(.custom("Roboto-SemiBold", size: 24))
                        .foregroundColor(syncSettings.role == .parent ? activeColor : inactiveColor)
                }
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
                .accessibilityLabel("Switch role")
                .accessibilityHint("Double-tap to toggle between child and parent")
            }
            .disabled(isCounting)
            .alert(isPresented: $showRoleAlert) {
                Alert(
                    title: Text("Confirm Role Switch"),
                    message: Text("Switch to \((targetRole == .parent) ? "PARENT" : "CHILD") mode?"),
                    primaryButton: .default(Text("Yes")) {
                        if let newRole = targetRole { onRoleConfirmed(newRole) }
                    },
                    secondaryButton: .cancel()
                )
            }

            // ── Sync/Stop button ─────────────────────────
            // push everything left, so this group hugs right
                        Spacer(minLength: 0)
                        // ── Sync/Stop + lamp, always 8 pt apart ─────────
                        HStack(spacing: 8) {
                            Button {
                                guard !isCounting else { return }
                                onToggleSync()
                            } label: {
                                Text(isSyncEnabled ? "STOP" : "SYNC")
                                    .font(.custom("Roboto-SemiBold", size: 24))
                                    .foregroundColor(activeColor)
                                    .fixedSize()
                            }
                            .disabled(syncSettings.role == .parent && isCounting)
            
                            if settings.highContrastSyncIndicator {
                                Image(systemName: syncSettings.isEstablished
                                      ? "checkmark.circle.fill"
                                      : "xmark.octagon.fill")
                                    .foregroundColor(syncSettings.isEstablished ? .green : .red)
                                    .frame(width: 18, height: 18)
                            } else {
                                Circle()
                                    .fill(syncSettings.isEstablished ? .green : .red)
                                    .frame(width: 18, height: 18)
                            }
                        }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }



    /// Encapsulate the three‐step BLE role change
    private func applyRoleChange(_ newRole: SyncSettings.Role) {
        // 1) Tear down whatever BLE role we were in
        syncSettings.bleDriftManager.stop()
        // 2) Flip the logical role
        syncSettings.role = newRole
        // 3) Re‐start BLE in the new role
        syncSettings.bleDriftManager.start()
        // 4) Notify any parent logic
        onRoleConfirmed(newRole)
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
    private let arrowsSpacing: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let keyWidth  = (fullWidth - 40) / 3
            
            // Position arrows at the very edges of the carousel:
            let leftX     =  (keyWidth / 2 + 12) - arrowsSpacing
            let rightX    = fullWidth - (keyWidth / 2 + 12) + arrowsSpacing
            let midY      = (geo.size.height / 2)

            ZStack {
                // ─── Center “No events” or the current event’s text + delete “×”
                if events.isEmpty {
                    Text("No events added")
                        .font(.custom("Roboto-Light", size: 20))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 10)
                        .position(x: fullWidth / 2, y: midY)
                }
                else if currentIndex < events.count {
                    HStack(spacing: 4) {
                        Text(formattedText(for: events[currentIndex], index: currentIndex + 1))
                            .font(.custom("Roboto-Light", size: 20))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)

                        Button {
                            events.remove(at: currentIndex)
                            // After removing, clamp currentIndex
                            if events.isEmpty {
                                currentIndex = 0
                            } else if currentIndex >= events.count {
                                currentIndex = events.count - 1
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .frame(width: 12, height: 12)
                                .padding(.horizontal, 0)
                                .foregroundColor(.gray)
                            
                        }
                        .buttonStyle(.plain)
                        .disabled(isCounting)
                        .accessibilityLabel("Delete event")
                        .accessibilityHint("Removes this stop/cue from the schedule")
                    }
                    .position(x: fullWidth / 2, y: midY)
                }

                // ─── LEFT ARROW, only if we can page backward
                if currentIndex > 0 {
                    Button {
                        currentIndex -= 1
                    } label: {
                        Image(systemName: "arrow.left")
                            .resizable()
                            .frame(width: 18, height: 16)
                            .foregroundColor(.black)
                            .accessibilityLabel("Previous event")

                    }
                    .position(x: leftX, y: midY)
                    .disabled(isCounting)
                }

                // ─── RIGHT ARROW, only if we can page forward
                if currentIndex < events.count - 1 {
                    Button {
                        currentIndex += 1
                    } label: {
                        Image(systemName: "arrow.right")
                            .resizable()
                            .frame(width: 18, height: 16)
                            .foregroundColor(.black)
                            .accessibilityLabel("Next event")

                    }
                    .position(x: rightX, y: midY)
                    .disabled(isCounting)
                }
            }
            .onChange(of: events) { newEvents in
                // If the array shrank below currentIndex, clamp it.
                if newEvents.isEmpty {
                    currentIndex = 0
                } else if currentIndex >= newEvents.count {
                    currentIndex = newEvents.count - 1
                }
            }
        }
        .frame(height: 160)
    }

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
            if parts.isEmpty { parts.append("0s") }
            return parts.joined()
        }

        switch event {
        case .stop(let s):
            return "\(index). Stop at \(timeString(s.eventTime))"
        case .cue(let c):
            return "\(index). Cue at \(timeString(c.cueTime))"
        case .restart(let r):
            return "\(index). Restart at \(timeString(r.restartTime))"
        }
    }
}


//──────────────────────────────────────────────────────────────
// MARK: – Bottom button rows
//──────────────────────────────────────────────────────────────
struct SyncBottomButtons: View {
    @EnvironmentObject private var settings: AppSettings
    /// whether to show the RESET button
        var showResetButton: Bool = true
        /// when in Settings, show “N / 4” instead of the Start/Stop button
        var showPageIndicator: Bool = false
        /// 1-based current page
        var currentPage: Int = 1
        /// total number of pages
        var totalPages: Int = 4    /// true when countdown or run loop is active
    
    var isCounting: Bool

    /// callback to either “start” (when not running) or “stop” (when running)
    let startStop: () -> Void

    /// callback to actually perform “reset”
    let reset: () -> Void

    @State private var showResetConfirm: Bool      = false
    @State private var awaitingSecondTap: Bool     = false

    // ── New for “stop” confirmation ───────────────────────────────────
    @State private var showStopConfirm: Bool       = false
    @State private var awaitingStopSecondTap: Bool = false

    var body: some View {
        HStack(spacing: 0) {
                    // ── Left: “RESET” (hidden in Settings)
                    if showResetButton {
                        Button("RESET") {
                            reset()
                        }
                        .font(.custom("Roboto-SemiBold", size: 28))
                        .foregroundColor(settings.themeTextColor)
                        .opacity(isCounting ? 0.3 : 1)           // faded while running
                        .disabled(isCounting)
                        .accessibilityHint("Clears the timer when you’re not running")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .alert("Confirm Reset", isPresented: $showResetConfirm) {
                            Button("Yes, reset", role: .destructive) {
                                performReset()
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Are you sure you want to reset the timer?")
                        }
                    }
            
            
            // ── Right: page indicator in Settings, otherwise “STOP”/“START”
                        if showPageIndicator {
                            Text("\(currentPage) / \(totalPages)")
                                .font(.custom("Roboto-SemiBold", size: 28))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Button(action: {
                                if isCounting {
                                    handleStopTap()
                                } else {
                                    startStop()
                                }
                                lightHaptic()
                            }) {
                                Text(isCounting ? "STOP" : "START")
                                    .font(.custom("Roboto-SemiBold", size: 28))
                                    .foregroundColor(settings.themeTextColor)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .accessibilityHint(isCounting
                                        ? "Stops the timer"
                                        : "Starts or resumes the timer")
                            }
                        }
            // never disable either button at this level; your confirm‐alert logic handles it
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 36)
        .offset(y: 8)
        .alert("Confirm Stop", isPresented: $showStopConfirm) {
            Button("Yes, stop", role: .destructive) {
                performStop()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to stop the timer?")
        }
    }

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
        startStop()            // actually call the “stop” action
        awaitingStopSecondTap = false
    }
}



// ─── Utility for nicely-formatted centiseconds ───────────────────────
extension TimeInterval {
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
struct TimerCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings

// ── New: detect landscape
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    // ── Hint‐flash timer and states ─────────────────────────────────
    @State private var leftFlash: Bool = false
    @State private var rightFlash: Bool = false
    private let flashTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    // ── “ERR” flash states ───────────────────────────────────────────
    @State private var isErrFlashing: Bool = false
    @State private var showErr: Bool = false

    // ── SYNCING… logic ───────────────────────────────────────────────
    @State private var dotCount: Int = 0
    @State private var showNothingYet: Bool = false
    @State private var syncError: Bool = false
    @State private var dotTimer: AnyCancellable? = nil
    @State private var toggleTimer: AnyCancellable? = nil

    // ── Computed string of dots ──────────────────────────────────────
    private var dotString: String {
        switch dotCount {
        case 0:  return "."
        case 1:  return ".."
        case 2:  return "..."
        default: return "."
        }
    }

    // ── Flags for hint flashes ───────────────────────────────────────
    private var shouldFlashLeft: Bool {
        mode == .stop && stopStep == 0
    }
    private var shouldFlashRight: Bool {
        mode == .stop && stopStep == 1
    }

    // ── Inputs ───────────────────────────────────────────────────────
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
    var events: [Event]

    // ── Derived styling ────────────────────────────────────────────
    private var isDark: Bool  { colorScheme == .dark }
    private var txtMain: Color { isDark ? .white : .primary }
    private var txtSec:  Color { isDark ? Color.white.opacity(0.6) : .secondary }
    private var leftTint: Color {
        (mode == .stop && stopStep == 0) ? txtMain : txtSec
    }
    private var rightTint: Color {
        (mode == .stop && stopStep == 1) ? txtMain : txtSec
    }

    // ── Render raw digits as “HH:MM:SS.CC” ─────────────────────────────
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
        ZStack {
            
            // ── Toggle hints via flashTimer ───────────────────────────────
            Color.clear
                .onReceive(flashTimer) { _ in
                    if shouldFlashLeft {
                        leftFlash.toggle()
                    } else {
                        leftFlash = false
                    }
                    if shouldFlashRight {
                        rightFlash.toggle()
                    } else {
                        rightFlash = false
                    }
                }
            
            GeometryReader { geo in
                // In portrait, we inset 16pt on each side; in landscape, only 10pt each side:
                let horizontalInset: CGFloat = isLandscape ? 10 : 16
                let innerW = geo.size.width - (horizontalInset * 2)
                // “fs” is the base font‐size for the big timer text; scale it up in landscape:
                let fsPortrait = innerW / 4.6
                let fs = isLandscape ? (fsPortrait * 1.4) : fsPortrait
                let isCompactWidth = (geo.size.width <= 389)

                // Now pick all the other sizes according to the same scale:
                let hintFontSize: CGFloat = isLandscape ? 32 : 24    // for “START POINT” / “DURATION”
                let subTextFontSize: CGFloat = isLandscape ? 28 : 20 // for “SYNCING…”, circles’ “S/C/R” labels
                let circleDiameter: CGFloat = isLandscape ? 30 : 18  // for the 5 event circles
                let stopTimerFontSize: CGFloat = isLandscape ? 30 : 24 // for the small stop‐timer underneath

                ZStack {
                    // ── (A) Card background with drop shadow ─────────────────
                    if !isLandscape {
                        Group {
                            if settings.lowPowerMode {
                                // Low‐Power: flat fill only
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isDark ? Color.black : Color.white)
                            } else {
                                // Normal: material + overlay + shadow
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.black.opacity(isDark ? 0.25 : 0))
                                    )
                                    .shadow(
                                        color: Color.black.opacity(0.125),
                                        radius: 10, x: 0, y: 6
                                    )
                            }
                        }
                        .ignoresSafeArea(edges: .horizontal)

                        if settings.flashStyle == .tint && flashZero {
                        
                        
                            flashColor
                                .ignoresSafeArea()
                                .transition(.opacity)
                                .animation(.easeInOut(duration: Double(settings.flashDurationOption) / 1000), value: flashZero)
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .opacity(0.5)
                        }
                    }

                    // ── (B) Full vertical stack ────────────────────────────
                    VStack(spacing: 0) {
                        // B.1) Top hints “START POINT” / “DURATION” ────────────
                        ZStack {
                            let primaryHintColor = isDark ? Color.white : Color.black
                            HStack {
                                Text(leftHint)
                                    .foregroundColor(
                                        shouldFlashLeft
                                        ? (leftFlash ? primaryHintColor : Color.gray)
                                        : Color.gray
                                    )
                                Spacer()
                                Text(rightHint)
                                    .foregroundColor(
                                        shouldFlashRight
                                        ? (rightFlash ? primaryHintColor : Color.gray)
                                        : Color.gray
                                    )
                            }
                            .font(.custom("Roboto-Regular", size: hintFontSize))
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            
                            // ── “ERR” flashes ────────────────────────────────────
                            if showErr {
                                Text("ERR")
                                    .font(.custom("Roboto-Regular", size: hintFontSize))
                                    .foregroundColor(txtMain)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 6)
                            }
                        }
                        .onChange(of: syncSettings.statusMessage) { newMsg in
                            if newMsg.contains("Invalid")
                                || newMsg.contains("failed")
                                || newMsg.contains("Timeout") {
                                triggerErrFlash()
                            }
                        }
                    
                        
                        // B.2) Main time + dash + flash overlays ───────────────
                        HStack(spacing: 4) {
                            // the “–” prefix
                            Text("-")
                                .font(.custom("Roboto-Light", size: fs))
                                .foregroundColor(isCountdownActive ? .black : .gray)


                            // ZStack so we can overlay “flash” text on top of the normal timer text
                            ZStack {
                                // 1) Idle raw-digits entry mode
                                if mode == .stop && (phase == .idle || phase == .paused) {                                    Text(rawString(from: stopDigits))
                                        .font(.custom("Roboto-Regular", size: fs))
                                        .minimumScaleFactor(0.5)
                                        .foregroundColor(txtMain)
                                }
                                else if mode == .sync && phase == .idle && !syncDigits.isEmpty {
                                    Text(rawString(from: syncDigits))
                                        .font(.custom("Roboto-Regular", size: fs))
                                        .minimumScaleFactor(0.5)
                                        .foregroundColor(txtMain)
                                }


                                // 2) Running or after idle → always show the properly formatted, rollover‐correct time
                                else {
                                    let fullString = mainTime.formattedCS
                                    Text(fullString)
                                        .font(.custom("Roboto-Regular", size: fs))
                                        .minimumScaleFactor(0.5)
                                        .foregroundColor(
                                            flashStyle == .fullTimer && flashZero
                                                ? flashColor
                                                : txtMain
                                        )
                                }


                                // 3) Overlay the flashing delimiters / numbers—but ONLY at the zero moment
                                if (flashStyle == .delimiters || flashStyle == .numbers) && flashZero {
                                    Text(makeFlashed())
                                        .font(.custom("Roboto-Regular", size: fs))
                                        .minimumScaleFactor(0.5)

                                }


                                // 4) Dot style flash
                                if flashStyle == .dot && flashZero {
                                    Circle()
                                        .fill(flashColor)
                                        .frame(
                                            width: isLandscape ? 16 : 10,
                                            height: isLandscape ? 16 : 10
                                        )
                                        .offset(x: innerW / 2 - 36, y: -fs * 0.45)
                                }

                            }
                            
                        }
                        .padding(.horizontal, 12)
                        Spacer(minLength: 4)
                        .accessibilityElement(children: .combine)

                        // ── NEW: when width ≤389, show failsafe icons here ─────────
                                  if isCompactWidth {
                                    HStack(spacing: 16) {
                                      if settings.countdownResetMode == .manual {
                                        ZStack {
                                          Image(systemName: "lock.fill")
                                          Text("C")
                                            .font(.custom("Roboto-SemiBold", size: subTextFontSize * 0.8))
                                        }
                                        .foregroundColor(txtMain)
                                      }
                                      if settings.stopConfirmationMode != .off {
                                        ZStack {
                                          Image(systemName: "lock.fill")
                                          Text("S")
                                            .font(.custom("Roboto-SemiBold", size: subTextFontSize * 0.8))
                                        }
                                        .foregroundColor(txtMain)
                                      }
                                      if settings.resetConfirmationMode != .off {
                                        ZStack {
                                          Image(systemName: "lock.fill")
                                          Text("R")
                                            .font(.custom("Roboto-SemiBold", size: subTextFontSize * 0.8))
                                        }
                                        .foregroundColor(txtMain)
                                      }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 4)
                                  }
                        
                        // B.3) “SYNCING…” / “NOTHING FOUND YET…” or 5 event‐circles ──
                        HStack(spacing: 0) {
                            if syncSettings.isEnabled && !syncSettings.isEstablished {
                                if syncError {
                                    Text("ERR01: No devices found")
                                        .font(.custom("Roboto-Light", size: subTextFontSize))
                                        .foregroundColor(isDark ? .white : .black)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 0) // moved 18 more to the right
                                } else {
                                    if showNothingYet {
                                        Text("NOTHING FOUND YET\(dotString)")
                                            .font(.custom("Roboto-Light", size: subTextFontSize))
                                            .foregroundColor(isDark ? .white : .black)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 0)
                                    } else {
                                        Text("SYNCING\(dotString)")
                                            .font(.custom("Roboto-Light", size: subTextFontSize))
                                            .foregroundColor(isDark ? .white : .black)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 0)
                                    }
                                }
                            } else {
                                ForEach(0..<5) { idx in
                                    if idx < events.count {
                                        switch events[idx] {
                                        case .stop:
                                            ZStack {
                                                Circle()
                                                    .fill(flashColor)
                                                    .frame(width: circleDiameter,
                                                       height: circleDiameter)
                                                Text("S")
                                                    .font(.custom("Roboto-Regular", size: subTextFontSize * 0.6))
                                                    .foregroundColor(isDark ? .black : .white)
                                            }
                                        case .cue:
                                            ZStack {
                                                Circle()
                                                .stroke(flashColor, lineWidth: isLandscape ? 1.5 : 1)
                                                .frame(width: circleDiameter,
                                                       height: circleDiameter)
                                                Text("C")
                                                    .font(.custom("Roboto-Regular", size: subTextFontSize * 0.6))
                                                    .foregroundColor(flashColor)
                                            }
                                        case .restart:
                                            ZStack {
                                                Circle()
                                                .stroke(flashColor, lineWidth: isLandscape ? 1.5 : 1)
                                                .frame(width: circleDiameter,
                                                       height: circleDiameter)
                                                Text("R")
                                                    .font(.custom("Roboto-Regular", size: subTextFontSize * 0.6))
                                                    .foregroundColor(isDark ? .white : .black)
                                            }
                                        }
                                    } else {
                                        Circle()
                                        .stroke(Color.gray, lineWidth: isLandscape ? 1.5 : 1)
                                        .frame(width: circleDiameter,
                                               height: circleDiameter)
                                    }
                                    Spacer().frame(width: isLandscape ? 8 : 4)
                                }
                            }

                            Spacer()

                            Text(stopActive ? stopRemaining.formattedCS : "00:00:00.00")
                                .font(.custom("Roboto-Regular", size: stopTimerFontSize))
                                .foregroundColor(
                                    stopActive
                                        ? flashColor
                                        : (mode == .sync ? txtSec : txtMain)
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                        Spacer(minLength: 4)

                        // B.4) Bottom labels “EVENTS VIEW” / “SYNC VIEW” ──────
                        HStack {
                            Text("EVENTS VIEW")
                                .foregroundColor(mode == .stop ? txtMain : txtSec)
                            Spacer()
                            Text("SYNC VIEW")
                                .foregroundColor(mode == .sync ? txtMain : txtSec)
                        }
                        .font(.custom("Roboto-Regular", size: isLandscape ?  28 : 24))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                    // ── (B.5) Failsafe indicators ─────────────────────────────────
                    HStack(spacing: 16) {
                        if settings.countdownResetMode == .manual {
                            ZStack {
                                Image(systemName: "lock.fill")
                                Text("C")
                                    .font(.custom("Roboto-SemiBold", size: subTextFontSize * 0.8))
                            }
                            .foregroundColor(txtMain)
                        }
                        if settings.stopConfirmationMode != .off {
                            ZStack {
                                Image(systemName: "lock.fill")
                                Text("S")
                                    .font(.custom("Roboto-SemiBold", size: subTextFontSize * 0.8))
                            }
                            .foregroundColor(txtMain)
                        }
                        if settings.resetConfirmationMode != .off {
                            ZStack {
                                Image(systemName: "lock.fill")
                                Text("R")
                                    .font(.custom("Roboto-SemiBold", size: subTextFontSize * 0.8))
                            }
                            .foregroundColor(txtMain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .position(
                        x: geo.size.width / 2,
                        y: geo.size.height - (isLandscape ? 24 : 16)
                    )

                    // ── (C) Tap zones to switch mode ─────────────────────
                    if !isLandscape {
                        HStack(spacing: 0) {
                            // Left half: tap → EVENTS (stop)
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture {
                                    mode = .stop
                                    lightHaptic()
                                }
                            // Right half: tap → SYNC
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture {
                                    mode = .sync
                                    lightHaptic()
                                }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                    }
                }
                .frame(
                width: isLandscape
                    ? geo.size.width               // full width in landscape (we already inset via horizontalInset)
                    : (geo.size.width - 32),       // subtract 16pt left+right in portrait
                height: isLandscape
                    ? geo.size.height              // full height in landscape
                    : 190                          // fixed 190 in portrait
                )
                .padding(.horizontal, isLandscape ? horizontalInset : 16)
                

            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Elapsed time: \(mainTime.formattedCS)")
            .accessibilityHint(
              mode == .stop
                ? "Tap left half for Events View, right half for Sync View"
                : "Tap to switch views"
            )
        }
        
        // ── Lifecycle & syncing‐phase orchestration ──────────────────────
        .onAppear {
            if syncSettings.isEnabled && !syncSettings.isEstablished {
                beginSyncingPhase()
            }
        }
        .onChange(of: syncSettings.isEnabled) { isEnabled in
            if isEnabled && !syncSettings.isEstablished {
                beginSyncingPhase()
            } else {
                cancelSyncingPhase()
            }
        }
        .onChange(of: syncSettings.isEstablished) { established in
            if established {
                cancelSyncingPhase()
            }
        }
    }

    // ── Start dot animation, then “NOTHING” toggling, then error ─────
    private func beginSyncingPhase() {
        syncError = false
        showNothingYet = false
        dotCount = 0

        // 1) Start dot animation
        dotTimer?.cancel()
        dotTimer = Timer.publish(every: 0.4, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                dotCount = (dotCount + 1) % 3
            }

        // 2) After 6 seconds, toggle “NOTHING FOUND YET…” every 4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard !syncSettings.isEstablished else { return }
            showNothingYet = true
            toggleTimer?.cancel()
            toggleTimer = Timer.publish(every: 4.0, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    showNothingYet.toggle()
                }
        }

        // 3) After 30 seconds, show error
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            guard !syncSettings.isEstablished else { return }
            cancelSyncingPhase()
            syncError = true
            triggerErrFlash()
        }
    }

    private func cancelSyncingPhase() {
        dotTimer?.cancel(); dotTimer = nil
        toggleTimer?.cancel(); toggleTimer = nil
        syncError = false
        showNothingYet = false
        dotCount = 0
    }

    // ── “ERR” flash helper ─────────────────────────────────────────────
    private func triggerErrFlash() {
        guard !isErrFlashing else { return }
        isErrFlashing = true
        showErr = true

        var toggleCount = 0
        func doToggle() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showErr.toggle()
                toggleCount += 1
                if toggleCount < 6 {
                    doToggle()
                } else {
                    showErr = false
                    isErrFlashing = false
                }
            }
        }
        doToggle()
        
    }
    
}

enum EditableField { case ip, port, lobbyCode }

//──────────────────────────────────────────────────────────────
// MARK: – MainScreen  (everything in one struct)
//──────────────────────────────────────────────────────────────
struct MainScreen: View {
    // ── Environment & Settings ────────────────────────────────
    @EnvironmentObject private var settings   : AppSettings
    @EnvironmentObject var syncSettings: SyncSettings
    @AppStorage("settingsPage") private var settingsPage: Int = 0
    let numberOfPages = 4
    
    @State private var showSyncErrorAlert = false
    @State private var syncErrorMessage = ""

    
    // ── UI mode ────────────────────────────────────────────────
    @Binding var parentMode: ViewMode
    @State private var previousMode: ViewMode = .sync   // track old mode
    
    // ── Detect landscape vs portrait ───────────────────────────
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
    // ── Timer state ─────────────────────────────────────────────

    @State var phase: Phase = .idle
    @State private var flashZero: Bool = false
    @State var countdownDigits: [Int] = []
    @State private var countdownDuration: TimeInterval = 0
    @State var countdownRemaining: TimeInterval = 0
    @State var elapsed: TimeInterval = 0
    @State var startDate: Date? = nil
    @State private var ticker: AnyCancellable? = nil
    @State private var justEditedAfterPause: Bool = false
    @State private var pausedElapsed: TimeInterval = 0
    @State private var stopCleared: Bool = false


    
    // ── Sync / Lock ─────────────────────────────────────────────
    private var lockActive: Bool { syncSettings.isLocked }
    private var padLocked: Bool {
        lockActive
        || phase == .running
        || phase == .countdown
    }
    
    
    // ── Stop‐event buffers + unified events + rawStops ───────────
    @State private var stopDigits: [Int] = []
    @State private var cueDigits: [Int] = []
    @State private var restartDigits: [Int] = []
    @State private var stopStep: Int = 0       // 0 = start, 1 = duration
    @State private var tempStart: TimeInterval = 0
    @State private var events: [Event] = []
    @State private var rawStops: [StopEvent] = []
    @State private var stopActive: Bool = false
    @State private var stopRemaining: TimeInterval = 0
    @State private var editedAfterFinish: Bool = false
    @State private var editingTarget: EditableField? = nil   // nil = not editing
    @State private var inputText      = ""                   // live buffer
    @State private var isEnteringField = false
    @State private var showBadPortError = false

    private func confirm(_ text: String) {
            // Only validate port on Enter
            if editingTarget == .port {
                if let p = UInt16(text), (49153...65534).contains(p) {
                    syncSettings.peerPort = text
                    showBadPortError = false
                    editingTarget = nil
                    isEnteringField = false
                } else {
                    showBadPortError = true
                }
                return
            }
            // IP or Lobby‐Code
            switch editingTarget {
            case .ip:
                syncSettings.peerIP = text
            case .lobbyCode:
                syncSettings.currentCode = text
            default:
                break
            }
            inputText = ""
            editingTarget = nil
            isEnteringField = false
        }
    
    
    
    @State private var eventMode: EventMode = .stop
    @Binding var showSettings: Bool
    
    @AppStorage("hasSeenWalkthrough") private var hasSeenWalkthrough: Bool = true
    @AppStorage("walkthroughPage") private var walkthroughPage: Int = 0
    
    // ── Derived: true when countdown or stopwatch is active ──────
    private var isCounting: Bool {
        phase == .countdown || phase == .running
    }
    // only true when actively counting down or paused with some time left
    private var willCountDown: Bool {
        phase == .countdown
        || (phase == .paused && countdownRemaining > 0)
        // only treat “typed digits” as a countdown if it's not the special post-finish edit
        || (phase == .idle && !countdownDigits.isEmpty && !justEditedAfterPause)
    }
    
    
    // ─────────────────────────────────────────────────────────────
    // Only clear the *list* of events — do NOT touch stopDigits
    private func clearAllEvents() {
        events.removeAll()
        stopCleared = false

    }


    
    var body: some View {
        
        // 1) Detect “Max-sized” devices by width (≈414pt+)
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight      = UIScreen.main.bounds.height
        let isMax       = screenWidth >= 414 //max
        let isMiniPhone       = screenWidth == 375 && screenHeight == 812 //mini
        let isVerySmallPhone = screenWidth <= (376) && !isMiniPhone //SE
        let isStandardPhone   = screenWidth == 390 && screenHeight == 844 //12/13/14
        
        let isSmallPhone = (screenWidth > 376 && screenWidth < 414) && !isStandardPhone //pro
        
        // — new detection for iPhone 13/14 mini & iPhone 12/13/14 —
        
        // 2) Decide your offsets
        let timerOffset   = isMax ? 36 : 10    // ↓ TimerCard/SettingsPagerCard
        let modeBarOffset = isMax ? -42 : -56    // ↓ mode bar
        
        ZStack {
            
            if settings.flashStyle == .tint && flashZero && isLandscape {
                settings.flashColor
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(
                        .easeInOut(duration: Double(settings.flashDurationOption) / 1000),
                        value: flashZero
                    )
            }
            
            if isLandscape {
                GeometryReader { fullGeo in
                    let hm: CGFloat = 8
                    let w   = fullGeo.size.width  - (hm * 2)
                    let h   = fullGeo.size.height * 0.22
                    
                    TimerCard(
                        mode: $parentMode,
                        flashZero: $flashZero,
                        isRunning: phase == .running,
                        flashStyle: settings.flashStyle,
                        flashColor: settings.flashColor,
                        syncDigits: countdownDigits,
                        stopDigits: {
                            switch eventMode {
                            case .stop:    return stopDigits
                            case .cue:     return cueDigits
                            case .restart: return restartDigits
                            }
                        }(),
                        phase: phase,
                        mainTime: displayMainTime(),
                        stopActive: stopActive,
                        stopRemaining: stopRemaining,
                        leftHint: "START POINT",
                        rightHint: "DURATION",
                        stopStep: stopStep,
                        makeFlashed: makeFlashedOverlay,
                        isCountdownActive: willCountDown,
                        events: events
                    )
                    .frame(width: w, height: h)
                    .position(x: fullGeo.size.width/2, y: fullGeo.size.height/2)
                    .offset(y: 12)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            } else {
                // ── PORTRAIT ──────────────────────────────────────
                VStack(spacing: isVerySmallPhone ? 2 : (isSmallPhone ? 4 : 8)) {
                    // Top card (Timer or Settings)
                    Group {
                        if parentMode == .settings {
                            SettingsPagerCard(
                                page: $settingsPage,
                                editingTarget: $editingTarget,
                                inputText: $inputText,
                                isEnteringField: $isEnteringField,
                                showBadPortError:$showBadPortError
                            )
                            .environmentObject(settings)
                            .environmentObject(syncSettings)
                            .transition(.settingsSlide)
                        } else {
                            TimerCard(
                                mode: $parentMode,
                                flashZero: $flashZero,
                                isRunning: phase == .running,
                                flashStyle: settings.flashStyle,
                                flashColor: settings.flashColor,
                                syncDigits: countdownDigits,
                                stopDigits: eventMode == .stop ? stopDigits
                                : eventMode == .cue  ? cueDigits
                                : restartDigits,
                                phase: phase,
                                mainTime: displayMainTime(),
                                stopActive: stopActive,
                                stopRemaining: stopRemaining,
                                leftHint: "START POINT",
                                rightHint: "DURATION",
                                stopStep: stopStep,
                                makeFlashed: makeFlashedOverlay,
                                isCountdownActive: willCountDown,
                                events: events
                            )
                            .allowsHitTesting(!lockActive)
                            .transition(.settingsSlide)
                        }
                    }
                    .frame(height: isVerySmallPhone ? 220
                           : isSmallPhone     ? 260
                           : 296)
                    .padding(.top,
                             parentMode == .settings
                             ? ( isVerySmallPhone ? 120
                                 : (isSmallPhone ? 32
                                    : 16) + 26)   // 38+18 on small, 52+20 on max
                             : (isVerySmallPhone ? 102
                                : isSmallPhone ? 54
                                : 56)   // 44+10 on small, 60+20 on max
                    )
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.4), value: parentMode)
                    
                    // Mode bar (Sync / Events)
                    if parentMode == .sync || parentMode == .stop {
                        ZStack {
                            if !settings.lowPowerMode {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .frame(height: 80)
                                    .shadow(color: .black.opacity(0.125), radius: 10, x: 0, y: 6)
                            }
                            if parentMode == .sync {
                                SyncBar(
                                    isCounting: isCounting,
                                    isSyncEnabled: syncSettings.isEnabled,
                                    onToggleSync: toggleSyncMode, onRoleConfirmed: { newRole in
                                        syncSettings.role = newRole
                                    }
                                      )
                                      .environmentObject(syncSettings)
                            } else {
                                EventsBar(
                                    events: $events,
                                    eventMode: $eventMode,
                                    isCounting: isCounting,
                                    onAddStop: commitStopEntry,
                                    onAddCue:  commitCueEntry,
                                    onAddRestart: commitRestartEntry
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, isVerySmallPhone ? 44
                                 : isSmallPhone ? 0
                                 : isStandardPhone ? -36
                                 : -46)
                        .padding(.top, CGFloat(modeBarOffset))
                    }
                    
                    Spacer(minLength: 0)
                    
                    // NumPad
                    NumPadView(
                        parentMode:   $parentMode,
                        settingsPage: $settingsPage,
                        isEntering:   $isEnteringField,
                        onKey: { key in
                            // ① If editing an IP/port field in Settings:
                            if parentMode == .settings && isEnteringField {
                                switch key {
                                case .digit(let n):
                                    inputText.append(String(n))
                                case .dot:
                                    inputText.append(".")
                                case .backspace:
                                    _ = inputText.popLast()
                                case .enter:
                                    confirm(inputText)
                                default:
                                    break
                                }
                                return
                            }
                            // ② Normal timer/chevron behavior:
                            if parentMode != .settings {
                                switch key {
                                case .digit, .backspace:
                                    if parentMode == .sync {
                                        handleCountdownKey(key)
                                    } else {
                                        switch eventMode {
                                        case .stop:    handleStopKey(key)
                                        case .cue:     handleCueKey(key)
                                        case .restart: handleRestartKey(key)
                                        }
                                    }
                                case .settings:
                                    previousMode = parentMode
                                    parentMode   = .settings
                                default:
                                    break
                                }
                            } else {
                                // In Settings but not editing: page flips
                                switch key {
                                case .chevronLeft:
                                    settingsPage = (settingsPage + numberOfPages - 1) % numberOfPages
                                case .chevronRight:
                                    settingsPage = (settingsPage + 1) % numberOfPages
                                default:
                                    break
                                }
                            }
                        },
                        onSettings: {
                            // Gear toggles in/out of Settings
                            if parentMode == .settings {
                                parentMode = previousMode
                            } else {
                                previousMode = parentMode
                                parentMode   = .settings
                            }
                        },
                        lockActive: padLocked
                    )
                    .offset(y: isVerySmallPhone ? -110
                            : isSmallPhone     ? -60
                            : isStandardPhone ? -38
                            : -52)
                    
                    // Bottom buttons
                    ZStack {
                                SyncBottomButtons(
                                    showResetButton:   parentMode == .sync,
                                    showPageIndicator: parentMode == .settings,
                                    currentPage:       settingsPage + 1,
                                    totalPages:        numberOfPages,
                                    isCounting:        isCounting,
                                    startStop:         toggleStart,
                                    reset:             resetAll
                                )
                            .disabled(lockActive || parentMode != .sync)
                            .opacity(parentMode == .sync    ? 1.0 :
                                     parentMode == .settings ? 0.3 : 0.0)
                            // overlay just the page title over where RESET lives
                            if parentMode == .settings {
                                // compute the title for each settings‐page
                                let pageTitle: String = {
                                    switch settingsPage {
                                    case 0: return "THEME"  // look & feel
                                    case 1: return "SET"        // timer behavior
                                    case 2: return "CONNECT"    // connection method
                                    case 3: return "ABOUT"      // about
                                    default: return ""
                                    }
                                }()
                                HStack {
                                    Text(pageTitle)
                                        .font(.custom("Roboto-SemiBold", size: 28))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 36)
                                .offset(y: 8)
                            }
                    
                        EventBottomButtons(
                            canAdd: {
                                switch eventMode {
                                case .stop:    return !stopDigits.isEmpty
                                case .cue:     return !cueDigits.isEmpty
                                case .restart: return !restartDigits.isEmpty
                                }
                            }(),
                            eventMode: eventMode,
                            add: {
                                switch eventMode {
                                case .stop:    commitStopEntry()
                                case .cue:     commitCueEntry()
                                case .restart: commitRestartEntry()
                                }
                            },
                            reset: clearAllEvents
                        )
                        .disabled(lockActive)
                        .opacity(parentMode == .stop ? 1 : 0)
                    }
                    .frame(height: 44)
                    .offset(y: isVerySmallPhone ? -100
                            : isSmallPhone ? -60
                            : isStandardPhone ? -38
                            : -48)
                    .padding(.bottom, isVerySmallPhone ? 4
                             : isSmallPhone ? 4
                             : isStandardPhone ? 4
                             : 8)
                    
                    // Walkthrough “?”
                    .overlay(alignment: .center) {
                        if parentMode == .settings {
                            Button {
                                hasSeenWalkthrough = false
                                walkthroughPage    = 0
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 24))
                                    .opacity(0.75)
                                    .foregroundColor(.gray)
                                    .accessibilityLabel("Help")
                                    .accessibilityHint("Restarts the in-app walkthrough")
                            }
                            .offset(y: -44)
                        }
                    }
                    .transition(.settingsSlide)
                    .animation(.easeInOut(duration: 0.4), value: parentMode)
                }
            }
        }

        .alert(isPresented: $showSyncErrorAlert) {
                    Alert(
                        title: Text("Cannot Start Sync"),
                        message: Text(syncErrorMessage),
                        dismissButton: .default(Text("OK"))
                    )
                }
                // wire up the child‐side handler
                .onAppear {
                    syncSettings.onReceiveTimer = { msg in
                        applyIncomingTimerMessage(msg)
                    }
                }
                .onDisappear {
                    syncSettings.onReceiveTimer = nil
                }
        
        // 1) When you switch *into* Events view, seed the STOP buffer:
            .onChange(of: parentMode) { newMode in
                if newMode == .stop {
                    // ensure we’re in STOP mode
                    eventMode   = .stop
                    stopDigits  = timeToDigits(displayMainTime())
                    stopStep    = 0
                    stopCleared = false
                }
            }
            // 2) When you switch *within* Events between Stop/Cue/Restart:
            .onChange(of: eventMode) { newMode in
                switch newMode {
                case .stop:
                    stopDigits  = timeToDigits(displayMainTime())
                    stopStep    = 0
                    stopCleared = false
                case .cue:
                    cueDigits   = timeToDigits(displayMainTime())
                case .restart:
                    restartDigits = timeToDigits(displayMainTime())
                }
            }
        // ── When the parent stops syncing, immediately kill any live countdown ──
                    .onChange(of: syncSettings.isEnabled) { isEnabled in
                        if !isEnabled {
                            // parent just hit “STOP” → tear down our countdown ticker
                            ticker?.cancel()
                            // reset to idle
                            phase = .idle
                            // zero‐out any in-flight time
                            countdownDigits.removeAll()
                            countdownDuration = 0
                            countdownRemaining = 0
                            elapsed = 0
                            startDate = nil
                        }
                    }
    }
        

    //──────────────────── Helper: TimeInterval → [Int] for HHMMSScc ─────
    private func timeToDigits(_ time: TimeInterval) -> [Int] {
        let totalCs = Int((time * 100).rounded())
        let cs = totalCs % 100
        let s = (totalCs / 100) % 60
        let m = (totalCs / 6000) % 60
        let h = totalCs / 360000
        var arr = [
            h / 10, h % 10,
            m / 10, m % 10,
            s / 10, s % 10,
            cs / 10, cs % 10
        ]
        while arr.first == 0 && arr.count > 1 {
            arr.removeFirst()
        }
        return arr
    }
    
    //──────────────────── formatted overlay ─────────────────────────────────
    private func makeFlashedOverlay() -> AttributedString {
        let raw = displayMainTime().csString
        var a = AttributedString(raw)
        for i in a.characters.indices {
            let ch = a.characters[i]
            let delim = (ch == ":" || ch == ".")
            let doFlash: Bool
            switch settings.flashStyle {
            case .delimiters:
                doFlash = delim && flashZero
            case .numbers:
                doFlash = !delim && flashZero
            default:
                doFlash = false
            }
            a[i...i].foregroundColor = doFlash ? settings.flashColor : .primary
        }
        return a
    }
    
    //──────────────────── main-time chooser ─────────────────────────────────
    private func displayMainTime() -> TimeInterval {
        switch phase {
        case .idle:
            if !countdownDigits.isEmpty {
                return digitsToTime(countdownDigits)
            }
            return countdownRemaining
        case .countdown:
            return countdownRemaining
        case .running:
            return elapsed
        case .paused:
            if countdownRemaining > 0 {
                return countdownRemaining
            }
            return elapsed
        }
    }
    

    // MARK: – toggleSyncMode (drop-in)
    private func toggleSyncMode() {
        if syncSettings.isEnabled {
            // — TURN SYNC OFF —
            switch syncSettings.connectionMethod {
            case .network:
                if syncSettings.role == .parent { syncSettings.stopParent() }
                else                           { syncSettings.stopChild() }

            case .bluetooth:
                if syncSettings.role == .parent { syncSettings.stopParent() }
                else                           { syncSettings.stopChild() }

            case .bonjour:
                syncSettings.bonjourManager.stopAdvertising()
                syncSettings.bonjourManager.stopBrowsing()
                if syncSettings.role == .parent { syncSettings.stopParent() }
                else                             { syncSettings.stopChild() }
            }

            syncSettings.isEnabled     = false
            syncSettings.statusMessage = "Sync stopped"

        } else {
            // — PRE-CHECK RADIOS —
            switch syncSettings.connectionMethod {
            case .network, .bonjour:
                // Wi-Fi must be up
                let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
                let sem = DispatchSemaphore(value: 0)
                monitor.pathUpdateHandler = { _ in sem.signal() }
                monitor.start(queue: .global(qos: .background))
                sem.wait()                  // wait for first update
                let path = monitor.currentPath
                monitor.cancel()
                guard path.status == .satisfied else {
                    syncErrorMessage   = "Wi-Fi is off or not connected.\nPlease enable Wi-Fi to sync."
                    showSyncErrorAlert = true
                    return
                }

            case .bluetooth:
                    // Only error if Bluetooth is explicitly powered OFF
                    let btMgr = CBCentralManager(delegate: nil, queue: nil, options: nil)
                    if btMgr.state == .poweredOff {
                        syncErrorMessage   = "Bluetooth is off.\nPlease enable Bluetooth to sync."
                        showSyncErrorAlert = true
                        return
                    }
            }

            // — TURN SYNC ON — (existing logic unchanged)
            switch syncSettings.connectionMethod {
            case .network:
                if syncSettings.role == .parent { syncSettings.startParent() }
                else                           { syncSettings.startChild() }

            case .bluetooth:
                if syncSettings.role == .parent { syncSettings.startParent() }
                else                           { syncSettings.startChild() }

            case .bonjour:
                if syncSettings.role == .parent {
                    syncSettings.startParent()
                    syncSettings.bonjourManager.startAdvertising()
                    syncSettings.bonjourManager.startBrowsing()
                    syncSettings.statusMessage = "Bonjour: advertising & listening"
                } else {
                    syncSettings.bonjourManager.advertisePresence()
                    syncSettings.bonjourManager.startBrowsing()
                    syncSettings.statusMessage = "Bonjour: advertising & searching…"
                }
            }

            syncSettings.isEnabled = true
        }
    }


    //──────────────────── timer engine ────────────────────────────────────
    private let dt: TimeInterval = 1.0 / 120.0
    
    private func startLoop() {
        ticker?.cancel()
        ticker = Timer.publish(every: dt, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                switch phase {
                case .countdown:
                    tickCountdown()
                case .running:
                    tickRunning()
                default:
                    break
                }
            }
    }
    
    private func tickCountdown() {
        countdownRemaining = max(0, countdownRemaining - dt)
        if countdownRemaining == 0 {
            phase = .running
            startDate = Date()
            flashZero = true
            if settings.vibrateOnFlash {
                // vibrate the device when the flash fires
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() +
                                          Double(settings.flashDurationOption)/1000) {
                flashZero = false
            }
        }
        // Only broadcast when we’re actually showing the SYNC view
            guard parentMode == .sync, syncSettings.role == .parent else { return }
        
            let msgPhase = (phase == .countdown) ? "countdown" : "running"
            let msg = TimerMessage(
              action: .start,
              timestamp: Date().timeIntervalSince1970,
              phase: msgPhase,
              remaining: displayMainTime(),
              stopEvents: rawStops.map {
                StopEventWire(eventTime: $0.eventTime, duration: $0.duration)
            }
        )
        print("[iOS] about to send TimerMessage")
        ConnectivityManager.shared.send(msg)
        if syncSettings.role == .parent && syncSettings.isEnabled {
            syncSettings.broadcastToChildren(msg)
        }
    }
    
    private func tickRunning() {
        // 1) If we’re in a “stop” period, count that down first
        if stopActive {
            let dt = 1.0 / 120.0
            stopRemaining = max(0, stopRemaining - dt)
            if stopRemaining <= 0 {
                // the stop just finished → resume at exactly the pausedElapsed
                stopActive = false
                elapsed = pausedElapsed
                startDate = Date().addingTimeInterval(-pausedElapsed)
            }
            return
        }

        // 2) Expire any events that were scheduled before our pausedElapsed
        while let first = events.first, first.fireTime <= pausedElapsed {
            events.removeFirst()
        }

        // 3) Advance the main clock
        elapsed = Date().timeIntervalSince(startDate ?? Date())

        // 4) If the next event is due, handle it
        if let nextEvent = events.first, elapsed >= nextEvent.fireTime {
            switch nextEvent {
            case .stop(let s):
                // record where we are, then enter a new stop
                pausedElapsed = elapsed
                stopActive = true
                stopRemaining = s.duration
                events.removeFirst()

                // broadcast updated stop-events list
                let remainingStopWires = events.compactMap { event -> StopEventWire? in
                    if case .stop(let st) = event {
                        return StopEventWire(eventTime: st.eventTime, duration: st.duration)
                    } else {
                        return nil
                    }
                }
                let stopMsg = TimerMessage(
                    action: .update,
                    timestamp: Date().timeIntervalSince1970,
                    phase: "running",
                    remaining: elapsed,
                    stopEvents: remainingStopWires
                )
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    syncSettings.broadcastToChildren(stopMsg)
                }

            case .cue(let c):
                flashZero = true
                let flashSec = Double(settings.flashDurationOption) / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + flashSec) {
                    flashZero = false
                }
                events.removeFirst()

                let remainingStopWires = events.compactMap { event -> StopEventWire? in
                    if case .stop(let st) = event {
                        return StopEventWire(eventTime: st.eventTime, duration: st.duration)
                    } else {
                        return nil
                    }
                }
                let cueMsg = TimerMessage(
                    action: .update,
                    timestamp: Date().timeIntervalSince1970,
                    phase: "running",
                    remaining: elapsed,
                    stopEvents: remainingStopWires
                )
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    syncSettings.broadcastToChildren(cueMsg)
                }

            case .restart(let r):
                ticker?.cancel()
                phase = .running
                elapsed = 0
                startDate = Date()
                startLoop()
                events.removeFirst()

                let remainingStopWires = events.compactMap { event -> StopEventWire? in
                    if case .stop(let st) = event {
                        return StopEventWire(eventTime: st.eventTime, duration: st.duration)
                    } else {
                        return nil
                    }
                }
                let resetMsg = TimerMessage(
                    action: .reset,
                    timestamp: Date().timeIntervalSince1970,
                    phase: "running",
                    remaining: elapsed,
                    stopEvents: remainingStopWires
                )
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    syncSettings.broadcastToChildren(resetMsg)
                }
            }
        }
        // 5) Otherwise, just broadcast the regular running update
        else {
            let remainingStopWires = events.compactMap { event -> StopEventWire? in
                if case .stop(let st) = event {
                    return StopEventWire(eventTime: st.eventTime, duration: st.duration)
                } else {
                    return nil
                }
            }
            let updateMsg = TimerMessage(
                action: .update,
                timestamp: Date().timeIntervalSince1970,
                phase: "running",
                remaining: elapsed,
                stopEvents: remainingStopWires
            )
            if syncSettings.role == .parent && syncSettings.isEnabled {
                syncSettings.broadcastToChildren(updateMsg)
            }
        }
    }


    
    //──────────────────── num-pad helpers ─────────────────────────────────
    private func digitsToTime(_ d: [Int]) -> TimeInterval {
        var a = d
        while a.count < 8 { a.insert(0, at: 0) }
        let h = a[0] * 10 + a[1]
        let m = a[2] * 10 + a[3]
        let s = a[4] * 10 + a[5]
        let cs = a[6] * 10 + a[7]
        return TimeInterval(h * 3600 + m * 60 + s) + TimeInterval(cs) / 100.0
    }
    
    private func handleCountdownKey(_ key: NumPadView.Key) {
        switch key {
        case .digit(let n):
            // If we were paused (or running), switch into “editing” mode by seeding countdownDigits:
            if phase != .idle {
                // If user tapped a digit while paused at 0 (i.e. countdown finished),
                // mark editedAfterFinish = true so toggleStart() will know to resume instead of restart.
                if phase == .paused && countdownRemaining == 0 && elapsed > 0 {
                    justEditedAfterPause = true
                }
                let baseDigits = timeToDigits(displayMainTime())
                countdownDigits = baseDigits
                phase = .idle
            }
            // Now append the new digit:
            if countdownDigits.count < 8 {
                countdownDigits.append(n)
            }
            countdownRemaining = digitsToTime(countdownDigits)
            
            
        case .backspace:
            // If we’re not already in “edit” (phase == .idle), seed from display and switch to idle
            if phase != .idle {
                if phase == .paused && countdownRemaining == 0 && elapsed > 0 {
                    justEditedAfterPause = true
                }
                countdownDigits = timeToDigits(displayMainTime())
                phase = .idle
            }
            // Now perform the actual backspace:
            if !countdownDigits.isEmpty {
                _ = countdownDigits.popLast()
                if !countdownDigits.isEmpty {
                    countdownRemaining = digitsToTime(countdownDigits)
                } else {
                    // If we popped all digits, reset remaining so user can start fresh
                    countdownRemaining = 0
                }
            }
            
            
        default:
            break
        }
    }
    
    private func handleStopKey(_ key: NumPadView.Key) {
        switch key {
        case .digit(let n):
            // Only auto-seed when the buffer is empty *and* the user hasn’t just cleared it:
            if stopDigits.isEmpty && !stopCleared {
                stopDigits = timeToDigits(displayMainTime())
            }
            // Any digit entry resets the “cleared” flag:
            stopCleared = false

            if stopDigits.count < 8 {
                stopDigits.append(n)
            }

        case .backspace:
            // Remove the last digit if there is one:
            if !stopDigits.isEmpty {
                stopDigits.removeLast()
                // If they just emptied the buffer, mark that fact:
                if stopDigits.isEmpty {
                    stopCleared = true
                }
            }

        default:
            break
        }
    }

    
    private func handleCueKey(_ key: NumPadView.Key) {
        switch key {
        case .digit(let n) where cueDigits.count < 8:
            cueDigits.append(n)
        case .backspace:
            if !cueDigits.isEmpty {
                cueDigits.removeLast()
            }
        default:
            break
        }
    }
    
    private func handleRestartKey(_ key: NumPadView.Key) {
        switch key {
        case .digit(let n) where restartDigits.count < 8:
            restartDigits.append(n)
        case .backspace:
            if !restartDigits.isEmpty {
                restartDigits.removeLast()
            }
        default:
            break
        }
    }
    
    

    // 2) Replace your existing commitStopEntry() with:
    private func commitStopEntry() {
        guard !stopDigits.isEmpty else { return }

        if stopStep == 0 {
            // first tap: record start-point, switch to “duration” entry
            tempStart = digitsToTime(stopDigits)
            stopStep = 1
            // seed the duration buffer with the current display-time
            stopDigits = timeToDigits(displayMainTime())
        }
        else {
            // second tap: build the StopEvent
            let dur = digitsToTime(stopDigits)
            let newStop = StopEvent(eventTime: tempStart, duration: dur)

            // record exactly where we are now so we can reseed the UI
            pausedElapsed = displayMainTime()

            events.append(.stop(newStop))
            events.sort { $0.fireTime < $1.fireTime }

            if syncSettings.role == .parent && syncSettings.isEnabled {
                let stopWires: [StopEventWire] = events.compactMap {
                    if case .stop(let s) = $0 {
                        return StopEventWire(eventTime: s.eventTime,
                                             duration: s.duration)
                    } else {
                        return nil
                    }
                }
                let m = TimerMessage(
                    action: .addEvent,
                    timestamp: Date().timeIntervalSince1970,
                    phase: (phase == .running ? "running" : "idle"),
                    remaining: pausedElapsed,
                    stopEvents: stopWires
                )
                syncSettings.broadcastToChildren(m)
            }

            // **re-seed** your entry buffer so the card shows the paused time
            stopDigits = timeToDigits(pausedElapsed)
            stopStep = 0
        }

        lightHaptic()
    }

    private func commitCueEntry() {
        guard !cueDigits.isEmpty else { return }

        // 1) Snapshot the paused time
        pausedElapsed = displayMainTime()

        // 2) Add & sort the new cue event
        let cueTime = digitsToTime(cueDigits)
        let newCue  = CueEvent(cueTime: cueTime)
        events.append(.cue(newCue))
        events.sort { $0.fireTime < $1.fireTime }

        // 3) Broadcast .addEvent if parent
        if syncSettings.role == .parent && syncSettings.isEnabled {
            let stopWires = events.compactMap { event -> StopEventWire? in
                if case .stop(let s) = event {
                    return StopEventWire(eventTime: s.eventTime, duration: s.duration)
                }
                return nil
            }
            let m = TimerMessage(
                action:     .addEvent,
                timestamp:  Date().timeIntervalSince1970,
                phase:      (phase == .running ? "running" : "idle"),
                remaining:  pausedElapsed,
                stopEvents: stopWires
            )
            syncSettings.broadcastToChildren(m)
        }

        // 4) Reseed the cue-buffer so the card shows pausedElapsed
        cueDigits = timeToDigits(pausedElapsed)

        // 5) Force pause at exactly pausedElapsed
        phase     = .paused
        elapsed   = pausedElapsed
        startDate = Date().addingTimeInterval(-pausedElapsed)

        lightHaptic()
    }
    private func commitRestartEntry() {
        guard !restartDigits.isEmpty else { return }

        // 1) Snapshot the paused time
        pausedElapsed = displayMainTime()

        // 2) Add & sort the new restart event
        let rt        = digitsToTime(restartDigits)
        let newRestart = RestartEvent(restartTime: rt)
        events.append(.restart(newRestart))
        events.sort { $0.fireTime < $1.fireTime }

        // 3) Broadcast .addEvent if parent
        if syncSettings.role == .parent && syncSettings.isEnabled {
            let stopWires = events.compactMap { event -> StopEventWire? in
                if case .stop(let s) = event {
                    return StopEventWire(eventTime: s.eventTime, duration: s.duration)
                }
                return nil
            }
            let m = TimerMessage(
                action:     .addEvent,
                timestamp:  Date().timeIntervalSince1970,
                phase:      (phase == .running ? "running" : "idle"),
                remaining:  pausedElapsed,
                stopEvents: stopWires
            )
            syncSettings.broadcastToChildren(m)
        }

        // 4) Reseed the restart-buffer so the card shows pausedElapsed
        restartDigits = timeToDigits(pausedElapsed)

        // 5) Force pause at exactly pausedElapsed
        phase     = .paused
        elapsed   = pausedElapsed
        startDate = Date().addingTimeInterval(-pausedElapsed)

        lightHaptic()
    }

    
    //──────────────────── toggleStart / resetAll ─────────────────────────
    private func toggleStart() {
        switch phase {
        case .idle:
            // If we previously finished a countdown and the user then edited digits,
            // we want to unpause/resume rather than start a brand‐new countdown:
            if justEditedAfterPause {
                let startValue = digitsToTime(countdownDigits)
                phase = .running
                elapsed = startValue
                startDate = Date().addingTimeInterval(-elapsed)
                startLoop()
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "running",
                        remaining: elapsed,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    syncSettings.broadcastToChildren(m)
                }
                justEditedAfterPause = false
                countdownRemaining = 0
                return
            }
            
            
            // Otherwise, proceed with your normal “new‐countdown” logic:
            if !countdownDigits.isEmpty {
                let newSeconds = digitsToTime(countdownDigits)
                countdownDuration = newSeconds
                countdownRemaining = newSeconds
                countdownDigits.removeAll()
            } else {
                countdownRemaining = countdownDuration
            }
            
            
            if countdownDuration > 0 {
                phase = .countdown
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "countdown",
                        remaining: countdownRemaining,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    syncSettings.broadcastToChildren(m)
                }
                startLoop()
            } else {
                phase = .running
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "running",
                        remaining: elapsed,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    syncSettings.broadcastToChildren(m)
                }
                startDate = Date()
                startLoop()
            }
            
        case .countdown:
            // stop our local countdown ticker
                    ticker?.cancel()

                    // broadcast a “pause” to the children so they also stop
                    if syncSettings.role == .parent && syncSettings.isEnabled {
                        let pauseMsg = TimerMessage(
                            action: .pause,
                            timestamp: Date().timeIntervalSince1970,
                            phase: "paused",
                            remaining: countdownRemaining,
                            stopEvents: rawStops.map {
                              StopEventWire(eventTime: $0.eventTime, duration: $0.duration)
                            }
                        )
                        syncSettings.broadcastToChildren(pauseMsg)
                    }

                    // now do your normal pause/reset logic
            if settings.countdownResetMode == .manual {
                  // true “pause” style
                  phase = .paused
                  // broadcast the pause so kids stop where they are
                  sendPause(to: countdownRemaining)
                } else {
                  // failsafe off: reset to full duration
                  let baseDigits = timeToDigits(countdownDuration)
                  countdownDigits    = baseDigits
                  countdownRemaining = digitsToTime(baseDigits)
                  phase              = .idle
                  // tell all children “you’re paused at the full-length value”
                  sendPause(to: countdownRemaining)
                }
            
        case .running:
            ticker?.cancel()
                    phase = .paused
                    // you already broadcast here:
                    if syncSettings.role == .parent && syncSettings.isEnabled {
                        let m = TimerMessage(
                            action: .pause,
                            timestamp: Date().timeIntervalSince1970,
                            phase: "paused",
                            remaining: elapsed,
                            stopEvents: rawStops.map {
                              StopEventWire(eventTime: $0.eventTime, duration: $0.duration)
                            }
                        )
                        syncSettings.broadcastToChildren(m)
                    }
            
        case .paused:
            if countdownRemaining > 0 {
                phase = .countdown
                startLoop()
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "countdown",
                        remaining: countdownRemaining,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    syncSettings.broadcastToChildren(m)
                }
            } else {
                phase = .running
                startDate = Date().addingTimeInterval(-elapsed)
                startLoop()
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    let m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "running",
                        remaining: elapsed,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    syncSettings.broadcastToChildren(m)
                }
                
            }
            
        }
        
    }
    // helper to fold your broadcast code
    private func sendPause(to remaining: TimeInterval) {
      guard syncSettings.role == .parent && syncSettings.isEnabled else { return }
      let msg = TimerMessage(
        action: .pause,
        timestamp: Date().timeIntervalSince1970,
        phase: "paused",
        remaining: remaining,
        stopEvents: rawStops.map {
          StopEventWire(eventTime: $0.eventTime, duration: $0.duration)
        }
      )
      syncSettings.broadcastToChildren(msg)
    }
    // MARK: – Reset everything (called by your “Reset” button)
    private func resetAll() {
        guard phase == .idle || phase == .paused else { return }
        ticker?.cancel()
        phase = .idle
        
        // Broadcast reset to children if we’re the parent
        if syncSettings.role == .parent && syncSettings.isEnabled {
            let m = TimerMessage(
                action: .reset,
                timestamp: Date().timeIntervalSince1970,
                phase: "idle",
                remaining: 0,
                stopEvents: []
            )
            syncSettings.broadcastToChildren(m)
        }
        
        // Clear all local state
        countdownDigits.removeAll()
        countdownDuration = 0
        countdownRemaining = 0
        elapsed = 0
        startDate = nil
        
        rawStops.removeAll()
        events.removeAll()
        stopActive = false
        stopRemaining = 0
        stopDigits.removeAll()
        stopStep = 0
        
        lightHaptic()
    }
    
    //──────────────────── apply incoming TimerMessage ────────────────────
    // MARK: – Handle messages from the parent
    func applyIncomingTimerMessage(_ msg: TimerMessage) {
        guard syncSettings.role == .child else { return }
        
        // Rebuild stop‐events
        rawStops = msg.stopEvents.map {
            StopEvent(eventTime: $0.eventTime, duration: $0.duration)
        }
        events = rawStops.map(Event.stop)
        syncSettings.stopWires = msg.stopEvents
        
        switch msg.action {
        case .start:
            if msg.phase == "countdown" {
                countdownRemaining = msg.remaining
                phase = .countdown
                startLoop()
            } else {
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
            // Optionally handle newly‐added events here
            break
        }
    }
}
extension Color {
    /// A human‐readable name for a handful of known colors.
    var accessibilityName: String {
        switch self {
        case .red:    return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .purple: return "Purple"
        // …add any others you commonly use…
        default:      return "gray"
        }
    }
}

// ── 1) New Subview for Flash-Color Swatches ───────────────────────
struct FlashColorPicker: View {
    @Binding var selectedColor: Color
    @Binding var showCustom: Bool
    let presets: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flash Color")
                .font(.custom("Roboto-Regular", size: 16))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12.5) {
                    ForEach(presets, id: \.self) { color in
                        let colorName = color.accessibilityName
                        let isSelected = (color == selectedColor)
                        Button {
                            selectedColor = color
                            lightHaptic()
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.primary : Color.clear,
                                                lineWidth: 2.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, maxHeight: 32)
                        .accessibilityLabel(Text(color.accessibilityName))
                        .accessibilityHint(Text("Selects \(color.accessibilityName) flash color"))
                    }

                    ZStack {
                                        // 1) Background circle: gray until a custom color is picked
                                        Circle()
                                            .fill(selectedColor == .clear ? Color.gray : selectedColor)
                                            .frame(width: 32, height: 32)

                                        // 2) Palette icon
                                        Image(systemName: "paintpalette")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                        // ↓———— VoiceOver label/hint
                                            .accessibilityLabel("Custom flash color")
                                            .accessibilityHint("Double-tap to choose any color from the system picker")


                                        // 3) Invisible ColorPicker to catch taps
                                        ColorPicker("", selection: $selectedColor, supportsOpacity: true)
                                            .labelsHidden()
                                            .frame(width: 32, height: 32)
                                            .scaleEffect(1.2)
                                            .opacity(0.1125)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: 32)
                                    .padding(.vertical, 2)
                                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
            .scrollDisabled(true)
            .sheet(isPresented: $showCustom) {
                NavigationView {
                    ColorPicker("Pick Custom Flash Color", selection: $selectedColor)
                        .padding()
                        .navigationTitle("Custom Color")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showCustom = false }
                            }
                        }
                }
            }
        }
    }
}
// 0) LOOK & FEEL
struct AppearancePage: View {
    @EnvironmentObject private var appSettings: AppSettings
    // 1) All of your static presets, including the grey one last:
        private let flashPresets: [Color] = [
            .red, .orange, .yellow, .green, .blue, .purple,
            Color(red: 199/255, green: 199/255, blue: 204/255)  // the “grey” preset
        ]
    // 2) Detect “Max‐sized” phones by width >= 414pt
        private var isMaxPhone: Bool {
            UIScreen.main.bounds.width >= 414
        }
    let presets: [Color]
    // New: which sub-tab is active?
        enum Tab: String, CaseIterable, Identifiable, SegmentedOption {
          case theme = "Theme"
          case ui    = "UI"
          var id: String { rawValue }
          var icon: String {
            switch self {
            case .theme: return "paintpalette.fill"
            case .ui:    return "rectangle.on.rectangle"
            }
          }
          var label: String { rawValue }
        }
        @State private var selectedTab: Tab = .theme
    
    var body: some View {
        VStack(spacing: 16) {
                  // 1) Pill picker between Theme / UI
                  SegmentedControlPicker(selection: $selectedTab)
                    .frame(maxWidth: .infinity)      // ← let it grow to fill the content area
                    .padding(.horizontal, 12)         // ← pull it 8pt in from each edge (instead of 12)
                    .padding(.vertical, 0)
  

                  // 2) Content for each tab
            Group {
                            if selectedTab == .theme {
                                VStack(alignment: .leading, spacing: 12) {
                                    FlashColorPicker(
                                      selectedColor: $appSettings.flashColor,
                                      showCustom: .constant(false),
                                      presets: isMaxPhone
                                      ? flashPresets
                                      : Array(flashPresets.dropLast())
                                      )
                                    FlashStylePicker(
                                      selectedStyle: $appSettings.flashStyle,
                                      flashColor:    $appSettings.flashColor
                                    )
                                    ThemePicker(
                                      selected:    $appSettings.appTheme,
                                      customColor: $appSettings.customThemeOverlayColor
                                    )
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    // ── Low-Power Mode ─────────────────
                                    Toggle("Low-Power Mode (buggy)", isOn: $appSettings.lowPowerMode)
                                        .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                                    Text("Strips out all images, materials, shadows, and custom colors to minimize display power; layout is buggy, no performance issues.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)


                                    // ── High-Contrast Sync Indicator ────
                                    Toggle("High-Contrast Sync Indicator", isOn: $appSettings.highContrastSyncIndicator)
                                        .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                                    Text("Replaces every sync-lamp circle with a bold ✓ or ✕ icon for maximum contrast.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 12)
             }
         }


// 1) TIMER BEHAVIOR
struct TimerBehaviorPage: View {
  @EnvironmentObject private var appSettings: AppSettings

  // one state to choose which subpage to show:
  @State private var selectedTab: FeedbackType = .feedback

  var body: some View {
    VStack(spacing: 20) {
      // 1) Top‐level tab strip
      SegmentedControlPicker(selection: $selectedTab)
            .frame(maxWidth: .infinity)      // ← let it grow to fill the content area
            .padding(.horizontal, -8)         // ← pull it 8pt in from each edge (instead of 12)
            .padding(.vertical, 0)

      // 2) Switch between the two modes
      Group {
        switch selectedTab {
        case .feedback:
          feedbackContent
        case .safety:
          safetyContent
        }
      }
      .animation(.easeInOut, value: selectedTab)

      Spacer(minLength: 0)
    }
    .padding(.top, 12)
    .padding(.horizontal, 20)
    .scrollDisabled(true)  // keep everything locked to your card’s fixed height
  }

    /// A bespoke SwiftUI slider with uniform 50 ms tick marks, snapping to a custom set of values,
    /// and fine-grain control when dragging vertically away from the track.

    struct CustomStepSlider: View {
        @Binding var value: Double
        let steps: [Double]
        let range: ClosedRange<Double>
        let thresholdVertical: CGFloat        // vertical drag threshold for fine control
        let thumbColor: Color                 // color of the thumb and label border

        // drawing constants
        private let uniformStep: Double = 50  // millisecond spacing for ticks
        private let trackHeight: CGFloat = 4
        private let thumbSize: CGFloat   = 24
        private let inset: CGFloat       = 8
        @State private var lastStepIndex: Int?
        @State private var selectionFeedback = UISelectionFeedbackGenerator()

        var body: some View {
            GeometryReader { geo in
                let W           = geo.size.width
                let totalTrackW = W - inset * 2
                let minVal      = range.lowerBound
                let maxVal      = range.upperBound
                let frac        = (value - minVal) / (maxVal - minVal)
                let knobX       = inset + frac * totalTrackW
                let tickCount   = Int((maxVal - minVal) / uniformStep)

                ZStack(alignment: .leading) {
                    // 1) Track
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: trackHeight)
                        .padding(.horizontal, inset)

                    // 2) Uniform tick marks every `uniformStep` ms
                    HStack(spacing: 0) {
                        ForEach(0...tickCount, id: \.self) { idx in
                            Rectangle()
                                .frame(
                                    width: 1,
                                    height: (idx == 0 || idx == tickCount)
                                        ? trackHeight * 2
                                        : trackHeight * 1.5
                                )
                                .foregroundColor(.secondary.opacity(0.6))
                            if idx < tickCount {
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, inset)

                    // 3) Thumb
                    Circle()
                        .fill(thumbColor)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .offset(x: knobX - thumbSize / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    // calculate raw value
                                    let rawX      = drag.location.x - inset
                                    let clampedX  = min(max(0, rawX), totalTrackW)
                                    let rawVal    = minVal + Double(clampedX / totalTrackW) * (maxVal - minVal)
                                    let distanceV = abs(drag.location.y - thumbSize / 2)

                                    let newVal: Double
                                    if distanceV <= thresholdVertical {
                                        // discrete snap to nearest step
                                        let nearest = steps.min(by: { abs($0 - rawVal) < abs($1 - rawVal) })!
                                        newVal = nearest
                                        let idx = steps.firstIndex(of: nearest)!
                                        if idx != lastStepIndex {
                                            lastStepIndex = idx
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                    } else {
                                        // continuous fine-grain control with granular haptic
                                        selectionFeedback.selectionChanged()
                                        let continuousRawVal = rawVal
                                        newVal = min(max(minVal, continuousRawVal), maxVal)
                                    }
                                    value = min(max(minVal, newVal), maxVal)
                                }
                                .onEnded { _ in
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                        )
                }
            }
            .frame(height: thumbSize)
        }
    }







    @ViewBuilder
    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Vibrate on Flash", isOn: $appSettings.vibrateOnFlash)
                .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                .font(.custom("Roboto-Regular", size: 16))
                .onChange(of: appSettings.vibrateOnFlash) { _ in lightHaptic() }
            
            // MARK: — Flash Length Picker (ValueSlider on iOS 17, fallback prior) —
            Section {
                VStack(spacing: 8) {
                    // 1) Title + value badge inline
                    HStack {
                        Text("Flash Length")
                            .font(.custom("Roboto-Regular", size: 16))
                        Spacer()
                        Text("\(appSettings.flashDurationOption) ms")
                            .font(.custom("Roboto-Light", size: 14))
                            .bold()
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(appSettings.flashColor.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(appSettings.flashColor)
                    }
                    
                    // 2) Slider below, full-width
                    CustomStepSlider(
                        value: Binding {
                            Double(appSettings.flashDurationOption)
                        } set: { newVal in
                            appSettings.flashDurationOption = Int(newVal)
                        },
                        steps: [50,100,150,250,500,750,1000].map(Double.init),
                        range: 50...1000,
                        thresholdVertical: 100,
                        thumbColor: appSettings.flashColor
                    )
                    .frame(height: 44)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                
                // explanatory footnote
                Text("Timer flashes at 00.00. Shorter flashes feel snappier; longer flashes are easier to notice.")
                    .font(.custom("Roboto-Light", size: 16))
                    .padding(.bottom, 8)
                    .foregroundColor(.secondary)
            }
        }
    }
            
  private var safetyContent: some View {
      VStack(alignment: .leading, spacing: 16) {
          Toggle("Countdown Lock",
                 isOn: Binding(
                    get: { appSettings.countdownResetMode == .manual },
                    set: { appSettings.countdownResetMode = $0 ? .manual : .off }
                 )
          )
          .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
          // subtitle for Countdown Lock
          Text("Prevents the countdown from resetting on stop.")
              .font(.custom("Roboto-Light", size: 12))
              .foregroundColor(.secondary)
              .padding(.leading, 0)
              .lineLimit(1)
          
          Menu {
              ForEach(ResetConfirmationMode.allCases) { style in
                  Button(style.rawValue) { appSettings.resetConfirmationMode = style }
              }
          } label: {
              settingRow(title: "Reset Lock",
                         value: appSettings.resetConfirmationMode.rawValue,
                         icon: "arrow.counterclockwise.circle")
              .tint(appSettings.flashColor)
          }
          // subtitle for Reset Lock
          Text("Requires confirmation before resetting the timer.")
              .font(.custom("Roboto-Light", size: 12))
              .foregroundColor(.secondary)
              .padding(.leading, 0)
              .lineLimit(1)
      
        

      Menu {
        ForEach(ResetConfirmationMode.allCases) { style in
          Button(style.rawValue) { appSettings.stopConfirmationMode = style }
        }
      } label: {
        settingRow(title: "Stop Lock",
                   value: appSettings.stopConfirmationMode.rawValue,
                   icon: "pause.circle")
        .tint(appSettings.flashColor)
      }
    Text("Requires confirmation before stopping the timer.")
            .font(.custom("Roboto-Light", size: 12))
            .foregroundColor(.secondary)
            .padding(.leading, 0)
            .lineLimit(1)
    }
  }

  private func settingRow(title: String, value: String, icon: String) -> some View {
    HStack {
      Label(title, systemImage: icon)
      Spacer()
      Text(value).foregroundColor(.secondary)
      Image(systemName: "chevron.down")
            .font(.system(size: 14, weight: .thin))
            .foregroundColor(.secondary)
    }
    .contentShape(Rectangle())
    .font(.custom("Roboto-Regular", size: 16))
    .padding(.vertical, 6)
  }
}




struct SegmentedControlPicker<Option: SegmentedOption>: View {
    @Binding var selection: Option
    var shadowOpacity: Double = 0.08
    @Namespace private var slide
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            segments
        }
        .padding(0)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(shadowOpacity), radius: 4, x: 0, y: 2)
    }

    private var segments: some View {
        // wrap in Array() to satisfy RandomAccessCollection
        ForEach(Array(Option.allCases), id: \.id) { option in
            Button {
                withAnimation(.easeOut(duration: 0.4)) {
                    selection = option
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: option.icon)
                    Text(option.label)
                        .font(.custom("Roboto-SemiBold", size: 16))
                }
                .foregroundColor(selection.id == option.id ? .white : .primary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(activeBackground(for: option))
                .accessibilityLabel(option.label)
                .accessibilityHint("Selects \(option.label) tab")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func activeBackground(for option: Option) -> some View {
        if selection.id == option.id {
            RoundedRectangle(cornerRadius: 12)
                .fill(appSettings.flashColor)
                .matchedGeometryEffect(id: "slide", in: slide)
        }
    }
}


struct ConnectionPage: View {
    @EnvironmentObject private var syncSettings: SyncSettings
    @EnvironmentObject private var settings: AppSettings
    @Binding var editingTarget: EditableField?
    @Binding var inputText: String
    @Binding var isEnteringField: Bool
    @Binding var showBadPortError: Bool
    
    @State private var portGenerated = false
    @State private var showDeviceIP = false
    @State private var placeholderTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var ipBlink = false
    @State private var portBlink = false
    @State private var showSyncErrorAlert = false
    @State private var syncErrorMessage   = ""
    
    @State private var isWifiAvailable = false
    @State private var showNoWifiAlert = false
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    
    
    private func generateEphemeralPort() -> UInt16 {
        UInt16.random(in: 49153...65534)
    }
    
    private func cancelEntry() {
        editingTarget = nil
        inputText = ""
        isEnteringField = false
    }
    
    private var isMax: Bool {
        UIScreen.main.bounds.height >= 930
    }
    
    /// Friendly description for each method
    private var connectionDescription: String {
        switch syncSettings.connectionMethod {
        case .network:
            return "High-precision sync. Use your IP + random port for parent or input ports for child."
        case .bluetooth:
            return "Lower-precision, peer-to-peer sync over Bluetooth using PDF417 codes."
        case .bonjour:
            return "Zero-config, automatic discovery over your local network."
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Content area ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: -24) {
                SegmentedControlPicker(selection: $syncSettings.connectionMethod,
                                       shadowOpacity: 0.08)
                .onChange(of: syncSettings.connectionMethod) { newMethod in
                        // Warm up BLE stack immediately on first tap into Bluetooth mode
                    // Warm up BLE on a background queue so the pill-picker stays instant
                            if newMethod == .bluetooth {
                                DispatchQueue.global(qos: .utility).async {
                                    let bt = syncSettings.bleDriftManager
                                    bt.start()
                                    usleep(100_000)
                                    bt.stop()
                                }
                            }                    // ① clear any in-flight numpad entry
                        cancelEntry()
                
                        // ② if we were mid-sync, shut everything down
                        if syncSettings.isEnabled {
                            switch syncSettings.connectionMethod {
                            case .network, .bluetooth:
                                if syncSettings.role == .parent { syncSettings.stopParent() }
                                else                            { syncSettings.stopChild() }
                
                            case .bonjour:
                                syncSettings.bonjourManager.stopAdvertising()
                                syncSettings.bonjourManager.stopBrowsing()
                                if syncSettings.role == .parent { syncSettings.stopParent() }
                                else                            { syncSettings.stopChild() }
                            }
                            syncSettings.isEnabled = false
                        }
                    }
                .frame(maxWidth: .infinity)      // ← let it grow to fill the content area
                .padding(.horizontal, -8)         // ← pull it 8pt in from each edge (instead of 12)
                .padding(.vertical, -8)
                .accessibilityLabel(syncSettings.connectionMethod.rawValue)
                .accessibilityHint("Selects \(syncSettings.connectionMethod.rawValue) sync mode")
                // hide description once we’re in a live Bonjour lobby
                if !(syncSettings.connectionMethod == .bonjour && syncSettings.isEnabled) {
                    Text(connectionDescription)
                        .font(.custom("Roboto-Light", size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 40)
                } else {
                    // live lobby header
                    HStack {
                        Text("Lobby Code: \(syncSettings.currentCode)")
                            .font(.headline)
                        Spacer()
                        Button {
                            syncSettings.parentLockEnabled.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: syncSettings.parentLockEnabled ? "lock.fill" : "lock.open")
                                Text(syncSettings.parentLockEnabled ? "" : "")
                            }
                        }
                        .buttonStyle(.automatic)
                        .foregroundColor(
                            (settings.appTheme == .dark)
                            ? .white
                            : .black
                        )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 40)
                }
                
                switch syncSettings.connectionMethod {
                case .network:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your Port:")
                            Spacer()
                            Button {
                                let newPort = String(generateEphemeralPort())
                                syncSettings.listenPort = newPort
                                portGenerated = true
                            } label: {
                                Text(portGenerated
                                     ? syncSettings.listenPort
                                     : "Tap to generate")
                                .font(.custom("Roboto-Regular", size: 16))
                                .foregroundColor(portGenerated ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Generate port")
                            .accessibilityHint("Gives you a random ephemeral port for listening")
                        }
                        HStack {
                              Text("Your IP:")
                              Spacer()
                              Button {
                                if isWifiAvailable {
                                  withAnimation { showDeviceIP.toggle() }
                                } else {
                                  showNoWifiAlert = true
                                }
                              } label: {
                                Text(showDeviceIP
                                     ? getLocalIPAddress() ?? "Unknown"
                                     : (isWifiAvailable ? "Tap to reveal" : "No Wi-Fi"))
                                  .font(.custom("Roboto-Regular", size: 16))
                                  .foregroundColor(
                                    isWifiAvailable
                                      ? (showDeviceIP ? .primary : .secondary)
                                      : .secondary
                                  )
                              }
                              .buttonStyle(.plain)
                              .accessibilityLabel("Reveal device IP")
                              .accessibilityHint("Double-tap to show your local Wi-Fi IP address")
                              .disabled(!isWifiAvailable)
                              .alert("No Wi-Fi Connection",
                                     isPresented: $showNoWifiAlert) {
                                Button("OK") { }
                              } message: {
                                Text("Please join a Wi-Fi network before revealing your IP address.")
                              }
                            }
                        // ── Parent IP row ─────────────────────────────────────
                        HStack {
                            Text("Parent IP:")
                            Spacer()
                            // decide what to show: either the user’s input or the stored IP
                            let ipText: String = {
                                if editingTarget == .ip {
                                    return inputText.isEmpty ? "Tap to enter" : inputText
                                } else {
                                    return syncSettings.peerIP.isEmpty ? "Tap to enter" : syncSettings.peerIP
                                }
                            }()
                            
                            Text(ipText)
                                .font(.custom("Roboto-Regular", size: 16))
                                .foregroundColor(
                                    // blink placeholder only while editing & empty
                                    editingTarget == .ip && inputText.isEmpty
                                    ? (ipBlink ? .primary : .clear)
                                    : (editingTarget == .ip
                                       ? .primary
                                       : (syncSettings.peerIP.isEmpty ? .secondary : .primary))
                                )
                                .onTapGesture {
                                    // enter edit-mode
                                    syncSettings.peerIP = ""
                                    inputText           = ""
                                    editingTarget       = .ip
                                    isEnteringField     = true
                                }
                        }
                        .accessibilityLabel("Parent IP address")
                        .accessibilityHint("Double-tap to enter the parent device’s IP")
                        
                        // ── Parent Port row ───────────────────────────────────
                        HStack {
                            Text("Parent Port:")
                            Spacer()
                            let portText: String = {
                                if editingTarget == .port {
                                    if showBadPortError {
                                        return "Invalid port (49153-65534)"
                                    }
                                    return inputText.isEmpty ? "Tap to enter" : inputText
                                }
                                return syncSettings.peerPort.isEmpty ? "Tap to enter" : syncSettings.peerPort
                            }()
                            
                            Text(portText)
                                .font(.custom("Roboto-Regular", size: 16))
                                .foregroundColor(
                                    // 1) error flash: black/gray
                                    editingTarget == .port && showBadPortError
                                        ? (portBlink ? .primary : .secondary)
                                    // 2) placeholder‐flash pre‐digit
                                    : (editingTarget == .port && inputText.isEmpty)
                                        ? (portBlink ? .primary : .clear)
                                    // 3) normal editing / committed
                                    : (editingTarget == .port
                                        ? .primary
                                        : (syncSettings.peerPort.isEmpty ? .secondary : .primary))
                                )
                                .onTapGesture {
                                    syncSettings.peerPort = ""
                                    inputText             = ""
                                    editingTarget         = .port
                                    isEnteringField       = true
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    
                case .bluetooth:
                    BLEPairingView()
                        .environmentObject(syncSettings)
                    
                case .bonjour:
                    if !syncSettings.isEnabled {
                            // detect narrow screens (< iPhone12 width)
                            let isCompact = UIScreen.main.bounds.width < 390                                            // inline lobby‐code editor
                                            HStack(spacing: isCompact ? 8 : 18) {
                                                let displayCode = editingTarget == .lobbyCode
                                                    ? (inputText.isEmpty ? "—" : inputText)
                                                    : (syncSettings.currentCode.isEmpty ? "—" : syncSettings.currentCode)
                    
                                                Text("LOBBY")
                                                    .font(.custom("Roboto-SemiBold", size: 24))
                                                    .foregroundColor(
                                                        (settings.appTheme == .dark)
                                                        ? .white
                                                        : .black
                                                    )
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                                    .allowsTightening(true)
                                                Text(displayCode)
                                                    .font(.custom("Roboto-Regular", size: 24))
                                                    .foregroundColor(
                                                        (settings.appTheme == .dark)
                                                        ? .white
                                                        : .black
                                                    )
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                                    .allowsTightening(true)
                    
                                                Spacer()
                    
                                                Button("NEW") {
                                                    syncSettings.generateCode()
                                                }
                                                .font(.custom("Roboto-SemiBold", size: 24))
                                                .foregroundColor(
                                                    (settings.appTheme == .dark)
                                                    ? .white
                                                    : .black
                                                )
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                                .allowsTightening(true)
                                                .buttonStyle(.plain)
                    
                                                Button("EDIT") {
                                                    editingTarget   = .lobbyCode
                                                    inputText       = ""
                                                    isEnteringField = true
                                                }
                                                .font(.custom("Roboto-Regular", size: 24))
                                                .foregroundColor(
                                                    (settings.appTheme == .dark)
                                                    ? .white
                                                    : .black
                                                )
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                                .allowsTightening(true)
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 8)
                        // ── explainer steps ────────────────────────────────
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To start a lobby:")
                                .font(.custom("Roboto-Regular", size: 14))
                                .foregroundColor(.secondary)
                             Text("1. Tap NEW to generate a code.")
                                .font(.custom("Roboto-Light", size: 12))
                                .foregroundColor(.secondary)
                            Text("2. Share this code with others.")
                                .font(.custom("Roboto-Light", size: 12))
                                .foregroundColor(.secondary)
                            Text("3. Tap SYNC to begin syncing.")
                                .font(.custom("Roboto-Light", size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 28)
                    } else {
                    // show live lobby (fixed height)
                        // show live lobby (fixed height)
                                                VStack {
                                                    LobbyView()
                                                        .environmentObject(syncSettings)
                                                }
                        // full width, fixed 140-pt height
                        .frame(maxWidth: .infinity, alignment: .top)
                        .frame(height: 140)                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.vertical, 4)
                    }
                }
            }
            .contentShape(Rectangle())                     // make the whole area tappable
            .onTapGesture {
                guard editingTarget != nil else { return }   // only when editing
                cancelEntry()
            }
            Spacer(minLength: 0)
            
                // ── Sync / Stop + Lamp row (always pinned at bottom) ─────────
                HStack(spacing: 8) {
                    // ── Role toggle ──
                    Button {
                        let newRole: SyncSettings.Role = (syncSettings.role == .parent ? .child : .parent)
                        syncSettings.role = newRole
                    } label: {
                        HStack(spacing: 4) {
                            Text("CHILD")
                                .font(.custom("Roboto-SemiBold", size: 24))
                                .foregroundColor(syncSettings.role == .child ? .primary : .secondary)
                            Text("/")
                                .font(.custom("Roboto-SemiBold", size: 24))
                                .foregroundColor(.secondary)
                            Text("PARENT")
                                .font(.custom("Roboto-SemiBold", size: 24))
                                .foregroundColor(syncSettings.role == .parent ? .primary : .secondary)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()

                    // ── Sync/Stop button ──
                    Button {
                        toggleSync()
                    } label: {
                        Text(syncSettings.isEnabled ? "STOP" : "SYNC")
                            .font(.custom("Roboto-SemiBold", size: 24))
                            .foregroundColor((settings.appTheme == .dark) ? .white : .black)
                            .fixedSize()   // hug text width
                    }
                    .buttonStyle(.plain)

                    // ── Lamp ──
                    if settings.highContrastSyncIndicator {
                        Image(systemName:
                                (syncSettings.isEnabled && syncSettings.isEstablished)
                              ? "checkmark.circle.fill"
                              : "xmark.octagon.fill"
                        )
                        .foregroundColor(
                            (syncSettings.isEnabled && syncSettings.isEstablished) ? .green : .red
                        )
                        .frame(width: 20, height: 20)
                    } else {
                        Circle()
                            .fill((syncSettings.isEnabled && syncSettings.isEstablished) ? .green : .red)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)   // <<< fill width, align left
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        .onAppear {
              wifiMonitor.pathUpdateHandler = { path in
                DispatchQueue.main.async {
                  isWifiAvailable = (path.status == .satisfied)
                }
              }
              wifiMonitor.start(queue: .global(qos: .background))
            }
            .onDisappear {
              wifiMonitor.cancel()
            }
        
        // ── placeholder blinking logic ─────────────────────────────────
        .onReceive(placeholderTimer) { _ in
            // only toggle while truly editing & empty
            if editingTarget == .ip && inputText.isEmpty {
                ipBlink.toggle()
            } else {
                ipBlink = false
            }
            if editingTarget == .port && (inputText.isEmpty || showBadPortError) {
                portBlink.toggle()
            } else {
                portBlink = false
            }
        }
        .onChange(of: inputText) { newValue in
            // 1) Parent-port: once 5 digits are in, auto-submit
            if editingTarget == .port {
                        // clear any previous error
                        showBadPortError = false
                        // once 5 digits are entered, validate
                        if newValue.count == 5 {
                            if let port = UInt16(newValue),
                               (49153...65534).contains(port)
                            {
                                // valid → commit
                                syncSettings.peerPort   = newValue
                                editingTarget           = nil
                                isEnteringField         = false
                            } else {
                                // invalid → show error
                                showBadPortError = true
                            }
                            return
                        }
                    }
                    // 2) Lobby code: existing 5-digit auto-commit
                    guard editingTarget == .lobbyCode else { return }
                    if newValue.count == 5 {
                        syncSettings.currentCode = newValue
                        editingTarget            = nil
                        isEnteringField          = false
                    }
                }
        .alert("Cannot Start Sync",
               isPresented: $showSyncErrorAlert) {
          Button("OK", role: .cancel) { }
        } message: {
          Text(syncErrorMessage)
        }
    }
    
    
    // MARK: – Sections
    
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your Port:")
                Spacer()
                Button {
                    let newPort = String(generateEphemeralPort())
                    syncSettings.listenPort = newPort
                    portGenerated = true
                } label: {
                    Text(portGenerated
                         ? syncSettings.listenPort
                         : "Tap to generate")
                    .font(.custom("Roboto-Regular", size: 16))
                    .foregroundColor(portGenerated ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                Text("Your IP:")
                Spacer()
                Button {
                    withAnimation { showDeviceIP.toggle() }
                } label: {
                    Text(showDeviceIP
                         ? getLocalIPAddress() ?? "Unknown"
                         : "Tap to reveal")
                    .font(.custom("Roboto-Regular", size: 16))
                    .foregroundColor(showDeviceIP ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider().opacity(0.5)
            
            HStack {
                Text("Parent IP:")
                Spacer()
                Text(editingTarget == .ip
                     ? inputText
                     : (syncSettings.peerIP.isEmpty ? "Tap to enter" : syncSettings.peerIP))
                .font(.custom("Roboto-Regular", size: 16))
                .foregroundColor(editingTarget == .ip
                                 ? .primary
                                 : (syncSettings.peerIP.isEmpty ? .secondary : .primary))
                .onTapGesture {
                    syncSettings.peerIP = ""
                    inputText = ""
                    editingTarget   = .ip
                    isEnteringField = true
                }
            }
            
            HStack {
                Text("Parent Port:")
                Spacer()
                Text(editingTarget == .port
                     ? inputText
                     : (syncSettings.peerPort.isEmpty ? "Tap to enter" : syncSettings.peerPort))
                .font(.custom("Roboto-Regular", size: 16))
                .foregroundColor(editingTarget == .port
                                 ? .primary
                                 : (syncSettings.peerPort.isEmpty ? .secondary : .primary))
                .onTapGesture {
                    syncSettings.peerPort = ""
                    inputText             = ""
                    editingTarget         = .port
                    isEnteringField       = true
                }
            }
        }
    }
    
    private var bluetoothSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("")
                .foregroundColor(.secondary)
        }
    }
    
    private var bonjourSection: some View {
        LobbyView()
            .environmentObject(syncSettings)
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
    }
    
    private var roleToggle: some View {
        Button { toggleSync() } label: { /* simplified */ Text("CHILD/PARENT") }
    }
    
    private var syncButton: some View {
        Button { toggleSync() } label: { Text(syncSettings.isEnabled ? "STOP" : "SYNC") }
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(syncSettings.isEnabled && syncSettings.isEstablished ? .green : .red)
            .frame(width: 20, height: 20)
        
    }
    
    
    // MARK: – Helpers
    
    private var lampColor: Color {
        (syncSettings.isEnabled && syncSettings.isEstablished)
        ? .green
        : .red
    }
    
    // In ConnectionPage:
    private func toggleSync() {
        if syncSettings.isEnabled {
            // — STOP SYNC —
            switch syncSettings.connectionMethod {
            case .network:
                if syncSettings.role == .parent { syncSettings.stopParent() }
                else                             { syncSettings.stopChild() }
                
            case .bluetooth:
                if syncSettings.role == .parent { syncSettings.stopParent() }
                else                             { syncSettings.stopChild() }
                
            case .bonjour:
                syncSettings.bonjourManager.stopAdvertising()
                syncSettings.bonjourManager.stopBrowsing()
            }
            syncSettings.isEnabled = false
            
        } else {
            // — PRE-CHECK RADIOS —
            switch syncSettings.connectionMethod {
            case .network, .bonjour:
                let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
                let sem = DispatchSemaphore(value: 0)
                monitor.pathUpdateHandler = { _ in sem.signal() }
                monitor.start(queue: .global(qos: .background))
                sem.wait()
                let path = monitor.currentPath
                monitor.cancel()
                guard path.status == .satisfied else {
                    syncErrorMessage   = "Wi-Fi is off or not connected.\nPlease enable Wi-Fi to sync."
                    showSyncErrorAlert = true
                    return
                }
                
            case .bluetooth:
                  let btState = syncSettings.bleDriftManager.central.state
                  guard btState == .poweredOn else {
                    syncErrorMessage   = "Bluetooth is off.\nPlease enable Bluetooth to sync."
                    showSyncErrorAlert = true
                    return
                  }
                
            }
            
            // — START SYNC — (existing logic unchanged)
            switch syncSettings.connectionMethod {
            case .network:
                if syncSettings.role == .parent { syncSettings.startParent() }
                else                             { syncSettings.startChild() }
                
            case .bluetooth:
                if syncSettings.role == .parent { syncSettings.startParent() }
                else                             { syncSettings.startChild() }
                
            case .bonjour:
                if syncSettings.role == .parent {
                    syncSettings.bonjourManager.startAdvertising()
                } else {
                    syncSettings.bonjourManager.startBrowsing()
                }
            }
            syncSettings.isEnabled = true
        }
    }
}



 struct NicknameGenerator {
    static let adjectives = ["Sunny","Brave","Swift","Clever","Mighty","Calm","Witty","Bold","Vague","Pushy","Vulgar", "Mellow", "Wise", "Brainy", "Sleepy","Royal","Proud","Zany","Weary,","Good","Strange","Up"]
    static let animals    = ["Fox","Hawk","Otter","Wolf","Falcon","Bear","Dolphin","Lynx","Cat","Aardvark","Capybara","Tardigrade","Horse","Albatross","Ant","Alpaca","Llama","Cheetah","Chinchilla","Hare","Mantis","Lark","Narwhal","Partridge","Penguin","Toucan","Zebra"]

    static func make() -> String {
        let adj = adjectives.randomElement()!
        let ani = animals.randomElement()!
        return "\(adj) \(ani)"
    }
}
struct LobbyView: View {
    @EnvironmentObject private var syncSettings: SyncSettings

    // ── New drag/offset state
    @State private var dragOffset: CGFloat = 0
    @State private var showMessage = false
    @State private var contentOffsetY: CGFloat = 0
    @State private var messageOffsetY: CGFloat = -80
    @State private var bounce = false

    private let pullThreshold: CGFloat = 60
    private let messageHeight: CGFloat = 80

    private var parents: [SyncSettings.Peer] {
        var list = syncSettings.peers.filter { $0.role == .parent }
        if syncSettings.role == .parent {
            let me = SyncSettings.Peer(
                id: syncSettings.localPeerID,
                name: syncSettings.localNickname,
                role: .parent,
                joinTs: 0,
                signalStrength: 3
            )
            if !list.contains(where: { $0.id == me.id }) {
                list.insert(me, at: 0)
            }
        }
        return list
    }

    private var children: [SyncSettings.Peer] {
        var list = syncSettings.peers.filter { $0.role == .child }
        if syncSettings.role == .child {
            let me = SyncSettings.Peer(
                id: syncSettings.localPeerID,
                name: syncSettings.localNickname,
                role: .child,
                joinTs: 0,
                signalStrength: 3
            )
            if !list.contains(where: { $0.id == me.id }) {
                list.insert(me, at: 0)
            }
        }
        return list
    }

    private func barsIcon(for strength: Int) -> String {
        switch strength {
        case 3: return "wifi"
        case 2: return "wifi.wave.2"
        case 1: return "wifi.exclamationmark"
        default: return "wifi.slash"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── Your peer‐list, now draggable
            HStack(spacing: 16) {
                if syncSettings.connectionMethod == .bluetooth {
                    bluetoothColumn
                } else {
                    parentsColumn
                    childrenColumn
                }
            }
            .padding()
            .offset(y: contentOffsetY + dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { g in
                        guard syncSettings.peers.isEmpty, !showMessage else { return }
                        let y = max(g.translation.height, 0)
                        dragOffset = y
                        // reveal message proportionally
                        messageOffsetY = min(-messageHeight + y, 0)
                    }
                    .onEnded { g in
                        guard syncSettings.peers.isEmpty, !showMessage else {
                            dragOffset = 0
                            return
                        }
                        if g.translation.height > pullThreshold {
                            triggerStickyMessage()
                        } else {
                            // snap back
                            withAnimation(.easeOut) {
                                dragOffset = 0
                                messageOffsetY = -messageHeight
                            }
                        }
                    }
            )

            if showMessage {
                VStack(spacing: 4) {
                    // -- Rubber-duck “pixel” --
                    Text("🐣")
                        .font(.system(size: 32))                 // big enough to feel like art
                        .scaleEffect(bounce ? 1.15 : 1.0)        // gentle zoom
                        .animation(
                            .interpolatingSpring(stiffness: 250, damping: 15)
                                .repeatForever(autoreverses: true),
                            value: bounce
                        )
                        .onAppear { bounce = true }
                        .onDisappear { bounce = false }

                    Text("Waiting for friends…")
                        .font(.custom("Roboto-Regular", size: 16))
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .frame(height: messageHeight)        // 80 pt is still fine
                .offset(y: messageOffsetY)
            }
        }
    }

    private func triggerStickyMessage() {
        showMessage = true
        // lock in place
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            contentOffsetY = messageHeight
            messageOffsetY = 0
            dragOffset = 0
        }
        // hold, then slide back up
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeIn(duration: 0.3)) {
                contentOffsetY = 0
                messageOffsetY = -messageHeight
            }
            // hide after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showMessage = false
            }
        }
    }

    // ── Columns unchanged below ───────────────────────────────────
    private var bluetoothColumn: some View {
        VStack(spacing: 8) {
            Text("Peers").font(.custom("Roboto-SemiBold", size: 16))
            ForEach(syncSettings.discoveredPeers.indices, id: \.self) { i in
                let peer = syncSettings.discoveredPeers[i]
                ParentRowView(
                    index: i,
                    peer: peer,
                    isMe: peer.id == syncSettings.localPeerID,
                    barsIcon: barsIcon(for:)
                )
            }
            Spacer()
        }
    }

    private var parentsColumn: some View {
        VStack(spacing: 8) {
            Text("Parents").font(.custom("Roboto-SemiBold", size: 16))
            ForEach(parents.indices, id: \.self) { i in
                let peer = parents[i]
                ParentRowView(
                    index: i,
                    peer: peer,
                    isMe: peer.id == syncSettings.localPeerID,
                    barsIcon: barsIcon(for:)
                )
            }
            Spacer()
        }
    }

    private var childrenColumn: some View {
        VStack(spacing: 8) {
            Text("Children").font(.custom("Roboto-SemiBold", size: 16))
            ForEach(children.indices, id: \.self) { i in
                let peer = children[i]
                ParentRowView(
                    index: i,
                    peer: peer,
                    isMe: peer.id == syncSettings.localPeerID,
                    barsIcon: barsIcon(for:)
                )
            }
            Spacer()
        }
    }
}

struct ParentRowView: View {
    let index: Int
    let peer: SyncSettings.Peer
    let isMe: Bool
    let barsIcon: (Int) -> String

    var body: some View {
        HStack {
            Text("\(index + 1). \(peer.name)")
                .fontWeight(isMe ? .bold : .regular)
            Spacer()
            if isMe {
                Text("(me!)").foregroundColor(.secondary)
            } else {
                Image(systemName: barsIcon(peer.signalStrength))
                    .foregroundColor(.secondary)
            }
        }
    }
}


private struct PeerRow: View {
    var peer: SyncSettings.Peer   // ← use SyncSettings.Peer, not the local Peer
    var isMe: Bool

    private func bars(_ n: Int) -> String {
        switch n {
        case 3: return "wifi"
        case 2: return "wifi.slash"
        case 1: return "wifi.exclamationmark"
        default: return "wifi.slash"
        }
    }

    var body: some View {
        HStack {
            Text(peer.name + (isMe ? " (me!)" : ""))
                .fontWeight(isMe ? .bold : .regular)
            Spacer()
            Image(systemName: bars(peer.signalStrength))
        }
        .padding(8)
        .background(isMe ? Color.accentColor.opacity(0.2)
                         : Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
struct FallingIconsView: View {
    var body: some View {
        Color.clear        // no-op for now
            .allowsHitTesting(false)
    }
}

// 3) ABOUT
struct AboutPage: View {
    @State private var showHallOfFame = false
    @State private var tapCount = 0
    @State private var showRain = false
    @State private var moveFirst = false      // ← NEW
    @State private var rippleStates = Array(repeating: false, count: 15)
    @State private var rippleOffset: CGFloat = 0
    @State private var didSlide = false
    @AppStorage("eggUnlocked") private var eggUnlocked: Bool = false
    private let slotWidth: CGFloat = 14    // width+spacing of one badge
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    @EnvironmentObject private var appSettings: AppSettings
    
    
    
    var body: some View {
        
        GeometryReader { geo in
           
            let slideOffset = didSlide ? slotWidth * 4 : 0
            
            VStack(alignment: .leading, spacing: 12) {
              
                // ── Icon + version block ──────────────────────────
                HStack(alignment: .top, spacing: 12) {
                    
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(radius: 4, y: 2)
                        .onLongPressGesture {
                            showHallOfFame = true
                        }
                    
                    // Multiline text + hourglass “breadcrumbs”
                    HStack(alignment: .top, spacing: 4) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("SyncTimer™ Version \(version)-\(build)")
                                .font(.custom("Roboto-SemiBold", size: 16))
                                .lineLimit(1)
                            Text("© 2025 Stage Devices, LLC")
                                .font(.custom("Roboto-SemiBold", size: 16))
                            // allow wrapping here
                                .lineLimit(1)
                        }
                        // let this VStack take precedence in the HStack
                        .layoutPriority(1)
                        .offset(y: 4)
                        
                        Spacer(minLength: 8)
                        
                        // ── Breadcrumbs / “badge” zone ────────────────────────
                        if !eggUnlocked {
                            // original three‐row breadcrumbs
                            VStack(spacing: 2) {
                                HStack(spacing: 2) {
                                    ForEach(0..<min(tapCount, 5), id: \.self) { i in
                                        Image(systemName: "hourglass")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .opacity(
                                                          eggUnlocked
                                                            ? (i == 4 ? 1 : 0)      // after unlock, only badge #4 stays
                                                            : (rippleStates[i] ? 0 : 1)
                                                        )
                                            .animation(.easeOut(duration: 0.3), value: rippleStates[i])
                                    }
                                }
                                if tapCount > 5 {
                                    HStack(spacing: 2) {
                                        ForEach(5..<min(tapCount, 10), id: \.self) { i in
                                            Image(systemName: "hourglass")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .opacity(
                                                              eggUnlocked
                                                                ? (i == 4 ? 1 : 0)      // after unlock, only badge #4 stays
                                                                : (rippleStates[i] ? 0 : 1)
                                                            )
                                                .animation(
                                                    .easeOut(duration: 0.3).delay(Double(14 - i) * 0.1),
                                                    value: rippleStates[i]
                                                )
                                        }
                                    }
                                }
                                if tapCount > 10 {
                                    HStack(spacing: 2) {
                                        ForEach(10..<min(tapCount, 15), id: \.self) { i in
                                            Image(systemName: "hourglass")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .opacity(
                                                              eggUnlocked
                                                                ? (i == 4 ? 1 : 0)      // after unlock, only badge #4 stays
                                                                : (rippleStates[i] ? 0 : 1)
                                                            )
                                                .animation(
                                                    .easeOut(duration: 0.3).delay(Double(14 - i) * 0.1),
                                                    value: rippleStates[i]
                                                )
                                        }
                                    }
                                }
                            }
                        } else {
                            // once unlocked, show only the 5th badge (index 4) permanently:
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { i in
                                    Image(systemName: "hourglass")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .opacity(i == 4 ? 1 : 0)
                                }
                            }
                        }
                    }
                    // make the entire block tappable
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !didSlide else { return }
                        guard !eggUnlocked else { return }
                        let newCount = tapCount + 1
                        
                        // fire on exactly taps 5, 10, and 15
                        switch newCount {
                        case 5:
                            withAnimation { showRain = true }
                        case 10:
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                NotificationCenter.default.post(name: .spawnGiantHourglass, object: nil)
                            }
                        case 15:
                            NotificationCenter.default.post(name: .openBottomEdge, object: nil)
                            let slotWidth: CGFloat = 14    // (icon ~12 + spacing 2)
                                    // fade out 14→1, starting at t = 1s, 0.1s apart, each 0.3s long
                            for i in (0...14).reversed() where i != 4 {   // 0…14 except 4
                                let t = 1 + Double(14 - i) * 0.1
                                      DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                          rippleStates[i] = true
                                        }
                                      }
                                    }
                            // after last fade finishes, slide the first badge
                                    let totalDelay = 1 + Double(14)*0.1 + 0.3
                                    DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
                                        eggUnlocked = true

                                    }
                        default:
                            break
                        }
                        
                        // now clamp
                        tapCount = min(newCount, 15)
                    }
                }
                .padding(.bottom, 8)

                
                Divider().opacity(0.5)
                Text("Roboto font family\nCopyright 2011 Google Inc.\nApache License 2.0")
                    .font(.custom("Roboto-Light", size: 14))
                Divider().opacity(0.5)
                
                HStack {
                    // left column
                    VStack(alignment: .leading, spacing: 8) {
                        Link("Website", destination: URL(string: "https://www.synctimerapp.com")!)
                            .font(.custom("Roboto-Regular", size: 16))
                            .tint(appSettings.appTheme == .dark ? .white : .gray)
                        Link("Report a Bug", destination: URL(string: "https://www.synctimerapp.com/support")!)
                            .font(.custom("Roboto-Regular", size: 16))
                            .tint(appSettings.appTheme == .dark ? .white : .gray)
                    }
                    Spacer()
                    // right column
                    VStack(alignment: .trailing, spacing: 8) {
                        Link("Privacy Policy", destination: URL(string: "https://www.cbassuarez.com/synctimer-privacy-policy")!)
                            .font(.custom("Roboto-Regular", size: 16))
                            .tint(appSettings.appTheme == .dark ? .white : .gray)
                        Link("Terms of Service", destination: URL(string: "https://www.cbassuarez.com/synctimer-terms-of-service")!)
                            .font(.custom("Roboto-Regular", size: 16))
                        .tint(appSettings.appTheme == .dark ? .white : .gray)
                    }
                }
                .font(.custom("Roboto-Regular", size: 16))
                
                Divider().opacity(0.5)
                
                // Share & Rate
                HStack {
                    if #available(iOS 16.0, *) {
                        ShareLink(item: URL(string: "https://apps.apple.com/app/id123456789")!) {
                            Label("Share This App", systemImage: "square.and.arrow.up")
                                .font(.custom("Roboto-Regular", size: 16))
                                .tint(appSettings.appTheme == .dark ? .white : .black)
                        }
                    } else {
                        Button {
                            UIApplication.shared.open(URL(string: "https://apps.apple.com/app/id123456789")!)
                        } label: {
                            Label("Share This App", systemImage: "square.and.arrow.up")
                                .font(.custom("Roboto-Regular", size: 16))
                                .tint(appSettings.appTheme == .dark ? .white : .black)
                        }
                    }
                    Spacer()
                    Button {
                        UIApplication.shared.open(URL(string: "itms-apps://itunes.apple.com/app/id123456789")!)
                    } label: {
                        Label("Rate on App Store", systemImage: "star.fill")
                            .font(.custom("Roboto-Regular", size: 16))
                            .tint(appSettings.appTheme == .dark ? .white : .black)
                    }
                }
                .font(.custom("Roboto-Regular", size: 16))
                
                Text("Made in Los Angeles, CA")
                    .font(.custom("Roboto-Light", size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .sheet(isPresented: $showHallOfFame) {
                HallOfFameCard()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.hidden)
            }
            .overlay(
                Group {
                    if showRain {
                        FallingIconsOverlay {
                            let W = geo.size.width
                            let H = geo.size.height
                            return [
                                CGRect(x: 0,    y: 0, width: 1,    height: H), // left
                                CGRect(x: W-1,  y: 0, width: 1,    height: H), // right
                                CGRect(x: 0,    y: 0, width: W,    height: 2)  // bottom
                            ]
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                    }
                }
            )
            
        } // GeometryReader
        .onAppear {
            if eggUnlocked {
                tapCount = 15                        // let all rows exist
                for idx in 0..<15 { rippleStates[idx] = true }   // hide all…
                rippleStates[4] = false              // …except badge #4
            }
        }


        .onDisappear {
                        // only clear rain; leave tapCount at 15 if eggUnlocked
                        showRain = false
            
                    }
    }
}

/// Thanks & Credits sheet shown from a long-press on the About icon.
private struct HallOfFameCard: View {
    @State private var showBackers = false
    @EnvironmentObject private var appSettings: AppSettings
    @State private var currentBetaIndex = 0
    private let betaTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    
    // Define badge tiers
    private enum Tier: Int, CaseIterable {
        case platinum   // top tier
        case gold
        case silver
        case bronze
    }
    
    
    /// Founders / Sustainers / Supporters badges (orthogonal to metal tiers)
    private enum FounderTier: String {
        case founder    = "Founders"
        case sustainer  = "Sustainers"
        case supporter  = "Supporters"
        
        var iconName: String {       // SF-Symbol for tooltip badge
            switch self {
            case .founder:   return "crown.fill"
            case .sustainer: return "infinity"
            case .supporter: return "heart.fill"
            }
        }
    }
    // Replace with your real lists
    private struct BetaTester: Identifiable {
        let id = UUID()
        let imageName: String   // must exist in Assets.xcassets
        let name: String        // display name
    }
    
    private let betaTesters: [BetaTester] = [
        .init(imageName: "paul_avatar", name: "P.Y."),
        .init(imageName: "nuc_avatar", name: "P.Y."),
        .init(imageName: "nuc_avatar", name: "P.Y."),
        .init(imageName: "nuc_avatar", name: "P.Y."),
        .init(imageName: "nuc_avatar", name: "P.Y."),
        .init(imageName: "nuc_avatar", name: "P.Y."),
        .init(imageName: "nuc_avatar", name: "P.Y."),
        .init(imageName: "nuc_avatar", name: "P.Y."),
        
    ]
    // MARK: – Animated shimmer border used for platinum tier
    private struct ShimmerBorder: View {
        // One full lap every 8 s
        private let period: TimeInterval = 8
        
        var body: some View {
            TimelineView(.animation) { timeline in
                // Convert current time into an angle 0-360°
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: period)) / period
                let start = Angle(degrees: phase * 360)
                let end   = Angle(degrees: phase * 360 + 360)
                
                // Static stroke path, animated ANGULAR gradient
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.purple, .blue, .green, .yellow, .orange, .red, .purple]),
                            center: .center,
                            startAngle: start,
                            endAngle: end
                        ),
                        lineWidth: 4
                    )
            }
        }
    }
    ///Rounded rect with a centred downward arrow (“speech-bubble” look)
    private struct TooltipBubble: Shape {
        let corner: CGFloat = 10
        let arrowW: CGFloat = 16
        let arrowH: CGFloat = 8
        func path(in r: CGRect) -> Path {
            let body = CGRect(x: r.minX,
                              y: r.minY,
                              width:  r.width,
                              height: r.height - arrowH)
            var p = Path(roundedRect: body, cornerRadius: corner)
            // arrow
            let midX = r.midX
            p.move(to: CGPoint(x: midX - arrowW/2, y: body.maxY))
            p.addLine(to: CGPoint(x: midX,             y: body.maxY + arrowH))
            p.addLine(to: CGPoint(x: midX + arrowW/2, y: body.maxY))
            p.closeSubpath()
            return p
        }
    }
    
    private struct TooltipView: View {
        let backer: Backer
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(backer.founderTier.rawValue,
                      systemImage: backer.founderTier.iconName)
                
                Label("Pledged on \(backer.contributionDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                
                Text(backer.thankYou)
                    .font(.footnote)
                
                Text("\(Int(backer.contributionShare * 100))% of goal")
                .font(.footnote)
            }
            .padding(12)
            // 📌 bubble background + stroke
            .background(
                TooltipBubble()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                TooltipBubble()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }
    
    private struct BubbleSizeKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }
    
    // helpers to keep the tooltip on-screen
    private func clampedX(cell: CGRect, bubble: CGSize, screenW: CGFloat) -> CGFloat {
        let half = bubble.width / 2
        return min(max(cell.midX,   half + 8), screenW - half - 8)
    }
    private func clampedY(cell: CGRect, bubble: CGSize, topSafe: CGFloat) -> CGFloat {
        // place bubble above its card; if that would bleed off the top,
        // drop it just below the top safe-area + a small gap
        let target = cell.minY - bubble.height / 2 - 8
        let minY   = topSafe + bubble.height / 2 + 8
        return max(target, minY)
    }
    
    // Change to a Backer model
    private struct Backer: Identifiable {
        let id = UUID()
        let name: String
        let imageName: String?     // local asset name
        let tier: Tier             // reuse your Tier enum
        // tooltip data
        let founderTier: FounderTier
        let contributionDate: Date
        let thankYou: String
        /// Share of total crowd-fund goal (0…1)
        let contributionShare: Double
    }
    // ── New flippable, dynamic‐size BackerCard ──────────────
    private struct BackerCard: View {
        let backer: Backer
        @EnvironmentObject private var appSettings: AppSettings
        
        @State private var isFlipped = false
        
        var body: some View {
            Group {
                if isFlipped {
                    cardBack
                        .transition(.opacity.combined(with: .scale))
                } else {
                    cardFront
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isFlipped)
            .onTapGesture {
                withAnimation {
                    isFlipped.toggle()
                }
                // auto-reset after 3s
                if isFlipped {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { isFlipped = false }
                    }
                }
            }
            .parallax(magnitude: 8)
        }
        
        // FRONT side (fixed minHeight)
        private var cardFront: some View {
            HStack(spacing: 12) {
                if let img = backer.imageName {
                    Image(img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .innerShadow(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .innerShadow(Circle())
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        )
                }
                Text(backer.name)
                    .font(.custom("Roboto-SemiBold", size: 14))
                    .blendMode(.multiply)
                    .foregroundColor(appSettings.appTheme == .dark ? .gray : .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(minHeight:
                    backer.tier == .platinum ? 100 :
                    backer.tier == .gold     ?  90 :
                    backer.tier == .silver   ?  80 : 70)
                .background(tierBackground)          // ⬅️ use it here
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        
        // BACK side (dynamic height)
        private var cardBack: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(backer.founderTier.rawValue,
                      systemImage: backer.founderTier.iconName)
                Label(
                    "Pledged on \(backer.contributionDate.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "calendar"
                )
                // your percentage label (or determinate bar) goes here
                         Text("\(Int(backer.contributionShare * 100))% of goal")
                             .font(.footnote)
                
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        
        // Shared subviews
        @ViewBuilder
        private var tierBackground: some View {
            MetallicPlate(kind:
                backer.tier == .platinum ? .platinum :
                backer.tier == .gold     ? .gold     :
                backer.tier == .silver   ? .silver   : .bronze
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(2, anchor: .center)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    
    private let friends: [Backer] = [
        Backer(
            name: "The New Uncertainty Collective",
            imageName: "nuc_avatar",
            tier: .gold,
            founderTier: .sustainer,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*100),
            thankYou: "Thanks for the monthly support 🫶",
            contributionShare: 0.10
        ),
        Backer(
            name: "The New Uncertainty Collective",
            imageName: "nuc_avatar",
            tier: .platinum,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*100),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.40
            
        ),
        Backer(
            name: "Paul Yorke",
            imageName: "paul_avatar",
            tier: .silver,
            founderTier: .supporter,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "Paul Yorke",
            imageName: "paul_avatar",
            tier: .bronze,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "The New Uncertainty Collective",
            imageName: "nuc_avatar",
            tier: .gold,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "The New Uncertainty Collective",
            imageName: "nuc_avatar",
            tier: .platinum,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "Paul Yorke",
            imageName: "paul_avatar",
            tier: .silver,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.15
        ),
        Backer(
            name: "Paul Yorke",
            imageName: "paul_avatar",
            tier: .bronze,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.15
        )
        // …
    ]
    
    
    let libraries: [(String, String)] = [
      ("SwiftUI", "swift"),
      ("Combine", "network"),
      ("CoreBluetooth", "antenna.radiowaves.left.and.right"),
      ("CoreHaptics", "hand.tap")
    ]
    
    

    var body: some View {
        
            ZStack {
                // card background
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                
                // scrollable content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Hall of Fame")
                        
                    // MARK: – Beta Testers Carousel (smooth)
                    Text("Beta Testers")
                        .font(.custom("Roboto-SemiBold", size: 16))
                        .padding(.horizontal, 16)
                    InfiniteCarousel(betaTesters, spacing: 16, speed: 25) { tester in
                        Image(tester.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(
                                Text(tester.name)
                                    .font(.system(size:10, weight:.medium))
                                    .padding(.horizontal,6)
                                    .padding(.vertical,2)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .foregroundStyle(.primary),
                                alignment: .bottomLeading
                            )
                    }
                    .padding(.vertical, 0)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        
                        
                        // ▹ Apply an aggressive fade at the edges:
                        .mask(
                          LinearGradient(
                            gradient: Gradient(stops: [
                              .init(color: .white.opacity(0), location: 0.00),
                              .init(color: .white,             location: 0.20),
                              .init(color: .white,             location: 0.80),
                              .init(color: .white.opacity(0), location: 1.00),
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                          )
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Backers")
                                    .font(.custom("Roboto-SemiBold", size: 16))
                                    .padding(.horizontal, 16)
                                    .offset(y: -24)
                                
                                MasonryLayout(columns: 2, spacing: 16) {
                                    ForEach(friends) { backer in
                                        BackerCard(backer: backer)
                                        // start 20pt down + invisible
                                            .offset(y: showBackers ? 0 : 20)
                                            .opacity(showBackers ? 1 : 0)
                                        // stagger by tier
                                            .animation(animation(for: backer.tier), value: showBackers)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 20)
                            }
                        }
                        
                                    }
                                    .padding(0) // no extra inset on the VStack
                                }
                            }
                // <<-- All of these live directly on the ZStack in body:
                .padding()                    // outer card padding
                .coordinateSpace(name: "HOF")
                .scrollDisabled(false)
                .onAppear { showBackers = true }
            }
            
            // pick a distinct curve + delay for each Tier
            private func animation(for tier: Tier) -> Animation {
                switch tier {
                case .platinum:
                    // slow spring in first
                    return .interpolatingSpring(stiffness: 60, damping: 6)
                        .delay(0.00)
                case .gold:
                    // gentle ease-out
                    return .easeOut(duration: 0.8)
                        .delay(0.20)
                case .silver:
                    // slow ease-in
                    return .easeIn(duration: 0.9)
                        .delay(0.40)
                case .bronze:
                    // long ease-in-out
                    return .easeInOut(duration: 1.0)
                        .delay(0.60)
                }
            }
            
            @ViewBuilder private func SectionHeader(_ title: String) -> some View {
                Text(title)
                    .font(.custom("Roboto-SemiBold", size: 20))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
            
            @ViewBuilder private func ListSection(_ title: String, items: [String]) -> some View {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("Roboto-SemiBold", size: 16))
                    ForEach(items, id: \.self) { item in
                        Text("• \(item)")
                            .font(.custom("Roboto-Light", size: 14))
                    }
                }
            }
        }

// MARK: – FallingIconsScene
final class FallingIconsScene: SKScene, SKPhysicsContactDelegate {
    private let dropInterval: TimeInterval = 0.08
  private var lastDropTime: TimeInterval = 0

    /// your “ground” rects
       private var allBounceRects: [CGRect] = []
       var bounceRects: [CGRect] = [] {
         didSet {
           allBounceRects = bounceRects      // stash for later
           rebuildBoundaries()
         }
       }
    private var selectedNode: SKSpriteNode?

  private var startTime: TimeInterval?
  private var phase = 0
    private let t0: TimeInterval = 1.0   // first drop at 0.5s
  private let t1: TimeInterval = 4.0   // second drop at 1.0s
  private let t2: TimeInterval = 7.5   // two drops at 1.5s
  private let floodStart: TimeInterval = 2.0
    private let showerDuration: TimeInterval = 18.0

  override func didMove(to view: SKView) {
    backgroundColor     = .clear
    physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
    scaleMode           = .resizeFill
      physicsWorld.contactDelegate = self
    rebuildBoundaries()
      view.isUserInteractionEnabled = true
      // listen for the “giant hourglass” Easter egg
          NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpawnGiantHourglass),
            name: .spawnGiantHourglass,
            object: nil
          )
      // listen for the “open bottom” Easter egg
              NotificationCenter.default.addObserver(
                  self,
                  selector: #selector(handleOpenBottomEdge),
                  name: .openBottomEdge,
                  object: nil
              )
    // reset our sequence
    startTime = nil
    phase     = 0
  }
    @objc private func handleOpenBottomEdge() {
            dropBottomEdge()
        }
    @objc private func handleSpawnGiantHourglass() {
        // 1) Before the giant lands, make all existing little hourglasses much less bouncy
                for case let node as SKSpriteNode in children
                    where node.name != "giant" && node.physicsBody != nil
                {
                    let body = node.physicsBody!
                    body.restitution    = 1.0    // lots of bounce
                    body.friction       = 0.1    // no grip
                    body.linearDamping  = 0.1    // slow them down fast
                    body.angularDamping = 0.1
                }
                // 2) Now drop the giant
                spawnGiantHourglass()      }
    
      private func spawnGiantHourglass() {
        let tex  = SKTexture(imageNamed: "GiantHourglass")
        let node = SKSpriteNode(texture: tex)
        node.name = "giant"
        // make it huge
        node.setScale(3.0)
        node.zRotation = 0
        let r = max(node.size.width, node.size.height)/2
        let body = SKPhysicsBody(circleOfRadius: r)
          body.mass = 15.0                   // ↑ much heavier so it carries more momentum
          body.restitution = 0.4             // ↓ less bouncy so energy is absorbed
          body.linearDamping = 0.3           // add a bit of drag
          body.angularDamping = 0.3
        node.physicsBody = body
        // drop from center
        node.position = CGPoint(x: size.width/2, y: size.height + r*2)
        addChild(node)
        // slam it down
        node.physicsBody?.applyImpulse(CGVector(dx: .random(in: -800...800),
                                                dy: -5000))
      }
  override func update(_ currentTime: TimeInterval) {
    // record the very first frame time
    if startTime == nil {
      startTime = currentTime
      return
    }

    let elapsed = currentTime - startTime!

    switch phase {
    case 0 where elapsed >= t0:
      spawnIcon()        // first drop
      phase = 1

    case 1 where elapsed >= t1:
      spawnIcon()
      spawnIcon()        // second drop
      phase = 2

    case 2 where elapsed >= t2:
      spawnIcon()        // two quick drops
      spawnIcon()
      phase = 3

    case 3 where elapsed >= floodStart && elapsed < showerDuration:
      // full flood at your normal rate
      if currentTime - lastDropTime >= dropInterval {
        lastDropTime = currentTime
        spawnIcon()
      }

    case 3 where elapsed >= showerDuration:
      // stop spawning
      phase = 4

    default:
      break
    }
  }
    // MARK: – Touch‐drag to move sprites
      override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: self)
        // pick topmost sprite under touch
        if let node = nodes(at: loc).first(where: { $0 is SKSpriteNode && $0.physicsBody != nil }) as? SKSpriteNode {
          selectedNode = node
          // freeze physics while dragging
          node.physicsBody?.isDynamic = false
        }
      }
    
      override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let node = selectedNode else { return }
        node.position = t.location(in: self)
      }
    
      override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let node = selectedNode else { return }
        // re-enable physics so it drops/bounces from its new spot
        node.physicsBody?.isDynamic = true
        selectedNode = nil
      }
      override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
      }
  private func spawnIcon() {
    let palette = [
      "HourglassIndigo","HourglassTeal","HourglassYellow",
      "HourglassBlue","HourglassMint","HourglassOrange",
      "HourglassPurple","HourglassCyan","HourglassGreen",
      "HourglassRed"
    ]
    let imageName = palette.randomElement()!
    let tex       = SKTexture(imageNamed: imageName)
    let node      = SKSpriteNode(texture: tex)

    let scale = CGFloat.random(in: 0.8...1.2)
    node.setScale(scale)
    node.zRotation = CGFloat.random(in: 0...(2 * .pi))

    let r    = max(node.size.width, node.size.height) / 2
      // simpler ellipse approximation (much faster)
          let approxSize = CGSize(
              width: node.size.width * 0.95,
              height: node.size.height * 0.95
          )
      let body = SKPhysicsBody(rectangleOf: approxSize);
      body.restitution    = 0.3
      // tag for contact detection
      body.categoryBitMask    = 0x1
      body.contactTestBitMask = 0x2
      body.mass           = CGFloat.random(in: 0.9...1.1)
      body.friction       = 0.3             // surface friction
      body.linearDamping  = CGFloat.random(in: 0.5...1.0)  // more drag
      body.angularDamping = CGFloat.random(in: 0.5...1.0)
    node.physicsBody    = body

    node.position = CGPoint(
      x: .random(in: 0...size.width),
      y: size.height + r * 2
    )
    addChild(node)

    let imp = CGVector(
      dx: .random(in: -20...20),
      dy: .random(in: -30...10)
    )
    node.physicsBody?.applyImpulse(imp)
  }

  private func rebuildBoundaries() {
    children.filter { $0.name == "boundary" }
            .forEach { $0.removeFromParent() }

      for rect in bounceRects {
             let edge = SKNode()
             // tag sides vs bottom
             edge.name = (rect.width <= 1) ? "boundary-side" : "boundary-bottom"
      let path = CGMutablePath()
      path.addRect(rect)
      let body = SKPhysicsBody(edgeLoopFrom: path)
        body.restitution = 0.7
        // tag walls so we can catch puck↔wall collisions
        body.categoryBitMask    = 0x1                     // “puck”
        body.contactTestBitMask = 0x1 | 0x2
        edge.physicsBody = body
      addChild(edge)
    }
  }
    /// when you finally open the bottom, remove those loops so
        /// the remaining hourglasses can fall right through:
        private func dropBottomEdge() {
            children
              .filter { $0.name == "boundary-bottom" }
              .forEach { $0.removeFromParent() }
        }
    // MARK: — on each puck↔wall contact, decay restitution so bounces die out
    func didBegin(_ contact: SKPhysicsContact) {
    // figure out which body is the hourglass “puck”
        // for any bodyA or bodyB that is a puck, decay its restitution
        for b in [contact.bodyA, contact.bodyB] where b.categoryBitMask == 0x1 {
            b.restitution = max(b.restitution * 0.6, 0)   // stronger decay
            b.friction    = min(b.friction + 0.1, 1.0)    // gradually increase friction
           }
        // when giant hits the first small hourglass, drop the side walls
            let bodies = [contact.bodyA, contact.bodyB]
            let hitGiant = bodies.contains { $0.node?.name == "giant" }
            let hitSmall = bodies.contains {
              $0.categoryBitMask == 0x1 && $0.node?.name != "giant"
            }
            if hitGiant && hitSmall {
              dropSideWalls()
            }
  }
    /// convert the static side edges into dynamic boards so they fall
    private func dropSideWalls() {
      // create falling boards where the side loops were
      for rect in allBounceRects where rect.width <= 1 {
        let board = SKSpriteNode(color: .clear, size: rect.size)
        board.position = CGPoint(x: rect.midX, y: rect.midY)
        let body = SKPhysicsBody(rectangleOf: rect.size)
        body.restitution    = 0.2
        body.friction       = 0.8
        body.linearDamping  = 1.0
        body.angularDamping = 1.0
        board.physicsBody   = body
        addChild(board)
      }
      // remove the old static side–loop bodies
      children
        .filter { $0.name == "boundary-side" }
        .forEach { $0.removeFromParent() }
    }
}

extension Notification.Name {
    static let spawnGiantHourglass = Notification.Name("spawnGiantHourglass")
    static let openBottomEdge       = Notification.Name("openBottomEdge")
}
//──────────────────────────────────────────────────────────
// MARK: – SwiftUI Wrapper
//──────────────────────────────────────────────────────────
struct FallingIconsOverlay: UIViewRepresentable {
    /// Return an array of CGRects *in the SKView’s coordinate space*—
    /// e.g. the left wall, right wall, and bottom of your card.
    let boundsProvider: () -> [CGRect]

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.backgroundColor = .clear
        skView.allowsTransparency = true

        // create your scene and assign the physics boundaries exactly once:
        let scene = FallingIconsScene(size: .zero)
        scene.bounceRects = boundsProvider()
        skView.presentScene(scene)

        context.coordinator.scene = scene
        return skView
    }

    func updateUIView(_ skView: SKView, context: Context) {
        // keep the scene stretched to fill its container:
        skView.scene?.size = skView.bounds.size

        // ←— **remove** this line, or guard it so it only runs once:
        // context.coordinator.scene?.bounceRects = boundsProvider()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        weak var scene: FallingIconsScene?
    }
}



// Finally, your card wrapper:
struct SettingsPagerCard: View {
    @Binding var page: Int
    @Binding var editingTarget: EditableField?
    @Binding var inputText: String
    @Binding var isEnteringField: Bool
    @Binding var showBadPortError: Bool      // ← add this

    
    @EnvironmentObject private var appSettings : AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings
    private let flashPresets: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple,
        Color(red: 199/255, green: 199/255, blue: 204/255)
    ]
    // total card height:
    /// Replace the hard-coded 312 with this:
        private var cardHeight: CGFloat {
            UIScreen.main.bounds.width < 414 ? 292 : 312
        }        // only top padding, not top+bottom:
        private let topInset: CGFloat = 0


        var body: some View {
            ZStack {
                // 1) Base: always use ultraThinMaterial + shadow
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .shadow(
                                    color: Color.black.opacity(appSettings.lowPowerMode ? 0 : 0.15),
                                    radius: appSettings.lowPowerMode ? 0 : 8,
                                    x: 0, y: appSettings.lowPowerMode ? 0 : 4
                                )

                            // 2) Overlay flat color *only* in Low-Power Mode
                            if appSettings.lowPowerMode {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(appSettings.appTheme == .dark ? Color.black : Color.white)
                            }


                // host exactly one page, pinned to top + inset
                Group {
                    switch page {
                    case 0:
                        AppearancePage(presets: flashPresets)
                    case 1:
                        TimerBehaviorPage()
                    case 2:
                        ConnectionPage(
                            editingTarget: $editingTarget,
                            inputText: $inputText,
                            isEnteringField: $isEnteringField,
                            showBadPortError: $showBadPortError
                        )
                    case 3:
                        AboutPage()
                    default:
                        EmptyView()
                    }
                }
                .padding(.top, topInset)
                // force every page into the same height
                .frame(
                    maxWidth: .infinity,
                    maxHeight: cardHeight - topInset,
                    alignment: .topLeading
                )
                .clipped()
            }
            .frame(height: cardHeight)
            .padding(.horizontal, 16)
            .offset(y: 8)
            .onChange(of: page) { _ in
              editingTarget   = nil
              inputText       = ""
              isEnteringField = false
            }
        }
    }

//──────────────────────────────────────────────────────────────
// MARK: – ContentView
//──────────────────────────────────────────────────────────────
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings

    @AppStorage("settingsPage") private var settingsPage = 0
    @State private var showSettings = false
    @State private var mainMode: ViewMode = .sync
    
    @AppStorage("hasSeenWalkthrough") private var hasSeenWalkthrough: Bool = false
    @State private var showSyncErrorAlert = false
    @State private var syncErrorMessage   = ""
    
    @State private var editingTarget: EditableField? = nil
    @State private var inputText: String = ""
    @State private var isEnteringField: Bool = false

    var body: some View {
        // Decide regular SYNC backdrop
        let bgImageName: String = {
            switch settings.appTheme {
            case .light: return "MainBG1"
            case .dark:  return "MainBG2"
            }
        }()

        ZStack(alignment: .bottomLeading) {
            // 1) Draw the backdrop image
            AppBackdrop(imageName: bgImageName)
            
            // 2) If we're in light theme and the user has chosen a non‐clear color,
            //    blend it over the backdrop immediately.
            if settings.appTheme == .light,
               settings.customThemeOverlayColor != .clear
            {
                Color(settings.customThemeOverlayColor)
                    .compositingGroup()      // isolate this layer for blending
                    .blendMode(.multiply)     // or .multiply, whichever you prefer
                    .ignoresSafeArea()       // cover the full screen
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: settings.customThemeOverlayColor)
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
        // 1) Present WalkthroughView as a full-screen cover on first launch:
               .fullScreenCover(isPresented: Binding(
                   get: { !hasSeenWalkthrough },
                   set: { _ in hasSeenWalkthrough = true }
               )) {
                   WalkthroughView()
                       .environmentObject(settings)
                       .environmentObject(syncSettings)
               }
               // 2) When the user taps “gear,” show your SettingsView in a sheet:
               .sheet(isPresented: $showSettings) {
                   SettingsPagerCard(page: $settingsPage,
                                     editingTarget: $editingTarget,
                                     inputText: $inputText,
                                     isEnteringField: $isEnteringField,
                                     showBadPortError: .constant(false)
                   )
                       .environmentObject(settings)
                       .environmentObject(syncSettings)
                       .preferredColorScheme(
                           settings.appTheme == .dark ? .dark : .light
                       )
                   
               }
               .alert(isPresented: $showSyncErrorAlert) {
                 Alert(
                   title: Text("Cannot Start Sync"),
                   message: Text(syncErrorMessage),
                   dismissButton: .default(Text("OK"))
                 )
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
    // hook up the UIKit delegate
    
    // your own state‐objects…
    @StateObject private var appSettings  = AppSettings()
    @StateObject private var syncSettings = SyncSettings()
    @AppStorage("settingsPage") private var settingsPage = 0
    @State private var editingTarget: EditableField? = nil
    @State private var inputText       = ""
    @State private var isEnteringField = false
        
    init() {
        print("✅ Original image loads:", UIImage(named: "AppLogo") != nil)
        _ = UIImage(named: "LaunchLogo")
        print("✅ Duplicate image loads:", UIImage(named: "LaunchLogo") != nil)

        // ── Your existing startup work ───────────────────────────────
        print("❓ LaunchScreen exists at:",
              Bundle.main.url(forResource: "LaunchScreen", withExtension: "storyboardc")
              ?? "🛑 NOT FOUND")
        // Drop in App.init() and read the console.
        print("→ launch key iOS actually sees:",
              Bundle.main.object(forInfoDictionaryKey: "UILaunchStoryboardName") ?? "nil")

        print("→ storyboard in bundle? ",
              FileManager.default.fileExists(
                    atPath: Bundle.main.bundlePath + "/LaunchScreen.storyboardc"))

        UIApplication.shared.isIdleTimerDisabled = true
        registerRoboto()
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = ConnectivityManager.shared
            session.activate()
            print("[WC] WCSession.activate() called, state = \(session.activationState.rawValue)")
        }
        
        UIImpactFeedbackGenerator(style: .light).prepare()
        _ = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in }
        _ = SettingsPagerCard(
                   page: $settingsPage,
                   editingTarget: $editingTarget,
                   inputText: $inputText,
                   isEnteringField: $isEnteringField,
                   showBadPortError: .constant(false)
               )
       
        _ = syncSettings.bleDriftManager.central.state
        
    }
    
    var body: some Scene {
        let bleManager     = syncSettings.bleDriftManager
        let bonjourManager = syncSettings.bonjourManager
        
        WindowGroup {
            ContentView()
                .transition(.opacity.animation(.easeOut(duration: 0.3)))
                .environmentObject(appSettings)
                .environmentObject(syncSettings)
                .preferredColorScheme(appSettings.appTheme == .dark ? .dark : .light)
            
        }
        
        // Tear-down logic when connection method changes
        .onChange(of: syncSettings.connectionMethod) { _ in
            syncSettings.stopParent()
            syncSettings.stopChild()
            bleManager.stop()
            bonjourManager.stopBrowsing()
            bonjourManager.stopAdvertising()
        }
    
    
}
}
