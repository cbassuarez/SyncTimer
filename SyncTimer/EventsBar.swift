import SwiftUI

struct EventsBar: View {
    @Binding var events: [Event]
    @Binding var eventMode: EventMode
    var isCounting: Bool
    let onAddStop: () -> Void
    let onAddCue: () -> Void
    let onAddRestart: () -> Void

    var body: some View {
        let _arrowSpacing: CGFloat = 55
        GeometryReader { geo in
            let totalWidth    = geo.size.width
            let buttonWidth   = totalWidth / 4          // 1/4 of the bar
            let carouselWidth = totalWidth * 3 / 4      // 3/4 of the bar
            let barHeight     = geo.size.height         // e.g. 60

            HStack(spacing: 0) {
                // ─── CYCLE (“STOP” / “CUE” / “RESTART”) button ─────────────────
                Button(action: {
                    // Cycle through modes: stop → cue → restart → stop
                    switch eventMode {
                    case .stop:     eventMode = .cue
                    case .cue:      eventMode = .restart
                    case .restart:  eventMode = .stop
                    }
                }) {
                    Text(
                        eventMode == .stop   ? "STOP" :
                        eventMode == .cue    ? "CUE" :
                                              "RESTART"
                    )
                    .font(.custom("Roboto-SemiBold", size: 18))
                    .foregroundColor(.white)
                    .frame(width: buttonWidth, height: barHeight)
                }
                .background({
                    switch eventMode {
                    case .stop:     return Color.red
                    case .cue:      return Color.blue
                    case .restart:  return Color.green
                    }
                }())
                .cornerRadius(8)
                .offset(x: 18)            // ← shift the button 12px to the right
                .offset(y: 0)
                .disabled(isCounting)

                // ─── EventsCarousel occupies the remaining two-thirds ─────────────
                EventsCarousel(events: $events, isCounting: isCounting)
                    .frame(width: carouselWidth, height: barHeight)
            }
            .frame(width: totalWidth, height: barHeight, alignment: .center)
            .offset(y: 0)
        }
        .frame(height: 60)  // fix overall bar height at 60
    }
}
