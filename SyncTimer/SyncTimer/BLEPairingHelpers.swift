//
//  BLEPairingHelpers.swift
//  SyncTimer
//
//  A PDF417-based BLE pairing helper for SyncTimer
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import UIKit
import CoreBluetooth

// ── Your BLE service/characteristic UUIDs ───────────────────────
let timerServiceUUID        = CBUUID(string: "0000FEE0-0000-1000-8000-00805F9B34FB")
let driftCharacteristicUUID = CBUUID(string: "0000FEE1-0000-1000-8000-00805F9B34FB")

// ── Payload structure ───────────────────────────────────────────
private struct PairingPayload: Codable {
    let serviceUUID: String
    let charUUID:    String
    let deviceName:  String
    let hostAddress: String
    let port:        UInt16
}

// ─────────────────────────────────────────────────────────────────
// MARK: – PDF417GeneratorView (black bars on truly transparent bg)
// ─────────────────────────────────────────────────────────────────
struct PDF417GeneratorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: Data
    let height: CGFloat

    private let context = CIContext()
    private let filter  = CIFilter.pdf417BarcodeGenerator()

    var body: some View {
        GeometryReader { geo in
            if let ui = makeTransparentBarcode(
                size: CGSize(width: geo.size.width, height: height)
            ) {
                Image(uiImage: ui)
                  .resizable()
                  .interpolation(.none)
                  .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(height: height)
    }

    private func makeTransparentBarcode(size: CGSize) -> UIImage? {
        // 1) generate raw (black on white)
        filter.message         = payload
        filter.compactionMode  = 0.0    // automatic
        filter.correctionLevel = 2.0    // medium
        guard let raw = filter.outputImage else { return nil }

        // 2) invert so bars=white, bg=black
        let invert = CIFilter.colorInvert()
        invert.inputImage = raw
        guard let inverted = invert.outputImage else { return nil }

        // 3) make that inverted into an alpha mask (white→opaque, black→transparent)
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = inverted
        guard let alphaMask = mask.outputImage else { return nil }

        // 4) blend original raw over a clear background using that mask
        let blend = CIFilter.blendWithMask()
        // choose black or white bars based on current color scheme
                let barCI = CIImage(
                    color: CIColor(
                        red:   colorScheme == .dark ? 1 : 0,
                        green: colorScheme == .dark ? 1 : 0,
                        blue:  colorScheme == .dark ? 1 : 0,
                        alpha: 1
                    )
                ).cropped(to: raw.extent)
                blend.inputImage      = barCI
        blend.backgroundImage = CIImage(color: .clear).cropped(to: raw.extent)
        blend.maskImage       = alphaMask
        guard let outCI = blend.outputImage else { return nil }

        // 5) scale without blur
        let sx = size.width  / outCI.extent.width
        let sy = size.height / outCI.extent.height
        let scaled = outCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: – Scanner VC & SwiftUI wrapper
// ─────────────────────────────────────────────────────────────────
protocol PDF417ScannerDelegate: AnyObject {
    func didFind(data: Data)
}

class ScannerViewController: UIViewController,
                              AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: PDF417ScannerDelegate?
    private let session = AVCaptureSession()
    private let output  = AVCaptureMetadataOutput()
    
    // keep a strong reference so we can convert points
    private var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // 1) camera input
        guard let device = AVCaptureDevice.default(for: .video),
              let input  = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        // 2) metadata output (PDF417)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.pdf417]

        // 3) preview
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame        = view.bounds
        view.layer.addSublayer(previewLayer)

        // 4) gestures
        let singleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleFocusTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTap)

        // 5) start
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    // MARK: – PDF417 detection
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first,
              obj.type == .pdf417,
              let s = obj.stringValue,
              let d = s.data(using: .utf8)
        else { return }
        session.stopRunning()
        delegate?.didFind(data: d)
    }

    // MARK: – single-tap: focus & expose
    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let point    = previewLayer.captureDevicePointConverted(
                         fromLayerPoint: location
                       )
        guard let input = session.inputs.first as? AVCaptureDeviceInput else { return }
        let device = input.device

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("❌ failed to lock for focus/exposure:", error)
        }
    }

    // MARK: – double-tap: switch cameras
    @objc private func handleSwitchCamera(_ gesture: UITapGestureRecognizer) {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        let currentPos = currentInput.device.position
        let newPos: AVCaptureDevice.Position = (currentPos == .back) ? .front : .back

        guard let newDevice = AVCaptureDevice.default(
                  .builtInWideAngleCamera,
                  for: .video,
                  position: newPos
              ),
              let newInput = try? AVCaptureDeviceInput(device: newDevice)
        else { return }

        session.beginConfiguration()
        session.removeInput(currentInput)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
        } else {
            // if we can’t add the new one, put the old one back
            session.addInput(currentInput)
        }
        session.commitConfiguration()
    }
}


struct PDF417ScannerView: UIViewControllerRepresentable {
    let onFound: (Data) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFound) }
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_: ScannerViewController, context _: Context) {}
    class Coordinator: NSObject, PDF417ScannerDelegate {
        let onFound: (Data)->Void
        init(_ f: @escaping (Data)->Void) { onFound = f }
        func didFind(data: Data) { onFound(data) }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: – BLEPairingView (single, same-sized rounded rect)
// ─────────────────────────────────────────────────────────────────
struct BLEPairingView: View {
    @EnvironmentObject private var syncSettings: SyncSettings
    @State private var showingScanner = false
    @State private var lastError: String?
    @Environment(\.colorScheme) private var colorScheme


    // ── Layout constants
    private let codeHeight: CGFloat   = 60
    private let cornerRadius: CGFloat = 8

    // ── JSON encoder for stable payloads
    private var jsonEncoder: JSONEncoder {
        var e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }

    // ── Parent’s static payload
    private var parentPayload: Data {
       let p = PairingPayload(
        serviceUUID: timerServiceUUID.uuidString,
        charUUID:    driftCharacteristicUUID.uuidString,
        deviceName:  "TimerParent",
        hostAddress: syncSettings.listenerIPAddress,
        port:         syncSettings.listenerPort
    )
        let json = (try? jsonEncoder.encode(p)) ?? Data()
            if let s = String(data: json, encoding: .utf8) {
              print("🔥 parentPayload JSON →", s)
            }
            return json     }

    // ── “X” button to cancel/reset
    private var xButton: some View {
        Button {
            showingScanner = false
            syncSettings.pairingServiceUUID        = nil
            syncSettings.pairingCharacteristicUUID = nil
            syncSettings.pairingDeviceName         = nil
            lastError = nil
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(.secondary)
                .padding(6)
        }
    }

    // ── Container that’s always the same size and transparent
    @ViewBuilder
    private func pairingContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(height: codeHeight)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // ── Handle a scan result
    private func handleScan(_ data: Data) {
        do {
            let pairing = try JSONDecoder().decode(PairingPayload.self, from: data)
            print("🔥 scanned PairingPayload →", pairing)
            // … now extract:
            let svcStr  = pairing.serviceUUID
            let charStr = pairing.charUUID
            let devName = pairing.deviceName
            let host    = pairing.hostAddress
            let port    = pairing.port

            DispatchQueue.main.async {
                syncSettings.pairingServiceUUID        = CBUUID(string: svcStr)
                syncSettings.pairingCharacteristicUUID = CBUUID(string: charStr)
                syncSettings.pairingDeviceName         = devName
                syncSettings.parentIPAddress           = host
                syncSettings.parentPort                = port
                lastError = nil

                syncSettings.bleDriftManager.stop()
                syncSettings.role = .child
                syncSettings.bleDriftManager.start()
            }
        } catch {
            print("❌ handleScan decoding error:", error)
            lastError = error.localizedDescription
        }
    }


    var body: some View {
        VStack(spacing: 12) {
            if syncSettings.role == .parent {
                pairingContainer {
                    PDF417GeneratorView(payload: parentPayload, height: codeHeight)
                }
                .onAppear {
                  // 1) start your TCP listener so listenerIPAddress is populated
                  syncSettings.startParent()
                  // 2) then start BLE peripheral
                  // syncSettings.bleDriftManager.start()
                }


                Text("Have your child scan this code.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

            } else {
                // ── CHILD MODE ────────────────────────────

                // 1. If we already have stored pairing info, show it + X
                if
                    let svc     = syncSettings.pairingServiceUUID,
                    let char    = syncSettings.pairingCharacteristicUUID,
                    let devName = syncSettings.pairingDeviceName
                {
                    let p = PairingPayload(
                        serviceUUID: svc.uuidString,
                        charUUID:    char.uuidString,
                        deviceName:  devName,
                        hostAddress: syncSettings.parentIPAddress!,
                        port:        syncSettings.parentPort!
                    )
                    let data = (try? jsonEncoder.encode(p)) ?? Data()

                    pairingContainer {
                        PDF417GeneratorView(payload: data, height: codeHeight)
                    }
                    .overlay(xButton, alignment: .topTrailing)
                    .onAppear {
                        syncSettings.bleDriftManager.stop()
                        syncSettings.bleDriftManager.start()
                    }

                }
                // 2. Else if in scanning mode, show live camera + X
                else if showingScanner {
                    pairingContainer {
                        PDF417ScannerView { data in
                            showingScanner = false
                            handleScan(data)
                        }
                    }
                    .overlay(xButton, alignment: .topTrailing)

                }
                // 3. Else: show the “tap to scan” placeholder
                else {
                    pairingContainer {
                        Button {
                            showingScanner = true
                        } label: {
                            VStack {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 24))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text("Scan pairing code")
                                    .font(.headline)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                
                            }
                        }
                    }
                }

                // Any error text
                if let err = lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}
