//
//  UIEnvironmentKeys.swift
//  SyncTimer
//
//  Created by seb on 9/14/25.
//

import Foundation
import SwiftUI
// MARK: - Environment keys for pane & badge stroke color
struct IsEventsPaneKey: EnvironmentKey { static let defaultValue: Bool = false }
struct BadgeStrokeColorKey: EnvironmentKey { static let defaultValue: Color = .accentColor }

extension EnvironmentValues {
    var isEventsPane: Bool {
        get { self[IsEventsPaneKey.self] }
        set { self[IsEventsPaneKey.self] = newValue }
    }
    var badgeStrokeColor: Color {
        get { self[BadgeStrokeColorKey.self] }
        set { self[BadgeStrokeColorKey.self] = newValue }
    }
}
