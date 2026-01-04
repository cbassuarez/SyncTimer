//
//  CueXML.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation
enum CueXML {
    // MARK: Write
    static func write(_ sheet: CueSheet) -> Data {
        var xml = ""
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }
        xml += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<cueSheet version=\"\(sheet.version)\">\n"
        xml += "  <meta>\n"
        xml += "    <title>\(esc(sheet.title))</title>\n"
        if let n = sheet.notes { xml += "    <notes>\(esc(n))</notes>\n" }
        xml += "    <timeSignature num=\"\(sheet.timeSigNum)\" den=\"\(sheet.timeSigDen)\"/>\n"
        xml += "    <tempo bpm=\"\(sheet.bpm)\"/>\n"
        if !sheet.tempoChanges.isEmpty {
            for t in sheet.tempoChanges {
                xml += "    <tempoChange atBar=\"\(t.atBar)\" bpm=\"\(t.bpm)\"/>\n"
            }
        }
        if !sheet.meterChanges.isEmpty {
            for m in sheet.meterChanges {
                xml += "    <meterChange atBar=\"\(m.atBar)\" num=\"\(m.num)\" den=\"\(m.den)\"/>\n"
            }
        }
        xml += "  </meta>\n"
        xml += "  <events>\n"
        for e in sheet.events {
            let hold = (e.holdSeconds != nil) ? " holdSeconds=\"\(e.holdSeconds!)\"" : ""
            let label = (e.label != nil) ? " label=\"\(esc(e.label!))\"" : ""
            xml += "    <event type=\"\(e.kind.rawValue)\" at=\"\(e.at)\"\(hold)\(label)/>\n"
        }
        xml += "  </events>\n"
        xml += "</cueSheet>\n"
        return xml.data(using: .utf8) ?? Data()
    }

    // MARK: Read (tolerant, “open anyway” option lives in caller)
    static func read(_ data: Data) throws -> CueSheet {
        let p = XMLParser(data: data)
        let delegate = CueXMLParserDelegate()
        p.delegate = delegate
        guard p.parse() else {
            throw p.parserError ?? NSError(domain: "CueXML", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid XML"])
        }
        return delegate.build()
    }

    private final class CueXMLParserDelegate: NSObject, XMLParserDelegate {
        var title = "Untitled"
        var notes: String?
        var num = 4, den = 4
        var bpm: Double = 120
        var tempoChanges: [CueSheet.TempoChange] = []
        var meterChanges: [CueSheet.MeterChange] = []
        var events: [CueSheet.Event] = []

        private var currentElement: String?
        private var textBuffer = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
            currentElement = name; textBuffer = ""
            switch name {
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
                if let t = attributes["type"], let at = attributes["at"] {
                    let kind = CueSheet.Event.Kind(rawValue: t) ?? .cue
                    var e = CueSheet.Event(kind: kind, at: Double(at) ?? 0, holdSeconds: nil, label: nil)
                    if let h = attributes["holdSeconds"] { e.holdSeconds = Double(h) }
                    if let l = attributes["label"] { e.label = l }
                    events.append(e)
                }
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { textBuffer += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch name {
            case "title": title = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            case "notes": notes = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            default: break
            }
            currentElement = nil; textBuffer = ""
        }

        func build() -> CueSheet {
            return CueSheet(title: title,
                            notes: notes,
                            timeSigNum: num, timeSigDen: den, bpm: bpm,
                            tempoChanges: tempoChanges, meterChanges: meterChanges,
                            events: events)
        }
    }
}
