// BLEDriftManager.swift
// (Place this alongside SyncTimerApp.swift in your project)

import Foundation
import CoreBluetooth

extension Notification.Name {
  static let parentDidStop = Notification.Name("parentDidStop")
}


struct DriftRequest: Codable {
    let requestTimestamp: TimeInterval
    let elapsedSeconds: TimeInterval
}

struct DriftResponse: Codable {
    let requestTimestamp: TimeInterval
    let responseTimestamp: TimeInterval
    let elapsedSeconds: TimeInterval
}

final class BLEDriftManager: NSObject {
    // Weak reference back to your SyncSettings (so you can read “elapsed”)
    private weak var owner: SyncSettings?
    var central: CBCentralManager { centralManager }

    
    // MARK: – Parent (Peripheral) side
    private var peripheralManager: CBPeripheralManager!
    private var driftCharacteristic: CBMutableCharacteristic?
    private var driftTimer: Timer?
    
    
    // MARK: – Child (Central) side
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var driftCharOnPeripheral: CBCharacteristic?
    
    // Remember whether we’re supposed to be “started” as parent or child.
    // Once powered on, the delegate method will pick up this flag.
    private var shouldActAsParent = false
    private var shouldActAsChild = false
    
    init(owner: SyncSettings) {
        self.owner = owner
        super.init()
        
        // Create them with delegates, but do NOT call any BLE APIs here.
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager    = CBCentralManager(delegate: self, queue: nil)
    }
    
    func start() {
        guard let role = owner?.role else { return }
        print("BLEDriftManager.start() as \(role)")
        switch role {
        case .parent:
            shouldActAsParent = true
            if peripheralManager.state == .poweredOn {
                print("Parent: setting up peripheral immediately")
                setupParentPeripheral()
            }
        case .child:
            shouldActAsChild = true
            // if already powered on, kick off scan immediately; otherwise delegate will handle it
            if centralManager.state == .poweredOn {
                centralManagerDidUpdateState(centralManager)
            }
        }
    }

    
    
    /// Called by SyncSettings whenever you disable sync or switch out of Bluetooth.
    func stop() {
        // 1) Stop any pending drift‐timer
        driftTimer?.invalidate()
        driftTimer = nil
        
        // 2) Tear down *both* peripheral & central
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        driftCharacteristic = nil
        
        centralManager.stopScan()
        if let p = discoveredPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        discoveredPeripheral = nil
        driftCharOnPeripheral = nil
        
        // 3) Clear your flags
        shouldActAsParent = false
        shouldActAsChild  = false
        
        // 🛑 Notify any listeners that parent has stopped
        NotificationCenter.default.post(name: .parentDidStop, object: nil)
        
            }


    // ────────────────────────────────────────────────────────────
    // MARK: – Parent setup (CBPeripheralManager)
    private func setupParentPeripheral() {
        // don’t re‐run this if we already did
            guard driftCharacteristic == nil else {
              print("Parent: setupParentPeripheral already called, skipping")
              return
            }
            // 1) Create the characteristic
            let props: CBCharacteristicProperties    = [.notify, .writeWithoutResponse]
            let perms: CBAttributePermissions         = [.readable, .writeable]
            let char = CBMutableCharacteristic(
                type:        driftCharacteristicUUID,
                properties:  props,
                value:       nil,
                permissions: perms
            )
            driftCharacteristic = char

        // 2) Create and add the service
        let timerService = CBMutableService(type: timerServiceUUID, primary: true)
        timerService.characteristics = [driftCharacteristic!]
        peripheralManager.add(timerService)
    }


    /// Every 5 s (once a child has subscribed) we send a DriftRequest
    private func sendDriftRequestIfNeeded() {
        guard owner?.role == .parent else { return }
        guard let driftChar = driftCharacteristic else { return }

        let tReq = Date().timeIntervalSince1970
        let eReq = owner?.getCurrentElapsed() ?? 0

        let packet = DriftRequest(requestTimestamp: tReq, elapsedSeconds: eReq)
        guard let data = try? JSONEncoder().encode(packet) else { return }

        peripheralManager.updateValue(data,
                                      for: driftChar,
                                      onSubscribedCentrals: nil)
    }

    /// Parent receives child’s write here
    private func handleWriteFromChild(_ data: Data) {
        // First try decode as DriftResponse
        if let resp = try? JSONDecoder().decode(DriftResponse.self, from: data) {
            handleDriftResponse(resp)
        }
        // Else ignore or decode other packet types if you like
    }

    private func handleDriftResponse(_ resp: DriftResponse) {
        let tReq      = resp.requestTimestamp
        let tChild    = resp.responseTimestamp
        let eChild    = resp.elapsedSeconds
        let tMasterRx = Date().timeIntervalSince1970
        let rtt       = tMasterRx - tReq
        let offset    = tChild - (tReq + rtt/2)

        // Now compute drift:
        let eMasterAtReq   = owner?.getElapsedAt(timestamp: tReq) ?? 0
        let eMasterAtChild = eMasterAtReq + (tChild - tReq)
        let drift          = eChild - eMasterAtChild

        if abs(drift) > 0.005 {
            // Send a one‐shot correction
            let correction = -drift
            if let corrData = try? JSONEncoder().encode(correction),
               let driftChar = driftCharacteristic
            {
                peripheralManager.updateValue(corrData,
                                              for: driftChar,
                                              onSubscribedCentrals: nil)
            }
        }
    }

    // ────────────────────────────────────────────────────────────
    // MARK: – Child setup (CBCentralManager)

    private func handleDriftRequest(_ req: DriftRequest) {
        let tChildRecv = Date().timeIntervalSince1970
        let eChild     = owner?.getCurrentElapsed() ?? 0

        let response = DriftResponse(
            requestTimestamp: req.requestTimestamp,
            responseTimestamp: tChildRecv,
            elapsedSeconds: eChild
        )
        guard let data       = try? JSONEncoder().encode(response),
              let char       = driftCharOnPeripheral,
              let peripheral = discoveredPeripheral
        else { return }

        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }

    private func handleDriftCorrection(_ data: Data) {
        if let correction = try? JSONDecoder().decode(Double.self, from: data) {
            NotificationCenter.default.post(
                name: .driftCorrectionReceived,
                object: correction
            )
        }
    }
}

// ───────────────────────────────────────────────────────────────────
// MARK: – CBPeripheralManagerDelegate (Parent)
extension BLEDriftManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            // Only if we’ve been asked to act as parent
            if shouldActAsParent {
                setupParentPeripheral()
            }
        default:
            // If we lose power, tear down everything
            stop()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didAdd service: CBService,
                           error: Error?) {
        if error == nil {
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [timerServiceUUID],
                CBAdvertisementDataLocalNameKey: "TimerParent"
            ])
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager,
                                              error: Error?) {
        if let err = error {
            print("Parent: Advertising failed: \(err.localizedDescription)")
        } else {
            print("Parent: Advertising \(timerServiceUUID)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        print("Parent: central \(central) DID subscribe to \(characteristic.uuid)")
        if driftTimer == nil {
          driftTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendDriftRequestIfNeeded()
          }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        // Look at the characteristic’s subscribedCentrals, not the manager’s
        if driftCharacteristic?.subscribedCentrals?.isEmpty ?? true {
            driftTimer?.invalidate()
            driftTimer = nil
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if req.characteristic.uuid == driftCharacteristicUUID,
               let data = req.value {
                handleWriteFromChild(data)
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
// MARK: – CBCentralManagerDelegate (Child)
// MARK: – CBCentralManagerDelegate (Child)
extension BLEDriftManager: CBCentralManagerDelegate, CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // only scan if we’ve been asked to act as child
            guard shouldActAsChild else {
                print("Child: not in child mode, ignoring central state = \(central.state)")
                return
            }
            // pick the scanned service UUID (or fallback to your default)
            let serviceUUIDs = owner?.pairingServiceUUID.map { [$0] } ?? [timerServiceUUID]
            // set up scan options (no duplicates + optional device-name filter)
            var options: [String:Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
            if let name = owner?.pairingDeviceName {
                options[CBAdvertisementDataLocalNameKey] = name
            }
            print("Child: central poweredOn → scanning for \(serviceUUIDs) with options \(options)")
            central.scanForPeripherals(withServices: serviceUUIDs, options: options)

        default:
            // if we lose power or exit child mode, stop scanning
            if shouldActAsChild {
                central.stopScan()
                print("Child: central state \(central.state) → stopped scanning")
            }
        }
    }


        private func startScanningAsChild() {
            // only scan if we've actually stored a pairing service UUID
            guard let svcUUID = owner?.pairingServiceUUID else {
                print("Child: no pairingServiceUUID set, not scanning")
                return
            }
            print("Child: scanning for service \(svcUUID)")
            let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            centralManager.scanForPeripherals(
                withServices: [svcUUID],
                options: options
            )
        }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        // log everything we see on discovery
        print("Child: discovered \(peripheral.name ?? "<no name>") [\(peripheral.identifier)] → advData:", advertisementData)

        // optionally filter by name here (but _not_ in scan options)
        if let expected = owner?.pairingDeviceName,
           let advName  = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           advName != expected {
            print("Child: ignoring '\(advName)' – expecting '\(expected)'")
            return
        }

        // ── NEW: convert RSSI to 0…3 bars ───────────────────────────────
        let rssiValue = RSSI.intValue
        let bars: Int
        switch rssiValue {
        case ..<(-90):
            bars = 0
        case -90..<(-70):
            bars = 1
        case -70..<(-50):
            bars = 2
        default:
            bars = 3
        }

        // report this peer into your syncSettings
        owner?.addDiscoveredService(
            name: peripheral.name ?? "Unknown",
            role: .child,          // scanning as child
            signal: bars
        )
        // ────────────────────────────────────────────────────────────────

        // bingo—stop scanning and connect
        centralManager.stopScan()
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        print("Child: connecting to \(peripheral.name ?? "<no-name>")")
    }

        
        
        func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print("Child: didConnect to \(peripheral.name ?? "<no-name>")")
        peripheral.discoverServices([timerServiceUUID])
    }
        
        func centralManager(_ central: CBCentralManager,
                            didFailToConnect peripheral: CBPeripheral,
                            error: Error?) {
            cleanupPeripheral(peripheral)
        }
        
        func centralManager(_ central: CBCentralManager,
                            didDisconnectPeripheral peripheral: CBPeripheral,
                            error: Error?) {
            cleanupPeripheral(peripheral)
        }
        
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        print("Child: didDiscoverServices:", peripheral.services ?? [])
        guard let svcs = peripheral.services else { return }
        for svc in svcs where svc.uuid == timerServiceUUID {
            peripheral.discoverCharacteristics([driftCharacteristicUUID], for: svc)
            return
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        print("Child: didDiscoverCharacteristicsFor", service.uuid, service.characteristics ?? [])
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == driftCharacteristicUUID {
            driftCharOnPeripheral = char
            print("Child: subscribing to drift characteristic")
            peripheral.setNotifyValue(true, for: char)
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let err = error {
            print("Child: subscribe failed:", err)
        } else {
            print("Child: isNotifying =", characteristic.isNotifying)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let err = error {
            print("Child: Notification error: \(err.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }

        if let req = try? JSONDecoder().decode(DriftRequest.self, from: data) {
            handleDriftRequest(req)
        }
        else if let _ = try? JSONDecoder().decode(Double.self, from: data) {
            handleDriftCorrection(data)
        } else {
            print("Child: Unexpected BLE packet")
        }
    }

    private func cleanupPeripheral(_ peripheral: CBPeripheral) {
        driftCharOnPeripheral   = nil
        discoveredPeripheral    = nil
    }
}

extension Notification.Name {
    static let driftCorrectionReceived = Notification.Name("driftCorrectionReceived")
}
