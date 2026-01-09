import Foundation
import SwiftUI

@MainActor
final class WhatsNewCoordinator: ObservableObject {
    @AppStorage("whatsnew.lastSeenVersion") private var lastSeenVersion: String = ""
    @Published var isPresented: Bool = false
    private var didCheck = false

    static var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    func checkAndPresentIfNeeded(currentVersion: String) {
        guard didCheck == false else { return }
        didCheck = true

        guard currentVersion.isEmpty == false else { return }

        if lastSeenVersion.isEmpty {
            lastSeenVersion = currentVersion
            return
        }

        guard lastSeenVersion != currentVersion else { return }

        if isMajorUpdate(from: lastSeenVersion, to: currentVersion) {
            isPresented = true
        } else {
            lastSeenVersion = currentVersion
        }
    }

    func forcePresent(currentVersion: String) {
        guard currentVersion.isEmpty == false else { return }
        isPresented = true
    }

    func markSeen(currentVersion: String) {
        guard currentVersion.isEmpty == false else { return }
        lastSeenVersion = currentVersion
    }

    private func isMajorUpdate(from oldVersion: String, to newVersion: String) -> Bool {
        let overrides: Set<String> = ["0.9"]
        let normalizedNew = Self.normalizedMajorMinor(from: newVersion)
        if overrides.contains(normalizedNew) { return true }

        guard let old = SemVer(oldVersion), let new = SemVer(newVersion) else { return false }

        if new.major > old.major { return true }
        if new.major == 0 && old.major == 0 && new.minor > old.minor { return true }
        return false
    }

    private static func normalizedMajorMinor(from version: String) -> String {
        let parts = version.split(separator: ".")
        guard let major = parts.first else { return version }
        let minor = parts.dropFirst().first ?? "0"
        return "\(major).\(minor)"
    }
}

private struct SemVer: Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        let parts = raw.split(separator: ".").map(String.init)
        guard let major = Int(parts[safe: 0] ?? "0"),
              let minor = Int(parts[safe: 1] ?? "0"),
              let patch = Int(parts[safe: 2] ?? "0") else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
