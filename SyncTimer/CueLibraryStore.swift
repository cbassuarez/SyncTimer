//
//  CueLibraryStore.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation
import UniformTypeIdentifiers
import UIKit
import CryptoKit

@MainActor
final class CueLibraryStore: ObservableObject {
    static let shared = CueLibraryStore()
    private init() { try? loadIndex(suppressPublish: true); primed = true }

    @Published private(set) var index = CueLibraryIndex()
    @Published private(set) var sheets: [UUID: CueSheet] = [:]
    private var primed = false
    // Decoded image cache to keep overlay rendering off the main thread.
    private static let imageCache = NSCache<NSUUID, UIImage>()

    private func publish() {
        guard primed else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // reassign to trigger @Published without doing it during the current view update
            self.index  = self.index
            self.sheets = self.sheets
        }
    }

    func badgeLabel(for sheetID: UUID) -> String? {
        guard let meta = index.sheets[sheetID] else { return nil }
        let title = meta.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        let fileName = meta.fileName
        guard !fileName.isEmpty else { return nil }
        return URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }
}



extension UTType {
    static var cueXML: UTType { UTType(importedAs: "com.stagedevices.synctimer.cue-xml") }
}
// MARK: - Uniquing helpers
extension CueLibraryStore {
    struct AssetMeta: Codable, Equatable {
        var id: UUID
        var mime: String
        var ext: String
        var sha256: String
        var byteCount: Int
        var created: Date
    }
    // Paths
    private var baseURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CueSheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var assetsURL: URL {
        let url = baseURL.appendingPathComponent("Assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var indexURL: URL { baseURL.appendingPathComponent("index.json") }
    func fileURL(for meta: CueLibraryIndex.SheetMeta) -> URL { baseURL.appendingPathComponent(meta.fileName) }
    // MARK: - Delete sheet (minimal: remove file + index maps)
        func delete(metaID: UUID) throws {
            guard let meta = index.sheets[metaID] else { return }
            // Remove file from disk (ignore if missing)
            let url = fileURL(for: meta)
            _ = try? FileManager.default.removeItem(at: url)
            // Update index maps (folders cleanup will be added once folder model is aligned)
            index.sheets.removeValue(forKey: metaID)
            index.recents.removeAll { $0 == metaID }
            try persistIndex()
            garbageCollectUnusedAssets()
            publish()
        }
    
    // MARK: - Move sheet to folder (nil = root)
        func moveSheet(_ id: UUID, toFolderID folderID: UUID?) throws {
            // 1) Remove occurrences from every folder in the tree
            removeSheetID(id, from: &index.root)
            // 2) Append to destination or root
            if let fid = folderID {
                let placed = append(sheetID: id, toFolderID: fid, node: &index.root)
                if !placed, !index.root.sheetIDs.contains(id) {
                    index.root.sheetIDs.append(id) // fallback to root if folder not found
                }
            } else {
                if !index.root.sheetIDs.contains(id) { index.root.sheetIDs.append(id) }
            }
            try persistIndex()
            publish()
        }
    
    // MARK: - Folders (by UUID, recursive over CueLibraryIndex.Folder)
        @discardableResult
        func createFolder(name: String, under parentID: UUID?) throws -> UUID {
            let new = CueLibraryIndex.Folder(id: UUID(), name: name, children: [], sheetIDs: [])
            if let pid = parentID {
                let inserted = insert(folder: new, under: pid, node: &index.root)
                if !inserted { index.root.children.append(new) } // fallback to root
            } else {
                index.root.children.append(new)
            }
            try persistIndex()
            publish()
            return new.id
        }
        private func insert(folder new: CueLibraryIndex.Folder, under target: UUID, node: inout CueLibraryIndex.Folder) -> Bool {
            if node.id == target { node.children.append(new); return true }
            for i in node.children.indices {
                if insert(folder: new, under: target, node: &node.children[i]) { return true }
            }
            return false
        }
        func renameFolder(id: UUID, to newName: String) throws {
            guard rename(folderID: id, to: newName, in: &index.root) else { return }
            try persistIndex()
            publish()
        }
        private func rename(folderID: UUID, to newName: String, in node: inout CueLibraryIndex.Folder) -> Bool {
            if node.id == folderID { node.name = newName; return true }
            for i in node.children.indices {
                if rename(folderID: folderID, to: newName, in: &node.children[i]) { return true }
            }
            return false
        }
        func deleteFolder(id: UUID) throws {
            guard deleteFolder(id: id, in: &index.root) else { return }
            try persistIndex()
            publish()
        }
        private func deleteFolder(id: UUID, in node: inout CueLibraryIndex.Folder) -> Bool {
            for i in node.children.indices {
                if node.children[i].id == id {
                    node.children.remove(at: i)
                    return true
                } else if deleteFolder(id: id, in: &node.children[i]) {
                    return true
                }
            }
            return false
        }
    
    // MARK: - Assets
    private func assetMetaURL(for id: UUID) -> URL { assetsURL.appendingPathComponent("\(id.uuidString).json") }
    private func assetDataURL(for meta: AssetMeta) -> URL { assetsURL.appendingPathComponent("\(meta.id.uuidString).\(meta.ext)") }

    func assetMeta(id: UUID) -> AssetMeta? {
        let url = assetMetaURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AssetMeta.self, from: data)
    }

    func assetData(id: UUID) -> Data? {
        guard let meta = assetMeta(id: id) else { return nil }
        return try? Data(contentsOf: assetDataURL(for: meta))
    }

    nonisolated static func assetDataFromDisk(id: UUID) -> Data? {
        guard let meta = assetMetaFromDisk(id: id) else { return nil }
        let dataURL = assetDataURLFromDisk(for: meta)
        return try? Data(contentsOf: dataURL)
    }

    nonisolated static func assetMetaFromDisk(id: UUID) -> AssetMeta? {
        let metaURL = assetMetaURLFromDisk(for: id)
        guard let metaData = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(AssetMeta.self, from: metaData)
    }

    nonisolated static func exportAssetBlobFromDisk(id: UUID) -> CueXML.AssetBlob? {
        guard let meta = assetMetaFromDisk(id: id),
              let data = try? Data(contentsOf: assetDataURLFromDisk(for: meta)) else { return nil }
        let sha = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        return CueXML.AssetBlob(id: meta.id, mime: meta.mime, sha256: sha, data: data)
    }

    private nonisolated static func assetsBaseURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CueSheets", isDirectory: true)
        let assetsURL = baseURL.appendingPathComponent("Assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        return assetsURL
    }

    private nonisolated static func assetMetaURLFromDisk(for id: UUID) -> URL {
        assetsBaseURL().appendingPathComponent("\(id.uuidString).json")
    }

    private nonisolated static func assetDataURLFromDisk(for meta: AssetMeta) -> URL {
        assetsBaseURL().appendingPathComponent("\(meta.id.uuidString).\(meta.ext)")
    }

    nonisolated static func cachedImage(id: UUID) -> UIImage? {
        imageCache.object(forKey: id as NSUUID)
    }

    nonisolated static func cacheImage(_ image: UIImage, for id: UUID) {
        imageCache.setObject(image, forKey: id as NSUUID)
    }

    func prefetchImages(in sheet: CueSheet) {
        let assetIDs = Set(sheet.events.compactMap { event in
            if case .image(let payload)? = event.payload { return payload.assetID }
            return nil
        })
        guard !assetIDs.isEmpty else { return }
        Task.detached(priority: .utility) {
            for id in assetIDs {
                if CueLibraryStore.cachedImage(id: id) != nil { continue }
                guard let data = CueLibraryStore.assetDataFromDisk(id: id),
                      let decoded = UIImage(data: data) else { continue }
                CueLibraryStore.cacheImage(decoded, for: id)
            }
        }
    }

    private func hasAlpha(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        switch cg.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }

    private func redraw(_ image: UIImage, maxEdge: CGFloat = 2048) -> UIImage? {
        var targetSize = image.size
        let longest = max(targetSize.width, targetSize.height)
        if longest > maxEdge, longest > 0 {
            let scale = maxEdge / longest
            targetSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    @discardableResult
    func ingestImage(data: Data, preferLossy: Bool = true) throws -> UUID {
        guard let ui = UIImage(data: data) else {
            throw NSError(domain: "CueLibraryStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }
        guard let sanitized = redraw(ui) else {
            throw NSError(domain: "CueLibraryStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to redraw image"])
        }
        let alpha = hasAlpha(sanitized)
        var mime = "image/png"
        var ext = "png"
        var encoded = sanitized.pngData() ?? data
        if preferLossy, !alpha, let jpg = sanitized.jpegData(compressionQuality: 0.88) {
            mime = "image/jpeg"
            ext = "jpg"
            encoded = jpg
        }
        let sha = SHA256.hash(data: encoded).compactMap { String(format: "%02x", $0) }.joined()
        let id = UUID()
        let meta = AssetMeta(id: id, mime: mime, ext: ext, sha256: sha, byteCount: encoded.count, created: Date())
        try encoded.write(to: assetDataURL(for: meta), options: .atomic)
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: assetMetaURL(for: id), options: .atomic)
        return id
    }

    func exportAssetBlob(id: UUID) -> CueXML.AssetBlob? {
        guard let meta = assetMeta(id: id), let data = try? Data(contentsOf: assetDataURL(for: meta)) else { return nil }
        let sha = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        return CueXML.AssetBlob(id: meta.id, mime: meta.mime, sha256: sha, data: data)
    }

    func assetBlobs(for sheet: CueSheet) -> [CueXML.AssetBlob] {
        let assetIDs = Set(sheet.events.compactMap { event in
            if case .image(let payload)? = event.payload { return payload.assetID }
            return nil
        })
        return assetIDs.compactMap { exportAssetBlob(id: $0) }
    }

    nonisolated static func assetBlobsFromDisk(for sheet: CueSheet) -> [CueXML.AssetBlob] {
        let assetIDs = Set(sheet.events.compactMap { event in
            if case .image(let payload)? = event.payload { return payload.assetID }
            return nil
        })
        return assetIDs.compactMap { exportAssetBlobFromDisk(id: $0) }
    }

    func garbageCollectUnusedAssets() {
        let used = referencedAssetIDs()
        guard let metas = try? FileManager.default.contentsOfDirectory(at: assetsURL, includingPropertiesForKeys: nil) else { return }
        for url in metas where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let meta = try? JSONDecoder().decode(AssetMeta.self, from: data) else { continue }
            if !used.contains(meta.id) {
                _ = try? FileManager.default.removeItem(at: assetDataURL(for: meta))
                _ = try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func referencedAssetIDs() -> Set<UUID> {
        var ids: Set<UUID> = []
        for meta in index.sheets.values {
            let url = fileURL(for: meta)
            guard let data = try? Data(contentsOf: url),
                  let sheet = try? CueXML.read(data) else { continue }
            for e in sheet.events {
                if case .image(let payload)? = e.payload {
                    ids.insert(payload.assetID)
                }
            }
        }
        return ids
    }

    func ingestEmbeddedAssets(for sheet: inout CueSheet, blobs: [CueXML.AssetBlob]) {
        guard !blobs.isEmpty else { return }
        var remap: [UUID: UUID] = [:]
        for blob in blobs {
            var targetID = blob.id
            if let existing = assetMeta(id: blob.id) {
                if existing.sha256 != blob.sha256 {
                    targetID = UUID()
                }
            }
            let ext: String
            if blob.mime.contains("jpeg") { ext = "jpg" }
            else if blob.mime.contains("png") { ext = "png" }
            else { ext = URL(fileURLWithPath: blob.mime).pathExtension.isEmpty ? "bin" : URL(fileURLWithPath: blob.mime).pathExtension }
            let meta = AssetMeta(id: targetID, mime: blob.mime, ext: ext, sha256: blob.sha256, byteCount: blob.data.count, created: Date())
            try? blob.data.write(to: assetDataURL(for: meta), options: .atomic)
            if let encoded = try? JSONEncoder().encode(meta) {
                try? encoded.write(to: assetMetaURL(for: meta.id), options: .atomic)
            }
            if targetID != blob.id {
                remap[blob.id] = targetID
            }
        }
        guard !remap.isEmpty else { return }
        for idx in sheet.events.indices {
            if case .image(let payload)? = sheet.events[idx].payload,
               let newID = remap[payload.assetID] {
                sheet.events[idx].payload = .image(.init(assetID: newID, contentMode: payload.contentMode, caption: payload.caption))
            }
        }
    }

    nonisolated static func ingestEmbeddedAssetsFromDisk(for sheet: inout CueSheet, blobs: [CueXML.AssetBlob]) {
        guard !blobs.isEmpty else { return }
        var remap: [UUID: UUID] = [:]
        for blob in blobs {
            var targetID = blob.id
            if let existing = assetMetaFromDisk(id: blob.id) {
                if existing.sha256 != blob.sha256 {
                    targetID = UUID()
                }
            }
            let ext: String
            if blob.mime.contains("jpeg") { ext = "jpg" }
            else if blob.mime.contains("png") { ext = "png" }
            else { ext = URL(fileURLWithPath: blob.mime).pathExtension.isEmpty ? "bin" : URL(fileURLWithPath: blob.mime).pathExtension }
            let meta = AssetMeta(id: targetID, mime: blob.mime, ext: ext, sha256: blob.sha256, byteCount: blob.data.count, created: Date())
            try? blob.data.write(to: assetDataURLFromDisk(for: meta), options: .atomic)
            if let encoded = try? JSONEncoder().encode(meta) {
                try? encoded.write(to: assetMetaURLFromDisk(for: meta.id), options: .atomic)
            }
            if targetID != blob.id {
                remap[blob.id] = targetID
            }
        }
        guard !remap.isEmpty else { return }
        for idx in sheet.events.indices {
            if case .image(let payload)? = sheet.events[idx].payload,
               let newID = remap[payload.assetID] {
                sheet.events[idx].payload = .image(.init(assetID: newID, contentMode: payload.contentMode, caption: payload.caption))
            }
        }
    }

        
    // MARK: CRUD
    func save(_ sheet: CueSheet, intoFolderID folderID: UUID? = nil, tags: [String]) throws {
        var s = sheet
        s = s.normalized()
        // Titles
        if s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s.title = "Untitled"
        }
        s.title = uniqueTitle(for: s.title, excluding: s.id)

        // File name (ensure extension, then unique)
        if s.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s.fileName = s.title + ".xml" // or your sanitizer if you have one
        }
        s.fileName = uniqueFileName(for: s.fileName, excluding: s.id)

        let now = Date()
        s.modified = now
        let data = CueXML.write(s)
        let fileName = s.fileName.isEmpty ? sanitized("\(s.title).xml") : s.fileName
        let id = s.id
        try data.write(to: baseURL.appendingPathComponent(fileName), options: .atomic)
        sheets[id] = s
        let meta = CueLibraryIndex.SheetMeta(id: id, fileName: fileName, title: s.title, tags: tags, pinned: false, created: s.created, modified: s.modified, lastOpened: s.lastOpened)
        self.index.sheets[id] = meta
        appendSheet(id, toFolderID: folderID)            // <- mutate tree here
        self.index.recents.removeAll(where: { $0 == id })
        self.index.recents.insert(id, at: 0)
        if self.index.recents.count > 50 { self.index.recents.removeLast(self.index.recents.count - 50) }
        
        try persistIndex()
        publish()
    }

    func importXML(from url: URL,
                   intoFolderID folderID: UUID? = nil,
                   renameTo: String? = nil,
                   tags: [String] = []) throws -> CueSheet {
        // Security-scoped access for files coming from outside your container
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        var (s, assets) = try CueXML.readWithAssets(data)
        ingestEmbeddedAssets(for: &s, blobs: assets)
        s.title = renameTo ?? s.title
        s.fileName = sanitized((renameTo ?? s.title) + ".xml")

        try save(s, intoFolderID: folderID, tags: tags)   // save() ends with publish()
        return s
    }


    func load(meta: CueLibraryIndex.SheetMeta) throws -> CueSheet {
        let data = try Data(contentsOf: fileURL(for: meta))
        var (s, assets) = try CueXML.readWithAssets(data)
        ingestEmbeddedAssets(for: &s, blobs: assets)
        s.created = meta.created
        s.modified = meta.modified
        s.fileName = meta.fileName; s.id = meta.id; s.tags = meta.tags; s.lastOpened = Date()
        sheets[s.id] = s
        index.sheets[s.id]?.lastOpened = s.lastOpened
        try persistIndex()
        publish()
        return s
    }

    func exportXML(_ metas: [CueLibraryIndex.SheetMeta]) throws -> [URL] {
        // returns file URLs for the caller to feed into FileExporter; zipping multi-select happens in UI layer
        return try metas.map { meta in
            let url = fileURL(for: meta)
            let data = try Data(contentsOf: url)
            var (sheet, _) = try CueXML.readWithAssets(data)
            var blobs: [CueXML.AssetBlob] = []
            for e in sheet.events {
                if case .image(let payload)? = e.payload, let blob = exportAssetBlob(id: payload.assetID) {
                    blobs.append(blob)
                }
            }
            let xml = CueXML.write(sheet, assets: blobs)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(meta.fileName)
            try xml.write(to: temp, options: .atomic)
            return temp
        }
    }

    // MARK: Index persist
    private func persistIndex() throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
    }
    private func loadIndex(suppressPublish: Bool = false) throws {
            if let data = try? Data(contentsOf: indexURL) {
                index = try JSONDecoder().decode(CueLibraryIndex.self, from: data)
            } else {
                index = CueLibraryIndex()
                try persistIndex()
                if !suppressPublish { publish() }  // <- INIT passes suppressPublish: true
        }
       }

    // Helpers
    private func sanitized(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return n
    }
        // Put this INSIDE the class body, or in: extension CueLibraryStore { ... }
        private func appendSheet(_ sheetID: UUID, toFolderID folderID: UUID?) {
            if let fid = folderID {
                // Try to append into the target folder; if not found, fall back to root.
                let didAppend = append(sheetID: sheetID, toFolderID: fid, node: &self.index.root)
                if !didAppend {
                    if !self.index.root.sheetIDs.contains(sheetID) {
                        self.index.root.sheetIDs.append(sheetID)
                    }
                }
            } else {
                if !self.index.root.sheetIDs.contains(sheetID) {
                    self.index.root.sheetIDs.append(sheetID)
                }
            }
        }
    
    /// Return a title that doesn’t collide with existing sheet titles.
    func uniqueTitle(for desired: String, excluding id: UUID? = nil) -> String {
        let used = Set(index.sheets.values
            .filter { $0.id != id }
            .map { $0.title.trimmingCharacters(in: .whitespaces).lowercased() })
        return bump(desired, within: used)
    }

    /// Return a file name (e.g. "Song.xml") unique across the library.
    /// If it collides, inserts " (n)" **before** the extension.
    func uniqueFileName(for desired: String, excluding id: UUID? = nil) -> String {
        let used = Set(index.sheets.values
            .filter { $0.id != id }
            .compactMap { $0.fileName.trimmingCharacters(in: .whitespaces).lowercased() })
        // Split into stem + extension
        let url = URL(fileURLWithPath: desired)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let uniqueStem = bump(stem, within: used.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }.asSet())
        return ext.isEmpty ? uniqueStem : "\(uniqueStem).\(ext)"
    }

    /// Core “(n)” logic. If `name` exists in `used`, produce "name (1)", "name (2)", etc.
    private func bump(_ name: String, within used: Set<String>) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if !used.contains(lower) { return trimmed }

        let root = stripNumericSuffix(trimmed)
        var n = 1
        var candidate = "\(root) (\(n))"
        while used.contains(candidate.lowercased()) {
            n += 1
            candidate = "\(root) (\(n))"
        }
        return candidate
    }

    /// Turn "Track (3)" → "Track"; leaves other names unchanged.
    private func stripNumericSuffix(_ s: String) -> String {
        let regex = try! NSRegularExpression(pattern: #" \(\d+\)$"#, options: [])
        let range = NSRange(location: 0, length: (s as NSString).length)
        return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

private extension Sequence where Element == String {
    func asSet() -> Set<String> { Set(self) }
}

/// Recursively finds the folder by id and appends the sheet there.
/// - Returns: true if the folder was found and mutated; false otherwise.
@discardableResult
private func append(sheetID: UUID, toFolderID target: UUID, node: inout CueLibraryIndex.Folder) -> Bool {
    if node.id == target {
        if !node.sheetIDs.contains(sheetID) { node.sheetIDs.append(sheetID) }
        return true
    }
    for i in node.children.indices {
        if append(sheetID: sheetID, toFolderID: target, node: &node.children[i]) {
            return true
        }
    }
    return false
}
/// Recursively remove a sheet ID anywhere in the folder tree.
private func removeSheetID(_ id: UUID, from node: inout CueLibraryIndex.Folder) {
    node.sheetIDs.removeAll { $0 == id }
    for i in node.children.indices {
        removeSheetID(id, from: &node.children[i])
    }
}
// One-time bundled installer you can call from anywhere
extension CueLibraryStore {
    /// Import a bundled cuesheet once (guarded by a defaults flag).
    /// - Parameters:
    ///   - resource: basename of the file in your app bundle
    ///   - ext:      default "cuesheet.xml"
    ///   - flag:     bump to force re-install for existing users
    ///    Imports the bundled starter once and returns it when installed,
         /// otherwise returns nil (already installed or not found).
         @discardableResult
    func installBundledStarterOnce(
        resource: String = "Starter Cue Sheet",
        ext: String = "cuesheet.xml",
        flag: String = "SyncTimer_InstalledStarterTemplate_v4"
    ) -> CueSheet? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: flag) == false else { return nil }
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return nil }
        do {
            let s = try importXML(from: url, intoFolderID: nil) // saves as .xml internally
            defaults.set(true, forKey: flag)
            return s
        } catch {
            // swallow; we'll try again next launch
            return nil
        }
    }
}
// MARK: - Lookup helpers for presets / UI
extension CueLibraryStore {
    /// Titles for pickers (disambiguate duplicate titles with file name)
    func allSheetNamesOrIds() -> [String] {
        let metas = index.sheets.values
        let dupTitles = Set(metas.map(\.title).filter { t in metas.filter { $0.title == t }.count > 1 })
        let labels = metas.map { meta -> String in
            dupTitles.contains(meta.title) ? "\(meta.title) – (\(meta.fileName))" : meta.title
        }
        return labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Resolve by UUID string, "Title – (File.xml)" label, exact title, or exact fileName.
    func sheet(namedOrId key: String) -> CueSheet? {
        if let uuid = UUID(uuidString: key), let meta = index.sheets[uuid] {
            return try? load(meta: meta)
        }
        if let meta = index.sheets.values.first(where: { "\($0.title) – (\($0.fileName))" == key }) {
            return try? load(meta: meta)
        }
        if let meta = index.sheets.values.first(where: { $0.title == key }) {
            return try? load(meta: meta)
        }
        if let meta = index.sheets.values.first(where: { $0.fileName == key }) {
            return try? load(meta: meta)
        }
        return nil
    }
}

#if DEBUG
extension CueLibraryStore {
    func debugAssetIDs(limit: Int = 2) -> [UUID] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: assetsURL, includingPropertiesForKeys: nil)) ?? []
        let ids = urls.compactMap { url -> UUID? in
            guard url.pathExtension == "json" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
        return Array(ids.prefix(limit))
    }
}
#endif
