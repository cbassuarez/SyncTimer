import SwiftUI

/// A true “metallic” plate background, with
/// • a soft base tint per tier
/// • a subtle tileable noise overlay
/// • an animated, random mesh gradient (for iridescence)
/// • a gentle sweep shimmer on appear / kind-change
/// 
struct MetallicPlate: View {
    enum Kind { case platinum, gold, silver, bronze }
    let kind: Kind

    // mesh resolution (n×n)
    private let meshSize = 4

    // a palette of bright “crystal” colors
    private let palette: [Color] = [
        .cyan, .mint, .pink, .purple, .orange, .yellow, .blue, .green, .teal
    ]

    // changing these via regenerate()
    @State private var meshPoints: [SIMD2<Float>] = []
    @State private var meshColors: [Color] = []
    @State private var animateSweep = false

    var body: some View {
        ZStack {
            // ① base tint
            Rectangle()
            .fill(baseFill)

            // ② brushed‐metal noise
            Image("metal_noise")
                .resizable(resizingMode: .tile)
                .opacity(0.22)
            
            // ③ only-for-platinum mesh overlay
            if kind == .platinum {
                MeshGradient(
                    width: meshSize, height: meshSize,
                    points: meshPoints, colors: meshColors
                )
                .opacity(0.12)
                .blendMode(.overlay)
            }
            
            // ④ shimmer sweep
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .clear, .white.opacity(0.4)],
                        startPoint: animateSweep ? .leading : .trailing,
                        endPoint:   animateSweep ? .trailing : .leading
                    )
                )
                .opacity(0.15)
                .blendMode(.overlay)
                .animation(.easeOut(duration: 1.2), value: animateSweep)
        }
        // force SwiftUI to render all children to an offscreen buffer
        .drawingGroup()
        // then clip to your rounded rect
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear(perform: regenerate)
        .onChange(of: kind) { _ in regenerate() }
    }
    /// Base gradient per metal tier
    private var baseFill: some ShapeStyle {
        switch kind {
        case .platinum:
            return LinearGradient(
                colors: [Color.white.opacity(0.85), Color.gray.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .gold:
            return LinearGradient(
                colors: [Color.yellow.opacity(0.7), Color.orange.opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .silver:
            return LinearGradient(
                colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .bronze:
            // More traditional copper/bronze tones
                    return LinearGradient(
                        colors: [
                            Color(red: 205/255, green: 127/255, blue:  50/255).opacity(0.8),
                            Color(red: 184/255, green: 115/255, blue:  35/255).opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint:   .bottomTrailing
                    )
        }
    }

    /// Generate a new random mesh + trigger shimmer
    private func regenerate() {
        let count = meshSize * meshSize
        meshPoints = (0..<count).map { _ in
            SIMD2<Float>(Float.random(in: 0...1), Float.random(in: 0...1))
        }
        meshColors = (0..<count).map { _ in
            palette.randomElement()!
        }
        // kick off the sweep
        animateSweep.toggle()
    }
}
