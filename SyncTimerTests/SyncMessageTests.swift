//
//  SyncMessageTests.swift
//  SyncTimerTests
//

import Testing
import UIKit
@testable import SyncTimer

struct SyncMessageTests {

    @Test func sheetSnapshotDecodesLegacyPayload() throws {
        let sheet = CueSheet(
            title: "Legacy Sheet",
            notes: nil,
            timeSigNum: 4,
            timeSigDen: 4,
            bpm: 120,
            tempoChanges: [],
            meterChanges: [],
            events: []
        )

        let message = SyncMessage.sheetSnapshot(sheet)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        guard case let .sheetSnapshot(decodedSheet) = decoded else {
            Issue.record("Expected sheetSnapshot message")
            return
        }

        #expect(decodedSheet.title == sheet.title)
    }

    @Test func sheetSnapshotEmbedsAssets() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let data = try #require(image.pngData())
        let assetID = try CueLibraryStore.shared.ingestImage(data: data, preferLossy: false)

        let event = CueSheet.Event(
            kind: .image,
            at: 0,
            holdSeconds: nil,
            label: "Test Image",
            payload: .image(.init(assetID: assetID))
        )
        let sheet = CueSheet(
            title: "Asset Sheet",
            notes: nil,
            timeSigNum: 4,
            timeSigDen: 4,
            bpm: 120,
            tempoChanges: [],
            meterChanges: [],
            events: [event]
        )

        let message = SyncMessage.sheetSnapshot(sheet)
        let encoded = try JSONEncoder().encode(message)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let snapshot = try #require(json["sheetSnapshot"] as? String)
        let xmlData = try #require(Data(base64Encoded: snapshot))
        let xml = String(data: xmlData, encoding: .utf8) ?? ""

        #expect(xml.contains("<assets>"))
        #expect(xml.contains(assetID.uuidString))
    }
}
