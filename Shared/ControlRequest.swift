//
//  ControlRequest.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation

public struct ControlRequest: Codable, Equatable {
    public enum Command: String, Codable {
        case start
        case stop
        case reset
        case requestSnapshot
        case requestAsset
        case unknown

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = (try? container.decode(String.self)) ?? ""
            self = Command(rawValue: raw) ?? .unknown
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
    public let command: Command
    public let origin : String   // "watchOS"
    public let ts     : TimeInterval
    public let assetID: UUID?

    public init(_ command: Command,
                origin: String = "watchOS",
                ts: TimeInterval = Date().timeIntervalSince1970,
                assetID: UUID? = nil) {
        self.command = command
        self.origin = origin
        self.ts = ts
        self.assetID = assetID
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

public struct WatchAck: Codable, Equatable {
    public let stateSeq: UInt64?
    public let displayID: UInt64?
    public let lastEventIDSeen: UInt64?
    public let assetIDsCachedDelta: [UUID]?
    public let ts: TimeInterval

    public init(stateSeq: UInt64?,
                displayID: UInt64?,
                lastEventIDSeen: UInt64?,
                assetIDsCachedDelta: [UUID]? = nil,
                ts: TimeInterval = Date().timeIntervalSince1970) {
        self.stateSeq = stateSeq
        self.displayID = displayID
        self.lastEventIDSeen = lastEventIDSeen
        self.assetIDsCachedDelta = assetIDsCachedDelta
        self.ts = ts
    }
}
