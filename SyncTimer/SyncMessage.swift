import Foundation

enum SyncMessage: Codable {
    case sheetSnapshot(CueSheet)
    case playbackState(PlaybackState)
    case cueEvent(CueEvent)

    private enum CodingKeys: String, CodingKey {
        case type
        case sheetSnapshot
        case playbackState
        case cueEvent
    }

    private enum MessageType: String, Codable {
        case sheetSnapshot
        case playbackState
        case cueEvent
    }

    private static func encodeSheetSnapshot(_ sheet: CueSheet) throws -> String {
        let data = CueXML.write(sheet)
        return data.base64EncodedString()
    }

    private static func decodeSheetSnapshot(_ string: String) throws -> CueSheet {
        guard let data = Data(base64Encoded: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.sheetSnapshot],
                                                    debugDescription: "Invalid base64 sheet snapshot"))
        }
        return try CueXML.read(data)
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
