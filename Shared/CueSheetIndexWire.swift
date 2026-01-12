//
//  CueSheetIndexWire.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation

public struct CueSheetSummaryWire: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var eventCount: Int
    public var modifiedAt: TimeInterval?

    public init(id: UUID, title: String, eventCount: Int, modifiedAt: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.eventCount = eventCount
        self.modifiedAt = modifiedAt
    }
}

public struct CueSheetIndexWire: Codable, Equatable {
    public var items: [CueSheetSummaryWire]

    public init(items: [CueSheetSummaryWire]) {
        self.items = items
    }
}
