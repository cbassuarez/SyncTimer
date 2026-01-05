//
//  CueXML.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation
import CryptoKit
enum CueXML {
    struct AssetBlob: Equatable {
        var id: UUID
        var mime: String
        var sha256: String
        var data: Data
    }
    // MARK: Write
    static func write(_ sheet: CueSheet, assets: [AssetBlob] = []) -> Data {
        let normalized = sheet.normalized()
        let hasOverlayContent = normalized.events.contains(where: { $0.kind == .message || $0.kind == .image })
        let hasRehearsalMarks = normalized.events.contains(where: { ($0.rehearsalMarkMode ?? .off) != .off })
        let needsV2 = hasOverlayContent || hasRehearsalMarks || !assets.isEmpty
        let version = max(normalized.version, needsV2 ? 2 : normalized.version)
        var xml = ""
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }
        xml += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<cueSheet version=\"\(version)\">\n"
        xml += "  <meta>\n"
        xml += "    <title>\(esc(normalized.title))</title>\n"
        if let n = normalized.notes { xml += "    <notes>\(esc(n))</notes>\n" }
        xml += "    <timeSignature num=\"\(normalized.timeSigNum)\" den=\"\(normalized.timeSigDen)\"/>\n"
        xml += "    <tempo bpm=\"\(normalized.bpm)\"/>\n"
        if !normalized.tempoChanges.isEmpty {
            for t in normalized.tempoChanges {
                xml += "    <tempoChange atBar=\"\(t.atBar)\" bpm=\"\(t.bpm)\"/>\n"
            }
        }
        if !normalized.meterChanges.isEmpty {
            for m in normalized.meterChanges {
                xml += "    <meterChange atBar=\"\(m.atBar)\" num=\"\(m.num)\" den=\"\(m.den)\"/>\n"
            }
        }
        xml += "  </meta>\n"
        xml += "  <events>\n"
        for e in normalized.events {
            let hold = (e.holdSeconds != nil) ? " holdSeconds=\"\(e.holdSeconds!)\"" : ""
            let label = (e.label != nil) ? " label=\"\(esc(e.label!))\"" : ""
            var extra = ""
            switch e.kind {
            case .message:
                if case .message(let payload)? = e.payload, !payload.spans.isEmpty {
                    extra += " fmt=\"\(encodeSpans(payload.spans))\""
                }
            case .image:
                if case .image(let payload)? = e.payload {
                    extra += " assetID=\"\(payload.assetID.uuidString)\""
                    extra += " contentMode=\"\(payload.contentMode.rawValue)\""
                    if let caption = payload.caption, !caption.spans.isEmpty {
                        extra += " captionFmt=\"\(encodeSpans(caption.spans))\""
                    }
                }
            case .cue:
                if let mode = e.rehearsalMarkMode, mode != .off {
                    extra += " reh=\"\(mode.rawValue)\""
                }
            default: break
            }
            xml += "    <event type=\"\(e.kind.rawValue)\" at=\"\(e.at)\"\(hold)\(label)\(extra)/>\n"
        }
        xml += "  </events>\n"
        if version >= 2, !assets.isEmpty {
            xml += "  <assets>\n"
            for blob in assets {
                let dataB64 = blob.data.base64EncodedString()
                xml += "    <image id=\"\(blob.id.uuidString)\" mime=\"\(blob.mime)\" sha256=\"\(blob.sha256)\">\(dataB64)</image>\n"
            }
            xml += "  </assets>\n"
        }
        xml += "</cueSheet>\n"
        return xml.data(using: .utf8) ?? Data()
    }

    // MARK: Read (tolerant, “open anyway” option lives in caller)
    static func read(_ data: Data) throws -> CueSheet {
        return try readWithAssets(data).0
    }

    static func readWithAssets(_ data: Data) throws -> (CueSheet, [AssetBlob]) {
        let p = XMLParser(data: data)
        let delegate = CueXMLParserDelegate()
        p.delegate = delegate
        guard p.parse() else {
            throw p.parserError ?? NSError(domain: "CueXML", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid XML"])
        }
        return (delegate.build(), delegate.embeddedAssets)
    }

    private static func encodeSpans(_ spans: [CueSheet.Span]) -> String {
        let payload = spans.map { ["loc": $0.location, "len": $0.length, "sty": $0.styles.rawValue] }
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let b64 = data?.base64EncodedString(options: []) ?? ""
        return b64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func decodeSpans(_ encoded: String) -> [CueSheet.Span] {
        var padded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded),
              let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let loc = dict["loc"] as? Int, let len = dict["len"] as? Int, let sty = dict["sty"] as? Int else { return nil }
            return CueSheet.Span(location: loc, length: len, styles: CueSheet.StyleSet(rawValue: sty))
        }
    }

    private final class CueXMLParserDelegate: NSObject, XMLParserDelegate {
        var version = 1
        var title = "Untitled"
        var notes: String?
        var num = 4, den = 4
        var bpm: Double = 120
        var tempoChanges: [CueSheet.TempoChange] = []
        var meterChanges: [CueSheet.MeterChange] = []
        var events: [CueSheet.Event] = []
        var embeddedAssets: [AssetBlob] = []

        private var textBuffer = ""
        private var currentAsset: (UUID, String, String)?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
            textBuffer = ""
            switch name {
            case "cueSheet":
                if let v = attributes["version"], let iv = Int(v) { version = iv }
            case "timeSignature":
                if let n = attributes["num"], let d = attributes["den"] {
                    num = Int(n) ?? 4; den = Int(d) ?? 4
                }
            case "tempo":
                if let b = attributes["bpm"] { bpm = Double(b) ?? 120 }
            case "tempoChange":
                if let a = attributes["atBar"], let b = attributes["bpm"] {
                    tempoChanges.append(.init(atBar: Int(a) ?? 0, bpm: Double(b) ?? bpm))
                }
            case "meterChange":
                if let a = attributes["atBar"], let n = attributes["num"], let d = attributes["den"] {
                    meterChanges.append(.init(atBar: Int(a) ?? 0, num: Int(n) ?? num, den: Int(d) ?? den))
                }
            case "event":
                guard let t = attributes["type"], let at = attributes["at"] else { return }
                let kind = CueSheet.Event.Kind(rawValue: t) ?? .cue
                var e = CueSheet.Event(kind: kind, at: Double(at) ?? 0, holdSeconds: nil, label: nil, payload: nil)
                if let h = attributes["holdSeconds"] { e.holdSeconds = Double(h) }
                if let l = attributes["label"] { e.label = l }
                if let reh = attributes["reh"] ?? attributes["rehearsal"] {
                    e.rehearsalMarkMode = CueSheet.RehearsalMarkMode(rawValue: reh)
                }
                switch kind {
                case .message:
                    let spans = attributes["fmt"].map { CueXML.decodeSpans($0) } ?? []
                    let text = e.label ?? ""
                    e.payload = .message(.init(text: text, spans: spans))
                case .image:
                    if let idStr = attributes["assetID"], let uuid = UUID(uuidString: idStr) {
                        let mode = CueSheet.ImagePayload.ContentMode(rawValue: attributes["contentMode"] ?? "fit") ?? .fit
                        let captionSpans = attributes["captionFmt"].map { CueXML.decodeSpans($0) } ?? []
                        let captionText = e.label
                        let caption: CueSheet.MessagePayload? = captionText.map { CueSheet.MessagePayload(text: $0, spans: captionSpans) }
                        e.payload = .image(.init(assetID: uuid, contentMode: mode, caption: caption))
                    }
                default:
                    break
                }
                events.append(e)
            case "image":
                if let idStr = attributes["id"], let uuid = UUID(uuidString: idStr),
                   let mime = attributes["mime"], let sha = attributes["sha256"] {
                    currentAsset = (uuid, mime, sha)
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { textBuffer += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch name {
            case "title": title = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            case "notes": notes = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            case "image":
                if let meta = currentAsset {
                    let data = Data(base64Encoded: textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Data()
                    embeddedAssets.append(.init(id: meta.0, mime: meta.1, sha256: meta.2, data: data))
                }
                currentAsset = nil
            default:
                break
            }
            textBuffer = ""
        }

        func build() -> CueSheet {
            var sheet = CueSheet(title: title,
                                 notes: notes,
                                 timeSigNum: num, timeSigDen: den, bpm: bpm,
                                 tempoChanges: tempoChanges, meterChanges: meterChanges,
                                 events: events)
            sheet.version = version
            return sheet
        }
    }
}
