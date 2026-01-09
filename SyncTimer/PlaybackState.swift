import Foundation

public enum PlaybackPhase: String, Codable {
    case idle
    case running
    case paused
}

public struct PlaybackState: Codable, Equatable {
    public var isRunning: Bool
    public var phase: PlaybackPhase?
    public var seq: UInt64?
    public var masterUptimeNsAtStop: UInt64?
    public var elapsedAtStopNs: UInt64?
    public var startTime: TimeInterval
    public var elapsedTime: TimeInterval
    public var currentEventID: UUID?
    public var nextEventID: UUID?
    public var sheetID: UUID
    public var revision: Int
    public var protocolVersion: Int = 1
    public var sentAt: Date = .now

    public init(isRunning: Bool,
                phase: PlaybackPhase? = nil,
                seq: UInt64? = nil,
                masterUptimeNsAtStop: UInt64? = nil,
                elapsedAtStopNs: UInt64? = nil,
                startTime: TimeInterval,
                elapsedTime: TimeInterval,
                currentEventID: UUID?,
                nextEventID: UUID?,
                sheetID: UUID,
                revision: Int,
                protocolVersion: Int = 1,
                sentAt: Date = .now) {
        self.isRunning = isRunning
        self.phase = phase
        self.seq = seq
        self.masterUptimeNsAtStop = masterUptimeNsAtStop
        self.elapsedAtStopNs = elapsedAtStopNs
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
