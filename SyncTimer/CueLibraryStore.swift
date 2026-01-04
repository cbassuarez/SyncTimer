//
//  CueLibraryStore.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation
import UniformTypeIdentifiers

@MainActor
final class CueLibraryStore: ObservableObject {
    static let shared = CueLibraryStore()
    private init() { try? loadIndex(suppressPublish: true); primed = true }

    @Published private(set) var index = CueLibraryIndex()
    @Published private(set) var sheets: [UUID: CueSheet] = [:]
    private var primed = false

    private func publish() {
        guard primed else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // reassign to trigger @Published without doing it during the current view update
            self.index  = self.index
            self.sheets = self.sheets
        }
    }
}



extension UTType {
    static var cueXML: UTType { UTType(importedAs: "com.stagedevices.synctimer.cue-xml") }
}
// MARK: - Uniquing helpers
extension CueLibraryStore {
    // Paths
    private var baseURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CueSheets", isDirectory: true)
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
    
        
    // MARK: CRUD
    func save(_ sheet: CueSheet, intoFolderID folderID: UUID? = nil, tags: [String]) throws {
        var s = sheet
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
        var s = try CueXML.read(data)
        s.title = renameTo ?? s.title
        s.fileName = sanitized((renameTo ?? s.title) + ".xml")

        try save(s, intoFolderID: folderID, tags: tags)   // save() ends with publish()
        return s
    }


    func load(meta: CueLibraryIndex.SheetMeta) throws -> CueSheet {
        let data = try Data(contentsOf: fileURL(for: meta))
        var s = try CueXML.read(data)
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
        return try metas.map { meta in fileURL(for: meta) }
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
