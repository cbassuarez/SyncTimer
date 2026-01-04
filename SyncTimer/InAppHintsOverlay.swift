//
//  InAppHintsOverlay.swift
//  SyncTimer
//
//  Created by seb on 9/12/25.
//

import Foundation
import SwiftUI

struct InAppHint: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

struct InAppHintsOverlay: View {
    @Binding var isShowing: Bool
    @Binding var step: Int
    let steps: [InAppHint]

    var body: some View {
        if isShowing, !steps.isEmpty {
            ZStack {
                // Dim scrim
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { advance() }

                // Card (matches your BLE/LAN status card aesthetics)
                VStack(alignment: .leading, spacing: 10) {
                    // Header line (status-dot + “Hints” label)
                    HStack(spacing: 8) {
                        Circle().fill(Color.yellow).frame(width: 10, height: 10)
                        Text("Hints")
                            .font(.custom("Roboto-Medium", size: 16))
                        Spacer()
                        Text("\(step + 1)/\(steps.count)")
                            .font(.custom("Roboto-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }

                    Text(steps[step].title)
                        .font(.custom("Roboto-SemiBold", size: 18))

                    Text(steps[step].body)
                        .font(.custom("Roboto-Regular", size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Skip") { isShowing = false }
                            .font(.custom("Roboto-SemiBold", size: 14))
                            .foregroundColor(.primary)
                        Spacer()
                        Button(step == steps.count - 1 ? "Done" : "Next") { advance() }
                            .font(.custom("Roboto-SemiBold", size: 14))
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 20)
                .frame(maxWidth: 420)
                .transition(.opacity)
            }
        }
    }

    private func advance() {
        if step + 1 < steps.count {
            step += 1
        } else {
            isShowing = false
        }
    }
}

// A small preset you can tweak anytime
enum HintsLibrary {
    static let firstRun: [InAppHint] = [
        .init(title: "Pick your link",
              body: "Use the CONNECT tab’s picker to choose Bluetooth or LAN. Bluetooth is easiest; LAN is most precise."),
        .init(title: "Set your role",
              body: "Tap CHILD / PARENT at the bottom. Parent drives; Child follows."),
        .init(title: "Tap SYNC to begin",
              body: "Amber dot = discovering/advertising. Green dot = connected and syncing."),
        .init(title: "Nearby",
              body: "SYNC on both devices. No pairing step; the child auto-finds the parent nearby."),
        .init(title: "LAN",
              body: "Parent: tap Your IP to reveal and Your Port to generate. Child: tap Parent IP and Parent Port to join.")
    ]
}
