// SharedModels/Sources/SharedModels/SharedModels.swift
import Foundation
import SwiftUI
import Combine

// MARK: - Cross-platform DTOs
public struct StopEventWire: Codable, Equatable {
    public var eventTime: TimeInterval
    public var duration : TimeInterval

    public init(eventTime: TimeInterval, duration: TimeInterval) {
        self.eventTime = eventTime
        self.duration  = duration
    }
}
// NEW: light-weight wires for cues/restarts
public struct CueEventWire: Codable, Equatable {
    public let cueTime: TimeInterval
}
public struct RestartEventWire: Codable, Equatable {
    public let restartTime: TimeInterval
}
