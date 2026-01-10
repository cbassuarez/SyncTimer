import SwiftUI
import UIKit

enum QuickAction: Equatable {
    case startResume
    case countdown(Int)
    case openCueSheets
    case joinRoom
}

@MainActor
final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()
    @Published var pending: QuickAction?

    func handle(_ item: UIApplicationShortcutItem) -> Bool {
        let type = item.type
        switch type {
        case "com.stagedevices.synctimer.startResume":
            pending = .startResume
        case "com.stagedevices.synctimer.cuesheets":
            pending = .openCueSheets
        case "com.stagedevices.synctimer.join":
            pending = .joinRoom
        default:
            if type.contains("countdown.") {
                let sec = Int(type.split(separator: ".").last ?? "") ?? 0
                pending = .countdown(sec)
            } else {
                return false
            }
        }
        #if DEBUG
        print("[QuickAction] received \(type)")
        #endif
        return true
    }
}
