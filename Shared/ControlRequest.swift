//
//  ControlRequest.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation

public struct ControlRequest: Codable, Equatable {
    public enum Command: String, Codable { case start, stop, reset, requestSnapshot }
    public let command: Command
    public let origin : String   // "watchOS"
    public let ts     : TimeInterval
    public let rehydrateEventsOnReset: Bool?
    public let rehydrateCueSheetID: UUID?

    public init(_ command: Command,
                origin: String = "watchOS",
                ts: TimeInterval = Date().timeIntervalSince1970,
                rehydrateEventsOnReset: Bool? = nil,
                rehydrateCueSheetID: UUID? = nil) {
        self.command = command
        self.origin = origin
        self.ts = ts
        self.rehydrateEventsOnReset = rehydrateEventsOnReset
        self.rehydrateCueSheetID = rehydrateCueSheetID
    }
}

public struct SnapshotRequest: Codable, Equatable {
    public let origin: String
    public let ts: TimeInterval

    public init(origin: String = "watchOS", ts: TimeInterval = Date().timeIntervalSince1970) {
        self.origin = origin
        self.ts = ts
    }
}
