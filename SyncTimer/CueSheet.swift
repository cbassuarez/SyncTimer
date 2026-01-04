//
//  CueSheet.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation

public struct CueSheet: Identifiable, Equatable, Hashable {
    public struct TempoChange: Equatable, Hashable { public var atBar: Int; public var bpm: Double }
    public struct MeterChange: Equatable, Hashable { public var atBar: Int; public var num: Int; public var den: Int }
    public struct Event: Identifiable, Equatable, Hashable {
        public enum Kind: String { case stop, cue, restart, flashColor }
        public var id = UUID()
        public var kind: Kind
        public var at: TimeInterval            // absolute seconds from 0.0 (authoritative)
        public var holdSeconds: TimeInterval?  // for stop-hold semantics
        public var label: String?              // optional label
        // NOTE: no colorToken/tolerance per your spec
    }

    public var id = UUID()
    public var version = 1
    public var title: String
    public var notes: String?
    public var timeSigNum: Int = 4
    public var timeSigDen: Int = 4
    public var bpm: Double = 120
    public var tempoChanges: [TempoChange] = []
    public var meterChanges: [MeterChange] = []
    public var events: [Event] = []

    // Library-side (not serialized into XML)
    public var tags: [String] = []
    public var fileName: String = ""          // e.g., "My Piece.xml"
    public var lastOpened: Date? = nil
    public var created: Date = Date()
    public var modified: Date = Date()

    // lightweight content hash for versioning/broadcast
    public var contentHash: String {
        let base = "\(version)|\(title)|\(bpm)|\(timeSigNum)/\(timeSigDen)|\(tempoChanges)|\(meterChanges)|\(events)"
        return String(base.hashValue)
    }
}
