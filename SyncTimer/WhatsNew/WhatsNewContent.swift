import Foundation

enum WhatsNewAction: String, Codable {
    case openJoinQR
    case openCueSheetsCreateBlank
    case openReleaseNotes
}

struct WhatsNewCard: Codable, Identifiable {
    let id: String
    let symbol: String
    let headline: String
    let body: String
    let ctaTitle: String
    let ctaAction: WhatsNewAction
}

struct WhatsNewVersionEntry: Codable, Identifiable {
    let version: String
    let title: String
    let subtitle: String
    let lede: String
    let cards: [WhatsNewCard]
    let bullets: [String]?

    var id: String { version }
}

struct WhatsNewIndex: Codable {
    let currentVersion: String?
    let versions: [WhatsNewVersionEntry]

    func entry(for version: String) -> WhatsNewVersionEntry? {
        if let explicit = currentVersion,
           let match = versions.first(where: { $0.version == explicit }) {
            return match
        }
        if let match = versions.first(where: { $0.version == version }) {
            return match
        }
        return versions.last
    }
}

enum WhatsNewContentLoader {
    static func load(bundle: Bundle = .main) -> WhatsNewIndex? {
        guard let url = bundle.url(forResource: "WhatsNew", withExtension: "plist") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = PropertyListDecoder()
            return try decoder.decode(WhatsNewIndex.self, from: data)
        } catch {
            #if DEBUG
            print("[WhatsNew] Failed to load WhatsNew.plist: \(error)")
            #endif
            return nil
        }
    }
}
