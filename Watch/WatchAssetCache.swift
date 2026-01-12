import Foundation
#if os(watchOS)
import UIKit

final class WatchAssetCache {
    static let shared = WatchAssetCache()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private lazy var baseURL: URL = {
        let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchAssets", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {}

    func image(for id: UUID) -> UIImage? {
        if let cached = memory.object(forKey: id.uuidString as NSString) {
            return cached
        }
        let url = assetURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        memory.setObject(image, forKey: id.uuidString as NSString)
        return image
    }

    @discardableResult
    func store(data: Data, id: UUID) -> UIImage? {
        let url = assetURL(for: id)
        try? data.write(to: url, options: [.atomic])
        guard let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: id.uuidString as NSString)
        return image
    }

    private func assetURL(for id: UUID) -> URL {
        baseURL.appendingPathComponent("\(id.uuidString).bin")
    }
}
#endif
