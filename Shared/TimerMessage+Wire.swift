//
//  TimerMessage+Wire.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation
public typealias CueSheetSummaryWire = TimerMessage.WatchCueSheetSummary
public struct CueSheetIndexWire: Codable, Equatable {
    public var items: [TimerMessage.WatchCueSheetSummary]
    public init(items: [TimerMessage.WatchCueSheetSummary]) {
        self.items = items
    }
}

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
    public struct WatchCueSheetSummary: Codable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var eventCount: Int
        public var estDurationSec: Double?
        public var isRecent: Bool?
        public var modifiedAt: Date? = nil
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
        public var stopIntervalActive: TimeInterval?
    
    // ── NEW (all optional; safe for older builds) ─────────────────────
        /// "parent" | "child"
        public var role: String?
        /// true iff peer sync link established (parent/child)
        public var connected: Bool?
        /// "bonjour" | "nearby" | "network" | "unreachable"
        public var link: String?
        /// true iff role==parent AND link is connected AND not parentLockEnabled
        public var controlsEnabled: Bool?
        /// "green" | "amber" | "red" — mirrors your Sync lamp
        public var syncLamp: String?
        /// one-shot edge for cue/zero-flash haptic (optional)
        public var flashNow: Bool?
        /// flash style identifier (e.g., "fullTimer", "dot", "tint")
        public var flashStyle: String?
        /// flash duration in milliseconds
        public var flashDurationMs: Int?
        /// flash color in ARGB (0xAARRGGBB)
        public var flashColorARGB: UInt32?
        /// flash color in RGBA components (r,g,b,a in 0...1)
        public var flashRGBA: [Double]?
        /// true iff flashColor is perceptually red (computed on phone)
        public var flashColorIsRed: Bool?
        /// monotonic flash sequence for edge detection
        public var flashSeq: UInt64?
        /// haptic enabled for flash, mirrors iOS setting
        public var flashHapticsEnabled: Bool?
        public var showHours: Bool?
        public var display: TimerDisplayWire?
        public var assetManifest: [CueAssetManifestItem]?
    public var assetRequests: [UUID]?
    public var assetChunks: [CueAssetChunk]?
    // UI-only (optional): watch next-event dial snapshot; no timer semantics change.
        public var scheduleState: String?
        public var nextEventRemaining: TimeInterval?
        public var nextEventInterval: TimeInterval?
        public var nextEventKind: String?
        public var nextEventStepped: Bool?
    // UI-only (optional): watch cue sheets snapshot; no timer semantics change.
        public var watchCueSheets: [WatchCueSheetSummary]?
        public var watchActiveCueSheetID: UUID?
        public var watchActiveCueSheetTitle: String?
        public var watchIsCueBroadcasting: Bool?
        public var watchPeerConnected: Bool?
        public var watchConnectedChildrenCount: Int?
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
                      stopIntervalActive: TimeInterval? = nil,
    cueEvents: [CueEventWire]? = nil,
            restartEvents: [RestartEventWire]? = nil,
            sheetLabel: String? = nil,
            sheetID: String? = nil,
                      role: String? = nil,
                      connected: Bool? = nil,
                      link: String? = nil,
                      controlsEnabled: Bool? = nil,
                      syncLamp: String? = nil,
                      flashNow: Bool? = nil,
                      flashStyle: String? = nil,
                      flashDurationMs: Int? = nil,
                      flashColorARGB: UInt32? = nil,
                      flashRGBA: [Double]? = nil,
                      flashColorIsRed: Bool? = nil,
                      flashSeq: UInt64? = nil,
                      flashHapticsEnabled: Bool? = nil,
                      showHours: Bool? = nil,
                      display: TimerDisplayWire? = nil,
                      assetManifest: [CueAssetManifestItem]? = nil,
                      assetRequests: [UUID]? = nil,
                      assetChunks: [CueAssetChunk]? = nil,
                      scheduleState: String? = nil,
                      nextEventRemaining: TimeInterval? = nil,
                      nextEventInterval: TimeInterval? = nil,
                      nextEventKind: String? = nil,
                      nextEventStepped: Bool? = nil,
                      watchCueSheets: [WatchCueSheetSummary]? = nil,
                      watchActiveCueSheetID: UUID? = nil,
                      watchActiveCueSheetTitle: String? = nil,
                      watchIsCueBroadcasting: Bool? = nil,
                      watchPeerConnected: Bool? = nil,
                      watchConnectedChildrenCount: Int? = nil) {
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
        self.stopIntervalActive = stopIntervalActive
        self.cueEvents = cueEvents
                self.restartEvents = restartEvents
        self.sheetLabel = sheetLabel
        self.sheetID = sheetID
        self.role              = role
        self.connected         = connected
                  self.link              = link
                  self.controlsEnabled   = controlsEnabled
                  self.syncLamp          = syncLamp
                  self.flashNow          = flashNow
        self.flashStyle        = flashStyle
        self.flashDurationMs   = flashDurationMs
        self.flashColorARGB    = flashColorARGB
        self.flashRGBA         = flashRGBA
        self.flashColorIsRed   = flashColorIsRed
        self.flashSeq          = flashSeq
        self.flashHapticsEnabled = flashHapticsEnabled
        self.showHours         = showHours
        self.display           = display
        self.assetManifest     = assetManifest
        self.assetRequests     = assetRequests
        self.assetChunks       = assetChunks
        self.scheduleState     = scheduleState
        self.nextEventRemaining = nextEventRemaining
        self.nextEventInterval = nextEventInterval
        self.nextEventKind     = nextEventKind
        self.nextEventStepped  = nextEventStepped
        self.watchCueSheets = watchCueSheets
        self.watchActiveCueSheetID = watchActiveCueSheetID
        self.watchActiveCueSheetTitle = watchActiveCueSheetTitle
        self.watchIsCueBroadcasting = watchIsCueBroadcasting
        self.watchPeerConnected = watchPeerConnected
        self.watchConnectedChildrenCount = watchConnectedChildrenCount
      }
}
