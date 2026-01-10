import Foundation
import SwiftUI

// QA checklist:
// 1. Fresh install: no Whats New during onboarding; once onboarding completes, it should only show if version differs.
// 2. Update 0.8→0.9: shows once.
// 3. Build increment (same version): does NOT show.
// 4. Update while backgrounded: shows on next foreground (if idle).
// 5. Timer running: does not show; shows after stop when idle.
// 6. Any modal presented: does not show; shows later when none are presented.
// 7. Cue sheet edit view: does not show; shows later when exit.
// 8. Join flow active: does not show; shows later.
// 9. About → What’s New opens the sheet any time.
// 10. Reduce Motion: no draw effect.
// 11. iPhone: haptics on CTA; iPad/Mac: no haptics.
// 12. Dynamic Type XXL: no truncation, scrolls.

@MainActor
final class WhatsNewController: ObservableObject {
    @AppStorage("whatsNew.lastSeenVersion") private var lastSeenVersion: String = ""
    @AppStorage("whatsNew.pendingVersionToShow") private var pendingVersionToShow: String = ""
    @AppStorage("whatsNew.hasLaunchedBefore") private var hasLaunchedBefore: Bool = false

    @Published var isPresented: Bool = false
    @Published var manualPresentationRequested: Bool = false

    static var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    func requestManualPresentation() {
        manualPresentationRequested = true
    }

    func evaluatePresentationEligibility(
        currentVersion: String,
        isIdle: Bool,
        isOnboardingVisible: Bool,
        isPresentingModal: Bool,
        isJoinFlowActive: Bool,
        hasContent: Bool,
        reason: String
    ) {
        guard currentVersion.isEmpty == false else { return }

        if !hasLaunchedBefore {
            hasLaunchedBefore = true
            if lastSeenVersion.isEmpty {
                lastSeenVersion = currentVersion
            }
            debugLog("first launch → skip", reason: reason)
            return
        }

        if lastSeenVersion.isEmpty {
            lastSeenVersion = currentVersion
            debugLog("missing lastSeen → seed", reason: reason)
            return
        }

        let isNewVersion = currentVersion != lastSeenVersion
        let shouldQueue = !isIdle || isOnboardingVisible || isPresentingModal || isJoinFlowActive

        if shouldQueue {
            if isNewVersion {
                pendingVersionToShow = currentVersion
            }
            debugLog("queued (not idle)", reason: reason)
            return
        }

        guard isPresented == false else { return }

        let hasPending = pendingVersionToShow == currentVersion
        guard isNewVersion || hasPending else {
            debugLog("no new version", reason: reason)
            return
        }

        guard hasContent else {
            if isNewVersion {
                lastSeenVersion = currentVersion
            }
            pendingVersionToShow = ""
            debugLog("missing content → skip", reason: reason)
            return
        }

        isPresented = true
        debugLog("present", reason: reason)
    }

    func markSeen(currentVersion: String) {
        guard currentVersion.isEmpty == false else { return }
        lastSeenVersion = currentVersion
        pendingVersionToShow = ""
    }

    func clearPending() {
        pendingVersionToShow = ""
    }

    #if DEBUG
    private func debugLog(_ message: String, reason: String) {
        print("[WhatsNew] \(message) (\(reason))")
    }
    #else
    private func debugLog(_: String, reason: String) { }
    #endif
}
