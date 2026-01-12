import Foundation
import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

#if canImport(WatchKit)
@MainActor
final class ExtendedRuntimeKeeper: NSObject, WKExtendedRuntimeSessionDelegate, ObservableObject {
    private var session: WKExtendedRuntimeSession?
    private var lastInvalidationUptime: TimeInterval = 0

    func update(shouldRun: Bool, scenePhase: ScenePhase) {
        let isActive = scenePhase == .active
        if !isActive || !shouldRun {
            invalidate()
            return
        }
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard session == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let backoff: TimeInterval = 2.0
        guard now - lastInvalidationUptime >= backoff else { return }
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start()
        session = newSession
    }

    private func invalidate() {
        session?.invalidate()
        session = nil
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
    }

    func extendedRuntimeSessionDidInvalidate(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        if session === extendedRuntimeSession {
            session = nil
            lastInvalidationUptime = ProcessInfo.processInfo.systemUptime
        }
    }
}
#else
@MainActor
final class ExtendedRuntimeKeeper: ObservableObject {
    func update(shouldRun: Bool, scenePhase: ScenePhase) {
    }
}
#endif
