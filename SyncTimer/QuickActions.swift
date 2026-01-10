//
//  QuickActions.swift
//  SyncTimer
//

import Foundation

enum QuickActionType: String, CaseIterable {
    case startResume
    case countdown30
    case countdown60
    case countdown300
    case openCueSheets
    case openCurrentCueSheet
    case openJoinRoom

    static var typePrefix: String {
        if let bundleID = Bundle.main.bundleIdentifier {
            return "\(bundleID)."
        }
        return "synctimer."
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

enum QuickActionStorage {
    static let typeKey = "launch.quickAction.type"
    static let payloadSecondsKey = "launch.quickAction.payloadSeconds"
    static let openJoinLargeKey = "launch.quickAction.openJoinLarge"
    static let pendingOpenJoinSheetKey = "launch.pendingOpenJoinSheet"
    static let pendingOpenJoinLargeKey = "launch.pendingOpenJoinLarge"
    static let countdownSecondsUserInfoKey = "seconds"
}
