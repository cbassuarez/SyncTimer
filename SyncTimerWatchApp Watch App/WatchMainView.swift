import SwiftUI
import WatchConnectivity   // for ConnectivityManager
import WatchKit            // for WKHapticType

// ── Local helper so `TimeInterval.formattedCS` exists on watchOS ──
private extension TimeInterval {
    /// HH:MM:SS.CC  (centiseconds)
    var formattedCS: String {
        let cs = Int((self * 100).rounded())
        let h  = cs / 360000
        let m  = (cs / 6000) % 60
        let s  = (cs / 100) % 60
        let c  = cs % 100
        return String(format: "%02d:%02d:%02d.%02d", h, m, s, c)
    }
}

// MARK: – UI
struct WatchMainView: View {
    @ObservedObject private var cm = ConnectivityManager.shared
    @State private var current: TimerMessage?

    var body: some View {
      
        VStack(spacing: 8) {
            
            if let m = current {
                Text(m.remaining.formattedCS)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(m.phase == "countdown" ? .red : .primary)
            } else {
                ProgressView()
            }
                
        }
        .onReceive(cm.$incoming.compactMap { $0 }) { current = $0 }
        .onAppear { WKInterfaceDevice.current().play(.notification) }
        .task {
            if let ctx = WCSession.default.receivedApplicationContext["timer"] as? Data,
               let msg = try? JSONDecoder().decode(TimerMessage.self, from: ctx) {
                current = msg
            }
        }
    }
}
