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
