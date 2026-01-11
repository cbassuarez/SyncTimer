
//
//  SyncTimerApp.swift   – 2025-06-01, compile-clean
//


import SwiftUI
import Combine
import AudioToolbox
import CoreText
import Sentry
import Network
import SystemConfiguration
import AVFoundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
import CoreImage.CIFilterBuiltins
import CoreBluetooth
import SpriteKit
import UIKit
#if canImport(AppKit)
import AppKit
#endif


//───────────────────
// MARK: – Haptics
//───────────────────
private enum Haptics {
    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

//───────────────────
// MARK: – tiny helpers
//───────────────────
// MARK: - App-wide notification (optional)
// MARK: - App-wide notifications
extension Notification.Name {
    /// Toasts etc. after "Open in SyncTimer" imports an XML
    static let didImportCueSheet = Notification.Name("didImportCueSheet")
    /// A cue sheet has been loaded (either local load or broadcast-accept)
    static let whatsNewOpenCueSheets = Notification.Name("whatsNewOpenCueSheets")
    /// Countdown quick actions for iOS home-screen shortcuts.
    static let quickActionCountdown = Notification.Name("quickActionCountdown")
}

extension SyncSettings.SyncConnectionMethod: SegmentedOption {
  var icon: String {
    switch self {
    case .network:   return "wifi"      // pick your SF Symbol
    case .bluetooth: return "antenna.radiowaves.left.and.right"
    case .bonjour:   return "antenna.radiowaves.left.and.right"
    }
  }
  var label: String { rawValue }
}
// MARK: - Timer ↔︎ Settings morph (matched-geometry)
/// A tiny wrapper that owns the `@Namespace` so both cards can morph cleanly.
struct CardMorphSwitcher<TimerV: View, SettingsV: View>: View {
    @Namespace private var ns
    @Binding var mode: ViewMode
    let timer: TimerV
    let settings: SettingsV

    var body: some View {
    ZStack {
           if mode == .settings {
                settings
                    .matchedGeometryEffect(id: "TimerSettingsCard", in: ns)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            } else {
                timer
                    .matchedGeometryEffect(id: "TimerSettingsCard", in: ns)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            }
        }
    }
}
private struct CardMorph: ViewModifier {
    enum Phase { case identity, insertionActive, removalActive }
    let phase: Phase

    func body(content: Content) -> some View {
        switch phase {
        case .identity:
            content
        case .insertionActive:
            content
                .offset(y: -12)
                .opacity(0)
                .blur(radius: 2)
                .scaleEffect(0.98, anchor: .top)
                .clipped()
        case .removalActive:
            content
                .opacity(0)
                .blur(radius: 1)
                .scaleEffect(0.97)
                .clipped()
        }
    }
}

// MARK: - Sync/Events bar morph (matched-geometry; layout-safe)
struct ModeBarMorphSwitcher<SyncV: View, EventsV: View>: View {
    @Namespace private var ns
    let isSync: Bool
    let sync: SyncV
    let events: EventsV

    init(isSync: Bool,
         @ViewBuilder sync: () -> SyncV,
         @ViewBuilder events: () -> EventsV) {
        self.isSync = isSync
        self.sync   = sync()
        self.events = events()
    }

    var body: some View {
        ZStack {
            if isSync {
                sync
                    .matchedGeometryEffect(id: "modebar", in: ns)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                events
                    .matchedGeometryEffect(id: "modebar", in: ns)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(
            {
                if #available(iOS 17, *) {
                    return .snappy(duration: 0.26, extraBounce: 0.25)
                } else {
                    return .easeInOut(duration: 0.26)
                }
            }(),
            value: isSync
        )
    }
}
private struct PhoneStyleOnMiniLandscapeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var phoneStyleOnMiniLandscape: Bool {
        get { self[PhoneStyleOnMiniLandscapeKey.self] }
        set { self[PhoneStyleOnMiniLandscapeKey.self] = newValue }
    }
}

private struct BadgeRowLiftKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var badgeRowLift: CGFloat {
        get { self[BadgeRowLiftKey.self] }
        set { self[BadgeRowLiftKey.self] = newValue }
    }
}

// pagination for ipads
private struct LeftPanePager<Devices: View, Notes: View>: View {
    @Binding var tab: Int
    let titleProvider: () -> [String]
    let onPrev: () -> Void
    let onNext: () -> Void
    @ViewBuilder let devicesView: () -> Devices
    @ViewBuilder let notesView: () -> Notes

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            // Header with arrows + title (like Settings)
            HStack {
                Button(action: onPrev) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                Spacer(minLength: 8)
                Text(titleProvider()[safe: tab] ?? "")
                    .font(.custom("Roboto-SemiBold", size: 20))
                    .foregroundStyle(.secondary)
                    .animation(nil, value: tab)
                Spacer(minLength: 8)
                Button(action: onNext) { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 4)

            // Paged content with morphy snap
            ZStack {
                Group {
                    if tab == 0 { devicesView().id("devices") }
                    else        { notesView().id("notes")   }
                }
                .contentTransition(.opacity)
                .transition(.opacity)
                .animation(
                    {
                        if #available(iOS 17, *) {
                            return .snappy(duration: 0.24, extraBounce: 0.25)
                        } else { return .easeInOut(duration: 0.24) }
                    }(),
                    value: tab
                )
            }
        }
        .padding(.top, 2)
    }
}

private struct LeftPaneNav: View {
    @Binding var tab: Int
    let titles: [String]

    var body: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(anim) { tab = (tab + titles.count - 1) % titles.count }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // Center title + dots
            VStack(spacing: 6) {
                Text(titles[safe: tab] ?? "")
                    .font(.custom("Roboto-SemiBold", size: 17))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(0..<titles.count, id: \.self) { i in
                        Circle()
                            .frame(width: 6, height: 6)
                            .opacity(i == tab ? 1.0 : 0.25)
                            .animation(nil, value: tab)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(anim) { tab = (tab + 1) % titles.count }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var anim: Animation {
        if #available(iOS 17, *) { return .snappy(duration: 0.24, extraBounce: 0.25) }
        else { return .easeInOut(duration: 0.24) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

 // ─────────────────────────────────────────────────────────────
 // Presets Model (device-local)
 // ─────────────────────────────────────────────────────────────
 struct Preset: Identifiable, Codable, Equatable {
     enum Kind: String, Codable { case countdown, cueRelative, cueAbsolute, sheet }
     var id: UUID = UUID()
     var name: String = ""
     var kind: Kind
     var seconds: Double?          // countdown or cue time
     var sheetIdentifier: String?  // persisted cue sheet identifier (or filename/title)
     var icon: String = "circle"   // SF Symbol
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

// Centralized app-level settings (themes, preferences, etc.)
final class AppSettings: ObservableObject {

    // High-contrast toggle — single source of truth
    @Published var highContrastSyncIndicator: Bool {
        didSet {
            UserDefaults.standard.set(highContrastSyncIndicator, forKey: "highContrastSyncIndicator")
        }
    }

    // Seed from defaults so the toggle reflects prior choice on launch
    init() {
        self.highContrastSyncIndicator = UserDefaults.standard.bool(forKey: "highContrastSyncIndicator")
    }
    @AppStorage("leftPanePaginateOnLargePads")
        var leftPanePaginateOnLargePads: Bool = false
    // AppSettings.swift
    @AppStorage("allowSyncChangesInMainView")
    public var allowSyncChangesInMainView: Bool = true

    // The rest of your settings (unchanged)
    @AppStorage("showHours") var showHours: Bool = true
    @Published var roleSwitchConfirmationMode: RoleSwitchConfirmationMode = .popup
    @Published var appTheme: AppTheme = .light
    @Published var customThemeOverlayColor: Color = .clear
    @Published var lowPowerMode: Bool = false
    @AppStorage("UltraSyncKalman") var ultraSyncKalman: Bool = true
    @Published var vibrateOnFlash: Bool = true
    @Published var flashDurationOption: Int = 250
    @Published var flashStyle: FlashStyle = .fullTimer
    @Published var flashColor: Color = .red
    @Published var countdownResetMode: CountdownResetMode = .off
    @Published var resetConfirmationMode: ResetConfirmationMode = .off
    @Published var stopConfirmationMode: ResetConfirmationMode = .off
    @AppStorage("simulateChildMode") var simulateChildMode: Bool = false
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
// ──────────────────────────────────────────────────────────────
// MARK: – Central timer formatter (HH:MM:SS.CC or MM:SS.CC)
// ──────────────────────────────────────────────────────────────
/// Formats a time interval in seconds into either `HH:MM:SS.CC` or `MM:SS.CC`.
/// Minutes-only is used when `alwaysShowHours == false` and the absolute value is < 3600s.
@inline(__always)
func formatTimerString(_ t: TimeInterval, alwaysShowHours: Bool) -> String {
    // We format the absolute value; any sign/prefix is handled by the caller UI.
    let v = abs(t)
    // Centiseconds (rounded) to stay consistent with other renderers
    let cs = Int((v * 100).rounded())
    let h  = cs / 360_000
    let m  = (cs / 6_000) % 60
    let s  = (cs / 100) % 60
    let c  = cs % 100

    if alwaysShowHours || v >= 3600.0 {
        return String(format: "%02d:%02d:%02d.%02d", h, m, s, c)
    } else {
        let mm = cs / 6_000 // total minutes
        return String(format: "%02d:%02d.%02d", mm, s, c)
    }
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

struct HostJoinRequestV1: Equatable {
    let hostUUID: UUID
    let deviceName: String?
    let sourceURL: String
}

enum HostJoinParseError: Error, Equatable {
    case invalidURL
    case invalidHost
    case invalidPath
    case invalidVersion
    case missingHostUUID
    case invalidHostUUID
}

extension HostJoinParseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn’t look like a SyncTimer link."
        case .invalidHost, .invalidPath:
            return "This isn’t a SyncTimer join link."
        case .invalidVersion:
            return "This join link is outdated."
        case .missingHostUUID, .invalidHostUUID:
            return "Host ID missing or invalid."
        }
    }
}

enum HostJoinLinkParser {
    static func parse(urlString: String) -> Result<HostJoinRequestV1, HostJoinParseError> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed) {
            return parse(url: url)
        }
        if !trimmed.lowercased().hasPrefix("http"),
           let url = URL(string: "https://\(trimmed)") {
            return parse(url: url)
        }
        return .failure(.invalidURL)
    }

    static func parse(url: URL) -> Result<HostJoinRequestV1, HostJoinParseError> {
        guard url.host == "synctimerapp.com" else {
            return .failure(.invalidHost)
        }
        guard url.path == "/host" else {
            return .failure(.invalidPath)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidURL)
        }
        let queryPairs: [(String, String)] = (components.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        }
        let query = Dictionary(uniqueKeysWithValues: queryPairs)
        guard query["v"] == "1" else {
            return .failure(.invalidVersion)
        }
        guard let hostUUIDRaw = query["host_uuid"] else {
            return .failure(.missingHostUUID)
        }
        guard let hostUUID = UUID(uuidString: hostUUIDRaw) else {
            return .failure(.invalidHostUUID)
        }
        let deviceName = query["device_name"]?.removingPercentEncoding
        return .success(
            HostJoinRequestV1(
                hostUUID: hostUUID,
                deviceName: deviceName,
                sourceURL: url.absoluteString
            )
        )
    }
}

private enum ChildJoinLinkParseResult {
    case join(JoinRequestV1)
    case legacy(HostJoinRequestV1)
}

private enum ChildJoinLinkParseError: Error, Equatable {
    case notSyncTimerLink
    case unsupportedSyncTimerLink
    case joinError(JoinLinkParser.JoinLinkError)
    case legacyError(HostJoinParseError)
}

private func parseChildJoinLink(url: URL, currentBuild: Int? = nil) -> Result<ChildJoinLinkParseResult, ChildJoinLinkParseError> {
    guard url.host == "synctimerapp.com" else {
        return .failure(.notSyncTimerLink)
    }
    switch JoinRequestV1.parse(url: url, currentBuild: currentBuild) {
    case .success(let request):
        return .success(.join(request))
    case .failure(let error):
        if case .invalidPath = error {
            switch HostJoinLinkParser.parse(url: url) {
            case .success(let request):
                return .success(.legacy(request))
            case .failure(let legacyError):
                if case .invalidPath = legacyError {
                    return .failure(.unsupportedSyncTimerLink)
                }
                return .failure(.legacyError(legacyError))
            }
        }
        return .failure(.joinError(error))
    }
}

extension SyncSettings {
    /// Centralized place to flip connection state.
    /// Call on main when possible; this wraps main-queue just in case.
    func setEstablished(_ connected: Bool) {
        DispatchQueue.main.async {
            self.isEstablished = connected
        }
    }
}

final class SyncSettings: ObservableObject {
    var connectedChildrenCount: Int { childConnections.count }

    // Singleton-ish access (only if you already use a shared pattern)
        static let shared = SyncSettings()
    // Injected from App root; used by `receiveLoop` to process beacons
    weak var clockSyncService: ClockSyncService? {
        didSet {
            clockSyncService?.burstRequestHandler = { [weak self] count, spacingMs in
                self?.requestBeaconBurst(count: count, spacingMs: spacingMs)
            }
        }
    }

    // Auto-retry state (child, .network only)
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt: Int = 0
    private var syncEnvelopeSeq: Int = 0
    private var lastReceivedSyncSeq: Int = -1
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private var actionSeqCounter: UInt64 = 0

    private var wcCancellables: Set<AnyCancellable> = []

    init() {
        ConnectivityManager.shared.$incoming
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.onReceiveTimer?(msg)
            }
            .store(in: &wcCancellables)

        ConnectivityManager.shared.$incomingSyncEnvelope
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] envelope in
                guard let self else { return }
                self.receiveSyncEnvelope(envelope)
            }
            .store(in: &wcCancellables)
    }

    private func resetSyncSequence() {
        lastReceivedSyncSeq = -1
    }

    private func isControlAction(_ action: TimerMessage.Action) -> Bool {
        switch action {
        case .start, .pause, .reset, .endCueSheet:
            return true
        case .update, .addEvent:
            return false
        }
    }
    
    // Cancel any active retry
    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectAttempt = 0
    }
    
    /// TEMP: best-effort disconnect for a specific child.
        /// If we don’t yet map NWConnection ⇄ Peer, we drop all children as a fallback.
        func disconnectPeer(_ id: UUID) {
            // Remove from peers model
            DispatchQueue.main.async {
                self.peers.removeAll { $0.id == id }
            }
            // TODO: once mapping exists, cancel only that NWConnection.
            // For now, safest: drop all and let remaining reconnect.
            for c in childConnections { c.cancel() }
            childConnections.removeAll()
            DispatchQueue.main.async {
                self.isEstablished = false
                self.statusMessage = "Child disconnected"
            }
        }
    
    // Schedule the next attempt with gentle backoff (0.6s, 1.2s, 2.0s, 3.0s, 4.0s… capped)
    private func scheduleReconnect(_ reason: String) {
        guard isEnabled, role == .child, connectionMethod == .network else { return }
        reconnectWorkItem?.cancel()
        
        // Backoff curve: ~0.6 * (attempt+1)^1.2, max 4.5s
        reconnectAttempt += 1
        let delay = min(4.5, 0.6 * pow(Double(reconnectAttempt + 1), 1.2))
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isEnabled else { return }
            // Only try again if we still don’t have a ready connection
            if self.clientConnection == nil || self.clientConnection?.state != .ready {
                self._connectChildOverLAN()
            }
        }
        reconnectWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    private var syncKeepAlive: AnyCancellable?
    
    // Keep amber “alive” until we’re green; cancel itself once connected/disabled.
    private func beginKeepAlive() {
        // Reset any prior ticker
        syncKeepAlive?.cancel()

        // Only run while user wants sync
        guard isEnabled else { return }

        syncKeepAlive = Timer.publish(every: 2.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }

                // If sync toggled off, stop the keep-alive entirely
                guard self.isEnabled else {
                    self.syncKeepAlive?.cancel()
                    self.syncKeepAlive = nil
                    return
                }

                // If already connected (green), stop the keep-alive
                if self.isEstablished {
                    self.syncKeepAlive?.cancel()
                    self.syncKeepAlive = nil
                    return
                }

                switch self.connectionMethod {
                case .network:
                    // LAN keep-alive is child-only; parent listens instead.
                    guard self.role == .child else { return }

                    // If Network.framework reports ready, promote to green and stop.
                    if self.clientConnection?.state == .ready {
                        DispatchQueue.main.async {
                            self.isEstablished = true
                            // Keep your existing status text pattern:
                            self.statusMessage = "Connected to \(self.peerIP):\(self.peerPort)"
                        }
                        self.syncKeepAlive?.cancel()
                        self.syncKeepAlive = nil
                        return
                    }

                    // Otherwise, idempotently kick another connect attempt.
                    // (If you added backoff helpers, they’ll manage pacing.)
                    self.cancelReconnect()      // safe if you added it; no-op if not present
                    self._connectChildOverLAN()

                case .bluetooth, .bonjour:
                    // Keep peer-to-peer discovery alive while amber (idempotent calls).
                    self.bonjourManager.startBrowsing()
                    if self.role == .parent {
                        self.bonjourManager.startAdvertising()
                    }
                }
            }
    }

    
    private func endKeepAlive() {
        syncKeepAlive?.cancel()
        syncKeepAlive = nil
    }

    private func makeBeaconEnvelope() -> BeaconEnvelope {
        if let env = clockSyncService?.makeBeacon(parentUUID: localPeerID.uuidString) {
            return env
        }
        return BeaconEnvelope(
            type: .beacon,
            uuidP: localPeerID.uuidString,
            uuidC: nil,
            seq: UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFFFFFF,
            tP_send: ProcessInfo.processInfo.systemUptime,
            tC_recv: nil,
            tC_echoSend: nil,
            tP_recv: nil
        )
    }

    private func sendBeaconToChildren() {
        let env = makeBeaconEnvelope()
        guard let data = try? JSONEncoder().encode(env) else { return }
        let framed = data + Data([0x0A])
        for conn in childConnections {
            conn.send(content: framed, completion: .contentProcessed({ _ in }))
        }
    }

    private func requestBeaconBurst(count: Int, spacingMs: Int) {
        guard role == .parent,
              isEnabled,
              connectionMethod != .bluetooth,
              count > 0 else { return }
        beaconBurstCancellable?.cancel()
        isBeaconBurstActive = true
        var remaining = count
        sendBeaconToChildren()
        remaining -= 1
        guard remaining > 0 else {
            isBeaconBurstActive = false
            return
        }
        let interval = max(0.01, Double(spacingMs) / 1000.0)
        beaconBurstCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if remaining <= 0 {
                    self.beaconBurstCancellable?.cancel()
                    self.beaconBurstCancellable = nil
                    self.isBeaconBurstActive = false
                    return
                }
                self.sendBeaconToChildren()
                remaining -= 1
            }
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
    
    // Tap pairing glue
    var tapPairingAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
    }
    private var tapMgr: TapPairingManager?
    @Published var tapStateText: String = "Ready"
    
    // SyncTimerApp.swift
    func beginTapPairing() {
        guard tapPairingAvailable else {
            tapStateText = "Not available on Mac"
            return
        }
        let mgr = TapPairingManager(role: (role == .parent) ? .parent : .child)
        self.tapMgr = mgr

        // Parent: provide live listener endpoint for the tap handoff
        mgr.endpointProvider = { [weak self] in
            guard let self = self, !self.listenerIPAddress.isEmpty else { return nil }
            return TapPairingManager.ResolvedEndpoint(host: self.listenerIPAddress,
                                                      port: self.listenerPort)
        }

        mgr.onResolved = { [weak self] ep in
            guard let self = self else { return }
            if self.role == .child {
                DispatchQueue.main.async {
                    self.peerIP   = ep.host
                    self.peerPort = String(ep.port)
                    self._connectChildOverLAN()
                }
            }
        }

        mgr.start(ephemeral: ["sid": UUID().uuidString])
    }

    
        func cancelTapPairing() {
            tapMgr?.cancel()
            tapMgr = nil
            tapStateText = "Ready"
        }
    
    // MARK: — Lobby properties
    
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
    
    
    
    
    
    /// Keys for parsing Bonjour TXT records
    private enum TXTKey {
        
        static let role      = "role"
        static let timestamp = "ts"
        static let hostUUID  = "hostUUID"
        static let roomLabel = "roomLabel"
    }
    
    /// Called by BonjourSyncManager when a service is resolved
    func handleResolvedService(_ service: NetService, txt: [String: Data]) {
        //lobby lock removed
        
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
        let resolvedHostUUID: UUID? = {
            guard let data = txt[TXTKey.hostUUID],
                  let raw = String(data: data, encoding: .utf8) else {
                return nil
            }
            return UUID(uuidString: raw)
        }()
        if let allowed = joinAllowedHostUUIDs {
            guard let resolvedHostUUID, allowed.contains(resolvedHostUUID) else {
                return
            }
        }
        let peerID = resolvedHostUUID ?? service.name.hashValueAsUUID
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
        case network   = "Wi-Fi"
        case bluetooth = "Nearby"
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
    @Published var joinAllowedHostUUIDs: Set<UUID>? = nil
    @Published var joinSelectedHostUUID: UUID? = nil
    @Published var pendingHostJoinRequest: HostJoinRequestV1? = nil
    @Published var lastJoinHostUUID: UUID? = nil
    @Published var lastJoinLabelCandidate: String? = nil
    @Published var lastJoinDeviceNameCandidate: String? = nil
    @Published var lastJoinLabelRevision: Int? = nil
    @Published var lastBonjourRoomLabel: String? = nil
    @Published var lastBonjourHostUUID: UUID? = nil
    
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

    func applyJoinConstraints(allowed: Set<UUID>, selected: UUID?) {
        joinAllowedHostUUIDs = allowed
        joinSelectedHostUUID = selected
    }

    func setJoinTargetHostUUID(_ uuid: UUID) {
        applyJoinConstraints(allowed: [uuid], selected: uuid)
    }

    func clearJoinConstraints() {
        joinAllowedHostUUIDs = nil
        joinSelectedHostUUID = nil
    }

    func stashJoinLabelCandidate(hostUUID: UUID,
                                 roomLabel: String?,
                                 deviceName: String?,
                                 labelRevision: Int? = nil) {
        lastJoinHostUUID = hostUUID
        lastJoinLabelCandidate = roomLabel
        lastJoinDeviceNameCandidate = deviceName
        lastJoinLabelRevision = labelRevision
    }

    func clearJoinLabelCandidate() {
        lastJoinHostUUID = nil
        lastJoinLabelCandidate = nil
        lastJoinDeviceNameCandidate = nil
        lastJoinLabelRevision = nil
        lastBonjourRoomLabel = nil
        lastBonjourHostUUID = nil
    }

    func connectChildOverLAN(host: String, port: UInt16) {
        guard role == .child else { return }
        peerIP = host
        peerPort = String(port)
        _connectChildOverLAN()
    }

    func connectToResolvedBonjourParent(service: NetService, txt: [String: Data]) -> Bool {
        guard role == .child, connectionMethod == .bonjour else { return false }
        guard let allowed = joinAllowedHostUUIDs else { return false }
        guard let roleData = txt[TXTKey.role],
              let roleString = String(data: roleData, encoding: .utf8),
              roleString == "parent" else { return false }

        let resolvedHostUUID: UUID? = {
            guard let data = txt[TXTKey.hostUUID],
                  let raw = String(data: data, encoding: .utf8) else {
                return nil
            }
            return UUID(uuidString: raw)
        }()
        guard let resolvedHostUUID, allowed.contains(resolvedHostUUID) else { return false }
        if let selected = joinSelectedHostUUID {
            guard resolvedHostUUID == selected else { return false }
        } else if allowed.count > 1 {
            return false
        }
        if let labelData = txt[TXTKey.roomLabel],
           let label = String(data: labelData, encoding: .utf8),
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastBonjourRoomLabel = label
            lastBonjourHostUUID = resolvedHostUUID
        }

        if let connection = clientConnection {
            switch connection.state {
            case .ready, .preparing, .waiting, .setup:
                return true
            default:
                break
            }
        }

        guard let addrs = service.addresses, !addrs.isEmpty else { return false }
        let v4data = addrs.first { data in
            data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress?.assumingMemoryBound(to: sockaddr_storage.self) else {
                    return false
                }
                return base.pointee.ss_family == sa_family_t(AF_INET)
            }
        } ?? addrs.first
        guard let hostPortData = v4data else { return false }

        switch NetService.fromSockAddr(data: hostPortData) {
        case .hostPort(let host, _):
            guard service.port > 0, let port = UInt16(exactly: service.port) else { return false }
            connectChildOverLAN(host: host.debugDescription, port: port)
            return true
        case .none:
            return false
        }
    }
    
    @Published var role: Role         = .parent
    @Published var isEnabled          = false
    @Published var isEstablished      = false {
        didSet {
            if oldValue != isEstablished {
                resetSyncSequence()
            }
        }
    }
    @Published var statusMessage: String = "Not connected"
    @Published var listenPort: String = "50000"
    @Published var peerIP:     String = ""
    @Published var peerPort:   String = "50000"
    
    private var listener: NWListener?
    private var beaconCancellable: AnyCancellable?
    private var beaconBurstCancellable: AnyCancellable?
    private var isBeaconBurstActive = false
    private var childConnections: [NWConnection] = []
    private var clientConnection: NWConnection?
    
    var onReceiveTimer: ((TimerMessage)->Void)? = nil
    var onReceiveSyncMessage: ((SyncEnvelope) -> Void)? = nil
    
    var elapsedProvider: (() -> TimeInterval)? = nil
    var elapsedAtProvider: ((TimeInterval) -> TimeInterval)? = nil
    var isTimerAdvancingProvider: (() -> Bool)? = nil
    var driftDebugLoggingEnabled: Bool = false

    func integrateBonjourConnection(_ conn: NWConnection) {
        clientConnection?.cancel()
        clientConnection = conn
        DispatchQueue.main.async {
            self.isEstablished  = true
            self.statusMessage  = "Bonjour: connected"
        }
        receiveLoop(on: conn)
    }
    
    func getCurrentElapsed() -> TimeInterval { elapsedProvider?() ?? 0 }
    func getElapsedAt(timestamp: TimeInterval) -> TimeInterval {
        elapsedAtProvider?(timestamp) ?? getCurrentElapsed()
    }
    func isTimerAdvancingForDiscipline() -> Bool { isTimerAdvancingProvider?() ?? false }
    
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
                case .bluetooth:
                    bleDriftManager.start()
                    clockSyncService?.reset()
                case .bonjour:
                    bonjourManager.startAdvertising()
                statusMessage = "Bonjour: advertising"
            }
        
                // UltraSync beacons (parent → all), 20 Hz
                if connectionMethod != .bluetooth, (ConnectivityManager.shared != nil) {
                    beaconCancellable?.cancel()
                    beaconCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
                        .autoconnect()
                        .sink { [weak self] _ in
                            guard let self = self, self.isEnabled else { return }
                            guard !self.isBeaconBurstActive else { return }
                            self.sendBeaconToChildren()
                        }
                }
        beginKeepAlive() // <—
    }
    
    private func setupParentConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                // Update UI on main
                DispatchQueue.main.async {
                    self.isEstablished = true
                    self.statusMessage = "Child connected"
                }

                // Send a tiny newline-framed ping to flip the child lamp as soon as bytes flow
                let ping = Data([0x0A]) // newline-delimited empty frame
                conn.send(content: ping,
                          completion: NWConnection.SendCompletion.contentProcessed { _ in })

                // Start receiving after we’ve marked connected
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
        beaconCancellable?.cancel()
        beaconCancellable = nil
        beaconBurstCancellable?.cancel()
        beaconBurstCancellable = nil
        isBeaconBurstActive = false
        clockSyncService?.reset()
        endKeepAlive()   // <—
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
            cancelReconnect()          // clear any stale plan
                _connectChildOverLAN()     // ⟵ single connection path
                beginKeepAlive()
            
        case .bluetooth:
            guard let h = parentIPAddress,
                  let p = parentPort else {
                // No manual endpoint? Use Bonjour (peer-to-peer Wi-Fi) as the transport.
                bonjourManager.startBrowsing()
                statusMessage = "Bonjour: searching…"
                clockSyncService?.reset()
                bleDriftManager.start() // keep BLE drift measurement
                return
            }
            connectToParent(host: h, port: p)
            bonjourManager.startBrowsing()
            clockSyncService?.reset()
            bleDriftManager.start()
            
        case .bonjour:
            bonjourManager.startBrowsing()
            statusMessage = "Bonjour: searching…"
        }
        beginKeepAlive() // <—
    }
    
    func stopChild() {
        cancelReconnect()                // ← stop any scheduled retries
        reconnectAttempt = 0             // ← reset backoff
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
        endKeepAlive()   // <—
        beaconCancellable?.cancel()
                beaconCancellable = nil
                clockSyncService?.reset()
        // Also: when we *become* connected, stop the keep-alive
        func setEstablished(_ connected: Bool) {
            DispatchQueue.main.async {
                self.isEstablished = connected
                if connected { self.endKeepAlive() } else if self.isEnabled { self.beginKeepAlive() }
            }
        }
    }
    
    private func _connectChildOverLAN() {
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
        
        // If there is a stale/non-ready connection hanging around, kill it first.
        if let c = clientConnection, c.state != .ready {
            c.cancel()
            clientConnection = nil
        }
        
        // Fresh connection every attempt
        let endpoint = NWEndpoint.Host(ipString)
        let port     = NWEndpoint.Port(rawValue: portNum)!
        let conn     = NWConnection(host: endpoint, port: port, using: .tcp)
        
        clientConnection = conn
        DispatchQueue.main.async {
            self.statusMessage = "Connecting…"
            self.isEstablished = false
        }
        print("👉 Child attempting connection to \(ipString):\(portNum)… (attempt \(reconnectAttempt + 1))")
        
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .waiting(let err):
                DispatchQueue.main.async { self.statusMessage = "Waiting: \(err.localizedDescription)" }
                print("⌛ Child waiting: \(err.localizedDescription)")
                // Parent may not be listening yet → schedule gentle retry
                self.scheduleReconnect("waiting")
                
            case .preparing:
                print("… Child preparing connection …")
                
            case .ready:
                self.cancelReconnect()
                self.reconnectAttempt = 0

                DispatchQueue.main.async {
                    self.setEstablished(true)                 // ⟵ turn lamp green immediately
                    self.statusMessage = "Connected to \(ipString):\(portNum)"
                }

                // Nudge the parent with one tiny frame so *both* sides see traffic
                let ping = Data([0x0A])                      // \n
                conn.send(content: ping, completion: .contentProcessed { _ in })

                print("✅ Child connected!")
                self.receiveLoop(on: conn)                   // then start reading

                
                
            case .failed(let err):
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Connect failed: \(err.localizedDescription)"
                }
                print("❌ Child failed: \(err.localizedDescription)")
                conn.cancel()
                self.clientConnection = nil
                self.scheduleReconnect("failed")
                
            case .cancelled:
                DispatchQueue.main.async {
                    self.isEstablished = false
                    self.statusMessage = "Disconnected"
                }
                print("🛑 Child cancelled")
                self.clientConnection = nil
                // If user still wants sync, keep trying
                self.scheduleReconnect("cancelled")
                
            default:
                break
            }
        }
        
        conn.start(queue: .global(qos: .background))
    }
    
    
    // ── BROADCAST A JSON-ENCODED MESSAGE TO “ALL CHILDREN” (parent only) ──
        func broadcastToChildren(_ msg: TimerMessage) {
            guard role == .parent else { return }
            var outbound = msg
            if isControlAction(outbound.action) {
                if outbound.actionSeq == nil {
                    actionSeqCounter &+= 1
                    outbound.actionSeq = actionSeqCounter
                }
                outbound.actionKind = outbound.action
            }
            if outbound.stateSeq == nil {
                outbound.stateSeq = actionSeqCounter
            }
            if let actionSeq = outbound.actionSeq {
                outbound.stateSeq = actionSeq
            }
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(outbound) else { return }
            let framed = data + Data([0x0A])   // newline-delimit each JSON packet
    
            // ① Existing LAN path (TCP/Bonjour)
            for conn in childConnections {
                conn.send(content: framed, completion: .contentProcessed({ _ in }))
            }
            ConnectivityManager.shared.send(outbound)
    
            // ② NEW: BLE path (notify subscribed centrals)
            if connectionMethod == .bluetooth {
                bleDriftManager.sendTimerMessageToChildren(outbound)
            }
        }

        func broadcastSyncMessage(_ message: SyncMessage) {
            guard role == .parent else { return }
            syncEnvelopeSeq += 1
            let envelope = SyncEnvelope(seq: syncEnvelopeSeq, message: message)
            broadcastSyncEnvelope(envelope)
        }

        private func broadcastSyncEnvelope(_ envelope: SyncEnvelope) {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(envelope) else { return }
            let framed = data + Data([0x0A])

            for conn in childConnections {
                conn.send(content: framed, completion: .contentProcessed({ _ in }))
            }
            ConnectivityManager.shared.sendSyncEnvelope(envelope)

            if connectionMethod == .bluetooth {
                bleDriftManager.sendSyncEnvelopeToChildren(envelope)
            }
        }
    
    // ── SEND JSON TO PARENT (child only) ─────────────────────────────────
        func sendToParent(_ msg: TimerMessage) {
            guard role == .child else { return }
            let encoder = JSONEncoder()
            ConnectivityManager.shared.send(msg)
    
            switch connectionMethod {
            case .bluetooth:
                // NEW: write to parent's BLE characteristic
                bleDriftManager.sendTimerMessageToParent(msg)
    
            default:
                // existing TCP path
                guard let conn = clientConnection,
                      let data = try? encoder.encode(msg) else { return }
                let framed = data + Data([0x0A])
                conn.send(content: framed, completion: .contentProcessed({ _ in }))
            }
        }

        func sendSyncMessageToParent(_ message: SyncMessage) {
            guard role == .child else { return }
            let envelope = SyncEnvelope(seq: Int(Date().timeIntervalSince1970 * 1000), message: message)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(envelope) else { return }
            let framed = data + Data([0x0A])
            ConnectivityManager.shared.sendSyncEnvelope(envelope)

            switch connectionMethod {
            case .bluetooth:
                bleDriftManager.sendSyncEnvelopeToParent(envelope)
            default:
                guard let conn = clientConnection else { return }
                conn.send(content: framed, completion: .contentProcessed({ _ in }))
            }
        }
    // ── RECEIVE LOOP (both parent and child reuse) ───────────────────────
    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                // ⬇️ turn lamp green on first packet, no button cycle required
                if self.role == .child { self.setEstablished(true) }
                
                // Buffer + extract newline-framed packets across receives.
                let connectionID = ObjectIdentifier(connection)
                var buffer = self.receiveBuffers[connectionID] ?? Data()
                buffer.append(data)

                let delimiter = Data([0x0A])
                var frames: [Data] = []
                while let range = buffer.firstRange(of: delimiter) {
                    let frame = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    frames.append(frame)
                }
                self.receiveBuffers[connectionID] = buffer

                let decoder = JSONDecoder()
                for frame in frames {
                    guard !frame.isEmpty else { continue }
                    if let msg = try? decoder.decode(TimerMessage.self, from: frame) {
                        DispatchQueue.main.async { self.onReceiveTimer?(msg) }
                        continue
                                            }
                                            if let env = try? decoder.decode(SyncEnvelope.self, from: frame) {
                                                DispatchQueue.main.async {
                                                    self.receiveSyncEnvelope(env)
                                                }
                                                continue
                                            }
                                            if self.isEnabled,
                                               self.connectionMethod != .bluetooth,
                                               let env = try? decoder.decode(BeaconEnvelope.self, from: frame) {
                                                // Route via ClockSyncService
                                                let roleIsChild = (self.role == .child)
                                                                if let reply = self.clockSyncService?.handleInbound(env,
                                                                                                                            roleIsChild: roleIsChild,
                                                                                                                            localUUID: self.localPeerID.uuidString) {
                                                    // parent followup → unicast; child echo → to parent
                                                    let payload = (try? JSONEncoder().encode(reply)).map { $0 + Data([0x0A]) }
                                                    if let p = payload {
                                                        if roleIsChild {
                                                            // send to parent
                                                            self.clientConnection?.send(content: p, completion: .contentProcessed({ _ in }))
                                                        } else {
                                                            // parent → target child (match by uuidC suffix in service name if needed, else broadcast)
                                                            // Here: broadcast; the child filters on uuidC.
                                                            for c in self.childConnections { c.send(content: p, completion: .contentProcessed({ _ in })) }
                                                        }
                                                    }
                                                }
                                                continue
                    }
                    print("⚠️ [Sync] decode failed for \(frame.count) bytes")
                }
            }
            
            if isComplete == false && error == nil {
                // Keep reading
                self.receiveLoop(on: connection)
            } else {
                // Connection closed or errored
                let connectionID = ObjectIdentifier(connection)
                self.receiveBuffers.removeValue(forKey: connectionID)
                connection.cancel()
            }
        }
    }

    func receiveSyncEnvelope(_ envelope: SyncEnvelope) {
        guard envelope.seq > lastReceivedSyncSeq else { return }
        lastReceivedSyncSeq = envelope.seq
        #if DEBUG
        switch envelope.message {
        case .sheetSnapshot:
            print("📡 [Sync] received sheet snapshot seq=\(envelope.seq)")
        case .playbackState:
            print("📡 [Sync] received playback state seq=\(envelope.seq)")
        default:
            break
        }
        #endif
        onReceiveSyncMessage?(envelope)
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
struct CueEvent: Identifiable, Equatable, Codable {
    let id: UUID
    var cueTime: TimeInterval
    init(id: UUID = UUID(), cueTime: TimeInterval) {
        self.id = id
        self.cueTime = cueTime
    }
    static func == (lhs: CueEvent, rhs: CueEvent) -> Bool {
        return lhs.id == rhs.id
    }
}

struct MessageEvent: Identifiable, Equatable {
    let id = UUID()
    var messageTime: TimeInterval
    static func == (lhs: MessageEvent, rhs: MessageEvent) -> Bool {
        return lhs.id == rhs.id
    }
}

struct ImageEvent: Identifiable, Equatable {
    let id = UUID()
    var imageTime: TimeInterval
    static func == (lhs: ImageEvent, rhs: ImageEvent) -> Bool {
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
    case message(MessageEvent)
    case image(ImageEvent)
    case restart(RestartEvent)

    var id: UUID {
        switch self {
        case .stop(let s):   return s.id
        case .cue(let c):    return c.id
        case .message(let m): return m.id
        case .image(let i):  return i.id
        case .restart(let r):  return r.id
        }
    }

    var fireTime: TimeInterval {
        switch self {
        case .stop(let s):   return s.eventTime
        case .cue(let c):    return c.cueTime
        case .message(let m): return m.messageTime
        case .image(let i):  return i.imageTime
        case .restart(let r):  return r.restartTime
        }
    }

    /// Helper readable property for the TimerCard’s circles
    var isStop: Bool {
        switch self {
        case .stop:   return true
        case .cue:    return false
        case .message: return false
        case .image:  return false
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
    // NEW: iPad-landscape detector (scope the 32pt rule narrowly)
        private var isPadLandscape: Bool {
            UIDevice.current.userInterfaceIdiom == .pad && UIScreen.main.bounds.width > UIScreen.main.bounds.height
        }

    // NEW: 10.9″/11″ class (exclude 12.9″/13″)
    private var isPad109Landscape: Bool {
        guard isPadLandscape else { return false }
        let nativeMax = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
        // 12.9/13 are 2732px+ in the long edge; treat everything below as “10.9/11 family”
        return nativeMax < 2732
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
        LazyVGrid(
            columns: columns,
            spacing: isPad109Landscape ? 32 : (isPadLandscape ? 52 : vGap)
        ) {
            ForEach(allKeys, id: \.self) { key in
                let keyMinH = isPad109Landscape ? 44 : (isPadLandscape ? 52 : calcKeyHeight())
                if key == .settings {
                    let isActive = parentMode == .settings
                    let circleSize = min(max(44, keyMinH), 76)
                    let iconPt = max(28, min(34, circleSize * 0.46))
                    GlassCircleIconButton(
                        systemName: isActive ? "gearshape.fill" : "gearshape",
                        tint: isActive ? appSettings.flashColor : appSettings.flashColor.opacity(0.55),
                        size: circleSize,
                        iconPointSize: iconPt,
                        imageRotationDegrees: (!appSettings.lowPowerMode && isActive ? 360 : 0),
                        imageRotationAnimation: .easeInOut(duration: 0.5),
                        accessibilityLabel: "Settings"
                    ) {
                        handle(.settings)
                    }
                    .frame(maxWidth: .infinity, minHeight: keyMinH)
                } else {
                    Button {
                        handle(key)
                    } label: {
                        icon(for: key)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: keyMinH
                            )
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
            Haptics.light()
            onKey(key)
            
            
        case .dot:
            guard isEntering else { return }
            Haptics.light()
            onKey(.dot)
            
            
        case .enter:
            guard isEntering else { return }
            Haptics.light()
            onKey(.enter)
            isEntering = false
            
            
        case .settings:
            Haptics.light()
            onSettings()
            
            
        case .chevronLeft:
            guard parentMode == .settings else { return }
            Haptics.selection()
            settingsPage = (settingsPage + 3) % 4
            
            
        case .chevronRight:
            guard parentMode == .settings else { return }
            Haptics.selection()
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
    @State private var suppressNextOpenSettingsTap = false

    /// True when either a countdown or the stopwatch is active.
    var isCounting: Bool
    
    var isSyncEnabled: Bool
    /// Opens the Sync Settings page from the sync bar.
    let onOpenSyncSettings: () -> Void

    /// Toggles sync via the same path used in Settings.
    let onToggleSyncMode: () -> Void

    /// Called when the role switch is finally confirmed.
    let onRoleConfirmed: (SyncSettings.Role) -> Void

    private var isSmallPhone: Bool {
        UIScreen.main.bounds.height < 930
    }

    var body: some View {
        let isDark        = (colorScheme == .dark)
        let activeColor   = isDark ? Color.white : Color.black
        let inactiveColor = Color.gray
        let allowMainViewChanges = settings.allowSyncChangesInMainView
        let roleAccessibilityHint = allowMainViewChanges
            ? "Tap to toggle. Long-press for settings."
            : "Long-press to toggle between child and parent"
        let syncAccessibilityHint = allowMainViewChanges
            ? "Tap to toggle. Long-press for settings."
            : "Long-press to toggle sync mode"
        let roleGesture = LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: TapGesture())
        let syncGesture = LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: TapGesture())

        HStack(spacing: 0) {
            // ── Role toggle ────────────────────────────
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .layoutPriority(1)
            .accessibilityLabel("Switch role")
            .accessibilityHint(roleAccessibilityHint)
            .contentShape(Rectangle())
            .gesture(roleGesture.onEnded { value in
                switch value {
                case .first(true):
                    if allowMainViewChanges {
                        suppressNextOpenSettingsTap = false
                        onOpenSyncSettings()
                    } else {
                        guard !isCounting else {
                            Haptics.warning()
                            suppressNextOpenSettingsTap = true
                            return
                        }
                        suppressNextOpenSettingsTap = true
                        Haptics.light()
                        let newRole: SyncSettings.Role = (syncSettings.role == .parent ? .child : .parent)
                        onRoleConfirmed(newRole)
                    }
                case .second:
                    if allowMainViewChanges {
                        guard !isCounting else { return }
                        guard !isCounting else { Haptics.warning(); return }
                        Haptics.light()
                        let newRole: SyncSettings.Role = (syncSettings.role == .parent ? .child : .parent)
                        onRoleConfirmed(newRole)
                    } else {
                        onOpenSyncSettings()
                    }
                default:
                    break
                }
            })

            // ── Sync/Stop button ─────────────────────────
            Spacer(minLength: 0)
            // ── Sync/Stop + lamp, always 8 pt apart ─────────
            HStack(spacing: 8) {
                // Label mirrors Settings; tap is inert, long-press opens connections
                Text(isSyncEnabled ? "STOP" : "SYNC")
                    .font(.custom("Roboto-SemiBold", size: 24))
                    .foregroundColor(activeColor)
                    .fixedSize()
                let lampState: SyncStatusLamp.LampState =
                    syncSettings.isEstablished ? .connected :
                    (syncSettings.isEnabled ? .streaming : .off)

                SyncStatusLamp(
                    state: lampState,
                    size: 18,
                    highContrast: settings.highContrastSyncIndicator
                )

            }
            .contentShape(Rectangle())
            .accessibilityHint(syncAccessibilityHint)
            .gesture(syncGesture.onEnded { value in
                switch value {
                case .first(true):
                    if allowMainViewChanges {
                        suppressNextOpenSettingsTap = false
                        onOpenSyncSettings()
                    } else {
                        suppressNextOpenSettingsTap = true
                        Haptics.light()
                        onToggleSyncMode()
                    }
                case .second:
                    if allowMainViewChanges {
                        Haptics.light()
                        onToggleSyncMode()
                    } else {
                        onOpenSyncSettings()
                    }
                default:
                    break
                }
            })
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard allowMainViewChanges == false else { return }
            guard suppressNextOpenSettingsTap == false else {
                suppressNextOpenSettingsTap = false
                return
            }
            onOpenSyncSettings()
        }
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
        case .message(let m):
                    return "\(index). Message at \(timeString(m.messageTime))"
                case .image(let i):
                    return "\(index). Image at \(timeString(i.imageTime))"
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
extension TimeInterval {
    /// Minutes-only when under 1h *and* the user toggle is OFF; otherwise HH:MM:SS.CC.
    /// Preserves the sign for countdown.
    func formattedAdaptiveCS(alwaysShowHours: Bool) -> String {
        let t   = self
        let neg = t < 0
        let absT = abs(t)

        // match your existing rounding to centiseconds
        let cs = Int((absT * 100).rounded())
        let h  = cs / 360_000
        let m  = (cs / 6_000) % 60
        let s  = (cs / 100) % 60
        let c  = cs % 100

        let body: String = {
            if alwaysShowHours || absT >= 3600.0 {
                return String(format: "%02d:%02d:%02d.%02d", h, m, s, c)
            } else {
                let mm = cs / 6_000 // total minutes (keeps digit-entry mapping intact)
                return String(format: "%02d:%02d.%02d", mm, s, c)
            }
        }()
        return neg ? "-" + body : body
    }
}
private struct RoundedCorners: Shape {
    var radius: CGFloat = 12
    var corners: UIRectCorner = []
    func path(in rect: CGRect) -> Path {
        let p = UIBezierPath(roundedRect: rect,
                             byRoundingCorners: corners,
                             cornerRadii: CGSize(width: radius, height: radius))
        return Path(p.cgPath)
    }
}

// ─────────────────────────────────────────────────────────────────────
// MARK: - TimerCard   (single-Text flash — no ghosting)
// ─────────────────────────────────────────────────────────────────────
struct TimerCard: View {
    
    
    // near the other derived flags in TimerCard
    private var isPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @EnvironmentObject private var cueBadge: CueBadgeState
    @EnvironmentObject private var clockSync: ClockSyncService
    @EnvironmentObject private var cueDisplay: CueDisplayController
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings
    @Environment(\.phoneStyleOnMiniLandscape) private var phoneStyleOnMiniLandscape
    @Environment(\.badgeRowLift) private var badgeRowLift

    // ── New: detect landscape (use true window size on iPad/split)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.containerSize) private var containerSize
        private var isLandscape: Bool {
            if containerSize != .zero { return containerSize.width > containerSize.height }
            return verticalSizeClass == .compact
        }
    
    
    // Mini-iPad landscape: strip chrome/overlays/labels and lift the badge row
      let showCardChrome: Bool = true              // controls any internal background/shadow
      let showTapZoneOverlays: Bool = true         // disables the left/right vertical tints & dividers
      let showSectionLabels: Bool = true           // hides "SYNC VIEW" / "EVENTS VIEW" labels
      let badgeRowYOffset: CGFloat = 0             // vertical nudge for the badges ro

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
    private enum MessagePlacement {
        case gap, circles, modeBar, header
    }
    private enum CueBadgeMode {
        case localDismissible
        case remoteLocked
    }

    // ── Flags for hint flashes ───────────────────────────────────────
    private var shouldFlashLeft: Bool {
        mode == .stop && stopStep == 0
    }
    private var shouldFlashRight: Bool {
        mode == .stop && stopStep == 1
    }
    private var cueBadgeMode: CueBadgeMode {
        let isRemote = (syncSettings.role == .child || settings.simulateChildMode) && cueBadge.broadcast
        return isRemote ? .remoteLocked : .localDismissible
    }
    private var isChildTabLockActive: Bool {
        (syncSettings.role == .child) && syncSettings.isEnabled && syncSettings.isEstablished
    }
    private var eventsTabDisabled: Bool {
        isChildTabLockActive && mode == .sync
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
    var onClearEvents: (() -> Void)? = nil
    @State private var isMessageExpanded = false
    @Namespace private var rehearsalMarkNamespace

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
        var d = digits
        while d.count < 8 { d.insert(0, at: 0) }   // keep your 8-digit HHMMSSCC model

        let h  = d[0] * 10 + d[1]
        let m  = d[2] * 10 + d[3]
        let s  = d[4] * 10 + d[5]
        let cc = d[6] * 10 + d[7]

        let totalSeconds = h * 3600 + m * 60 + s

        if settings.showHours || totalSeconds >= 3600 {
            return String(format: "%02d:%02d:%02d.%02d", h, m, s, cc)
        } else {
            let mm = h * 60 + m   // ← purely a display fold; entry/backspace logic stays HHMMSSCC
            return String(format: "%02d:%02d.%02d", mm, s, cc)
        }
    }
    

    // MARK: - Connectivity status adapter for TimerStatusStrip
        private func makeStatus() -> TimerConnectivityStatus {
            // Transport (CONNECT tab selection)
            let selected: TimerConnectivityStatus.SyncMode = {
                let m = String(describing: syncSettings.connectionMethod).lowercased()
                if m.contains("ble") || m.contains("bluetooth") || m.contains("nearby") { return .bluetooth }
                if m.contains("lan") || m.contains("bonjour") || m.contains("wifi") { return .lan }
                return .off
            }()
    
            // Role / child count
            let isParentNow = (syncSettings.role == .parent)
            let childCount  = isParentNow ? syncSettings.peers.filter { $0.role == .child  }.count : 0
    
            // Watch reachability
            // Watch reachability (safe on all platforms)
            #if canImport(WatchConnectivity)
            let watchConnected: Bool = {
                guard WCSession.isSupported() else { return false }
                let s = WCSession.default
                return s.activationState == .activated && (s.isPaired || s.isReachable)
            }()
            #else
            let watchConnected = false
            #endif

    
            // ---- Signal strength → 0…1 (averaged RSSI across relevant peers) ----
            func mapRSSITo01(_ rssi: Int) -> Double {
                let clamped = max(-95, min(-45, rssi))          // typical BLE/Wi-Fi window
                return (Double(clamped) + 95.0) / 50.0          // −95→0.0, −45→1.0
            }
            let relevantPeers = syncSettings.peers.filter { isParentNow ? ($0.role == .child) : ($0.role == .parent) }
            let strength01: Double? = {
                let values = relevantPeers.map { $0.signalStrength }
                guard !values.isEmpty else { return nil }
                let avg = Double(values.reduce(0, +)) / Double(values.count)
                return mapRSSITo01(Int(avg.rounded()))
            }()
    
            // ---- Drift (ms) best-effort: try any exposed “drift/skew/offset” Double on managers ----
            func bestEffortDriftMs() -> Double? {
                // If you have a dedicated property (e.g. clockSyncService.currentDriftMs),
                // replace this whole function with that property.
                func probe(_ any: Any?) -> Double? {
                    guard let any else { return nil }
                    let mirror = Mirror(reflecting: any)
                    for child in mirror.children {
                        guard let label = child.label?.lowercased() else { continue }
                        if (label.contains("drift") || label.contains("skew") || label.contains("offset")),
                           let v = child.value as? Double { return v }
                        if (label.contains("drift") || label.contains("skew") || label.contains("offset")),
                           let vOpt = child.value as? Double?, let v = vOpt { return v }
                    }
                    return nil
                }
                return probe(syncSettings.clockSyncService) ??
                       probe(syncSettings.bleDriftManager)  ??
                       probe(syncSettings.bonjourManager)
            }
            let driftMs = bestEffortDriftMs() ?? .nan   // NaN → “— ms” until real value exists
    
            return TimerConnectivityStatus(
                syncMode: selected,
                isStreaming: syncSettings.isEnabled,
                isConnected: syncSettings.isEstablished,
                isParent: isParentNow,
                childCount: childCount,
                isWatchConnected: watchConnected,
                strength01: strength01,
                driftMs: driftMs,
                highContrast: settings.highContrastSyncIndicator
            )
        }
    private func currentSyncMode() -> TimerConnectivityStatus.SyncMode {
        // Robust to enum name changes; uses description text
        let method = String(describing: syncSettings.connectionMethod).lowercased()
        if method.contains("ble") || method.contains("bluetooth") || method.contains("nearby") { return .bluetooth }
        if method.contains("lan") || method.contains("bonjour") || method.contains("wifi") { return .lan }
        return .off
    }

    private func isSearchingNow() -> Bool {
        // Show “searching” while enabled but not established; no extra types needed
        return syncSettings.isEnabled && !syncSettings.isEstablished
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
                let isPadLike = (containerSize != .zero ? containerSize.width : UIScreen.main.bounds.width) >= 700
                let horizontalInset: CGFloat = isPadLike ? 0 : (isLandscape ? 10 : 16)
                let innerW = geo.size.width - (horizontalInset * 2)                // “fs” is the base font‐size for the big timer text; scale it up in landscape:
                let fsPortrait = innerW / 4.6
                let fs = isLandscape ? (fsPortrait * 1.4) : fsPortrait
                let isCompactWidth = (geo.size.width <= 389)

                // Now pick all the other sizes according to the same scale:
                let hintFontSize: CGFloat = isLandscape ? 32 : 24    // for “START POINT” / “DURATION”
                let subTextFontSize: CGFloat = isLandscape ? 28 : 20 // for “SYNCING…”, circles’ “S/C/R” labels
                let circleDiameter: CGFloat = isLandscape ? 30 : 18  // for the 5 event circles
                let stopTimerFontSize: CGFloat = isLandscape ? 30 : 24 // for the small stop‐timer underneath
                let messagePayload: CueSheet.MessagePayload? = cueDisplay.messagePayload
                let imagePayload: CueSheet.ImagePayload? = cueDisplay.image
                let rehearsalMarkText: String? = cueDisplay.rehearsalMarkText
                let overlayAnimationToken = "\(messagePayload?.text ?? "")|\(rehearsalMarkText ?? "")|\(imagePayload?.assetID.uuidString ?? "")"
                let placement = messagePlacement(for: geo.size)
                let showCollapsedMessage = false
                let fadeAnimation = Animation.easeInOut(duration: 0.25)
                let cardCornerRadius: CGFloat = 12
                let cardWidth = geo.size.width - (horizontalInset * 2)
                let cardHeight = isLandscape ? geo.size.height : 190
                let showOverlayBanner = (messagePayload != nil || rehearsalMarkText != nil) && !isMessageExpanded
                let showExpandedOverlay = isMessageExpanded && (messagePayload != nil || rehearsalMarkText != nil)

                let cardBody = ZStack {
                    // ── (A) Card background with drop shadow ─────────────────
                    if !isLandscape || isPadLayout {
                        Group {
                            if settings.lowPowerMode {
                                // Low-Power: flat fill only (no blur/material)
                                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                    .fill(isDark ? Color.black : Color.white)
                                
                                
                            } else {
                                // Normal: material + subtle “glass” cues (safe on all iOS 16/17)
                                let corner: CGFloat = cardCornerRadius
                                let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
                                
                                shape
                                    .fill(.ultraThinMaterial)
                                 //   .glassEffect()
                                
                                // light “glass” rim stroke (looks premium, cheap to render)
                                    .overlay(
                                        shape
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(colorScheme == .light ? 0.18 : 0.08),
                                                        Color.white.opacity(0.03)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                // soft internal highlight for light mode only
                                    .overlay(
                                        shape
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(colorScheme == .light ? 0.10 : 0.0),
                                                        Color.white.opacity(0.00)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                                // ⬇️ PINNED overlays on the shape's own bounds
                                    .overlay(alignment: .bottomLeading) {
                                        if (!isLandscape || isPadLayout && !phoneStyleOnMiniLandscape) && mode == .stop {
                                            GeometryReader { p in
                                                let tintH = floor(p.size.height * 0.4)
                                                VStack(spacing: 0) {
                                                    Spacer()                                // ↓ pin to bottom
                                                    HStack(spacing: 0) {
                                                        LinearGradient(colors: [Color.gray.opacity(0.125), .clear],
                                                                       startPoint: .bottom, endPoint: .top)
                                                        .frame(width: floor(p.size.width * 0.5), height: tintH)
                                                        .mask(LinearGradient(colors: [.black, .clear],
                                                                             startPoint: .trailing, endPoint: .leading))
                                                        .clipShape(RoundedCorners(radius: corner, corners: [.bottomLeft]))
                                                        Spacer()                            // ← keep on left half
                                                    }
                                                }
                                            }
                                            .allowsHitTesting(false)
                                        }
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if (!isLandscape || isPadLayout && !phoneStyleOnMiniLandscape) && mode == .sync {
                                            GeometryReader { p in
                                                let tintH = floor(p.size.height * 0.4)
                                                VStack(spacing: 0) {
                                                    Spacer()                                // ↓ pin to bottom
                                                    HStack(spacing: 0) {
                                                        Spacer()                            // → keep on right half
                                                        LinearGradient(colors: [Color.gray.opacity(0.125), .clear],
                                                                       startPoint: .bottom, endPoint: .top)
                                                        .frame(width: floor(p.size.width * 0.5), height: tintH)
                                                        .mask(LinearGradient(colors: [.black, .clear],
                                                                             startPoint: .leading, endPoint: .trailing))
                                                        .clipShape(RoundedCorners(radius: corner, corners: [.bottomRight]))
                                                    }
                                                }
                                            }
                                            .allowsHitTesting(false)
                                        }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if !isLandscape || isPadLayout && !phoneStyleOnMiniLandscape {
                                            GeometryReader { p in
                                                let lineH = floor(p.size.height * 0.4)
                                                let px    = 1.5 / UIScreen.main.scale
                                                
                                                VStack(spacing: 0) {
                                                    Spacer() // ↓ pins the divider to the bottom of the GeometryReader
                                                    Rectangle()
                                                        .fill(
                                                            LinearGradient(colors: [Color.gray.opacity(0.18), .clear],
                                                                           startPoint: .bottom, endPoint: .top)
                                                        )
                                                        .frame(width: px, height: lineH)  // true hairline
                                                        .offset(y: -px * 0.5)             // half-pixel snap
                                                        .frame(maxWidth: .infinity, alignment: .center)
                                                }
                                            }
                                            .allowsHitTesting(false)
                                        }
                                    }
                                
                            }
                        }
                        .ignoresSafeArea(edges: .horizontal)
                        
                        
                        
                        if settings.flashStyle == .tint && flashZero {
                            
                            
                            flashColor
                                .ignoresSafeArea()
                                .transition(.opacity)
                                .animation(.easeInOut(duration: Double(settings.flashDurationOption) / 1000), value: flashZero)
                                .background(Color(.systemBackground))
                                .cornerRadius(cardCornerRadius)
                                .opacity(0.5)
                        }
                    }
                    
                    // ── (B) Full vertical stack ────────────────────────────
                    VStack(spacing: 0) {
                        // B.1) Top hints “START POINT” / “DURATION” ────────────
                        if let payload = messagePayload, showCollapsedMessage, placement == .header {
                            CollapsedMessageBanner(payload: payload, onDismiss: dismissMessage, onExpand: expandMessage)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                                .transition(.opacity)
                                .animation(fadeAnimation, value: overlayAnimationToken)
                        } else {
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
                            .transition(.opacity)
                            .animation(fadeAnimation, value: overlayAnimationToken)
                        }
                        
                        
                        // B.2) Main time + dash + flash overlays ───────────────
                        HStack(spacing: 4) {
                            // the “–” prefix
                            Text("-")
                                .font(.custom("Roboto-Light", size: fs))
                                .foregroundColor(isCountdownActive ? .black : .gray)
                            
                            
                            // ZStack so we can overlay “flash” text on top of the normal timer text
                            ZStack {
                                // Erase the heavy conditional branches so the type-checker chills out
                                let mainText: AnyView = {
                                    if mode == .stop && (phase == .idle || phase == .paused) {
                                        return AnyView(
                                            ZStack {
                                                Text("88:88:88.88")
                                                    .font(.custom("Roboto-Regular", size: fs))
                                                    .minimumScaleFactor(0.5)
                                                    .opacity(0) // width-keeper
                                                Text(rawString(from: stopDigits))
                                                    .font(.custom("Roboto-Regular", size: fs))
                                                    .minimumScaleFactor(0.5)
                                                    .foregroundColor(txtMain)
                                            }
                                        )
                                    } else if mode == .sync && phase == .idle && !syncDigits.isEmpty {
                                        return AnyView(
                                            ZStack {
                                                Text("88:88:88.88")
                                                    .font(.custom("Roboto-Regular", size: fs))
                                                    .minimumScaleFactor(0.5)
                                                    .opacity(0) // width-keeper
                                                Text(rawString(from: syncDigits))
                                                    .font(.custom("Roboto-Regular", size: fs))
                                                    .minimumScaleFactor(0.5)
                                                    .foregroundColor(txtMain)
                                            }
                                        )
                                    } else {
                                        // Running or after idle
                                        
                                        let fullString = formatTimerString(mainTime, alwaysShowHours: settings.showHours)
                                        return AnyView(
                                            ZStack(alignment: .center) {
                                                // width-keeper to match HH layout even when showing MM
                                                Text("88:88:88.88")
                                                    .font(.custom("Roboto-Regular", size: fs))
                                                    .minimumScaleFactor(0.5)
                                                    .opacity(0)
                                                // visible text
                                                Text(fullString)
                                                    .font(.custom("Roboto-Regular", size: fs))
                                                    .minimumScaleFactor(0.5)
                                                    .foregroundColor(
                                                        (flashStyle == .fullTimer && flashZero) ? flashColor : txtMain
                                                    )
                                            }
                                        )
                                    }
                                }()
                                mainText
                                
                                
                                
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
                        
                        if let payload = messagePayload, showCollapsedMessage, placement == .gap {
                            CollapsedMessageBanner(payload: payload, onDismiss: dismissMessage, onExpand: expandMessage)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 4)
                                .transition(.opacity)
                                .animation(fadeAnimation, value: overlayAnimationToken)
                        }
                        
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
                        if let payload = messagePayload, showCollapsedMessage, placement == .circles {
                            CollapsedMessageBanner(payload: payload, onDismiss: dismissMessage, onExpand: expandMessage)
                                .padding(.horizontal, 12)
                                .transition(.opacity)
                                .animation(fadeAnimation, value: overlayAnimationToken)
                        } else {
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
                                            let glyphSize = circleDiameter * 0.56

                                            switch events[idx] {
                                            case .stop:
                                                ZStack {
                                                    Circle()
                                                        .fill(flashColor)
                                                        .frame(width: circleDiameter,
                                                               height: circleDiameter)
                                                    Image(systemName: "playpause")
                                                        .font(.system(size: glyphSize, weight: .semibold))
                                                        .symbolRenderingMode(.hierarchical)
                                                        .foregroundStyle(isDark ? Color.black : Color.white)
                                                        .contentTransition(.symbolEffect(.replace))
                                                        .ifAvailableSymbolReplace()

                                                }
                                            case .cue:
                                                ZStack {
                                                    Circle()
                                                        .stroke(flashColor, lineWidth: isLandscape ? 1.5 : 1)
                                                        .frame(width: circleDiameter,
                                                               height: circleDiameter)
                                                    Image(systemName: "bolt.fill")
                                                        .font(.system(size: glyphSize, weight: .semibold))
                                                        .symbolRenderingMode(.hierarchical)
                                                        .foregroundStyle(flashColor)
                                                        .contentTransition(.symbolEffect(.replace))
                                                        .ifAvailableSymbolReplace()

                                                }
                                            case .restart:
                                                ZStack {
                                                    Circle()
                                                        .stroke(flashColor, lineWidth: isLandscape ? 1.5 : 1)
                                                        .frame(width: circleDiameter,
                                                               height: circleDiameter)
                                                    Image(systemName: "arrow.counterclockwise")
                                                        .font(.system(size: glyphSize, weight: .semibold))
                                                        .symbolRenderingMode(.hierarchical)
                                                        .foregroundStyle(isDark ? Color.white : Color.black)
                                                        .contentTransition(.symbolEffect(.replace))
                                                        .ifAvailableSymbolReplace()

                                                }
                                            case .message:
                                                ZStack {
                                                    Circle()
                                                        .fill(flashColor.opacity(0.25))
                                                        .frame(width: circleDiameter,
                                                               height: circleDiameter)
                                                    Circle()
                                                        .stroke(flashColor, lineWidth: isLandscape ? 1.5 : 1)
                                                        .frame(width: circleDiameter,
                                                               height: circleDiameter)
                                                    Image(systemName: "text.quote")
                                                        .font(.system(size: glyphSize, weight: .semibold))
                                                        .symbolRenderingMode(.hierarchical)
                                                        .foregroundStyle(isDark ? Color.white : Color.black)
                                                        .contentTransition(.symbolEffect(.replace))
                                                        .ifAvailableSymbolReplace()

                                                }
                                                .accessibilityLabel("Message event")
                                            case .image:
                                                ZStack {
                                                    Circle()
                                                        .stroke(flashColor, lineWidth: isLandscape ? 1.5 : 1)
                                                        .frame(width: circleDiameter,
                                                               height: circleDiameter)
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .stroke(flashColor, lineWidth: isLandscape ? 1.2 : 1)
                                                        .frame(width: circleDiameter * 0.55,
                                                               height: circleDiameter * 0.42)
                                                    Image(systemName: "mountain.2")
                                                        .font(.system(size: circleDiameter * 0.34, weight: .semibold))
                                                        .symbolRenderingMode(.hierarchical)
                                                        .foregroundStyle(isDark ? Color.white : Color.black)
                                                        .contentTransition(.symbolEffect(.replace))
                                                        .ifAvailableSymbolReplace()

                                                }
                                                .accessibilityLabel("Image event")
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
                                
                                Text(stopActive
                                     ? stopRemaining.formattedAdaptiveCS(alwaysShowHours: settings.showHours)
                                     : (settings.showHours ? "00:00:00.00" : "00:00.00"))
                                .font(.custom("Roboto-Regular", size: stopTimerFontSize))
                                .foregroundColor(
                                    stopActive
                                    ? flashColor
                                    : (mode == .sync ? txtSec : txtMain)
                                )
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .transition(.opacity)
                            .animation(fadeAnimation, value: overlayAnimationToken)
                        }
                        
                        Spacer(minLength: 4)
                        if !phoneStyleOnMiniLandscape {
                            // B.4) Bottom labels “EVENTS VIEW” / “SYNC VIEW” ──────
                            if let payload = messagePayload, showCollapsedMessage, placement == .modeBar {
                                CollapsedMessageBanner(payload: payload, onDismiss: dismissMessage, onExpand: expandMessage)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 6)
                                    .transition(.opacity)
                                    .animation(fadeAnimation, value: overlayAnimationToken)
                            } else {
                                HStack {
                                    Text("EVENTS VIEW")
                                        .foregroundColor(mode == .stop ? txtMain : txtSec)
                                        .opacity(eventsTabDisabled ? 0.35 : 1.0)
                                    Spacer()
                                    Text("SYNC VIEW")
                                        .foregroundColor(mode == .sync ? txtMain : txtSec)
                                }
                                .font(.custom("Roboto-Regular", size: isLandscape ?  28 : 24))
                                .padding(.horizontal, 12)
                                .padding(.bottom, 6)
                                .transition(.opacity)
                                .animation(fadeAnimation, value: overlayAnimationToken)
                            }
                        }
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
                    if !isLandscape || isPadLayout && !phoneStyleOnMiniLandscape {
                        HStack(spacing: 0) {
                            // Left half: tap → EVENTS (stop)
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture {
                                    guard !eventsTabDisabled else { return }
                                    mode = .stop
                                    lightHaptic()
                                }
                                .allowsHitTesting(!eventsTabDisabled)
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
                let baseCard = cardBody
                    .frame(
                        width: cardWidth,
                        height: cardHeight
                    )
                    // ── Connectivity strip (LED-style) — match badge height; sits between big timer and stop-down timer
                    .overlay(alignment: .topTrailing) {
                        // Use the SAME vertical math as the badge so they line up
                        let badgeTopOffset: CGFloat = {
                            let base = isLandscape ? fs * 0.90 : fs * 0.78
                            let compactBump: CGFloat = isCompactWidth ? 8 : 12
                            return base + compactBump + 14
                        }()

                        TimerStatusStrip(status: makeStatus())
                            .padding(.trailing, 28)          // same as “DURATION” padding
                            .padding(.top, badgeTopOffset + 18) // exactly the badge’s vertical track
                            .allowsHitTesting(false)
                    }

                                    // ── Badge overlay (does not affect layout) ───────────────
                                    .overlay(alignment: .topLeading) {
                                        if let label = cueBadge.label {
                                            // Heuristic: place between big timer line and the 5 circles.
                                            // Uses fs (big font size), width compactness, and orientation.
                                            let badgeTopOffset: CGFloat = {
                                                let base = isLandscape ? fs * 0.90 : fs * 0.78
                                                let compactBump: CGFloat = isCompactWidth ? 8 : 12
                                                return base + compactBump + 14   // +14 ≈ hint/spacing cushion
                                            }()
                                            let lockSymbol = (UIImage(systemName: "lock.circle.fill") != nil)
                                            ? "lock.circle.fill"
                                            : "lock.fill"
                                            HStack(spacing: 8) {
                                                Image(systemName: cueBadge.broadcast
                                                      ? "antenna.radiowaves.left.and.right"
                                                      : "doc.text")
                                                Text(
                                                    cueBadgeMode == .remoteLocked
                                                    ? "streaming '\(label)'"
                                                    : "'\(label)' loaded"
                                                )
                                                    .font(.footnote.weight(.semibold))
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                                if cueBadgeMode == .localDismissible {
                                                    Button {
                                                        withAnimation(.easeOut(duration: 0.2)) {
                                                            // clear events first, then clear badge
                                                            onClearEvents?()
                                                        }
                                                    } label: {
                                                        Image(systemName: "xmark")
                                                            .font(.caption2)
                                                            .foregroundStyle(flashColor)   // ← match app flash color
                                                    }
                                                } else {
                                                    Image(systemName: lockSymbol)
                                                        .font(.caption2)
                                                        .foregroundStyle(flashColor)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4) // ~85% height vs before
                                                    .background(.ultraThinMaterial,
                                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .stroke(
                                                                Color.primary.opacity(0.12),
                                                                style: StrokeStyle(
                                                                    lineWidth: 1,
                                                                    dash: cueBadgeMode == .remoteLocked ? [3, 3] : []
                                                                )
                                                            )
                                                    )
                                                    // Pin to the same left inset as your timer/circles (12pt)
                                                                    .padding(.leading, 12)
                                                                    .offset(y: -4)

                                                                    // Drop ~12pt lower than before
                                                                    .padding(.top, badgeTopOffset + 12)
                                                                    // Ensure it hugs the left; no accidental centering
                                                                    .frame(maxWidth: .infinity, alignment: .leading)

                                                                    .transition(.opacity)                                            .allowsHitTesting(true)
                                                                    .accessibilityElement(children: .combine)
                                                                    .accessibilityLabel(
                                                                        cueBadgeMode == .remoteLocked
                                                                        ? "Cue sheet from parent (locked)"
                                                                        : "Cue sheet loaded"
                                                                    )
                                        }
                                    }

                    .animation(
                        {
                            if #available(iOS 17, *) { .snappy(duration: 0.26, extraBounce: 0.25) }
                            else { .easeInOut(duration: 0.26) }
                        }(),
                        value: mode
                    )

                ZStack {
                    baseCard
                    if let imagePayload {
                        TimerCardDisplayEventOverlay(
                            message: nil,
                            image: imagePayload,
                            rehearsalMark: nil,
                            cornerRadius: cardCornerRadius,
                            namespace: rehearsalMarkNamespace,
                            onDismiss: {
                                dismissImage()
                            }
                        )
                        .transition(.opacity)
                        .animation(fadeAnimation, value: overlayAnimationToken)
                        .frame(width: cardWidth, height: cardHeight)
                        .zIndex(1)
                    }
                    if showExpandedOverlay {
                        TimerCardDisplayEventOverlay(
                            message: messagePayload,
                            image: nil,
                            rehearsalMark: rehearsalMarkText,
                            cornerRadius: cardCornerRadius,
                            namespace: rehearsalMarkNamespace,
                            onDismiss: {
                                dismissMessage()
                            }
                        )
                        .transition(.opacity)
                        .animation(fadeAnimation, value: overlayAnimationToken)
                        .frame(width: cardWidth, height: cardHeight)
                        .zIndex(2)
                    }
                }
                .frame(
                    width: cardWidth,
                    height: cardHeight
                )
                .overlay(alignment: .topLeading) {
                    if showOverlayBanner {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .allowsHitTesting(false)
                            ScoreCueBanner(
                                message: messagePayload,
                                rehearsalMark: rehearsalMarkText,
                                namespace: rehearsalMarkNamespace,
                                onDismiss: dismissMessage,
                                onToggleExpand: expandMessage
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                        .transition(.opacity)
                        .animation(fadeAnimation, value: overlayAnimationToken)
                        .zIndex(3)
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Elapsed time: \(mainTime.formattedCS)")
            .accessibilityHint(
              mode == .stop
                ? "Tap left half for Events View, right half for Sync View"
                : "Tap to switch views"
            )
            .onChange(of: cueDisplay.messagePayload) { _ in
                resetExpansion()
                collapseOverlayIfNeeded()
            }
            .onChange(of: cueDisplay.rehearsalMarkText) { _ in
                resetExpansion()
                collapseOverlayIfNeeded()
            }
            .onChange(of: cueDisplay.image) { _ in
                resetExpansion()
                collapseOverlayIfNeeded()
            }
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
    
    private func dismissMessage() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isMessageExpanded = false
            cueDisplay.isExpanded = false
            cueDisplay.dismiss()
        }
    }
    
    private func dismissImage() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isMessageExpanded = false
            cueDisplay.isExpanded = false
            cueDisplay.dismiss()
        }
    }
    
    private func expandMessage() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isMessageExpanded = true
            cueDisplay.isExpanded = true
        }
    }

    private func resetExpansion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isMessageExpanded = false
            cueDisplay.isExpanded = false
        }
    }

    private func collapseOverlayIfNeeded() {
        guard cueDisplay.messagePayload == nil, cueDisplay.rehearsalMarkText == nil else { return }
        resetExpansion()
    }
    
    private func messagePlacement(for size: CGSize) -> MessagePlacement {
        let h = size.height
        if h >= 190 { return .gap }
        if h >= 170 { return .circles }
        if h >= 150 { return .modeBar }
        return .header
    }
    
    private struct CollapsedMessageBanner: View {
        let payload: CueSheet.MessagePayload
        var onDismiss: () -> Void
        var onExpand: () -> Void
        
        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                Text(attributedText(from: payload))
                    .lineLimit(2)
                    .accessibilityLabel("Message")
                    .accessibilityValue(payload.text)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: onExpand)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Message")
            .accessibilityValue(payload.text)
        }
    }
    
    private struct RehearsalMarkGlyph: View {
        let text: String
        var namespace: Namespace.ID?
        var isBadge: Bool = false
        var isSource: Bool = true

        var body: some View {
            let corner: CGFloat = isBadge ? 3 : 4
            let base = Text(text)
                .font(.system(size: isBadge ? 12 : 14, weight: .heavy, design: .rounded))
                .padding(.horizontal, isBadge ? 8 : 10)
                .padding(.vertical, isBadge ? 4 : 6)
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.primary.opacity(0.32))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.primary.opacity(0.78), lineWidth: 3)
                )
                .accessibilityLabel("Rehearsal mark \(text)")

            if let namespace {
                return AnyView(base.matchedGeometryEffect(id: "rehearsalMarkGlyph", in: namespace, isSource: isSource))
            } else {
                return AnyView(base)
            }

        }
    }

    private struct ReservedRehearsalMarkSlot: View {
        let mark: String?
        var namespace: Namespace.ID?
        var body: some View {
            Group {
                if let mark {
                    RehearsalMarkGlyph(text: mark, namespace: namespace)
                } else {
                    Color.clear
                        .frame(width: 44, height: 32)
                }
            }
            .frame(width: 54, alignment: .leading)
        }
    }

    private struct ScoreCueBanner: View {
        let message: CueSheet.MessagePayload?
        let rehearsalMark: String?
        var namespace: Namespace.ID
        var onDismiss: () -> Void
        var onToggleExpand: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                ReservedRehearsalMarkSlot(mark: rehearsalMark, namespace: namespace)
                if let message {
                    Text(attributedText(from: message))
                        .font(.body.italic())
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Message")
                        .accessibilityValue(message.text)
                } else {
                    Spacer(minLength: 0)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: onToggleExpand)
            .accessibilityElement(children: .combine)
        }
    }

    private struct TimerCardDisplayEventOverlay: View {
        let message: CueSheet.MessagePayload?
        let image: CueSheet.ImagePayload?
        let rehearsalMark: String?
        let cornerRadius: CGFloat
        var namespace: Namespace.ID?
        var onDismiss: () -> Void
        @State private var uiImage: UIImage?
        @State private var imageLoadToken: UUID?
        @State private var showMissingImage = false
        
        var body: some View {
            ZStack {
                overlayContent
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(8)
                        }
                        .accessibilityLabel("Dismiss")
                    }
                    Spacer(minLength: 0)
                }
                .padding(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.thinMaterial.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .onAppear(perform: loadImageIfNeeded)
            .onChange(of: image?.assetID) { _ in loadImageIfNeeded() }
        }
        
        @ViewBuilder
        private var overlayContent: some View {
            if let payload = image {
                GeometryReader { proxy in
                    let horizontalPadding: CGFloat = 16
                    let containerWidth = max(0, proxy.size.width - (horizontalPadding * 2))

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 12) {
                            Group {
                                if let uiImage {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: containerWidth)
                                } else if showMissingImage {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 28))
                                            .foregroundColor(.secondary)
                                        Text("Image unavailable")
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: containerWidth)
                                } else {
                                    VStack {
                                        ProgressView()
                                  //      Text("Image unavailable")
                                            //           .font(.body.weight(.semibold))
                                    }
                                    .frame(width: containerWidth)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 12)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            } else if message != nil || rehearsalMark != nil {
                VStack(spacing: 12) {
                    ScrollView {
                        HStack(alignment: .top, spacing: 12) {
                            ReservedRehearsalMarkSlot(mark: rehearsalMark, namespace: namespace)
                            if let message {
                                Text(attributedText(from: message))
                                    .font(.body.italic())
                                    .lineSpacing(5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        
        private var accessibilityLabel: String {
            if message != nil { return "Message" }
            if image != nil { return "Image" }
            if rehearsalMark != nil { return "Rehearsal mark" }
            return ""
        }
        
        private var accessibilityValue: String {
            if let payload = message { return payload.text }
            if image != nil { return "Image" }
            if let mark = rehearsalMark { return "Rehearsal mark \(mark)" }
            return ""
        }
        
        private func loadImageIfNeeded() {
            guard let image else {
                uiImage = nil
                showMissingImage = false
                imageLoadToken = nil
                return
            }
            if let cached = CueLibraryStore.cachedImage(id: image.assetID) {
                uiImage = cached
                showMissingImage = false
                return
            }
            uiImage = nil
            showMissingImage = false
            let assetID = image.assetID
            imageLoadToken = assetID
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if imageLoadToken == assetID && uiImage == nil {
                    showMissingImage = true
                }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = CueLibraryStore.assetDataFromDisk(id: assetID),
                      let decoded = UIImage(data: data) else { return }
                CueLibraryStore.cacheImage(decoded, for: assetID)
                DispatchQueue.main.async {
                    if image.assetID == assetID {
                        uiImage = decoded
                        showMissingImage = false
                    }
                }
            }
        }
    }
    
}

enum EditableField { case ip, port, lobbyCode }

//──────────────────────────────────────────────────────────────
// MARK: – MainScreen  (everything in one struct)
//──────────────────────────────────────────────────────────────
private extension UIApplication {
    func topMostController(_ base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topMostController(nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let sel = tab.selectedViewController {
            return topMostController(sel)
        }
        if let presented = base?.presentedViewController {
            return topMostController(presented)
        }
        return base
    }
}
// MARK: - Container size environment (actual window size)
private struct ContainerSizeKey: EnvironmentKey { static let defaultValue = CGSize.zero }
extension EnvironmentValues {
    var containerSize: CGSize {
        get { self[ContainerSizeKey.self] }
        set { self[ContainerSizeKey.self] = newValue }
    }
}


struct MainScreen: View {
    // Add next to your other computed vars
    
    @State private var showCueSheets = false
    @State private var pendingCueSheetCreateFromWhatsNew = false
    @Environment(\.containerSize) private var containerSize
    @Environment(\.horizontalSizeClass) private var hSize
        private var isPadDevice: Bool {
            UIDevice.current.userInterfaceIdiom == .pad
        }
    // 12.9"/13" iPad hardware (native height ≥ 2732 px)
        private var isLargePad129Family: Bool {
            guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
            let maxNative = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
            return maxNative >= 2732
        }
    // Next to isLargePad129Family
    private var isPad109Family: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        let maxNative = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
        return maxNative == 2360 // 10.9" iPad/Air family
    }
    private var isPad11Family: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        let nativeMax = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
        // 11" iPad Pro/air ≈ 2388; 10.9" ≈ 2360; exclude 12.9"/13" (2732+)
        return nativeMax >= 2360 && nativeMax < 2732
    }
    // 8.3" iPad mini family
    private var isPadMiniFamily: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        let maxNative = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
        return maxNative == 2266 // iPad mini (8.3")
    }
    // Build wires from the current in-memory events list
        private func encodeCurrentEvents()
    -> (stops: [StopEventWire], cues: [CueEventWire], restarts: [RestartEventWire]) {
            let stops: [StopEventWire] = events.compactMap {
                if case let .stop(s) = $0 { return StopEventWire(eventTime: s.eventTime, duration: s.duration) }
                return nil
            }
            let cues: [CueEventWire] = events.compactMap {
                if case let .cue(c) = $0 { return CueEventWire(cueTime: c.cueTime) }
                return nil
            }
            let restarts: [RestartEventWire] = events.compactMap {
                if case let .restart(r) = $0 { return RestartEventWire(restartTime: r.restartTime) }
                return nil
            }
            return (stops, cues, restarts)
        }
    
        // Build wires + label directly from a CueSheet (used by broadcast(sheet))
        private func wires(from sheet: CueSheet)
        -> (stops: [StopEventWire], cues: [CueEventWire], restarts: [RestartEventWire], label: String) {
            let sorted = sheet.events.sorted { $0.at < $1.at }
            let stops: [StopEventWire] = sorted.compactMap {
                if $0.kind == .stop { return StopEventWire(eventTime: $0.at, duration: $0.holdSeconds ?? 0) }
                return nil
            }
            let cues: [CueEventWire] = sorted.compactMap {
                if $0.kind == .cue { return CueEventWire(cueTime: $0.at) }
                return nil
            }
            let restarts: [RestartEventWire] = sorted.compactMap {
                if $0.kind == .restart { return RestartEventWire(restartTime: $0.at) }
                return nil
            }
            let label = sheetBadgeLabel(for: sheet)
            return (stops, cues, restarts, label)
        }

    // ── Environment & Settings ────────────────────────────────
    @EnvironmentObject private var settings   : AppSettings
    @EnvironmentObject var syncSettings: SyncSettings
    @AppStorage("settingsPage") private var settingsPage: Int = 0
    let numberOfPages = 4
    @State private var showSyncErrorAlert = false
    @State private var syncErrorMessage = ""
    // WC: 4 Hz tick + sink for commands
        @State private var wcTick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
        @State private var wcCancellables = Set<AnyCancellable>()
        
    // ── UI mode ────────────────────────────────────────────────
    @Binding var parentMode: ViewMode
    @State private var previousMode: ViewMode = .sync   // track old mode
    @State private var lastAcceptedMode: ViewMode = .sync
    @State private var wasChildTabLockActive = false
    
    // Preset editor state
    @State private var showPresetEditor = false
    @State private var pendingPresetEditIndex: Int? = nil
    
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
    @State private var childTargetStartDate: Date? = nil
    @State private var childDisplayElapsed: TimeInterval = 0
    @State private var ticker: AnyCancellable? = nil
    @State private var justEditedAfterPause: Bool = false
    @State private var pausedElapsed: TimeInterval = 0
    @State private var stopCleared: Bool = false

    // ── Notes persistence & sync ───────────────────────────────
        /// Your device’s global note (persists across the app)
        @AppStorage("notes.global") private var notesLocal: String = ""
        /// Parent’s note mirrored onto this device (cleared if none present)
        @State private var notesParent: String = ""
    
    // ── pagination for left pane ───────────────────────────────

    @AppStorage("leftPanePagerOnLargePads") private var leftPanePagerOnLargePads: Bool = false
    @AppStorage("leftPaneTab")             private var leftPaneTab: Int = 0 // remember last tab
    @inline(__always)
    private func settingsMorphAnim() -> Animation {
        if #available(iOS 17, *) { return .snappy(duration: 0.26, extraBounce: 0.25) }
        return .easeInOut(duration: 0.26)
    }


        /// Parent includes its note when broadcasting; child is read-only
    private var parentNotePayload: String? {
                (syncSettings.role == .parent &&
                 !notesLocal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ? notesLocal : nil
            }
    // ── Presets persistence (device-local JSON) ──────────────────────────
        @AppStorage("presets.data") private var presetsBlob: Data = Data()
        @State private var presetsDirtyNonce: Int = 0  // bump to refresh when edited
    private var presets: [Preset] { loadPresets() } // read-only convenience
    // Helpers to avoid mutating `self` in closures:
    private func loadPresets() -> [Preset] {
        guard !presetsBlob.isEmpty,
              let arr = try? JSONDecoder().decode([Preset].self, from: presetsBlob)
        else { return [] }
        return arr
    }
    private func savePresets(_ newValue: [Preset]) {
        let clipped = newValue.map { p in
            var x = p
            if x.name.count > 32 { x.name = String(x.name.prefix(32)) }
            return x
        }
        if let data = try? JSONEncoder().encode(clipped) { presetsBlob = data }
    }
    // ── Sync / Lock ─────────────────────────────────────────────
        private var lockActive: Bool { syncSettings.isLocked }
        private var isChildTabLockActive: Bool {
            (syncSettings.role == .child) && syncSettings.isEnabled && syncSettings.isEstablished
        }
        /// Child devices must be UI-locked while connected to a parent.
        private var uiLockedByParent: Bool {
            isChildTabLockActive
        }
        private var padLocked: Bool {
            lockActive
            || uiLockedByParent           // ← add child lock
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
    @StateObject private var cueDisplay = CueDisplayController()
    @EnvironmentObject private var cueBadge: CueBadgeState
    @State private var rawStops: [StopEvent] = []
    @State private var stopActive: Bool = false
    @State private var stopRemaining: TimeInterval = 0
    @State private var editedAfterFinish: Bool = false
    @State private var editingTarget: EditableField? = nil   // nil = not editing
    @State private var inputText      = ""                   // live buffer
    @State private var isEnteringField = false
    @State private var showBadPortError = false
    /// Monotonic anchor for frame-accurate dt while a STOP is active
    @State private var lastTickUptime: TimeInterval? = nil
    // Local page binding for embedding the CONNECT cards without changing the global pager
     @State private var connectPageShadow: Int = 2
    @State private var lastLoadedLabel: String? = nil
    @State private var lastLoadedWasBroadcast: Bool = false
    @State private var loadedCueSheetID: UUID? = nil
    @State private var loadedCueSheet: CueSheet? = nil
    @State private var activeCueSheet: CueSheet? = nil
    @State private var pendingPlaybackState: PlaybackState? = nil
    @State private var playbackStateSeq: UInt64 = 0
    @State private var playbackStopAnchorElapsedNs: UInt64? = nil
    @State private var playbackStopAnchorUptimeNs: UInt64? = nil
    @State private var lastAppliedPlaybackSeq: UInt64 = 0
    @State private var lastAppliedControlSeq: UInt64 = 0
    @State private var lastAppliedControlKind: TimerMessage.Action? = nil
    @State private var ignoreRunningUpdatesUntil: TimeInterval? = nil
    @State private var lastStopFinalSettleSeq: UInt64? = nil
    @State private var lastStopBurstSeq: UInt64? = nil
    @State private var lastStopAnchorElapsedNs: UInt64? = nil
    @State private var lastStopAnchorUptimeNs: UInt64? = nil
    @State private var stopSettleCancellable: AnyCancellable? = nil
    @State private var stopSettleFinalWorkItem: DispatchWorkItem? = nil
    
    @State private var childDecorativeSchedule: [Event] = [] // .message + .image from the loaded sheet
    @State private var childDecorativeCursor: Int = 0
    @State private var childWireCues: [Event] = []           // last-known cue wires from parent
    @State private var childWireRestarts: [Event] = []       // last-known restart wires from parent
    @State private var lastEndedCueSheetID: UUID? = nil
    @State private var lastEndCueSheetReceivedAt: TimeInterval? = nil
    private var isChildDevice: Bool {
        syncSettings.role == .child || settings.simulateChildMode
    }
    private let remoteActiveCueSheetSentinelID = UUID(uuidString: "7F5C7D06-28B4-4E98-9D07-7C06D1B2CB2F")!
    private var activeCueSheetID: UUID? {
        get {
            UserDefaults.standard.string(forKey: "activeCueSheetID").flatMap(UUID.init)
        }
        nonmutating set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: "activeCueSheetID")
        }
    }
    
    func apply(_ sheet: CueSheet, broadcastBadge: Bool = false) {
        activateCueSheet(sheet, broadcastBadge: broadcastBadge)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func activateCueSheet(_ sheet: CueSheet, broadcastBadge: Bool) {
        activeCueSheetID = sheet.id
        activeCueSheet = sheet
        lastEndedCueSheetID = nil
        lastEndCueSheetReceivedAt = nil
        loadedCueSheetID = sheet.id
        loadedCueSheet = sheet
        cueDisplay.reset()
        cueDisplay.buildTimeline(from: sheet)
        mapEvents(from: sheet)
        if isChildDevice {
            cueBadge.setFallbackLabel(sheetBadgeLabel(for: sheet), broadcast: true)
        } else {
            cueBadge.setLoaded(sheetID: sheet.id, broadcast: broadcastBadge)
        }
        // Notify any listeners that a sheet was loaded
        NotificationCenter.default.post(name: .didLoadCueSheet, object: sheet)
        CueLibraryStore.shared.prefetchImages(in: sheet)
    }

    private func endActiveCueSheet(reason: String) {
        activeCueSheetID = nil
        activeCueSheet = nil
        events.removeAll()
        rawStops.removeAll()
        cueDisplay.reset()
        childDecorativeSchedule.removeAll()
        childDecorativeCursor = 0
        childWireCues.removeAll()
        childWireRestarts.removeAll()
        syncSettings.stopWires = []
        pendingPlaybackState = nil
        cueBadge.clear()
        #if DEBUG
        print("[CueSheet] endActiveCueSheet reason=\(reason)")
        #endif
    }

    private func handleChildLinkLost(reason: String) {
        guard isChildDevice else { return }
        let hasRemoteState = activeCueSheetID != nil
            || cueBadge.broadcast
            || !childWireCues.isEmpty
            || !childWireRestarts.isEmpty
            || !childDecorativeSchedule.isEmpty
        if hasRemoteState {
            endActiveCueSheet(reason: "link-lost-\(reason)")
        }
    }

    private func mapEvents(from sheet: CueSheet) {
        let mapped: [Event] = sheet.events
            .sorted { $0.at < $1.at }
            .map { se in
                switch se.kind {
                case .cue:
                    return .cue(CueEvent(cueTime: se.at))
                case .stop:
                    return .stop(StopEvent(eventTime: se.at, duration: se.holdSeconds ?? 0))
                case .restart:
                    return .restart(RestartEvent(restartTime: se.at))
                case .message:
                    return .message(MessageEvent(messageTime: se.at))
                case .image:
                    return .image(ImageEvent(imageTime: se.at))
                default:
                    // Unknown/new kinds → treat as a cue at the same absolute time
                    return .cue(CueEvent(cueTime: se.at))
                }
            }
        
        let decorative = mapped.filter {
            if case .message = $0 { return true }
            if case .image   = $0 { return true }
            return false
        }

        if isChildDevice {
            childDecorativeSchedule = decorative.sorted { $0.fireTime < $1.fireTime }
            childDecorativeCursor = 0
            rebuildChildDisplayEvents()
        } else {
            events = mapped
            // Keep rawStops in sync so the stop loop/timer logic continues to work
            rawStops = mapped.compactMap {
                if case let .stop(s) = $0 { return s } else { return nil }
            }
        }
    }

    private func reloadCurrentCueSheet() {
        guard let sheetID = activeCueSheetID,
              let meta = CueLibraryStore.shared.index.sheets[sheetID],
              let sheet = try? CueLibraryStore.shared.load(meta: meta) else { return }

        loadedCueSheetID = sheet.id
        loadedCueSheet = sheet
        activeCueSheet = sheet
        cueDisplay.reset()
        cueDisplay.buildTimeline(from: sheet)
        mapEvents(from: sheet)
        NotificationCenter.default.post(name: .didLoadCueSheet, object: sheet)
        CueLibraryStore.shared.prefetchImages(in: sheet)
    }
    // Derive connected device display names for the Devices card.
        // Replace internals later with your canonical peer list if you expose one.
    private func connectedDeviceNamesForUI() -> [String] {
            // Try to find `[String]` named "connectedDeviceNames"
            let m = Mirror(reflecting: syncSettings)
            if let names = m.children.first(where: { $0.label == "connectedDeviceNames" })?.value as? [String],
               !names.isEmpty {
                return names
            }
            // Try to find peers array named "connectedPeers" and pluck displayName/name via reflection
            if let peersAny = m.children.first(where: { $0.label == "connectedPeers" })?.value as? [Any] {
                let names: [String] = peersAny.compactMap { peer in
                    let pm = Mirror(reflecting: peer)
                    // prefer displayName, then name
                    if let dn = pm.children.first(where: { $0.label == "displayName" })?.value as? String, !dn.isEmpty {
                        return dn
                    }
                    if let nm = pm.children.first(where: { $0.label == "name" })?.value as? String, !nm.isEmpty {
                        return nm
                    }
                    return nil
                }
                if !names.isEmpty { return names }
            }
            // Nothing discoverable; return empty (caller will show "No devices connected")
            return []
        }
    private func addCueFromPreset(at time: Double, treatAsAbsolute: Bool) {
        // Resolve target time
        let target = treatAsAbsolute ? time : max(0, displayMainTime() + time)
        // Add & sort
        events.append(.cue(CueEvent(cueTime: target)))
        events.sort { $0.fireTime < $1.fireTime }

        // Broadcast snapshot if parent (no pause)
        if syncSettings.role == .parent && syncSettings.isEnabled {
            let snap = encodeCurrentEvents()
            var m = TimerMessage(
                action:     .addEvent,
                timestamp:  Date().timeIntervalSince1970,
                phase:      (phase == .running ? "running" : "idle"),
                remaining:  displayMainTime(),
                stopEvents: snap.stops,
                parentLockEnabled: syncSettings.parentLockEnabled,
                cueEvents: snap.cues,
                restartEvents: snap.restarts,
                sheetLabel: cueBadge.label
            )
            m.notesParent = parentNotePayload
            syncSettings.broadcastToChildren(m)
        }
        // No phase changes here — do NOT pause.
        lightHaptic()
    }
    private var shouldPaginateLeftPane: Bool {
        let smallPads = (isPad109Family || isPad11Family)
        return smallPads || (isLargePad129Family && leftPanePagerOnLargePads)
    }

    // Broadcast to children when attachMode == .global — non-destructive (doesn't touch radios)
        func broadcast(_ sheet: CueSheet) {
            // Only the parent with sync enabled should broadcast
            guard syncSettings.role == .parent,
                  syncSettings.isEnabled,
                  activeCueSheetID != nil else { return }
    
            // Convert sheet → wire format the child already understands (StopEventWire).
            // If your sheet includes cues/restarts, you can extend your wire later; for now
            // stops render the 5-circle strip reliably across devices.
            let (stops, cues, restarts) = wireAllEvents(from: sheet)
    
            // Keep whatever phase/remaining you’re currently in; the child already rebuilds
            // its rawStops/events from msg.stopEvents at the top of applyIncomingTimerMessage.
            let phaseString: String = {
                switch phase {
                case .idle:      return "idle"
                case .countdown: return "countdown"
                case .running:   return "running"
                case .paused:    return "paused"
                }
            }()
    
            let m = TimerMessage(
                action:     .update,                           // piggyback the existing path
                timestamp:  Date().timeIntervalSince1970,
                phase:      phaseString,
                remaining:  displayMainTime(),
                stopEvents: stops,
                            parentLockEnabled: syncSettings.parentLockEnabled,
                            isStopActive: nil,
                            stopRemainingActive: nil,
                            cueEvents: cues,
                            restartEvents: restarts,
                            sheetLabel: sheetBadgeLabel(for: sheet)
            )
    
            // IMPORTANT: this does NOT stop or toggle any radios.
            syncSettings.broadcastToChildren(m)

            syncSettings.broadcastSyncMessage(.sheetSnapshot(sheet))
            let state = makePlaybackState(for: sheet)
            syncSettings.broadcastSyncMessage(.playbackState(state))
            if settings.simulateChildMode {
                applyIncomingSyncMessage(.sheetSnapshot(sheet))
                applyIncomingSyncMessage(.playbackState(state))
            }
        }
    
    /// Helper: build *all* event wires from a sheet
        private func wireAllEvents(from sheet: CueSheet)
        -> ([StopEventWire],[CueEventWire],[RestartEventWire]) {
            let sorted = sheet.events.sorted { $0.at < $1.at }
            let stops     = sorted.compactMap { $0.kind == .stop    ? StopEventWire(eventTime: $0.at, duration: $0.holdSeconds ?? 0) : nil }
            let cues      = sorted.compactMap { $0.kind == .cue     ? CueEventWire(cueTime: $0.at) : nil }
            let restarts  = sorted.compactMap { $0.kind == .restart ? RestartEventWire(restartTime: $0.at) : nil }
            return (stops, cues, restarts)
        }
    
        private func sheetBadgeLabel(for sheet: CueSheet) -> String {
            if let label = CueLibraryStore.shared.badgeLabel(for: sheet.id) {
                return label
            }
            let name  = sheet.fileName.isEmpty ? sheet.title : sheet.fileName
            return name.lastIndex(of: ".").map { String(name[..<$0]) } ?? name
        }

        private func sheetRevision(for sheet: CueSheet) -> Int {
            Int(sheet.modified.timeIntervalSince1970)
        }

        private func makePlaybackState(for sheet: CueSheet) -> PlaybackState {
            let sorted = sheet.events.sorted { $0.at < $1.at }
            let currentIndex = sorted.lastIndex { $0.at <= elapsed }
            let nextIndex = sorted.firstIndex { $0.at > elapsed }
            let startEpoch = startDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970 - elapsed
            let playbackPhase: PlaybackPhase = {
                switch phase {
                case .running: return .running
                case .paused: return .paused
                case .idle, .countdown: return .idle
                }
            }()
            if playbackPhase == .running {
                clearPlaybackStopAnchor()
            } else {
                capturePlaybackStopAnchor(elapsedSeconds: elapsed)
            }
            playbackStateSeq &+= 1
            return PlaybackState(
                isRunning: playbackPhase == .running,
                phase: playbackPhase,
                seq: playbackStateSeq,
                masterUptimeNsAtStop: playbackPhase == .running ? nil : playbackStopAnchorUptimeNs,
                elapsedAtStopNs: playbackPhase == .running ? nil : playbackStopAnchorElapsedNs,
                startTime: startEpoch,
                elapsedTime: elapsed,
                currentEventID: currentIndex.map { sorted[$0].id },
                nextEventID: nextIndex.map { sorted[$0].id },
                sheetID: sheet.id,
                revision: sheetRevision(for: sheet)
            )
        }

        private func broadcastPlaybackStateIfNeeded() {
            guard syncSettings.role == .parent,
                  syncSettings.isEnabled,
                  let sheet = activeCueSheet else { return }
            let state = makePlaybackState(for: sheet)
            syncSettings.broadcastSyncMessage(.playbackState(state))
            if settings.simulateChildMode {
                applyIncomingSyncMessage(.playbackState(state))
            }
        }

        private func broadcastEndCueSheet(sheetID: UUID?) {
            guard syncSettings.role == .parent, syncSettings.isEnabled else { return }
            let phaseString: String = {
                switch phase {
                case .idle:      return "idle"
                case .countdown: return "countdown"
                case .running:   return "running"
                case .paused:    return "paused"
                }
            }()
            let msg = TimerMessage(
                action: .endCueSheet,
                timestamp: Date().timeIntervalSince1970,
                phase: phaseString,
                remaining: displayMainTime(),
                stopEvents: [],
                sheetID: sheetID?.uuidString
            )
            syncSettings.broadcastToChildren(msg)
            if syncSettings.connectionMethod == .bluetooth {
                for idx in 1...2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + (0.1 * Double(idx))) {
                        syncSettings.broadcastToChildren(msg)
                    }
                }
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
                // stop existing sync + cancel tap pairing session
                 if syncSettings.role == .parent { syncSettings.stopParent() }
                 else                           { syncSettings.stopChild() }
                syncSettings.cancelTapPairing()
                // Stop BLE advertise/scan
                syncSettings.bleDriftManager.stop()

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
                // kick off Tap-to-Pair immediately after Bluetooth sync starts
                if syncSettings.tapPairingAvailable {
                    syncSettings.beginTapPairing()
                } else {
                    syncSettings.tapStateText = "Not available on Mac"
                }
            case .bonjour:
                if syncSettings.role == .parent {
                    syncSettings.startParent()
                    syncSettings.bonjourManager.startAdvertising()
                    syncSettings.bonjourManager.startBrowsing()
                    syncSettings.statusMessage = "Bonjour: advertising & listening"
                } else {
                    syncSettings.bonjourManager.advertisePresence()
                    syncSettings.bonjourManager.startBrowsing()
                    // (BLEDriftManager will set defaults; this call actually spins it up)
                    syncSettings.bleDriftManager.start()
                    syncSettings.statusMessage = "Bonjour: advertising & searching…"
                }
            }

            syncSettings.isEnabled = true
        }
    }

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
            default:
                break
            }
            inputText = ""
            editingTarget = nil
            isEnteringField = false
        }
    
    
   
    @State private var hasUnsaved: Bool = false   // or compute if you already track dirty state

    private func openCueSheets() {
        showCueSheets = true
    }

    private func updateTimerActiveState() {
        isTimerActive = (phase == .running || phase == .countdown)
    }

    private func syncPresentationState() {
        isPresentingCueSheets = showCueSheets
        isPresentingPresetEditor = showPresetEditor
        updateTimerActiveState()
    }
    
    private func dismissActiveCueSheet() {
        let endedID = activeCueSheetID
        endActiveCueSheet(reason: "user-dismiss")
        if let endedID,
           syncSettings.role == .parent,
           syncSettings.isEnabled {
            broadcastEndCueSheet(sheetID: endedID)
        }
    }

    @State private var eventMode: EventMode = .stop
    @Binding var showSettings: Bool
    @Binding var isTimerActive: Bool
    @Binding var isPresentingCueSheets: Bool
    @Binding var isPresentingPresetEditor: Bool
    
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
    // Choose a discrete scale so it *snaps* in mini/small/big
    private func numpadScale(for size: CGSize) -> CGFloat {
        switch iPadWindowMode(size) {
        case .big:   return 1.0
        case .small: return 0.88
        case .mini:  return 0.76
        }
    }
     // ─────────────────────────────────────────────────────────────
     // PresetEditorSheet (modal like CueSheetsSheet)
     // ─────────────────────────────────────────────────────────────
     struct PresetEditorSheet: View {
         @Environment(\.dismiss) private var dismiss
         @State private var working: Preset
         let isEditing: Bool
         let availableSheets: [String]              // identifiers/titles you expose in CueSheetsSheet
         let onSave: (Preset) -> Void
         @State private var lastAutoName: String = ""
         @State private var userEditedName: Bool = false
    
         init(editing preset: Preset?, sheets: [String], onSave: @escaping (Preset) -> Void) {
             _working = State(initialValue: preset ?? Preset(name: "", kind: .countdown, seconds: 30, sheetIdentifier: nil, icon: "timer"))
             self.isEditing = (preset != nil)
             self.availableSheets = sheets
             self.onSave = onSave
             // note: lastAutoName/userEditedName initialized in .onAppear
         }
    
         var body: some View {
             NavigationStack {
                 Form {
                     Section("Preset Type") {
                          Picker("", selection: Binding(
                              get: {
                                  (working.kind == .sheet) ? 2 : (working.kind == .countdown ? 0 : 1)
                              },
                              set: { idx in
                                  switch idx {
                                  case 0: working.kind = .countdown
                                  case 1: working.kind = .cueRelative  // default to relative; toggle below can switch to absolute
                                  default: working.kind = .sheet
                                  }
                              }
                          )) {
                              Text("Countdown").tag(0)
                              Text("Cue").tag(1)
                              Text("Event Sheet").tag(2)
                          }
                          .pickerStyle(.segmented)
                          Text("Choose what this preset does when tapped. Cue presets add a flash marker at a time.")
                              .font(.footnote).foregroundStyle(.secondary)
                      }
                     Section("Name") {
                         TextField("Optional (32 chars)", text: $working.name)
                                     .onChange(of: working.name) { new in
                                       if new.count > 32 { working.name = String(new.prefix(32)) }
                                       // Detect user override vs auto
                                       if new != lastAutoName { userEditedName = true }
                                     }
                                   // Hint
                                   Text("If left blank, the name auto-updates from the type and time.")
                                     .font(.footnote)
                                     .foregroundStyle(.secondary)
                         Text("Shown on the preset chip. If blank, a sensible name is generated.")
                                .font(.footnote).foregroundStyle(.secondary)
                     }
                     if working.kind == .countdown || working.kind == .cueRelative || working.kind == .cueAbsolute {
                         Section("Time") {
                             TimePickerSeconds(value: Binding(
                                 get: { working.seconds ?? 0 },
                                 set: { working.seconds = $0 }
                             ))
                             Text("Choose the duration (countdown) or cue time.")
                                .font(.footnote).foregroundStyle(.secondary)
                             if working.kind == .cueRelative || working.kind == .cueAbsolute {
                                         Toggle(isOn: Binding(
                                             get: { working.kind == .cueRelative },
                                             set: { $0 ? (working.kind = .cueRelative) : (working.kind = .cueAbsolute) }
                                         )) { Text("Relative offset from now") }
                                         Text("Relative: cue triggers at current time + offset.\nAbsolute: cue triggers at an exact time on the clock.")
                                             .font(.footnote).foregroundStyle(.secondary)
                                     } else {
                                         Text("Countdown duration to prefill into the main timer when tapped.")
                                             .font(.footnote).foregroundStyle(.secondary)
                                     }
                         }
                     }
                     if working.kind == .sheet {
                         Section("Cue Sheet") {
                             if availableSheets.isEmpty {
                                 Text("No cue sheets available. Add one in Cue Sheets.")
                                     .foregroundStyle(.secondary)
                             } else {
                                 Picker("Select a saved sheet", selection: Binding(
                                                 get: {
                                                     // always non-nil while this UI is visible
                                                     if let id = working.sheetIdentifier, availableSheets.contains(id) { return id }
                                                     let first = availableSheets.first!
                                                     DispatchQueue.main.async { working.sheetIdentifier = first }
                                                     return first
                                                 },
                                                 set: { working.sheetIdentifier = $0 }
                                             )) {
                                     ForEach(availableSheets, id: \.self) { s in Text(s).tag(s) }
                                 }
                                 Text("Pick a saved cue sheet to load when this preset is tapped.")
                                        .font(.footnote).foregroundStyle(.secondary)
                             }
                         }
                     }
                     
                 }
                 .navigationTitle(isEditing ? "Edit Preset" : "New Preset")
                 .toolbar {
                     ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                     ToolbarItem(placement: .confirmationAction) {
                         Button("Save") {
                             var p = working
                             // Auto icon by type (requirement #3)
                                     p.icon = {
                                         switch p.kind {
                                         case .countdown:   return "timer"
                                         case .cueRelative: return "flag.fill"
                                         case .cueAbsolute: return "flag"
                                         case .sheet:       return "music.note.list"
                                         }
                                     }()
                             // If the current name is still the auto-generated one (or empty),
                                         // ensure we save with the latest auto name.
                                         let auto = autoName(for: p)
                                         if p.name.isEmpty || p.name == lastAutoName || userEditedName == false {
                                           p.name = auto
                                         }

                             onSave(p); dismiss()
                         }
                         .disabled(!isValid(working))
                     }
                 }
                 // Seed auto name and keep it updated as fields change
                       .onAppear {
                         lastAutoName = autoName(for: working)
                         if working.name.isEmpty { working.name = lastAutoName }
                         userEditedName = (working.name != lastAutoName)
                       }
                       .onChange(of: working.kind)        { _ in refreshAutoName() }
                       .onChange(of: working.seconds)     { _ in refreshAutoName() }
                       .onChange(of: working.sheetIdentifier) { _ in refreshAutoName() }
             }
         }
         private func refreshAutoName() {
             let next = autoName(for: working)
             // Update only if user hasn't overridden the name
             if working.name.isEmpty || working.name == lastAutoName || userEditedName == false {
               working.name = next
               userEditedName = false
             }
             lastAutoName = next
             // Auto-set icon by type
             working.icon = defaultIcon(for: working.kind)
           }
         private func isValid(_ p: Preset) -> Bool {
             switch p.kind {
             case .countdown, .cueRelative, .cueAbsolute: return (p.seconds ?? 0) > 0
             case .sheet: return !(p.sheetIdentifier ?? "").isEmpty
             }
         }
         private func format(_ s: Double) -> String {
             let cs = Int(round(s * 100))
             let sec = cs / 100
             let cs2 = cs % 100
             let m = sec / 60
             let r = sec % 60
             return String(format: "%d:%02d.%02d", m, r, cs2)
         }
         private func autoName(for p: Preset) -> String {
             switch p.kind {
             case .countdown:   return "Countdown \(format(p.seconds ?? 0))"
             case .cueRelative: return "Cue +\(format(p.seconds ?? 0))"
             case .cueAbsolute: return "Cue \(format(p.seconds ?? 0))"
             case .sheet:
               let label = p.sheetIdentifier ?? "Sheet"
               return "Load \(label)"
             }
           }
           private func defaultIcon(for kind: Preset.Kind) -> String {
             switch kind {
             case .countdown:   return "timer"
             case .cueRelative: return "flag.fill"
             case .cueAbsolute: return "flag"
             case .sheet:       return "music.note.list"
             }
           }
     }

     // Simple seconds picker (MM:SS.CC) for countdown/cue
     struct TimePickerSeconds: View {
         @Binding var value: Double
         var body: some View {
             HStack {
                 Stepper("Seconds: \(String(format: "%.2f", value))", value: $value, in: 0...3599.99, step: 0.25)
             }
         }
     }
    
    var body: some View {
        GeometryReader { geo in
            mainLayout(in: geo)
        }
    }

    @ViewBuilder
    private func mainLayout(in geo: GeometryProxy) -> some View {
        // Use the *actual window* size
        let winSize: CGSize = geo.size
        let screenWidth: CGFloat  = winSize.width
        let screenHeight: CGFloat = winSize.height

            // Phones keep their size-class logic
            let isPhoneLandscape: Bool = (verticalSizeClass == .compact)
                        let isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad
            // iPad: decide by aspect, not size class
            let isPadLandscapeByAspect: Bool = winSize.width > winSize.height
        
        // 1) Use the **actual window size** if provided (iPad/Split/Stage Manager),
              
        let isMax       = screenWidth >= 414 //max
        let isMiniPhone       = (abs(screenWidth - 375) < 0.5 && abs(screenHeight - 812) < 0.5) // mini
              let isVerySmallPhone  = (screenWidth <= 376) && !isMiniPhone                            // SE
                let isStandardPhone   = (abs(screenWidth - 390) < 0.5 && abs(screenHeight - 844) < 0.5) // 12/13/14
        
        let isSmallPhone = (screenWidth > 376 && screenWidth < 414) && !isStandardPhone //pro
        
        // — new detection for iPhone 13/14 mini & iPhone 12/13/14 —
        
        // 2) Decide your offsets
        let timerOffset   = isMax ? 36 : 10    // ↓ TimerCard/SettingsPagerCard
        let modeBarOffset = isMax ? -42 : -56    // ↓ mode bar
        
            ZStack {
                if settings.flashStyle == .tint && flashZero && (isPadDevice ? isPadLandscapeByAspect : isLandscape) {
                    settings.flashColor
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: Double(settings.flashDurationOption) / 1000), value: flashZero)
                }
                // ── LAYOUT CHOOSER ──────────────────────────────────────────────
                // Strong, compile-safe portrait detection for iPad.
                // 1) Primary: this window's aspect (Stage Manager / split aware)
                // 2) Fallback: physical screen aspect (in case a nested GeometryReader lies)
                let isPadPortraitLike =
                    (winSize.height >= winSize.width) ||
                    (UIScreen.main.bounds.height >= UIScreen.main.bounds.width)

                Group {
                    if isPad && isPadPortraitLike {
                        // ✅ Any iPad that reads as portrait uses the unified portrait layout
                        iPadUnifiedLayout()
                    } else if isPad {
                        // ✅ All other iPads use the 2-pane landscape layout
                        iPadLandscapeLayout()
                    } else if isPhoneLandscape {
                        // (existing iPhone-landscape block unchanged)
                        GeometryReader { fullGeo in
                            let hm: CGFloat = 8
                            let w = fullGeo.size.width  - (hm * 2)
                            let h = fullGeo.size.height * 0.22
                            // phone landscape timercard
                            VStack(spacing: 8) {
                                TimerCard(
                                    mode: $parentMode,
                                    flashZero: $flashZero,
                                    isRunning: phase == .running,
                                    flashStyle: settings.flashStyle,
                                    flashColor: settings.flashColor,
                                    syncDigits: countdownDigits,
                                    stopDigits: { switch eventMode { case .stop: return stopDigits; case .cue: return cueDigits; case .restart: return restartDigits } }(),
                                    phase: phase,
                                    mainTime: displayMainTime(),
                                    stopActive: stopActive,
                                    stopRemaining: stopRemaining,
                                    leftHint: "START POINT",
                                    rightHint: "DURATION",
                                    stopStep: stopStep,
                                    makeFlashed: makeFlashedOverlay,
                                    isCountdownActive: willCountDown,
                                    events: events,
                                    onClearEvents: {
                                        dismissActiveCueSheet()
                                        hasUnsaved = false
                                    }
                                )
                                .environmentObject(cueDisplay)
                                .frame(width: w, height: h)
                            }
                            .position(x: fullGeo.size.width/2, y: fullGeo.size.height/2)
                            .offset(y: 12)
                        }
                        .environment(\.containerSize, .zero)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    } else {
                        // your existing iPhone-portrait VStack stays as-is
                        // (no changes needed here)
                        VStack(spacing: isVerySmallPhone ? 2 : (isSmallPhone ? 4 : 8)) {
                            // Top card (Timer or Settings)
                            // Top card (Timer or Settings) — matched-geometry morph
                            CardMorphSwitcher(
                                mode: $parentMode,
                                timer:
                                    //OG phone portrait timercard
                                    VStack(spacing: 8) {
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
                                            events: events,
                                            onClearEvents: {
                                                dismissActiveCueSheet()
                                                hasUnsaved = false
                                            }
                                        )
                                        .environmentObject(cueDisplay)
                                    }
                                
                                // Lock timer interactions while child is connected
                                    .allowsHitTesting(!(lockActive || (isChildTabLockActive && parentMode == .sync))),                                            settings:
                                    SettingsPagerCard(
                                        page: $settingsPage,
                                        editingTarget: $editingTarget,
                                        inputText: $inputText,
                                        isEnteringField: $isEnteringField,
                                        showBadPortError: $showBadPortError
                                    )
                                    .environmentObject(settings)
                                    .environmentObject(syncSettings)
                            )
                            .animation(
                                {
                                    if #available(iOS 17, *) {
                                        return parentMode == .settings
                                        ? .snappy(duration: 0.26, extraBounce: 0.25)
                                        : .snappy(duration: 0.24, extraBounce: 0.25)
                                    } else {
                                        return .easeInOut(duration: 0.26)
                                    }
                                }(),
                                value: parentMode
                            )
                            
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
                            // Mode bar (Sync / Events) — matched-geometry morph, layout-safe
                            if parentMode == .sync || parentMode == .stop {
                                ZStack {
                                    if !settings.lowPowerMode {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .frame(height: 80)
                                            .shadow(color: .black.opacity(0.125), radius: 10, x: 0, y: 6)
                                    }
                                    //main sync bar
                                    ModeBarMorphSwitcher(isSync: parentMode == .sync) {
                                        // --- SYNC content ---
                                        Group {
                                            SyncBar(
                                                isCounting: isCounting,
                                                isSyncEnabled: syncSettings.isEnabled,
                                                onOpenSyncSettings: {
                                                    previousMode = parentMode
                                                    parentMode   = .settings
                                                    settingsPage = 2
                                                },
                                                onToggleSyncMode: {
                                                    toggleSyncMode()
                                                },
                                                onRoleConfirmed: { newRole in
                                                    // keep your existing role-swap logic
                                                    let wasEnabled = syncSettings.isEnabled
                                                    if wasEnabled {
                                                        if syncSettings.role == .parent { syncSettings.stopParent() }
                                                        else                           { syncSettings.stopChild() }
                                                        syncSettings.isEnabled = false
                                                    }
                                                    syncSettings.role = newRole
                                                    if wasEnabled {
                                                        switch syncSettings.connectionMethod {
                                                        case .network, .bluetooth, .bonjour:
                                                            if newRole == .parent { syncSettings.startParent() }
                                                            else                  { syncSettings.startChild() }
                                                        }
                                                        syncSettings.isEnabled = true
                                                    }
                                                }
                                            )
                                            .environmentObject(syncSettings)
                                        }
                                    } events: {
                                        // (unchanged EventsBar)
                                        EventsBar(
                                            events: $events,
                                            eventMode: $eventMode,
                                            isPaused: phase == .paused,
                                            unsavedChanges: hasUnsaved,
                                            onOpenCueSheets: { openCueSheets() },
                                            isCounting: isCounting,
                                            onAddStop: commitStopEntry,
                                            onAddCue:  commitCueEntry,
                                            onAddRestart: commitRestartEntry,
                                            cueSheetAccent: settings.flashColor

                                        )
                                    }

                                }
                                .padding(.horizontal, 16)
                                .padding(.top, isVerySmallPhone ? 44
                                         : isSmallPhone ? 0
                                         : isStandardPhone ? -36
                                         : -46)
                                .padding(.top, CGFloat(modeBarOffset))
                                // Present the cue sheet from the container, not inside the initializer
                                
                                
                                
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
                                    let anim: Animation = {
                                        if #available(iOS 17, *) {
                                            return parentMode == .settings
                                            ? .snappy(duration: 0.26, extraBounce: 0.25)
                                            : .snappy(duration: 0.24, extraBounce: 0.25)
                                        } else {
                                            return .easeInOut(duration: 0.26)
                                        }
                                    }()
                                    
                                    if parentMode == .settings {
                                        withAnimation(anim) { parentMode = previousMode }
                                    } else {
                                        withAnimation(anim) {
                                            previousMode = parentMode
                                            parentMode   = .settings
                                        }
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
                                .disabled(lockActive || uiLockedByParent || parentMode != .sync)
                                .opacity(
                                    parentMode == .sync
                                    ? (uiLockedByParent ? 0.35 : 1.0)
                                    : (parentMode == .settings ? 0.3 : 0.0)
                                )
                                if parentMode == .settings {
                                    let pageTitle: String = {
                                        switch settingsPage {
                                        case 0: return "THEME"
                                        case 1: return "SET"
                                        case 2: return "CONNECT"
                                        case 3: return "ABOUT"
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
                                .disabled(lockActive || uiLockedByParent)
                                .opacity(parentMode == .stop ? (uiLockedByParent ? 0.35 : 1.0) : 0)
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
                            .zIndex(1)
                            .animation(.easeInOut(duration: 0.4), value: parentMode)
                        }
                    }
                }
            }
            // ✅ Publish this window size to the whole subtree so your
            //    iPad sublayouts and computed properties can read it.
            .environment(\.containerSize, winSize)
                .dynamicTypeSize(.medium ... .medium)
                .alert(isPresented: $showSyncErrorAlert) {
                    Alert(
                        title: Text("Cannot Start Sync"),
                        message: Text(syncErrorMessage),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .toolbar(isPadDevice ? .hidden : .automatic, for: .navigationBar)
                .navigationBarHidden(isPadDevice)

            // 1) Watch commands → Parent-only control (phone enforces authority)
                .onAppear {
                    installDisciplineProviders()
                    // Seed two starter presets if none exist (device-local).
                                       if presets.isEmpty {
                                           savePresets([
                                               Preset(name: "Countdown 0:30", kind: .countdown,    seconds: 30, icon: "timer"),
                                               Preset(name: "Cue +0:10",       kind: .cueRelative,  seconds: 10, icon: "flag.fill")
                                           ])
                                       }
                    ConnectivityManager.shared.commands
                        .receive(on: DispatchQueue.main)
                        .sink { cmd in
                            let isParent = (syncSettings.role == .parent)
                            let unlocked = !(syncSettings.parentLockEnabled ?? false)
                            guard isParent && unlocked else { return }
                            switch cmd.command {
                            case .start: if !isCounting { toggleStart() }
                            case .stop:  if  isCounting { toggleStart() }
                            case .reset: if !isCounting { resetAll() }
                            }
                        }
                        .store(in: &wcCancellables)
                }
                .onReceive(NotificationCenter.default.publisher(for: .TimerStart)) { _ in
                    if !isCounting { toggleStart() }   // start/resume only; never pause a running/countdown timer
                }

                .onReceive(NotificationCenter.default.publisher(for: .TimerPause)) { _ in
                     if phase == .running { toggleStart() }
                 }
                 .onReceive(NotificationCenter.default.publisher(for: .TimerReset)) { _ in
                     if phase != .running { resetAll() }
                 }
                .onReceive(NotificationCenter.default.publisher(for: .quickActionCountdown)) { note in
                    guard !stopActive else { return }
                    parentMode = .sync
                    let seconds = note.userInfo?["seconds"] as? Int ?? lastCountdownSecondsForQuickAction()
                    startCountdownFromQuickAction(seconds: seconds)
                }
                .onDisappear {
                    wcCancellables.removeAll()
                }
            
            // 2) Push TimerMessage snapshots at 4 Hz
                .onReceive(wcTick) { _ in
                    let phaseString: String = {
                        switch phase {
                        case .idle: return "idle"
                        case .countdown: return "countdown"
                        case .running: return "running"
                        case .paused: return "paused"
                        }
                    }()
                    
                    let linkStr: String = {
                        if !syncSettings.isEnabled { return "unreachable" }
                        switch syncSettings.connectionMethod {
                        case .bonjour:   return "bonjour"
                        case .bluetooth: return "nearby"
                        case .network:   return "network"
                        }
                    }()
                    
                    // Include live event snapshot so children stay in sync while running.
                    let snapshot = encodeCurrentEvents()
                    let tm = TimerMessage(
                        action: .update,
                        timestamp: Date().timeIntervalSince1970,
                        phase: phaseString,
                        remaining: displayMainTime(),
                        stopEvents: snapshot.stops,
                        anchorElapsed: elapsed,
                        parentLockEnabled: syncSettings.parentLockEnabled,
                        isStopActive: stopActive,
                        stopRemainingActive: stopRemaining,
                        cueEvents: snapshot.cues,
                        restartEvents: snapshot.restarts,
                        showHours: settings.showHours
                        // If you extended TimerMessage with role/link/controlsEnabled/etc, you can also pass them here:
                        // , role: (syncSettings.role == .parent ? "parent" : "child")
                        // , link: linkStr
                        // , controlsEnabled: (syncSettings.role == .parent && syncSettings.isEnabled && syncSettings.isEstablished && !(syncSettings.parentLockEnabled ?? false))
                        // , syncLamp: (syncSettings.isEnabled && syncSettings.isEstablished ? "green" : (syncSettings.isEnabled ? "amber" : "red"))
                        // , flashNow: flashZero
                    )
                    
                    ConnectivityManager.shared.send(tm)
                    if syncSettings.role == .parent && syncSettings.isEnabled {
                        syncSettings.broadcastToChildren(tm)   // ← keep children’s snapshot hot (stops + cues + restarts)
                    }

                    if syncSettings.role == .parent,
                       syncSettings.isEnabled,
                       let sheet = activeCueSheet {
                        let state = makePlaybackState(for: sheet)
                        syncSettings.broadcastSyncMessage(.playbackState(state))
                        if settings.simulateChildMode {
                            applyIncomingSyncMessage(.playbackState(state))
                        }
                    }

                }
            // end watch commands
            // wire up the child‐side handler
                .onAppear {
                    syncSettings.onReceiveTimer = { msg in
                        applyIncomingTimerMessage(msg)
                    }
                    syncSettings.onReceiveSyncMessage = { envelope in
                        applyIncomingSyncMessage(envelope.message)
                    }
                }
                .onDisappear {
                    syncSettings.onReceiveTimer = nil
                    syncSettings.onReceiveSyncMessage = nil
                }
            
            // 1) When you switch *into* Events view, seed the STOP buffer:
                .onChange(of: parentMode) { newMode in
                    if isChildTabLockActive && lastAcceptedMode == .sync && newMode == .stop {
                        parentMode = .sync
                        return
                    }
                    lastAcceptedMode = newMode
                    if newMode == .stop {
                        // ensure we’re in STOP mode
                        eventMode   = .stop
                        stopDigits  = timeToDigits(displayMainTime())
                        stopStep    = 0
                        stopCleared = false
                    }
                }
                .onChange(of: isChildTabLockActive) { isActive in
                    if isActive && !wasChildTabLockActive && parentMode == .stop {
                        parentMode = .sync
                    }
                    wasChildTabLockActive = isActive
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
                        handleChildLinkLost(reason: "sync-disabled")
                    }
                }
                .onChange(of: syncSettings.isEstablished) { established in
                    if !established {
                        handleChildLinkLost(reason: "established-false")
                    }
                }
            // Map a loaded CueSheet into the live events list (drives EventsBar + 5 circles)
                .onReceive(NotificationCenter.default.publisher(for: .didLoadCueSheet)) { note in
                    guard let sheet = note.object as? CueSheet else { return }
                    mapEvents(from: sheet)
                }
                .onReceive(NotificationCenter.default.publisher(for: .whatsNewOpenCueSheets)) { note in
                    if let shouldCreate = note.userInfo?["createBlank"] as? Bool, shouldCreate {
                        pendingCueSheetCreateFromWhatsNew = true
                    }
                    showCueSheets = true
                }
            // Stable SwiftUI sheet presenter (medium/large detents are defined inside CueSheetsSheet)
                .sheet(isPresented: $showCueSheets) {
                    CueSheetsSheet(
                        isPresented: $showCueSheets,
                        openNewBlankEditor: $pendingCueSheetCreateFromWhatsNew,
                        canBroadcast: { syncSettings.role == .parent && syncSettings.isEnabled },
                        onLoad: { sheet in
                            apply(sheet, broadcastBadge: false)
                        },
                        onBroadcast: { sheet in
                            apply(sheet, broadcastBadge: true) // local first
                            broadcast(sheet)                   // then send
                        }
                    )
                    .environmentObject(settings)
                }
                .sheet(isPresented: $showPresetEditor) {
                                    // Provide your available cue sheet identifiers/titles
                                    let sheetNames = CueLibraryStore.shared.allSheetNamesOrIds()
                    let current = loadPresets()
                     let editing: Preset? = pendingPresetEditIndex.flatMap { idx in
                         (idx >= 0 && idx < current.count) ? current[idx] : nil
                     }
                                   PresetEditorSheet(editing: editing, sheets: sheetNames) { saved in
                                        var arr = loadPresets()
                                        if let idx = pendingPresetEditIndex,
                                           idx >= 0, idx < arr.count {
                                            arr[idx] = saved
                                        } else {
                                            arr.append(saved)
                                        }
                                       savePresets(arr)
                                    }
                                }
                .onAppear {
                    syncPresentationState()
                }
                .onChange(of: showCueSheets) { _ in
                    syncPresentationState()
                }
                .onChange(of: showPresetEditor) { _ in
                    syncPresentationState()
                }
                .onChange(of: phase) { _ in
                    updateTimerActiveState()
                }
        // at the very end of MainScreen's body chain (on the outermost view)
        .toolbar(isPadDevice ? .hidden : .automatic, for: .navigationBar)
        .navigationBarHidden(isPadDevice)

    }
    
    @ViewBuilder
        private func ConnectedDevicesPaneInline() -> some View {
            VStack(alignment: .leading, spacing: 12) {
                // App logo (fills its bar height)
                   
                
                // Devices header (match Notes header)
                    Text("DEVICES")
                    .padding(.horizontal, 20)
                      .font(.custom("Roboto-SemiBold", size: 52))
                      .lineLimit(1)
                      .truncationMode(.tail)
                      .foregroundColor(.secondary)        // header text
    
                // ─────────────────────────────────────────────────────
                            // CONNECTED DEVICES CARD (count + names)
                            // ─────────────────────────────────────────────────────
           //                 VStack(alignment: .leading, spacing: 10) {
           //                     // Count row
             //                   let names = connectedDeviceNamesForUI()
               //                 HStack(spacing: 8) {
      //                              Image(systemName: names.isEmpty ? "circle.dashed" : "person.2.fill")
       //                                 .imageScale(.large)
       //                                 .foregroundColor(.secondary)
      //                              if names.isEmpty {
       //                                 Text("No devices connected")
      //                                      .font(.custom("Roboto-Regular", size: 16))
      //                                      .foregroundColor(.secondary)
       //                             } else {
       //                                 Text("\(names.count) connected")
       //                                     .font(.custom("Roboto-SemiBold", size: 16))
       //                                     .foregroundColor(.secondary)
       //                             }
        //                            Spacer()
       //                         }
       //                         // Names list
       //                         if !names.isEmpty {
        //                            VStack(alignment: .leading, spacing: 6) {
        //                                ForEach(names, id: \.self) { n in
       //                                     HStack(spacing: 8) {
       //                                         Image(systemName: "iphone")
       //                                             .imageScale(.small)
         //                                           .foregroundColor(.secondary)
         //                                       Text(n)
        //                                            .font(.custom("Roboto-Regular", size: 15))
        //                                    }
         //                               }
         //                           }
        //                            .padding(.top, 2)
         //                       }
           //                 }
           //                 .padding(.horizontal, 20)
           //                 .padding(0)
           //
           //                 // A little separation before the full CONNECT cards
            //                Divider().opacity(0.25)
    
                // ✅ Reuse the EXACT CONNECT page cards by embedding SettingsPagerCard pinned to page 2
                //    (uses a local shadow page binding so we don't affect the global pager)
               SettingsPagerCard(
                    page: $connectPageShadow,            // ← pinned to CONNECT
                    editingTarget: $editingTarget,
                    inputText: $inputText,
                    isEnteringField: $isEnteringField,
                    showBadPortError: $showBadPortError
                )
                .environmentObject(settings)
                .environmentObject(syncSettings)
                .onAppear { connectPageShadow = 2 }      // keep it on CONNECT
                .id("ConnectCardsEmbed")                 // avoid pager state bleed
    
                // No inline Notes here — the single source of truth is NotesCard in BIG mode.
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 0)
        }
    // ─────────────────────────────────────────────────────────────
        // NotesCard (BIG mode left pane)
        // ─────────────────────────────────────────────────────────────
    struct NotesCard: View {
                /// Your device's local note (same store whether Parent or Child)
                @Binding var notesLocal: String
                /// Mirrored parent's note (read-only on child; unused on parent)
                @Binding var notesParent: String
            let isChildLocked: Bool
            let roleIsParent: Bool
            @Environment(\.colorScheme) private var colorScheme
            private enum NoteTab: Hashable { case mine, parent }
        var bodyMinHeight: CGFloat = 160   // ← new, default keeps current behavior

            @State private var tab: NoteTab = .mine   // child-only Mine/Parent picker
    
            private let limit = 10_000
            // Header font: Roboto-SemiBold 64 (truncated)
            private var headerView: some View {
                HStack(spacing: 8) {
                    Text("NOTES")
                        .padding(.horizontal, 20)
                        .font(.custom("Roboto-SemiBold", size: 52))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.secondary)

                    if isChildLocked {
                        Image(systemName: "lock.fill")
                            .imageScale(.medium)
                            .opacity(0.75)
                        Text("Read-only")
                            .font(.custom("Roboto-Regular", size: 16))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    // Child-only Mine/Parent picker
                                        if !roleIsParent {
                                            Picker("", selection: $tab) {
                                                Text("Mine").tag(NoteTab.mine)
                                                Text("Parent").tag(NoteTab.parent)
                                            }
                                            .pickerStyle(.segmented)
                                            .frame(maxWidth: 240)
                                        }
                }
            }
    
        // Choose which buffer is visible/editable:
                    //  - Parent: always edit your local note
                    //  - Child : Mine = local note (editable if not child-locked), Parent = mirrored (read-only)
                    private var binding: Binding<String> {
                        if roleIsParent { return $notesLocal }
                        return (tab == .mine) ? $notesLocal : $notesParent
                    }
    
        private var isEditable: Bool {
                        // Parent can always edit local; Child can edit local only when not child-locked
                        if roleIsParent { return true }
                        return (tab == .mine) && !isChildLocked
                    }
    
            // Placeholder
            private var placeholder: String { "Add show notes…  (Markdown, autosaves)" }
             
            var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    headerView
                    ZStack(alignment: .topLeading) {
                        // Live inline Markdown via "ghost editor" (buttery & bulletproof)
                                            GhostMarkdownEditor(
                                                text: binding,
                                                isEditable: isEditable,
                                                characterLimit: limit
                                            )
                                            .frame(minHeight: bodyMinHeight)   // ← use the knob here
                                            .padding(12)  // ← inner padding for the typing area
                                            .accessibilityLabel("Notes editor")
                                            .accessibilityHint(isEditable ? "Editable notes" : "Read-only notes")
                                           .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    
                        // Placeholder
                        if binding.wrappedValue.isEmpty {
                            Text(placeholder)
                                .font(.custom("Roboto-Regular", size: 16))
                                .foregroundColor(.secondary)
                                .padding(.top, 10)
                                .padding(.leading, 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                          .overlay(                                   // ← outline
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                              .stroke(Color.gray.opacity(0.65), lineWidth: 1)
                              .padding(.horizontal, 20)
                          )
                          .padding(.bottom, 16)                  // ← breathing room below the outline
                }
                .padding(.top, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
     // ─────────────────────────────────────────────────────────────
     // PresetsCard (BIG iPad left pane, below Notes)
     // ─────────────────────────────────────────────────────────────
     struct PresetsCard: View {
         @Binding var list: [Preset]
         // Timer context (for enable/disable + actions)
         let isChildLinked: Bool       // (role==.child && isEnabled && isEstablished)
         let isRunningOrCountdownOrStop: Bool
         let isParent: Bool
         // Hooks supplied from MainScreen:
         let fillCountdownDigits: (Double) -> Void
         let addCueRelative: (Double) -> Void
         let addCueAbsolute: (Double) -> Void
         let loadAndBroadcastSheet: (String) -> Void
         let presentEditor: (_ editingIndex: Int?) -> Void
         let currentElapsed: Double
            let isRunning: Bool
         let stopActive: Bool
         
         private let cardCorner: CGFloat = 12
    
         var body: some View {
             VStack(alignment: .leading, spacing: 12) {
                 HStack(spacing: 8) {
                     Text("PRESETS")
                         .padding(.horizontal, 20)
                         .font(.custom("Roboto-SemiBold", size: 20))
                         .foregroundColor(.secondary)
                     Spacer()
                 }
    
                 // Single-row, horizontally scrolling chips
                  ScrollView(.horizontal, showsIndicators: false) {
                      LazyHGrid(
                              rows: [GridItem(.fixed(52), spacing: 8, alignment: .center)], // taller row for shadow
                              spacing: 8
                          ) {
                          ForEach(Array(list.enumerated()), id: \.element.id) { (idx, p) in
                             let disabled = tileDisabled(p)
                             let isPastAbs = (p.kind == .cueAbsolute) &&
                                             (p.seconds != nil) &&
                                             isRunning &&
                                             (p.seconds! <= currentElapsed)
                             PresetTile(
                               preset: p,
                               isDisabled: disabled,
                               isPastAbsolute: isPastAbs,
                               tap: { handleTap(p) },
                               edit: { presentEditor(idx) }
                             )
                           }
                          // Dashed "Add preset" chip
                          Button { presentEditor(nil) } label: {
                              HStack(spacing: 8) {
                                  Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                  Text("Add").font(.custom("Roboto-Regular", size: 16))
                              }
                              .padding(.horizontal, 12).frame(height: 36)
                              .overlay(
                                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                                      .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                      .foregroundStyle(.secondary.opacity(0.35))
                              )
                          }
                          .buttonStyle(.plain)
                          .disabled(isChildLinked)
                          .opacity(isChildLinked ? 0.5 : 1)
                      }
                      .padding(.vertical, 8)            // ← top padding for the chips row
                      .padding(.horizontal, 20)    // ← match 20pt horizontal rhythm
                  }
             }
             .padding(.top, 0)
         }
    
         private func tileDisabled(_ p: Preset) -> Bool {
             if isChildLinked { return true } // linked child: fully disabled
             switch p.kind {
                 case .cueRelative:
                     // Relative cue: allowed while running; only block during STOP
                     return stopActiveOnly()
                 case .cueAbsolute:
                     // Absolute cue: allowed while running, UNLESS time already passed
                     if let t = p.seconds, isRunning, t <= currentElapsed { return true }
                     return stopActiveOnly()
                 default:
                     // countdown & sheet presets disabled during running/countdown/stop
                     return isRunningOrCountdownOrStop
                 }
                 func stopActiveOnly() -> Bool { return isRunningOrCountdownOrStop && stopActive }
         }
    
         private func handleTap(_ p: Preset) {
             guard !tileDisabled(p) else { return }
             switch p.kind {
             case .countdown:
                 if let s = p.seconds { fillCountdownDigits(s) }
             case .cueRelative:
                 if let s = p.seconds { addCueRelative(s) }
             case .cueAbsolute:
                 if let s = p.seconds { addCueAbsolute(s) }
             case .sheet:
                 if let id = p.sheetIdentifier { loadAndBroadcastSheet(id) }
             }
         }
     }
    
     // Small tile with icon + label + context menu for edit/delete
    private struct PresetTile: View {
      let preset: Preset
      let isDisabled: Bool
      let isPastAbsolute: Bool
      let tap: () -> Void
      let edit: () -> Void
         @Environment(\.colorScheme) private var colorScheme
    
         var body: some View {
             HStack(spacing: 10) {
                 Image(systemName: preset.icon.isEmpty ? defaultIcon : preset.icon)
                     .font(.system(size: 18, weight: .semibold))
                     .frame(width: 24, height: 24)
                 Text(title)
                     .font(.custom("Roboto-Regular", size: 16))
                     .lineLimit(1)
                     .fixedSize(horizontal: true, vertical: false)
             }
             .frame(height: 46)
                .padding(.horizontal, 12)                              // ← side padding for chip
                .opacity((isDisabled || isPastAbsolute) ? 0.45 : 1)
                .padding(.vertical, 2)   // space for the shadow blur
                .padding(.horizontal, 0)
                .background(                                           // ← glass background
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                )
                .overlay(                                              // ← subtle stroke for definition
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.25), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { if !(isDisabled || isPastAbsolute) { tap() } }
                .allowsHitTesting(!(isDisabled || isPastAbsolute))
               .contextMenu { Button("Edit") { edit() }.disabled(isDisabled || isPastAbsolute) }
         }
    
         private var defaultIcon: String {
             switch preset.kind {
             case .countdown:   return "timer"
             case .cueRelative: return "flag.fill"
             case .cueAbsolute: return "flag"
             case .sheet:       return "music.note.list"
             }
         }
         private var title: String {
             if !preset.name.isEmpty { return preset.name }
             switch preset.kind {
             case .countdown:
                 return "Countdown \(format(preset.seconds ?? 0))"
             case .cueRelative:
                 return "Cue +\(format(preset.seconds ?? 0))"
             case .cueAbsolute:
                 return "Cue \(format(preset.seconds ?? 0))"
             case .sheet:
                 return "Load sheet"
             }
         }
         private func format(_ s: Double) -> String {
             let cs = Int(round(s * 100))
             let sec = cs / 100
             let cs2 = cs % 100
             let m = sec / 60
             let r = sec % 60
             return String(format: "%d:%02d.%02d", m, r, cs2)
         }
     }
        // ─────────────────────────────────────────────────────────────
        // MarkdownTextView: UITextView-backed live Markdown renderer
        // - Renders Markdown inline as you type
        // - Enforces a hard 10k character limit
        // - Editable toggling (child-locked read-only)
        // - Keeps caret visible as iOS manages scrolling within UITextView
        // ─────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────
     // iPad Landscape Tiering
    // ─────────────────────────────────────────────────────────────
    // iPad Window Modes
    enum IPadWindowMode { case mini, small, big }

    @inline(__always)
    private func iPadWindowMode(_ size: CGSize) -> IPadWindowMode {
        // These thresholds line up with iPadOS “quarter / half / full-ish” widths
        // across 11" and 12.9"/13" (Stage Manager tolerated).
        let w = size.width
        if w >= 782 { return .big }      // fullscreen / large SM width
        if w >= 500 { return .small }    // left/right split
        return .mini                     // corner / quadrant
    }


    // Pick a synthetic iPhone profile to get tighter inter-row spacing inside NumPadView
    private func numpadPhoneProfileSize(forColumnHeight h: CGFloat, remaining: CGFloat) -> CGSize {
        // iPhone “mini” & “small” baselines your NumPadView already adapts to
        let mini  = CGSize(width: 320, height: 260)
        let small = CGSize(width: 390, height: 844)
        // If vertical room is tight, force “mini” profile; otherwise “small”
        let useMini = (remaining < 350) || (h < 500)
        return useMini ? mini : small
    }

    
     private let devicesPaneW: CGFloat = 320
     private let windowInset: CGFloat = 20
    @ViewBuilder
    private func iPadLandscapeLayout() -> some View {
        GeometryReader { geo in
                let size = geo.size
                let mode = iPadWindowMode(size)
        
                let insetH: CGFloat = 20
                let insetT: CGFloat = 20
                let insetB: CGFloat = 20
        
            Group {
                // 📌 Force iPad mini in LANDSCAPE to use our mini landscape builder (no duplication).
                      if UIDevice.current.userInterfaceIdiom == .pad && (isPadMiniFamily && size.width > size.height) {
                        iPadLandscapeMini(size: size, insetH: insetH, insetT: insetT, insetB: insetB)
                      }
                  // ✅ Portrait iPads always use the unified portrait layout.
                 else if size.height >= size.width {
                    iPadUnifiedLayout()
                  }
                  // Default: tiered landscape iPad layouts
                  else {
                    Group {
                      switch mode {
                      case .mini:  iPadLandscapeMini(size: size, insetH: insetH, insetT: insetT, insetB: insetB)
                    case .small: iPadLandscapeSmall(size: size, insetH: insetH, insetT: insetT, insetB: insetB)
                      case .big:   iPadLandscapeBig(size: size, insetH: insetH, insetT: insetT, insetB: insetB)
                      }
                    }
                    .id(mode)
                    .animation(nil, value: mode)
                  }
                }
            }
    }

    @ViewBuilder
    private func iPadLandscapeMini(size: CGSize, insetH: CGFloat, insetT: CGFloat, insetB: CGFloat) -> some View {
        GeometryReader { fullGeo in
            let hm: CGFloat = 8
            let w  = fullGeo.size.width  - (hm * 2)
            let h  = fullGeo.size.height * 0.22   // phone-landscape proportion
//ipad mini timercard for when in landscape
            VStack(spacing: 8) {
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
                    // phone style ⇒ no affordance text
                    leftHint: "",
                    rightHint: "",
                    stopStep: stopStep,
                    makeFlashed: makeFlashedOverlay,
                    isCountdownActive: willCountDown,
                    events: events,
                    onClearEvents: {
                        dismissActiveCueSheet()
                        hasUnsaved = false
                    }
                )
                .frame(width: w, height: h)
            }
            .position(x: fullGeo.size.width / 2, y: fullGeo.size.height / 2) // (d) vertically centered
            // defensively strip any parent-applied effects
            .compositingGroup()
            .offset(y: 200)
            .shadow(color: .clear, radius: 0)
            // (a)(c) tell TimerCard to be phone-simple: no background/shadow, no overlays/dividers, no “SYNC/ EVENTS VIEW”
            .environment(\.phoneStyleOnMiniLandscape, true)
            // (b) lift the badge row ~20pt upwards
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    private func iPadLandscapeSmall(size: CGSize, insetH: CGFloat, insetT: CGFloat, insetB: CGFloat) -> some View {
        let contentW = size.width  - insetH*2
        let contentH = size.height - insetT - insetB

        // Wider and centered
        let columnW  = min(max(580, floor(contentW * 0.60)), contentW)
        // Make the column fill the full usable height so the footer aligns with BIG mode
               let columnH  = contentH
        return VStack(spacing: 0) {
            IPhonePortraitColumn(width: columnW, height: columnH, mode: .small)
                .frame(width: columnW, height: columnH, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .center)   // center column
        }
        // Match BIG mode’s vertical offset so bottom buttons align exactly
                .frame(width: contentW, height: contentH, alignment: .top)
                .padding(.top, max(0, insetT + 64))
                .padding(.horizontal, insetH)
                .padding(.bottom, insetB)
    }


    
    @ViewBuilder
    private func iPadLandscapeBig(size: CGSize, insetH: CGFloat, insetT: CGFloat, insetB: CGFloat) -> some View {
        @Environment(\.colorScheme) var colorScheme

        @Namespace  var leftPaneNS
        let contentW = size.width  - insetH*2
        let contentH = size.height - insetT - insetB
        let rightW   = floor(contentW * 0.4)
        let leftW    = contentW - rightW - 16
        // NEW: computed column height (take almost all vertical space with a floor)
        let columnH  = min(max(5, floor(contentH * 0.96)), contentH)
        let shouldPaginateLeftPane: Bool = {
            if isLargePad129Family {
                // 12.9"/13": user-controlled via Settings
                return settings.leftPanePaginateOnLargePads
            } else {
                // 10.9"/11": always paginated
                return true
            }
        }()

        // 12.9/13" keeps the old +64 pad; 10.9" gets a -20 lift (offset, not padding)
           let extraTopPad:  CGFloat = isLargePad129Family ? 64 : 0
           let extraTopLift: CGFloat = isLargePad129Family ? 0  : -40
        // Align the two panes by their TOP edges, add vertical divider between panes
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 12) {
                // ─────────────── Row 1: Launch logo (ALWAYS SHOWN, never paginated)
                ZStack {
                    Image(settings.appTheme == .dark ? "LaunchLogoDarkMode" : "LaunchLogo")
                    
                    .resizable()
                    .scaledToFill()          // ← fill height
                    .frame(maxWidth: 300, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
                }
                .frame(height: 40)           // ← container height; tweak (64–84) to taste
                .offset(y: -20)
                .offset(
                  x: ((isPadDevice && (isPad109Family || isPad11Family)) && (size.width > size.height))
                     ? -192
                     : -232
                )


                

                // ─────────────── Row 2: Devices / Notes (the ONLY thing that paginates)
                // ─────────────── Row 2: Devices / Notes (the ONLY thing that paginates)
                Group {
                    if shouldPaginateLeftPane {
                        ZStack(alignment: .top) {
                            if leftPaneTab == 0 {
                                ConnectedDevicesPaneInline()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .matchedGeometryEffect(id: "leftPaneContent", in: leftPaneNS)
                                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                            } else {
                                let notesMinBase: CGFloat = {
                                    if isLargePad129Family { return 500 }                // 12.9"/13"
                                    if isPad109Family || isPad11Family { return 320 }    // 10.9"/11"
                                    return 500                                           // default/safety
                                }()
                                NotesCard(
                                    notesLocal:   $notesLocal,
                                    notesParent:  $notesParent,
                                    isChildLocked: uiLockedByParent,
                                    roleIsParent: (syncSettings.role == .parent),
                                    bodyMinHeight: max(notesMinBase, columnH * 0.70)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .layoutPriority(1)
                                .matchedGeometryEffect(id: "leftPaneContent", in: leftPaneNS)
                                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                            }
                        }
                        .animation(
                            {
                                if #available(iOS 17, *) {
                                    return .snappy(duration: 0.26, extraBounce: 0.25)
                                } else {
                                    return .easeInOut(duration: 0.26)
                                }
                            }(),
                            value: leftPaneTab
                        )
                    } else {
                        VStack(spacing: 12) {
                            ConnectedDevicesPaneInline()
                                .frame(maxWidth: .infinity, alignment: .top)

                            NotesCard(
                                notesLocal:   $notesLocal,
                                notesParent:  $notesParent,
                                isChildLocked: uiLockedByParent,
                                roleIsParent: (syncSettings.role == .parent)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)



                // ─────────────── Row 2.5: Centered page nav (only when paginating)
                if shouldPaginateLeftPane {
                    LeftPaneNav(tab: $leftPaneTab, titles: ["Devices", "Notes"])
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }

                // ─────────────── Row 3: Presets (unaffected)
                PresetsCard(
                    list: Binding(
                        get: { loadPresets() },
                        set: { savePresets($0); presetsDirtyNonce &+= 1 }
                    ),
                    isChildLinked: (syncSettings.role == .child && syncSettings.isEnabled && syncSettings.isEstablished),
                    isRunningOrCountdownOrStop: (phase == .running || phase == .countdown || stopActive),
                    isParent: (syncSettings.role == .parent),
                    fillCountdownDigits: { secs in
                        countdownDigits = timeToDigits(secs)
                        countdownDuration = secs
                        countdownRemaining = secs
                        parentMode = .sync
                    },
                    addCueRelative: { ofs in addCueFromPreset(at: ofs, treatAsAbsolute: false) },
                    addCueAbsolute: { absSec in addCueFromPreset(at: absSec, treatAsAbsolute: true) },
                    loadAndBroadcastSheet: { sheetID in
                        openCueSheets()
                        if let sheet = CueLibraryStore.shared.sheet(namedOrId: sheetID) {
                            let shouldBroadcast = (syncSettings.role == .parent && syncSettings.isEnabled)
                            apply(sheet, broadcastBadge: shouldBroadcast)
                            if shouldBroadcast { broadcast(sheet) }
                        }
                    },
                    presentEditor: { idx in pendingPresetEditIndex = idx; showPresetEditor = true },
                    currentElapsed: displayMainTime(),
                    isRunning: (phase == .running),
                    stopActive: stopActive
                )
                .id(presetsDirtyNonce)
            }
            .frame(width: leftW, height: columnH, alignment: .top)

        
                    // VERTICAL DIVIDER BETWEEN PANES
                    Rectangle().fill(.separator).frame(width: 1).opacity(0.5)
            IPhonePortraitColumn(width: rightW, height: columnH, mode: .big)
                .frame(width: rightW, height: columnH, alignment: .top)
        }
                .frame(width: contentW, height: contentH, alignment: .top)
                    .padding(.top, max(0, insetT + extraTopPad))   // never negative
                    .offset(y: extraTopLift)                       // apply the -20 only on 10.9"
                    .padding(.horizontal, insetH)
                    .padding(.bottom, insetB)
    }



     private func phonePortraitCardWidth() -> CGFloat {
         // Match your iPhone portrait card’s effective width (content width minus gutters).
         return 390
     }
    //our ipad small pane "iphone column" view
    @ViewBuilder
    private func IPhonePortraitColumn(
      width: CGFloat,
      height: CGFloat,
      mode: IPadWindowMode? = nil   // ← add this (nil = not in iPad landscape tiers)
    ) -> some View {
        GeometryReader { g in
            
            
        ZStack(alignment: .bottom) {
            let isPad109 = isPadDevice && isPad109Family   // 10.9" only

                // Single source of truth so TimerCard width == Mode Bar width
                let colPad: CGFloat = 20
            let innerW = max(360, width - colPad * 2)   // exact inner width (Timer/Bar/Numpad share this)

            // Safe-area aware measurements
            let safeTop  = g.safeAreaInsets.top
            let safeBot  = g.safeAreaInsets.bottom

            
            // Visual constants (slightly tighter on 10.9")
            let barH: CGFloat       = isPad109 ? 74 : 80
            let buttonsH: CGFloat   = 44
            let footerPad: CGFloat  = 0
            let cardH: CGFloat      = max(240, min(height * (isPad109 ? 0.28 : 0.30), 500))

            // Tier spacing: gap ABOVE the mode bar (tighter on 10.9")
            let vSpacingAboveBar: CGFloat = {
                switch mode {
                case .big?:   return isPad109 ? 28 : 32
                case .small?: return isPad109 ? 32 : 40
                case .mini?:  return 0
                case nil:     return 32
                }
            }()

            // (existing)
            let vSpacingBetween: CGFloat = 12
            let usedTop = cardH + vSpacingAboveBar + barH + vSpacingBetween
            let reservedFooter = buttonsH + footerPad + g.safeAreaInsets.bottom
            let remaining = max(0, height - usedTop - reservedFooter)

            // ► NUMPAD HEIGHT — key fix:
            //    On 10.9" let it use the *actual* remaining space (no min-height clamp).
            //    On others, keep your current min/max behavior.
            let numpadMinH_DefaultBig:  CGFloat = 520
            let numpadMaxH_DefaultBig:  CGFloat = 650
            let numpadMinH_DefaultSm:   CGFloat = 400
            let numpadMaxH_DefaultSm:   CGFloat = 600

            let targetNumpad: CGFloat = {
                if isPad109 {
                    // Fill whatever remains, minus a tiny cushion so it never collides with the footer
                    return max(0, remaining - 8)
                } else {
                    let minH = (mode == .big ? numpadMinH_DefaultBig : numpadMinH_DefaultSm)
                    let maxH = (mode == .big ? numpadMaxH_DefaultBig : numpadMaxH_DefaultSm)
                    return max(minH, min(maxH, remaining))
                }
            }()

            // Tighter row height hint on 10.9" so keys render a touch shorter
            let hHint: CGFloat = {
                if isPad109 { return (mode == .big ? 18 : 24) }
                return (mode == .big ? 20 : 30)
            }()
            let tightNumpadProfile = CGSize(width: innerW, height: hHint)


            let isLandscape = g.size.width > g.size.height
                let lift: CGFloat = (isPadDevice && isPad109Family && isLandscape) ? 120 : 0

            // Smaller target & hard cap specifically for SMALL (others unchanged)
            let maxFraction: CGFloat = {
                switch mode {
                case .small?: return 0.46   // ensure there’s room but not oversized
                case .big?:   return 0.46
                case .mini?:  return 0.26
                default:      return 0.46
                }
            }()

            let baselineNumpadHeight: CGFloat = 1500

            let numpadPhoneProfileSize =
                isPadDevice
                ? numpadPhoneProfileSize(forColumnHeight: height, remaining: targetNumpad)
                : CGSize(width: width, height: height)

            

            VStack(alignment: .leading, spacing: vSpacingBetween) {
                // 1) TIMER — nudged up slightly
                CardMorphSwitcher(
                    mode: $parentMode,
                    timer:
                        // ipad timercard in landscape, using iphone portrait timercard as the head of a columned right pane, hence the name
                        VStack(spacing: 8) {
                            TimerCard(
                                mode: $parentMode,
                                flashZero: $flashZero,
                                isRunning: phase == .running,
                                flashStyle: settings.flashStyle,
                                flashColor: settings.flashColor,
                                syncDigits: countdownDigits,
                                stopDigits: eventMode == .stop ? stopDigits
                                : eventMode == .cue  ? cueDigits
                                :                      restartDigits,
                                phase: phase,
                                mainTime: displayMainTime(),
                                stopActive: stopActive,
                                stopRemaining: stopRemaining,
                                leftHint: "START POINT",
                                rightHint: "DURATION",
                                stopStep: stopStep,
                                makeFlashed: makeFlashedOverlay,
                                isCountdownActive: willCountDown,
                    events: events,
                    onClearEvents: {
                        dismissActiveCueSheet()
                        hasUnsaved = false
                    }
                )
                .environmentObject(cueDisplay)
            }
                        .allowsHitTesting(!(lockActive || (isChildTabLockActive && parentMode == .sync))),
                    settings:
                        SettingsPagerCard(
                            page: $settingsPage,
                            editingTarget: $editingTarget,
                            inputText: $inputText,
                            isEnteringField: $isEnteringField,
                            showBadPortError: $showBadPortError
                        )
                        .environmentObject(settings)
                        .environmentObject(syncSettings)
                )
                .frame(height: cardH)
                .animation(
                  {
                    if #available(iOS 17, *) { .snappy(duration: 0.26, extraBounce: 0.25) }
                    else { .easeInOut(duration: 0.26) }
                  }(),
                  value: parentMode
                )
                .zIndex(2) // card always above
                // Make timer width match the mode bar by using the same horizontal padding:
                      .padding(.horizontal, colPad)
                
                // 2) MODE BAR — pushed down ~20pt
                if parentMode == .sync || parentMode == .stop {
                    ZStack {
                        if !settings.lowPowerMode {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(height: barH)
                                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
                        }
                        ModeBarMorphSwitcher(isSync: parentMode == .sync) {
                            Group {
                                SyncBar(
                                    isCounting: isCounting,
                                    isSyncEnabled: syncSettings.isEnabled,
                                    onOpenSyncSettings: {
                                        previousMode = parentMode
                                        parentMode   = .settings
                                        settingsPage = 2
                                    },
                                    onToggleSyncMode: {
                                        toggleSyncMode()
                                    },
                                    onRoleConfirmed: { newRole in
                                        let wasEnabled = syncSettings.isEnabled
                                        if wasEnabled {
                                            if syncSettings.role == .parent { syncSettings.stopParent() }
                                            else                           { syncSettings.stopChild() }
                                            syncSettings.isEnabled = false
                                        }
                                        syncSettings.role = newRole
                                        if wasEnabled {
                                            switch syncSettings.connectionMethod {
                                            case .network, .bluetooth, .bonjour:
                                                if newRole == .parent { syncSettings.startParent() }
                                                else                  { syncSettings.startChild() }
                                            }
                                            syncSettings.isEnabled = true
                                        }
                                    }
                                )
                                .environmentObject(syncSettings)
                            }
                        } events: {
                            // (unchanged)
                            EventsBar(
                                events: $events,
                                eventMode: $eventMode,
                                isPaused: phase == .paused,
                                unsavedChanges: hasUnsaved,
                                onOpenCueSheets: { openCueSheets() },
                                isCounting: isCounting,
                                onAddStop: commitStopEntry,
                                onAddCue:  commitCueEntry,
                                onAddRestart: commitRestartEntry,
                                cueSheetAccent: settings.flashColor
                            )
                        }

                    }
                    .padding(.top, vSpacingAboveBar)
                    .padding(.horizontal, colPad)
                }
                
                // ─────────────────────────────────────────────────────────────
                // 3) NUMPAD — auto-resizes, no clipping
                // REPLACE your NumPad block with this:
                // ─────────────────────────────────────────────────────────────
                NumPadView(
                    parentMode:   $parentMode,
                    settingsPage: $settingsPage,
                    isEntering:   $isEnteringField,
                    onKey: { key in
                        if parentMode == .settings && isEnteringField {
                            switch key {
                            case .digit(let n): inputText.append(String(n))
                            case .dot:          inputText.append(".")
                            case .backspace:    _ = inputText.popLast()
                            case .enter:        confirm(inputText)
                            default:            break
                            }
                            return
                        }
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
                            default: break
                            }
                        } else {
                            switch key {
                            case .chevronLeft:  settingsPage = (settingsPage + numberOfPages - 1) % numberOfPages
                            case .chevronRight: settingsPage = (settingsPage + 1) % numberOfPages
                            default: break
                            }
                        }
                    },
                    onSettings: {
                        let anim: Animation = {
                            if #available(iOS 17, *) {
                                return parentMode == .settings
                                ? .snappy(duration: 0.26, extraBounce: 0.25)
                                : .snappy(duration: 0.24, extraBounce: 0.25)
                            } else { return .easeInOut(duration: 0.26) }
                        }()
                        if parentMode == .settings {
                            withAnimation(anim) { parentMode = previousMode }
                        } else {
                            withAnimation(anim) { previousMode = parentMode; parentMode = .settings }
                        }
                    },
                    lockActive: padLocked
                )
                .frame(width: innerW, height: targetNumpad, alignment: .top)   // exact width + visible multiple rows
                .layoutPriority(1)
                .padding(.top, parentMode == .settings ? 111 : 0)

                .clipped()
                
                // Tight rows + correct width handed to NumPad
                .environment(\.containerSize, tightNumpadProfile)
                .padding(.horizontal, colPad)   // match Timer/Bar width exactly
                .zIndex(1) // stays below the card
            }
            
                          
            
                        // ─────────────────────────────────────────────────────────────
                        // Column-local footer, pinned to the bottom of this pane
                        // ─────────────────────────────────────────────────────────────
                        ZStack {
                            Color.clear.contentShape(Rectangle()) // full-width tappable slab
            
                            // Sync footer (only interactive in SYNC)
                            SyncBottomButtons(
                                showResetButton:   parentMode == .sync,
                                showPageIndicator: parentMode == .settings,
                                currentPage:       settingsPage + 1,
                                totalPages:        numberOfPages,
                                isCounting:        isCounting,
                                startStop:         toggleStart,
                                reset:             resetAll
                        )
                        .disabled(lockActive || uiLockedByParent || parentMode != .sync)
                           .opacity(parentMode == .sync ? (uiLockedByParent ? 0.35 : 1.0)
                                                         : (parentMode == .settings ? 0.3 : 0.0))
                            .allowsHitTesting(parentMode == .sync)
            
                            // Events footer (only interactive in STOP/Events)
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
                            .disabled(lockActive || uiLockedByParent)
                            .opacity(parentMode == .stop ? (uiLockedByParent ? 0.35 : 1.0) : 0)
                            .allowsHitTesting(parentMode == .stop)
                        }
                        .frame(height: buttonsH + footerPad)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
            // ↓ Ensure SMALL mode footer sits at the same vertical position as BIG
                                    //    (positive y moves it DOWN; tune if your hardware shows a 1–2pt difference)
                        .offset(y: (mode == .small ? (isPad109 ? 24 : 48) : 0))
                        .offset(y: ((isPadDevice && (isPad109Family || isPad11Family)) && (g.size.width > g.size.height))
                                    ? (mode == .small ? -100 : -140)
                                    : 0)



                                    // Keep the tappable area with the visual
                                    .contentShape(Rectangle())
                                    .allowsHitTesting(true)
                        .zIndex(1000) // top within the column only
                    }
            }
        }
    


    // ─────────────────────────────────────────────────────────────
    // iPad unified layout: full-width TimerCard + full-width bars
    // ─────────────────────────────────────────────────────────────
    @ViewBuilder
    private func iPadUnifiedLayout() -> some View {
        @Environment(\.phoneStyleOnMiniLandscape)
        var phoneStyleOnMiniLandscape

        GeometryReader { geo in
            
            let numpadScale: CGFloat = 0.65   // tweak 0.80–0.90 to taste
            let size = geo.size

            let winW = geo.size.width
            let winH = geo.size.height
            let isLandscape = winW > winH
            let topSafe = geo.safeAreaInsets.top
            let isBigPortrait = (!isLandscape && winH >= 1360)   // 12.9/13 only, full-height
            // Mini in PORTRAIT = short long-edge in points (mini ~1133–1135pt)
                let isMiniPortraitPoints = (UIDevice.current.userInterfaceIdiom == .pad
                                            && !isLandscape
                                            && max(winW, winH) <= 1135)
            let footerButtonsH: CGFloat = 44
            let footerPad: CGFloat = 10
            let reservedFooter = footerButtonsH + footerPad + geo.safeAreaInsets.bottom
            // Top band height derived from the actual window size
            let baseTopH: CGFloat = isLandscape
                    ? max(360, min(winH * 0.50, 640))
                    : (
                        isMiniPortraitPoints
                        ? max(220, min(winH * 0.32, 440))  // ⬅︎ Portrait mini only: noticeably smaller
                        : max(300, min(winH * 0.42, 560))
                      )
             // 12.9" portrait: grow the top band so the next section (mode bar) starts lower
             let isTallPadPortrait = (UIDevice.current.userInterfaceIdiom == .pad && !isLandscape && winH >= 1000)
             let topH: CGFloat = baseTopH + (isTallPadPortrait ? 24 : 0)

            // Mode bar height (visual only)
            let barH: CGFloat = settings.lowPowerMode ? 72 : 88
            // sections above NumPad: top card + mode bar + small gap
            let usedTop = topH
                       + ((parentMode == .sync || parentMode == .stop) ? (barH + 20) : 0)
                       + 8

            let remainingForNumPad = max(0, winH - usedTop - reservedFooter)

            // Pick a synthetic iPhone profile only on iPad
            let numpadPhoneProfile =
                isPadDevice
                ? numpadPhoneProfileSize(forColumnHeight: winH, remaining: remainingForNumPad)
                : CGSize(width: winW, height: winH)

            
            // 12.9" portrait only (Stage Manager tolerant)
            let nativeMax = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
            let is129Portrait = (UIDevice.current.userInterfaceIdiom == .pad && nativeMax >= 2732 && !isLandscape)
            // lifts
            let modeBarLift: CGFloat = is129Portrait ? 24 : 0
            let bottomLift: CGFloat  = is129Portrait ? 120 : 0
            let extraH = max(0, geo.size.height - 1194)
            let baseY = 1080 + extraH * 0.70                   // your existing placement
            let y = baseY + (isLargePad129Family ? 72 : 0)     // ↓ only on 12.9/13" (tune 56–96)



            VStack(spacing: 20) {
                // ── TOP CARD: TimerCard ⇄ SettingsPagerCard (same size/placement) ──
                ZStack(alignment: .top) {
                    Color.clear // keep background full-bleed

                    CardMorphSwitcher(
                        mode: $parentMode,
                        timer:
                            VStack(spacing: 8) {
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
                                    events: events,
                                    onClearEvents: {
                                        dismissActiveCueSheet()
                                        hasUnsaved = false
                                    }
                                )
                                .environmentObject(cueDisplay)
                            }
                            .allowsHitTesting(!(lockActive || (isChildTabLockActive && parentMode == .sync)))
                            .transition(.opacity)
                            .padding(.horizontal, 20)
                            .overlay(alignment: .topLeading) {
                                if !isLandscape {
                                    Color.clear
                                        .frame(width: 1, height: 1)
                                        .popover(isPresented: $showCueSheets, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                            NavigationStack {
                                                ScrollView {
                                                    CueSheetsSheet(
                                                        isPresented: $showCueSheets,
                                                        openNewBlankEditor: $pendingCueSheetCreateFromWhatsNew,
                                                        canBroadcast: { syncSettings.role == .parent && syncSettings.isEnabled },
                                                        onLoad: { sheet in
                                                            apply(sheet, broadcastBadge: false)
                                                        },
                                                        onBroadcast: { sheet in
                                                            apply(sheet, broadcastBadge: true)
                                                            broadcast(sheet)
                                                        }
                                                    )
                                                    .environmentObject(settings)
                                                    .padding(16)
                                                }
                                                .navigationTitle("Cue Sheets")
                                            }
                                            .frame(
                                                width: min(700, geo.size.width  - 120),
                                                height: min(700, geo.size.height - 200)
                                            )
                                        }
                                }
                            },
                        settings:
                            SettingsPagerCard(
                                page: $settingsPage,
                                editingTarget: $editingTarget,
                                inputText: $inputText,
                                isEnteringField: $isEnteringField,
                                showBadPortError: $showBadPortError
                            )
                            .environmentObject(settings)
                            .environmentObject(syncSettings)
                            .offset(y: -20)
                            .allowsHitTesting(true)
                            .transition(.opacity)
                    )

                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    .environment(\.containerSize, geo.size)

                    // Title overlay for Settings pages
                    if parentMode == .settings {
                        let pageTitle: String = {
                            switch settingsPage {
                            case 0: return "THEME"
                            case 1: return "SET"
                            case 2: return "CONNECT"
                            case 3: return "ABOUT"
                            default: return ""
                            }
                        }()

                        // Float it at the top-left, same horizontal padding as the card
                        Text(pageTitle)
                            .font(.custom("Roboto-SemiBold", size: 28))
                            .foregroundColor(.secondary)
                            .offset(y: 1066)
                            .padding(.horizontal, 20)
                            .allowsHitTesting(false)  // pure label
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                .frame(width: winW, height: topH, alignment: isLandscape ? .center : .top)
                .animation(
                    {
                        if #available(iOS 17, *) {
                            return parentMode == .settings
                            ? .snappy(duration: 0.26, extraBounce: 0.25)
                            : .snappy(duration: 0.24, extraBounce: 0.25)
                        } else {
                            return .easeInOut(duration: 0.26)
                        }
                    }(),
                    value: parentMode
                )
                Spacer(minLength: modeBarLift)  // 12.9" portrait only adds 24pt
                // ── MODE BAR (always *below* the TimerCard) ─────────────────
                if parentMode == .sync || parentMode == .stop {
                    ZStack {
                        if !settings.lowPowerMode && !phoneStyleOnMiniLandscape {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(height: barH)
                                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
                        }
                        ModeBarMorphSwitcher(isSync: parentMode == .sync) {
                            Group {
                                SyncBar(
                                    isCounting: isCounting,
                                    isSyncEnabled: syncSettings.isEnabled,
                                    onOpenSyncSettings: {
                                        previousMode = parentMode
                                        parentMode   = .settings
                                        settingsPage = 2
                                    },
                                    onToggleSyncMode: {
                                        toggleSyncMode()
                                    },
                                    onRoleConfirmed: { newRole in
                                        let wasEnabled = syncSettings.isEnabled
                                        if wasEnabled {
                                            if syncSettings.role == .parent { syncSettings.stopParent() }
                                            else                           { syncSettings.stopChild() }
                                            syncSettings.isEnabled = false
                                        }
                                        syncSettings.role = newRole
                                        if wasEnabled {
                                            switch syncSettings.connectionMethod {
                                            case .network, .bluetooth, .bonjour:
                                                if newRole == .parent { syncSettings.startParent() }
                                                else                  { syncSettings.startChild() }
                                            }
                                            syncSettings.isEnabled = true
                                        }
                                    }
                                )
                                .environmentObject(syncSettings)
                            }
                        } events: {
                          
                            EventsBar(
                                events: $events,
                                eventMode: $eventMode,
                                isPaused: phase == .paused,
                                unsavedChanges: hasUnsaved,
                                onOpenCueSheets: { openCueSheets() },
                                isCounting: isCounting,
                                onAddStop: commitStopEntry,
                                onAddCue:  commitCueEntry,
                                onAddRestart: commitRestartEntry,
                                cueSheetAccent: settings.flashColor
                            )
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)   // ← 20pt side padding (mode bar)
                    .padding(.top, 20)   // +24pt on 12.9" portrait
                }
                // ── NUMPAD (below the mode bar) ───────────────────────────────
                NumPadView(
                    parentMode:   $parentMode,
                    settingsPage: $settingsPage,
                    isEntering:   $isEnteringField,
                    onKey: { key in
                        // ① If editing an IP/Port in Settings
                        if parentMode == .settings && isEnteringField {
                            switch key {
                            case .digit(let n): inputText.append(String(n))
                            case .dot:          inputText.append(".")
                            case .backspace:    _ = inputText.popLast()
                            case .enter:        confirm(inputText)
                            default:            break
                            }
                            return
                        }

                        // ② Normal timer/events handling
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
                            // ③ In Settings (not editing): page flips
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
                        let anim: Animation = {
                            if #available(iOS 17, *) {
                                return parentMode == .settings
                                ? .snappy(duration: 0.26, extraBounce: 0.25)
                                : .snappy(duration: 0.24, extraBounce: 0.25)
                            } else {
                                return .easeInOut(duration: 0.26)
                            }
                        }()
                        if parentMode == .settings {
                            withAnimation(anim) { parentMode = previousMode }
                        } else {
                            withAnimation(anim) {
                                previousMode = parentMode
                                parentMode   = .settings
                            }
                        }
                    },
                    lockActive: padLocked
                )
                .padding(.horizontal, 20)               // keep the 20pt side padding
                // Do NOT float into the card when in Settings mode
                               .padding(.top, parentMode == .settings ? 0 : -20)
                               .scaleEffect(numpadScale, anchor: .top) // uniformly shrink rows & keys
                .clipped()                              // avoid any scaled overflow
                .environment(\.containerSize, numpadPhoneProfile) // ⬅️ this line makes rows tighter on iPad
                .zIndex(1)   // stays below the card
                // Reserve space so content doesn't sit under the footer buttons.
                                .padding(.bottom, footerButtonsH + footerPad)
                
                // Reserve space for the global footer; nothing local here anymore.
                                Spacer(minLength: 0)
                                    .frame(height: footerButtonsH + footerPad)
            }
            .frame(width: winW, height: winH, alignment: .top)
            .environment(\.containerSize, geo.size)
            // ⬆︎ Force a visible lift only on iPad mini portrait
            .offset(y: (isPadDevice && isPadMiniFamily)
                        ? -80 : 0)
                      


        }
        .safeAreaInset(edge: .bottom) {
            // Bottom buttons for iPad portrait (unified layout)
            ZStack {
                // SYNC footer
                SyncBottomButtons(
                    showResetButton:   parentMode == .sync,
                    showPageIndicator: parentMode == .settings,
                    currentPage:       settingsPage + 1,
                    totalPages:        numberOfPages,
                    isCounting:        isCounting,
                    startStop:         toggleStart,
                    reset:             resetAll
                )
                .disabled(lockActive || uiLockedByParent || parentMode != .sync)
                .opacity(
                    parentMode == .sync
                    ? (uiLockedByParent ? 0.35 : 1.0)
                    : (parentMode == .settings ? 0.3 : 0.0)
                )
                .allowsHitTesting(parentMode == .sync)

                // EVENTS footer
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
                .disabled(lockActive || uiLockedByParent)
                .opacity(parentMode == .stop ? (uiLockedByParent ? 0.35 : 1.0) : 0)
                .allowsHitTesting(parentMode == .stop)
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .offset(y:
                isLargePad129Family ? 1200 :
                (isPad109Family || isPad11Family) ? 1080 :
                (isPadMiniFamily ? 920 : 1200)
            )
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
        let raw = displayMainTime()
            .formattedAdaptiveCS(alwaysShowHours: settings.showHours)  // was: .csString
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
    
    private func installDisciplineProviders() {
        syncSettings.elapsedProvider = { [self] in
            if stopActive { return pausedElapsed }
            switch phase {
            case .countdown:
                return countdownRemaining
            case .running, .paused, .idle:
                return elapsed
            }
        }
        syncSettings.elapsedAtProvider = { [self] timestamp in
            if stopActive { return pausedElapsed }
            if phase == .running, let startDate {
                return max(0, timestamp - startDate.timeIntervalSince1970)
            }
            if phase == .countdown {
                return countdownRemaining
            }
            return elapsed
        }
        syncSettings.isTimerAdvancingProvider = { [self] in
            phase == .running && !stopActive
        }
    }

    private let stopSettleThresholdNs: UInt64 = 10_000_000
    private let stopSettleDuration: TimeInterval = 0.12
    private let stopSettleBurstCount: Int = 3
    private let stopSettleBurstSpacingMs: Int = 40

    private func elapsedToNs(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, (seconds * 1_000_000_000).rounded()))
    }

    private func capturePlaybackStopAnchor(elapsedSeconds: TimeInterval) {
        guard playbackStopAnchorElapsedNs == nil else { return }
        playbackStopAnchorUptimeNs = DispatchTime.now().uptimeNanoseconds
        playbackStopAnchorElapsedNs = elapsedToNs(elapsedSeconds)
        if syncSettings.role == .parent,
           syncSettings.isEnabled,
           syncSettings.connectionMethod != .bluetooth {
            syncSettings.clockSyncService?.requestBurstSyncSamples(count: stopSettleBurstCount,
                                                                   spacingMs: stopSettleBurstSpacingMs)
        }
    }

    private func clearPlaybackStopAnchor() {
        playbackStopAnchorElapsedNs = nil
        playbackStopAnchorUptimeNs = nil
    }

    private func applyStopAnchor(targetElapsedNs: UInt64, allowSlew: Bool) {
        let targetSeconds = Double(targetElapsedNs) / 1_000_000_000
        let currentSeconds = childDisplayElapsed
        let deltaNs = Int64((currentSeconds - targetSeconds) * 1_000_000_000)
        if !allowSlew || UInt64(abs(deltaNs)) <= stopSettleThresholdNs {
            stopSettleCancellable?.cancel()
            childDisplayElapsed = targetSeconds
            elapsed = targetSeconds
            return
        }
        startStopSettle(from: currentSeconds, to: targetSeconds, duration: stopSettleDuration)
    }

    private func startStopSettle(from: TimeInterval, to: TimeInterval, duration: TimeInterval) {
        stopSettleCancellable?.cancel()
        let startUptime = ProcessInfo.processInfo.systemUptime
        stopSettleCancellable = Timer.publish(every: dt, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let now = ProcessInfo.processInfo.systemUptime
                let progress = min(1, (now - startUptime) / duration)
                let value = from + (to - from) * progress
                childDisplayElapsed = value
                elapsed = value
                if progress >= 1 {
                    stopSettleCancellable?.cancel()
                    stopSettleCancellable = nil
                    childDisplayElapsed = to
                    elapsed = to
                }
            }
    }

    private func scheduleStopAnchorReassertion(seq: UInt64?, targetElapsedNs: UInt64, count: Int, spacingMs: Int) {
        stopSettleFinalWorkItem?.cancel()
        let delay = max(0.05, Double(count * spacingMs) / 1000.0)
        let work = DispatchWorkItem {
            guard phase != .running else { return }
            if let seq, lastStopFinalSettleSeq == seq { return }
            applyStopAnchor(targetElapsedNs: targetElapsedNs, allowSlew: true)
            lastStopFinalSettleSeq = seq
        }
        stopSettleFinalWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func requestStopSettleBurstIfNeeded(seq: UInt64?) {
        guard phase != .running else { return }
        let token = seq ?? 0
        if let last = lastStopBurstSeq, last == token { return }
        if syncSettings.connectionMethod != .bluetooth {
            syncSettings.clockSyncService?.requestBurstSyncSamples(count: stopSettleBurstCount,
                                                                   spacingMs: stopSettleBurstSpacingMs)
        }
        lastStopBurstSeq = token
    }

    private func updateChildRunningElapsed(dt: TimeInterval) -> TimeInterval {
        let now = Date()
        if let targetStartDate = childTargetStartDate {
            if startDate == nil {
                startDate = targetStartDate
            } else if let currentStartDate = startDate {
                let error = currentStartDate.timeIntervalSince(targetStartDate)
                let maxAdjust = childMaxSlewRate * dt
                if maxAdjust > 0 {
                    let clamped = min(max(error, -maxAdjust), maxAdjust)
                    startDate = currentStartDate.addingTimeInterval(-clamped)
                }
            }
        }

        let candidate = now.timeIntervalSince(startDate ?? now)
        if candidate >= childDisplayElapsed {
            childDisplayElapsed = candidate
        }
        return childDisplayElapsed
    }

    //──────────────────── timer engine ────────────────────────────────────
    private let dt: TimeInterval = 1.0 / 120.0
    private let childMaxSlewRate: TimeInterval = 0.05
    
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
        lastTickUptime = ProcessInfo.processInfo.systemUptime
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
        guard syncSettings.role == .parent && syncSettings.isEnabled else { return }
        
            let msgPhase = (phase == .countdown) ? "countdown" : "running"
            var msg = TimerMessage(
              action: .start,
              timestamp: Date().timeIntervalSince1970,
              phase: msgPhase,
              remaining: displayMainTime(),
              stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime, duration: $0.duration) },
              parentLockEnabled: syncSettings.parentLockEnabled
        )
        msg.notesParent = parentNotePayload
        print("[iOS] about to send TimerMessage")
        ConnectivityManager.shared.send(msg)
        if syncSettings.role == .parent && syncSettings.isEnabled {
            syncSettings.broadcastToChildren(msg)
        }
    }
    
    private func tickRunning() {
        
        // 0) frame-accurate dt
        let nowUp = ProcessInfo.processInfo.systemUptime
        let dt = max(0, nowUp - (lastTickUptime ?? nowUp))
        lastTickUptime = nowUp

        // 1) If we’re in a “stop”, count that down first
        if stopActive {
            stopRemaining = max(0, stopRemaining - dt)
            if stopRemaining <= 0 {
                stopActive = false
                elapsed = pausedElapsed
                startDate = Date().addingTimeInterval(-pausedElapsed)
                if isChildDevice {
                    childDisplayElapsed = pausedElapsed
                    childTargetStartDate = startDate
                }
            }
            return
        }

        // 2) Advance the main clock (do this BEFORE event checks)
        if isChildDevice {
            let displayElapsed = updateChildRunningElapsed(dt: dt)
            elapsed = displayElapsed
            consumeDecorativesUpTo(displayElapsed)
            return
        }
        elapsed = Date().timeIntervalSince(startDate ?? Date())
        cueDisplay.apply(elapsed: elapsed)
        
        // 4) Handle next due event
            if let next = events.first, elapsed >= next.fireTime {
                switch next {
                case .stop(let s):
                    pausedElapsed = elapsed
                    stopActive = true
                    stopRemaining = s.duration
                    events.removeFirst()
                    let snap = encodeCurrentEvents()
                    var stopMsg = TimerMessage(
                        action: .update,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "stop",
                        remaining: pausedElapsed,
                        stopEvents: snap.stops,
                        anchorElapsed: pausedElapsed,
                        parentLockEnabled: syncSettings.parentLockEnabled,
                        isStopActive: true,
                        stopRemainingActive: s.duration,
                        cueEvents: snap.cues,
                        restartEvents: snap.restarts,
                        sheetLabel: cueBadge.label
                    )

                    stopMsg.notesParent = parentNotePayload
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

                    let snap = encodeCurrentEvents()
                                    var cueMsg = TimerMessage(
                                        action: .update,
                                        timestamp: Date().timeIntervalSince1970,
                                        phase: "running",
                                        remaining: elapsed,
                                        stopEvents: snap.stops,
                                        parentLockEnabled: syncSettings.parentLockEnabled,
                                        cueEvents: snap.cues,
                                        restartEvents: snap.restarts,
                                        sheetLabel: cueBadge.label,
                                        flashNow: true
                                    )
                    cueMsg.notesParent = parentNotePayload
                    if syncSettings.role == .parent && syncSettings.isEnabled {
                        syncSettings.broadcastToChildren(cueMsg)
                    }

                case .message:
                    events.removeFirst()

                case .image:
                    events.removeFirst()

                case .restart(let r):
                    ticker?.cancel()
                    phase = .running
                    elapsed = 0
                    startDate = Date()
                startLoop()
                events.removeFirst()

                let snap = encodeCurrentEvents()
                let resetMsg = TimerMessage(
                    action: .reset,
                    timestamp: Date().timeIntervalSince1970,
                    phase: "running",
                    remaining: elapsed,
                    stopEvents: snap.stops,
                    cueEvents: snap.cues,
                    restartEvents: snap.restarts,
                    sheetLabel: cueBadge.label
                )
                cueDisplay.reset()
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
            let snap = encodeCurrentEvents()
            var updateMsg = TimerMessage(
                action: .update,
                timestamp: Date().timeIntervalSince1970,
                phase: "running",
                remaining: elapsed,
                stopEvents: remainingStopWires,
                parentLockEnabled: syncSettings.parentLockEnabled,
                cueEvents: snap.cues,
                restartEvents: snap.restarts,
                sheetLabel: cueBadge.label
            )

            updateMsg.notesParent = parentNotePayload
            if syncSettings.role == .parent && syncSettings.isEnabled {
                syncSettings.broadcastToChildren(updateMsg)
            }
        }
    }
    // Dismiss keyboard on drag/tap
        private func endEditing() {
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            #endif
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
                    stopEvents: stopWires,
                    parentLockEnabled: syncSettings.parentLockEnabled
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
                    let snap = encodeCurrentEvents()
                    var m = TimerMessage(
                        action:     .addEvent,
                        timestamp:  Date().timeIntervalSince1970,
                        phase:      (phase == .running ? "running" : "idle"),
                        remaining:  pausedElapsed,
                        stopEvents: snap.stops,
                        parentLockEnabled: syncSettings.parentLockEnabled,
                        cueEvents: snap.cues,
                        restartEvents: snap.restarts,
                        sheetLabel: cueBadge.label
                    )
            m.notesParent = parentNotePayload
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
                    let snap = encodeCurrentEvents()
                    var m = TimerMessage(
                        action:     .addEvent,
                        timestamp:  Date().timeIntervalSince1970,
                        phase:      (phase == .running ? "running" : "idle"),
                        remaining:  pausedElapsed,
                        stopEvents: snap.stops,
                        parentLockEnabled: syncSettings.parentLockEnabled,
                        cueEvents: snap.cues,
                        restartEvents: snap.restarts,
                        sheetLabel: cueBadge.label
                    )
            m.notesParent = parentNotePayload
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
                    var m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "running",
                        remaining: elapsed,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    m.notesParent = parentNotePayload
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
                persistLastCountdownSeconds(countdownDuration)
            }
            
            
            if countdownDuration > 0 {
                phase = .countdown
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    var m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "countdown",
                        remaining: countdownRemaining,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    m.notesParent = parentNotePayload
                    syncSettings.broadcastToChildren(m)
                }
                startLoop()
            } else {
                phase = .running
                if syncSettings.role == .parent && syncSettings.isEnabled {
                    var m = TimerMessage(
                        action: .start,
                        timestamp: Date().timeIntervalSince1970,
                        phase: "running",
                        remaining: elapsed,
                        stopEvents: rawStops.map {
                            StopEventWire(eventTime: $0.eventTime,
                                          duration: $0.duration)
                        }
                    )
                    m.notesParent = parentNotePayload
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
                var pauseMsg = TimerMessage(
                    action: .pause,
                    timestamp: Date().timeIntervalSince1970,
                    phase: "paused",
                    remaining: countdownRemaining,
                    stopEvents: rawStops.map { StopEventWire(eventTime: $0.eventTime, duration: $0.duration) },
                    parentLockEnabled: syncSettings.parentLockEnabled
                )
                pauseMsg.notesParent = parentNotePayload
                syncSettings.broadcastToChildren(pauseMsg)
            }
            
            // now do your normal pause/reset logic
            if settings.countdownResetMode == .manual {
                // true “pause” style
                phase = .paused
                capturePlaybackStopAnchor(elapsedSeconds: elapsed)
                // broadcast the pause so kids stop where they are
                sendPause(to: countdownRemaining)
            } else {
                // failsafe off: reset to full duration
                let baseDigits = timeToDigits(countdownDuration)
                countdownDigits    = baseDigits
                countdownRemaining = digitsToTime(baseDigits)
                phase              = .idle
                capturePlaybackStopAnchor(elapsedSeconds: elapsed)
                // tell all children “you’re paused at the full-length value”
                sendPause(to: countdownRemaining)
            }
            broadcastPlaybackStateIfNeeded()
            
        case .running:
            ticker?.cancel()
            phase = .paused
            pausedElapsed = elapsed
            capturePlaybackStopAnchor(elapsedSeconds: elapsed)
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
            broadcastPlaybackStateIfNeeded()
            if syncSettings.role == .parent,
               syncSettings.isEnabled,
               syncSettings.connectionMethod != .bluetooth {
                syncSettings.clockSyncService?.requestBurstSyncSamples(count: 3, spacingMs: 40)
            }
            
        case .paused:
            if countdownRemaining > 0 {
                phase = .countdown
                clearPlaybackStopAnchor()
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
                clearPlaybackStopAnchor()
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

    private var lastCountdownDefaultsKey: String { "quickActions.lastCountdownSeconds" }

    private func persistLastCountdownSeconds(_ seconds: TimeInterval) {
        let s = max(0, Int(seconds.rounded()))
        guard s > 0 else { return }
        UserDefaults.standard.set(s, forKey: lastCountdownDefaultsKey)
    }

    private func lastCountdownSecondsForQuickAction() -> Int {
        let s = UserDefaults.standard.integer(forKey: lastCountdownDefaultsKey)
        return s > 0 ? s : 30
    }

    private func startCountdownFromQuickAction(seconds: Int) {
        let secs = max(1, seconds)

        // Allow starting a fresh countdown from a paused main timer (e.g. paused after post-countdown running).
        if phase == .paused {
            resetAll() // safe: resetAll() already guards (idle || paused)
        }
        guard phase == .idle else { return }

        countdownDigits.removeAll()
        countdownDuration  = TimeInterval(secs)
        countdownRemaining = TimeInterval(secs)
        persistLastCountdownSeconds(countdownDuration)

        toggleStart() // reuse existing countdown start/broadcast path
    }


    // helper to fold your broadcast code
    private func sendPause(to remaining: TimeInterval) {
      guard syncSettings.role == .parent && syncSettings.isEnabled else { return }
      var msg = TimerMessage(
        action: .pause,
        timestamp: Date().timeIntervalSince1970,
        phase: "paused",
        remaining: remaining,
        stopEvents: rawStops.map {
            StopEventWire(eventTime: $0.eventTime, duration: $0.duration)
        }
      )
        msg.notesParent = parentNotePayload
      syncSettings.broadcastToChildren(msg)
    }
    // MARK: – Reset everything (called by your “Reset” button)
    private func resetAll() {
        guard phase == .idle || phase == .paused else { return }
        ticker?.cancel()
        phase = .idle
        clearPlaybackStopAnchor()
        stopSettleCancellable?.cancel()
        stopSettleFinalWorkItem?.cancel()
        lastStopAnchorElapsedNs = nil
        lastStopAnchorUptimeNs = nil
        lastStopBurstSeq = nil

        // Rebuild cues/overlays only if a sheet is active
        if activeCueSheetID != nil {
            reloadCurrentCueSheet()
        } else {
            endActiveCueSheet(reason: "reset-no-active")
        }
        
        // Broadcast reset to children if we’re the parent
        if syncSettings.role == .parent && syncSettings.isEnabled {
            let snap = encodeCurrentEvents() // (stops, cues, restarts)
            var m = TimerMessage(
                action: .reset,
                timestamp: Date().timeIntervalSince1970,
                phase: "idle",
                remaining: 0,
                stopEvents: snap.stops,
                anchorElapsed: nil,
                parentLockEnabled: syncSettings.parentLockEnabled,
                isStopActive: false,
                stopRemainingActive: nil,
                cueEvents: snap.cues,
                restartEvents: snap.restarts,
                sheetLabel: cueBadge.label
            )
            m.notesParent = parentNotePayload
            syncSettings.broadcastToChildren(m)
        }

        
        // Clear all local state
        countdownDigits.removeAll()
        countdownDuration = 0
        countdownRemaining = 0
        elapsed = 0
        startDate = nil
        pausedElapsed = 0          // ← add this
            lastTickUptime = nil       // ← and this, for a clean first dt
        // DO NOT clear events; just exit any active stop
        stopActive = false
        stopRemaining = 0
        stopDigits.removeAll()
        stopStep = 0
        
        lightHaptic()
    }
    
    //──────────────────── apply incoming TimerMessage ────────────────────
    // MARK: – Handle messages from the parent
    func applyIncomingSyncMessage(_ message: SyncMessage) {
        guard syncSettings.role == .child || settings.simulateChildMode else { return }

        switch message {
        case .sheetSnapshot(let sheet):
            if activeCueSheetID == nil,
               let endedAt = lastEndCueSheetReceivedAt,
               let endedID = lastEndedCueSheetID,
               endedID == sheet.id,
               Date().timeIntervalSince1970 - endedAt < 2.0 {
                return
            }
            let pending = pendingPlaybackState
            pendingPlaybackState = nil
            activateCueSheet(sheet, broadcastBadge: true)

            if let pending = pending,
               pending.sheetID == sheet.id,
               pending.revision == sheetRevision(for: sheet) {
                applyIncomingSyncMessage(.playbackState(pending))
            }

        case .playbackState(let state):
            if activeCueSheetID == nil, loadedCueSheet == nil {
                pendingPlaybackState = state
                return
            }
            guard activeCueSheetID != nil,
                  let sheet = activeCueSheet ?? loadedCueSheet,
                  sheet.id == state.sheetID,
                  state.revision == sheetRevision(for: sheet) else {
                return
            }

            let wasRunning = phase == .running
            if let seq = state.seq, seq <= lastAppliedPlaybackSeq {
                return
            }
            if let seq = state.seq {
                lastAppliedPlaybackSeq = seq
            }

            let incomingPhase = state.phase ?? (state.isRunning ? .running : (state.elapsedTime == 0 ? .idle : .paused))
            let delta = max(0, Date().timeIntervalSince(state.sentAt))
            var adjusted = state
            adjusted.isRunning = (incomingPhase == .running)
            if incomingPhase == .running {
                adjusted.elapsedTime += delta
            }

            if incomingPhase == .running {
                stopSettleCancellable?.cancel()
                stopSettleFinalWorkItem?.cancel()
                lastStopFinalSettleSeq = nil
                lastStopBurstSeq = nil
                lastStopAnchorElapsedNs = nil
                lastStopAnchorUptimeNs = nil
                let targetStart = Date().addingTimeInterval(-adjusted.elapsedTime)
                childTargetStartDate = targetStart
                if startDate == nil {
                    startDate = targetStart
                    childDisplayElapsed = adjusted.elapsedTime
                    elapsed = adjusted.elapsedTime
                }
                lastTickUptime = ProcessInfo.processInfo.systemUptime
                phase = .running
                startLoop()
            } else {
                ticker?.cancel()
                phase = incomingPhase == .idle ? .idle : .paused
                childTargetStartDate = nil
                startDate = nil
                if let anchorNs = adjusted.elapsedAtStopNs {
                    adjusted.elapsedTime = Double(anchorNs) / 1_000_000_000
                    let isNewAnchor = (anchorNs != lastStopAnchorElapsedNs)
                        || (state.masterUptimeNsAtStop != lastStopAnchorUptimeNs)
                    let shouldSlew = isNewAnchor || wasRunning
                    // Stop anchor: snap/slew once into the authoritative elapsed, then freeze.
                    applyStopAnchor(targetElapsedNs: anchorNs, allowSlew: shouldSlew)
                    pausedElapsed = adjusted.elapsedTime
                    lastStopAnchorElapsedNs = anchorNs
                    lastStopAnchorUptimeNs = state.masterUptimeNsAtStop
                    if shouldSlew {
                        requestStopSettleBurstIfNeeded(seq: state.seq)
                        scheduleStopAnchorReassertion(seq: state.seq,
                                                      targetElapsedNs: anchorNs,
                                                      count: stopSettleBurstCount,
                                                      spacingMs: stopSettleBurstSpacingMs)
                    }
                } else {
                    childDisplayElapsed = adjusted.elapsedTime
                    elapsed = adjusted.elapsedTime
                }
            }

            cueDisplay.syncPlaybackState(adjusted)

        case .cueEvent(let event):
            events.append(.cue(event))
            events.sort { $0.fireTime < $1.fireTime }
        }
    }
    
    private func rebuildChildDisplayEvents() {
        var combined: [Event] =
            rawStops.map(Event.stop) +
            childWireCues +
            childWireRestarts
        if childDecorativeCursor < childDecorativeSchedule.count {
            combined += childDecorativeSchedule[childDecorativeCursor...]
        }
        combined.sort { $0.fireTime < $1.fireTime }
        events = combined
    }

    private func quantizeCentiseconds(_ time: TimeInterval) -> TimeInterval {
        Double(Int((time * 100).rounded())) / 100.0
    }

    private func consumeDecorativesUpTo(_ elapsedTime: TimeInterval) {
        cueDisplay.apply(elapsed: elapsedTime)
        let target = quantizeCentiseconds(elapsedTime)
        var newCursor = childDecorativeCursor
        while newCursor < childDecorativeSchedule.count {
            let eventTime = quantizeCentiseconds(childDecorativeSchedule[newCursor].fireTime)
            if eventTime <= target {
                newCursor += 1
            } else {
                break
            }
        }
        if newCursor != childDecorativeCursor {
            childDecorativeCursor = newCursor
            rebuildChildDisplayEvents()
        }
    }

    func applyIncomingTimerMessage(_ msg: TimerMessage) {
        guard syncSettings.role == .child else { return }

        let isControlAction = (msg.action == .pause || msg.action == .reset || msg.action == .start || msg.action == .endCueSheet)
        let hasRemoteCuePayload = msg.action != .endCueSheet
            && (msg.cueEvents != nil || msg.restartEvents != nil || (msg.sheetLabel?.isEmpty == false))
        // Centisecond quantizer to keep visuals identical across devices
        @inline(__always) func qcs(_ t: TimeInterval) -> TimeInterval {
            return Double(Int((t * 100).rounded())) / 100.0
        }
        // One-way latency from parent timestamp → “now”
        let now = Date().timeIntervalSince1970
        let delta = max(0, now - msg.timestamp) // never negative
        let actionSeqDesc = msg.actionSeq.map(String.init) ?? "nil"
        let stateSeqDesc = msg.stateSeq.map(String.init) ?? "nil"
        var dropReason: String? = nil

        if isControlAction, let seq = msg.actionSeq, seq <= lastAppliedControlSeq {
            dropReason = "stale-control"
        } else if !isControlAction {
            if let stateSeq = msg.stateSeq, stateSeq < lastAppliedControlSeq {
                dropReason = "stale-state"
            } else if let ignoreUntil = ignoreRunningUpdatesUntil,
                      now < ignoreUntil,
                      msg.phase == "running" {
                dropReason = "quench-window"
            }
        }

        if syncSettings.connectionMethod == .bluetooth {
            let decision = dropReason ?? "applied"
            print("[BLE Child] recv action=\(msg.action) phase=\(msg.phase) remaining=\(qcs(msg.remaining)) actionSeq=\(actionSeqDesc) stateSeq=\(stateSeqDesc) lastControlSeq=\(lastAppliedControlSeq) decision=\(decision)")
        }
        if let dropReason {
            if dropReason == "stale-control",
               syncSettings.connectionMethod == .bluetooth,
               let seq = msg.actionSeq {
                syncSettings.bleDriftManager.sendControlAck(seq: seq)
            }
            return
        }
        
        // Always refresh stops (TimerMessage always carries these)
        rawStops = msg.stopEvents.map { StopEvent(eventTime: $0.eventTime, duration: $0.duration) }
        syncSettings.stopWires = msg.stopEvents

        // Only refresh cues/restarts when the parent actually included them
        if let cueWires = msg.cueEvents {
            childWireCues = cueWires.map { .cue(CueEvent(cueTime: $0.cueTime)) }
        }
        if let rstWires = msg.restartEvents {
            childWireRestarts = rstWires.map { .restart(RestartEvent(restartTime: $0.restartTime)) }
        }

        rebuildChildDisplayEvents()
        
        // Mirror parent's note and sheet label when provided
                notesParent = msg.notesParent ?? ""
                if hasRemoteCuePayload, activeCueSheetID == nil {
                    activeCueSheetID = remoteActiveCueSheetSentinelID
                    #if DEBUG
                    print("[CueSheet] child activated remote sheet (sentinel) label=\(msg.sheetLabel ?? "nil")")
                    #endif
                }
                if let lbl = msg.sheetLabel, !lbl.isEmpty {
                    cueBadge.setFallbackLabel(lbl, broadcast: true)
                }
                switch msg.action {
        case .start:
            if msg.phase == "countdown" {
                countdownRemaining = max(0, qcs(msg.remaining - delta))
                phase = .countdown
                childTargetStartDate = nil
                startDate = nil
                startLoop()
            } else {
                // Parent was already running at msg.timestamp; advance by delta
                                let adj = qcs(msg.remaining + delta)
                phase = .running
                lastStopAnchorElapsedNs = nil
                lastStopAnchorUptimeNs = nil
                lastStopBurstSeq = nil
                let targetStart = Date().addingTimeInterval(-adj)
                childTargetStartDate = targetStart
                startDate = targetStart
                elapsed = adj
                childDisplayElapsed = adj
                startLoop()
            }
            
        case .pause:
            ticker?.cancel()
            phase = .paused
            // Pause uses the exact parent-displayed time (no delta)
                        countdownRemaining = qcs(msg.remaining)
                        if lastStopAnchorElapsedNs == nil {
                            elapsed = qcs(msg.remaining)
                            pausedElapsed = elapsed
                        }
            childTargetStartDate = nil
            startDate = nil
            if lastStopAnchorElapsedNs == nil {
                childDisplayElapsed = elapsed
            }
            
        case .reset:
                    ticker?.cancel()
                    stopSettleCancellable?.cancel()
                    stopSettleFinalWorkItem?.cancel()
                    lastStopFinalSettleSeq = nil
                                phase = "idle" == "idle" ? .idle : .idle  // keep explicit for readability
                                countdownDigits.removeAll()
                                countdownDuration = 0
                                countdownRemaining = 0
                                elapsed = 0
                    childDisplayElapsed = 0
                    childTargetStartDate = nil
                    startDate = nil
                                stopActive = false
                                stopRemaining = 0
                    lastStopAnchorElapsedNs = nil
                    lastStopAnchorUptimeNs = nil
                    lastStopBurstSeq = nil
                    childDecorativeCursor = 0
                    cueDisplay.reset()
                    if let sheet = activeCueSheet {
                        cueDisplay.buildTimeline(from: sheet)
                    }
                    rebuildChildDisplayEvents()
        case .endCueSheet:
                    lastEndedCueSheetID = msg.sheetID.flatMap(UUID.init(uuidString:))
                    lastEndCueSheetReceivedAt = Date().timeIntervalSince1970
                    endActiveCueSheet(reason: "remote-end")
            
        case .update:
            switch msg.phase {
            case "countdown":
                countdownRemaining = max(0, qcs(msg.remaining - delta))
                phase = .countdown
                childTargetStartDate = nil
                startDate = nil
            case "paused", "idle":
                ticker?.cancel()
                phase = (msg.phase == "idle") ? .idle : .paused
                let fixed = qcs(msg.remaining)
                childTargetStartDate = nil
                startDate = nil
                pausedElapsed = fixed
                elapsed = fixed
                childDisplayElapsed = fixed
            case "stop":
                ticker?.cancel()
                phase = .paused
                let fixed = qcs(msg.remaining)
                childTargetStartDate = nil
                startDate = nil
                pausedElapsed = fixed
                elapsed = fixed
                childDisplayElapsed = fixed
            default:
                let adj = qcs(msg.remaining + delta)
                phase = .running
                childTargetStartDate = Date().addingTimeInterval(-adj)
                if startDate == nil {
                    startDate = childTargetStartDate
                    elapsed = adj
                    childDisplayElapsed = adj
                }
            }
                    // If parent sent an immediate flash edge (cue), mirror it
                                if msg.flashNow == true {
                                    flashZero = true
                                    let flashSec = Double(settings.flashDurationOption) / 1000.0
                                    DispatchQueue.main.asyncAfter(deadline: .now() + flashSec) { flashZero = false }
                                }
                    
            // If the parent entered a stop, mirror it locally.
                    if msg.isStopActive == true, let parentStopLeft = msg.stopRemainingActive {
                        // Freeze main clock at parent’s pausedElapsed (as of message time)
                        pausedElapsed = qcs(msg.remaining)   // the elapsed at the moment stop began
                        stopActive = true
                        elapsed = pausedElapsed
                            // While the packet was in flight, the parent’s stop timer ticked by `delta`
                            stopRemaining = max(0, qcs(parentStopLeft - delta))
                            childTargetStartDate = nil
                            childDisplayElapsed = pausedElapsed
                            // Ensure the run loop is active so our child ticks the stop timer down
                            startLoop()
                            ignoreRunningUpdatesUntil = now + 0.25
                        }
                case .addEvent:
                    // caches were already updated at the top of this function (when arrays are present)
                    rebuildChildDisplayEvents()

                }
        if isControlAction,
           syncSettings.connectionMethod == .bluetooth,
           let seq = msg.actionSeq {
            syncSettings.bleDriftManager.sendControlAck(seq: seq)
        }
        if isControlAction, let seq = msg.actionSeq {
            lastAppliedControlSeq = max(lastAppliedControlSeq, seq)
            lastAppliedControlKind = msg.action
            if msg.action == .pause || msg.action == .reset {
                ignoreRunningUpdatesUntil = now + 0.25
            }
        }
        if phase == .running || phase == .paused {
            let displayElapsed = isChildDevice ? childDisplayElapsed : elapsed
            consumeDecorativesUpTo(displayElapsed)
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
    // 12.9"/13" iPad hardware (native height ≥ 2732 px)
        private var isLargePad129Family: Bool {
            guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
            let maxNative = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
            return maxNative >= 2732
        }
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
                                    // ── Hours display mode ─────────────────
                                    Toggle("Always show hours (HH:MM:SS.CC)", isOn: $appSettings.showHours)
                                      .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                                    Text("When off: show MM:SS.CC until the timer reaches 1 hour; then auto-switch to HH:MM:SS.CC while ≥ 1h.")
                                      .font(.footnote)
                                      .foregroundColor(.secondary)

                                    // ── Low-Power Mode ─────────────────
                            //        Toggle("Low-Power Mode (buggy)", isOn: $appSettings.lowPowerMode)
                              //          .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                                //    Text("Strips out all images, materials, shadows, and custom colors to minimize display power; layout is buggy, no performance issues.")
                                  //      .font(.footnote)
                                    //    .foregroundColor(.secondary)
                                    
                                   // ── Allow sync changes ─────────────────

                                    Toggle(isOn: $appSettings.allowSyncChangesInMainView) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Allow sync changes in main view")
                                                .font(.custom("Roboto-Regular", size: 16))
                                            Text("If on, tapping the Sync Bar in the main view changes your settings. If off, long-press to launch Settings.")
                                                .font(.custom("Roboto-Regular", size: 12))
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                                    
                                    // ── High-Contrast Sync Indicator ────
                                    Toggle("High-Contrast Sync Indicator", isOn: $appSettings.highContrastSyncIndicator)
                                        .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                                    Text("Replaces every sync-lamp with high-contrast alts")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                    
                                    // ── Left Pane Pagination (12.9"/13" only) ─────────────
                                    if isLargePad129Family {
                                        Divider().padding(.vertical, 2)

                                        Toggle("Paginate Devices / Notes", isOn: $appSettings.leftPanePaginateOnLargePads)
                                            .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))

                                        Text("Shows Devices and Notes as pages with arrow navigation. Launch logo and Presets remain always visible.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }

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
          ///RESET LOCK - NOT NEEDED NOW THAT RESET IS GATED 
   //       Menu {
   //           ForEach(ResetConfirmationMode.allCases) { style in
   //               Button(style.rawValue) { appSettings.resetConfirmationMode = style }
    //          }
     //     } label: {
      //        settingRow(title: "Reset Lock",
       //                  value: appSettings.resetConfirmationMode.rawValue,
        //                 icon: "arrow.counterclockwise.circle")
         //     .tint(appSettings.flashColor)
   //       }
          // subtitle for Reset Lock
   //       Text("Requires confirmation before resetting the timer.")
    //          .font(.custom("Roboto-Light", size: 12))
     //         .foregroundColor(.secondary)
      //        .padding(.leading, 0)
       //       .lineLimit(1)
      
        

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

          //#if DEBUG
//    Divider()
//        .padding(.vertical, 4)
          //
          //    Toggle("Simulate Child Mode", isOn: $appSettings.simulateChildMode)
          //        .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
          //        .font(.custom("Roboto-Regular", size: 16))
          //   Text("Applies incoming sync updates locally to preview child rendering.")
          //      .font(.custom("Roboto-Light", size: 12))
          //      .foregroundColor(.secondary)
          //     .padding(.leading, 0)
          //      .lineLimit(2)
          //#endif
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
    var allowed: [Option]? = nil
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
        let options: [Option] = allowed ?? Array(Option.allCases)   // filter if provided
        return ForEach(options, id: \.id) { option in
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
                .contentShape(Rectangle())
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

#if canImport(SwiftUI)
@available(iOS 17.0, *)
private struct LampPulse: ViewModifier {
  let trigger: Bool
  func body(content: Content) -> some View {
    content
      .keyframeAnimator(initialValue: CGFloat(1.0), trigger: trigger) { view, _ in
        view
      } keyframes: { _ in
        KeyframeTrack(\.self) {
          CubicKeyframe(1.0, duration: 0.0)
          CubicKeyframe(1.12, duration: 0.12)
          CubicKeyframe(1.0, duration: 0.18)
        }
      }
  }
}
extension View {
  @ViewBuilder
  func ifAvailableiOS17Pulse(isConnected: Bool) -> some View {
    if #available(iOS 17.0, *) { self.modifier(LampPulse(trigger: isConnected)) }
    else { self }
  }
}
#endif
private func performToggleSyncMode(syncSettings: SyncSettings,
                                   showSyncErrorAlert: Binding<Bool>,
                                   syncErrorMessage: Binding<String>) {
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
                syncErrorMessage.wrappedValue = "Wi-Fi is off or not connected.\nPlease enable Wi-Fi to sync."
                showSyncErrorAlert.wrappedValue = true
                return
            }

        case .bluetooth:
                // Only error if Bluetooth is explicitly powered OFF
                let btMgr = CBCentralManager(delegate: nil, queue: nil, options: nil)
                if btMgr.state == .poweredOff {
                    syncErrorMessage.wrappedValue = "Bluetooth is off.\nPlease enable Bluetooth to sync."
                    showSyncErrorAlert.wrappedValue = true
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
            if syncSettings.tapPairingAvailable {
                syncSettings.beginTapPairing()
            } else {
                syncSettings.tapStateText = "Not available on Mac"
            }

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

private func stopSyncIfNeeded(syncSettings: SyncSettings) {
    guard syncSettings.isEnabled else { return }
    if syncSettings.role == .parent { syncSettings.stopParent() }
    else { syncSettings.stopChild() }
    syncSettings.isEnabled = false
}

private func startSyncIfNeeded(syncSettings: SyncSettings, toggleSyncMode: () -> Void) {
    guard !syncSettings.isEnabled else { return }
    toggleSyncMode()
}

private func startChildJoin(_ request: HostJoinRequestV1,
                            transport: SyncSettings.SyncConnectionMethod = .bluetooth,
                            syncSettings: SyncSettings,
                            toggleSyncMode: () -> Void) {
    stopSyncIfNeeded(syncSettings: syncSettings)
    syncSettings.role = .child
    syncSettings.connectionMethod = transport
    let deviceName = request.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
    syncSettings.stashJoinLabelCandidate(
        hostUUID: request.hostUUID,
        roomLabel: nil,
        deviceName: deviceName
    )
    if transport == .bluetooth {
        syncSettings.setJoinTargetHostUUID(request.hostUUID)
    } else {
        syncSettings.clearJoinConstraints()
    }
    if let deviceName, !deviceName.isEmpty {
        syncSettings.pairingDeviceName = deviceName
    }
    startSyncIfNeeded(syncSettings: syncSettings, toggleSyncMode: toggleSyncMode)
}

private func startChildRoom(_ room: ChildSavedRoom,
                            syncSettings: SyncSettings,
                            toggleSyncMode: () -> Void) {
    stopSyncIfNeeded(syncSettings: syncSettings)
    syncSettings.role = .child
    let transport = (room.preferredTransport == .bonjour) ? .network : room.preferredTransport
    syncSettings.connectionMethod = transport
    if transport != .bluetooth {
        if let ip = room.peerIP { syncSettings.peerIP = ip }
        if let port = room.peerPort { syncSettings.peerPort = port }
        syncSettings.clearJoinConstraints()
    } else if let hostUUID = room.hostUUID {
        syncSettings.setJoinTargetHostUUID(hostUUID)
    } else {
        syncSettings.clearJoinConstraints()
    }
    if let hostUUID = room.hostUUID {
        syncSettings.stashJoinLabelCandidate(hostUUID: hostUUID, roomLabel: nil, deviceName: nil)
    }
    startSyncIfNeeded(syncSettings: syncSettings, toggleSyncMode: toggleSyncMode)
}

struct ConnectionPage: View {
    @EnvironmentObject private var syncSettings: SyncSettings
    @EnvironmentObject private var settings: AppSettings
    @Binding var editingTarget: EditableField?
    @Binding var inputText: String
    @Binding var isEnteringField: Bool
    @Binding var showBadPortError: Bool
    @State private var placeholderTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var ipBlink = false
    @State private var portBlink = false
    @State private var showSyncErrorAlert = false
    @State private var syncErrorMessage   = ""
    @State private var showPortWarning = false
    
    
    
    @State private var isWifiAvailable = false
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    @State private var showJoinSheet = false
    @AppStorage("whatsnew.pendingJoin") private var pendingJoinFromWhatsNew: Bool = false
    
    // Treat default/sentinel ports as "unset" for display-only
        private func isUnsetPort(_ s: String) -> Bool {
            guard let p = UInt16(s) else { return true }      // non-numeric = unset
            if p == 0 || p == 50000 { return true }           // common defaults
            return !(49153...65534).contains(p)               // outside ephemeral range → treat as unset
        }
    private func generateEphemeralPort() -> UInt16 {
        UInt16.random(in: 49153...65534)
    }

    private func ensureValidListenPortIfNeeded() {
        if isUnsetPort(syncSettings.listenPort) {
            syncSettings.listenPort = String(generateEphemeralPort())
        }
    }
    
    private func cancelEntry() {
        editingTarget = nil
        inputText = ""
        isEnteringField = false
    }
    
    private var isMax: Bool {
        UIScreen.main.bounds.height >= 930
    }

    private var hostUUIDString: String {
        syncSettings.localPeerID.uuidString
    }

    private var hostDeviceName: String {
        UIDevice.current.name
    }

    private var hostShareURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "synctimerapp.com"
        components.path = "/host"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "host_uuid", value: hostUUIDString),
            URLQueryItem(name: "device_name", value: hostDeviceName)
        ]
        return components.url ?? URL(string: "https://synctimerapp.com/host")!
    }

    private var hostShareURLString: String {
        hostShareURL.absoluteString
    }

    private var uuidSuffix: String {
        String(hostUUIDString.suffix(8)).uppercased()
    }
    
    
    
    // MARK: – Derived Bluetooth status (small, compiler-friendly)
        private var btStatusText: String {
            // OFF wins; then Connected; else amber states
                    if !syncSettings.isEnabled { return "Off" }
                    if syncSettings.isEstablished { return "Connected" }
                    return (syncSettings.role == .parent) ? "Advertising…" : "Searching…"
        }
    // MARK: – Derived LAN status (same logic/wording style as BLE)
        private var lanStatusText: String {
            if !syncSettings.isEnabled { return "Off" }
            if syncSettings.isEstablished { return "Connected" }
            // amber while SYNC is ON but link not established yet
            return (syncSettings.role == .parent) ? "Listening…" : "Connecting…"
        }
    
    @ViewBuilder
        private func bluetoothStatusPanel(statusText: String,
                                          isEstablished: Bool,
                                          roleIsParent: Bool,
                                          isEnabled: Bool,
                                          signalBars: Int? = nil) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                // Top line
                HStack(spacing: 8) {
                                    if !isEnabled {
                                        Circle().fill(Color.gray).frame(width: 10, height: 10)
                                    } else {
                                        let state: SyncStatusLamp.LampState = isEstablished ? .connected : .streaming
                                        SyncStatusLamp(state: state,
                                                       size: 12,
                                                       highContrast: settings.highContrastSyncIndicator)
                                    }
                    Text(statusText)
                        .font(.custom("Roboto-Medium", size: 16))
                    Spacer()
                    Text("Nearby")
                        .font(.custom("Roboto-Regular", size: 13))
                        .foregroundColor(.secondary)
                }
                // Facts row (role + optional bars)
                HStack(spacing: 12) {
                    Label(roleIsParent ? "Parent" : "Child",
                          systemImage: roleIsParent ? "arrow.up.circle" : "arrow.down.circle")
                        .font(.custom("Roboto-Regular", size: 13))
                        .foregroundColor(.secondary)
                    if let bars = signalBars {
                        Divider().frame(height: 12).opacity(0.3)
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Rectangle()
                                    .frame(width: 4, height: CGFloat(6 + i*3))
                                    .opacity(i < bars ? 1 : 0.25)
                            }
                        }
                        .accessibilityLabel("Signal bars \(bars) of 3")
                    }
                    Spacer()
                }
                // Micro-tip
                Text(!isEnabled
                                ? "SYNC is OFF. Tap SYNC to start."
                                 : (isEstablished
                                    ? "Connected. Connection status updates within a few seconds (bluetooth limitation)."
                                    : (roleIsParent
                                       ? "SYNC is ON. Advertising for nearby children."
                                       : "SYNC is ON. Searching for a parent nearby.")))
                .font(.custom("Roboto-Light", size: 12))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    
    // MARK: – LAN status panel (same card style as Bluetooth, compact height)
        @ViewBuilder
        private func lanStatusPanel(statusText: String,
                                    isEstablished: Bool,
                                    roleIsParent: Bool,
                                    isEnabled: Bool,
                                    isWifiAvailable: Bool,
                                    onRequestPortChange: @escaping () -> Void) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                // Top line — identical style
                HStack(spacing: 8) {
                                    if !isEnabled {
                                        Circle().fill(Color.gray).frame(width: 10, height: 10)
                                    } else {
                                        let state: SyncStatusLamp.LampState = isEstablished ? .connected : .streaming
                                        SyncStatusLamp(state: state,
                                                       size: 12,
                                                       highContrast: settings.highContrastSyncIndicator)
                                    }
                    Text(statusText).font(.custom("Roboto-Medium", size: 16))
                    Spacer()
                Text("Wi-Fi").font(.custom("Roboto-Regular", size: 13)).foregroundColor(.secondary)
                }
                // Facts row — match BLE (Label + SF Symbol)
                            HStack(spacing: 12) {
                                Label(roleIsParent ? "Parent" : "Child",
                                      systemImage: roleIsParent ? "arrow.up.circle" : "arrow.down.circle")
                                    .font(.custom("Roboto-Regular", size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            // Micro-tip only when useful (OFF or not connected) to save height
                            if !isEnabled || !isEstablished {
                                Text(!isEnabled
                                     ? "SYNC is OFF. Tap SYNC to start."
                                     : (roleIsParent
                                        ? "Share your IP and Port with children."
                                        : "Enter the parent’s IP and Port below."))
                                .font(.custom("Roboto-Light", size: 12))
                                .foregroundColor(.secondary)
                            }
                            Divider().opacity(0.12)
                // PARENT (Host) — single row: Your IP • Your Port
                            Text("If Parent")
                                .font(.custom("Roboto-Medium", size: 12))
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Text("HOST:")
                                                    .font(.custom("Roboto-SemiBold", size: 16))
                                Spacer()
                                let ipText = isWifiAvailable
                                    ? (getLocalIPAddress() ?? "Unknown")
                                    : "Not connected to Wi-Fi"
                                Text(ipText)
                                    .font(.custom("Roboto-Regular", size: 16))
                                    .foregroundColor(isWifiAvailable ? .primary : .secondary)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                Text("•").foregroundColor(.secondary).opacity(0.5)
                                Button(action: onRequestPortChange) {
                                    Text(syncSettings.listenPort)
                                        .font(.custom("Roboto-Regular", size: 16))
                                        .foregroundColor(isUnsetPort(syncSettings.listenPort) ? .secondary : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                            Divider().opacity(0.08)
                            // CHILD (Join) — single row: Parent IP • Parent Port
                            Text("If Child")
                                .font(.custom("Roboto-Medium", size: 12))
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Text("JOIN:")
                                    .font(.custom("Roboto-SemiBold", size: 16))
                                Spacer()
                                // Parent IP (tap to enter)
                                let ipText: String = {
                                    if editingTarget == .ip { return inputText.isEmpty ? "Enter IP" : inputText }
                                    return syncSettings.peerIP.isEmpty ? "Enter IP" : syncSettings.peerIP
                                }()
                                Text(ipText)
                                    .font(.custom("Roboto-Regular", size: 16))
                                    .foregroundColor(
                                        (editingTarget == .ip && inputText.isEmpty) ? .secondary
                                        : (editingTarget == .ip ? .primary : (syncSettings.peerIP.isEmpty ? .secondary : .primary))
                                    )
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                    .onTapGesture {
                                        syncSettings.peerIP = ""
                                        inputText           = ""
                                        editingTarget       = .ip
                                        isEnteringField     = true
                                    }
                                Text("•").foregroundColor(.secondary).opacity(0.5)
                                // Parent Port (tap to enter)
                                let portText: String = {
                                                    if editingTarget == .port {
                                                        if showBadPortError { return "Invalid (49153–65534)" }
                                                        return inputText.isEmpty ? "Enter Port" : inputText
                                                    }
                                                    return isUnsetPort(syncSettings.peerPort) ? "Enter Port" : syncSettings.peerPort
                                                }()
                                Text(portText)
                                                    .font(.custom("Roboto-Regular", size: 16))
                                                    .foregroundColor(
                                                        (editingTarget == .port && showBadPortError) ? .secondary :
                                                        (editingTarget == .port && inputText.isEmpty) ? .secondary :
                                                        (editingTarget == .port ? .primary : (isUnsetPort(syncSettings.peerPort) ? .secondary : .primary))
                                                    )
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                    .onTapGesture {
                                        syncSettings.peerPort = ""
                                        inputText             = ""
                                        editingTarget         = .port
                                        isEnteringField       = true
                                    }
                            }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    // MARK: – toggleSyncMode (drop-in)
    private func toggleSyncMode() {
        performToggleSyncMode(
            syncSettings: syncSettings,
            showSyncErrorAlert: $showSyncErrorAlert,
            syncErrorMessage: $syncErrorMessage
        )
    }

    /// Friendly description for each method
    private var connectionDescription: String {
        switch syncSettings.connectionMethod {
        case .network:
            return ""
        case .bluetooth:
            return ""
        case .bonjour:
            return ""
        }
    }

    private var joinQRButton: some View {
        GlassCircleIconButton(
            systemName: "qrcode",
            tint: settings.flashColor,
            accessibilityLabel: syncSettings.role == .parent ? "Generate Join QR" : "Join via QR",
            accessibilityHint: syncSettings.role == .parent
                ? "Opens a share sheet for children to join."
                : "Opens a join sheet to scan a QR or pick a room."
        ) {
            Haptics.light()
            showJoinSheet = true
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            // ── Content area ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: -24) {
                HStack(spacing: 10) {
                    SegmentedControlPicker(selection: $syncSettings.connectionMethod,
                                           shadowOpacity: 0.08,
                                           allowed: [.network, .bluetooth])
                    .onChange(of: syncSettings.connectionMethod) { newMethod in
                        // ① clear any in-flight numpad entry
                            cancelEntry()
                    
                            // ② if we were mid-sync, shut everything down
                        if syncSettings.isEnabled {
                                                    if syncSettings.role == .parent { syncSettings.stopParent() }
                                                    else                            { syncSettings.stopChild() }
                                                    syncSettings.isEnabled = false
                                                }
                        if newMethod == .network {
                            ensureValidListenPortIfNeeded()
                        }
                    }
                    .frame(maxWidth: .infinity)      // ← let it grow to fill the content area
                    .accessibilityLabel(syncSettings.connectionMethod.rawValue)
                    .accessibilityHint("Selects \(syncSettings.connectionMethod.rawValue) sync mode")
                    joinQRButton
                }
                .padding(.horizontal, -8)         // ← pull it 8pt in from each edge (instead of 12)
                .padding(.vertical, -8)
                Text(connectionDescription)
                                    .font(.custom("Roboto-Light", size: 14))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 28)
                
                // MARK: - HACK: WHEN YOU REFACTOR THE CONNECT PAGE, YOU SHOULD PROBABLY BRING THIS BACK
//                if syncSettings.role == .parent {
  //                  Text("Share a Join QR for children to connect.")
    //                    .font(.custom("Roboto-Light", size: 12))
      //                  .foregroundColor(.secondary)
        //                .padding(.horizontal, 8)
          //              .padding(.bottom, 18)
            //    } else {
  //                  Text("Scan a parent Join QR to connect.")
    //                    .font(.custom("Roboto-Light", size: 12))
      //                  .foregroundColor(.secondary)
        //                .padding(.horizontal, 8)
          //              .padding(.bottom, 18)
            //    }

                switch syncSettings.connectionMethod {
                case .network:
                                    lanStatusPanel(
                                        statusText: lanStatusText,
                                        isEstablished: syncSettings.isEstablished,
                                        roleIsParent: (syncSettings.role == .parent),
                                        isEnabled: syncSettings.isEnabled,
                                        isWifiAvailable: isWifiAvailable,
                                        onRequestPortChange: { showPortWarning = true }
                                    )
                    
                case .bluetooth:
                    bluetoothStatusPanel(statusText: btStatusText,
                                                             isEstablished: syncSettings.isEstablished,
                                                             roleIsParent: (syncSettings.role == .parent),
                                                         isEnabled: syncSettings.isEnabled,
                                                             signalBars: nil) // pass bars if you track them
                    
                case .bonjour:
                                    // Deprecated in UI: keep empty branch to satisfy exhaustiveness.
                                    EmptyView()
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
                    toggleSyncMode()
                } label: {
                    Text(syncSettings.isEnabled ? "STOP" : "SYNC")
                        .font(.custom("Roboto-SemiBold", size: 24))
                        .foregroundColor((settings.appTheme == .dark) ? .white : .black)
                        .fixedSize()   // hug text width
                }
                .buttonStyle(.plain)
                
                // ── Lamp ──
                let state: SyncStatusLamp.LampState = syncSettings.isEstablished
                ? .connected : (syncSettings.isEnabled ? .streaming : .off)
                SyncStatusLamp(state: state, size: 20, highContrast: settings.highContrastSyncIndicator)
            }
                .frame(maxWidth: .infinity, alignment: .leading)   // <<< fill width, align left
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        .onAppear {
            if pendingJoinFromWhatsNew {
                pendingJoinFromWhatsNew = false
                showJoinSheet = true
            }
              ensureValidListenPortIfNeeded()
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
        .onChange(of: pendingJoinFromWhatsNew) { newValue in
            guard newValue else { return }
            pendingJoinFromWhatsNew = false
            showJoinSheet = true
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
                        // Parent-port: once 5 digits are in, auto-submit
                        guard editingTarget == .port else { return }
                        showBadPortError = false
                        if newValue.count == 5 {
                            if let port = UInt16(newValue),
                               (49153...65534).contains(port) {
                                // valid → commit
                                syncSettings.peerPort = newValue
                                editingTarget         = nil
                                isEnteringField       = false
                            } else {
                                // invalid → show error
                                showBadPortError = true
                            }
                        }
                    }
        .alert("Changing Port", isPresented: $showPortWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Proceed", role: .destructive) {
                syncSettings.listenPort = String(generateEphemeralPort())
            }
        } message: {
            Text("This will break the current room for anyone using the old join info.")
        }
        .alert("Cannot Start Sync",
               isPresented: $showSyncErrorAlert) {
          Button("OK", role: .cancel) { }
        } message: {
          Text(syncErrorMessage)
        }
        .sheet(isPresented: $showJoinSheet) {
            Group {
                if syncSettings.role == .parent {
                    GenerateJoinQRSheet(
                        deviceName: hostDeviceName,
                        hostUUIDString: hostUUIDString,
                        hostShareURL: hostShareURL,
                        onRequestEnableSync: {
                            guard !syncSettings.isEnabled else { return }
                            toggleSyncMode()
                        }
                    )
                } else {
                    ChildJoinSheet(
                        onJoinRequest: { request, transport in
                            startChildJoin(
                                request,
                                transport: transport,
                                syncSettings: syncSettings,
                                toggleSyncMode: toggleSyncMode
                            )
                        },
                        onJoinRoom: { room in
                            startChildRoom(
                                room,
                                syncSettings: syncSettings,
                                toggleSyncMode: toggleSyncMode
                            )
                        }
                    )
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .presentationCornerRadius(28)
        }
    }
    
    
    // MARK: – Sections
    
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your Port:")
                Spacer()
                Text(syncSettings.listenPort)
                    .font(.custom("Roboto-Regular", size: 12))
                    .foregroundColor(isUnsetPort(syncSettings.listenPort) ? .secondary : .primary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .contentShape(Rectangle())
                    .onTapGesture { showPortWarning = true }
                    .accessibilityAddTraits(.isButton)
            }
            
            HStack {
                Text("Your IP:")
                Spacer()
                let ipText = isWifiAvailable
                    ? (getLocalIPAddress() ?? "Unknown")
                    : "Not connected to Wi-Fi"
                Text(ipText)
                    .font(.custom("Roboto-Regular", size: 16))
                    .foregroundColor(isWifiAvailable ? .primary : .secondary)
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
                                 : (isUnsetPort(syncSettings.peerPort) ? "Tap to enter" : syncSettings.peerPort))
                .font(.custom("Roboto-Regular", size: 16))
                .foregroundColor(
                                    editingTarget == .port
                                        ? (inputText.isEmpty ? .secondary : .primary)
                                        : (isUnsetPort(syncSettings.peerPort) ? .secondary : .primary)
                                )
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


private enum ChildJoinTab: String, CaseIterable, Identifiable, SegmentedOption {
    case join = "Join"
    case rooms = "Rooms"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .join: return "qrcode"
        case .rooms: return "tray.full"
        }
    }
    var label: String { rawValue }
}

private struct ChildJoinSheet: View {
    @EnvironmentObject private var syncSettings: SyncSettings
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var roomsStore: ChildRoomsStore
    @State private var selectedTab: ChildJoinTab = .join
    @State private var pendingRequest: HostJoinRequestV1? = nil

    let onJoinRequest: (HostJoinRequestV1, SyncSettings.SyncConnectionMethod) -> Void
    let onJoinRoom: (ChildSavedRoom) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                LiquidGlassCircle(diameter: 44, tint: settings.flashColor)
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(settings.flashColor)
                            .symbolRenderingMode(.hierarchical)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join")
                        .font(.custom("Roboto-SemiBold", size: 20))
                    Text("Connect to a parent timer.")
                        .font(.custom("Roboto-Light", size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            SegmentedControlPicker(selection: $selectedTab, shadowOpacity: 0.08)

            Group {
                switch selectedTab {
                case .join:
                    JoinTabView(
                        roomsStore: roomsStore,
                        pendingRequest: $pendingRequest,
                        onJoinRequest: onJoinRequest
                    )
                case .rooms:
                    ChildRoomsTabView(
                        roomsStore: roomsStore,
                        onJoinRoom: onJoinRoom
                    )
                }
            }
        }
        .padding(20)
        .onAppear {
            if let pending = syncSettings.pendingHostJoinRequest {
                syncSettings.pendingHostJoinRequest = nil
                pendingRequest = pending
                selectedTab = .join
            }
        }
        .onChange(of: syncSettings.pendingHostJoinRequest?.hostUUID) { _ in
            if let pending = syncSettings.pendingHostJoinRequest {
                syncSettings.pendingHostJoinRequest = nil
                pendingRequest = pending
                selectedTab = .join
            }
        }
    }
}

private struct JoinTabView: View {
    @EnvironmentObject private var joinRouter: JoinRouter
    @ObservedObject var roomsStore: ChildRoomsStore
    @Binding var pendingRequest: HostJoinRequestV1?
    let onJoinRequest: (HostJoinRequestV1, SyncSettings.SyncConnectionMethod) -> Void

    private enum CameraPermissionState {
        case unknown
        case authorized
        case denied
    }

    @State private var cameraPermission: CameraPermissionState = .unknown
    @State private var isScanning = true
    @State private var torchEnabled = false
    @State private var scanError: String? = nil
    @State private var scanResetToken = UUID()
    @State private var lastRequest: HostJoinRequestV1? = nil
    @State private var lastJoinRequest: JoinRequestV1? = nil
    @State private var preferredTransport: SyncSettings.SyncConnectionMethod = .bluetooth

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                scannerContent
                    .frame(height: 260)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                statusLine
                    .padding(.bottom, 10)
            }

            if let scanError {
                errorCard(message: scanError)
            } else if let request = lastRequest {
                joinActionsCard(for: request)
            } else if let joinError = joinRouter.lastJoinUserFacingError {
                incompleteWiFiCard(message: joinError)
            }
        }
        .onAppear {
            refreshCameraPermission()
        }
        .onChange(of: pendingRequest?.hostUUID) { _ in
            if let request = pendingRequest {
                pendingRequest = nil
                handleJoin(request)
            }
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        switch cameraPermission {
        case .authorized:
            QRCodeScannerView(
                isActive: $isScanning,
                torchEnabled: $torchEnabled,
                resetToken: scanResetToken
            ) { code in
                handleScan(code)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("Camera access is off.")
                    .font(.custom("Roboto-Regular", size: 14))
                Button("Open Settings") {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                }
                .font(.custom("Roboto-SemiBold", size: 14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unknown:
            VStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("Requesting camera access…")
                    .font(.custom("Roboto-Regular", size: 14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .font(.custom("Roboto-Light", size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                torchEnabled.toggle()
            } label: {
                Image(systemName: torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!torchAvailable || cameraPermission != .authorized)

            Button {
                pasteLink()
            } label: {
                Text("Paste Link")
                    .font(.custom("Roboto-SemiBold", size: 12))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
    }

    private var statusText: String {
        if joinRouter.lastJoinUserFacingError != nil {
            return "Wi-Fi join needs IP/Port."
        }
        if let scanError {
            return "Invalid QR. Try again."
        }
        if let request = lastRequest {
            return "Connecting to \(request.deviceName ?? "parent")…"
        }
        if let request = lastJoinRequest {
            let label = request.roomLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = request.deviceNames.first ?? "room"
            let name = (label?.isEmpty == false) ? label! : fallback
            return "Connecting to \(name)…"
        }
        return "Point the camera at the join QR."
    }

    private var torchAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    private func refreshCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermission = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                }
            }
        default:
            cameraPermission = .denied
        }
    }

    private func handleScan(_ code: String) {
        guard let url = normalizedURL(from: code) else {
            scanError = "Not a SyncTimer link."
            isScanning = false
            lastRequest = nil
            lastJoinRequest = nil
            return
        }
        switch parseChildJoinLink(url: url) {
        case .success(.join(let request)):
            #if DEBUG
            logParsedJoin(request)
            #endif
            handleJoin(request)
        case .success(.legacy(let request)):
            #if DEBUG
            logParsedLegacy(request)
            #endif
            handleJoin(request)
        case .failure(let error):
            scanError = scanErrorMessage(for: error)
            isScanning = false
            lastRequest = nil
            lastJoinRequest = nil
        }
    }

    private func handleJoin(_ request: HostJoinRequestV1) {
        scanError = nil
        lastRequest = request
        lastJoinRequest = nil
        isScanning = false
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        onJoinRequest(request, preferredTransport)
    }

    private func handleJoin(_ request: JoinRequestV1) {
        scanError = nil
        lastRequest = nil
        lastJoinRequest = request
        isScanning = false
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        joinRouter.ingestParsed(request)
    }

    private func pasteLink() {
        #if canImport(UIKit)
        let pasteboardText = UIPasteboard.general.string ?? ""
        #else
        let pasteboardText = ""
        #endif
        guard !pasteboardText.isEmpty else {
            scanError = "Paste a SyncTimer join link."
            isScanning = false
            lastRequest = nil
            lastJoinRequest = nil
            return
        }
        handleScan(pasteboardText)
    }

    private func resetScanner() {
        scanError = nil
        isScanning = true
        lastRequest = nil
        lastJoinRequest = nil
        joinRouter.clearJoinUserFacingError()
        scanResetToken = UUID()
    }

    private func normalizedURL(from code: String) -> URL? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed) {
            return url
        }
        if !trimmed.lowercased().hasPrefix("http"),
           let url = URL(string: "https://\(trimmed)") {
            return url
        }
        return nil
    }

    private func scanErrorMessage(for error: ChildJoinLinkParseError) -> String {
        switch error {
        case .notSyncTimerLink:
            return "Not a SyncTimer link."
        case .unsupportedSyncTimerLink:
            return "Unsupported SyncTimer link."
        case .joinError(let joinError):
            return joinErrorMessage(for: joinError)
        case .legacyError(let legacyError):
            return legacyError.errorDescription ?? "Invalid link."
        }
    }

    private func joinErrorMessage(for error: JoinLinkParser.JoinLinkError) -> String {
        switch error {
        case .invalidVersion:
            return "This join link is outdated."
        case .invalidMode:
            return "Unsupported join mode."
        case .invalidHosts:
            return "This SyncTimer join link is missing host info."
        case .invalidMinBuild:
            return "This isn’t a SyncTimer join link."
        case .updateRequired(let minBuild):
            return "Update required (build \(minBuild)+) to join."
        case .invalidPath:
            return "Unsupported SyncTimer link."
        }
    }

    private func transportForJoin(_ mode: String) -> SyncSettings.SyncConnectionMethod {
        switch mode {
        case "wifi":
            return .network
        case "nearby", "bluetooth":
            return .bluetooth
        default:
            return .bluetooth
        }
    }

    #if DEBUG
    private func logParsedJoin(_ request: JoinRequestV1) {
        let transport = transportForJoin(request.mode)
        let hostUUID = request.selectedHostUUID ?? request.hostUUIDs.first
        let peerPort = request.peerPort.map { String($0) } ?? "nil"
        print("[JoinTabView] parsed /join: mode=\(request.mode) transport=\(transport.rawValue) hostUUID=\(hostUUID?.uuidString ?? "nil") peer=\(request.peerIP ?? "nil"):\(peerPort)")
    }

    private func logParsedLegacy(_ request: HostJoinRequestV1) {
        print("[JoinTabView] parsed /host: transport=\(preferredTransport.rawValue) hostUUID=\(request.hostUUID.uuidString)")
    }
    #endif

    @ViewBuilder
    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.custom("Roboto-Regular", size: 14))
            Button("Rescan") {
                resetScanner()
            }
            .font(.custom("Roboto-SemiBold", size: 14))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func incompleteWiFiCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.custom("Roboto-Regular", size: 14))
            HStack(spacing: 10) {
                Button("Switch to Nearby") {
                    joinRouter.retryIncompleteWiFiAsNearby()
                }
                .font(.custom("Roboto-SemiBold", size: 14))
                Button("Rescan") {
                    resetScanner()
                }
                .font(.custom("Roboto-SemiBold", size: 14))
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func joinActionsCard(for request: HostJoinRequestV1) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Having trouble pairing?")
                .font(.custom("Roboto-Medium", size: 14))
            HStack(spacing: 10) {
                Button("Retry") {
                    onJoinRequest(request, preferredTransport)
                }
                .font(.custom("Roboto-SemiBold", size: 14))
                Button(preferredTransport == .bluetooth ? "Switch to Wi-Fi" : "Switch to Nearby") {
                    preferredTransport = (preferredTransport == .bluetooth) ? .network : .bluetooth
                }
                .font(.custom("Roboto-SemiBold", size: 14))
            }
            .buttonStyle(.borderless)
            Button("Save Room") {
                let label = request.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = "Room \(request.hostUUID.uuidString.suffix(4))"
                let name = (label?.isEmpty == false) ? label! : fallback
                let room = ChildSavedRoom(
                    label: name,
                    preferredTransport: preferredTransport,
                    hostUUID: request.hostUUID
                )
                roomsStore.upsert(room)
            }
            .font(.custom("Roboto-SemiBold", size: 14))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ChildRoomsTabView: View {
    @ObservedObject var roomsStore: ChildRoomsStore
    let onJoinRoom: (ChildSavedRoom) -> Void

    var body: some View {
        if roomsStore.rooms.isEmpty {
            VStack(spacing: 10) {
                Text("No saved rooms yet.")
                    .font(.custom("Roboto-Regular", size: 14))
                Text("Scan a Join QR to add one.")
                    .font(.custom("Roboto-Light", size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(roomsStore.rooms) { room in
                        Button {
                            onJoinRoom(room)
                            roomsStore.updateLastUsed(room)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(room.label)
                                            .font(.custom("Roboto-SemiBold", size: 16))
                                            .foregroundColor(.primary)
                                        if room.renamedAt != nil, room.previousLabel != nil {
                                            Text("RENAMED")
                                                .font(.custom("Roboto-Medium", size: 9))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.18), in: Capsule())
                                        }
                                    }
                                    if let previous = room.previousLabel, room.renamedAt != nil {
                                        Text("was \(previous)")
                                            .font(.custom("Roboto-Light", size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    if let hostUUID = room.hostUUID {
                                        Text("Host …\(hostUUID.uuidString.suffix(4))")
                                            .font(.custom("Roboto-Light", size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(room.preferredTransport == .bluetooth ? "Nearby" : "Wi-Fi")
                                    .font(.custom("Roboto-SemiBold", size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onJoinRoom(room)
                                roomsStore.updateLastUsed(room)
                            } label: {
                                Label("Join", systemImage: "arrow.down.circle")
                            }
                            Button(role: .destructive) {
                                roomsStore.delete(room)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

private final class QRCodePreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct QRCodeScannerView: UIViewRepresentable {
    @Binding var isActive: Bool
    @Binding var torchEnabled: Bool
    let resetToken: UUID
    let onFound: (String) -> Void

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRCodeScannerView
        var session: AVCaptureSession?
        var device: AVCaptureDevice?
        private var didScan = false
        private var lastResetToken: UUID?

        init(parent: QRCodeScannerView) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan else { return }
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue else { return }
            didScan = true
            DispatchQueue.main.async {
                self.parent.onFound(value)
            }
            session?.stopRunning()
        }

        func resetIfNeeded(_ token: UUID) {
            if lastResetToken != token {
                lastResetToken = token
                didScan = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> QRCodePreviewView {
        let view = QRCodePreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill

        let session = AVCaptureSession()
        context.coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return view
        }

        context.coordinator.device = device
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }

        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: QRCodePreviewView, context: Context) {
        context.coordinator.resetIfNeeded(resetToken)

        if isActive, let session = context.coordinator.session, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } else if !isActive, let session = context.coordinator.session, session.isRunning {
            session.stopRunning()
        }

        if let device = context.coordinator.device, device.hasTorch {
            do {
                try device.lockForConfiguration()
                device.torchMode = torchEnabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // Ignore torch errors.
            }
        }
    }
}

private struct GenerateJoinQRSheet: View {
    @State private var showShareGlyph = false
    let deviceName: String
    let hostUUIDString: String
    let hostShareURL: URL
    let onRequestEnableSync: (() -> Void)?

    init(deviceName: String,
         hostUUIDString: String,
         hostShareURL: URL,
         onRequestEnableSync: (() -> Void)? = nil) {
        self.deviceName = deviceName
        self.hostUUIDString = hostUUIDString
        self.hostShareURL = hostShareURL
        self.onRequestEnableSync = onRequestEnableSync
    }
    @State private var isEditingRoomLabel = false
    @State private var roomLabelDraft: String = ""
    @FocusState private var roomLabelFocused: Bool
    @State private var roomToRename: Room? = nil
    @State private var renameDraft: String = ""

#if canImport(UIKit)
    private func printJoinQR() {
        guard let img = makePrintedJoinQRUIImage(
            from: joinAppClipURLString,
            title: roomLabelForSharing,
            qrScale: 14
        ) else { return }

        let ctrl = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo
        info.jobName = "SyncTimer Join QR"
        ctrl.printInfo = info
        ctrl.printingItem = img
        ctrl.present(animated: true, completionHandler: nil)
    }

#endif
    private func sanitizeRoomLabel(_ raw: String) -> String {
        let parts = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let s = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Join Room" : s
    }

    private var roomLabelForSharing: String {
        sanitizeRoomLabel(currentRoomLabel)
    }

    private func makePrintedJoinQRUIImage(from string: String,
                                          title: String,
                                          qrScale: CGFloat = 14) -> UIImage? {
        guard let tile = makeBrandedJoinQRUIImage(from: string, qrScale: qrScale) else { return nil }

        let title = sanitizeRoomLabel(title)
        let topPad: CGFloat = 28
        let midPad: CGFloat = 18
        let sidePad: CGFloat = 24
        let bottomPad: CGFloat = 28

        let maxWidth = tile.size.width + (sidePad * 2)

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping

        let titleFont = UIFont.systemFont(ofSize: 34, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: para
        ]

        let titleRect = (title as NSString).boundingRect(
            with: CGSize(width: maxWidth - (sidePad * 2), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        ).integral

        let canvasSize = CGSize(
            width: maxWidth,
            height: topPad + titleRect.height + midPad + tile.size.height + bottomPad
        )

        let r = UIGraphicsImageRenderer(size: canvasSize)
        return r.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            let titleDrawRect = CGRect(
                x: sidePad,
                y: topPad,
                width: maxWidth - (sidePad * 2),
                height: titleRect.height
            )
            (title as NSString).draw(with: titleDrawRect,
                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                     attributes: attrs,
                                     context: nil)

            let tileOrigin = CGPoint(
                x: (maxWidth - tile.size.width) * 0.5,
                y: topPad + titleRect.height + midPad
            )
            tile.draw(at: tileOrigin)
        }
    }

    @EnvironmentObject private var syncSettings: SyncSettings
    @EnvironmentObject private var settings: AppSettings

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showCopiedToast = false
    @State private var lastCopied: CopyKey? = nil
    @State private var showQRModal = false
    @State private var toastText: String = "Copied"
    private enum JoinQRTab: CaseIterable {
        case create
        case rooms

        var title: String {
            switch self {
            case .create: return "Create"
            case .rooms: return "Rooms"
            }
        }

        var systemImage: String {
            switch self {
            case .create: return "qrcode"
            case .rooms: return "tray.full"
            }
        }
    }

    @State private var selectedTab: JoinQRTab = .create
    @StateObject private var roomsStore = RoomsStore()
    @Namespace private var tabNamespace

    private enum CopyKey { case link, hostID, ip, port }

    // Website QR-generator entrypoint (Advanced → Open in browser only)
    private var prefillGeneratorURL: URL {
        // matches web decodeState(): #state=<base64(JSON)>
        let hosts: [[String: String]] = [
            ["uuid": hostUUIDString, "deviceName": deviceName]
        ]

        let json: [String: Any] = [
            "mode": joinMode,                  // "wifi" | "nearby"
            "roomLabel": roomLabelForSharing,
            "hosts": hosts,
            "minBuild": "",
            "minVersion": "",
            "displayMode": false,
            "printMode": false
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []),
              !data.isEmpty
        else { return hostShareURL }

        let payload = data.base64EncodedString()

        var c = URLComponents()
        c.scheme = "https"
        c.host = "synctimerapp.com"
        c.path = "/qr/"
        c.fragment = "state=\(payload)"
        return c.url ?? hostShareURL
    }
    private var prefillGeneratorURLString: String { prefillGeneratorURL.absoluteString }


    // Canonical App Clip join URL (QR/Share/Copy/Print must use this)
    private var joinMode: String {
        (normalizedConnectionMethod == .bluetooth) ? "nearby" : "wifi"
    }

    private var joinAppClipURL: URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "synctimerapp.com"
        c.path = "/join"

        var items: [URLQueryItem] = [
            .init(name: "v", value: "1"),
            .init(name: "mode", value: joinMode),
            .init(name: "hosts", value: hostUUIDString)
        ]

        // Optional but expected (keeps UI nicer in Join flow)
        if !deviceName.isEmpty {
            items.append(.init(name: "device_names", value: deviceName))
        }
        // single shared label (even if multiple hosts/device_names)
        items.append(.init(name: "room_label", value: roomLabelForSharing))

        if let endpoint = wifiJoinEndpoint {
            items.append(.init(name: "ip", value: endpoint.ip))
            items.append(.init(name: "port", value: String(endpoint.port)))
        }

        // Legacy hint only if bonjour is actually the stored method
        if syncSettings.connectionMethod == .bonjour {
            items.append(.init(name: "transport_hint", value: "bonjour"))
        }

        // Update gating (optional but supported)
        if let buildStr = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let build = Int(buildStr), build > 0 {
            items.append(.init(name: "min_build", value: String(build)))
        }

        c.queryItems = items
        return c.url ?? prefillGeneratorURL
    }

    private var joinAppClipURLString: String { joinAppClipURL.absoluteString }

    private func joinAppClipURL(for room: Room) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "synctimerapp.com"
        c.path = "/join"

        let mode = (room.connectionMethod == .bluetooth) ? "nearby" : "wifi"
        var items: [URLQueryItem] = [
            .init(name: "v", value: "1"),
            .init(name: "mode", value: mode),
            .init(name: "hosts", value: room.hostUUID.uuidString)
        ]

        if !deviceName.isEmpty {
            items.append(.init(name: "device_names", value: deviceName))
        }
        items.append(.init(name: "room_label", value: sanitizeRoomLabel(room.label)))

        if let endpoint = wifiJoinEndpoint(forPort: room.listenPort), mode == "wifi" {
            items.append(.init(name: "ip", value: endpoint.ip))
            items.append(.init(name: "port", value: String(endpoint.port)))
        }

        if room.connectionMethod == .bonjour {
            items.append(.init(name: "transport_hint", value: "bonjour"))
        }

        if let buildStr = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let build = Int(buildStr), build > 0 {
            items.append(.init(name: "min_build", value: String(build)))
        }

        c.queryItems = items
        return c.url ?? prefillGeneratorURL
    }

    private var uuidSuffix: String { String(hostUUIDString.suffix(8)).uppercased() }
    private var hostUUID: UUID? { UUID(uuidString: hostUUIDString) }

    private var normalizedConnectionMethod: SyncSettings.SyncConnectionMethod {
        switch syncSettings.connectionMethod {
        case .bonjour: return .network   // bonjour deprecated → treat as Wi-Fi in this sheet
        default:       return syncSettings.connectionMethod
        }
    }
    private var transportLabel: String {
        switch normalizedConnectionMethod {
        case .network:   return "Wi-Fi"
        case .bluetooth: return "Nearby"
        case .bonjour:   return "Wi-Fi" // unreachable via normalized, but keeps switch future-proof
        }
    }
    private var transportSymbol: String {
        switch normalizedConnectionMethod {
        case .network:   return "wifi"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .bonjour:   return "wifi"
        }
    }
    private var subtitleLine2: String {
        switch normalizedConnectionMethod {
        case .network:   return "Same network and port required."
        case .bluetooth: return "Works nearby over Bluetooth."
        case .bonjour:   return "Same network and port required."
        }
    }


    // Treat default/sentinel ports as "unset" for display-only (mirrors ConnectionPage)
    private func isUnsetPort(_ s: String) -> Bool {
        guard let p = UInt16(s) else { return true }
        if p == 0 || p == 50000 { return true }
        return !(49153...65534).contains(p)
    }

    private func generateEphemeralPort() -> UInt16 {
        UInt16.random(in: 49153...65534)
    }

    private func ensureValidListenPortIfNeeded() {
        if isUnsetPort(syncSettings.listenPort) {
            syncSettings.listenPort = String(generateEphemeralPort())
        }
    }

    private func connectionLabel(for method: SyncSettings.SyncConnectionMethod) -> String {
        switch method {
        case .network:   return "Wi-Fi"
        case .bluetooth: return "Nearby"
        case .bonjour:   return "Wi-Fi" // deprecated
        }
    }

    private func showRenamePrompt(for room: Room) {
        renameDraft = room.label
        roomToRename = room
    }


    private var ipString: String {
        getLocalIPAddress() ?? "Not on Wi-Fi"
    }

    private var wifiJoinEndpoint: (ip: String, port: UInt16)? {
        guard joinMode == "wifi" else { return nil }
        guard let ip = getLocalIPAddress(), !ip.isEmpty else { return nil }
        guard let port = UInt16(syncSettings.listenPort),
              (49153...65534).contains(port) else { return nil }
        return (ip, port)
    }

    private func wifiJoinEndpoint(forPort portString: String) -> (ip: String, port: UInt16)? {
        guard let ip = getLocalIPAddress(), !ip.isEmpty else { return nil }
        guard let port = UInt16(portString),
              (49153...65534).contains(port) else { return nil }
        return (ip, port)
    }

    private var isWiFiJoinReady: Bool {
        joinMode != "wifi" || wifiJoinEndpoint != nil
    }

    private func hapticSuccess() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func copyToPasteboard(_ value: String, key: CopyKey, toast: String = "Copied") {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif

        hapticSuccess()
        toastText = toast
        lastCopied = key

        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) { showCopiedToast = true }
        } else {
            showCopiedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !reduceMotion {
                withAnimation(.easeIn(duration: 0.18)) { showCopiedToast = false }
            } else {
                showCopiedToast = false
            }
            lastCopied = nil
        }
    }

    private func loadRoom(_ room: Room) {
        let wasEnabled = syncSettings.isEnabled
        let currentRole = syncSettings.role

        if wasEnabled {
            if currentRole == .parent { syncSettings.stopParent() }
            else { syncSettings.stopChild() }
        }

        syncSettings.connectionMethod = (room.connectionMethod == .bonjour) ? .network : room.connectionMethod
        syncSettings.role = room.role
        if room.connectionMethod != .bluetooth { // network OR legacy bonjour
            syncSettings.listenPort = room.listenPort
        }

        syncSettings.isEnabled = true
        if room.role == .parent { syncSettings.startParent() }
        else { syncSettings.startChild() }

        roomsStore.updateLastUsed(room)

        showQRModal = false
        showCopiedToast = false
        lastCopied = nil

        if reduceMotion {
            selectedTab = .create
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = .create
            }
        }
    }

    private var currentRoomLabel: String {
        guard let hostUUID, let room = roomsStore.room(for: hostUUID) else {
            return "Join Room"
        }
        return room.label
    }

    private func ensureActiveRoom() {
        guard let hostUUID else { return }
        let label = roomsStore.room(for: hostUUID)?.label ?? "Join Room"
        roomsStore.upsert(
            hostUUID: hostUUID,
            label: label,
            connectionMethod: normalizedConnectionMethod,
            role: syncSettings.role,
            listenPort: syncSettings.listenPort
        )
    }

    private func syncActiveRoomSettings() {
        guard let hostUUID else { return }
        let label = roomsStore.room(for: hostUUID)?.label ?? "Join Room"
        roomsStore.upsert(
            hostUUID: hostUUID,
            label: label,
            connectionMethod: normalizedConnectionMethod,
            role: syncSettings.role,
            listenPort: syncSettings.listenPort
        )
    }

    private func beginRoomLabelEdit() {
        roomLabelDraft = currentRoomLabel
        isEditingRoomLabel = true
        roomLabelFocused = true
    }

    private func commitRoomLabelEdit() {
        guard let hostUUID else { return }
        let trimmed = sanitizeRoomLabel(roomLabelDraft)
        roomsStore.rename(hostUUID: hostUUID, newLabel: trimmed)
        roomLabelDraft = trimmed
        isEditingRoomLabel = false
        roomLabelFocused = false
    }

    // MARK: - QR image
    #if canImport(UIKit)
    private typealias JoinQRImage = UIImage
    #else
    private typealias JoinQRImage = Never
    #endif
    #if canImport(UIKit)
    private func makeQRCodeUIImage(from string: String, scale: CGFloat = 10) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
#if canImport(UIKit)
    @MainActor
private enum AppAsset {
    final class Token {} // anchors the bundle for *this* module/target
    static let bundle = Bundle(for: Token.self)

    static func uiImage(named name: String) -> UIImage? {
        // Try module bundle first, then main, then legacy
        if let ui = UIImage(named: name, in: bundle, compatibleWith: nil) { return ui.withRenderingMode(.alwaysOriginal) }
        if let ui = UIImage(named: name, in: .main, compatibleWith: nil) { return ui.withRenderingMode(.alwaysOriginal) }
        if let ui = UIImage(named: name) { return ui.withRenderingMode(.alwaysOriginal) }

        // Fallback: render the SwiftUI Image into a UIImage (works even when UIKit lookup doesn’t)
        if #available(iOS 16.0, *) {
            let r = ImageRenderer(content:
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 256, height: 256)
            )
            r.isOpaque = false
            return r.uiImage
        }
        return nil
    }
}
#endif

    private func makeBrandedJoinQRUIImage(
        from string: String,
        qrScale: CGFloat = 14,
        tileCornerRadius: CGFloat = 22,
        tilePadding: CGFloat = 18
    ) -> UIImage? {
        guard let rawQR = makeQRCodeUIImage(from: string, scale: qrScale) else { return nil }

        let qrSide = rawQR.size.width
        let tileSide = qrSide + (tilePadding * 2)
        let tileSize = CGSize(width: tileSide, height: tileSide)

        let renderer = UIGraphicsImageRenderer(size: tileSize)
        let logoImage = UIImage(named: "AppLogo")

        return renderer.image { context in
            let tileRect = CGRect(origin: .zero, size: tileSize)
            let tilePath = UIBezierPath(roundedRect: tileRect, cornerRadius: tileCornerRadius)
            UIColor.white.setFill()
            tilePath.fill()

            // Draw QR (crisp, no interpolation)
            let qrRect = CGRect(x: tilePadding, y: tilePadding, width: qrSide, height: qrSide)
            context.cgContext.saveGState()
            context.cgContext.setShouldAntialias(false)
            context.cgContext.interpolationQuality = .none
            rawQR.draw(in: qrRect)
            context.cgContext.restoreGState()

            // If logo missing, still return a valid QR tile
            guard let logo = logoImage else { return }

            // Center “logo plate” over the QR (ECC H makes this safe)
            let plateSide = min(max(qrSide * 0.24, 64), qrSide * 0.28) // ~24–28% of QR
            let plateRect = CGRect(
                x: tilePadding + (qrSide - plateSide) * 0.5,
                y: tilePadding + (qrSide - plateSide) * 0.5,
                width: plateSide,
                height: plateSide
            )

            let plateCorner = plateSide * 0.26
            let platePath = UIBezierPath(roundedRect: plateRect, cornerRadius: plateCorner)

            // Plate shadow + fill (knocks out modules under it)
            context.cgContext.saveGState()
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 8,
                color: UIColor.black.withAlphaComponent(0.18).cgColor
            )
            UIColor.white.withAlphaComponent(0.98).setFill()
            platePath.fill()
            context.cgContext.restoreGState()

            // Subtle strokes (premium but minimal)
            UIColor.white.withAlphaComponent(0.18).setStroke()
            platePath.lineWidth = 1
            platePath.stroke()

            let innerStroke = UIBezierPath(
                roundedRect: plateRect.insetBy(dx: 0.6, dy: 0.6),
                cornerRadius: plateCorner * 0.92
            )
            UIColor.black.withAlphaComponent(0.06).setStroke()
            innerStroke.lineWidth = 0.6
            innerStroke.stroke()

            // Draw logo (readable)
            let logoInset = plateSide * 0.10
            let logoRect = plateRect.insetBy(dx: logoInset, dy: logoInset)
            logo.draw(in: logoRect)
        }
    }

    #endif

    @ViewBuilder
    private var headerIcon: some View {
        let base = Image(systemName: showShareGlyph ? "square.and.arrow.up" : "qrcode")
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(showShareGlyph ? .hierarchical : .palette)
            .foregroundStyle(showShareGlyph ? settings.flashColor : .primary,
                             settings.flashColor) // qrcode keeps (primary + flashColor)

        ZStack {
            LiquidGlassCircle(diameter: 44, tint: settings.flashColor)

            if #available(iOS 26.0, *) {
                if reduceMotion {
                    base
                } else {
                    base
                      .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.upUp.byLayer)))
//                      .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showShareGlyph)

                }
            } else {
                // older iOS: no symbolEffect, still visible
                Image(systemName: "qrcode")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            showShareGlyph = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    showShareGlyph = true   // one replace: qrcode → share
                }
            }
        }
        .onDisappear { showShareGlyph = false } // ensures it replays next time

        .accessibilityHidden(true)
    }


    private func glassCard<Content: View>(cornerRadius: CGFloat = 16,
                                          @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(.systemBackground))
                          : AnyShapeStyle(Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private struct QuickChipButtonStyle: ButtonStyle {
        var reduceMotion: Bool
        var isEmphasized: Bool = false

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            let strokeOpacity: Double = pressed ? 0.22 : 0.10
            let shadowOpacity: Double = pressed ? 0.10 : 0.06
            let shadowRadius: CGFloat = pressed ? 10 : 8
            let shadowY: CGFloat = pressed ? 6 : 5

            return configuration.label
                .scaleEffect(pressed ? 0.98 : 1.0)
                .brightness(pressed ? 0.03 : 0.0)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.8)
                        .padding(0.5)
                }
                .shadow(color: .black.opacity(shadowOpacity),
                        radius: shadowRadius,
                        x: 0, y: shadowY)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
        }

    }

    private func quickChip(
        leading: String,
        text: String,
        trailing: String,
        isActive: Bool,
        isEmphasized: Bool = false,
        disabled: Bool = false
    ) -> some View {
        let shape = Capsule()

        // Precompute styles (dramatically reduces SwiftUI type-check complexity)
        let leadingColor: Color = disabled
            ? .secondary
            : (isActive ? settings.flashColor : .primary.opacity(0.85))

        let textColor: Color = disabled ? .secondary : .primary
        let trailingColor: Color = disabled ? .secondary.opacity(0.7) : .secondary

        let ringColor: Color = disabled
            ? Color.white.opacity(0.10)
            : (isActive
                ? settings.flashColor.opacity(isEmphasized ? 0.40 : 0.26)
                : Color.white.opacity(0.18))

        return HStack(spacing: 8) {
            Image(systemName: leading)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(leadingColor)
                .ifAvailableSymbolReplace()

            Text(text)
                .font(.custom(isEmphasized ? "Roboto-SemiBold" : "Roboto-Medium", size: 13))
                .foregroundStyle(textColor)

            Image(systemName: trailing)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(trailingColor)
                .contentTransition(.symbolEffect(.replace))
                .ifAvailableSymbolReplace()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 36)
        .background { quickChipBackground(in: shape) }
        .overlay { shape.stroke(ringColor, lineWidth: 1) }
        .overlay { shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6).padding(1) }
        .opacity(disabled ? 0.60 : 1.0)
        .accessibilityElement(children: .combine)
    }


    private func stopSyncIfRunning() {
        guard syncSettings.isEnabled else { return }
        if syncSettings.role == .parent { syncSettings.stopParent() }
        else { syncSettings.stopChild() }
        syncSettings.isEnabled = false
    }

    private func setConnectionMethod(_ method: SyncSettings.SyncConnectionMethod) {
        let desired: SyncSettings.SyncConnectionMethod = (method == .bonjour) ? .network : method
        guard syncSettings.connectionMethod != desired else { return }
        Haptics.light()
        stopSyncIfRunning()
        syncSettings.connectionMethod = desired
        if desired == .network {
            ensureValidListenPortIfNeeded()
        }
        syncActiveRoomSettings()
    }


    private func cycleConnectionMethod() {
        let next: SyncSettings.SyncConnectionMethod
        switch normalizedConnectionMethod {
        case .network:   next = .bluetooth
        case .bluetooth: next = .network
        case .bonjour:   next = .network
        }
        setConnectionMethod(next)
    }

    @ViewBuilder
    private func quickChipBackground(in shape: Capsule) -> some View {
        if reduceTransparency {
            shape.fill(Color(.systemBackground))
        } else if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }


    private func setRole(_ role: SyncSettings.Role) {
        guard syncSettings.role != role else { return }
        Haptics.light()
        stopSyncIfRunning()
        syncSettings.role = role
        syncActiveRoomSettings()
    }

    private func toggleRole() {
        let next: SyncSettings.Role = (syncSettings.role == .parent) ? .child : .parent
        setRole(next)
    }

    private func setSyncEnabled(_ enabled: Bool) {
        guard syncSettings.isEnabled != enabled else { return }
        Haptics.light()
        if enabled {
            // Prefer the sheet’s “blessed” enable path if provided (keeps parity with main UX).
            if let onRequestEnableSync { onRequestEnableSync(); return }

            // Safe fallback if the closure is nil.
            syncSettings.isEnabled = true
            if syncSettings.role == .parent { syncSettings.startParent() }
            else { syncSettings.startChild() }
        } else {
            stopSyncIfRunning()
        }
    }


    private func glassPrimaryButton(label: String,
                                    systemImage: String,
                                    disabled: Bool = false,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .font(.custom("Roboto-SemiBold", size: 16))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.00)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1.0)
        .accessibilityLabel(label)
    }

    private func glassSecondaryButton(label: String,
                                      systemImage: String,
                                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .font(.custom("Roboto-Medium", size: 16))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func glassToggleBackground(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Group {
            if reduceTransparency {
                shape.fill(Color(.systemBackground))
            } else if #available(iOS 26.0, macOS 15.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
                
            } else if #available(iOS 18.0, macOS 15.0, *) {
                shape
                    .fill(.clear)
                    .containerShape(shape)
                    .clipShape(shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            shape.stroke(Color.white.opacity(0.16), lineWidth: 0.6)
        )
    }

    private var joinTabsPicker: some View {
        let radius: CGFloat = 12
        return HStack(spacing: 6) {
            ForEach(JoinQRTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: radius - 3, style: .continuous)
                                .fill(Color.primary.opacity(0.1))
                                .matchedGeometryEffect(id: "joinQrTab", in: tabNamespace)
                        }
                        ViewThatFits(in: .horizontal) {
                            Label(tab.title, systemImage: tab.systemImage)
                                .font(.custom("Roboto-SemiBold", size: 13))
                                .labelStyle(.titleAndIcon)
                                .contentTransition(.symbolEffect(.replace))
                            Image(systemName: tab.systemImage)
                                .font(.custom("Roboto-SemiBold", size: 13))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: 42)
        .background(glassToggleBackground(radius: radius))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .frame(minHeight: 32)
    }

    private func advancedRow(title: String,
                             detail: String? = nil,
                             leadingSymbol: String,
                             key: CopyKey? = nil,
                             disabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Roboto-Medium", size: 14))
                        .foregroundColor(.primary)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Group {
                    if let key, lastCopied == key {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .ifAvailableSymbolReplace()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1.0)
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            headerIcon

            VStack(alignment: .leading, spacing: 6) {
                Text("Join QR")
                    .font(.custom("Roboto-SemiBold", size: 26))
                Text("Share a configured session with multiple people quickly through custom QRs.")
                    .font(.custom("Roboto-Regular", size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer()

            GlassCircleIconButton(
                systemName: "xmark",
                tint: settings.flashColor,
                accessibilityLabel: "Dismiss"
            ) {
                dismiss()
                Haptics.selection()
            }
        }
    }

    @ViewBuilder
    private var createRoomTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Compact payload summary (does real work)
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(deviceName)
                            .font(.custom("Roboto-SemiBold", size: 18))
                        Spacer()
                        Button {
                            copyToPasteboard(hostUUIDString, key: .hostID, toast: "Host ID copied")
                        } label: {
                            HStack(spacing: 6) {
                                Text("…\(uuidSuffix)")
                                    .font(.system(.caption, design: .monospaced))
                                Image(systemName: (lastCopied == .hostID) ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .ifAvailableSymbolReplace()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy Host ID")
                    }

                    if syncSettings.connectionMethod == .network {
                        Divider().opacity(0.12)

                        HStack(spacing: 10) {
                            Text("IP")
                                .font(.custom("Roboto-Medium", size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .leading)

                            Text(ipString)
                                .font(.custom("Roboto-Regular", size: 14))
                                .foregroundColor(ipString == "Not on Wi-Fi" ? .secondary : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Spacer()

                            if ipString != "Not on Wi-Fi" {
                                Button {
                                    copyToPasteboard(ipString, key: .ip, toast: "IP copied")
                                } label: {
                                    Image(systemName: (lastCopied == .ip) ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .ifAvailableSymbolReplace()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy IP")
                            }
                        }

                        HStack(spacing: 10) {
                            Text("Port")
                                .font(.custom("Roboto-Medium", size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .leading)

                            Text(syncSettings.listenPort)
                                .font(.custom("Roboto-Regular", size: 14))
                                .foregroundColor(isUnsetPort(syncSettings.listenPort) ? .secondary : .primary)

                            Spacer()

                            if !syncSettings.listenPort.isEmpty {
                                Button {
                                    copyToPasteboard(syncSettings.listenPort, key: .port, toast: "Port copied")
                                } label: {
                                    Image(systemName: (lastCopied == .port) ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .ifAvailableSymbolReplace()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy Port")
                            }
                        }
                    }
                }
            }

            // Glass chips (meaningful state)
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick settings")
                    .font(.custom("Roboto-Regular", size: 12))
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    // Transport (tap cycles; long-press shows explicit choices)
                    Button {
                        if reduceMotion { cycleConnectionMethod() }
                        else { withAnimation(.easeInOut(duration: 0.18)) { cycleConnectionMethod() } }
                    } label: {
                        quickChip(
                            leading: transportSymbol,
                            text: transportLabel,
                            trailing: "arrow.triangle.2.circlepath",
                            isActive: true
                        )
                    }
                    .buttonStyle(QuickChipButtonStyle(reduceMotion: reduceMotion))
                    .contextMenu {
                        Button { setConnectionMethod(.network) } label: { Label("Wi-Fi", systemImage: "wifi") }
                        Button { setConnectionMethod(.bluetooth) } label: { Label("Nearby", systemImage: "antenna.radiowaves.left.and.right") }
                    }
                    .accessibilityHint("Tap to cycle. Touch and hold for choices.")

                    // Role (tap toggles; long-press shows explicit choices)
                    Button {
                        if reduceMotion { toggleRole() }
                        else { withAnimation(.easeInOut(duration: 0.18)) { toggleRole() } }
                    } label: {
                        quickChip(
                            leading: (syncSettings.role == .parent ? "arrow.up.circle" : "arrow.down.circle"),
                            text: (syncSettings.role == .parent ? "Parent" : "Child"),
                            trailing: "arrow.triangle.swap",
                            isActive: true
                        )
                    }
                    .buttonStyle(QuickChipButtonStyle(reduceMotion: reduceMotion))
                    .contextMenu {
                        Button { setRole(.parent) } label: { Label("Parent", systemImage: "arrow.up.circle") }
                        Button { setRole(.child) } label: { Label("Child", systemImage: "arrow.down.circle") }
                    }
                    .accessibilityHint("Tap to toggle. Touch and hold for choices.")

                    // SYNC (primary in row)
                    Button {
                        if reduceMotion { setSyncEnabled(!syncSettings.isEnabled) }
                        else { withAnimation(.easeInOut(duration: 0.18)) { setSyncEnabled(!syncSettings.isEnabled) } }
                    } label: {
                        if syncSettings.isEnabled {
                            quickChip(
                                leading: "checkmark.circle.fill",
                                text: "Ready to Join",
                                trailing: "power",
                                isActive: true,
                                isEmphasized: true
                            )
                        } else {
                            quickChip(
                                leading: "bolt.fill",
                                text: "Enable SYNC",
                                trailing: "power",
                                isActive: false,
                                isEmphasized: true
                            )
                        }
                    }
                    .buttonStyle(QuickChipButtonStyle(reduceMotion: reduceMotion, isEmphasized: true))
                    .accessibilityHint(syncSettings.isEnabled ? "Tap to turn SYNC off." : "Tap to turn SYNC on.")
                }
            }
            .padding(.top, 2)

            .padding(.top, 2)

            // Actionable SYNC enable (only when it can help)
            if !syncSettings.isEnabled, let onRequestEnableSync {
                glassSecondaryButton(label: "Turn SYNC On", systemImage: "bolt.fill") {
                    onRequestEnableSync()
                }
                .accessibilityHint("Enables SYNC so children can connect.")
            }
            
            Divider().opacity(0.95)

            glassCard {
                Button {
                    beginRoomLabelEdit()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Room name")
                                .font(.custom("Roboto-Regular", size: 12))
                                .foregroundColor(.secondary)
                            if isEditingRoomLabel {
                                TextField("Join Room", text: $roomLabelDraft)
                                    .font(.custom("Roboto-SemiBold", size: 18))
                                    .focused($roomLabelFocused)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        commitRoomLabelEdit()
                                    }
                            } else {
                                Text(currentRoomLabel)
                                    .font(.custom("Roboto-SemiBold", size: 18))
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                        if isEditingRoomLabel {
                            Text("Return to save")
                                .font(.custom("Roboto-Light", size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onChange(of: roomLabelFocused) { focused in
                if !focused, isEditingRoomLabel {
                    commitRoomLabelEdit()
                }
            }

            
            glassPrimaryButton(label: "Save Room",
                               systemImage: "tray.and.arrow.down",
                               disabled: syncSettings.role != .parent) {
                guard let hostUUID else { return }
                roomsStore.upsert(
                    hostUUID: hostUUID,
                    label: roomLabelForSharing,
                    connectionMethod: normalizedConnectionMethod,
                    role: syncSettings.role,
                    listenPort: syncSettings.listenPort
                )
            }

            
            Text("Save rooms to keep connection presets handy or print QR codes for easy scanning. \(subtitleLine2)")
                .font(.custom("Roboto-Light", size: 12))
                .foregroundColor(.secondary)
            
            Divider().opacity(0.95)

            // Primary + Secondary actions (reduced above-the-fold weight)
            VStack(spacing: 10) {
                if !isWiFiJoinReady, joinMode == "wifi" {
                    Text("Connect to Wi-Fi to share a Wi-Fi join link.")
                        .font(.custom("Roboto-Regular", size: 12))
                        .foregroundColor(.secondary)
                }

                glassPrimaryButton(label: "Show QR",
                                   systemImage: "qrcode",
                                   disabled: (syncSettings.role != .parent || !isWiFiJoinReady)) {
                    Haptics.light()
                    if reduceMotion {
                        showQRModal = true
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showQRModal = true
                        }
                    }
                }

                HStack(spacing: 10) {
                    ShareLink(item: joinAppClipURL) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                            Text("Share")
                                .font(.custom("Roboto-Medium", size: 16))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
                    .buttonStyle(.plain)
                    .disabled(syncSettings.role != .parent || !isWiFiJoinReady)
                    .opacity(syncSettings.role != .parent || !isWiFiJoinReady ? 0.55 : 1.0)

                    #if canImport(UIKit)
                    glassSecondaryButton(label: "Print", systemImage: "printer") {
                        Haptics.light()
                        printJoinQR()
                    }
                    .disabled(syncSettings.role != .parent || !isWiFiJoinReady)
                    .opacity(syncSettings.role != .parent || !isWiFiJoinReady ? 0.55 : 1.0)
                    #endif
                }

                .buttonStyle(.plain)
                .disabled(syncSettings.role != .parent || !isWiFiJoinReady)
                .opacity(syncSettings.role != .parent || !isWiFiJoinReady ? 0.55 : 1.0)
            }
            
            
            Divider().opacity(0.95)

            // Troubleshooting (collapsed)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Confirm both devices are on the same Wi-Fi.")
                        .font(.custom("Roboto-Regular", size: 13))
                        .foregroundColor(.secondary)
                    Text("• Try Nearby mode.")
                        .font(.custom("Roboto-Regular", size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Text("Troubleshooting")
                    .font(.custom("Roboto-Medium", size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            // Advanced (collapsed): utilities + “open in browser”
            DisclosureGroup {
                VStack(spacing: 10) {
                    advancedRow(title: "Copy Join link",
                                detail: nil,
                                leadingSymbol: "link",
                                key: .link,
                                disabled: (syncSettings.role != .parent || !isWiFiJoinReady)) {
                        copyToPasteboard(joinAppClipURLString, key: .link, toast: "Join link copied")
                    }


                    advancedRow(title: "Copy Host ID",
                                detail: "…\(uuidSuffix)",
                                leadingSymbol: "number",
                                key: .hostID) {
                        copyToPasteboard(hostUUIDString, key: .hostID, toast: "Host ID copied")
                    }

                    if syncSettings.connectionMethod == .network, ipString != "Not on Wi-Fi" {
                        advancedRow(title: "Copy IP",
                                    detail: ipString,
                                    leadingSymbol: "wifi",
                                    key: .ip) {
                            copyToPasteboard(ipString, key: .ip, toast: "IP copied")
                        }
                    }

                    if syncSettings.connectionMethod == .network, !syncSettings.listenPort.isEmpty {
                        advancedRow(title: "Copy Port",
                                    detail: syncSettings.listenPort,
                                    leadingSymbol: "circle.grid.cross",
                                    key: .port) {
                            copyToPasteboard(syncSettings.listenPort, key: .port, toast: "Port copied")
                        }
                    }

                    Button {
                        openURL(prefillGeneratorURL)

                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "safari")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            Text("Open in browser")
                                .font(.custom("Roboto-Medium", size: 14))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Text("Opens the QR generator page for this host (prefilled).")
                        .font(.custom("Roboto-Light", size: 12))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced")
                    .font(.custom("Roboto-Medium", size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var roomsLibraryTab: some View {
        if roomsStore.rooms.isEmpty {
            VStack(spacing: 10) {
                Text("No saved rooms yet.")
                    .font(.custom("Roboto-Regular", size: 14))
                    .foregroundColor(.secondary)
                glassPrimaryButton(label: "Create a Room", systemImage: "plus") {
                    selectedTab = .create
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 20)
        } else {
            List {
                ForEach(roomsStore.rooms) { room in
                    glassCard {
                        roomRow(room)
                    }
                    .contextMenu {
                        Button {
                            showRenamePrompt(for: room)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        ShareLink(item: joinAppClipURL(for: room)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            roomsStore.delete(room)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            roomsStore.delete(room)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func roomRow(_ room: Room) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.label)
                        .font(.custom("Roboto-SemiBold", size: 16))
                    Spacer()
                    Text(connectionLabel(for: room.connectionMethod))
                        .font(.custom("Roboto-Regular", size: 12))
                        .foregroundColor(.secondary)
                }
                Text("Host …\(room.hostUUID.uuidString.suffix(4)) • Port \(room.listenPort) • \(room.lastUsed.formatted(date: .numeric, time: .shortened))")
                    .font(.custom("Roboto-Regular", size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                showRenamePrompt(for: room)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            Button {
                loadRoom(room)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text("Load Room")
                        .font(.custom("Roboto-Medium", size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        let showTabs = !roomsStore.rooms.isEmpty
        #if canImport(UIKit)
        let printAction: (() -> Void)? = { printJoinQR() }
        #else
        let printAction: (() -> Void)? = nil
        #endif
        return ZStack {
            if reduceTransparency {
                Color(.systemBackground)
                    .ignoresSafeArea()
            } else if #available(iOS 26.0, macOS 15.0, *) {
                let sheetShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassEffect(.regular, in: sheetShape)
                    .ignoresSafeArea()
                    .containerShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                if showTabs {
                    joinTabsPicker
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                if selectedTab == .create || !showTabs {
                    ScrollView {
                        createRoomTab
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                    }
                } else {
                    roomsLibraryTab
                        .padding(.top, 16)
                }
            }
            .allowsHitTesting(!showQRModal)

            if showCopiedToast {
                Text(toastText)
                    .font(.custom("Roboto-Medium", size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
            }

            if showQRModal {
                JoinQRStageOverlay(
                    joinAppClipURL: joinAppClipURL,
                    roomLabel: roomLabelForSharing,
                    deviceName: deviceName,
                    uuidSuffix: uuidSuffix,
                    accentColor: settings.flashColor,
                    reduceMotion: reduceMotion,
                    reduceTransparency: reduceTransparency,
                    qrImage: {
                        #if canImport(UIKit)
                        return makeBrandedJoinQRUIImage(from: joinAppClipURLString, qrScale: 14)
                        #else
                        return nil
                        #endif
                    }(),
                    onDismiss: {
                        if reduceMotion {
                            showQRModal = false
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showQRModal = false
                            }
                        }
                    },
                    onPrint: printAction
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onChange(of: roomsStore.rooms.count) { newValue in
            guard newValue == 0, selectedTab == .rooms else { return }
            if reduceMotion {
                selectedTab = .create
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = .create
                }
            }
        }
        .alert("Rename Room", isPresented: Binding(
            get: { roomToRename != nil },
            set: { isPresented in
                if !isPresented {
                    roomToRename = nil
                }
            }
        )) {
            TextField("Room name", text: $renameDraft)
            Button("Save") {
                guard let room = roomToRename else { return }
                roomsStore.rename(hostUUID: room.hostUUID, newLabel: renameDraft)
                if room.hostUUID == hostUUID {
                    roomLabelDraft = sanitizeRoomLabel(renameDraft)
                }
                roomToRename = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Newlines are removed.")
        }
        // iOS 16+ (works on iOS 26): remove default sheet material background
        .presentationBackground(.clear)

        // optional: keep system dimming but prevent weird “card” feel
        .presentationBackgroundInteraction(.disabled)
        .onAppear {
            if joinMode == "wifi" {
                ensureValidListenPortIfNeeded()
            }
            ensureActiveRoom()
        }
    }

    private struct JoinQRStageOverlay: View {
        let joinAppClipURL: URL
        let roomLabel: String
        let deviceName: String
        let uuidSuffix: String
        let accentColor: Color
        let reduceMotion: Bool
        let reduceTransparency: Bool
        let qrImage: JoinQRImage?
        let onDismiss: () -> Void
        let onPrint: (() -> Void)?

        @State private var highlightShift = false

        private var cardShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        }

        var body: some View {
            ZStack {
                Color.black
                    .opacity(reduceTransparency ? 0.55 : 0.45)
                    .ignoresSafeArea()
                    .overlay {
                        if !reduceTransparency {
                            RadialGradient(
                                colors: [
                                    Color.black.opacity(0.10),
                                    Color.black.opacity(0.48)
                                ],
                                center: .center,
                                startRadius: 80,
                                endRadius: 520
                            )
                            .ignoresSafeArea()
                        }
                    }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .ignoresSafeArea()

                ZStack {
                    if !reduceMotion {
                        cardShape
                            .fill(
                                RadialGradient(
                                    colors: [
                                        accentColor.opacity(0.18),
                                        accentColor.opacity(0.06),
                                        Color.clear
                                    ],
                                    center: highlightShift ? .topLeading : .bottomTrailing,
                                    startRadius: 20,
                                    endRadius: 260
                                )
                            )
                            .opacity(reduceTransparency ? 0.12 : 0.18)
                            .animation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true), value: highlightShift)
                            .onAppear { highlightShift = true }
                    }

                    VStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text(deviceName)
                                .font(.custom("Roboto-SemiBold", size: 18))
                            Text("Host ID …\(uuidSuffix)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white)
                            #if canImport(UIKit)
                            if let qrImage {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(20)
                                    .accessibilityLabel("Join QR code")
                            } else {
                                Text("Unable to generate QR.")
                                    .font(.custom("Roboto-Regular", size: 14))
                                    .foregroundColor(.secondary)
                            }
                            #else
                            Text("QR preview is not available on this platform.")
                                .font(.custom("Roboto-Regular", size: 14))
                                .foregroundColor(.secondary)
                            #endif
                        }
                        .frame(maxWidth: 320, maxHeight: 320)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                        Text(roomLabel)
                           .font(.custom("Roboto-SemiBold", size: 18))
                           .multilineTextAlignment(.center)
                           .lineLimit(1)
                           .minimumScaleFactor(0.85)
                           .padding(.top, 2)
                        HStack(spacing: 14) {
                            ShareLink(item: joinAppClipURL) {

                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                    Text("Share")
                                        .font(.custom("Roboto-Medium", size: 14))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Share Join QR")

                            GlassCircleIconButton(
                                systemName: "xmark",
                                tint: accentColor,
                                size: 48,
                                iconPointSize: 16,
                                accessibilityLabel: "Close"
                            ) {
                                onDismiss()
                            }

                            if let onPrint {
                                Button(action: onPrint) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "printer")
                                            .font(.system(size: 14, weight: .semibold))
                                            .symbolRenderingMode(.hierarchical)
                                        Text("Print")
                                            .font(.custom("Roboto-Medium", size: 14))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Print Join QR")
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 420)
                    .background {
                        if reduceTransparency {
                            cardShape.fill(Color(.systemBackground))
                        } else if #available(iOS 26.0, macOS 15.0, *) {
                            ZStack {
                                cardShape.fill(Color(.systemBackground).opacity(0.88))
                                Color.clear.glassEffect(.regular, in: cardShape)
                            }
                        } else {
                            cardShape.fill(Color(.systemBackground).opacity(0.88))
                        }
                    }
                    .overlay(
                        cardShape.stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
                    .overlay(
                        cardShape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            .padding(1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
                    .padding(.horizontal, 24)
                }
            }
        }
    }
}

// MARK: - iOS 17 symbol replace helper (compile-safe)
private extension View {
    @ViewBuilder
    func ifAvailableSymbolReplace() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
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
    @State private var showCreditsSheet = false
    @State private var showTroubleshootSheet = false

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
    @EnvironmentObject private var syncSettings: SyncSettings
    @EnvironmentObject private var whatsNewController: WhatsNewController
    
    private var flashTint: Color { appSettings.flashColor }

    private var aboutTint: Color {
        appSettings.appTheme == .dark ? .white : .gray
    }

    private var aboutGridColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    @ViewBuilder
    private func aboutLinkCell(title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            AboutDrawerSurface {
                AboutDrawerRow(icon: icon, title: title, tint: aboutTint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    
    private struct AboutDrawerRow: View {
        let icon: String
        let title: String
        let tint: Color
        var chevronTint: Color = .secondary

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 22, alignment: .center)

                Text(title)
                    .font(.custom("Roboto-Regular", size: 15))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(chevronTint)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
    }

    private struct AboutDrawerSurface<Content: View>: View {
        var tint: Color? = nil
        @ViewBuilder var content: () -> Content

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

            content()
                .background {
                    if #available(iOS 26.0, *) {
                        ZStack {
                         if let tint {
                             // Tint wash (saturated “plate” feel)
                             shape.fill(tint.opacity(0.22))
                             // Glass on top, tinted
                             shape
                                 .fill(Color.clear)
                                 .glassEffect(.regular.tint(tint), in: shape)
                             // Rim
                             shape.stroke(Color.white.opacity(0.14), lineWidth: 1)
                         } else {
                             // Neutral glass (existing behavior)
                             shape
                                 .fill(Color.clear)
                                 .glassEffect(.regular, in: shape)
                             shape.stroke(Color.white.opacity(0.12), lineWidth: 1)
                         }
                     }
                    } else {
                        ZStack {
                                                 if let tint {
                                                     shape.fill(tint.opacity(0.18))
                                                 }
                                                 shape.fill(.thinMaterial)
                                                 shape.stroke(Color.white.opacity(0.12), lineWidth: 1)
                                             }
                    }
                }
                .clipShape(shape)
        }
    }

    private struct CreditsSheet: View {
        @EnvironmentObject private var appSettings: AppSettings
        let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var expandedIDs: Set<String> = []
    @State private var copyAllConfirmationVisible = false

    @State private var legacyShareItem: LegacyShareItem? = nil

    // MARK: - Data model

    private enum CreditKind: String, CaseIterable {
        case people = "People"
        case font = "Fonts & Typography"
        case library = "Open-source"
        case service = "Services"
    }

    private struct CreditLink: Hashable {
        let title: String
        let url: URL
        let systemImage: String
    }

    private struct CreditItem: Identifiable, Hashable {
        let id: String
        let kind: CreditKind
        let name: String
        let role: String
        let licenseId: String?
        let copyright: String?
        let noticeText: String
        let links: [CreditLink]
        let isRequired: Bool
        let systemImage: String
    }

    // MARK: - Constants

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "SyncTimer"
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    private var osString: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    private var supportURL: URL {
        // TODO: set to your real support/contact page if different
        URL(string: "https://www.synctimerapp.com/support")!
    }

    private var websiteURL: URL {
        URL(string: "https://www.synctimerapp.com")!
    }

    private var privacyURL: URL {
        // TODO: update if your canonical URL changes
        URL(string: "https://www.cbassuarez.com/synctimer-privacy-policy")!
    }

    private var termsURL: URL {
        // TODO: update if your canonical URL changes
        URL(string: "https://www.cbassuarez.com/synctimer-terms-of-service")!
    }

    private var aboutTint: Color {
        appSettings.appTheme == .dark ? .white : .gray
    }

    private var flashTint: Color { appSettings.flashColor }

    // MARK: - Items

    private var creditItems: [CreditItem] {
        [
            // People
            CreditItem(
                id: "stagedevices",
                kind: .people,
                name: "Stage Devices, LLC",
                role: "Publisher",
                licenseId: nil,
                copyright: nil,
                noticeText: "SyncTimer is produced and published by Stage Devices, LLC.",
                links: [
                    CreditLink(title: "Website", url: websiteURL, systemImage: "safari"),
                    CreditLink(title: "Support", url: supportURL, systemImage: "questionmark.circle")
                ],
                isRequired: false,
                systemImage: "building.2"
            ),
            CreditItem(
                id: "design-engineering",
                kind: .people,
                name: "Design & Engineering",
                role: "Sebastian Suarez",
                licenseId: nil,
                copyright: nil,
                noticeText: "Design, engineering, and product direction.",
                links: [
                    CreditLink(title: "Support", url: supportURL, systemImage: "questionmark.circle")
                ],
                isRequired: false,
                systemImage: "paintbrush.pointed"
            ),

            // Fonts
            CreditItem(
                id: "roboto",
                kind: .font,
                name: "Roboto",
                role: "Used for UI text",
                licenseId: "Apache-2.0",
                copyright: "Copyright 2011 Google Inc.",
                noticeText: """

    Roboto font family
    Copyright 2011 Google Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    """,
    links: [
    CreditLink(title: "Website", url: URL(string: "[https://fonts.google.com/specimen/Roboto](https://fonts.google.com/specimen/Roboto)")!, systemImage: "globe"),
    CreditLink(title: "License", url: URL(string: "[https://www.apache.org/licenses/LICENSE-2.0](https://www.apache.org/licenses/LICENSE-2.0)")!, systemImage: "doc.text")
    ],
    isRequired: true,
    systemImage: "textformat"
    ),

            // Services / SDKs (present in codebase)
            CreditItem(
                id: "sentry",
                kind: .service,
                name: "Sentry",
                role: "Crash reporting & diagnostics",
                licenseId: "MIT", // TODO: confirm your exact Sentry SDK license for your pinned version
                copyright: nil,
                noticeText: """

    Sentry SDK

    License: MIT
    Source and license details are provided by Sentry.

    (If you ship Sentry via SPM/CocoaPods, paste the exact license text here for your pinned version.)
    """,
    links: [
    CreditLink(title: "Website", url: URL(string: "[https://sentry.io](https://sentry.io)")!, systemImage: "globe"),
    CreditLink(title: "License", url: URL(string: "[https://github.com/getsentry/sentry-cocoa](https://github.com/getsentry/sentry-cocoa)")!, systemImage: "doc.text")
    ],
    isRequired: true,
    systemImage: "waveform.path.ecg"
    )
    ]
    }

    // MARK: - Search

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matchesQuery(_ item: CreditItem) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        let haystack = [
            item.kind.rawValue,
            item.name,
            item.role,
            item.licenseId ?? "",
            item.copyright ?? "",
            item.noticeText
        ]
        .joined(separator: " • ")
        .lowercased()

        return haystack.contains(normalizedQuery)
    }

    private var filteredItems: [CreditItem] {
        creditItems.filter(matchesQuery)
    }

    private func items(for kind: CreditKind) -> [CreditItem] {
        filteredItems.filter { $0.kind == kind }
    }

    // MARK: - Third-party notices blob

    private var requiredItems: [CreditItem] {
        creditItems.filter { $0.isRequired }
    }

    private var requiredNoticesIncluded: Bool {
        // “Included” here means: required items exist and have non-empty notice text.
        !requiredItems.isEmpty && requiredItems.allSatisfy { !$0.noticeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var thirdPartyNoticesText: String {
        requiredItems
            .map { item in
                let headerBits: [String] = [
                    item.name,
                    item.licenseId.map { "(\($0))" } ?? nil
                ].compactMap { $0 }

                let header = headerBits.joined(separator: " ")
                return """

    (header)
    (item.noticeText.trimmingCharacters(in: .whitespacesAndNewlines))
    """
    }
    .joined(separator: "\n\n—\n\n")
    .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeThirdPartyNoticesFileURL() -> URL? {
        let text = thirdPartyNoticesText
        guard !text.isEmpty else { return nil }

        let fileName = "ThirdPartyNotices.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - UI pieces

    private var heroCard: some View {
        AboutDrawerSurface(tint: flashTint) {
            HStack(alignment: .center, spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appDisplayName)
                        .font(.custom("Roboto-SemiBold", size: 18))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Stage Devices, LLC • Made in Los Angeles")
                        .font(.custom("Roboto-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 10) {
                        Text("v\(versionString) (\(buildString))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)

                        Text(osString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
        }
    }

    private var requiredNoticeRow: some View {
        AboutDrawerSurface {
            HStack(spacing: 10) {
                Image(systemName: requiredNoticesIncluded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(requiredNoticesIncluded ? .green : .orange)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(requiredNoticesIncluded ? "Required notices included" : "Notices need attention")
                        .font(.custom("Roboto-SemiBold", size: 15))
                        .foregroundStyle(aboutTint)
                        .lineLimit(1)

                    Text(requiredNoticesIncluded ? "Third-party notices are bundled for sharing and audit." : "Add/confirm any missing third-party license text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.custom("Roboto-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 2)
    }

    private func licensePill(_ licenseId: String?) -> some View {
        HStack(spacing: 6) {
            if let licenseId, !licenseId.isEmpty {
                Text(licenseId)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(aboutTint)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(appSettings.appTheme == .dark ? 0.10 : 0.24))
                    )
            }
        }
    }

    private func toggleExpanded(_ id: String) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func creditRow(_ item: CreditItem) -> some View {
        let isExpanded = expandedIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                    toggleExpanded(item.id)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.kind == .font ? flashTint : aboutTint)
                        .frame(width: 22, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.custom("Roboto-SemiBold", size: 15))
                            .foregroundStyle(aboutTint)
                            .lineLimit(1)

                        Text(item.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    licensePill(item.licenseId)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Copy name") { copyToClipboard(item.name) }
                if let id = item.licenseId, !id.isEmpty {
                    Button("Copy license id") { copyToClipboard(id) }
                }
                Button("Copy full notice") { copyToClipboard(item.noticeText) }
            }

            if isExpanded {
                if let c = item.copyright, !c.isEmpty {
                    Text(c)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text(item.noticeText)
                    .font(.custom("Roboto-Light", size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !item.links.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(item.links, id: \.self) { link in
                            Link(destination: link.url) {
                                HStack(spacing: 6) {
                                    Image(systemName: link.systemImage)
                                        .font(.system(size: 12, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                    Text(link.title)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(aboutTint)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(appSettings.appTheme == .dark ? 0.08 : 0.18))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            copyToClipboard(item.noticeText)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                Text("Copy notice")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(aboutTint)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(appSettings.appTheme == .dark ? 0.08 : 0.18))
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(appSettings.appTheme == .dark ? 0.04 : 0.06))
        )
    }

    private func sectionCard(title: String, subtitle: String, content: @escaping () -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title, subtitle: subtitle)
            AboutDrawerSurface {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Legal card (copy/share + blob)

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Legal", subtitle: "Shareable third-party notices and policy links.")
            AboutDrawerSurface {
                VStack(alignment: .leading, spacing: 12) {

                    // Copy / Share actions
                    HStack(spacing: 10) {
                        Button {
                            copyToClipboard(thirdPartyNoticesText)
                            withAnimation(.easeInOut(duration: 0.2)) { copyAllConfirmationVisible = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation(.easeInOut(duration: 0.2)) { copyAllConfirmationVisible = false }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 13, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                Text("Copy all notices")
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(flashTint)
                            )
                        }
                        .buttonStyle(.plain)

                        if #available(iOS 16.0, *), let url = makeThirdPartyNoticesFileURL() {
                            ShareLink(item: url) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                    Text("Share notices")
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(aboutTint)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(appSettings.appTheme == .dark ? 0.08 : 0.18))
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                guard let url = makeThirdPartyNoticesFileURL() else { return }
                                legacyShareItem = LegacyShareItem(activityItems: [url])
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                    Text("Share notices")
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(aboutTint)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(appSettings.appTheme == .dark ? 0.08 : 0.18))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 0)
                    }

                    if copyAllConfirmationVisible {
                        Text("Copied to clipboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }

                    // Third-party notices blob
                    DisclosureGroup {
                        Text(thirdPartyNoticesText.isEmpty ? "No notices available." : thirdPartyNoticesText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    } label: {
                        Text("Third-party notices")
                            .font(.custom("Roboto-SemiBold", size: 14))
                            .foregroundStyle(aboutTint)
                    }
                    .tint(flashTint)

                    // Policy links
                    VStack(alignment: .leading, spacing: 8) {
                        Link(destination: privacyURL) {
                            AboutDrawerRow(icon: "hand.raised.fill", title: "Privacy Policy", tint: aboutTint)
                        }
                        .buttonStyle(.plain)

                        Link(destination: termsURL) {
                            AboutDrawerRow(icon: "doc.text.fill", title: "Terms of Service", tint: aboutTint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Legacy share

    private struct LegacyShareItem: Identifiable {
        let id = UUID()
        let activityItems: [Any]
    }

    private struct LegacyShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard
                    requiredNoticeRow

                    // Search results “mode”
                    if !normalizedQuery.isEmpty {
                        sectionCard(
                            title: "Results",
                            subtitle: "Matching credits and licenses."
                        ) {
                            AnyView(
                                VStack(alignment: .leading, spacing: 10) {
                                    if filteredItems.isEmpty {
                                        Text("No matches.")
                                            .font(.custom("Roboto-Regular", size: 14))
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 12)
                                    } else {
                                        ForEach(filteredItems) { item in
                                            creditRow(item)
                                        }
                                    }
                                }
                            )
                        }
                    } else {
                        // Prestige variant: Made by + Thanks + Fonts + Services + Legal
                        sectionCard(
                            title: "Made by",
                            subtitle: "Publisher, contact, and core credits."
                        ) {
                            AnyView(
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(items(for: .people)) { item in
                                        creditRow(item)
                                    }
                                }
                            )
                        }

                        sectionCard(
                            title: "Thanks",
                            subtitle: "Collaborators, testers, and institutions."
                        ) {
                            AnyView(
                                VStack(alignment: .leading, spacing: 10) {
                                    DisclosureGroup {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("• SyncTimer beta testers")
                                            Text("• CalArts (testing & performance contexts)")
                                            Text("• Colleagues and ensembles who stress-tested sync workflows")
                                        }
                                        .font(.custom("Roboto-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 6)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "hands.sparkles.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                                .symbolRenderingMode(.hierarchical)
                                                .foregroundStyle(aboutTint)
                                                .frame(width: 22, alignment: .center)

                                            Text("Special thanks")
                                                .font(.custom("Roboto-SemiBold", size: 15))
                                                .foregroundStyle(aboutTint)

                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .tint(flashTint)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.white.opacity(appSettings.appTheme == .dark ? 0.04 : 0.06))
                                    )
                                }
                            )
                        }

                        sectionCard(
                            title: "Fonts & Typography",
                            subtitle: "Typefaces used by the app, with license details."
                        ) {
                            AnyView(
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(items(for: .font)) { item in
                                        creditRow(item)
                                    }
                                }
                            )
                        }

                        sectionCard(
                            title: "Open-source & Services",
                            subtitle: "SDKs and services used for stability and diagnostics."
                        ) {
                            AnyView(
                                VStack(alignment: .leading, spacing: 10) {
                                    let services = items(for: .service) + items(for: .library)
                                    if services.isEmpty {
                                        Text("No third-party services listed.")
                                            .font(.custom("Roboto-Regular", size: 14))
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 12)
                                    } else {
                                        ForEach(services) { item in
                                            creditRow(item)
                                        }
                                    }
                                }
                            )
                        }

                        legalCard
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search credits & licenses")
            .navigationTitle("Credits & Licenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
            .sheet(item: $legacyShareItem) { item in
                LegacyShareSheet(activityItems: item.activityItems)
            }
        }
    }

    }
    
    private struct PressScaleStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .opacity(configuration.isPressed ? 0.94 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
        }
    }

    
    

    private struct TroubleshootSheet: View {
        @EnvironmentObject private var appSettings: AppSettings
        @EnvironmentObject private var syncSettings: SyncSettings
        @Environment(\.dismiss) private var dismiss
        @AppStorage("settingsPage") private var settingsPage = 0

    @State private var includeDeviceName = false
    @State private var includeScreenshot = false
    @State private var lastEventId: String? = nil

    @State private var copyConfirmationVisible = false
    @State private var shareItem: ShareItem? = nil

    // New: notes + review gate
    @State private var reportNotes: String = ""
    @State private var showReviewSheet = false

    // New: send-state icon cycle (paperplane.fill -> paperplane -> checkmark -> paperplane.fill)
    private enum SendState: Equatable { case idle, sending, sent }
    @State private var sendState: SendState = .idle

    // New: disclosure sections
    @State private var expandQuickActions = true
    @State private var expandDetails = false
    @State private var expandFixes = false
        
        
        private var topBarTitleFont: Font {
            if #available(iOS 26.0, *) { return .largeTitle.weight(.semibold) }
            return .title3.weight(.semibold)
        }

        private var topBarSubtitleFont: Font {
            if #available(iOS 26.0, *) { return .subheadline }
            return .footnote
        }

        private var troubleshootTopBarHeader: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("Report a Bug")
                    .font(topBarTitleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Send a report with diagnostics and an Event ID.")
                    .font(topBarSubtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)
        }


    let version: String
    let build: String
    let supportURL: URL

    private var aboutTint: Color {
        appSettings.appTheme == .dark ? .white : .gray
    }

    private var sendIconName: String {
        switch sendState {
        case .idle: return "paperplane.fill"
        case .sending: return "paperplane"
        case .sent: return "checkmark"
        }
    }
    

    private var notesCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(aboutTint)
                    .frame(width: 22, alignment: .center)

                Text("What happened? (optional)")
                    .font(.custom("Roboto-Regular", size: 15))
                    .foregroundStyle(aboutTint)

                Spacer()
            }

            if #available(iOS 16.0, *) {
                TextField("1–2 lines is perfect.", text: $reportNotes, axis: .vertical)
                    .lineLimit(1...2)
                    .font(.custom("Roboto-Regular", size: 14))
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .padding(.top, 2)
            } else {
                TextField("1–2 lines is perfect.", text: $reportNotes)
                    .font(.custom("Roboto-Regular", size: 14))
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            }
        }
        .clipShape(shape)
    }

        private var sendSubtitle: String {
            switch sendState {
            case .idle:
                return "Includes diagnostics. You’ll get an Event ID."
            case .sending:
                return "Sending…"
            case .sent:
                return "Sent. Event ID shown above."
            }
        }

        private var primarySendDrawer: some View {
            AboutDrawerSurface(tint: appSettings.flashColor) {
                HStack(spacing: 12) {
                    // icon badge (more “button”, less “row”)
                    ZStack {
                        Circle().fill(Color.white.opacity(0.18))
                        Group {
                            if #available(iOS 17.0, *) {
                                Image(systemName: sendIconName)
                                    .contentTransition(.symbolEffect(.replace))
                            } else {
                                Image(systemName: sendIconName)
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Send Report")
                            .font(.custom("Roboto-SemiBold", size: 17))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(sendSubtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.9))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .frame(minHeight: 64)   // <- the key: not a tiny strip anymore
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Send Report")
            .accessibilityHint("Review what will be sent, then send a report and receive an Event ID.")
        }


    private var privacyCard: some View {
        AboutDrawerSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(aboutTint)
                        .frame(width: 22, alignment: .center)

                    Toggle(isOn: $includeDeviceName) {
                        Text("Include device name")
                            .font(.custom("Roboto-Regular", size: 15))
                            .foregroundStyle(aboutTint)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))
                }

                Text("Reports include diagnostics only. No location, contacts, or content from your cue sheets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let lastEventId {
                        HStack(spacing: 8) {
                            Text("Last Event ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastEventId)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 2)
                    }
                    notesCard

                    Button {
                        guard sendState != .sending else { return }
                        Haptics.light()
                        showReviewSheet = true
                    } label: {
                        primarySendDrawer
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(sendState == .sending)
                    
                    privacyCard

                    disclosureCard(
                        title: "Quick actions",
                        systemImage: "bolt.fill",
                        isExpanded: $expandQuickActions
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button { copyDiagnostics() } label: {
                                AboutDrawerSurface {
                                    AboutDrawerRow(icon: "doc.on.doc", title: "Copy Diagnostics", tint: aboutTint)
                                }
                            }
                            .buttonStyle(.plain)

                            if copyConfirmationVisible {
                                Text("Copied to clipboard")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                            }

                            Button { shareDiagnostics() } label: {
                                AboutDrawerSurface {
                                    AboutDrawerRow(icon: "square.and.arrow.up", title: "Share Diagnostics", tint: aboutTint)
                                }
                            }
                            .buttonStyle(.plain)

                            if lastEventId != nil {
                                Button { copyEventId() } label: {
                                    AboutDrawerSurface {
                                        AboutDrawerRow(icon: "number.circle", title: "Copy Event ID", tint: aboutTint)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 10)
                    }

                    disclosureCard(
                        title: "Details",
                        systemImage: "info.circle.fill",
                        isExpanded: $expandDetails
                    ) {
                        statusCard
                            .padding(.top, 10)
                    }

                    disclosureCard(
                        title: "Fixes",
                        systemImage: "wrench.and.screwdriver.fill",
                        isExpanded: $expandFixes
                    ) {
                        commonFixes
                            .padding(.top, 10)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        troubleshootTopBarHeader
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }

            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            .sheet(isPresented: $showReviewSheet) {
                ReviewReportSheet(
                    version: version,
                    build: build,
                    includeDeviceName: includeDeviceName,
                    includeScreenshot: $includeScreenshot,
                    notes: reportNotes,
                    diagnostics: makeDiagnosticsSnapshot(),
                    onConfirmSend: {
                        showReviewSheet = false
                        sendReport()
                    }
                )
                .environmentObject(appSettings)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        // Ensure the sheet defaults to medium and can expand on demand, with drag indicator.
        .modifier(PresentationDefaults())
    }

    // MARK: - Glass disclosure card

        @ViewBuilder
        private func disclosureCard<Content: View>(
            title: String,
            systemImage: String,
            isExpanded: Binding<Bool>,
            @ViewBuilder content: @escaping () -> Content   //  add @escaping
        ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: isExpanded) {
                content()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(aboutTint)
                        .frame(width: 22, alignment: .center)

                    Text(title)
                        .font(.custom("Roboto-Regular", size: 15))
                        .foregroundStyle(aboutTint)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .tint(aboutTint)
        }
        .padding(12)
        .background {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            }
        }
        .clipShape(shape)
    }

    // MARK: - Status

    private var statusCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            statusRow(label: "Version", value: "\(version) (\(build))")
            statusRow(label: "Device", value: deviceLabel)
            statusRow(label: "iOS", value: UIDevice.current.systemVersion)
            statusRow(label: "Theme", value: appSettings.appTheme.rawValue.capitalized)
            statusRow(label: "Reduce Motion", value: UIAccessibility.isReduceMotionEnabled ? "On" : "Off")
            statusRow(label: "Sync", value: syncStatusDescription)
        }
        .font(.footnote)
        .padding(14)
        .background {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            }
        }
        .clipShape(shape)
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Fixes

    private var commonFixes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                settingsPage = 2
                dismiss()
            } label: {
                AboutDrawerSurface {
                    AboutDrawerRow(icon: "gearshape.fill", title: "Open Sync settings", tint: aboutTint)
                }
            }
            .buttonStyle(.plain)

            Button {
                NotificationCenter.default.post(name: .whatsNewOpenCueSheets, object: nil)
                dismiss()
            } label: {
                AboutDrawerSurface {
                    AboutDrawerRow(icon: "list.bullet.rectangle", title: "Open Cue Sheets", tint: aboutTint)
                }
            }
            .buttonStyle(.plain)

            Button {
                openSystemSettings(urlString: "App-Prefs:root=Bluetooth")
            } label: {
                AboutDrawerSurface {
                    AboutDrawerRow(icon: "bolt.horizontal.fill", title: "Open Bluetooth settings", tint: aboutTint)
                }
            }
            .buttonStyle(.plain)

            Button {
                openSystemSettings(urlString: "App-Prefs:root=WIFI")
            } label: {
                AboutDrawerSurface {
                    AboutDrawerRow(icon: "wifi", title: "Open Wi-Fi settings", tint: aboutTint)
                }
            }
            .buttonStyle(.plain)

            Link(destination: supportURL) {
                AboutDrawerSurface {
                    AboutDrawerRow(icon: "safari", title: "Open Support Website", tint: aboutTint)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Review sheet

    private struct ReviewReportSheet: View {
        @EnvironmentObject private var appSettings: AppSettings
        @Environment(\.dismiss) private var dismiss
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let version: String
        let build: String
        let includeDeviceName: Bool
        @Binding var includeScreenshot: Bool
        let notes: String
        let diagnostics: String
        let onConfirmSend: () -> Void

        private var topBarTitleFont: Font {
            if #available(iOS 26.0, *) { return .largeTitle.weight(.semibold) }
            return .title3.weight(.semibold)
        }

        private var topBarSubtitleFont: Font {
            if #available(iOS 26.0, *) { return .subheadline }
            return .footnote
        }

        private var reviewTopBarHeader: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Report")
                    .font(topBarTitleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Confirm what will be sent.")
                    .font(topBarSubtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: -84)
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)
        }

        private var summaryCard: some View {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

            return VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Version")
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text("\(version) (\(build))")
                        .foregroundStyle(.primary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Device name")
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(includeDeviceName ? "Included" : "Not included")
                        .foregroundStyle(.primary)
                }

                Toggle(isOn: $includeScreenshot) {
                    Text("Include screenshot (may contain sensitive info)")
                        .foregroundStyle(.primary)
                }
                .toggleStyle(SwitchToggleStyle(tint: appSettings.flashColor))

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Notes")
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : notes)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }

                DisclosureGroup {
                    Text(diagnostics)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } label: {
                    Text("Preview diagnostics")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .tint(appSettings.flashColor)

                Text("No location, contacts, or cue sheet content are included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .font(.footnote)
            .padding(14)
            .background {
                if #available(iOS 26.0, *) {
                    shape
                        .fill(Color.clear)
                        .glassEffect(.regular, in: shape)
                        .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
            }
            .clipShape(shape)
        }

        private var sendDrawer: some View {
            AboutDrawerSurface(tint: appSettings.flashColor) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(width: 22, alignment: .center)

                    Text("Send Report")
                        .font(.custom("Roboto-Regular", size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .contentShape(Rectangle())
            }
        }

        private struct SlideToSend: View {
            let tint: Color
            let reduceMotion: Bool
            let onConfirm: () -> Void

            @State private var dragX: CGFloat = 0
            @State private var didConfirm = false
            @State private var phase: Phase = .idle
            @State private var lock: Lock = .undecided
            @State private var baseX: CGFloat = 0

            private enum Phase {
                case idle
                case sending
                case sent
            }

            private enum Lock {
                case undecided
                case horizontal
                case vertical
            }

            private var statusLabel: String {
                switch phase {
                case .idle:
                    return "Slide to Send"
                case .sending:
                    return "Sending…"
                case .sent:
                    return "Sent"
                }
            }

            private var symbolName: String {
                switch phase {
                case .idle:
                    return "paperplane.fill"
                case .sending:
                    return "paperplane"
                case .sent:
                    return "checkmark"
                }
            }

            private func animationStyle() -> Animation {
                if reduceMotion {
                    return .easeOut(duration: 0.15)
                }
                return .interactiveSpring(response: 0.25, dampingFraction: 0.86, blendDuration: 0.1)
            }

            private func confirmSend(maxOffset: CGFloat) {
                guard !didConfirm else { return }
                didConfirm = true
                phase = .sending
                withAnimation(animationStyle()) {
                    dragX = maxOffset
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onConfirm()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    phase = .sent
                }
            }

            var body: some View {
                GeometryReader { proxy in
                    let metrics = layoutMetrics(for: proxy.size.width)
                    let isDragging = lock == .horizontal && dragX > 0

                    trackView(
                        height: metrics.trackHeight,
                        horizontalPadding: metrics.horizontalPadding,
                        isDragging: isDragging,
                        maxOffset: metrics.maxOffset,
                        threshold: metrics.threshold,
                        thumbSize: metrics.thumbSize
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Send Report")
                    .accessibilityHint("Slide to confirm sending diagnostics and optional screenshot.")
                    .accessibilityValue(phase == .idle ? "Not sent" : phase == .sending ? "Sending" : "Sent")
                    .accessibilityAction {
                        confirmSend(maxOffset: metrics.maxOffset)
                    }
                }
                .frame(height: 64)
            }

            private struct LayoutMetrics {
                let trackHeight: CGFloat
                let thumbSize: CGFloat
                let horizontalPadding: CGFloat
                let maxOffset: CGFloat
                let threshold: CGFloat
            }

            private func layoutMetrics(for width: CGFloat) -> LayoutMetrics {
                let trackHeight: CGFloat = 64
                let thumbSize: CGFloat = 44
                let horizontalPadding: CGFloat = 12
                let maxOffset = max(0, width - (horizontalPadding * 2 + thumbSize))
                let threshold = maxOffset * 0.85
                return LayoutMetrics(
                    trackHeight: trackHeight,
                    thumbSize: thumbSize,
                    horizontalPadding: horizontalPadding,
                    maxOffset: maxOffset,
                    threshold: threshold
                )
            }

            @ViewBuilder
            private func trackView(
                height: CGFloat,
                horizontalPadding: CGFloat,
                isDragging: Bool,
                maxOffset: CGFloat,
                threshold: CGFloat,
                thumbSize: CGFloat
            ) -> some View {
                AboutDrawerSurface(tint: tint) {
                    ZStack(alignment: .leading) {
                        labelView(isDragging: isDragging)
                        thumbView(
                            maxOffset: maxOffset,
                            threshold: threshold,
                            thumbSize: thumbSize
                        )
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: height)
                }
                .frame(height: height)
                .allowsHitTesting(!didConfirm)
            }

            private func labelView(isDragging: Bool) -> some View {
                Text(statusLabel)
                    .font(.custom("Roboto-Regular", size: 15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(isDragging ? 0.7 : 1)
            }

            private func thumbView(
                maxOffset: CGFloat,
                threshold: CGFloat,
                thumbSize: CGFloat
            ) -> some View {
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .overlay(thumbIcon)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: dragX)
                    .gesture(dragGesture(maxOffset: maxOffset, threshold: threshold))
                    .accessibilityHidden(true)
            }

            private var thumbIcon: some View {
                Group {
                    if #available(iOS 17.0, *) {
                        Image(systemName: symbolName)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image(systemName: symbolName)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            }

            private func dragGesture(maxOffset: CGFloat, threshold: CGFloat) -> some Gesture {
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !didConfirm else { return }
                        if lock == .undecided {
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) > 6 || abs(dy) > 6 {
                                if abs(dx) > abs(dy) {
                                    lock = .horizontal
                                    baseX = dragX
                                } else {
                                    lock = .vertical
                                }
                            }
                        }
                        guard lock == .horizontal else { return }
                        let proposed = baseX + value.translation.width
                        dragX = min(max(0, proposed), maxOffset)
                    }
                    .onEnded { _ in
                        defer {
                            lock = .undecided
                            baseX = dragX
                        }
                        guard !didConfirm else { return }
                        guard lock == .horizontal else { return }
                        if dragX >= threshold {
                            confirmSend(maxOffset: maxOffset)
                        } else {
                            withAnimation(animationStyle()) {
                                dragX = 0
                            }
                        }
                    }
            }
        }

        var body: some View {
            let confirmSend = {
                Haptics.light()
                dismiss()
                onConfirmSend()
            }

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryCard

                        if voiceOverEnabled {
                            Button(action: confirmSend) {
                                sendDrawer
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Send Report")
                            .accessibilityHint("Sends diagnostics and optional screenshot. You’ll receive an Event ID.")
                        } else {
                            SlideToSend(
                                tint: appSettings.flashColor,
                                reduceMotion: reduceMotion,
                                onConfirm: confirmSend
                            )
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 0) {
                            reviewTopBarHeader
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { dismiss() }
                    }
                }

            }
        }
    }

    // MARK: - Actions

    private var deviceLabel: String {
        let model = UIDevice.current.model
        guard includeDeviceName else { return model }
        return "\(model) (\(UIDevice.current.name))"
    }

    private var syncStatusDescription: String {
        let status = syncSettings.isEnabled
            ? (syncSettings.isEstablished ? "Connected" : "Connecting")
            : "Off"
        return "\(roleDescription) • \(syncSettings.connectionMethod.rawValue) • \(status)"
    }

    private var roleDescription: String {
        switch syncSettings.role {
        case .parent: return "Parent"
        case .child: return "Child"
        }
    }

    private func copyDiagnostics() {
        UIPasteboard.general.string = makeDiagnosticsSnapshot()
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.2)) { copyConfirmationVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) { copyConfirmationVisible = false }
        }
    }

    private func shareDiagnostics() {
        guard let url = makeDiagnosticsFileURL() else { return }
        shareItem = ShareItem(url: url)
    }

    private func sendReport() {
        guard sendState != .sending else { return }

        sendState = .sending
        Haptics.light()

        let diagnostics = makeDiagnosticsSnapshot()
        let notes = reportNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let eventId = SentrySDK.capture(message: "User report") { scope in
            scope.setTag(value: "manual_report", key: "source")
            scope.setContext(value: ["snapshot": diagnostics], key: "diagnostics")
            if !notes.isEmpty {
                scope.setContext(value: ["notes": notes], key: "user_notes")
            }
            if let data = diagnostics.data(using: .utf8) {
                let attachment = Attachment(
                    data: data,
                    filename: "SyncTimer-Diagnostics.txt",
                    contentType: "text/plain"
                )
                scope.addAttachment(attachment)
            }
            if includeScreenshot {
                if let pngData = captureScreenshotPNG() {
                    let attachment = Attachment(
                        data: pngData,
                        filename: "SyncTimer-Screenshot.png",
                        contentType: "image/png"
                    )
                    scope.addAttachment(attachment)
                } else {
                    #if DEBUG
                    print("Failed to capture screenshot for manual report.")
                    #endif
                }
            }
        }

        let idString = eventId.sentryIdString
        lastEventId = idString

        // Show Event ID ephemerally in the hero.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if lastEventId == idString { lastEventId = nil }
        }

        // sending -> sent -> idle (with “magic replace” in the icon)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sendState = .sent
            Haptics.light()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                sendState = .idle
            }
        }
    }

    private func copyEventId() {
        guard let lastEventId else { return }
        UIPasteboard.general.string = lastEventId
        Haptics.light()
    }

    private func openSystemSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url) { success in
            guard !success else { return }
            if let fallback = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(fallback)
            }
        }
    }

    private func captureScreenshotPNG() -> Data? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? scenes.first?.windows.first
        guard let window else { return nil }

        let bounds = window.bounds
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return image.pngData()
    }

    private func makeDiagnosticsFileURL() -> URL? {
        let diagnostics = makeDiagnosticsSnapshot()
        let fileName = "SyncTimer-Diagnostics.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try diagnostics.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func makeDiagnosticsSnapshot() -> String {
        var lines: [String] = []
        lines.append("SyncTimer Diagnostics")
        lines.append("Version: \(version) (\(build))")
        lines.append("iOS: \(UIDevice.current.systemVersion)")
        lines.append("Device: \(UIDevice.current.model)")
        if includeDeviceName {
            lines.append("Device Name: \(UIDevice.current.name)")
        }
        lines.append("Theme: \(appSettings.appTheme.rawValue.capitalized)")
        lines.append("Flash Color: \(flashColorDescription())")
        lines.append("Reduce Motion: \(UIAccessibility.isReduceMotionEnabled ? "On" : "Off")")
        lines.append("Sync Role: \(roleDescription)")
        lines.append("Sync Method: \(syncSettings.connectionMethod.rawValue)")
        lines.append("Sync Enabled: \(syncSettings.isEnabled ? "On" : "Off")")
        lines.append("Sync Established: \(syncSettings.isEstablished ? "Yes" : "No")")
        return lines.joined(separator: "\n")
    }

    private func flashColorDescription() -> String {
        let uiColor = UIColor(appSettings.flashColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
        return "Custom"
    }

    // MARK: - ShareSheet

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct ShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }

    // MARK: - Presentation defaults

    private struct PresentationDefaults: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 16.0, *) {
                content
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            } else {
                content
            }
        }
    }

    }

    

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
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
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

                // Row 1: What’s New + Credits (side-by-side to save height)
                VStack(alignment: .leading, spacing: 8) {

                    // Row 1: What’s New + Credits
                    HStack(spacing: 10) {
                        Button {
                            whatsNewController.requestManualPresentation()
                        } label: {
                            AboutDrawerSurface(tint: flashTint) {
                                       AboutDrawerRow(
                                           icon: "sparkles",
                                           title: "What’s New",
                                           tint: .white,
                                           chevronTint: .white.opacity(0.85)
                                       )
                                   }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        Link(destination: URL(string: "https://www.synctimerapp.com")!) {
                            AboutDrawerSurface(tint: flashTint) {
                                       AboutDrawerRow(
                                           icon: "safari",
                                           title: "Website",
                                           tint: .white,
                                           chevronTint: .white.opacity(0.85)
                                       )
                                   }
                          }
                          .buttonStyle(.plain)
                          .frame(maxWidth: .infinity)
                    }

                    // Row 2–3: Support links grid (slightly tighter spacing)
                    LazyVGrid(columns: aboutGridColumns, spacing: 6) {
                        Button {
                               showCreditsSheet = true
                           } label: {
                               AboutDrawerSurface {
                                   AboutDrawerRow(icon: "text.book.closed", title: "Credits", tint: aboutTint)
                               }
                           }
                           .buttonStyle(.plain)
                           .frame(maxWidth: .infinity, alignment: .leading)
                        aboutLinkCell(title: "Privacy Policy", icon: "hand.raised.fill",
                                      url: URL(string: "https://www.cbassuarez.com/synctimer-privacy-policy")!)
                        Button {
                            showTroubleshootSheet = true
                        } label: {
                            AboutDrawerSurface {
                                AboutDrawerRow(icon: "ladybug.fill", title: "Report a Bug", tint: aboutTint)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        aboutLinkCell(title: "Terms of Service", icon: "doc.text.fill",
                                      url: URL(string: "https://www.cbassuarez.com/synctimer-terms-of-service")!)
                    }

                    // Row 4: Share + Rate (PLAIN buttons for max vertical room)
                    HStack(spacing: 10) {

                        if #available(iOS 16.0, *) {
                            ShareLink(item: URL(string: "https://apps.apple.com/app/id123456789")!) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                    Text("Share This App")
                                        .font(.custom("Roboto-Regular", size: 14))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                .foregroundStyle(aboutTint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.vertical, 4) // very compact
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Button {
                                UIApplication.shared.open(URL(string: "https://apps.apple.com/app/id123456789")!)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                    Text("Share This App")
                                        .font(.custom("Roboto-Regular", size: 14))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                .foregroundStyle(aboutTint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            UIApplication.shared.open(URL(string: "itms-apps://itunes.apple.com/app/id123456789")!)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                Text("Rate on App Store")
                                    .font(.custom("Roboto-Regular", size: 14))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundStyle(aboutTint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Made in Los Angeles, CA")
                        .font(.custom("Roboto-Light", size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1) // keep it from being the first thing to disappear
                }


            }
            
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .sheet(isPresented: $showHallOfFame) {
                HallOfFameCard()
                    .environmentObject(appSettings)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showCreditsSheet) {
                CreditsSheet(onDismiss: { showCreditsSheet = false })
                    .environmentObject(appSettings)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showTroubleshootSheet) {
                TroubleshootSheet(
                    version: version,
                    build: build,
                    supportURL: URL(string: "https://www.synctimerapp.com/support")!
                )
                .environmentObject(appSettings)
                .environmentObject(syncSettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            name: "Your Ensemble Here",
            imageName: "nuc_avatar",
            tier: .gold,
            founderTier: .sustainer,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*100),
            thankYou: "Thanks for the monthly support 🫶",
            contributionShare: 0.10
        ),
        Backer(
            name: "Your Ensemble Here",
            imageName: "nuc_avatar",
            tier: .platinum,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*100),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.40
            
        ),
        Backer(
            name: "Your Ensemble Here",
            imageName: "paul_avatar",
            tier: .silver,
            founderTier: .supporter,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "Your Ensemble Here",
            imageName: "paul_avatar",
            tier: .bronze,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "Your Ensemble Here",
            imageName: "nuc_avatar",
            tier: .gold,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "Your Ensemble Here",
            imageName: "nuc_avatar",
            tier: .platinum,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.05
        ),
        Backer(
            name: "Your Ensemble Here",
            imageName: "paul_avatar",
            tier: .silver,
            founderTier: .founder,
            contributionDate: .init(timeIntervalSinceNow: -60*60*24*200),
            thankYou: "Your early pledge made SyncTimer possible!",
            contributionShare: 0.15
        ),
        Backer(
            name: "Your Ensemble Here",
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

//──────────────────────────────────────────────────────────────
// MARK: – LiquidGlassCircle (SDK-safe “liquid glass” button)
//──────────────────────────────────────────────────────────────
private struct GlassCircleIconButton: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 44
    var iconPointSize: CGFloat = 18
    var iconWeight: Font.Weight = .semibold
    var imageRotationDegrees: Double = 0
    var imageRotationAnimation: Animation? = nil
    var accessibilityLabel: String
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if #available(iOS 26.0, *) {
                    let shape = Circle()
                    shape
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(tint), in: shape)
                        .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
                } else {
                    LiquidGlassCircle(diameter: size, tint: tint)
                }

                Image(systemName: systemName)
                    .font(.system(size: iconPointSize, weight: iconWeight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(imageRotationDegrees))
                    .animation(imageRotationAnimation, value: imageRotationDegrees)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
        .frame(width: max(size, 44), height: max(size, 44))
    }
}

private struct LiquidGlassCircle: View {
    let diameter: CGFloat
    let tint: Color
    var body: some View {
        let shape = Circle()
        ZStack {
            // Core glass body (ultra-thin material)
            shape
                .fill(.ultraThinMaterial)
            // Rim lighting
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            // Subtle internal highlight
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(diameter * 0.06)
            // Tint wash (very light)
            shape
                .stroke(tint.opacity(0.35), lineWidth: 1)
                .blur(radius: 0.2)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
        .clipShape(shape)
        .contentShape(shape)
    }
}

// Finally, your card wrapper:
struct SettingsPagerCard: View {
        
    @Binding var page: Int
    @Namespace private var settingsNS

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
                            .matchedGeometryEffect(id: "settingsPageContent", in: settingsNS)
                                                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    case 1:
                        TimerBehaviorPage()
                            .matchedGeometryEffect(id: "settingsPageContent", in: settingsNS)
                                                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    case 2:
                        ConnectionPage(
                            editingTarget: $editingTarget,
                            inputText: $inputText,
                            isEnteringField: $isEnteringField,
                            showBadPortError: $showBadPortError
                        )
                        .matchedGeometryEffect(id: "settingsPageContent", in: settingsNS)
                                                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    case 3:
                        AboutPage()
                            .matchedGeometryEffect(id: "settingsPageContent", in: settingsNS)
                                                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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
                // NEW: Transport picker + Live status circle
                            TransportRow()
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
            }
            // Same timing feel as your card/toolbar morphs; layout remains stable.
                    .animation(
                        {
                            if #available(iOS 17, *) {
                                return .snappy(duration: 0.26, extraBounce: 0.25)
                            } else {
                                return .easeInOut(duration: 0.26)
                            }
                        }(),
                        value: page
                    )
        }
    }
// ─────────────────────────────────────────────────────────────
// MARK: – TransportRow (LAN/BLE) + Liquid Glass status circle
// ─────────────────────────────────────────────────────────────
private struct TransportRow: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncSettings
    @State private var showOverlay = false

    private var isParent: Bool { sync.role == .parent }

    // Mirror lamp: red (off), orange (streaming/not connected), green (connected)
    private var lampColor: Color {
        if !sync.isEnabled { return .red }
        return sync.isEstablished ? .green : .orange
    }

    private var symbolName: String {
        switch sync.connectionMethod {
        case .network:   return "wifi.router.fill"
        case .bluetooth: return "bolt.horizontal.fill"
        default:         return "wifi.router.fill"   // hidden in UI anyway
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Segmented transport picker (LAN / Bluetooth only)
            Picker("Transport", selection: $sync.connectionMethod) {
                Text("Wi-Fi").tag(SyncSettings.SyncConnectionMethod.network)
                Text("Nearby").tag(SyncSettings.SyncConnectionMethod.bluetooth)
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: sync.connectionMethod)

            Spacer(minLength: 12)

            // Liquid Glass status circle
            VStack(spacing: 6) {
                Button {
                    if isParent { showOverlay = true }
                } label: {
                    ZStack {
                                            LiquidGlassCircle(diameter: 60, tint: settings.flashColor)
                                            Image(systemName: symbolName)
                                                .font(.system(size: 24, weight: .semibold))
                                                .foregroundColor(settings.flashColor)
                                                .symbolRenderingMode(.hierarchical)
                                                .shadow(radius: 0.5)
                                            // Small status dot
                                            Circle()
                                                .fill(lampColor)
                                                .frame(width: 10, height: 10)
                                                .offset(x: 20, y: 20)
                                        }
                }
                .buttonStyle(.plain)
                .disabled(!isParent) // child cannot open overlay
                .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6),
                                 trigger: sync.isEstablished)

                // Child hint: show connected parent device name
                if !isParent, sync.isEstablished {
                    Text(sync.pairingDeviceName ?? "Connected")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .sheet(isPresented: $showOverlay) {
            ParticipantsOverlay(show: $showOverlay)
                .presentationDetents([.medium, .large])
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: – ParticipantsOverlay (Parent only)
// ─────────────────────────────────────────────────────────────
private struct ParticipantsOverlay: View {
    @EnvironmentObject private var sync: SyncSettings
    @EnvironmentObject private var settings: AppSettings
    @Binding var show: Bool

    private var parentPeers: [SyncSettings.Peer] {
        sync.peers.sorted { $0.joinTs < $1.joinTs }
    }

    var body: some View {
        NavigationView {
            List {
                Section("Parent") {
                    HStack {
                        Text(sync.localNickname)
                        Spacer()
                        Text("Host")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }
                Section("Children") {
                    if parentPeers.isEmpty {
                        Text("No children connected")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(parentPeers) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                    Text("Joined: \(Date(timeIntervalSince1970: TimeInterval(p.joinTs)/1000).formatted(date: .omitted, time: .shortened))")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                                Spacer()
                                // RSSI as bars (0–3)
                                HStack(spacing: 2) {
                                    ForEach(0..<3) { i in
                                        Rectangle()
                                            .fill(i < p.signalStrength ? settings.flashColor : Color.gray.opacity(0.3))
                                            .frame(width: 3, height: CGFloat(6 + i*4))
                                            .cornerRadius(1)
                                    }
                                }
                                Button("Disconnect") {
                                    sync.disconnectPeer(p.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connected Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { show = false }
                }
            }
        }
    }
}
//──────────────────────────────────────────────────────────────
// MARK: – ContentView
//──────────────────────────────────────────────────────────────
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings
    @EnvironmentObject private var joinRouter: JoinRouter
    @EnvironmentObject private var whatsNewController: WhatsNewController
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var quickActionRouter = QuickActionRouter.shared
    
    @AppStorage("settingsPage") private var settingsPage = 0
    @State private var showSettings = false
    @State private var mainMode: ViewMode = .sync
    @AppStorage("whatsnew.pendingJoin") private var pendingJoinFromWhatsNew: Bool = false
    
    @AppStorage("hasSeenWalkthrough") private var hasSeenWalkthrough: Bool = false
    @State private var showSyncErrorAlert = false
    @State private var syncErrorMessage   = ""
    
    @State private var editingTarget: EditableField? = nil
    @State private var inputText: String = ""
    @State private var isEnteringField: Bool = false
    @State private var didCheckJoinHandoff = false
    @State private var handledJoinRequestId: String? = nil
    @StateObject private var childRoomsStore = ChildRoomsStore()
    @State private var isTimerActive = false
    @State private var isPresentingCueSheets = false
    @State private var isPresentingPresetEditor = false
    @State private var whatsNewEntry: WhatsNewVersionEntry? = nil
    @State private var pendingWhatsNewCueSheetCreate = false
    @State private var showJoinSheetFromWhatsNew = false

    private let whatsNewIndex = WhatsNewContentLoader.load()
    
    var body: some View {
#if os(iOS)
if UIDevice.current.userInterfaceIdiom == .pad {
    GeometryReader { geo in
        let isLandscape = geo.size.width > geo.size.height
        let is129 = max(geo.size.width, geo.size.height) >= 1366  // 12.9" logical height
        let topLift: CGFloat = isLandscape
            ? (geo.safeAreaInsets.top + 982)
            : (geo.safeAreaInsets.top + (is129 ? 520 : 340))       // bump only on 12.9" portrait

        innerBody
            .environment(\.containerSize, geo.size)
            .frame(width: geo.size.width, height: geo.size.height)

            // Keep background full-bleed on sides + bottom, but DO NOT ignore the top.
            .ignoresSafeArea(.container, edges: [.horizontal, .bottom])

            // Push only the CONTENT down in portrait (background stays full-bleed).
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: topLift)
            }
    }
} else {
    innerBody
}
#else
innerBody
#endif





        
        
    }
    
    // Your original body content extracted so we can reuse it
    private var innerBody: some View {
        // Decide backdrop once
               let bgImageName: String = (settings.appTheme == .light) ? "MainBG1" : "MainBG2"
       
        return ZStack { // background fills screen; foreground is centered/capped on iPad
                  // 1) Full-bleed backdrop (never masks/crops foreground)
                   AppBackdrop(imageName: bgImageName)
                       .ignoresSafeArea()
       
                   // 2) Optional light overlay (also full-bleed)
                   if settings.appTheme == .light, settings.customThemeOverlayColor != .clear {
                       Color(settings.customThemeOverlayColor)
                           .compositingGroup()
                           .blendMode(.multiply)
                           .ignoresSafeArea()
                           .transition(.opacity)
                           .animation(.easeInOut(duration: 0.5), value: settings.customThemeOverlayColor)
                   }
       
                   // 3) Foreground content
#if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                GeometryReader { geo in
                            // Pass the **window size** to children so they lay out for THIS window,
                            // not the physical device screen.
                       ScrollView(.vertical, showsIndicators: false) {
                                MainScreen(parentMode: $mainMode, showSettings: $showSettings, isTimerActive: $isTimerActive, isPresentingCueSheets: $isPresentingCueSheets, isPresentingPresetEditor: $isPresentingPresetEditor)
                                    .environment(\.containerSize, geo.size)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .top)
                                    .padding(.vertical, 16)
                            }
                            .padding(.horizontal, 0)
                            .frame(width: geo.size.width, height: geo.size.height)
                    // keep foreground color scheme behavior
                    .preferredColorScheme(
                        mainMode == .stop
                        ? .dark
                        : (settings.appTheme == .dark ? .dark : .light)
                    )
                    // tiny bottom spacer so home-indicator never overlaps
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
                }
            } else {
                    VStack(spacing: 0) {
                           Spacer(minLength: 0)
                           MainScreen(parentMode: $mainMode, showSettings: $showSettings, isTimerActive: $isTimerActive, isPresentingCueSheets: $isPresentingCueSheets, isPresentingPresetEditor: $isPresentingPresetEditor)
                           Spacer(minLength: 12)
                       }
                       .preferredColorScheme(
                           mainMode == .stop
                           ? .dark
                           : (settings.appTheme == .dark ? .dark : .light)
                       )
                   }
                   #else
                   VStack(spacing: 0) {
                       Spacer(minLength: 0)
                       MainScreen(parentMode: $mainMode, showSettings: $showSettings, isTimerActive: $isTimerActive, isPresentingCueSheets: $isPresentingCueSheets, isPresentingPresetEditor: $isPresentingPresetEditor)
                       Spacer(minLength: 12)
                   }
                   .preferredColorScheme(
                       mainMode == .stop
                       ? .dark
                       : (settings.appTheme == .dark ? .dark : .light)
                   )
                   #endif
               }
        // Modals & alerts unchanged
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenWalkthrough },
            set: { _ in hasSeenWalkthrough = true }
        )) {
            WalkthroughView()
                .environmentObject(settings)
                .environmentObject(syncSettings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsPagerCard(page: $settingsPage,
                              editingTarget: $editingTarget,
                              inputText: $inputText,
                              isEnteringField: $isEnteringField,
                              showBadPortError: .constant(false))
            .environmentObject(settings)
            .environmentObject(syncSettings)
            .preferredColorScheme(settings.appTheme == .dark ? .dark : .light)
        }
        .sheet(isPresented: $whatsNewController.isPresented, onDismiss: {
            whatsNewController.markSeen(
                currentVersion: WhatsNewController.currentVersionString,
                currentBuild: WhatsNewController.currentBuildString
            )
            whatsNewEntry = nil
        }) {
            if let entry = whatsNewEntry {
                WhatsNewSheet(
                    entry: entry,
                    onAction: handleWhatsNewAction,
                    onDismiss: { dismissWhatsNew() }
                )
                .tint(settings.flashColor)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showJoinSheetFromWhatsNew) {
            Group {
                if syncSettings.role == .parent {
                    GenerateJoinQRSheet(
                        deviceName: hostDeviceName,
                        hostUUIDString: hostUUIDString,
                        hostShareURL: hostShareURL,
                        onRequestEnableSync: {
                            guard !syncSettings.isEnabled else { return }
                            toggleSyncMode()
                        }
                    )
                } else {
                    ChildJoinSheet(
                        onJoinRequest: { request, transport in
                            startChildJoin(
                                request,
                                transport: transport,
                                syncSettings: syncSettings,
                                toggleSyncMode: toggleSyncMode
                            )
                        },
                        onJoinRoom: { room in
                            startChildRoom(
                                room,
                                syncSettings: syncSettings,
                                toggleSyncMode: toggleSyncMode
                            )
                        }
                    )
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .presentationCornerRadius(28)
        }
        .alert(isPresented: $showSyncErrorAlert) {
            Alert(title: Text("Cannot Start Sync"),
                  message: Text(syncErrorMessage),
                  dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $joinRouter.needsHostPicker) {
            JoinHostPickerSheet(
                pending: joinRouter.pending,
                onSelect: { host in
                    joinRouter.selectHost(host)
                }
            )
        }
        .alert("Update Required", isPresented: Binding(
            get: { joinRouter.updateRequiredMinBuild != nil },
            set: { isPresented in
                if !isPresented {
                    joinRouter.updateRequiredMinBuild = nil
                }
            }
        )) {
            Button("Open App Store") {
                if let url = URL(string: ContentView.appStoreURLString) {
                    openURL(url)
                }
                joinRouter.updateRequiredMinBuild = nil
            }
            Button("Cancel", role: .cancel) {
                joinRouter.updateRequiredMinBuild = nil
            }
        } message: {
            if let minBuild = joinRouter.updateRequiredMinBuild {
                Text("Update required (build \(minBuild)+) to join this session.")
            }
        }
        .onAppear {
            evaluateWhatsNew(reason: "appear")
            guard !didCheckJoinHandoff else { return }
            didCheckJoinHandoff = true
            joinRouter.ingestAppGroupPendingIfAny()
            if syncSettings.connectionMethod == .bonjour {
                            syncSettings.connectionMethod = .network
                        }
            applyJoinIfReady()
        }
        .onChange(of: joinRouter.pending?.selectedHostUUID) { _ in
            applyJoinIfReady()
        }
        .onChange(of: joinRouter.pending?.requestId) { _ in
            applyJoinIfReady()
        }
        .onChange(of: joinRouter.pending?.requestId) { _ in
            evaluateWhatsNew(reason: "join-request-changed")
        }
        .onChange(of: joinRouter.needsHostPicker) { _ in
            evaluateWhatsNew(reason: "join-host-picker")
        }
        .onChange(of: syncSettings.isEstablished) { established in
            guard established, syncSettings.role == .child else { return }
            persistChildRoomOnEstablished()
        }
        .onChange(of: showSettings) { _ in
            evaluateWhatsNew(reason: "settings-toggle")
        }
        .onChange(of: showSyncErrorAlert) { _ in
            evaluateWhatsNew(reason: "sync-alert")
        }
        .onChange(of: hasSeenWalkthrough) { _ in
            evaluateWhatsNew(reason: "onboarding-change")
        }
        .onChange(of: isTimerActive) { _ in
            evaluateWhatsNew(reason: "timer-activity")
        }
        .onChange(of: isPresentingCueSheets) { _ in
            evaluateWhatsNew(reason: "cue-sheets-sheet")
        }
        .onChange(of: isPresentingPresetEditor) { _ in
            evaluateWhatsNew(reason: "preset-editor")
        }
        .onChange(of: whatsNewController.isPresented) { isPresented in
            if isPresented {
                showSettings = false
                if whatsNewEntry == nil {
                    whatsNewEntry = currentWhatsNewEntry
                }
            } else {
                whatsNewEntry = nil
                if pendingWhatsNewCueSheetCreate {
                    pendingWhatsNewCueSheetCreate = false
                    guard !isPresentingModal else { return }
                    NotificationCenter.default.post(
                        name: .whatsNewOpenCueSheets,
                        object: nil,
                        userInfo: ["createBlank": true]
                    )
                }
            }
        }
        .onChange(of: whatsNewController.manualPresentationRequested) { requested in
            guard requested else { return }
            whatsNewController.manualPresentationRequested = false
            presentWhatsNewManually()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            if let action = quickActionRouter.pending {
                handleQuickAction(action)
                quickActionRouter.pending = nil
            }
            evaluateWhatsNew(reason: "scene-active")
        }
        .environmentObject(childRoomsStore)
    }

    private static let appStoreURLString = "https://apps.apple.com/app/id0000000000"

    private var currentWhatsNewEntry: WhatsNewVersionEntry? {
        whatsNewIndex?.entry(for: WhatsNewController.currentVersionString)
    }

    private var hostUUIDString: String {
        syncSettings.localPeerID.uuidString
    }

    private var hostDeviceName: String {
        UIDevice.current.name
    }

    private var hostShareURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "synctimerapp.com"
        components.path = "/host"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "host_uuid", value: hostUUIDString),
            URLQueryItem(name: "device_name", value: hostDeviceName)
        ]
        return components.url ?? URL(string: "https://synctimerapp.com/host")!
    }

    // Whats New eligibility inputs: onboarding flag, timer phase, join flow, cue sheet/preset sheets, and settings.
    private var isOnboardingVisible: Bool { !hasSeenWalkthrough }
    private var isJoinFlowActive: Bool { joinRouter.pending != nil || joinRouter.needsHostPicker }
    private var isPresentingModal: Bool {
        showSettings || showSyncErrorAlert || joinRouter.needsHostPicker || isPresentingCueSheets || isPresentingPresetEditor
    }
    private var isIdleForWhatsNew: Bool {
        !isTimerActive && !isOnboardingVisible && !isPresentingModal && !isJoinFlowActive
    }

    private func dismissWhatsNew() {
        whatsNewController.isPresented = false
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .startResume:
            showSettings = false
                        mainMode = .sync
                        NotificationCenter.default.post(name: .TimerStart, object: nil)
        case .startCountdown:
            NotificationCenter.default.post(name: .quickActionCountdown, object: nil)
        case .openCueSheets:
            showSettings = false
            NotificationCenter.default.post(
                name: .whatsNewOpenCueSheets,
                object: nil,
                userInfo: ["createBlank": false]
            )
        case .joinRoom:
            showSettings = false
            pendingJoinFromWhatsNew = false
            if whatsNewController.isPresented {
                dismissWhatsNew()
                DispatchQueue.main.async {
                    showJoinSheetFromWhatsNew = true
                }
            } else {
                showJoinSheetFromWhatsNew = true
            }
        }
    }

    private func handleWhatsNewAction(_ action: WhatsNewAction) {
        switch action {
        case .openJoinQR:
            openJoinFromWhatsNew()
        case .openCueSheetsCreateBlank:
            openCueSheetsCreateBlankFromWhatsNew()
        case .openReleaseNotes:
            break
        }
    }

    private func openJoinFromWhatsNew() {
        pendingJoinFromWhatsNew = false
        dismissWhatsNew()
        DispatchQueue.main.async {
            showJoinSheetFromWhatsNew = true
        }
    }

    private func openCueSheetsCreateBlankFromWhatsNew() {
        guard !isPresentingModal else { return }
        pendingWhatsNewCueSheetCreate = true
        dismissWhatsNew()
        mainMode = .sync
        showSettings = false
    }

    private func presentWhatsNewManually() {
        guard let entry = currentWhatsNewEntry else { return }
        whatsNewEntry = entry
        whatsNewController.isPresented = true
    }

    private func evaluateWhatsNew(reason: String) {
        let currentVersion = WhatsNewController.currentVersionString
        let currentBuild = WhatsNewController.currentBuildString
        let entry = currentWhatsNewEntry
        whatsNewController.evaluatePresentationEligibility(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            isIdle: isIdleForWhatsNew,
            isOnboardingVisible: isOnboardingVisible,
            isPresentingModal: isPresentingModal,
            isJoinFlowActive: isJoinFlowActive,
            hasContent: entry != nil,
            reason: reason
        )
        if whatsNewController.isPresented, whatsNewEntry == nil {
            whatsNewEntry = entry
        }
    }

    private func applyJoinIfReady() {
        guard let request = joinRouter.pending else { return }
        guard !request.needsHostSelection else { return }
        guard handledJoinRequestId != request.requestId else { return }

        stashJoinLabelIfPossible(request)
        handledJoinRequestId = request.requestId
        let resolvedMethod: SyncSettings.SyncConnectionMethod
        switch request.mode {
        case "nearby", "bluetooth":
            resolvedMethod = .bluetooth
        case "wifi":
            resolvedMethod = .network
        default:
            resolvedMethod = .bluetooth
        }
        
        if syncSettings.isEnabled {
                    if syncSettings.role == .parent { syncSettings.stopParent() }
                    else { syncSettings.stopChild() }
                    syncSettings.isEnabled = false
                }

                syncSettings.role = .child
                syncSettings.connectionMethod = resolvedMethod
        syncSettings.applyJoinConstraints(
            allowed: Set(request.hostUUIDs),
            selected: request.selectedHostUUID
        )
        if resolvedMethod == .network {
            guard let ip = request.peerIP?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty,
                  let port = request.peerPort else {
                joinRouter.recordIncompleteWiFiJoin(request)
                return
            }
            syncSettings.peerIP = ip
            syncSettings.peerPort = String(port)
        }
        syncSettings.startChild()
        if resolvedMethod == .bluetooth, syncSettings.tapPairingAvailable {
                    syncSettings.beginTapPairing()
                }
                syncSettings.isEnabled = true

                showSettings = false
                mainMode = .sync
        joinRouter.markConsumed()
    }

    private func toggleSyncMode() {
        performToggleSyncMode(
            syncSettings: syncSettings,
            showSyncErrorAlert: $showSyncErrorAlert,
            syncErrorMessage: $syncErrorMessage
        )
    }

    private func persistChildRoomOnEstablished() {
        guard let hostUUID = syncSettings.joinSelectedHostUUID ?? syncSettings.lastJoinHostUUID else { return }
        let resolvedLabel = resolveAuthoritativeLabel(for: hostUUID)
        let transport: SyncSettings.SyncConnectionMethod = (syncSettings.connectionMethod == .bonjour) ? .network : syncSettings.connectionMethod
        let peerIP = syncSettings.peerIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let peerPort = syncSettings.peerPort.trimmingCharacters(in: .whitespacesAndNewlines)

        childRoomsStore.upsertConnected(
            hostUUID: hostUUID,
            authoritativeLabel: resolvedLabel.label,
            labelSource: resolvedLabel.source,
            labelRevision: syncSettings.lastJoinLabelRevision,
            preferredTransport: transport,
            peerIP: peerIP.isEmpty ? nil : peerIP,
            peerPort: peerPort.isEmpty ? nil : peerPort
        )
        syncSettings.clearJoinLabelCandidate()
    }

    private func resolveAuthoritativeLabel(for hostUUID: UUID) -> (label: String?, source: ChildSavedRoom.LabelSource) {
        if let candidate = normalizedLabel(syncSettings.lastJoinLabelCandidate), !candidate.isEmpty {
            return (candidate, .joinLink)
        }
        if syncSettings.lastBonjourHostUUID == hostUUID,
           let bonjourLabel = normalizedLabel(syncSettings.lastBonjourRoomLabel),
           !bonjourLabel.isEmpty {
            return (bonjourLabel, .bonjour)
        }
        if let deviceName = normalizedLabel(syncSettings.lastJoinDeviceNameCandidate), !deviceName.isEmpty {
            return (deviceName, .legacy)
        }
        return (nil, .unknown)
    }

    private func normalizedLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let trimmed = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stashJoinLabelIfPossible(_ request: JoinRequestV1) {
        guard let hostUUID = request.selectedHostUUID ?? (request.hostUUIDs.count == 1 ? request.hostUUIDs.first : nil) else {
            #if DEBUG
            print("[ContentView] stash join: deferred (needs host selection) requestId=\(request.requestId)")
            #endif
            return
        }
        let label = joinRoomLabelCandidate(for: request, hostUUID: hostUUID)
        let deviceName = joinDeviceNameCandidate(for: request, hostUUID: hostUUID)
        syncSettings.stashJoinLabelCandidate(
            hostUUID: hostUUID,
            roomLabel: label,
            deviceName: deviceName,
            labelRevision: nil
        )
        #if DEBUG
        print("[ContentView] stash join: hostUUID=\(hostUUID) peer=\(request.peerIP ?? "nil"):\(request.peerPort.map { String($0) } ?? "nil") label='\(label ?? "nil")'")
        #endif
    }

    private func joinRoomLabelCandidate(for request: JoinRequestV1, hostUUID: UUID) -> String? {
        let label = request.roomLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if label?.isEmpty == false {
            return label
        }
        return nil
    }

    private func joinDeviceNameCandidate(for request: JoinRequestV1, hostUUID: UUID) -> String? {
        if let selected = request.selectedHostUUID,
           let index = request.hostUUIDs.firstIndex(of: selected),
           request.deviceNames.indices.contains(index) {
            let name = request.deviceNames[index]
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        }
        if let deviceName = request.deviceNames.first, !deviceName.isEmpty {
            return deviceName
        }
        return nil
    }

    private func transportForJoin(_ mode: String) -> SyncSettings.SyncConnectionMethod {
        switch mode {
        case "wifi":
            return .network
        case "nearby", "bluetooth":
            return .bluetooth
        default:
            return .bluetooth
        }
    }
}

private struct JoinHostPickerSheet: View {
    let pending: JoinRequestV1?
    let onSelect: (UUID) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(hosts.indices, id: \.self) { index in
                    let host = hosts[index]
                    Button {
                        onSelect(host.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(host.name)
                            Text(host.suffix)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(pending?.roomLabel ?? "Select Host")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var hosts: [(id: UUID, name: String, suffix: String)] {
        guard let pending else { return [] }
        return pending.hostUUIDs.enumerated().map { index, uuid in
            let name = pending.deviceNames.indices.contains(index) ? pending.deviceNames[index] : "Host \(index + 1)"
            let suffix = "…\(uuid.uuidString.suffix(4))"
            return (id: uuid, name: name, suffix: suffix)
        }
    }
}
// Persistent badge state for "X loaded" shown inside TimerCard
@MainActor
final class CueBadgeState: ObservableObject {
    @Published var loadedCueSheetID: UUID? = nil
    @Published var broadcast: Bool = false
    @Published private var fallbackLabel: String? = nil
    private var cancellables = Set<AnyCancellable>()

    init() {
        CueLibraryStore.shared.$index
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var label: String? {
        if let sheetID = loadedCueSheetID,
           let label = CueLibraryStore.shared.badgeLabel(for: sheetID) {
            return label
        }
        return fallbackLabel
    }

    func setLoaded(sheetID: UUID, broadcast: Bool) {
        loadedCueSheetID = sheetID
        fallbackLabel = nil
        self.broadcast = broadcast
    }

    func setFallbackLabel(_ label: String, broadcast: Bool) {
        loadedCueSheetID = nil
        fallbackLabel = label
        self.broadcast = broadcast
    }

    func clear() {
        loadedCueSheetID = nil
        fallbackLabel = nil
        broadcast = false
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
    @UIApplicationDelegateAdaptor(SyncTimerMenuDelegate.self) private var menuDelegate
    // hook up the UIKit delegate
    
    // your own state‐objects…
    @StateObject private var appSettings  = AppSettings()
    @StateObject private var clockSync = ClockSyncService()
    @StateObject private var syncSettings = SyncSettings()
    @StateObject private var joinRouter = JoinRouter()
    @StateObject private var whatsNewController = WhatsNewController()
    @AppStorage("settingsPage") private var settingsPage = 0
    @State private var editingTarget: EditableField? = nil
    @State private var inputText       = ""
    @State private var isEnteringField = false
    // Monotonic tick anchor so the stop sub-timer decrements with real dt
    @State private var lastTickUptime: Double? = nil
    @StateObject private var cueBadge = CueBadgeState()
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
        registerRoboto()
        
#if canImport(WatchConnectivity)
if WCSession.isSupported() {
    let session = WCSession.default
    if session.delegate == nil {
        session.delegate = ConnectivityManager.shared
    }
    if session.activationState != .activated {
        session.activate()
    }
    print("[WC] WCSession.activate() called, state = \(session.activationState.rawValue)")
} else {
    print("[WC] WCSession not supported on this device.")
}
#endif

        
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
        
        // ──────────────────────────────────────────────────────────────
                // Main adaptive window (your current app window)
                // ──────────────────────────────────────────────────────────────
                WindowGroup {
                    // wrap the if/else in a Group so modifiers apply to the whole thing
                    Group {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                                            ContentView().ignoresSafeArea(.all)   // <- full-bleed on iPad
                                        } else {
                                            ContentView()
                                        }


                    }
                    .tint(Color("AccentColor"))

                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
                                        // Hand the shared Kalman instance to SyncSettings once
                    .onAppear {
                        syncSettings.clockSyncService = clockSync
                        AppActions.shared.connect(
                            appSettings: appSettings,
                            sync: syncSettings,
                            start: { NotificationCenter.default.post(name: .init("TimerStart"), object: nil) },
                            pause: { NotificationCenter.default.post(name: .init("TimerPause"), object: nil) },
                            reset: { NotificationCenter.default.post(name: .init("TimerReset"), object: nil) }
                        )
                        UIMenuSystem.main.setNeedsRebuild()   // 👈 ensure first draw uses your menus
                    }
                    .onChange(of: appSettings.showHours) { _ in UIMenuSystem.main.setNeedsRebuild() }
                    .onChange(of: appSettings.leftPanePaginateOnLargePads) { _ in UIMenuSystem.main.setNeedsRebuild() }
                    .onChange(of: appSettings.countdownResetMode) { _ in UIMenuSystem.main.setNeedsRebuild() }
                    .onChange(of: appSettings.resetConfirmationMode) { _ in UIMenuSystem.main.setNeedsRebuild() }
                    .onChange(of: appSettings.stopConfirmationMode) { _ in UIMenuSystem.main.setNeedsRebuild() }
                    .onChange(of: syncSettings.role) { _ in UIMenuSystem.main.setNeedsRebuild() }
                    .onChange(of: syncSettings.connectionMethod) { _ in UIMenuSystem.main.setNeedsRebuild() }
                    .onChange(of: syncSettings.isEnabled) { _ in UIMenuSystem.main.setNeedsRebuild() }

                    .environmentObject(appSettings)
                    .environmentObject(syncSettings)
                    .environmentObject(clockSync)
                    .environmentObject(cueBadge)
                    .environmentObject(joinRouter)
                    .environmentObject(whatsNewController)
                    .preferredColorScheme(appSettings.appTheme == .dark ? .dark : .light)
                    .dynamicTypeSize(.small ... .large)
            // “Open in SyncTimer” from Files/Share Sheet (XML only)
                    .onOpenURL { url in
                                    switch parseChildJoinLink(url: url) {
                                    case .success(.join(let request)):
                                        joinRouter.ingestParsed(request)
                                        return
                                    case .success(.legacy(let request)):
                                        syncSettings.pendingHostJoinRequest = request
                                        return
                                    case .failure(.joinError(let error)):
                                        joinRouter.handleParseFailure(error)
                                        return
                                    default:
                                        break
                                    }
                                    handleOpenURL(url)
                                }
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        guard let url = activity.webpageURL else { return }
                        switch parseChildJoinLink(url: url) {
                        case .success(.join(let request)):
                            joinRouter.ingestParsed(request)
                        case .success(.legacy(let request)):
                            syncSettings.pendingHostJoinRequest = request
                        case .failure(.joinError(let error)):
                            joinRouter.handleParseFailure(error)
                        default:
                            break
                        }
                    }

                }
#if targetEnvironment(macCatalyst)
                .defaultSize(width: 1380, height: 1050)
#endif
        
      
       

    
}
    // MARK: - Commands
    private struct MiniWindowCommands: Commands {
        @Environment(\.openWindow) private var openWindow
        var body: some Commands {
            CommandMenu("Window") {
                Button("Open Mini Timer") {
                    openWindow(id: "mini")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
// MARK: - Open-in handler
private extension SyncTimerApp {
    func handleOpenURL(_ url: URL) {
        // Only accept local .xml files
        guard url.isFileURL,
              url.pathExtension.lowercased() == "xml" else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            print("↪️ Ignored non-XML or non-file URL: \(url)")
            return
        }
        do {
            // Import into on-device library (root). Folders/tags can be assigned later in the sheet.
            _ = try CueLibraryStore.shared.importXML(from: url, intoFolderID: nil)  // nil = root
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            print("✅ Imported cue XML: \(url.lastPathComponent)")
            // Optional: notify UI to surface the Library / “Imported” toast
            NotificationCenter.default.post(name: .didImportCueSheet, object: nil)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            print("🛑 Failed to import cue XML: \(error.localizedDescription)")
        }
    }
}
