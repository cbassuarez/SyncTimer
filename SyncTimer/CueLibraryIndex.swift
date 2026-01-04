//
//  CueLibraryIndex.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation

struct CueLibraryIndex: Codable {
    struct Folder: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String
        var children: [Folder] = []
        var sheetIDs: [UUID] = [] // IDs of sheets living here
    }
    struct SheetMeta: Codable, Identifiable, Hashable {
        var id: UUID
        var fileName: String
        var title: String
        var tags: [String] = []
        var pinned: Bool = false
        var created: Date
        var modified: Date
        var lastOpened: Date?
    }

    var root: Folder = Folder(name: "Library")
    var sheets: [UUID: SheetMeta] = [:]
    var recents: [UUID] = []
}
