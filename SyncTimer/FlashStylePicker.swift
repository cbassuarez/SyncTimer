import SwiftUI

struct FlashStylePicker: View {
    @Binding var selectedStyle: FlashStyle
    @Binding var flashColor: Color

    private let styles: [FlashStyle] = FlashStyle.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flash Style")
                .font(.custom("Roboto-Regular", size: 16))

            HStack(spacing: 14) {
                ForEach(styles) { style in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectedStyle = style
                        }
                        lightHaptic()

                    }) {
                        ZStack {
                            // background circle matches your chosen flashColor
                            Circle()
                                .fill(flashColor.opacity(0.2))
                                .frame(width: 32, height: 32)

                            // inner content for each style
                            switch style {
                            case .dot:
                                // small circle, half the diameter, filled with flashColor
                                Circle()
                                    .fill(flashColor)
                                    .frame(width: 16, height: 16)

                            case .fullTimer:
                                Text("00:")
                                    .font(.custom("Roboto-SemiBold", size: 14))
                                    .foregroundColor(.primary)

                            case .delimiters:
                                Text(":")
                                    .font(.custom("Roboto-SemiBold", size: 14))
                                    .foregroundColor(.primary)

                            case .numbers:
                                Text("00")
                                    .font(.custom("Roboto-SemiBold", size: 14))
                                    .foregroundColor(.primary)

                            case .tint:
                                ZStack {
                                    // 1) Grayscale gradient
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.white, .gray]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            .opacity(0.5)
                                        )
                                    // 2) Multiply blend with your flashColor
                                    Circle()
                                        .fill(flashColor)
                                        .blendMode(.multiply)
                                }
                                .compositingGroup()   // required so the blendMode only applies within this ZStack
                                .frame(width: 32, height: 32)
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(
                                    selectedStyle == style ? Color.primary : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement()     // group them into one a11y-element
            .accessibilityLabel("Dot flash style")
            .accessibilityHint("Flashes a dot at each centisecond rollover")
        }
    }
}

struct FlashDurationPicker: View {
    @Binding var selectedDuration: Int
    @EnvironmentObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    
    private let options: [(value: Int, label: String)] = [
        (100,  ".1s"),
        (250,  ".25s"),
        (500,  ".5s"),
        (1000, "1s")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flash Duration")
                .font(.custom("Roboto-Regular", size: 16))
            
            HStack(spacing: 14) {
                ForEach(options, id: \.value) { option in
                    Button {
                        selectedDuration = option.value
                        lightHaptic()
                    } label: {
                        Text(option.label)
                            .font(.custom("Roboto-SemiBold", size: 14))
                            .foregroundColor(foregroundColor(for: option.value))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(backgroundColor(for: option.value))
                                    .overlay(
                                        Circle()
                                            .stroke(strokeColor(for: option.value), lineWidth: 2.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    private func backgroundColor(for value: Int) -> Color {
        if value == selectedDuration {
            return settings.flashColor
        } else {
            // fixed gray: RGB 142,142,147
            return Color(
                red:   199.0/255.0,
                green: 199.0/255.0,
                blue:  204.0/255.0
            )
        }
    }

    
    
    private func strokeColor(for value: Int) -> Color {
        guard value == selectedDuration else { return .clear }
        return colorScheme == .dark ? .white : .black
    }
    
    
    private func foregroundColor(for value: Int) -> Color {
        if value == selectedDuration {
            return .white        // white text regardless of light/dark mode
        } else {
            return .primary      // default system text color for unselected
        }
    }
}
