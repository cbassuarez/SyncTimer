import SwiftUI
import UIKit


struct ThemePicker: View {
    @Binding var selected: AppTheme
    @Binding var customColor: Color
    @Environment(\.colorScheme) private var colorScheme
    private let defaultOverlayColor: Color = Color.blue.opacity(0.75)

    
    @State private var didPickCustom = false
    @State private var showCustomPicker = false

    private let themes: [AppTheme] = [.light, .dark]
    

    var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(.custom("Roboto-Regular", size: 16))

                HStack(spacing: 16) {
                    // ─── Light / Dark buttons ────────────────────────────
                    ForEach(themes, id: \.self) { theme in
                        Button {
                            // select the theme and deselect any custom
                            selected = theme
                            customColor = .clear
                            lightHaptic()

                        } label: {
                            ZStack {
                                Circle()
                                    .fill(fillColor(for: theme))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(strokeColor(for: theme), lineWidth: 2.5)
                                    )
                                Image(systemName: theme == .light ? "sun.max.fill" : "moon.fill")
                                    .font(.system(size: 16))
                            }
                            .foregroundColor(theme == .light ? .yellow : .white)

                        }
                        .buttonStyle(.plain)
                    }

                    // ─── Custom-color palette icon ───────────────────────
                    ZStack {
                        // fallback to blue if custom is clear/near-invisible
                        let bg = shouldFallback(customColor)
                            ? defaultOverlayColor
                            : customColor

                        Circle()
                            .fill(bg)
                            .frame(width: 32, height: 32)

                        // show a stroke when a real customColor is active
                        Circle()
                            .stroke(
                                customColor != .clear
                                    ? (colorScheme == .dark ? .white : .black)
                                    : .clear,
                                lineWidth: 2.5
                            )
                            .frame(width: 32, height: 32)

                        Image(systemName: "paintpalette")
                            .font(.system(size: 16))
        
                        
                            .foregroundColor(.white)

                        // invisible picker overlay
                        ColorPicker("", selection: $customColor, supportsOpacity: true)
                            .labelsHidden()
                            .frame(width: 32, height: 32)
                            .opacity(0.1125)
                            .scaleEffect(1.2)
                        
                    }
                    .onChange(of: customColor) { new in
                        // treat picking a custom as “light” theme
                        if new != .clear {
                            selected = .light
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        
        }

    private func fillColor(for theme: AppTheme) -> Color {
        switch colorScheme {
        case .light:
            return theme == .light
                ? .white
                : Color(.darkGray)
        case .dark:
            return theme == .light
                ? .white
                : Color(.darkGray)
        @unknown default:
            return .white
        }
    }
    // fallback to blue if the custom color is clear/transparent or near-white
        private func shouldFallback(_ color: Color) -> Bool {
            let ui = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            return a < 0.05 || (r > 0.95 && g > 0.95 && b > 0.95)
        }

    private func strokeColor(for theme: AppTheme) -> Color {
       // if a custom overlay is active, no built-in theme should show as selected
        if customColor != .clear {
            return .clear
        }
        guard theme == selected else { return .clear }
        switch colorScheme {
        case .light:
            return theme == .light ? .black : .clear
        case .dark:
            return theme == .dark ? .white : .clear
        @unknown default:
            return .clear
        }
    }
}
