import Foundation
import SwiftUI

@MainActor
/// Drives the display overlays (message/image) and rehearsal marks as events fire.
final class CueDisplayController: ObservableObject {
    struct DurationConfig {
        var base: TimeInterval
        var perChar: TimeInterval
        var max: TimeInterval

        static let `default` = DurationConfig(base: 5.0, perChar: 0.15, max: 12.0)
    }
    enum Slot: Equatable {
        case none
        case message(CueSheet.MessagePayload)
        case image(CueSheet.ImagePayload)
    }

    @Published private(set) var slot: Slot = .none
    @Published private(set) var image: CueSheet.ImagePayload?
    @Published private(set) var messagePayload: CueSheet.MessagePayload?
    @Published private(set) var rehearsalMarkText: String?
    @Published private(set) var settledRehearsalMarkText: String?
    @Published var isExpanded: Bool = false

    private let durationConfig: DurationConfig

    private enum EntryKind {
        case message(CueSheet.MessagePayload, TimeInterval?)
        case image(CueSheet.ImagePayload, TimeInterval?)
        case rehearsalMark(String, TimeInterval?)
    }

    private struct Entry {
        var at: TimeInterval
        var kind: EntryKind
    }

    private var timeline: [Entry] = []
    private var cursor: Int = 0
    private var messageClearWorkItem: DispatchWorkItem?
    private var markClearWorkItem: DispatchWorkItem?
    private var imageClearWorkItem: DispatchWorkItem?
    private var settledMarksBySheet: [UUID: String] = [:]
    private var activeSheetID: UUID?

    init(durationConfig: DurationConfig = .default) {
        self.durationConfig = durationConfig
    }

    func buildTimeline(from sheet: CueSheet) {
        reset()
        activeSheetID = sheet.id
        settledRehearsalMarkText = settledMarksBySheet[sheet.id]

        let sorted = sheet.events.sorted { $0.at < $1.at }
        let markedCues: [(CueSheet.Event, String)] = {
            let candidates = sheet.events.filter { $0.kind == .cue && (($0.rehearsalMarkMode ?? .off) != .off) }
            return candidates.enumerated().map { (idx, ev) in (ev, rehearsalMarkLabel(for: idx)) }
        }()
        let markMap: [UUID: String] = Dictionary(uniqueKeysWithValues: markedCues.map { ($0.0.id, $0.1) })

        timeline = sorted.compactMap { event in
            switch event.kind {
            case .message:
                if case .message(let payload)? = event.payload {
                    return Entry(at: event.at, kind: .message(payload, event.holdSeconds))
                }
            case .image:
                let payload: CueSheet.ImagePayload = {
                    if case .image(let payload)? = event.payload { return payload }
#if DEBUG
                    assertionFailure("Image event missing payload; scheduling placeholder")
#endif
                    let caption = event.label.map { CueSheet.MessagePayload(text: $0) }
                    return CueSheet.ImagePayload(assetID: event.id, contentMode: .fit, caption: caption)
                }()
                return Entry(at: event.at, kind: .image(payload, event.holdSeconds))
            case .cue:
                if let mark = markMap[event.id] {
                    return Entry(at: event.at, kind: .rehearsalMark(mark, event.holdSeconds))
                }
            default:
                break
            }
            return nil
        }
        cursor = 0
    }

    func reset() {
        cancelAll()
        cursor = 0
        slot = .none
        image = nil
        messagePayload = nil
        rehearsalMarkText = nil
        settledRehearsalMarkText = nil
        isExpanded = false
        activeSheetID = nil
    }

    func dismiss() {
        cancelAll()
        slot = .none
        image = nil
        messagePayload = nil
        rehearsalMarkText = nil
        isExpanded = false
    }

    func apply(elapsed: TimeInterval) {
        while cursor < timeline.count && elapsed >= timeline[cursor].at {
            let entry = timeline[cursor]
            cursor += 1
            apply(entry)
        }
    }

    private func apply(_ entry: Entry) {
        switch entry.kind {
        case .message(let payload, let hold):
            messageClearWorkItem?.cancel()
            messagePayload = payload
            slot = .message(payload)
            schedule(for: hold, fallback: payload)
        case .image(let payload, let hold):
            imageClearWorkItem?.cancel()
            image = payload
            slot = .image(payload)
            schedule(for: hold, fallback: payload)
        case .rehearsalMark(let mark, let hold):
            markClearWorkItem?.cancel()
            rehearsalMarkText = mark
            if let sheetID = activeSheetID {
                settledMarksBySheet[sheetID] = mark
            }
            settledRehearsalMarkText = mark
            schedule(for: hold, fallback: mark)
        }

    }

    private func schedule(for hold: TimeInterval?, fallback payload: Any) {
        guard let hold else {
            scheduleDefaultDuration(for: payload)
            return
        }

        if hold > 0 {
            scheduleClear(after: hold, payload: payload)
        }
        // hold == 0 → sticky until dismissed/replaced
    }

    private func scheduleDefaultDuration(for payload: Any) {
        let charCount: Int = {
            if let msg = payload as? CueSheet.MessagePayload { return msg.text.count }
            if let img = payload as? CueSheet.ImagePayload { return img.caption?.text.count ?? 0 }
            if let mark = payload as? String { return mark.count }
            return 0
        }()
        let duration = min(durationConfig.base + (durationConfig.perChar * Double(charCount)), durationConfig.max)
        scheduleClear(after: duration, payload: payload)
    }

    private func scheduleClear(after delay: TimeInterval, payload: Any) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if payload is CueSheet.MessagePayload {
                self.messagePayload = nil
                if let image = self.image {
                    self.slot = .image(image)
                } else {
                    self.slot = .none
                }
            } else if payload is CueSheet.ImagePayload {
                self.image = nil
                if let message = self.messagePayload {
                    self.slot = .message(message)
                } else {
                    self.slot = .none
                }
            } else if payload is String {
                self.rehearsalMarkText = nil
            }
        }

        if payload is CueSheet.MessagePayload {
            messageClearWorkItem = work
        } else if payload is CueSheet.ImagePayload {
            imageClearWorkItem = work
        } else if payload is String {
            markClearWorkItem = work
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelAll() {
        messageClearWorkItem?.cancel()
        markClearWorkItem?.cancel()
        imageClearWorkItem?.cancel()
    }

    private func rehearsalMarkLabel(for index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var value = index
        var result = ""

        repeat {
            let remainder = value % letters.count
            result.insert(letters[remainder], at: result.startIndex)
            value = (value / letters.count) - 1
        } while value >= 0

        return result
    }
}
