import Foundation

public enum SyncMessage: Codable {
    case sheetSnapshot(CueSheet)
    case playbackState(PlaybackState)
    case cueEvent(CueEvent)
}

public struct SyncEnvelope: Codable {
    public var seq: Int
    public var message: SyncMessage

    public init(seq: Int, message: SyncMessage) {
        self.seq = seq
        self.message = message
    }
}
