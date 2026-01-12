//
//  TimerMessage+Wire.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation
public struct TimerMessage: Codable, Equatable {
    public enum Action: String, Codable {
        case update, start, pause, reset, addEvent, endCueSheet
    }
    public struct TimerDisplayWire: Codable, Equatable {
        public enum Kind: String, Codable { case none, message, image }
        public var kind: Kind
        public var text: String?
        public var fmt: String?
        public var assetID: UUID?
        public var caption: String?
        public var captionFmt: String?
        public var contentMode: String?
        public init(kind: Kind, text: String? = nil, fmt: String? = nil, assetID: UUID? = nil, caption: String? = nil, captionFmt: String? = nil, contentMode: String? = nil) {
            self.kind = kind
            self.text = text
            self.fmt = fmt
            self.assetID = assetID
            self.caption = caption
            self.captionFmt = captionFmt
            self.contentMode = contentMode
        }
    }
    public struct EventStamp: Codable, Equatable, Identifiable {
        public enum Kind: String, Codable {
            case stop
            case cue
            case restart
            case message
            case image
            case unknown

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let raw = (try? container.decode(String.self)) ?? ""
                self = Kind(rawValue: raw) ?? .unknown
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
        }

        public let id: UInt64
        public let kind: Kind
        public let time: TimeInterval

        public init(id: UInt64, kind: Kind, time: TimeInterval) {
            self.id = id
            self.kind = kind
            self.time = time
        }
    }

    public struct DisplayState: Codable, Equatable {
        public enum Kind: String, Codable {
            case none
            case cueFlash
            case message
            case image
            case unknown

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let raw = (try? container.decode(String.self)) ?? ""
                self = Kind(rawValue: raw) ?? .unknown
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
        }

        public var displayID: UInt64
        public var kind: Kind
        public var text: String?
        public var assetID: UUID?
        public var rehearsalMark: String?
        public var flashStartUptimeNs: UInt64?
        public var flashDurationMs: UInt32?
        public var holdUntilUptimeNs: UInt64?

        public init(displayID: UInt64,
                    kind: Kind,
                    text: String? = nil,
                    assetID: UUID? = nil,
                    rehearsalMark: String? = nil,
                    flashStartUptimeNs: UInt64? = nil,
                    flashDurationMs: UInt32? = nil,
                    holdUntilUptimeNs: UInt64? = nil) {
            self.displayID = displayID
            self.kind = kind
            self.text = text
            self.assetID = assetID
            self.rehearsalMark = rehearsalMark
            self.flashStartUptimeNs = flashStartUptimeNs
            self.flashDurationMs = flashDurationMs
            self.holdUntilUptimeNs = holdUntilUptimeNs
        }
    }
    public struct CueAssetManifestItem: Codable, Equatable {
        public var id: UUID
        public var mime: String
        public var sha256: String
        public var byteCount: Int
    }
    public struct CueAssetChunk: Codable, Equatable {
        public var id: UUID
        public var offset: Int
        public var data: String
    }

    public var action   : Action
    public var actionSeq: UInt64?
    public var stateSeq: UInt64?
    public var actionKind: Action?
    public var timestamp: TimeInterval
    public var phase    : String
    public var remaining: TimeInterval
    public var stopEvents: [StopEventWire]
    public var anchorElapsed: TimeInterval?
    public var parentLockEnabled: Bool?
    // NEW (optional): broadcast *all* events + sheet badge
        public let cueEvents: [CueEventWire]?
        public let restartEvents: [RestartEventWire]?
        public let sheetLabel: String?
        public let sheetID: String?
    // NEW: lets parent say “a stop just began”, and how much is left
        public var isStopActive: Bool?
        public var stopRemainingActive: TimeInterval?
    
    // ── NEW (all optional; safe for older builds) ─────────────────────
        /// "parent" | "child"
        public var role: String?
        /// "bonjour" | "nearby" | "network" | "unreachable"
        public var link: String?
        /// true iff role==parent AND link is connected AND not parentLockEnabled
        public var controlsEnabled: Bool?
        /// "green" | "amber" | "red" — mirrors your Sync lamp
        public var syncLamp: String?
        /// one-shot edge for cue/zero-flash haptic (optional)
        public var flashNow: Bool?
        public var showHours: Bool?
        public var display: TimerDisplayWire?
        public var recentEventStamps: [EventStamp]?
        public var displayState: DisplayState?
        public var assetManifest: [CueAssetManifestItem]?
        public var assetRequests: [UUID]?
        public var assetChunks: [CueAssetChunk]?
    /// Optional, only set by the **parent**. Mirrored read-only on children.
        var notesParent: String?
    public init(action: Action,
                  actionSeq: UInt64? = nil,
                  stateSeq: UInt64? = nil,
                  actionKind: Action? = nil,
                  timestamp: TimeInterval,
                  phase: String,
                  remaining: TimeInterval,
                  stopEvents: [StopEventWire],
                  anchorElapsed: TimeInterval? = nil,
                  parentLockEnabled: Bool? = nil,
    isStopActive: Bool? = nil,
                      stopRemainingActive: TimeInterval? = nil,
    cueEvents: [CueEventWire]? = nil,
            restartEvents: [RestartEventWire]? = nil,
            sheetLabel: String? = nil,
            sheetID: String? = nil,
                      role: String? = nil,
                      link: String? = nil,
                      controlsEnabled: Bool? = nil,
                      syncLamp: String? = nil,
                      flashNow: Bool? = nil,
                      showHours: Bool? = nil,
                      display: TimerDisplayWire? = nil,
                      recentEventStamps: [EventStamp]? = nil,
                      displayState: DisplayState? = nil,
                      assetManifest: [CueAssetManifestItem]? = nil,
                      assetRequests: [UUID]? = nil,
                      assetChunks: [CueAssetChunk]? = nil) {
          self.action            = action
          self.actionSeq         = actionSeq
          self.stateSeq          = stateSeq
          self.actionKind        = actionKind
          self.timestamp         = timestamp
          self.phase             = phase
          self.remaining         = remaining
          self.stopEvents        = stopEvents
          self.anchorElapsed     = anchorElapsed
          self.parentLockEnabled = parentLockEnabled
          self.isStopActive      = isStopActive
          self.stopRemainingActive = stopRemainingActive
        self.cueEvents = cueEvents
                self.restartEvents = restartEvents
        self.sheetLabel = sheetLabel
        self.sheetID = sheetID
        self.role              = role
                  self.link              = link
                  self.controlsEnabled   = controlsEnabled
                  self.syncLamp          = syncLamp
                  self.flashNow          = flashNow
        self.showHours         = showHours
        self.display           = display
        self.recentEventStamps = recentEventStamps
        self.displayState      = displayState
        self.assetManifest     = assetManifest
        self.assetRequests     = assetRequests
        self.assetChunks       = assetChunks
      }
}
