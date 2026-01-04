import SwiftUI
import UIKit
// ─────────────────────────────────────────────────────────────
// MARK: – SyncStatusLamp (red → amber → green, modern + light)
// ─────────────────────────────────────────────────────────────
struct SyncStatusLamp: View {
    enum LampState: Equatable { case off, streaming, connected } // ⟵ renamed from `State`
    var state: LampState
    var size: CGFloat = 18
    var highContrast: Bool = false

    @State private var breathe = false   // no shadowing now

    private var color: Color {
        switch state {
        case .off:       return .red
        case .streaming: return .orange
        case .connected: return .green
        }
    }
    // Use custom art in low-contrast mode (fallback to color dot if asset missing)
        private var badgeAssetName: String {
        switch state {
           case .off:       return "syncLamp_off"     // optional; won't be used below
         case .streaming: return "syncLamp_amber"
            case .connected: return "syncLamp_green"
            }
        }
    
    // NEW: asset names for low-contrast mode
        private var assetName: String {
            switch state {
            case .off:       return "syncLamp_red"
            case .streaming: return "syncLamp_amber"
            case .connected: return "syncLamp_green"
            }
        }

    private var transitionAnimation: Animation {
        if #available(iOS 17.0, *) { .snappy(duration: 0.28, extraBounce: 0.02) }
        else { .easeInOut(duration: 0.28) }
    }

    var body: some View {
        ZStack {
            // Base glyph
            Group {
                if highContrast {
                    Image(systemName:
                            state == .connected ? "checkmark.circle.fill"
                          : state == .streaming ? "exclamationmark.circle.fill"
                          : "xmark.octagon.fill"
                    )
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(color, Color.primary.opacity(0.22))
                } else {
                    // NEW: use custom art; fall back to color dot if asset missing
                    if let ui = UIImage(named: assetName) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                    } else {
                                        if let ui = UIImage(named: assetName) {
                                            Image(uiImage: ui).resizable().scaledToFit()
                                        } else {
                                            Circle().fill(color)
                                        }
                                    }
                }
            }
            .frame(width: size, height: size)
            .contentTransition(.opacity)
            .transaction { $0.animation = transitionAnimation }

            // Streaming “breath”: subtle halo
            if state == .streaming {
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: max(1, size * 0.10))
                    .frame(width: size, height: size)
                    .scaleEffect(breathe ? 1.14 : 0.92)
                    .opacity(breathe ? 0.45 : 0.18)
                    .allowsHitTesting(false)
            }

            // Connected “ripple”: single soft burst when entering .connected
            if state == .connected {
                if #available(iOS 17.0, *) {
                    Circle()
                        .stroke(color.opacity(0.22), lineWidth: max(1, size * 0.08))
                        .frame(width: size, height: size)
                        .keyframeAnimator(
                            initialValue: (scale: CGFloat(1.0), alpha: CGFloat(0.0)),
                            trigger: state   // re-runs when state changes to .connected
                        ) { view, value in
                            view
                                .scaleEffect(value.scale)
                                .opacity(value.alpha)
                        } keyframes: { _ in
                            KeyframeTrack(\.scale) {
                                CubicKeyframe(1.00, duration: 0.00)
                                CubicKeyframe(1.30, duration: 0.18)
                                CubicKeyframe(1.60, duration: 0.22)
                            }
                            KeyframeTrack(\.alpha) {
                                CubicKeyframe(0.00, duration: 0.00)
                                CubicKeyframe(0.40, duration: 0.18)
                                CubicKeyframe(0.00, duration: 0.22)
                            }
                        }
                        .allowsHitTesting(false)
                } else {
                    // Pre-iOS 17 fallback: quick ease-out pulse
                    Circle()
                        .stroke(color.opacity(0.22), lineWidth: max(1, size * 0.08))
                        .frame(width: size, height: size)
                        .scaleEffect(1.0)
                        .opacity(0.0)
                        .overlay(
                            Circle()
                                .stroke(color.opacity(0.22), lineWidth: max(1, size * 0.08))
                                .frame(width: size, height: size)
                                .scaleEffect(1.6)
                                .opacity(0.0)
                                .animation(.easeOut(duration: 0.35), value: state == .connected)
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        // Symbol bounce only in high-contrast mode
        .modifier(SymbolBounceIfHighContrast(highContrast: highContrast, trigger: state == .connected))
            

        // Drive the amber “breath” with a task keyed to `state` (no mutability complaints)
        .task(id: state) {
            if state == .streaming {
                breathe = false // reset baseline
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            } else {
                breathe = false
            }
        }

    }
}

private struct SymbolBounceIfHighContrast: ViewModifier {
    var highContrast: Bool
    var trigger: Bool
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), highContrast {
            content.symbolEffect(.bounce, value: trigger)
        } else {
            content
        }
    }
}



struct EventsBar: View {
    @Binding var events: [Event]
    @Binding var eventMode: EventMode
    var isPaused: Bool = false                 // only allow opening while paused
    var unsavedChanges: Bool = false           // shows red dot if true
    var onOpenCueSheets: (() -> Void)? = nil   // called when long-pressed & allowed
    var isCounting: Bool
    let onAddStop: () -> Void
    let onAddCue: () -> Void
    let onAddRestart: () -> Void

    var body: some View {
        let _arrowSpacing: CGFloat = 55
        GeometryReader { geo in
            let totalWidth    = geo.size.width
            let buttonWidth   = totalWidth / 4          // cycle button
                        let addWidth: CGFloat = 56                  // rectangular “+” button width
                        let carouselWidth = max(totalWidth - buttonWidth - addWidth, 0)
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
                    // NEW: unsaved “dot”
                                        .overlay(alignment: .topTrailing) {
                                            if unsavedChanges {
                                                Circle().fill(Color.red)
                                                    .frame(width: 6, height: 6)
                                                    .offset(x: 4, y: -4)
                                                    .accessibilityLabel("Unsaved changes")
                                            }
                                        }
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
                // Power-user path: long-press menu is safe (menu dismisses before action)
                                .contextMenu {
                                    Button {
                                        attemptOpenCueSheets()
                                    } label: {
                                        Label("Cue Sheets…", systemImage: "paperclip")
                                    }
                                }
                // ─── Rectangular “+” button → opens Cue Sheets ─────────────────
                                

                // ─── EventsCarousel occupies the remaining two-thirds ─────────────
                EventsCarousel(events: $events, isCounting: isCounting)
                    .frame(width: carouselWidth, height: barHeight)
                    .padding(.trailing, 56) //ensure the carousel text does not run into paperclip button
            }
            .frame(width: totalWidth, height: barHeight, alignment: .center)
            .offset(y: 0)
            // Trailing attach button (paperclip). Small, low emphasis, 44pt hit target.
                        .overlay(alignment: .trailing) {
                            Button {
                                attemptOpenCueSheets()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "paperclip")
                                        .imageScale(.medium)
                                    // No text; icon only to avoid competing with “+”
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .frame(minWidth: 44, minHeight: 44) // ensure comfortable hit size
                                .onTapGesture { attemptOpenCueSheets() }
                            }
                            .buttonStyle(.plain)
                            .zIndex(9999) //ensure paperclip wins hit test
                            // Win any gesture races with underlying content
                            .highPriorityGesture(TapGesture().onEnded { attemptOpenCueSheets() })
                            .simultaneousGesture(TapGesture().onEnded { attemptOpenCueSheets() })
                            .allowsHitTesting(true)
                            .padding(.trailing, 8)
                            .opacity((isPaused && !isCounting) ? 1.0 : 0.35)
                            //.disabled(!isPaused || isCounting)
                            .accessibilityLabel("Cue Sheets")
                            .accessibilityHint("Attach or load a cue sheet for this timer")
                        }
        }
        .frame(height: 60)  // fix overall bar height at 60
    }
}

// MARK: - Light haptics helpers
private enum Haptics {
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
// MARK: - Local helpers
private extension EventsBar {
    func attemptOpenCueSheets() {
        // Rely on the parent’s `.disabled(!isPaused || isCounting)` to enforce pause-only.
                // Do not silently block here — just fire the presenter on next runloop tick.
                Haptics.light()
                DispatchQueue.main.async { onOpenCueSheets?() }
                }    }

