//
//  PhoneCanvas.swift
//  SyncTimer
//
//  Created by seb on 9/17/25.
//

import Foundation
import SwiftUI

/// Constrains child layout to a fixed phone canvas, then scales/centers it
/// inside the parent’s *safe area*. Because this wraps INSIDE ContentView,
/// all children receive the phone-sized proposal and cannot overflow.
struct PhoneCanvas<Content: View>: View {
    let designSize: CGSize          // e.g. 390x844 (iPhone 14/15) or 375x812
    var extraShrink: CGFloat = 1.0  // e.g. 0.92 to add breathing room
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let availW = max(1, geo.size.width  - (insets.leading + insets.trailing))
            let availH = max(1, geo.size.height - (insets.top + insets.bottom))
            let scale  = min(availW / designSize.width, availH / designSize.height) * extraShrink

            ZStack {
                content()
                    // Hard-bound the canvas so inner GeometryReaders / .infinity can’t exceed it
                    .frame(width: designSize.width, height: designSize.height)
                    .clipped()
                    .scaleEffect(scale, anchor: .center)
            }
            // Center inside safe area, then pad back out to full window
            .frame(width: availW, height: availH, alignment: .center)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
