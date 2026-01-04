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
        public enum Kind: String { case stop, cue, restart, flashColor, message, image }
        public enum Payload: Equatable, Hashable {
            case message(MessagePayload)
            case image(ImagePayload)
        }
        public var id = UUID()
        public var kind: Kind
        public var at: TimeInterval            // absolute seconds from 0.0 (authoritative)
        public var holdSeconds: TimeInterval?  // for stop-hold semantics
        public var label: String?              // optional label
        public var payload: Payload?
        public init(id: UUID = UUID(), kind: Kind, at: TimeInterval, holdSeconds: TimeInterval? = nil, label: String? = nil, payload: Payload? = nil) {
            self.id = id
            self.kind = kind
            self.at = at
            self.holdSeconds = holdSeconds
            self.label = label
            self.payload = payload
        }
        // NOTE: no colorToken/tolerance per your spec
    }

    public struct MessagePayload: Equatable, Hashable, Codable {
        public var text: String
        public var spans: [Span]
        public init(text: String, spans: [Span] = []) {
            self.text = text
            self.spans = spans
        }
    }

    public struct ImagePayload: Equatable, Hashable, Codable {
        public enum ContentMode: String, Codable { case fit, fill }
        public var assetID: UUID
        public var contentMode: ContentMode
        public var caption: MessagePayload?
        public init(assetID: UUID, contentMode: ContentMode = .fit, caption: MessagePayload? = nil) {
            self.assetID = assetID
            self.contentMode = contentMode
            self.caption = caption
        }
    }

    public struct Span: Equatable, Hashable, Codable {
        public var location: Int
        public var length: Int
        public var styles: StyleSet
        public init(location: Int, length: Int, styles: StyleSet) {
            self.location = location
            self.length = length
            self.styles = styles
        }
    }

    public struct StyleSet: OptionSet, Codable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let bold = StyleSet(rawValue: 1 << 0)
        public static let italic = StyleSet(rawValue: 1 << 1)
        public static let underline = StyleSet(rawValue: 1 << 2)
        public static let strikethrough = StyleSet(rawValue: 1 << 3)
    }

    public func normalized() -> CueSheet {
        var copy = self
        copy.events = copy.events.map { ev in
            var e = ev
            if case .message(let msg)? = e.payload {
                let trimmed = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                e.payload = .message(.init(text: trimmed, spans: msg.spans))
                if e.label == nil { e.label = trimmed }
            }
            if case .image(let img)? = e.payload {
                if e.label == nil {
                    e.label = img.caption?.text.isEmpty == false ? img.caption?.text : "Image"
                }
            }
            return e
        }
        return copy
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
