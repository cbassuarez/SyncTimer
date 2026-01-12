import Foundation

#if os(watchOS)
struct CueSheet: Codable {
    let rawData: Data
}

struct PlaybackState: Codable {}

struct CueEvent: Codable {}
#endif

enum SyncMessage: Codable {
    case sheetSnapshot(CueSheet)
    case playbackState(PlaybackState)
    case cueEvent(CueEvent)
    case cueSheetIndexSummary(CueSheetIndexSummary)

    private enum CodingKeys: String, CodingKey {
        case type
        case sheetSnapshot
        case playbackState
        case cueEvent
        case cueSheetIndexSummary
        case cueSheetIndex
    }

    private enum MessageType: String, Codable {
        case sheetSnapshot
        case playbackState
        case cueEvent
        case cueSheetIndexSummary
        case cueSheetIndex
    }

    private struct LegacyCueSheetIndexItem: Codable {
        let id: UUID
        let title: String
        let cueCount: Int?
        let modifiedAt: Date?
    }

    private static func encodeSheetSnapshot(_ sheet: CueSheet) throws -> String {
        #if os(watchOS)
        return sheet.rawData.base64EncodedString()
        #else
        let blobs = CueLibraryStore.assetBlobsFromDisk(for: sheet)
        let data = CueXML.write(sheet, assets: blobs)
        return data.base64EncodedString()
        #endif
    }

    private static func decodeSheetSnapshot(_ string: String) throws -> CueSheet {
        guard let data = Data(base64Encoded: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.sheetSnapshot],
                                                    debugDescription: "Invalid base64 sheet snapshot"))
        }
        #if os(watchOS)
        return CueSheet(rawData: data)
        #else
        var (sheet, assets) = try CueXML.readWithAssets(data)
        CueLibraryStore.ingestEmbeddedAssetsFromDisk(for: &sheet, blobs: assets)
        return sheet
        #endif
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .sheetSnapshot:
            let snapshot = try container.decode(String.self, forKey: .sheetSnapshot)
            let sheet = try Self.decodeSheetSnapshot(snapshot)
            self = .sheetSnapshot(sheet)
        case .playbackState:
            let state = try container.decode(PlaybackState.self, forKey: .playbackState)
            self = .playbackState(state)
        case .cueEvent:
            let event = try container.decode(CueEvent.self, forKey: .cueEvent)
            self = .cueEvent(event)
        case .cueSheetIndexSummary:
            let summary = try container.decode(CueSheetIndexSummary.self, forKey: .cueSheetIndexSummary)
            self = .cueSheetIndexSummary(summary)
        case .cueSheetIndex:
            let legacy = try container.decode([LegacyCueSheetIndexItem].self, forKey: .cueSheetIndex)
            let items = legacy.map {
                CueSheetIndexSummary.Item(
                    id: $0.id,
                    name: $0.title,
                    cueCount: $0.cueCount,
                    modifiedAt: $0.modifiedAt?.timeIntervalSince1970
                )
            }
            self = .cueSheetIndexSummary(CueSheetIndexSummary(items: items, seq: 0))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sheetSnapshot(let sheet):
            try container.encode(MessageType.sheetSnapshot, forKey: .type)
            let snapshot = try Self.encodeSheetSnapshot(sheet)
            try container.encode(snapshot, forKey: .sheetSnapshot)
        case .playbackState(let state):
            try container.encode(MessageType.playbackState, forKey: .type)
            try container.encode(state, forKey: .playbackState)
        case .cueEvent(let event):
            try container.encode(MessageType.cueEvent, forKey: .type)
            try container.encode(event, forKey: .cueEvent)
        case .cueSheetIndexSummary(let summary):
            try container.encode(MessageType.cueSheetIndexSummary, forKey: .type)
            try container.encode(summary, forKey: .cueSheetIndexSummary)
        }
    }
}

struct SyncEnvelope: Codable {
    var seq: Int
    var message: SyncMessage

    init(seq: Int, message: SyncMessage) {
        self.seq = seq
        self.message = message
    }
}
