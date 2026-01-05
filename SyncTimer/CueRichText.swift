//
//  CueRichText.swift
//  SyncTimer
//
//  Lightweight converter for cue message spans -> AttributedString.
//

import Foundation
import SwiftUI

func attributedText(from payload: CueSheet.MessagePayload) -> AttributedString {
    var attributed = AttributedString(payload.text)
    var base = AttributeContainer()
    base.font = .body.italic()
    attributed.mergeAttributes(base)

    for span in payload.spans {
        guard span.length > 0 else { continue }
        let lower = max(0, span.location)
        let upper = min(payload.text.count, span.location + span.length)
        guard lower < upper else { continue }
        guard upper <= attributed.characters.count else { continue }
        let start = attributed.index(attributed.startIndex, offsetByCharacters: lower)
        let end = attributed.index(start, offsetByCharacters: upper - lower)
        guard start < end else { continue }
        let range = start..<end

        var font: Font = .body.italic()
        if span.styles.contains(.bold) { font = font.weight(.bold) }
        if span.styles.contains(.italic) { font = font.italic() }
        attributed[range].font = font

        if span.styles.contains(.underline) {
            attributed[range].underlineStyle = .single
        }
        if span.styles.contains(.strikethrough) {
            attributed[range].strikethroughStyle = .single
        }
    }

    let text = payload.text
    var lineStart = text.startIndex
    while lineStart <= text.endIndex {
        let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
        let length = text.distance(from: lineStart, to: lineEnd)
        let startOffset = text.distance(from: text.startIndex, to: lineStart)
        if length >= 0, startOffset <= attributed.characters.count {
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
            if length > 0, let attrEnd = attributed.index(attrStart, offsetByCharacters: length, limitedBy: attributed.endIndex) {
                let range = attrStart..<attrEnd
                let line = String(text[lineStart..<lineEnd])
                let leadingSpaces = line.prefix { $0 == " " }.count
                let body = line.dropFirst(leadingSpaces)
                var paragraph = ParagraphStyle()
                paragraph.lineSpacing = 4
                paragraph.paragraphSpacing = 4
                if body.hasPrefix("- ") || body.hasPrefix("• ") {
                    let prefixLen = min(length, leadingSpaces + 2)
                    let replaceEnd = attributed.index(attrStart, offsetByCharacters: prefixLen)
                    let bulletPrefix = String(repeating: " ", count: leadingSpaces) + "• "
                    attributed.replaceSubrange(attrStart..<replaceEnd, with: AttributedString(bulletPrefix))
                    paragraph.firstLineHeadIndent = CGFloat(leadingSpaces) * 6
                    paragraph.headIndent = paragraph.firstLineHeadIndent + 18
                } else if leadingSpaces > 0 {
                    paragraph.firstLineHeadIndent = CGFloat(leadingSpaces) * 6
                    paragraph.headIndent = paragraph.firstLineHeadIndent
                }
                attributed[range].paragraphStyle = paragraph
            }
        }
        if lineEnd == text.endIndex { break }
        lineStart = text.index(after: lineEnd)
    }

    return attributed
}
