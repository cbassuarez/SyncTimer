//
//  QuickActions.swift
//  SyncTimer
//

import Foundation

enum QuickActionType: String {
    case startResume
    case countdown30
    case countdown60
    case countdown300
    case openCueSheets
    case openCurrentCueSheet
    case openJoinRoom

    static var typePrefix: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "SyncTimer"
        return "\(bundleID).qa."
    }

    var shortcutType: String {
        Self.typePrefix + rawValue
    }

    static func fromShortcutType(_ type: String) -> QuickActionType? {
        if type.hasPrefix(typePrefix) {
            return QuickActionType(rawValue: String(type.dropFirst(typePrefix.count)))
        }
        return QuickActionType(rawValue: type)
    }
}

enum QuickActionDefaults {
    static let typeKey = "launch.quickAction.type"
    static let secondsKey = "launch.quickAction.payloadSeconds"
    static let openJoinLargeKey = "launch.quickAction.openJoinLarge"
    static let pendingOpenJoinSheetKey = "launch.pendingOpenJoinSheet"
    static let countdownSecondsUserInfoKey = "seconds"
}

extension Notification.Name {
    static let quickActionStartResume = Notification.Name("quickAction.startResume")
    static let quickActionStartCountdown = Notification.Name("quickAction.startCountdown")
    static let quickActionOpenCueSheets = Notification.Name("quickAction.openCueSheets")
    static let quickActionOpenCurrentCueSheet = Notification.Name("quickAction.openCurrentCueSheet")
}
