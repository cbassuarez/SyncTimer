//
//  TimerMessage+Wire.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation
public struct TimerMessage: Codable, Equatable {
    public enum Action: String, Codable {
        case update, start, pause, reset, addEvent
    }

    public var action   : Action
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
    /// Optional, only set by the **parent**. Mirrored read-only on children.
        var notesParent: String?
    public init(action: Action,
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
                      role: String? = nil,
                      link: String? = nil,
                      controlsEnabled: Bool? = nil,
                      syncLamp: String? = nil,
                      flashNow: Bool? = nil) {
          self.action            = action
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
        self.role              = role
                  self.link              = link
                  self.controlsEnabled   = controlsEnabled
                  self.syncLamp          = syncLamp
                  self.flashNow          = flashNow
      }
}
