import SwiftUI
import UIKit

/// Physically scales a fixed-size SwiftUI canvas to fit inside iPad safe area.
/// Ensures the hosted view is *intrinsically* sized to `designSize` before scaling,
/// preventing "masked/cropped" behavior.
struct ScaledHosting<Content: View>: UIViewControllerRepresentable {
    let designSize: CGSize          // e.g., 390x844 (iPhone 14/15)
    var extraShrink: CGFloat = 1.0  // e.g., 0.92 for a bit more breathing room
    @ViewBuilder var content: () -> Content

    // Wrap the app content in a fixed-size canvas so it reports intrinsic size.
    private var fixedRoot: some View {
        content()
            .frame(width: designSize.width, height: designSize.height, alignment: .center)
            .fixedSize()            // <- critical: make it intrinsic
            .clipped()              // keep internals within the canvas
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIHostingController(rootView: AnyView(fixedRoot))
        host.view.backgroundColor = .clear
        // Make hosting view size to its intrinsic content instead of filling parent.
        if #available(iOS 16.0, *) {
            host.sizingOptions = [.intrinsicContentSize]
        }

        // Start at the design size; we'll transform later.
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.bounds = CGRect(origin: .zero, size: designSize)
        host.view.frame  = CGRect(origin: .zero, size: designSize)

        let container = UIViewController()
        container.view.backgroundColor = .clear
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let host = uiViewController.children.first as? UIHostingController<AnyView> else { return }
        host.rootView = AnyView(fixedRoot)

        // Defer until layout so safeAreaInsets are valid
        DispatchQueue.main.async {
            guard let view = uiViewController.view else { return }
            let insets = view.safeAreaInsets
            let availW = max(1, view.bounds.width  - (insets.left + insets.right))
            let availH = max(1, view.bounds.height - (insets.top  + insets.bottom))

            let scale = min(availW / designSize.width,
                            availH / designSize.height) * max(0.1, extraShrink)

            host.view.transform = .identity
            host.view.bounds = CGRect(origin: .zero, size: designSize)
            host.view.center = CGPoint(x: insets.left + availW/2, y: insets.top + availH/2)
            host.view.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
}
