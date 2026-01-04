//
//  TimerCardPad.swift
//  SyncTimer
//
//  Created by seb on 9/20/25.
//

import Foundation
import SwiftUI
// MARK: - TimerCardPad (iPad-only: full-width, no env deps)
struct TimerCardPad: View {
    @Environment(\.padMetrics) private var MX
    @Binding var mode: ViewMode
    @Binding var flashZero: Bool

    let isRunning: Bool
    let flashStyle: FlashStyle
    let flashColor: Color

    // minimal inputs
    var mainTime: TimeInterval
    var stopActive: Bool
    var stopRemaining: TimeInterval
    var isCountdownActive: Bool

    // optional labels for parity
    var leftHint: String = "START POINT"
    var rightHint: String = "DURATION"

    var body: some View {
        GeometryReader { geo in
                    // Respect global 20pt inset (provided by parent), but guard in case of reuse.
                    let innerW = max(0, geo.size.width - MX.insetsH*2)
                    // Unified, single-line timer scaling across sizes & orientations
                    let fs = MX.fsTimer

            ZStack {
                // carrier
                let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 1))
                    .shadow(radius: 10, y: 6)

                VStack(spacing: 10) {
                    // top hints
                    HStack {
                        Text(leftHint).foregroundStyle(.secondary)
                        Spacer()
                        Text(rightHint).foregroundStyle(.secondary)
                    }
                    .font(.system(size: fs * 0.22, weight: .regular))
                    .padding(.horizontal, MX.insetsH)
                    .padding(.top, 10)

                    // main timer row
                    HStack(spacing: 8) {
                        Text("-")
                            .font(.system(size: fs, weight: .light, design: .rounded))
                            .foregroundStyle(isCountdownActive ? .primary : .secondary)

                        Text(format(mainTime))
                            .font(.system(size: fs, weight: .regular, design: .rounded))
                            .minimumScaleFactor(0.5)
                            .foregroundStyle((flashStyle == .fullTimer && flashZero) ? flashColor : .primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, MX.insetsH)

                    // stop mini-timer row
                    HStack {
                        Text(stopActive ? "STOP" : "—")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(stopActive ? format(stopRemaining) : (showsHours(mainTime) ? "00:00:00.00" : "00:00.00"))
                            .font(.system(size: fs * 0.36, weight: .regular, design: .rounded))
                            .foregroundStyle(stopActive ? flashColor : .secondary)
                    }
                    .padding(.horizontal, MX.insetsH)
                    .padding(.top, 2)

                    // bottom labels
                    HStack {
                        Text("EVENTS VIEW")
                            .foregroundStyle(mode == .stop ? .primary : .secondary)
                        Spacer()
                        Text("SYNC VIEW")
                            .foregroundStyle(mode == .sync ? .primary : .secondary)
                    }
                    .font(.system(size: fs * 0.26, weight: .regular))
                    .padding(.horizontal, MX.insetsH)
                    .padding(.bottom, 10)
                }

                // simple flash dot (optional)
                if flashStyle == .dot && flashZero {
                    Circle()
                        .fill(flashColor)
                        .frame(width: fs * 0.14, height: fs * 0.14)
                        .offset(x: innerW * 0.46, y: -fs * 0.40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // tap halves to toggle modes (parity with phone)
            .overlay {
                HStack(spacing: 0) {
                    Color.clear.onTapGesture { mode = .stop }
                    Color.clear.onTapGesture { mode = .sync }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func showsHours(_ t: TimeInterval) -> Bool { Int(t) >= 3600 }
    private func format(_ t: TimeInterval) -> String {
        let cs = abs(Int((t * 100).rounded()) % 100)
        let total = max(0, Int(t))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 { return String(format:"%02d:%02d:%02d.%02d", h, m, s, cs) }
        return String(format:"%02d:%02d.%02d", m, s, cs)
    }
}
