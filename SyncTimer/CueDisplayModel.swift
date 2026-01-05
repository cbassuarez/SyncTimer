import Foundation
import SwiftUI

@MainActor
/// Drives the single display slot (message/image) as events fire.
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

    private let durationConfig: DurationConfig

    private struct Entry {
        var at: TimeInterval
        var slot: Slot
        var hold: TimeInterval?
    }

    private var timeline: [Entry] = []
    private var cursor: Int = 0
    private var clearWorkItem: DispatchWorkItem?

    init(durationConfig: DurationConfig = .default) {
        self.durationConfig = durationConfig
    }

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

    func dismiss() {
        clearWorkItem?.cancel()
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

        guard let hold = entry.hold else {
            scheduleDefaultDuration(for: entry.slot)
            return
        }

        if hold > 0 {
            scheduleClear(after: hold)
        }
        // hold == 0 → sticky until dismissed/replaced
    }

    private func scheduleDefaultDuration(for slot: Slot) {
        let charCount: Int = {
            switch slot {
            case .message(let payload):
                return payload.text.count
            case .image(let payload):
                return payload.caption?.text.count ?? 0
            case .none:
                return 0
            }
        }()
        let duration = min(durationConfig.base + (durationConfig.perChar * Double(charCount)), durationConfig.max)
        scheduleClear(after: duration)
    }

    private func scheduleClear(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            self?.slot = .none
        }
        clearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
