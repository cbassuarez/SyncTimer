import SwiftUI

/// Shrinks & centers a phone-sized layout inside iPad/window safe-area.
/// It *hard-bounds* the content to a fixed design canvas, then scales down to fit.
struct PhoneFit<Content: View>: View {
    let designSize: CGSize            // e.g. 390x844 for iPhone 14/15
    var extraShrink: CGFloat = 1.0    // e.g. 0.92 to shrink an extra 8%
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            // Fit inside the safe-area box
            let availW = max(1, geo.size.width  - (insets.leading + insets.trailing))
            let availH = max(1, geo.size.height - (insets.top + insets.bottom))
            // Scale to *fit height or width*, then apply optional extra shrink
            let fitScale = min(availW / designSize.width, availH / designSize.height) * extraShrink
            // Final pixel size we’ll occupy after scaling
            let fittedW = designSize.width  * fitScale
            let fittedH = designSize.height * fitScale

            ZStack {
                // Letterbox background if you want one:
                // Color.black.opacity(0.02)
                content()
                    // Lock the phone canvas so internal .infinity frames can’t overflow
                    .frame(width: designSize.width, height: designSize.height)
                    .scaleEffect(fitScale, anchor: .center)
                    .clipped() // in case internals still try to spill
            }
            // Center the scaled canvas in the safe region, then pad back out to full window
            .frame(width: fittedW, height: fittedH, alignment: .center)
            .frame(width: availW, height: availH, alignment: .center)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .frame(width: geo.size.width, height: geo.size.height)
            .ignoresSafeArea()
        }
    }
}
