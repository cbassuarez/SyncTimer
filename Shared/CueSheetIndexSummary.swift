//
//  CueSheetIndexSummary.swift
//  SyncTimer
//
//  Created by Codex.
//

import Foundation

public struct CueSheetIndexSummary: Codable, Equatable {
    public struct Item: Codable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let cueCount: Int?
        public let modifiedAt: Double?

        public init(id: UUID, name: String, cueCount: Int?, modifiedAt: Double?) {
            self.id = id
            self.name = name
            self.cueCount = cueCount
            self.modifiedAt = modifiedAt
        }
    }

    public let items: [Item]
    public let seq: UInt64

    public init(items: [Item], seq: UInt64) {
        self.items = items
        self.seq = seq
    }
}
