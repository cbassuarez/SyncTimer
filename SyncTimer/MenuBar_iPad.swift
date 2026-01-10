//
//  MenuBar_iPad.swift
//  SyncTimer
//
//  Created by Sebastian Suarez-Solis on 9/29/25.
//

import Foundation
import SwiftUI
import UIKit
import Network

// MARK: - Central action layer (no business logic duplication)
@MainActor
final class AppActions: ObservableObject {
    static let shared = AppActions()

    // Injected refs
    weak var appSettings: AppSettings?
    weak var sync: SyncSettings?

    // Timer hooks
    var startTimer: (() -> Void)?
    var pauseTimer: (() -> Void)?
    var resetTimer:  (() -> Void)?

    // Simple state mirror used by the menu to label Start/Pause
    @Published var isTimerRunning: Bool = false

    func connect(appSettings: AppSettings,
                 sync: SyncSettings,
                 start: (() -> Void)? = nil,
                 pause: (() -> Void)? = nil,
                 reset: (() -> Void)? = nil) {
        self.appSettings = appSettings
        self.sync = sync
        self.startTimer = start
        self.pauseTimer = pause
        self.resetTimer = reset
    }

    // --- Timer actions actually do things ---
    func startTimerAction() {
            startTimer?()
            NotificationCenter.default.post(name: .init("TimerStart"), object: nil)
            isTimerRunning = true
            UIMenuSystem.main.setNeedsRebuild()
        }
    func pauseTimerAction() {
            pauseTimer?()
            NotificationCenter.default.post(name: .init("TimerPause"), object: nil)
            isTimerRunning = false
            UIMenuSystem.main.setNeedsRebuild()
        }
    func resetTimerAction() {
                    resetTimer?()
                    NotificationCenter.default.post(name: .init("TimerReset"), object: nil)
                    // commonly reset -> not running:
                    isTimerRunning = false
                    UIMenuSystem.main.setNeedsRebuild()
                }

    // ---- Devices (Sync) ----
    func togglePaginationLargePadOnly() {
        guard let s = appSettings else { return }
        s.leftPanePaginateOnLargePads.toggle()
    }
    func setRole(_ role: SyncSettings.Role) { sync?.role = role }

    enum Connection { case wifi, nearby }
    func setConnection(_ c: Connection) {
        switch c {
        case .wifi:   sync?.connectionMethod = .network
        case .nearby: sync?.connectionMethod = .bluetooth
        }
    }

    func startStopSync() {
        guard let sync else { return }
        if sync.isEnabled {
            if sync.role == .parent { sync.stopParent() } else { sync.stopChild() }
            if sync.connectionMethod == .bonjour {
                sync.bonjourManager.stopAdvertising()
                sync.bonjourManager.stopBrowsing()
            }
            sync.isEnabled = false
        } else {
            switch sync.connectionMethod {
            case .network:
                if sync.role == .parent { sync.startParent() } else { sync.startChild() }
            case .bluetooth:
                if sync.role == .parent { sync.startParent() } else { sync.startChild() }
                if sync.tapPairingAvailable {
                    sync.beginTapPairing()
                } else {
                    sync.tapStateText = "Not available on Mac"
                }
            case .bonjour:
                break // you’re not using Bonjour in the UI
            }
            sync.isEnabled = true
        }
    }

    // ---- Network dropdown (Reveal IP, Generate Port) ----
    func revealMyIPToPasteboard() {
        guard let ip = Self.getLocalIPAddress() else { return }
        UIPasteboard.general.string = ip
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func generateEphemeralPort() {
        let p = UInt16.random(in: 49153...65534)
        sync?.listenPort = String(p)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // ---- View ----
    func toggleAlwaysShowHours() {
        guard let s = appSettings else { return }
        s.showHours.toggle()
    }
    func toggleLeftPanePagination() {
        guard let s = appSettings else { return }
        s.leftPanePaginateOnLargePads.toggle()
    }

    // ---- Helpers ----
    private static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(p.pointee.ifa_flags)
            let addr  = p.pointee.ifa_addr.pointee
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
               addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(p.pointee.ifa_addr, socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if ip != "127.0.0.1" { address = ip; break }
                }
            }
        }
        return address
    }
}

// MARK: - Hardware helpers (mirror what you already use)
enum Hardware {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var isLargePad129Family: Bool {
        guard isPad else { return false }
        let maxNative = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
        return maxNative >= 2732 // 12.9"/13"
    }
}

// MARK: - Menu Delegate (iPad menu bar)
final class SyncTimerMenuDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        registerQuickActions()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        registerQuickActions()
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(handleQuickAction(shortcutItem))
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(handleQuickAction(shortcutItem))
    }

    private func registerQuickActions() {
#if targetEnvironment(macCatalyst)
        return
#else
        let items: [UIApplicationShortcutItem] = [
            UIApplicationShortcutItem(
                type: QuickActionType.startResume.shortcutType,
                localizedTitle: "Start / Resume",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "play.fill")
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.countdown30.shortcutType,
                localizedTitle: "Start Countdown",
                localizedSubtitle: "0:30",
                icon: UIApplicationShortcutIcon(systemImageName: "timer")
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.countdown60.shortcutType,
                localizedTitle: "Start Countdown",
                localizedSubtitle: "1:00",
                icon: UIApplicationShortcutIcon(systemImageName: "timer")
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.countdown300.shortcutType,
                localizedTitle: "Start Countdown",
                localizedSubtitle: "5:00",
                icon: UIApplicationShortcutIcon(systemImageName: "timer")
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.openCueSheets.shortcutType,
                localizedTitle: "Open Cue Sheets",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "music.note.list")
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.openCurrentCueSheet.shortcutType,
                localizedTitle: "Open Current Cue Sheet",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "doc.text.magnifyingglass")
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.openJoinRoom.shortcutType,
                localizedTitle: "Connect / Join Room",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "qrcode")
            )
        ]
        UIApplication.shared.shortcutItems = items
#endif
    }

    private func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        guard let action = QuickActionType.fromShortcutType(shortcutItem.type) else { return false }
        let defaults = UserDefaults.standard
        defaults.set(action.rawValue, forKey: QuickActionStorage.typeKey)
        defaults.set(0, forKey: QuickActionStorage.payloadSecondsKey)
        defaults.set(false, forKey: QuickActionStorage.openJoinLargeKey)

        switch action {
        case .countdown30:
            defaults.set(30, forKey: QuickActionStorage.payloadSecondsKey)
        case .countdown60:
            defaults.set(60, forKey: QuickActionStorage.payloadSecondsKey)
        case .countdown300:
            defaults.set(300, forKey: QuickActionStorage.payloadSecondsKey)
        case .openJoinRoom:
            defaults.set(true, forKey: QuickActionStorage.openJoinLargeKey)
        case .startResume, .openCueSheets, .openCurrentCueSheet:
            break
        }
        return true
#endif
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        guard Hardware.isPad, builder.system == .main else { return }

        // Keep stock menus except the ones we explicitly replace
        builder.remove(menu: .format)

        // ===================== View =====================
        let view_alwaysHours = UIAction(
            title: "Always Show Hours",
            state: (AppActions.shared.appSettings?.showHours ?? false) ? .on : .off
        ) { _ in AppActions.shared.toggleAlwaysShowHours() }

        let view_paginate = UIAction(
            title: "Paginate Devices / Notes",
            attributes: Hardware.isLargePad129Family ? [] : [.disabled],
            state: (AppActions.shared.appSettings?.leftPanePaginateOnLargePads ?? false) ? .on : .off
        ) { _ in AppActions.shared.toggleLeftPanePagination() }

        let viewMenu = UIMenu(
            title: "View",
            image: nil,
            identifier: UIMenu.Identifier("view.menu"),
            options: .displayInline,
            children: [view_alwaysHours, view_paginate]
        )

        // ===================== Devices =====================
        // Role submenu
        let roleParent = UIAction(
            title: "Parent",
            state: (AppActions.shared.sync?.role == .parent) ? .on : .off
        ) { _ in AppActions.shared.setRole(.parent) }

        let roleChild = UIAction(
            title: "Child",
            state: (AppActions.shared.sync?.role == .child) ? .on : .off
        ) { _ in AppActions.shared.setRole(.child) }

        let roleMenu = UIMenu(title: "Role", options: .displayInline, children: [roleParent, roleChild])

        // Connection submenu (Wi-Fi / Nearby)
        let wifi = UIAction(
            title: "Wi-Fi",
            state: (AppActions.shared.sync?.connectionMethod == .network) ? .on : .off
        ) { _ in AppActions.shared.setConnection(.wifi) }

        let nearby = UIAction(
            title: "Nearby",
            state: (AppActions.shared.sync?.connectionMethod == .bluetooth) ? .on : .off
        ) { _ in AppActions.shared.setConnection(.nearby) }

        let connectionMenu = UIMenu(title: "Connection", options: .displayInline, children: [wifi, nearby])

        // Start/Stop Sync
        let startStop = UIAction(
            title: (AppActions.shared.sync?.isEnabled ?? false) ? "Stop Sync" : "Start Sync"
        ) { _ in AppActions.shared.startStopSync() }

        // Network dropdown
        let revealIP = UIAction(title: "Copy My IP") { _ in AppActions.shared.revealMyIPToPasteboard() }
        let genPort  = UIAction(title: "Generate Port") { _ in AppActions.shared.generateEphemeralPort() }
        let networkDropdown = UIMenu(title: "Network", options: .displayInline, children: [revealIP, genPort])

        let devicesMenu = UIMenu(
            title: "Devices",
            image: nil,
            identifier: UIMenu.Identifier("devices.menu"),
            options: [],
            children: [startStop, roleMenu, connectionMenu, networkDropdown]
        )

        // ===================== Timer =====================
        // Single contextual Start/Pause row + separate Reset
        let startOrPause = UIAction(
            title: AppActions.shared.isTimerRunning ? "Pause" : "Start",
            identifier: UIAction.Identifier("timer.startpause")
        ) { _ in
            if AppActions.shared.isTimerRunning {
                AppActions.shared.pauseTimerAction()
            } else {
                AppActions.shared.startTimerAction()
            }
        }

        let reset = UIAction(
            title: "Reset",
            identifier: UIAction.Identifier("timer.reset")
        ) { _ in AppActions.shared.resetTimerAction() }

        let timerControls = UIMenu(
            title: "Controls",
            options: .displayInline,
            children: [startOrPause, reset]
        )

        // Reset Lock (Confirm) — single selection, mirrors Settings
        let resetLockChoices: [UIAction] = ResetConfirmationMode.allCases.map { mode in
            UIAction(
                title: mode.rawValue,
                state: (AppActions.shared.appSettings?.resetConfirmationMode == mode) ? .on : .off
            ) { _ in
                AppActions.shared.appSettings?.resetConfirmationMode = mode
                UIMenuSystem.main.setNeedsRebuild()
            }
        }
        let resetLockMenu = UIMenu(
            title: "Reset Lock (Confirm)",
            options: [.singleSelection, .displayInline],
            children: resetLockChoices
        )

        // Stop Lock (Confirm) — single selection, mirrors Settings
        let stopLockChoices: [UIAction] = ResetConfirmationMode.allCases.map { mode in
            UIAction(
                title: mode.rawValue,
                state: (AppActions.shared.appSettings?.stopConfirmationMode == mode) ? .on : .off
            ) { _ in
                AppActions.shared.appSettings?.stopConfirmationMode = mode
                UIMenuSystem.main.setNeedsRebuild()
            }
        }
        let stopLockMenu = UIMenu(
            title: "Stop Lock (Confirm)",
            options: [.singleSelection, .displayInline],
            children: stopLockChoices
        )

        let timerMenu = UIMenu(
            title: "Timer",
            image: nil,
            identifier: UIMenu.Identifier("timer.menu"),
            options: [],
            children: [timerControls, resetLockMenu, stopLockMenu]
        )

        // ===== Insert menus =====
        builder.replaceChildren(ofMenu: .view) { _ in
                    [view_alwaysHours, view_paginate]
                }
        builder.insertSibling(devicesMenu,  afterMenu: .view)
        builder.insertSibling(timerMenu,   afterMenu: UIMenu.Identifier("devices.menu"))
    }

    // keep standard delegate hook
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        true
    }
}
 // MARK: - Timer notifications
 extension Notification.Name {
   static let TimerStart = Notification.Name("TimerStart")
   static let TimerPause = Notification.Name("TimerPause")
   static let TimerReset = Notification.Name("TimerReset")
 }
