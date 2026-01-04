//
//  WatchStubs.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation
#if os(watchOS)
import SwiftUI

public struct TimerCard: View {
    @Binding var flashZero: Bool
    var isRunning: Bool
    var syncDigits: [Int]
    var stopDigits: [Int]
    var mainTime: TimeInterval
    var stopActive: Bool
    var stopRemaining: TimeInterval
    var isCountdownActive: Bool

    public init(flashZero: Binding<Bool>, isRunning: Bool,
                syncDigits: [Int], stopDigits: [Int],
                mainTime: TimeInterval, stopActive: Bool,
                stopRemaining: TimeInterval, isCountdownActive: Bool) {
        self._flashZero = flashZero
        self.isRunning = isRunning
        self.syncDigits = syncDigits
        self.stopDigits = stopDigits
        self.mainTime = mainTime
        self.stopActive = stopActive
        self.stopRemaining = stopRemaining
        self.isCountdownActive = isCountdownActive
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(timeString(mainTime))
                .font(.system(size: 32, weight: .semibold))
            if stopActive {
                Text("Stop: " + timeString(stopRemaining)).font(.footnote)
            }
        }
    }
    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded()); return String(format: "%02d:%02d", s/60, s%60)
    }
}

public struct SyncBar: View {
    var isCounting: Bool
    var isSyncEnabled: Bool
    var onToggleSync: () -> Void
    var onRoleConfirmed: (Bool) -> Void

    public init(isCounting: Bool, isSyncEnabled: Bool,
                onToggleSync: @escaping () -> Void,
                onRoleConfirmed: @escaping (Bool) -> Void) {
        self.isCounting = isCounting
        self.isSyncEnabled = isSyncEnabled
        self.onToggleSync = onToggleSync
        self.onRoleConfirmed = onRoleConfirmed
    }

    public var body: some View {
        HStack {
            Circle().fill(isSyncEnabled ? .green : .red).frame(width: 8, height: 8)
            Text(isCounting ? "Running" : "Idle").font(.caption2)
            Spacer()
            Image(systemName: "lock.fill").opacity(0.4) // visible but disabled
        }.padding(.horizontal, 2)
    }
}

public struct SyncBottomButtons: View {
    var showResetButton: Bool
    var showPageIndicator: Bool
    var currentPage: Int
    var totalPages: Int
    var isCounting: Bool
    var startStop: () -> Void
    var reset: () -> Void

    public init(showResetButton: Bool, showPageIndicator: Bool,
                currentPage: Int, totalPages: Int, isCounting: Bool,
                startStop: @escaping () -> Void, reset: @escaping () -> Void) {
        self.showResetButton = showResetButton
        self.showPageIndicator = showPageIndicator
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.isCounting = isCounting
        self.startStop = startStop
        self.reset = reset
    }

    public var body: some View {
        HStack {
            if showResetButton { Button("Reset", action: reset).disabled(isCounting) }
            Spacer()
            Button(isCounting ? "Stop" : "Start", action: startStop)
        }.font(.callout)
    }
}
#endif
