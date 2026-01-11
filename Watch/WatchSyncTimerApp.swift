//
//  WatchSyncTimerApp.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation
import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @Published var flashColor: Color = .red
}

@main
struct WatchSyncTimerApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            NowView()
                .environmentObject(appSettings)
        }
    }
}
