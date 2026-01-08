import Foundation

public struct PlaybackState: Codable, Equatable {
    public var isRunning: Bool
    public var startTime: TimeInterval
    public var elapsedTime: TimeInterval
    public var currentEventID: UUID?
    public var nextEventID: UUID?
    public var sheetID: UUID
    public var revision: Int
    public var protocolVersion: Int = 1
    public var sentAt: Date = .now

    public init(isRunning: Bool,
                startTime: TimeInterval,
                elapsedTime: TimeInterval,
                currentEventID: UUID?,
                nextEventID: UUID?,
                sheetID: UUID,
                revision: Int,
                protocolVersion: Int = 1,
                sentAt: Date = .now) {
        self.isRunning = isRunning
        self.startTime = startTime
        self.elapsedTime = elapsedTime
        self.currentEventID = currentEventID
        self.nextEventID = nextEventID
        self.sheetID = sheetID
        self.revision = revision
        self.protocolVersion = protocolVersion
        self.sentAt = sentAt
    }
}
