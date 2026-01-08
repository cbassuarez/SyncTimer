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
    // Link health
        private var linkWatchdog: Timer?
        private var lastPacketAt: TimeInterval = 0
        private var childIsNotifying = false
    
    // MARK: – Discovery helpers (keep amber when SYNC is ON)
        private func restartScanIfChild() {
            guard shouldActAsChild,
                  centralManager.state == .poweredOn,
                  owner?.isEnabled == true else { return }
            startScanningAsChild()
        }
        private func ensureAdvertisingIfParent() {
            guard shouldActAsParent,
                  peripheralManager.state == .poweredOn,
                  owner?.isEnabled == true else { return }
            if !peripheralManager.isAdvertising {
                let adv: [String: Any] = [
                    CBAdvertisementDataServiceUUIDsKey: [timerServiceUUID],
                    CBAdvertisementDataLocalNameKey: owner?.pairingDeviceName ?? "TimerParent"
                ]
                peripheralManager.startAdvertising(adv)
            }
            DispatchQueue.main.async { [weak self] in
                self?.owner?.setEstablished(false)
                self?.owner?.statusMessage = "Bluetooth: advertising…"
            }
        }
    
    // MARK: – Link watchdog
        @objc private func watchdogTick() {
            let now = Date().timeIntervalSince1970
            // Parent side: green only if we truly have at least one subscriber and traffic is fresh
            if shouldActAsParent {
                let hasSubs = !(driftCharacteristic?.subscribedCentrals?.isEmpty ?? true)
                let stale   = (now - lastPacketAt) > 8.0 // ~1.5× your 5s drift ping
                if !hasSubs || stale {
                    DispatchQueue.main.async { [weak self] in
                        guard let s = self else { return }
                        s.owner?.setEstablished(false)
                        if s.owner?.isEnabled == true {
                            s.owner?.statusMessage = "Bluetooth: advertising…"
                        } else {
                            s.owner?.statusMessage = "Bluetooth: off"
                        }
                    }
                    ensureAdvertisingIfParent()
                }
            }
            // Child side: green only if we’re notifying AND traffic is fresh
            if shouldActAsChild {
                let stale = (now - lastPacketAt) > 8.0
                if !childIsNotifying || stale {
                    DispatchQueue.main.async { [weak self] in
                        guard let s = self else { return }
                        s.owner?.setEstablished(false)
                        if s.owner?.isEnabled == true {
                            s.owner?.statusMessage = "Bluetooth: searching…"
                        } else {
                            s.owner?.statusMessage = "Bluetooth: off"
                        }
                    }
                    restartScanIfChild()
                }
            }
        }
    
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
        lastPacketAt = Date().timeIntervalSince1970
                linkWatchdog?.invalidate()
                linkWatchdog = Timer.scheduledTimer(timeInterval: 2.0,
                                                    target: self,
                                                    selector: #selector(watchdogTick),
                                                    userInfo: nil,
                                                    repeats: true)
        switch role {
        case .parent:
            shouldActAsParent = true
            DispatchQueue.main.async { [weak self] in
                    self?.owner?.setEstablished(false)
                    self?.owner?.statusMessage = "Bluetooth: advertising…"
                }
            // Seed child-visible identifiers (used in discovery UI / optional filters)
                        owner?.pairingServiceUUID = timerServiceUUID
                        owner?.pairingDeviceName  = "TimerParent"
            if peripheralManager.state == .poweredOn {
                print("Parent: setting up peripheral immediately")
                setupParentPeripheral()
            }
        case .child:
            shouldActAsChild = true
            DispatchQueue.main.async { [weak self] in
                    self?.owner?.setEstablished(false)
                self?.owner?.statusMessage = "Bluetooth: searching…"
                }
            // Ensure we always have a service UUID to scan for
                        if owner?.pairingServiceUUID == nil {
                            owner?.pairingServiceUUID = timerServiceUUID
                        }
            // if already powered on, kick off scan immediately; otherwise delegate will handle it
            if centralManager.state == .poweredOn {
                            startScanningAsChild()   // ⟵ scan NOW, don’t depend on isEnabled race
            }
        }
    }

    
    
    /// Called by SyncSettings whenever you disable sync or switch out of Bluetooth.
    func stop() {
        // 1) Stop any pending drift‐timer
        driftTimer?.invalidate()
        driftTimer = nil
        linkWatchdog?.invalidate()
                linkWatchdog = nil
                childIsNotifying = false
                lastPacketAt = 0
        
        // 2) Tear down *both* peripheral & central
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising() }
        peripheralManager.removeAllServices()
        driftCharacteristic = nil
        
        if centralManager.isScanning { centralManager.stopScan() }
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
        DispatchQueue.main.async { [weak self] in
                self?.owner?.setEstablished(false)
                self?.owner?.statusMessage = "Bluetooth: off"
            }
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
        print("Parent: Advertising \(timerServiceUUID)")
            DispatchQueue.main.async { [weak self] in
                self?.owner?.statusMessage = "Bluetooth: advertising…"
            }
    }


    /// Every 5 s (once a child has subscribed) we send a DriftRequest
    private func sendDriftRequestIfNeeded() {
        guard owner?.role == .parent else { return }
        guard let driftChar = driftCharacteristic else { return }

        let tReq = Date().timeIntervalSince1970
        let eReq = owner?.getCurrentElapsed() ?? 0
        lastPacketAt = tReq  // activity on the link
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
            lastPacketAt = Date().timeIntervalSince1970
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
        // Bluetooth link is “up” — show green
            DispatchQueue.main.async { [weak self] in
                self?.owner?.setEstablished(true)
                self?.owner?.statusMessage = "Bluetooth: connected"
            }
        lastPacketAt = Date().timeIntervalSince1970
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
            // Link is down — if SYNC is ON, keep amber & advertising; else go off
                        ensureAdvertisingIfParent() // (no-op if SYNC is OFF)
                        if owner?.isEnabled != true {
                            DispatchQueue.main.async { [weak self] in
                                self?.owner?.setEstablished(false)
                                self?.owner?.statusMessage = "Bluetooth: off"
                            }
                        }
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
            // Default to our known service if the app hasn’t seeded it yet
                   let svcUUID = owner?.pairingServiceUUID ?? timerServiceUUID
            let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            centralManager.scanForPeripherals(
                withServices: [svcUUID],
                options: options
            )
            print("Child: scanning for service \(svcUUID)")
                DispatchQueue.main.async { [weak self] in
                    self?.owner?.statusMessage = "Bluetooth: searching…"
                }
        }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        // Prefer close parents only (quick heuristic)
                guard RSSI.intValue >= -80 else {
                    // too far; ignore to reduce accidental picks in dense rooms
                    return
                }
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
            lastPacketAt = Date().timeIntervalSince1970
        peripheral.discoverServices([timerServiceUUID])
    }
        
        func centralManager(_ central: CBCentralManager,
                            didFailToConnect peripheral: CBPeripheral,
                            error: Error?) {
            cleanupPeripheral(peripheral)
            DispatchQueue.main.async { [weak self] in
                            self?.owner?.setEstablished(false)
                            self?.owner?.statusMessage = (self?.owner?.isEnabled == true) ? "Bluetooth: searching…" : "Bluetooth: off"
                        }
                        // resume scan only while SYNC is ON
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            self?.restartScanIfChild()
                        }
        }
        
        func centralManager(_ central: CBCentralManager,
                            didDisconnectPeripheral peripheral: CBPeripheral,
                            error: Error?) {
            cleanupPeripheral(peripheral)
            DispatchQueue.main.async { [weak self] in
                            self?.owner?.setEstablished(false)
                            self?.owner?.statusMessage = (self?.owner?.isEnabled == true) ? "Bluetooth: searching…" : "Bluetooth: off"
                        }
                        // resume scan only while SYNC is ON
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            self?.restartScanIfChild()
                        }
        }
    
        
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        print("Child: didDiscoverServices:", peripheral.services ?? [])
        guard let svcs = peripheral.services, !svcs.isEmpty else {
                    // No services → bounce and rescan
                    centralManager.cancelPeripheralConnection(peripheral)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.restartScanIfChild()
                    }
                    return
                }
                for svc in svcs where svc.uuid == timerServiceUUID {
                    peripheral.discoverCharacteristics([driftCharacteristicUUID], for: svc)
                    return
                }
                // Timer service not present → bounce and rescan
                print("Child: timer service not found, reconnecting…")
                centralManager.cancelPeripheralConnection(peripheral)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.restartScanIfChild()
                }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        print("Child: didDiscoverCharacteristicsFor", service.uuid, service.characteristics ?? [])
        guard let chars = service.characteristics, !chars.isEmpty else {
                    // No characteristics → bounce and rescan
                    centralManager.cancelPeripheralConnection(peripheral)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.restartScanIfChild()
                    }
                    return
                }
                for char in chars where char.uuid == driftCharacteristicUUID {
                    driftCharOnPeripheral = char
                    print("Child: subscribing to drift characteristic")
                    peripheral.setNotifyValue(true, for: char)
                    return
                }
                // Our characteristic wasn’t found → bounce and rescan
                print("Child: drift characteristic not found, reconnecting…")
                centralManager.cancelPeripheralConnection(peripheral)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.restartScanIfChild()
                }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let err = error {
            print("Child: subscribe failed:", err)
        } else {
            print("Child: isNotifying =", characteristic.isNotifying)
            if characteristic.isNotifying {
                        // Notification stream is live — show green
                        DispatchQueue.main.async { [weak self] in
                            self?.owner?.setEstablished(true)
                            self?.owner?.statusMessage = "Bluetooth: connected"
                        }
                childIsNotifying = true
                                        lastPacketAt = Date().timeIntervalSince1970
                    } else {
                        DispatchQueue.main.async { [weak self] in
                            self?.owner?.setEstablished(false)
                            self?.owner?.statusMessage = (self?.owner?.isEnabled == true) ? "Bluetooth: searching…" : "Bluetooth: off"
                        }
                        childIsNotifying = false
                        // If we’re still connected but not notifying, tear down and rescan to heal.
                                                if peripheral.state == .connected {
                                                    centralManager.cancelPeripheralConnection(peripheral)
                                                }
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                                                    self?.restartScanIfChild()
                                                }
                    }
        }
    }
    // MARK: - Timer control over BLE
        /// Parent → all subscribed children
        func sendTimerMessageToChildren(_ msg: TimerMessage) {
            // We’re the parent and we have a characteristic to notify on
            guard shouldActAsParent, let characteristic = driftCharacteristic else { return }
            // Only bother if at least one child is subscribed
            if (characteristic.subscribedCentrals?.isEmpty ?? true) { return }
            guard let data = try? JSONEncoder().encode(msg) else { return }
            _ = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
        }

        /// Child → parent (optional symmetry; harmless if unused)
        func sendTimerMessageToParent(_ msg: TimerMessage) {
            guard let p = discoveredPeripheral, let c = driftCharOnPeripheral else { return }
            guard let data = try? JSONEncoder().encode(msg) else { return }
            p.writeValue(data, for: c, type: .withoutResponse)
        }

        func sendSyncEnvelopeToChildren(_ envelope: SyncEnvelope) {
            guard shouldActAsParent, let characteristic = driftCharacteristic else { return }
            if (characteristic.subscribedCentrals?.isEmpty ?? true) { return }
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            _ = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
        }

        func sendSyncEnvelopeToParent(_ envelope: SyncEnvelope) {
            guard let p = discoveredPeripheral, let c = driftCharOnPeripheral else { return }
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            p.writeValue(data, for: c, type: .withoutResponse)
        }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let err = error {
            print("Child: Notification error: \(err.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        lastPacketAt = Date().timeIntervalSince1970

        // ① Try full timer control first (parent → child)
        if let msg = try? JSONDecoder().decode(TimerMessage.self, from: data) {
            DispatchQueue.main.async { [weak self] in
                self?.owner?.onReceiveTimer?(msg)
                self?.owner?.setEstablished(true) // keep lamp green while control flows
            }
            return
        }
        if let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: data) {
            DispatchQueue.main.async { [weak self] in
                self?.owner?.receiveSyncEnvelope(envelope)
                self?.owner?.setEstablished(true)
            }
            return
        }
        // ② Fall back to drift protocol
        if let req = try? JSONDecoder().decode(DriftRequest.self, from: data) {
            handleDriftRequest(req)
        } else if let _ = try? JSONDecoder().decode(Double.self, from: data) {
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
