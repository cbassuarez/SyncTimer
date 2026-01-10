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
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastSeenVersion = "whatsNew.lastSeenVersion"
        static let lastSeenBuild = "whatsNew.lastSeenBuild"
        static let pendingVersionToShow = "whatsNew.pendingVersionToShow"
        static let pendingBuildToShow = "whatsNew.pendingBuildToShow"
    }

    private var lastSeenVersion: String {
        get { defaults.string(forKey: Keys.lastSeenVersion) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastSeenVersion) }
    }

    private var lastSeenBuild: String {
        get { defaults.string(forKey: Keys.lastSeenBuild) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastSeenBuild) }
    }

    private var pendingVersionToShow: String {
        get { defaults.string(forKey: Keys.pendingVersionToShow) ?? "" }
        set { defaults.set(newValue, forKey: Keys.pendingVersionToShow) }
    }

    private var pendingBuildToShow: String {
        get { defaults.string(forKey: Keys.pendingBuildToShow) ?? "" }
        set { defaults.set(newValue, forKey: Keys.pendingBuildToShow) }
    }

    @Published var isPresented: Bool = false
    @Published var manualPresentationRequested: Bool = false

    static var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static var currentBuildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    private var debugForceWhatsNew: Bool {
#if DEBUG
        let value = Bundle.main.infoDictionary?["DEBUG_FORCE_WHATS_NEW"]
        if let boolValue = value as? Bool { return boolValue }
        if let stringValue = value as? String {
            return stringValue == "1" || stringValue.lowercased() == "true"
        }
#endif
        return false
    }

    func requestManualPresentation() {
        manualPresentationRequested = true
    }

    func evaluatePresentationEligibility(
        currentVersion: String,
        currentBuild: String,
        isIdle: Bool,
        isOnboardingVisible: Bool,
        isPresentingModal: Bool,
        isJoinFlowActive: Bool,
        hasContent: Bool,
        reason: String
    ) {
        guard currentVersion.isEmpty == false else { return }

        let isNewVersion = currentVersion != lastSeenVersion
        let isNewBuild = currentBuild != lastSeenBuild
        let isNewRelease = isNewVersion || isNewBuild || debugForceWhatsNew
        let shouldQueue = !isIdle || isOnboardingVisible || isPresentingModal || isJoinFlowActive

        if shouldQueue {
            if isNewRelease {
                pendingVersionToShow = currentVersion
                pendingBuildToShow = currentBuild
            }
            debugLog("queued (not idle)", reason: reason)
            return
        }

        guard isPresented == false else { return }

        let hasPending = pendingVersionToShow == currentVersion && pendingBuildToShow == currentBuild
        guard isNewRelease || hasPending else {
            debugLog("no new version", reason: reason)
            return
        }

        guard hasContent else {
            if isNewRelease {
                lastSeenVersion = currentVersion
                lastSeenBuild = currentBuild
            }
            pendingVersionToShow = ""
            pendingBuildToShow = ""
            debugLog("missing content → skip", reason: reason)
            return
        }

        isPresented = true
        debugLog("present", reason: reason)
    }

    func markSeen(currentVersion: String, currentBuild: String) {
        guard currentVersion.isEmpty == false else { return }
        lastSeenVersion = currentVersion
        lastSeenBuild = currentBuild
        pendingVersionToShow = ""
        pendingBuildToShow = ""
    }

    func clearPending() {
        pendingVersionToShow = ""
        pendingBuildToShow = ""
    }

    #if DEBUG
    private func debugLog(_ message: String, reason: String) {
        print("[WhatsNew] \(message) (\(reason))")
    }
    #else
    private func debugLog(_: String, reason: String) { }
    #endif
}
