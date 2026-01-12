import Foundation
import SwiftUI
#if canImport(Combine)
import Combine
#endif
#if canImport(WatchKit)
import WatchKit
#endif

#if canImport(WatchKit)
@MainActor
final class ExtendedRuntimeKeeper: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
#if canImport(Combine)
    let objectWillChange = ObservableObjectPublisher()
#endif
    private var session: WKExtendedRuntimeSession?
    private var lastInvalidationUptime: TimeInterval = 0
    private var stopTask: Task<Void, Never>?
    private let graceInterval: TimeInterval = 12.0

    func update(shouldRun: Bool) {
        if shouldRun {
            stopTask?.cancel()
            stopTask = nil
            startIfNeeded()
        } else {
            scheduleStopIfNeeded()
        }
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

    private func scheduleStopIfNeeded() {
        guard session != nil else { return }
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(graceInterval * 1_000_000_000))
            await self?.invalidate()
        }
    }

    private func invalidate() {
        stopTask?.cancel()
        stopTask = nil
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
            stopTask?.cancel()
            stopTask = nil
        }
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        if session === extendedRuntimeSession {
            session = nil
            lastInvalidationUptime = ProcessInfo.processInfo.systemUptime
            stopTask?.cancel()
            stopTask = nil
        }
    }
}
#else
@MainActor
final class ExtendedRuntimeKeeper: ObservableObject {
    func update(shouldRun: Bool) {
    }
}
#endif
