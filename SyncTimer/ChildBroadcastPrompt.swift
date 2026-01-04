//
//  ChildBroadcastPrompt.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation
import SwiftUI

struct ChildBroadcastPrompt: View {
    let sheet: CueSheet
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var seconds = 15
    var body: some View {
        VStack(spacing: 12) {
            Text("Load Cue Sheet?").font(.headline)
            Text(sheet.title).font(.subheadline)
            Text("\(sheet.events.count) events • \(Int(sheet.bpm)) BPM • \(sheet.timeSigNum)/\(sheet.timeSigDen)")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Decline (\(seconds))", role: .cancel) { onDecline() }
                Button("Accept") { onAccept() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                seconds -= 1; if seconds <= 0 { t.invalidate(); onDecline() }
            }
        }
    }
}
