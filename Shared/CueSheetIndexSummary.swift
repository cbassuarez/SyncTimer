//
//  CueSheetIndexSummary.swift
//  SyncTimer
//
//  Created by Codex.
//

import Foundation

public struct CueSheetIndexSummary: Codable, Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let cueCount: Int?
    public let modifiedAt: Date?

    public init(id: UUID, title: String, cueCount: Int?, modifiedAt: Date?) {
        self.id = id
        self.title = title
        self.cueCount = cueCount
        self.modifiedAt = modifiedAt
    }
}
