//
//  AdaptiveRoot.swift
//  SyncTimer
//
//  Created by seb on 9/17/25.
//

import Foundation
import SwiftUI

struct AdaptiveRoot: View {
    @Environment(\.openWindow) private var openWindow
    @State private var mode: ViewMode = .sync           // reuse your existing enum if you have one
    @State private var showSettingsSheet = false

    var body: some View {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let isMini = (w < 600) || (h < 280)
    
                if isMini {
                    // Mini-in-place: just reuse your existing ContentView
                    ContentView()
                } else if w >= 980 {
                    // 3-pane command center (currently stubbed to ContentView in your project)
                    CommandCenter3Pane()
                } else {
                    // 2-pane command center (also stubbed)
                    CommandCenter2Pane()
                }
            }
        }
}
