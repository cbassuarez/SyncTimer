import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ scene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let ok = QuickActionRouter.shared.handle(shortcutItem)
        completionHandler(ok)
    }
}
