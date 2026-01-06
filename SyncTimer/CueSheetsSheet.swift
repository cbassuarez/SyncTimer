//
//  CueSheetsSheet.swift — Stable minimal library + loader
//  SyncTimer
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

// MARK: - Header explainer
private var cueSheetsExplainer: some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("How to use Events Sheets")
            .font(.subheadline.weight(.semibold))
        Text("""
Tap a sheet to load a score on your device and any connected devices.
Edit or share from the ••• menu when needed, and use **Load Recent** to reopen past sheets.
""")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)                 // inner - match header card
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    .padding(.horizontal, 12)                 // outer - match header card offset
}
private extension NoteGrid {
    static var subdivisionsOnly: [NoteGrid] { [.quarter, .eighth, .sixteenth, .thirtySecond] }
}


private struct InlineDates: View {
    let created: Date
    let modified: Date

    var body: some View {
        let cal = Calendar.current
        let sameDay = cal.isDate(created, inSameDayAs: modified)

        let createdStr  = created.formatted(date: .abbreviated, time: .omitted)
        let modifiedStr = sameDay
            ? modified.formatted(date: .omitted, time: .shortened)                  // time only if same day
            : "\(modified.formatted(date: .abbreviated, time: .omitted)) \(modified.formatted(date: .omitted, time: .shortened))"

        return HStack(spacing: 6) {
            Text("Created \(createdStr)")
            Text("•")
            Text("Modified \(modifiedStr)")
        }
        .font(.custom("Roboto-Regular", size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

// MARK: - Minimal FileDocument for potential future export (kept here; not used by default)
struct XMLDoc: FileDocument {
    static var readableContentTypes: [UTType] = [.xml]
    var data: Data
    var name: String
    init(data: Data, name: String) { self.data = data; self.name = name }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
        self.name = "CueSheet.xml"
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let w = FileWrapper(regularFileWithContents: data)
        w.preferredFilename = name.hasSuffix(".xml") ? name : (name + ".xml")
        return w
    }
}
extension URL: Identifiable { public var id: String { absoluteString } }

// MARK: - Cue Sheets medium-detent
struct CueSheetsSheet: View {
    @Binding var isPresented: Bool
    var canBroadcast: () -> Bool = { false }
    let onLoad: (CueSheet) -> Void
    let onBroadcast: (CueSheet) -> Void

    // Own the subscription—do NOT use @ObservedObject for a publishing singleton here
    @StateObject private var store = CueLibraryStore.shared


    // UI state
    @State private var searchText: String = ""
    @State private var showingImporter = false
    @State private var shareURL: URL? = nil
    @State private var pendingSheet: CueSheet? = nil
    @State private var editingSheet: CueSheet? = nil
    private let cardRadius: CGFloat = 12  // match Recent/All cards
    @State private var showBroadcastChoice = false

    var body: some View {
        // Snapshot data (filtered). If the store hasn’t primed yet, render empty.
        let sheetsMap = store.index.sheets
        let recentIDs = store.index.recents.uniqued()
        let recentMetas: [CueLibraryIndex.SheetMeta] = recentIDs
            .compactMap { sheetsMap[$0] }
            .filter { filterMatches($0, search: searchText) }
        let allMetas: [CueLibraryIndex.SheetMeta] = Array(sheetsMap.values)
            .filter { filterMatches($0, search: searchText) }
            .sorted { $0.modified > $1.modified }
            
        ScrollView {
            
            VStack(spacing: 14) {
                Color.clear.frame(height: 8) // breathing room under grabber
                
                // Header (matches detent curvature)
                HStack {
                    Text("Events Sheets")
                    .font(.custom("Roboto-SemiBold", size: 24))

                    Spacer()
                    Button { showingImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.custom("Roboto-Regular", size: 16))

                    }
                   
                }
               
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .padding(.horizontal, 16)
                
                // Explainer (below the header)
                    cueSheetsExplainer
                // Search (card radius + material)
                SearchBar(text: $searchText, cornerRadius: cardRadius)
                    .padding(.horizontal, 16)
                
                // Quick actions (pills with same radius/material)
                HStack(spacing: 10) {
                    Button { loadMostRecentIfAny() } label: {
                        Label("Load Recent", systemImage: "clock.arrow.circlepath")
                            .font(.custom("Roboto-Regular", size: 15))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                    Button { newBlank() } label: {
                        Label("New Blank", systemImage: "plus")
                            .font(.custom("Roboto-Regular", size: 15))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                
                // Recent
                if !recentMetas.isEmpty {
                    SectionCard(title: "Recent") {
                        VStack(spacing: 8) {
                            ForEach(recentMetas, id: \.id) { meta in
                                LibraryRow(
                                    meta: meta,
                                    onTap: { load(meta) },
                                    onEdit: { if let s = try? store.load(meta: meta) { editingSheet = s } },
                                    onDuplicate: {
                                        do {
                                            var s = try store.load(meta: meta)   // non-optional; no `if let`
                                            s.id = UUID()
                                            s.fileName = ""                      // force unique filename regeneration
                                            let now = Date()
                                            s.created = now
                                            s.modified = now
                                            try store.save(s, intoFolderID: nil, tags: s.tags)  // will append " (n)" if needed
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } catch {
                                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                                        }
                                    },
                                                                        onDelete: { delete(meta) },
                                    onShare: { share(meta) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                // All
                SectionCard(title: "All") {
                    if allMetas.isEmpty {
                        Text("No sheets found.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(allMetas, id: \.id) { meta in
                                LibraryRow(
                                    meta: meta,
                                    onTap: { load(meta) },
                                    onEdit: { if let s = try? store.load(meta: meta) { editingSheet = s } },
                                    onDuplicate: {
                                        do {
                                            var s = try store.load(meta: meta)   // non-optional; no `if let`
                                            s.id = UUID()
                                            s.fileName = ""                      // force unique filename regeneration
                                            let now = Date()
                                            s.created = now
                                            s.modified = now
                                            try store.save(s, intoFolderID: nil, tags: s.tags)  // will append " (n)" if needed
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } catch {
                                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                                        }
                                    },
                                                                        onDelete: { delete(meta) },
                                    onShare: { share(meta) }
                                )
                            }
                        }
                    }
                    
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 8)
            }
            .padding(.bottom, 16)
        }
        
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.hidden)
        .background(Color.clear)
        // Base font for the entire Cue Sheets detent
       .font(.custom("Roboto-Regular", size: 17))

        
        // Present the editor as a proper sheet instead of a custom overlay
        .sheet(item: $editingSheet) { s in
            CueSheetEditorSheet(
                sheet: s,
                onSave: { updated in
                    try? store.save(updated, intoFolderID: nil, tags: updated.tags)
#if DEBUG
                    if let meta = store.index.sheets[updated.id] {
                        let url = store.fileURL(for: meta)
                        if let data = try? Data(contentsOf: url) {
                            if updated.events.contains(where: { $0.kind == .image }) {
                                let xml = String(data: data, encoding: .utf8) ?? ""
                                assert(xml.contains("type=\"image\"") && xml.contains("assetID=\""), "Saved image event missing assetID")
                            }
                            if let reloaded = try? CueXML.read(data) {
                                assert(!reloaded.events.contains(where: { $0.kind == .image && $0.payload == nil }), "Reloaded image event missing payload")
                            }
                        }
                    }
#endif
                    editingSheet = nil
                },
                onCancel: { editingSheet = nil }
            )
            .presentationDetents([.large])                // <- consistent, focused editor
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }

        
        
        // Importer (XML only)
         .fileImporter(
             isPresented: $showingImporter,
             allowedContentTypes: [.xml, .cueXML],
             allowsMultipleSelection: false
         ) { result in
             switch result {
             case .success(let urls):
                 guard let url = urls.first else { return }
                 // hop to next runloop so we’re not mutating while the importer is dismissing
                 DispatchQueue.main.async {
                     do {
                         _ = try store.importXML(from: url, intoFolderID: nil)
                         UINotificationFeedbackGenerator().notificationOccurred(.success)
                     } catch {
                         UINotificationFeedbackGenerator().notificationOccurred(.error)
                     }
                 }
             case .failure:
                 break
             }
         }

       
        .background(SharePresenter(url: $shareURL))
        // Broadcast confirmation
        .confirmationDialog(
            "Load this sheet?",
            isPresented: $showBroadcastChoice,
            presenting: pendingSheet
        ) { sheet in
            Button("Load on this device") {
                onLoad(sheet)
                isPresented = false
            }
            Button("Load and broadcast (cues are buggy)") {
                onLoad(sheet)      // local first
                onBroadcast(sheet) // then broadcast
                isPresented = false
            }
            Button("Cancel", role: .cancel) {
                pendingSheet = nil
            }
        } message: { _ in
            Text("You’re connected to other devices. Send this sheet to them too?")
        }
    }
    // MARK: - One-time starter template install
    // MARK: - Actions (user-triggered only; no mutation during body)

    private func filterMatches(_ meta: CueLibraryIndex.SheetMeta, search: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return meta.title.localizedCaseInsensitiveContains(q)
    }

    private func loadMostRecent() {
        guard let id = store.index.recents.first,
              let meta = store.index.sheets[id],
              let sheet = try? store.load(meta: meta) else { return }
        if canBroadcast() {
            pendingSheet = sheet
            showBroadcastChoice = true
        } else {
            onLoad(sheet)
            isPresented = false
        }
    }

    private func load(_ meta: CueLibraryIndex.SheetMeta) {
        guard let sheet = try? store.load(meta: meta) else { return }
        if canBroadcast() {
            pendingSheet = sheet
            showBroadcastChoice = true
        } else {
            onLoad(sheet)
            isPresented = false
        }
    }

    private func newBlank() {
            var s = CueSheet(title: "Untitled")
            // Default meter 4/4 (overrides any 5/4 legacy default in the model)
            s.timeSigNum = 4
            s.timeSigDen = 4
        s.created = Date()
        s.modified = s.created
            editingSheet = s
        }

        private func delete(_ meta: CueLibraryIndex.SheetMeta) {
            do { try store.delete(metaID: meta.id) }
            catch { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        }
    /// Share a single sheet via the iOS share sheet (UIActivityViewController).
           private func share(_ meta: CueLibraryIndex.SheetMeta) {
                do {
                    // Get the canonical on-disk export URL (already normalized to what the importer expects)
                    guard let url = try store.exportXML([meta]).first else { return }
                            shareURL = url
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } catch {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        private func loadMostRecentIfAny() {
            if let id = store.index.recents.first,
               let meta = store.index.sheets[id] {
                load(meta)
            }
        }
    
}


 

// MARK: - Row & Section UI

private struct LibraryRow: View {
    let meta: CueLibraryIndex.SheetMeta
    var onTap: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onShare: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: meta.pinned ? "pin.fill" : "doc.text")
                        .imageScale(.medium)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta.title)
                                                    .font(.custom("Roboto-Medium", size: 16))
                                                    .lineLimit(1)

                        InlineDates(created: meta.created, modified: meta.modified)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            Menu {
                            Button(role: .none) { onEdit() } label: {
                                Label("Edit", systemImage: "pencil").font(.custom("Roboto-Regular", size: 16))
                            }
                            Button(role: .none) { onShare() } label: {
                                                Label("Export as XML", systemImage: "square.and.arrow.up").font(.custom("Roboto-Regular", size: 16))
                                            }
                            Button(role: .none) { onDuplicate() } label: {
                                Label("Duplicate", systemImage: "doc.on.doc").font(.custom("Roboto-Regular", size: 16))
                            }
                            Button(role: .destructive) { onDelete() } label: {
                                Label("Delete", systemImage: "trash").font(.custom("Roboto-Regular", size: 16))
                            }
                        } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        }
    }
}
private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.custom("Roboto-SemiBold", size: 17))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.125), radius: 10, x: 0, y: 6)
    }
}

// MARK: - SearchBar (card-radius, material)
private struct SearchBar: View {
    @Binding var text: String
    var cornerRadius: CGFloat = 12
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search", text: $text)
                            .font(.custom("Roboto-Regular", size: 16))

                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct SharePresenter: UIViewControllerRepresentable {
    @Binding var url: URL?
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard let url else { return }
        if vc.presentedViewController == nil {
            let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            avc.completionWithItemsHandler = { _,_,_,_ in
                DispatchQueue.main.async { self.url = nil }
            }
            vc.present(avc, animated: true)
        }
    }
}

// MARK: - Utilities

private extension Array where Element: Hashable {
    /// Return unique elements, preserving original order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        var out: [Element] = []
        out.reserveCapacity(count)
        for e in self {
            if seen.insert(e).inserted { out.append(e) }
        }
        return out
    }
}
// MARK: - Simple wrap layout for tag chips
private struct Wrap<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content
    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.content = content
    }
    // Compatibility init to support `id: \.self` call sites
    init(_ data: Data, id: KeyPath<Data.Element, some Hashable>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.content = content
    }
    var body: some View {
        GeometryReader { geo in
            var x: CGFloat = 0
            var y: CGFloat = 0
            ZStack(alignment: .topLeading) {
                ForEach(Array(data), id: \.self) { item in
                    content(item)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(.thinMaterial, in: Capsule())
                        .alignmentGuide(.leading) { d in
                            if x + d.width > geo.size.width {
                                x = 0
                                y += d.height + 8
                            }
                            let result = x
                            x += d.width + 8
                            return result
                        }
                        .alignmentGuide(.top) { _ in y }
                }
            }
        }
        .frame(minHeight: 0, idealHeight: 0)
    }
}
private struct AbsoluteEntry: View {
    @Binding var timeText: String
    @State private var minutes: String = ""
    @State private var seconds: String = ""
    @State private var centiseconds: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time (HH:MM:SS.cc or MM:SS.cc)")
                            .font(.custom("Roboto-Regular", size: 13))
                            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                timeField(title: "MM", text: $minutes, limit: 999)
                Text(":")
                    .font(.custom("Roboto-Regular", size: 15))
                    .foregroundStyle(.secondary)
                timeField(title: "SS", text: $seconds, limit: 59, padTo: 2)
                Text(".")
                    .font(.custom("Roboto-Regular", size: 15))
                    .foregroundStyle(.secondary)
                timeField(title: "cc", text: $centiseconds, limit: 99, padTo: 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: minutes) { _ in updateTimeText() }
            .onChange(of: seconds) { _ in updateTimeText() }
            .onChange(of: centiseconds) { _ in updateTimeText() }
            .onChange(of: timeText) { _ in syncFieldsFromTimeText() }
            .onAppear { syncFieldsFromTimeText() }
        }
    }

    private func timeField(title: String, text: Binding<String>, limit: Int, padTo: Int = 2) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.custom("Roboto-Regular", size: 11))
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .font(.custom("Roboto-Regular", size: 16)).monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(minWidth: 40)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if let value = Int(digits) {
                        let clamped = min(max(0, value), limit)
                        let padded = String(format: "%0\(padTo)d", clamped)
                        if padded != text.wrappedValue { text.wrappedValue = padded }
                    } else {
                        text.wrappedValue = ""
                    }
                }
        }
    }

    private func syncFieldsFromTimeText() {
        let clean = timeText.replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ":")
        var totalSeconds: Double = 0
        if parts.count == 1 {
            totalSeconds = Double(clean) ?? 0
        } else if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let s = Double(parts[1]) ?? 0
            totalSeconds = m * 60 + s
        } else if parts.count >= 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let s = Double(parts[2]) ?? 0
            totalSeconds = h * 3600 + m * 60 + s
        }
        let centiTotal = Int((totalSeconds * 100).rounded())
        let mVal = centiTotal / 6000
        let sVal = max(0, min(59, (centiTotal % 6000) / 100))
        let cVal = max(0, min(99, centiTotal % 100))
        minutes = String(format: "%02d", mVal)
        seconds = String(format: "%02d", sVal)
        centiseconds = String(format: "%02d", cVal)
    }

    private func updateTimeText() {
        let mVal = Int(minutes) ?? 0
        let sVal = min(max(Int(seconds) ?? 0, 0), 59)
        let cVal = min(max(Int(centiseconds) ?? 0, 0), 99)
        timeText = String(format: "%02d:%02d.%02d", mVal, sVal, cVal)
    }
}

// MARK: - Large-detent editor (stable)
private struct CueSheetEditorSheet: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State var sheet: CueSheet
    var onSave: (CueSheet) -> Void
    var onCancel: () -> Void

    @State private var tab: Tab = .details
    @State private var isDirty: Bool = false
    enum Tab: String, CaseIterable { case details = "Details", events = "Events" /* tempoMeter to add next */ }

    var body: some View {
        VStack(spacing: 0) {
            // Header
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                let title = sheet.title.isEmpty ? "Untitled" : sheet.title
                                Text("Editing '\(title)'")
                                    .font(.custom("Roboto-SemiBold", size: 17))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if isDirty {
                                    Circle()
                                        .fill(flashColor) // uses global app tint/flash color if you theme accent
                                        .frame(width: 8, height: 8)
                                        .accessibilityLabel("Unsaved changes")
                                }
                            }
                            Spacer()
                            Button("Cancel", action: onCancel)
                                .font(.custom("Roboto-Regular", size: 16))
                            Button {
                                // normalize before save
                                sheet.events.sort { $0.at < $1.at }
                                onSave(sheet)
                                isDirty = false
                            } label: { Text("Save").font(.custom("Roboto-SemiBold", size: 16)) }
                            .buttonStyle(CueGlassActionButtonStyle())
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)     // moved down by 8pt
                        .padding(.bottom, 10)


            // Tabs
            CueEditorTabBar(
                selection: $tab,
                isDirty: isDirty,
                eventsCount: sheet.events.count
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)


            // Content
            Group {
                switch tab {
                case .details: DetailsSection(sheet: $sheet)
                case .events:  EventsSection(sheet: $sheet)
                }
            }
            .onChange(of: sheet) { _ in isDirty = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // extend sheet material through the bottom-safe-area region.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    private var flashColor: Color {
        appSettings.flashColor
    }
}
// Simple identifiable wrapper for .sheet(item:)
private struct IdentifiableIndex: Identifiable {
    let id = UUID()
    let value: Int
    init(_ value: Int) { self.value = value }
}

// MARK: - Editor Tab Bar (ViewThatFits + Glass)
private struct CueEditorTabBar: View {
    @Binding var selection: CueSheetEditorSheet.Tab
    let isDirty: Bool
    let eventsCount: Int
    @EnvironmentObject private var appSettings: AppSettings

    @Namespace private var ns

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideRail
            compactRail
            overflowRail
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Rails

    private var wideRail: some View {
        railContainer {
            tabButton(.details, mode: .iconAndText)
            tabButton(.events,  mode: .iconAndText)
        }
    }

    private var compactRail: some View {
        railContainer {
            tabButton(.details, mode: .iconOnly)
            tabButton(.events,  mode: .iconOnly)
        }
    }

    private var overflowRail: some View {
        Menu {
            Button { select(.details) } label: {
                Label("Details", systemImage: symbolName(for: .details, selected: selection == .details))
            }
            Button { select(.events) } label: {
                Label("Events", systemImage: symbolName(for: .events, selected: selection == .events))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName(for: selection, selected: true))
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(flashColor, flashColor.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
                Text(selection.rawValue)
                    .font(.custom("Roboto-SemiBold", size: 15))
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(railBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: Building blocks

    private enum LabelMode { case iconOnly, iconAndText }

    private func railContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(railBackground)
    }

    private var railBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .cueGlassIfAvailable()
            .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private func tabButton(_ tab: CueSheetEditorSheet.Tab, mode: LabelMode) -> some View {
        let selected = (selection == tab)
        let flash = flashColor

        return Button {
            select(tab)
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbolName(for: tab, selected: selected))
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            selected ? flash : flash.opacity(0.55),
                            selected ? flash.opacity(0.45) : flash.opacity(0.18)
                        )
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: selection) // motion without being “toy”

                    if tab == .events, eventsCount > 0 {
                        Text("\(eventsCount)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1))
                            .offset(x: 10, y: -10)
                            .accessibilityLabel("\(eventsCount) events")
                    }
                }

                if mode == .iconAndText {
                    Text(tab.rawValue)
                        .font(.custom("Roboto-SemiBold", size: 15))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .lineLimit(1)
                }

                if selected, isDirty {
                    Circle()
                        .fill(flash)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, mode == .iconOnly ? 10 : 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    Capsule()
                        .fill(.thinMaterial)
                        .cueGlassIfAvailable()
                        .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
                        .matchedGeometryEffect(id: "cueEditor.activeTab", in: ns)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }

    private func select(_ tab: CueSheetEditorSheet.Tab) {
        guard selection != tab else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
            selection = tab
        }
    }

    private func symbolName(for tab: CueSheetEditorSheet.Tab, selected: Bool) -> String {
        switch tab {
        case .details:
            return selected ? "info.circle.fill" : "info.circle"
        case .events:
            return selected ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
        }
    }

    private var flashColor: Color {
        appSettings.flashColor
    }
}

// MARK: - Glass helper (real .glassEffect, safely gated at runtime)
private extension View {
    @ViewBuilder func cueGlassIfAvailable() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            self.glassEffect()
        } else {
            self
        }
    }
}


// MARK: Details
private struct DetailsSection: View {
    @Binding var sheet: CueSheet
   @State private var tagDraft: String = ""
   @FocusState private var focus: Field?
    enum Field { case title, tag, notes }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Large editable title (full-width, no card)
                TextField("Title", text: $sheet.title)
                .font(.custom("Roboto-SemiBold", size: 42))

                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focus, equals: .title)
                    .onSubmit { focus = .tag }
                    .padding(.top, 6)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

                // Meta
                MetaStrip(created: sheet.created, modified: sheet.modified)

                // Tags (full width)
                VStack(alignment: .leading, spacing: 10) {
                    FieldHeader("Tags").font(.custom("Roboto-SemiBold", size: 15))
                    TagEditor(
                        tags: $sheet.tags,
                        draft: $tagDraft,
                        onCommit: addTag
                    )
                    .focused($focus, equals: .tag)
                }

                // Notes (glass hero)
                CueSheetNotesCard(
                    notes: $sheet.notes,
                    modified: sheet.modified,
                    focus: $focus
                )
            }
            .padding(.vertical, 6)
            .safeAreaPadding(.bottom, 12)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Title") { focus = .title }
                Button("Tags")  { focus = .tag }
                Button("Notes") { focus = .notes }
                Spacer()
                Button("Done")  { focus = nil }.bold()
            }
        }
    }

    // MARK: Helpers
    private func addTag() {
        let t = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sheet.tags.contains(t) else { return }
        sheet.tags.append(t)
        tagDraft = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private func glassCardBackground() -> some View {
    let radius: CGFloat = 16
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    return Group {
        if #available(iOS 26.0, macOS 15.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else if #available(iOS 18.0, macOS 15.0, *) {
            shape
                .fill(.clear)
                .containerShape(shape)
                .glassEffect()
                .clipShape(shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
        }
    }
    .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
    )
    .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1.1)
    )
}

private func cueGlassBackground(shape: RoundedRectangle) -> some View {
    Group {
        if #available(iOS 26.0, macOS 15.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else if #available(iOS 18.0, macOS 15.0, *) {
            shape
                .fill(.clear)
                .containerShape(shape)
                .glassEffect()
                .clipShape(shape)
        } else {
            shape
                .fill(.thinMaterial)
        }
    }
}

private extension View {
    func cueGlassChrome(shape: RoundedRectangle = .init(cornerRadius: 12, style: .continuous), minHeight: CGFloat = 36) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: minHeight)
            .background { cueGlassBackground(shape: shape) }
            .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.7))
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .contentShape(shape)
    }
}

private struct CueGlassActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .cueGlassChrome(shape: shape)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private func glassToggleBackground(radius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    return Group {
        if #available(iOS 26.0, macOS 15.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else if #available(iOS 18.0, macOS 15.0, *) {
            shape
                .fill(.clear)
                .containerShape(shape)
                .glassEffect()
                .clipShape(shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
        }
    }
    .overlay(
        shape.stroke(Color.white.opacity(0.16), lineWidth: 0.6)
    )
    .overlay(
        shape.stroke(Color.primary.opacity(0.1), lineWidth: 1)
    )
}

private struct CueSheetNotesCard: View {
    @Binding var notes: String?
    let modified: Date
    let focus: FocusState<DetailsSection.Field?>.Binding
    private enum Mode { case edit, preview }
    @State private var mode: Mode = .edit
    @State private var isExpanded: Bool = false
    @State private var showClearConfirm = false
    @Namespace private var toggleNS
    @FocusState private var notesFocused: Bool
    private let limit = 10_000
    private let collapsedCardMinHeight: CGFloat = 150
    private let expandedCardMinHeight: CGFloat = 240
    private let collapsedPreviewHeight: CGFloat = 132
    private let radius: CGFloat = 16

    private var binding: Binding<String> {
        Binding<String>(
            get: { notes ?? "" },
            set: { newVal in
                notes = newVal.isEmpty ? nil : newVal
            }
        )
    }

    private var hasText: Bool { !binding.wrappedValue.isEmpty }

    private var isCollapsedPreview: Bool {
        mode == .preview && !isExpanded && hasText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            card
        }
        .animation(.easeInOut(duration: 0.22), value: mode)
        .onChange(of: focus.wrappedValue) { newValue in
            notesFocused = (newValue == .notes)
        }
        .onChange(of: notesFocused) { newValue in
            if newValue {
                focus.wrappedValue = .notes
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded = true }
                mode = .edit
            } else if focus.wrappedValue == .notes {
                focus.wrappedValue = nil
                if hasText && mode == .edit {
                    withAnimation(.easeInOut(duration: 0.18)) { mode = .preview }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("NOTES")
                .font(.custom("Roboto-SemiBold", size: 17))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                toggle
                if mode == .preview && hasText {
                    expandCollapseButton
                }
                templateMenu
                clearButton
            }
        }
    }

    private var toggle: some View {
        let toggleRadius: CGFloat = 12
        return HStack(spacing: 6) {
            toggleButton(.edit, systemImage: "square.and.pencil", title: "Edit", containerRadius: toggleRadius)
            toggleButton(.preview, systemImage: "eye", title: "Preview", containerRadius: toggleRadius)
        }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(height: 42)
                .background(glassToggleBackground(radius: toggleRadius))
                .clipShape(RoundedRectangle(cornerRadius: toggleRadius, style: .continuous))
        .frame(minHeight: 32)
    }

    private func toggleButton(_ target: Mode, systemImage: String, title: String, containerRadius: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = target
            }
            if target == .edit {
                isExpanded = true
                notesFocused = true
            } else {
                notesFocused = false
            }
        } label: {
            ZStack {
                if mode == target {
                    RoundedRectangle(cornerRadius: containerRadius - 3, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .matchedGeometryEffect(id: "pill", in: toggleNS)
                }
                Label(title, systemImage: systemImage)
                    .font(.custom("Roboto-SemiBold", size: 13))
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 6)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
    }

    private var expandCollapseButton: some View {
        let label = isExpanded ? "Collapse" : "Expand"
        let systemImage = isExpanded ? "chevron.up" : "chevron.down"
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Label(label, systemImage: systemImage)
                .font(.custom("Roboto-Regular", size: 13))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
        }
        .buttonStyle(.plain)
    }

    private var templateMenu: some View {
        Menu {
            templateButton("Rehearsal")
            templateButton("Run")
            templateButton("Cues")
            templateButton("Lighting")
            templateButton("Tech")
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 24)
                .symbolRenderingMode(.palette)
        }
    }

    private func templateButton(_ title: String) -> some View {
        Button(title) {
            insertTemplate(title)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var clearButton: some View {
        Button {
            showClearConfirm = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 24)
                .symbolRenderingMode(.hierarchical)
        }
        .confirmationDialog("Clear notes?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                notes = nil
                mode = .edit
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var card: some View {
        return VStack(alignment: .leading, spacing: 10) {
            content
            footer
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: mode == .preview && !isExpanded ? collapsedCardMinHeight : expandedCardMinHeight,
            alignment: .topLeading
        )
        .background(glassCardBackground())
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(notesFocused ? 0.12 : 0.18), lineWidth: 0.4)
        )
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .padding(.horizontal, 2)
        .shadow(color: Color.black.opacity(notesFocused ? 0.08 : 0.16), radius: notesFocused ? 6 : 12, x: 0, y: notesFocused ? 3 : 8)
        .onTapGesture {
            if isCollapsedPreview {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                    mode = .edit
                    notesFocused = true
                }
            }
        }
    }

    private var content: some View {
        let showingPreview = (mode == .preview || isCollapsedPreview) && hasText
        return ZStack(alignment: .topLeading) {
            preview
                .opacity(showingPreview ? 1 : 0)
                .allowsHitTesting(showingPreview)
            editor
                .opacity(showingPreview ? 0 : 1)
                .allowsHitTesting(!showingPreview)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: binding)
                .font(.custom("Roboto-Regular", size: 16))
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
                .focused($notesFocused)
                .tint(.accentColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .onChange(of: binding.wrappedValue) { newValue in
                    if newValue.count > limit {
                        binding.wrappedValue = String(newValue.prefix(limit))
                    }
                }

            if binding.wrappedValue.isEmpty {
                Text("Add cue sheet notes… (Markdown)")
                    .font(.custom("Roboto-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(renderMarkdownPreview(binding.wrappedValue))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(
                    maxHeight: isCollapsedPreview ? collapsedPreviewHeight : .infinity,
                    alignment: .topLeading
                )
                .clipped()
                .animation(.none, value: binding.wrappedValue)
        }
        .overlay(alignment: .bottom) {
            if isCollapsedPreview {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color(.systemBackground).opacity(0.65)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .allowsHitTesting(false)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(binding.wrappedValue.count) / \(limit)")
                .font(.custom("Roboto-Regular", size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 14)
            Text("MARKDOWN")
                .font(.custom("Roboto-SemiBold", size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                )
            Spacer()
            Text(modified.formatted(date: .abbreviated, time: .shortened))
                .font(.custom("Roboto-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func insertTemplate(_ title: String) {
        let template = "### \(title)\n- "
        var current = binding.wrappedValue
        if current.isEmpty {
            current = template
        } else {
            current.append("\n\n---\n\n\(template)")
        }
        binding.wrappedValue = String(current.prefix(limit))
        mode = .edit
        isExpanded = true
        notesFocused = true
    }

    private func renderMarkdownPreview(_ source: String) -> AttributedString {
        let preprocessed = preprocessMarkdownPreview(source)
        guard !preprocessed.isEmpty else { return AttributedString("") }
        if let attributed = try? AttributedString(
            markdown: preprocessed,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return attributed
        }
        return AttributedString(preprocessed)
    }

    private func preprocessMarkdownPreview(_ source: String) -> String {
        guard !source.isEmpty else { return "" }
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        var out = ""

        for idx in lines.indices {
            let line = lines[idx]
            out.append(contentsOf: line)

            guard idx < lines.count - 1 else { continue }
            let nextLine = lines[idx + 1]
            if line.isEmpty || nextLine.isEmpty {
                out.append("\n")
            } else {
                out.append("  \n")
            }
        }

        return out
    }
}



private struct FieldHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.custom("Roboto-Regular", size: 13))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

    }
}

private struct TagEditor: View {
    @Binding var tags: [String]
    @Binding var draft: String
    var onCommit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Chips
            if !tags.isEmpty {
                Wrap(tags, id: \.self) { tag in
                    TagChip(tag: tag) {
                        if let idx = tags.firstIndex(of: tag) {
                            tags.remove(at: idx)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
            }
            // Composer
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                TextField("Add tag", text: $draft)
                    .font(.custom("Roboto-Regular", size: 16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(onCommit)
                Button {
                    onCommit()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.custom("Roboto-SemiBold", size: 15))
                }
                .buttonStyle(CueGlassActionButtonStyle())
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct TagChip: View {
    let tag: String
    var onDelete: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.custom("Roboto-Regular", size: 15))
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.custom("Roboto-SemiBold", size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MetaStrip: View {
    let created: Date
    let modified: Date
    var body: some View {
        HStack(spacing: 8) {
            Label(created.formatted(date: .abbreviated, time: .shortened),
                  systemImage: "calendar.badge.plus")
            .labelStyle(.iconOnly)
            Text("Created \(created.formatted(date: .abbreviated, time: .shortened))")
                .font(.custom("Roboto-Regular", size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Image(systemName: "arrow.clockwise.circle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text("Modified \(modified.formatted(date: .abbreviated, time: .shortened))")
                .font(.custom("Roboto-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Events
private func defaultLabel(for event: CueSheet.Event) -> String {
    switch event.kind {
    case .cue:
        return event.rehearsalMarkMode == .auto ? "Cue (+Rehearsal Mark)" : "Cue"
    case .stop:
        return "Stop"
    case .restart:
        return "Restart"
    case .message:
        if case .message(let payload) = event.payload {
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstLine = text.split(separator: "\n").first {
                let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count <= 24 { return String(trimmed) }
            }
        }
        return "Message"
    case .image:
        if case .image(let payload) = event.payload,
           let caption = payload.caption?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty,
           caption.count <= 24 {
            return caption
        }
        return "Image"
    default:
        return "Event"
    }
}
private struct EventsSection: View {
    @State private var messageDraft: String = ""

    @State private var pickedImageItem: PhotosPickerItem? = nil
    @State private var pickedImageAssetID: UUID? = nil
    @State private var pickedImageCaption: String = ""

    @Binding var sheet: CueSheet

    enum EntryMode { case musical, absolute }
        // Global timing selector (drives all sub-sections)
        @State private var globalTiming: EntryMode = .absolute

    @State private var kind: CueSheet.Event.Kind = .cue
        @State private var cueColorIndex: Int = 0
    @State private var rehearsalMarkMode: CueSheet.RehearsalMarkMode = .off
        // Musical token inputs
        @State private var bar: Int = 1       // supports negative for anacrusis
        @State private var beat: Int = 1
        @State private var grid: NoteGrid = .quarter
        @State private var tuplet: TupletMode = .off
        @State private var index: Int = 1     // 1…(slotsPerBeat * tuplet.count)
        @State private var showTupletCustom = false
        @State private var customM: String = "3"
        @State private var customN: String = "2"

    // Absolute input
    @State private var timeText: String = "00:00.00"
    // Stop hold
    @State private var hold: Double = 2.0
    // Show absolute time temporarily (1s) for tapped rows
    @State private var revealAbs: Set<Int> = []
    @State private var showTimingDetails: Bool = false

    // ── TEMPO CONFIG (separate section) ─────────────────────────────
        @State private var tBar: Int = 1
        @State private var tBeat: Int = 1
        @State private var tGrid: NoteGrid = .quarter
        @State private var tTuplet: TupletMode = .off
        @State private var tIndex: Int = 1
        @State private var tBPM: Double = 120
    // Preset denominators for snapping
        private let presetDenoms: [Int] = [1, 2, 4, 8, 12, 16, 20, 32, 64]
        // Editing an existing meter change
      @State private var editingMeterItem: IdentifiableIndex? = nil

        @State private var editNumDraft: Int = 4
        @State private var editDenDraft: Int = 4



    // ── METER CONFIG (separate section) ─────────────────────────────
      @State private var mBar: Int = 1
      @State private var mNum: Int = 4
      @State private var mDen: Int = 4
    @State private var mTimeText: String = "00:00.00"
    
    // ── Live musical anchors for recompute (only for musical-origin events) ──
       private enum Origin { case absolute, musical }
       /// bar/beat/slot labeling with precise subdivision
       private struct MusicalAnchor: Equatable {
           var bar: Int              // 1-based
           var beat: Int             // 1-based
           var slot: Int             // 1-based
           var slotsPerBeat: Int     // e.g. 1,2,3,4,6,8...
       }
       @State private var origins:  [Origin]            = []
       @State private var anchors:  [MusicalAnchor?]    = []
       @State private var revealAbsolute: Set<Int>      = []  // tap-to-toggle rows


    
    // Collapsible sections
       @State private var showTempoChanges: Bool = false
       @State private var showMeterChanges: Bool = false
    @ViewBuilder private var timingSection: some View {
        let bpmSteps: [Double] = Array(stride(from: 20.0, through: 300.0, by: 1.0))
        // ───────────────── TIMING (Global + Changes) ─────────────────
        VStack(alignment: .leading, spacing: 12) {
            Text("Timing").font(.custom("Roboto-SemiBold", size: 17))
            // Global timing selector
            Picker("", selection: $globalTiming) {
                Text("Absolute time").tag(EntryMode.absolute)
                Text("Metered").tag(EntryMode.musical)
            }
            .pickerStyle(.segmented)

            // —— Global (only when Metered) ———————————————
            if globalTiming == .musical {
                Text("Global").font(.subheadline.weight(.bold)).font(.custom("Roboto-SemiBold", size: 15))
                // Initial tempo
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tempo").font(.custom("Roboto-Regular", size: 15))
                        Spacer()
                        Text("\(Int(sheet.bpm)) BPM")
                            .font(.custom("Roboto-Regular", size: 15)).monospacedDigit()
                    }
                    TimerBehaviorPage.CustomStepSlider(
                        value: Binding {
                            sheet.bpm
                        } set: { newVal in
                            sheet.bpm = newVal
                        },
                        steps: bpmSteps,
                        range: 20...300,
                        thresholdVertical: 90,
                        thumbColor: .accentColor
                    )
                    .frame(height: 44)
                }
                // Initial time signature — styled fraction control
                FractionMeterControl(
                    numerator: $sheet.timeSigNum,
                    denominator: $sheet.timeSigDen,
                    presetDenominators: presetDenoms
                )
                Divider().opacity(0.15)
            }


            // —— Tempo Changes (collapsible; only when Metered) ———
            if globalTiming == .musical {
                DisclosureGroup(isExpanded: $showTempoChanges) {

                    VStack(alignment: .leading, spacing: 8) {

                        HStack(spacing: 10) {
                            Spacer(minLength: 8)

                            // BPM slider (same look as Global)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("BPM").font(.custom("Roboto-Regular", size: 15))
                                    Spacer()
                                    Text("\(Int(tBPM))")
                                        .font(.custom("Roboto-Regular", size: 15)).monospacedDigit()
                                }
                                TimerBehaviorPage.CustomStepSlider(
                                    value: $tBPM,
                                    steps: bpmSteps,
                                    range: 20...300,
                                    thresholdVertical: 90,
                                    thumbColor: .accentColor
                                )
                                .frame(height: 44)
                            }
                        }

                        // Musical-position authoring (no absolute variant here)

                        // Grid + Tuplet (bold x:y) + BeatGridPad (no Beat/Index badges)
                        HStack(spacing: 10) {
                            NoteGridSegmented(selection: $tGrid)

                            Menu {
                                Button("x:y") { tTuplet = .off; tNormalizeIndex() }
                                Button("3:2 (Triplet)") { tTuplet = .triplet; tNormalizeIndex() }
                                Button("5:4 (Quintuplet)") { tTuplet = .quintuplet; tNormalizeIndex() }
                                Button("7:4 (Septuplet)") { tTuplet = .septuplet; tNormalizeIndex() }
                            } label: {
                                TupletMenuLabel(tTuplet.label)
                            }
                        }
                        BeatGridPad(
                         beats: sheet.timeSigNum,
                         slotsPerBeat: tTotalSlotsPerBeat,
                         selectedBeat: $tBeat,
                         selectedIndex: $tIndex
                        )
                        .padding(.top, 6)


                        HStack {
                            Text("Will change at \(String(format: "%.2f", tPreviewSeconds()))s")
                             .font(.custom("Roboto-Regular", size: 13))
                            .foregroundStyle(.secondary)

                            Spacer()
                            Button {
                                addTempoChange()
                            } label: {
                                Label("Add Tempo Change", systemImage: "metronome.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } label: {
                    HStack {
                        Text("Tempo Changes").font(.custom("Roboto-SemiBold", size: 15))
                        Spacer()
                        if !sheet.tempoChanges.isEmpty {
                            Text("\(sheet.tempoChanges.count)")
                                .font(.custom("Roboto-Regular", size: 11))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }

                // Existing tempo changes (always visible list)
                if !sheet.tempoChanges.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(sheet.tempoChanges.indices), id: \.self) { i in
                            HStack(spacing: 10) {
                                Text("Bar \(sheet.tempoChanges[i].atBar)")
                                    .font(.custom("Roboto-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 72, alignment: .leading)
                                Stepper(value: $sheet.tempoChanges[i].bpm, in: 20...300, step: 1) {
                                    Text("\(Int(sheet.tempoChanges[i].bpm)) BPM")
                                        .font(.custom("Roboto-Regular", size: 15))
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    sheet.tempoChanges.remove(at: i)
                                    UIImpactFeedbackGenerator().impactOccurred()
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            // —— Time Signature Changes (collapsible; only when Metered) —
            if globalTiming == .musical {
                DisclosureGroup(isExpanded: $showMeterChanges) {

                    VStack(alignment: .leading, spacing: 8) {

                        Stepper(value: $mBar, in: 1...9999) {
                            Text("Bar \(mBar)").font(.custom("Roboto-Regular", size: 15))
                        }

                        // Fraction control for the meter to add
                        FractionMeterControl(
                         numerator: $mNum,
                         denominator: $mDen,
                         presetDenominators: presetDenoms
                        )


                        HStack {
                            Text("Will change at \(mPreviewLabel())")
                            .font(.custom("Roboto-Regular", size: 13))
                            .foregroundStyle(.secondary)

                            Spacer()
                            Button {
                                addMeterChange()
                            } label: {
                                Label("Add Time Signature", systemImage: "flag.2.crossed")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } label: {
                    HStack {
                        Text("Time Signature Changes").font(.custom("Roboto-SemiBold", size: 15))
                        Spacer()
                        if !sheet.meterChanges.isEmpty {
                            Text("\(sheet.meterChanges.count)")
                                .font(.custom("Roboto-Regular", size: 11))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            }
            if !sheet.meterChanges.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(sheet.meterChanges.indices), id: \.self) { i in
                        let mc = sheet.meterChanges[i]
                        HStack(spacing: 12) {
                                                        Text("Bar \(mc.atBar)")
                                                            .font(.custom("Roboto-Regular", size: 15))
                                                            .foregroundStyle(.secondary)
                                                            .frame(minWidth: 64, alignment: .leading)
                                                        Text("\(mc.num)/\(mc.den)")
                                                            .font(.custom("Roboto-SemiBold", size: 16)).monospacedDigit()
                                                            .padding(.horizontal, 10)
                                                            .padding(.vertical, 6)
                                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                                        Spacer()
                                                        Button {
                                                            editingMeterItem = IdentifiableIndex(i)
                                                            editNumDraft = mc.num
                                                            editDenDraft = mc.den
                                                        } label: {
                                                            Label("Edit", systemImage: "pencil")
                                                        }
                                                        .buttonStyle(.borderless)
                                                        Button(role: .destructive) {
                                                            sheet.meterChanges.remove(at: i)
                                                            UIImpactFeedbackGenerator().impactOccurred()
                                                        } label: { Image(systemName: "trash") }
                                                        .buttonStyle(.borderless)
                                                    }

                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
    private var timingSummaryStrip: some View {
        let modeLabel = globalTiming == .musical ? "Metered" : "Absolute"
        let detail: String = {
            if globalTiming == .musical {
                return "Start 0:00 • \(Int(sheet.bpm)) BPM • \(sheet.timeSigNum)/\(sheet.timeSigDen)"
            } else {
                return "Start 0:00 • Absolute timing"
            }
        }()

        return HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "metronome.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Timing")
                            .font(.custom("Roboto-SemiBold", size: 15))
                        Text(modeLabel)
                            .font(.custom("Roboto-Regular", size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Text(detail)
                        .font(.custom("Roboto-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showTimingDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showTimingDetails ? "Hide" : "Edit")
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showTimingDetails ? 180 : 0))
                }
                .font(.custom("Roboto-SemiBold", size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    private var timingGroupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            timingSummaryStrip
            if showTimingDetails {
                Divider().opacity(0.1).padding(.horizontal, 2)
                timingSection
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(glassCardBackground())
    }
    // MARK: - Composer (thin wrapper)
    @ViewBuilder private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            composerEventTypeSection
            Divider().opacity(0.12)
            if kind == .cue {
                composerFlashColorSection
                Divider().opacity(0.12)
                composerRehearsalMarkSection
                Divider().opacity(0.12)
            }
            composerTimeEntrySection
            composerPayloadSection
            composerPreviewAndAddRow

        }
        .padding(12)
        .background(glassCardBackground())
    }
    @ViewBuilder private var composerPayloadSection: some View {
        switch kind {
        case .message:
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Message", "Text shown on devices when this event fires.")
                TextEditor(text: $messageDraft)
                    .frame(minHeight: 90)
                    .padding(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }

        case .image:
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Image", "Pick an image asset. TimerCard overlays always width-fit the image.")

                if let preview = pickedImagePreview {
                    preview
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 140)
                        .clipped()
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1.1)
                        )
                }

                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickedImageItem, matching: .images) {
                        HStack(spacing: 8) {
                        Image(systemName: "photo")
                        Text(pickedImageAssetID == nil ? "Choose Image" : "Replace Image")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .opacity(0.6)
                    }
                    .font(.custom("Roboto-SemiBold", size: 15))
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                    .cueGlassChrome(minHeight: 48)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onChange(of: pickedImageItem) { item in
                        guard let item else { return }
                        Task { @MainActor in
                            defer { pickedImageItem = nil }
                            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                            do {
                                pickedImageAssetID = try CueLibraryStore.shared.ingestImage(data: data)
                                kind = .image
                            } catch {
                                pickedImageAssetID = nil
                            }
                        }
                    }

                    if pickedImageAssetID != nil {
                        Button(role: .destructive) {
                            pickedImageAssetID = nil
                            pickedImageCaption = ""
                        } label: {
                            Label("Remove Image", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                TextField("Caption (optional)", text: $pickedImageCaption)
                    .textFieldStyle(.roundedBorder)
            }

        default:
            EmptyView()
        }
    }

    private var pickedImagePreview: Image? {
        guard let id = pickedImageAssetID,
              let data = CueLibraryStore.shared.assetData(id: id),
              let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }

    private var composerEventTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Event Type", "Pick what fires. Hold applies to Stop; rehearsal marks to Cue.")
            EventTypeChipRow(selection: $kind)
            eventTypeDescription
            if kind == .stop {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: $hold, in: 0...30, step: 0.1) {
                        Text("Hold \(hold, specifier: "%.2f") s")
                            .font(.custom("Roboto-Regular", size: 15))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: kind)
    }
    private var eventTypeDescription: some View {
        let copy = eventTypeCopy(for: kind)
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.primary)
                    .font(.custom("Roboto-Regular", size: 14))
                if let secondary = copy.secondary {
                    Text(secondary)
                        .font(.custom("Roboto-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .id(kind)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 52, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.18), value: kind)
    }
    private func eventTypeCopy(for kind: CueSheet.Event.Kind) -> (primary: String, secondary: String?) {
        switch kind {
        case .stop:
            return ("Stop playback at this moment.", "Optional hold keeps the timer paused before clearing.")
        case .cue:
            return ("Drop a cue marker with flash color and rehearsal mark options.", "Hold controls message/image only; rehearsal marks auto-clear via defaults.")
        case .restart:
            return ("Restart the timer from zero and continue running.", nil)
        case .message:
            return ("Show a message overlay when the event triggers.", nil)
        case .image:
            return ("Display an overlay image on connected devices.", nil)
        case .flashColor:
            return ("Change the flash accent color mid-score.", nil)
        default:
            return ("Trigger the selected event.", nil)
        }
    }
    private var composerFlashColorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Flash Color", "Color used when the event is a Cue.")
            CueColorDots(selectedIndex: $cueColorIndex)
        }
    }
    private var composerRehearsalMarkSection: some View {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Rehearsal Mark", "Choose whether this cue shows a rehearsal mark.")
                Picker("", selection: $rehearsalMarkMode) {
                    Text("No").tag(CueSheet.RehearsalMarkMode.off)
                    Text("Yes").tag(CueSheet.RehearsalMarkMode.auto)
                }
                .pickerStyle(.segmented)
            }
        }
    private var composerTimeEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let desc = (globalTiming == .musical)
            ? "Pick bar • beat • subdivision; tempo/meter will resolve the time."
            : "Enter absolute time (MM:SS.cc). This never changes."
            sectionHeader("Time Entry", desc)

            if globalTiming == .musical {
                musicalBarBeatRow
                musicalGridTupletRow
                BeatGridPad(
                    beats: sheet.timeSigNum,
                    slotsPerBeat: totalSlotsPerBeat,
                    selectedBeat: $beat,
                    selectedIndex: $index
                )
                .padding(.top, 6)
            } else {
                AbsoluteEntry(timeText: $timeText)
            }
        }
    }
    private var musicalBarBeatRow: some View {
        HStack(spacing: 10) {
            Stepper(value: $bar, in: -128...9999) { Text("Bar \(bar)") }
                .frame(maxWidth: .infinity, alignment: .leading)

            // Beat is picked via the grid pad; show it read-only
            Text("Beat \(beat)")
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var musicalGridTupletRow: some View {
        HStack(spacing: 10) {
            NoteGridSegmented(selection: $grid)

            Menu {
                Button("x:y") { tuplet = .off; normalizeIndex() }
                Button("3:2 (Triplet)") { tuplet = .triplet; normalizeIndex() }
                Button("5:4 (Quintuplet)") { tuplet = .quintuplet; normalizeIndex() }
                Button("7:4 (Septuplet)") { tuplet = .septuplet; normalizeIndex() }
                Button("Custom…") { showTupletCustom = true }
            } label: {
                TupletMenuLabel(tuplet.label)
            }

            Text("Index \(index)/\(max(1, totalSlotsPerBeat))")
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }
    private struct NoteGridSegmented: View {
        @Binding var selection: NoteGrid
        var body: some View {
            Picker("Grid", selection: $selection) {
                ForEach(NoteGrid.subdivisionsOnly) { g in NoteGlyph(g, height: 32, vpad: 5).tag(g) }
                }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)

        }
    }
    private func TupletMenuLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.custom("Roboto-SemiBold", size: 15))
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(minWidth: 104, minHeight: 18, alignment: .center)
        .cueGlassChrome(minHeight: 48)
    }

private struct EventTypeChipRow: View {
    @Binding var selection: CueSheet.Event.Kind

    private struct Item: Identifiable {
        var id: CueSheet.Event.Kind { kind }
        let kind: CueSheet.Event.Kind
        let title: String
        let icon: String
    }

    private let items: [Item] = [
        .init(kind: .stop, title: "Stop", icon: "hand.raised.fill"),
        .init(kind: .cue, title: "Cue", icon: "bolt.fill"),
        .init(kind: .restart, title: "Restart", icon: "gobackward"),
        .init(kind: .message, title: "Message", icon: "text.bubble"),
        .init(kind: .image, title: "Image", icon: "photo")
    ]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                let isSelected = selection == item.kind
                Button {
                    selection = item.kind
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .imageScale(.medium)
                        Text(item.title)
                            .font(.custom("Roboto-Regular", size: 15))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(glassToggleBackground(radius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.14), lineWidth: isSelected ? 1.6 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
    private var composerPreviewAndAddRow: some View {
        let previewEvent = composerPreviewEvent()
        let previewLabel = previewEvent?.label ?? autoLabel(for: CueSheet.Event(kind: kind, at: 0, holdSeconds: nil, label: nil))
        let timeLabel = String(format: "Fires at %.2f s", previewSeconds())
        let detail = previewDetail(for: previewEvent)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(previewLabel)
                    .font(.custom("Roboto-SemiBold", size: 16))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    Text(timeLabel)
                        .font(.custom("Roboto-Regular", size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    if let detail {
                        Text(detail)
                            .font(.custom("Roboto-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Button { addEvent() } label: {
                Label("Add", systemImage: "plus.circle.fill")
                    .font(.custom("Roboto-SemiBold", size: 15))
            }
            .buttonStyle(CueGlassActionButtonStyle())
            .disabled(!canAddEvent)
        }
    }
    private var canAddEvent: Bool {
        switch kind {
        case .message:
            return !messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            return pickedImageAssetID != nil
        default:
            return true
        }
    }

    @ViewBuilder private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        Text(title).font(.custom("Roboto-SemiBold", size: 15))
        Text(subtitle).font(.custom("Roboto-Regular", size: 12)).foregroundStyle(.secondary)
    }

    
    @ViewBuilder private var eventList: some View {
        LazyVStack(spacing: 12) {
            if sheet.events.isEmpty {
                emptyStateCard
            } else {
                ForEach(Array(sheet.events.indices), id: \.self) { i in
                    let showMusical = (globalTiming == .musical) && i < origins.count && origins[i] == .musical && anchors.indices.contains(i) && anchors[i] != nil && !revealAbsolute.contains(i)

                    let label: String = {
                        if showMusical, !revealAbs.contains(i), let a = anchors[i] {
                            if a.slotsPerBeat > 1 {
                                return "Bar \(a.bar), Beat \(a.beat), Subdivision \(a.slot)/\(a.slotsPerBeat)"
                            } else {
                                return "Bar \(a.bar), Beat \(a.beat)"
                            }
                        } else {
                            return String(format: "@ %.2f s", sheet.events[i].at)
                        }
                    }()
                    EventRow(
                        event: $sheet.events[i],
                        timeLabel: label,
                        onTapTime: { revealAbsFor(i) },
                        onDelete: {
                            sheet.events.remove(at: i)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    )
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No events yet")
                .font(.custom("Roboto-SemiBold", size: 16))
            Text("Add your first event above to start building the cue sheet.")
                .font(.custom("Roboto-Regular", size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassCardBackground())
    }


    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        timingGroupCard
                        Divider()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        composerCard
                        Divider().opacity(0.08)
                        eventList
                            .padding(.vertical, 4)
                        // Bottom inset lives inside the scroll content so the sheet can extend fully without a dead zone.
                                                    .padding(.bottom, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .safeAreaPadding(.bottom, 16) // allow the last card to clear the home indicator without clipping.
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 18) } // Extra scrollable inset to lift the last card above the rounded sheet mask.
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.top, 10)
        }
        // Edit existing meter change as a sheet using the same fraction control
        .overlay {
            if let item = editingMeterItem {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Edit Time Signature").font(.custom("Roboto-SemiBold", size: 17))
                        FractionMeterControl(
                            numerator: $editNumDraft,
                            denominator: $editDenDraft,
                            presetDenominators: presetDenoms
                        )
                        HStack {
                            Button("Cancel") { editingMeterItem = nil }
                            Spacer()
                            Button("Save") {
                                let idx = item.value
                                let clampedDen = snapDen(editDenDraft)
                                sheet.meterChanges[idx] = CueSheet.MeterChange(
                                    atBar: sheet.meterChanges[idx].atBar,
                                    num: max(1, editNumDraft),
                                    den: clampedDen
                                )
                                editingMeterItem = nil
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 420)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }

               
               .onAppear { alignParallelState() }
                .onChange(of: sheet.events.count) { _ in alignParallelState() }

        // Keep events live-linked to Global tempo/meter while in Metered mode
                .onChange(of: sheet.bpm) { _ in
                    guard globalTiming == .musical else { return }
                    recomputeAllFromAnchors()
                    syncSortWithAnchors()
                }
                .onChange(of: sheet.timeSigNum) { _ in
                    guard globalTiming == .musical else { return }
                    recomputeAllFromAnchors()
                    syncSortWithAnchors()
                }
                .onChange(of: sheet.timeSigDen) { _ in
                    guard globalTiming == .musical else { return }
                    recomputeAllFromAnchors()
                    syncSortWithAnchors()
                }
                .onChange(of: globalTiming) { mode in
                    // Switching modes does NOT convert existing events.
                                // Absolute-time events remain absolute (no anchor).
                                // Musical-origin events will keep/receive anchors only when created as musical.
                                if mode == .absolute { revealAbsolute.removeAll() }

                }

    }
    private func revealAbsFor(_ i: Int) {
            guard !revealAbs.contains(i) else { return }
            revealAbs.insert(i)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                revealAbs.remove(i)
        }
        }

    private func addEvent() {
        let at: Double = (globalTiming == .absolute) ? parseTime(timeText) : musicalToSecondsNew()
        guard var e = makeEventDraft(at: at, allowMissingImage: false) else { return }
        applyAutoLabel(to: &e)
        sheet.events.append(e)
                if globalTiming == .musical {
                    // Store exact position metadata for this musical-origin event
                    let slots = max(1, totalSlotsPerBeat)
                    let idx   = min(max(1, index), slots)
                    anchors.append(MusicalAnchor(bar: bar, beat: beat, slot: idx, slotsPerBeat: slots))
                    origins.append(.musical)
                    syncSortWithAnchors()
                } else {
                    anchors.append(nil)
                    origins.append(.absolute)
                    sheet.events.sort { $0.at < $1.at }
                    // keep parallel arrays in sorted order too
                    syncSortWithAnchors()
                }
        if kind == .message {
            messageDraft = ""
        }
        if kind == .image {
            pickedImageAssetID = nil
            pickedImageCaption = ""
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func makeEventDraft(at time: Double, allowMissingImage: Bool) -> CueSheet.Event? {
        var e = CueSheet.Event(kind: kind, at: max(0, time), holdSeconds: nil, label: nil)
        switch kind {
        case .stop:
            e.holdSeconds = max(0, hold)

        case .message:
            let t = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            e.payload = .message(.init(text: t, spans: []))

        case .image:
            guard let id = pickedImageAssetID else {
#if DEBUG
                if !allowMissingImage { assertionFailure("Attempted to add an image event without an assetID") }
#endif
                if allowMissingImage { break } else { return nil }
            }
            let cap = pickedImageCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            let captionPayload: CueSheet.MessagePayload? = cap.isEmpty ? nil : .init(text: cap, spans: [])
            e.payload = .image(.init(assetID: id, caption: captionPayload))

        case .cue:
            e.rehearsalMarkMode = rehearsalMarkMode == .off ? nil : rehearsalMarkMode

        default:
            break
        }

        if e.kind == .stop { e.holdSeconds = max(0, hold) }
        return e
    }

    private func applyAutoLabel(to event: inout CueSheet.Event) {
        let existing = event.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return }
        event.label = autoLabel(for: event)
    }

    private func autoLabel(for event: CueSheet.Event) -> String {
        defaultLabel(for: event)
    }

    private func composerPreviewEvent() -> CueSheet.Event? {
        guard var e = makeEventDraft(at: previewSeconds(), allowMissingImage: true) else { return nil }
        applyAutoLabel(to: &e)
        return e
    }

    private func previewDetail(for event: CueSheet.Event?) -> String? {
        guard let event else { return nil }
        switch event.kind {
        case .stop:
            return String(format: "Hold %.1f s", event.holdSeconds ?? 0)
        case .cue:
            return event.rehearsalMarkMode == .auto ? "Rehearsal mark: On" : "Rehearsal mark: Off"
        case .message:
            if case .message(let payload) = event.payload {
                let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = text.split(separator: "\n").first.map(String.init) ?? ""
                if !preview.isEmpty { return preview }
            }
            return nil
        case .image:
            if case .image(let payload) = event.payload,
               let caption = payload.caption?.text.trimmingCharacters(in: .whitespacesAndNewlines),
               !caption.isEmpty {
                return caption
            }
            return nil
        default:
            return nil
        }
    }

    // conversions (simple; your Kalman/engine still reigns for runtime)
    private func musicalToSecondsNew() -> Double {
            let beatsPerBar = Double(max(sheet.timeSigNum, 1))
            // Scale BPM (quarter-note) to current denominator (e.g., 8th notes are half a quarter)
            let secondsPerBeat = (60.0 / max(sheet.bpm, 1)) * (4.0 / Double(max(sheet.timeSigDen, 1)))
            let barBeats = Double(bar - 1) * beatsPerBar
            let beatBeats = Double(beat - 1)
            let slots = max(1, totalSlotsPerBeat)
            let idx = min(max(index, 1), slots)
            let subFrac = Double(idx - 1) / Double(slots)  // 0.0 at start of beat, up to <1.0
            let totalBeats = barBeats + beatBeats + subFrac
            let t = totalBeats * secondsPerBeat
            return max(0, t)
        }
    // MARK: - Anchoring utilities (Metered mode)
    private func anchorToSeconds(_ a: MusicalAnchor) -> Double {
           let beatsPerBar = Double(max(sheet.timeSigNum, 1))
           let secPerBeat  = (60.0 / max(sheet.bpm, 1)) * (4.0 / Double(max(sheet.timeSigDen, 1)))
        let subFrac     = Double(max(1, a.slot) - 1) / Double(max(1, a.slotsPerBeat))
               let totalBeats  = Double(a.bar - 1) * beatsPerBar + Double(a.beat - 1) + subFrac

           return max(0, totalBeats * secPerBeat)
       }
   
    /// Align sizes of parallel arrays; default legacy events to absolute.
        private func alignParallelState() {
            if origins.count != sheet.events.count || anchors.count != sheet.events.count {
                let n = sheet.events.count
                if origins.count != n {
                    if origins.isEmpty { origins = Array(repeating: .absolute, count: n) }
                    else { origins = Array(origins.prefix(n)) + Array(repeating: .absolute, count: max(0, n - origins.count)) }
                }
                if anchors.count != n {
                    if anchors.isEmpty { anchors = Array(repeating: nil, count: n) }
                    else { anchors = Array(anchors.prefix(n)) + Array(repeating: nil, count: max(0, n - anchors.count)) }
                }
            }
        }

   
       /// Recompute all event times from anchors, in place.
       private func recomputeAllFromAnchors() {
           let count = min(sheet.events.count, anchors.count, origins.count)
                   guard count > 0 else { return }
                   for i in 0..<count {
                       if origins[i] == .musical, let a = anchors[i] {
                           sheet.events[i].at = anchorToSeconds(a)
                       }

           }
    }
   
       /// Keep events and anchors in the same sort order by `at`.
       private func syncSortWithAnchors() {
           let n = sheet.events.count
                   guard anchors.count == n, origins.count == n else { return }
                   let zipped: [(CueSheet.Event, MusicalAnchor?, Origin)] =
                       (0..<n).map { (sheet.events[$0], anchors[$0], origins[$0]) }
                   let sorted = zipped.sorted { $0.0.at < $1.0.at }
                   sheet.events = sorted.map { $0.0 }
                   anchors      = sorted.map { $0.1 }
                   origins      = sorted.map { $0.2 }

       }
    
    private func parseTime(_ s:String)->Double {
        let clean = s.replacingOccurrences(of:",", with: ".")
        let parts = clean.split(separator: ":")
        if parts.count == 1 { return Double(clean) ?? 0 }
        if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let sc = Double(parts[1]) ?? 0
            return m*60 + sc
        }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let sc = Double(parts[2]) ?? 0
        return h*3600 + m*60 + sc
    }
// MARK: - Derived, normalization
    private var totalSlotsPerBeat: Int {
        max(1, grid.slotsPerBeat * tuplet.count)
    }
    private func normalizeIndex() {
        index = min(max(1, index), totalSlotsPerBeat)
    }
    private func normalizeBeatWrap() {
        let num = max(1, sheet.timeSigNum)
        if beat > num {
            beat = 1
            bar += 1
        } else if beat < 1 {
            beat = num
            bar -= 1
        }
    }
    private func previewSeconds() -> Double {
        (globalTiming == .absolute) ? parseTime(timeText) : musicalToSecondsNew()
    }
    // ── TEMPO helpers ───────────────────────────────────────────────
        private var tTotalSlotsPerBeat: Int {
            max(1, tGrid.slotsPerBeat * tTuplet.count)
        }
        private func tNormalizeIndex() {
            tIndex = min(max(1, tIndex), tTotalSlotsPerBeat)
        }
        private func tNormalizeBeatWrap() {
            let num = max(1, sheet.timeSigNum)
            if tBeat > num { tBeat = 1; tBar += 1 }
            else if tBeat < 1 { tBeat = num; tBar -= 1 }
        }
    private func tMusicalToSeconds() -> Double {
           let beatsPerBar = Double(max(sheet.timeSigNum, 1))
           let secondsPerBeat = (60.0 / max(sheet.bpm, 1)) * (4.0 / Double(max(sheet.timeSigDen, 1)))
            let barBeats = Double(tBar - 1) * beatsPerBar
            let beatBeats = Double(tBeat - 1)
            let slots = max(1, tTotalSlotsPerBeat)
            let idx = min(max(tIndex, 1), slots)
            let subFrac = Double(idx - 1) / Double(slots)
            let totalBeats = barBeats + beatBeats + subFrac
            return max(0, totalBeats * secondsPerBeat)
        }
    private func tPreviewSeconds() -> Double { tMusicalToSeconds() }
    private func addTempoChange() {
        // Musical only (section hidden when not metered)
        let targetBar = max(1, tBar)

            let bpmVal = max(20, min(300, tBPM))
            sheet.tempoChanges.append(CueSheet.TempoChange(atBar: targetBar, bpm: bpmVal))
            sheet.tempoChanges.sort { (lhs, rhs) in lhs.atBar < rhs.atBar }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    // ── METER helpers ───────────────────────────────────────────────
    private func snapDen(_ den: Int) -> Int {
           // Snap arbitrary input to nearest preset
           guard let nearest = presetDenoms.min(by: { abs($0 - den) < abs($1 - den) }) else { return 4 }
           return nearest
       }

       private func gridForDen(_ den: Int) -> NoteGrid {
           switch den {
           case 1:  return .whole
           case 2:  return .half
           case 4:  return .quarter
           case 8:  return .eighth
           case 16: return .sixteenth
           default: return .thirtySecond
           }
       }
    private func mPreviewLabel() -> String { "Bar \(mBar)" }
       private func addMeterChange() {
           // Musical only (section hidden when not metered)
            let atBar = max(1, mBar)

           let num = max(1, mNum)
           let den = presetDenoms.contains(mDen) ? mDen : snapDen(mDen)

           sheet.meterChanges.append(CueSheet.MeterChange(atBar: atBar, num: num, den: den))
           sheet.meterChanges.sort { $0.atBar < $1.atBar }
           UIImpactFeedbackGenerator(style: .light).impactOccurred()
       }

}

// Reuse pieces from your earlier safe components
private struct CueColorDots: View {
    @Binding var selectedIndex: Int
    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(palette.indices, id: \.self) { i in
                Circle().fill(palette[i]).frame(width: 22, height: 22)
                    .overlay {
                        if i == selectedIndex { Circle().stroke(Color.primary, lineWidth: 2) }
                    }
                    .onTapGesture { selectedIndex = i }
            }
        }
    }
}
// Musical subdivision choices (expressed in beats where a quarter-note = 1 beat).
private enum NoteGrid: String, CaseIterable, Identifiable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond
    var id: String { rawValue }
    /// Asset names expected in the app bundle / asset catalog.
    var assetName: String {
        switch self {
        case .whole:        return "note_whole"
        case .half:         return "note_half"
        case .quarter:      return "note_quarter"
        case .eighth:       return "note_eighth"
        case .sixteenth:    return "note_sixteenth"
        case .thirtySecond: return "note_thirtySecond"
        }
    }
    /// Unicode fallback when the asset is missing (defensive).
        var fallback: String {
            switch self {
            case .whole:        return "♩×4"
            case .half:         return "♩×2"
            case .quarter:      return "♩"
            case .eighth:       return "♪"
            case .sixteenth:    return "♫"
            case .thirtySecond: return "♬"
            }
        }

    /// Fraction of a beat (quarter = 1.0). Dotted = ×1.5. Triplet = ×(2/3).
    func fraction(dotted: Bool, triplet: Bool) -> Double {
        let base: Double = {
            switch self {
            case .whole: return 4.0
            case .half: return 2.0
            case .quarter: return 1.0
            case .eighth: return 0.5
            case .sixteenth: return 0.25
            case .thirtySecond: return 0.125
            }
        }()
        var f = base
        if dotted { f *= 1.5 }
        if triplet { f *= (2.0/3.0) }
        return f
    }
    /// How many equal **slots inside one beat** this grid implies (for tapping/indexing).
       /// Coarser than a beat (whole/half) are treated as 1 slot-per-beat for targeting.
       var slotsPerBeat: Int {
           switch self {
           case .quarter:      return 1
           case .eighth:       return 2
           case .sixteenth:    return 4
           case .thirtySecond: return 8
           case .whole, .half: return 1
           }
       }
    }
   
   /// Tuplet / polyrhythm selection (m in the time of n). Off means 1:1.
   private enum TupletMode: Equatable, Hashable {
       case off
       case triplet       // 3:2
       case quintuplet    // 5:4
       case septuplet     // 7:4
       case custom(m: Int, n: Int?)   // m:n (n is for labeling)
   
       var count: Int {
           switch self {
           case .off: return 1
           case .triplet: return 3
           case .quintuplet: return 5
           case .septuplet: return 7
           case .custom(let m, _): return max(1, m)
           }
       }
       var label: String {
           switch self {
           case .off: return "polyrhythm"
           case .triplet: return "3:2"
           case .quintuplet: return "5:4"
           case .septuplet: return "7:4"
           case .custom(let m, let n): return n != nil ? "\(m):\(n!)" : "\(m):?"
           }
       }
   }


/// Renders a bundled note glyph, falling back to Unicode if the asset is missing.
@ViewBuilder
private func NoteGlyph(_ grid: NoteGrid, height: CGFloat = 14, vpad: CGFloat = 5) -> some View {
    if let ui = UIImage(named: grid.assetName) {
        let glyphWidth = height
        let targetHeight = glyphWidth * 1.2
        Image(uiImage: ui)
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: glyphWidth, height: targetHeight)
            .padding(.vertical, vpad + 2) // makes segmented control a bit taller
            .accessibilityLabel(Text(grid.fallback))
    } else {
        Text(grid.fallback)
            .font(.system(size: height)) // match visual size to image
            .padding(.vertical, vpad)
    }
}


private struct EventRow: View {
    @Binding var event: CueSheet.Event
    var timeLabel: String
    var onTapTime: () -> Void
    var onDelete: () -> Void
    @State private var messagePreview: String = ""
    @State private var previewWorkItem: DispatchWorkItem?



    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .imageScale(.large)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kindTitle)
                            .font(.custom("Roboto-SemiBold", size: 15))
                        if let pill = metadataPill {
                            Text(pill)
                                .font(.custom("Roboto-Regular", size: 12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete event")
            }

            TextField(defaultLabel(for: event), text: Binding(
                get: { event.label ?? "" },
                set: { event.label = $0.isEmpty ? nil : $0 }
            ))
            .font(.custom("Roboto-SemiBold", size: 17))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: onTapTime) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .imageScale(.medium)
                            Text(timeLabel)
                                .font(.custom("Roboto-Regular", size: 14))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("Tap for seconds")
                        .font(.custom("Roboto-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if event.kind == .cue {
                    Menu {
                        Button("On") { event.rehearsalMarkMode = .auto }
                        Button("Off") { event.rehearsalMarkMode = nil }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: event.rehearsalMarkMode == .auto ? "a.circle.fill" : "a.circle")
                            Text(event.rehearsalMarkMode == .auto ? "Rehearsal Mark" : "Mark Off")
                                .font(.custom("Roboto-Regular", size: 13))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                } else if event.kind == .stop {
                    Text("Hold \(event.holdSeconds ?? 0, specifier: "%.2f") s")
                        .font(.custom("Roboto-Regular", size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            if let detail = detailText {
                Text(detail)
                    .font(.custom("Roboto-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let imagePreview = imagePreview {
                HStack(alignment: .center, spacing: 10) {
                    imagePreview
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        if let caption = imageCaption, !caption.isEmpty {
                            Text(caption)
                                .font(.custom("Roboto-Regular", size: 13))
                                .lineLimit(2)
                        } else {
                            Text("Image payload")
                                .font(.custom("Roboto-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(glassCardBackground())
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .onAppear {
            syncMessagePreview()
        }
        .onChange(of: messageSourceText) { newValue in
            schedulePreviewUpdate(with: newValue)
        }
        .onDisappear {
            previewWorkItem?.cancel()
        }

    }

    private var iconName: String {
        switch event.kind {
        case .cue:     return "bolt.fill"
        case .stop:    return "hand.raised.fill"
        case .restart: return "gobackward"
        case .message: return "text.bubble"
        case .image:   return "photo"
        default:       return "questionmark"
        }
    }

    private var kindTitle: String {
        switch event.kind {
        case .cue: return "Cue"
        case .stop: return "Stop"
        case .restart: return "Restart"
        case .message: return "Message"
        case .image: return "Image"
        default: return "Event"
        }
    }

    private var metadataPill: String? {
        switch event.kind {
        case .stop:
            if let hold = event.holdSeconds { return String(format: "Hold %.1fs", hold) }
            return nil
        case .cue:
            return event.rehearsalMarkMode == .auto ? "Rehearsal Mark On" : nil
        default:
            return nil
        }
    }

    private var detailText: String? {
        switch event.kind {
        case .message:
            let preview = messagePreview.isEmpty ? trimmedFirstLine(from: messageSourceText) : messagePreview
            return preview.isEmpty ? nil : preview
        default:
            return nil
        }
    }

    private var imageCaption: String? {
        if case .image(let payload) = event.payload {
            return payload.caption?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private var imagePreview: Image? {
        if case .image(let payload) = event.payload,
           let data = CueLibraryStore.shared.assetData(id: payload.assetID),
           let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return nil
    }

    private var messageSourceText: String {
        if case .message(let payload)? = event.payload {
            return payload.text
        }
        return ""
    }

    private func trimmedFirstLine(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine
    }

    private func syncMessagePreview() {
        messagePreview = trimmedFirstLine(from: messageSourceText)
    }

    private func schedulePreviewUpdate(with text: String) {
        previewWorkItem?.cancel()
        let item = DispatchWorkItem {
            messagePreview = trimmedFirstLine(from: text)
        }
        previewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }
}
// MARK: - Fraction Meter Control (Num / Den)
private struct FractionMeterControl: View {
    @Binding var numerator: Int
    @Binding var denominator: Int
    let presetDenominators: [Int]

    @FocusState private var focusField: Field?
    enum Field { case num, den }

    // Drag state for smooth +/- with haptics
    @State private var dragAccumNum: CGFloat = 0
    @State private var dragAccumDen: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 20) {
                valueColumn(
                    title: "No. of Beats (top)",
                    value: Binding(
                        get: { numerator },
                        set: { numerator = clampNum($0) }
                    ),
                    field: .num,
                    dragAccum: $dragAccumNum,
                    stepper: { deltaNum($0) }
                )
                divider
                valueColumn(
                    title: "Unit Pulse (bottom)",
                    value: Binding(
                        get: { denominator },
                        set: { denominator = snapDen($0) }
                    ),
                    field: .den,
                    dragAccum: $dragAccumDen,
                    stepper: { deltaDen($0) }
                )
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 48)
    }

    private func valueColumn(title: String,
                             value: Binding<Int>,
                             field: Field,
                             dragAccum: Binding<CGFloat>,
                             stepper: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 6) {
            Text(title)
                            .font(.custom("Roboto-Regular", size: 13))
                            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { stepper(-1) } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                TextField("", value: value, formatter: NumberFormatter.integer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.custom("Roboto-SemiBold", size: 22)).monospacedDigit()
                    .frame(minWidth: 52)
                    .focused($focusField, equals: field)
                Button { stepper(1) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { g in
                        let dy = -g.translation.height
                        var acc = dragAccum.wrappedValue + dy
                        // Every ~16pt = 1 tick
                        let tick = Int(acc / 16.0)
                        if tick != 0 {
                            stepper(tick)
                            acc -= CGFloat(tick) * 16.0
                            light()
                        }
                        dragAccum.wrappedValue = acc
                    }
                    .onEnded { _ in dragAccum.wrappedValue = 0 }
            )
        }
    }

    // MARK: helpers
    private func clampNum(_ n: Int) -> Int { max(1, min(64, n)) }
    private func snapDen(_ d: Int) -> Int {
        guard let nearest = presetDenominators.min(by: { abs($0 - d) < abs($1 - d) }) else { return 4 }
        return nearest
    }
    private func deltaNum(_ delta: Int) {
        numerator = clampNum(numerator + delta)
    }
    private func deltaDen(_ delta: Int) {
        if let idx = presetDenominators.firstIndex(of: denominator) {
            let newIdx = max(0, min(presetDenominators.count - 1, idx + delta))
            denominator = presetDenominators[newIdx]
        } else {
            denominator = snapDen(denominator)
        }
    }
    private func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
private extension Double {
    func rounded(to places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}

private extension NumberFormatter {
    static let integer: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximumFractionDigits = 0
        return f
    }()
}

// MARK: - Entry controls
private struct MusicalEntry: View {
    @Binding var bar: Int
    @Binding var beat: Int
    @Binding var grid: NoteGrid
    @Binding var dotted: Bool
    @Binding var triplet: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                            Stepper(value: $bar, in: -32...9999) {
                                Text("Bar \(bar)").font(.custom("Roboto-Regular", size: 15))
                            }
                            Stepper(value: $beat, in: 1...64) {
                                Text("Beat \(beat)").font(.custom("Roboto-Regular", size: 15))
                            }
                        }

            HStack {
                Picker("Grid", selection: $grid) {
                    ForEach(NoteGrid.subdivisionsOnly) { g in NoteGlyph(g, height: 32, vpad: 5).tag(g) }
                }
                .pickerStyle(.segmented)

            }
            HStack(spacing: 16) {
                Toggle(isOn: Binding(
                    get: { dotted },
                    set: { new in
                        dotted = new
                        if new { triplet = false } // keep exclusive
                    }
                )) {
                                    Text("Dotted").font(.custom("Roboto-Regular", size: 15))
                                }
                                Toggle(isOn: Binding(

                    get: { triplet },
                    set: { new in
                        triplet = new
                        if new { dotted = false } // keep exclusive
                    }
                                )) {
                                                    Text("Triplet").font(.custom("Roboto-Regular", size: 15))
                                                }

            }
        }
    }
}


// MARK: - Beat Grid Pad
/// Shows `beats` columns, each with `slotsPerBeat` tappable subcells.
/// Tapping sets (selectedBeat, selectedIndex).
private struct BeatGridPad: View {
    let beats: Int
    let slotsPerBeat: Int
    @Binding var selectedBeat: Int
    @Binding var selectedIndex: Int

    private let cellW: CGFloat = 32
    private let cellH: CGFloat = 28
    private let gap: CGFloat   = 6
    private let labelH: CGFloat = 14
    private let minSingleChipWidth: CGFloat = 56 // prevents "Beat 10" from truncating

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(1...max(1, beats), id: \.self) { b in
                    let chips = max(1, slotsPerBeat)
                    let baseWidth = CGFloat(chips) * cellW + CGFloat(max(chips - 1, 0)) * gap
                    let width = chips == 1 ? max(baseWidth, minSingleChipWidth) : baseWidth

                    Group {
                        if chips == 1 {
                            VStack(alignment: .center, spacing: 6) {
                                Text("Beat \(b)")
                                    .font(.custom("Roboto-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                                    .frame(width: width, height: labelH, alignment: .center)

                                HStack(spacing: gap) {
                                    beatCells(beat: b, chips: chips)
                                }
                                .frame(width: width, alignment: .center)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Beat \(b)")
                                    .font(.custom("Roboto-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: width, height: labelH, alignment: .leading)

                                HStack(spacing: gap) {
                                    beatCells(beat: b, chips: chips)
                                }
                            }
                        }
                    }

                    // vertical divider between beats
                    if b < max(1, beats) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 1, height: cellH + labelH + 12)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 72)
    }

    @ViewBuilder
    private func beatCells(beat b: Int, chips: Int) -> some View {
        ForEach(1...chips, id: \.self) { s in
            let isSel = (b == selectedBeat && s == selectedIndex)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSel ? Color.accentColor.opacity(0.25) : Color.clear)
                .frame(width: cellW, height: cellH)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSel ? Color.accentColor : Color.primary.opacity(0.15),
                                lineWidth: isSel ? 2 : 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedBeat = b
                    selectedIndex = s
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        }
    }
}
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
