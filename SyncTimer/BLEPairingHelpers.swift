//
//  BLEPairingHelpers.swift
//  SyncTimer
//
//  Camera-based pairing removed. This file contains only BLE-related
//  helpers + a harmless stub for DataScannerWrapper so we never touch camera.
//

import SwiftUI
import CoreBluetooth
import CoreImage.CIFilterBuiltins // optional; safe to remove if you don't render PDF417

// ── Your BLE service/characteristic UUIDs ───────────────────────
let timerServiceUUID        = CBUUID(string: "0000FEE0-0000-1000-8000-00805F9B34FB")
let driftCharacteristicUUID = CBUUID(string: "0000FEE1-0000-1000-8000-00805F9B34FB")

// ── Payload structure (kept for compatibility) ──────────────────
private struct PairingPayload: Codable {
    let serviceUUID: String
    let charUUID:    String
    let deviceName:  String
    let hostAddress: String
    let port:        UInt16
}

// ── No-op scanner stub (prevents camera linking & crashes) ──────
// If any UI still tries to present the old scanner, it safely shows nothing.
@available(iOS 16.0, *)
struct DataScannerWrapper: View {
    init(onFound: @escaping (Data) -> Void) { /* no camera */ }
    var body: some View { EmptyView() }
}

// ── (Optional) If you rendered PDF417 codes somewhere, you can keep this helper. ──
func makePDF417Image(from text: String, scale: CGFloat = 3) -> UIImage? {
    let data = Data(text.utf8)
    let context = CIContext()
    let filter = CIFilter(name: "CIPDF417BarcodeGenerator")
    filter?.setValue(data, forKey: "inputMessage")
    guard let outputImage = filter?.outputImage else { return nil }
    let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    if let cg = context.createCGImage(scaled, from: scaled.extent) {
        return UIImage(cgImage: cg)
    }
    return nil
}
