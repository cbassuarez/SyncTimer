//
//  Notifications.swift
//  SyncTimer
//
//  Created by seb on 9/14/25.
//

import Foundation

extension Notification.Name {
    /// Fired when a cue sheet is selected/applied from CueSheetsSheet.
    static let didLoadCueSheet = Notification.Name("CueSheetLoaded")
    static let quickActionStartResume = Notification.Name("quickActionStartResume")
    static let quickActionStartCountdown = Notification.Name("quickActionStartCountdown")
    static let quickActionOpenCueSheets = Notification.Name("quickActionOpenCueSheets")
    static let quickActionOpenCurrentCueSheet = Notification.Name("quickActionOpenCurrentCueSheet")
}
