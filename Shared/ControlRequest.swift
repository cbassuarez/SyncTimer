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

    public init(_ command: Command,
                origin: String = "watchOS",
                ts: TimeInterval = Date().timeIntervalSince1970) {
        self.command = command
        self.origin = origin
        self.ts = ts
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
