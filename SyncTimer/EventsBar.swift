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

//──────────────────────────────────────────────────────────────
// MARK: – LiquidGlassCircle (SDK-safe “liquid glass” button)
//──────────────────────────────────────────────────────────────
private struct GlassCircleIconButton: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 44
    var iconPointSize: CGFloat = 18
    var iconWeight: Font.Weight = .semibold
    var accessibilityLabel: String
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if #available(iOS 26.0, *) {
                    let shape = Circle()
                    // Tint wash (this is what makes it feel “saturated” like the cycle plate)
                    shape.fill(tint.opacity(0.22))

                    // Glass on top
                    shape
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(tint), in: shape)

                    // Rim — match EventsBarCycleGlassPlate language
                    shape.stroke(Color.white.opacity(0.14), lineWidth: 1)


                } else {
                    LiquidGlassCircle(diameter: size, tint: tint)
                }

                Image(systemName: systemName)
                    .font(.system(size: iconPointSize, weight: iconWeight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
        .frame(width: max(size, 44), height: max(size, 44))
    }
}

private struct LiquidGlassCircle: View {
    let diameter: CGFloat
    let tint: Color
    var body: some View {
        let shape = Circle()
        ZStack {
            // Core glass body (ultra-thin material)
            shape
                .fill(.ultraThinMaterial)
            // Rim lighting
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            // Subtle internal highlight
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(diameter * 0.06)
            // Tint wash (very light)
            shape
                .stroke(tint.opacity(0.65), lineWidth: 1)

        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
        .clipShape(shape)
        .contentShape(shape)
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
    var cueSheetAccent: Color = .accentColor

    var body: some View {
        let _arrowSpacing: CGFloat = 55
        GeometryReader { geo in
            let totalWidth    = geo.size.width
            let buttonWidth   = totalWidth / 4          // cycle button
                        let addWidth: CGFloat = 56                  // rectangular “+” button width
                        let carouselWidth = max(totalWidth - buttonWidth - addWidth, 0)
            let barHeight     = geo.size.height         // e.g. 60

            
            let modeTint: Color = {
                switch eventMode {
                case .stop:     return .red
                case .cue:      return .blue
                case .restart:  return .green
                }
            }()

            
            HStack(spacing: 0) {
                // ─── CYCLE (“STOP” / “CUE” / “RESTART”) button ─────────────────
                Button(action: {
                    Haptics.light()
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
                .modifier(EventsBarCycleGlassPlate(tint: modeTint, cornerRadius: 8))

                .offset(x: 18)            // ← shift the button 12px to the right
                .offset(y: 0)
                .disabled(isCounting)
                // Power-user path: long-press menu is safe (menu dismisses before action)
                .contextMenu {
                    Button {
                        attemptOpenCueSheets()
                    } label: {
                        Label("Cue Sheets…", systemImage: "arrow.up.document")
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
                GlassCircleIconButton(
                    systemName: "arrow.up.document",
                    tint: cueSheetAccent,
                    size: 44,
                    iconPointSize: 18,
                    accessibilityLabel: "Cue Sheets",
                    accessibilityHint: "Attach or load a cue sheet for this timer",
                    action: {
                        attemptOpenCueSheets()
                    }
                )
                .padding(.trailing, 8)
                .opacity(1.0)
                .disabled(false)
                .zIndex(50)

            }
        }
        .frame(height: 60)  // fix overall bar height at 60
    }
}


private struct EventsBarCycleGlassPlate: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular.tint(tint), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
        } else {
            content
                .background(tint, in: shape)
                .clipShape(shape)
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
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
    }
}
