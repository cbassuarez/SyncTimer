import Foundation
import SwiftUI

/// Drives the single display slot (message/image) as events fire.
final class CueDisplayController: ObservableObject {
    enum Slot: Equatable {
        case none
        case message(CueSheet.MessagePayload)
        case image(CueSheet.ImagePayload)
    }

    @Published private(set) var slot: Slot = .none

    private struct Entry {
        var at: TimeInterval
        var slot: Slot
        var hold: TimeInterval?
    }

    private var timeline: [Entry] = []
    private var cursor: Int = 0
    private var clearWorkItem: DispatchWorkItem?

    func buildTimeline(from sheet: CueSheet) {
        timeline = sheet.events
            .filter { $0.kind == .message || $0.kind == .image }
            .sorted { $0.at < $1.at }
            .compactMap { event in
                switch event.kind {
                case .message:
                    if case .message(let payload)? = event.payload {
                        return Entry(at: event.at, slot: .message(payload), hold: event.holdSeconds)
                    }
                case .image:
                    if case .image(let payload)? = event.payload {
                        return Entry(at: event.at, slot: .image(payload), hold: event.holdSeconds)
                    }
                default: break
                }
                return nil
            }
        cursor = 0
    }

    func reset() {
        clearWorkItem?.cancel()
        cursor = 0
        slot = .none
    }

    func apply(elapsed: TimeInterval) {
        while cursor < timeline.count && elapsed >= timeline[cursor].at {
            let entry = timeline[cursor]
            cursor += 1
            apply(entry)
        }
    }

    private func apply(_ entry: Entry) {
        clearWorkItem?.cancel()
        slot = entry.slot
        if let hold = entry.hold, hold > 0 {
            let work = DispatchWorkItem { [weak self] in
                self?.slot = .none
            }
            clearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
        }
    }
}
