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
    for span in payload.spans {
        guard span.length > 0 else { continue }
        let lower = max(0, span.location)
        let upper = min(payload.text.count, span.location + span.length)
        guard lower < upper else { continue }
        guard lower < upper, upper <= attributed.characters.count else { continue }
                let start = attributed.index(attributed.startIndex, offsetByCharacters: lower)
                let end = attributed.index(start, offsetByCharacters: upper - lower)
                guard start < end else { continue }
        let range = start..<end

        if span.styles.contains(.bold) {
            attributed[range].font = .body.bold()
        }
        if span.styles.contains(.italic) {
            attributed[range].font = .body.italic()
        }
        if span.styles.contains(.underline) {
            attributed[range].underlineStyle = .single
        }
        if span.styles.contains(.strikethrough) {
            attributed[range].strikethroughStyle = .single
        }
    }
    return attributed
}
