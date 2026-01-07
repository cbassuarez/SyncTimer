//
//  BonjourSyncManager.swift
//  SyncTimer
//

import Foundation
import Network
import UIKit

/// Bonjour service type (TCP)
fileprivate let bonjourServiceType = "_synctimer._tcp."

/// Keys for our TXT record
private enum TXTKey {
    
    static let role      = "role"
    static let timestamp = "ts"

    static let phase     = "phase"
    static let remaining = "remaining"
    static let rawEvents = "events"
}


/// A thin wrapper around NetService/NetServiceBrowser to publish (parent) and discover (child).
final class BonjourSyncManager: NSObject {
    private var nwBrowser: NWBrowser?
    private weak var syncSettings: SyncSettings?

        // MARK: – UUID helper (public or fileprivate)
        private func uuid(from serviceName: String) -> UUID {
            var hasher = Hasher()
            hasher.combine(serviceName)
            let hash = UInt64(bitPattern: Int64(hasher.finalize()))
            let data = withUnsafeBytes(of: hash.bigEndian) { Data($0) } + Data(repeating: 0, count: 8)
            return UUID(uuid: (
                data[0], data[1], data[2], data[3],
                data[4], data[5], data[6], data[7],
                data[8], data[9], data[10], data[11],
                data[12], data[13], data[14], data[15]
            ))
        }


    
    // —— Parent (advertiser) side ——
    private var netService: NetService?
    private var txtUpdateTimer: Timer?

    // —— Child (browser) side ——
    private var browser: NetServiceBrowser?
    private var pendingResolve: [NetService] = []

    /// How long to wait before giving up discovery
    private let discoveryTimeout: TimeInterval = 30.0
    private var discoveryTimer: Timer?

    init(owner: SyncSettings) {
        self.syncSettings = owner
        super.init()
    }

    // MARK: – Parent APIs

    /// Call this when user toggles “sync on” and role == .parent.
    func startAdvertising() {
        guard let settings = syncSettings else { return }
        print("[AD] \(settings.role == .parent ? "Parent" : "Child") calling startAdvertising()")
        
        // Always advertise on port 50000
        let port: Int32 = settings.listenerPort > 0 ? Int32(settings.listenerPort) : 50000

        // Service name: "SyncTimer Parent – <DeviceName>"
        let peerName = UIDevice.current.name ?? "Unknown"
        let name = "SyncTimer Parent – \(peerName)"

        // Build initial TXT record from current timer state:
        let txtData = makeTXTRecord()

        if netService != nil { return }                    // idempotent
            let svc = NetService(domain: "local.", type: bonjourServiceType, name: name, port: port)
        svc.includesPeerToPeer = true          // ← allow AWDL
        svc.delegate = self
        svc.setTXTRecord(txtData)
        svc.publish(options: [.listenForConnections])

        self.netService = svc

        // Every time the timer state changes in your app, call `updateTXTRecord()`.
        // Here we also schedule a repeating timer to push TXT updates (optional).
        txtUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTXTRecord()
        }
    }
    // Call from either role to put *yourself* on the wire.
    func advertisePresence() {
        guard let settings = syncSettings else { return }
        if netService != nil { return }          // already advertising

        let isParent = (settings.role == .parent)

        // —— key change ↓ ——
        let port: Int32 = isParent
        ? (settings.listenerPort > 0 ? Int32(settings.listenerPort) : 50000)
                                   : Int32(UInt16.random(in: 49152...65534)) // child

        let peerName = UIDevice.current.name
        let name     = "SyncTimer \(isParent ? "Parent" : "Child") – \(peerName)"

        let svc = NetService(domain: "local.",
                             type: bonjourServiceType,
                             name: name,
                             port: port)

        svc.delegate = self
        svc.setTXTRecord(makeTXTRecord())

        // Only the **parent** needs to listen for incoming TCP children
        if isParent {
            svc.publish(options: [.listenForConnections])
        } else {
            svc.publish()                    // plain TXT-only advert for child
        }

        netService = svc

        // Keep our TXT fresh (role, lobby, timestamp, etc.)
        txtUpdateTimer?.invalidate()
        txtUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0,
                                              repeats: true) { [weak self] _ in
            self?.updateTXTRecord()
        }
    }

    /// Remove service and stop updating TXT
    func stopAdvertising() {
        txtUpdateTimer?.invalidate()
        txtUpdateTimer = nil

        guard let svc = netService else { return }
            svc.stop()
            netService = nil
    }
    // 2️⃣ Only the *child* opens the TCP connection
    private func maybeConnectTo(_ service: NetService) {
        guard let ss = syncSettings, ss.role == .child else { return }
        connectTo(service: service)          // ← your existing method
    }
    /// Update TXT with the very latest phase/remaining/events. Call this whenever the timer changes.
    private func updateTXTRecord() {
        guard let svc = netService else { return }
        let newTXT = makeTXTRecord()
        svc.setTXTRecord(newTXT)
    }

    /// Gathers data from SyncSettings → StopEventWire
    private func makeTXTRecord() -> Data {
        guard let settings = syncSettings else {
            return Data()
        }

        // We only publish the parent’s STOP-events here.
        let stopWires: [StopEventWire] = settings.stopWires

        // Serialize stopWires to JSON
        let eventData: Data
        if let d = try? JSONEncoder().encode(stopWires) {
            eventData = d
        } else {
            eventData = Data()
        }

        // Build a dictionary of UTF8-encoded TXT keys
        var dict: [String: Data] = [:]

        // For now, placeholders—later replace with actual phase & remaining
        let phaseString = "idle"
        let remainString = "0.0"

        dict[TXTKey.phase]     = Data(phaseString.utf8)
        dict[TXTKey.remaining] = Data(remainString.utf8)
        dict[TXTKey.rawEvents] = eventData

        
            // Role
            let roleStr = (settings.role == .parent) ? "parent" : "child"
            dict[TXTKey.role]     = Data(roleStr.utf8)

            // Timestamp in ms
            let ts = UInt64(Date().timeIntervalSince1970 * 1000)
            dict[TXTKey.timestamp] = Data(String(ts).utf8)
        
        // Add your own mnemonic:
            dict["name"] = Data(settings.localNickname.utf8)
        
        //  ── NEW: include your own mnemonic & RSSI
            dict["name"] = Data(settings.localNickname.utf8)
            dict["hostUUID"] = Data(settings.localPeerID.uuidString.utf8)
            // always advertise yourself at full strength:
            dict["rssi"] = Data("3".utf8)

            return NetService.data(fromTXTRecord: dict)    }

    // MARK: – Child APIs
    func startBrowsing() {
      // tear down any old browser
        if browser != nil { return }                       // idempotent
            let b = NetServiceBrowser()
            b.includesPeerToPeer = true                        // <— AWDL
            b.delegate = self
            browser = b
            b.searchForServices(ofType: bonjourServiceType, inDomain: "local.")
      DispatchQueue.main.async { self.syncSettings?.statusMessage = "Bonjour: searching…" }
      // optional timeout...
    }

    func stopBrowsing() {
        guard let b = browser else { return }
            b.stop()
            browser = nil
      pendingResolve.removeAll()
    }

    /// Once a parent is resolved, connect to it via TCP
    private func connectTo(service: NetService) {
        // 1) Find the first IPv4 sockaddr
        guard let addrs = service.addresses else { return }
        let v4data = addrs.first { data in
            data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress?.assumingMemoryBound(to: sockaddr_storage.self) else {
                    return false
                }
                return base.pointee.ss_family == sa_family_t(AF_INET)
            }
        }
        guard let hostPortData = v4data else {
            DispatchQueue.main.async {
                self.syncSettings?.statusMessage = "Bonjour: no IPv4 address"
            }
            return
        }

        // 2) Extract host & port
        switch NetService.fromSockAddr(data: hostPortData) {
        case .hostPort(let host, let port):
            let conn = NWConnection(host: host, port: port, using: .tcp)
            conn.stateUpdateHandler = { (newState: NWConnection.State) in
                switch newState {
                case .ready:
                    DispatchQueue.main.async {
                        self.syncSettings?.isEstablished = true
                        self.syncSettings?.statusMessage = "Bonjour: connected to \(service.name)"
                    }
                    self.syncSettings?.integrateBonjourConnection(conn)

                case .failed(let err):
                    DispatchQueue.main.async {
                        self.syncSettings?.statusMessage = "Bonjour: connection failed"
                    }
                    print("Bonjour TCP failed:", err.localizedDescription)
                    conn.cancel()

                case .cancelled:
                    DispatchQueue.main.async {
                        self.syncSettings?.statusMessage = "Bonjour: connection cancelled"
                    }
                    conn.cancel()

                default:
                    break
                }
            }

            conn.start(queue: .global(qos: .background))

        case .none:
            DispatchQueue.main.async {
                self.syncSettings?.statusMessage = "Bonjour: invalid address"
            }
        
            
            
            // Stop further browsing
            browser?.stop()
            browser = nil
        }
    }
    /// Parse TXT record into timer-state (if you want to show it immediately)
    private func parseTXTRecord(_ data: Data) {
        let txt = NetService.dictionary(fromTXTRecord: data)
        // phase
        if let phaseData = txt[TXTKey.phase],
           let phaseString = String(data: phaseData, encoding: .utf8) {
            DispatchQueue.main.async {
                self.syncSettings?.statusMessage = "Parent phase: \(phaseString)"
            }
        }

        // remaining (ignored for now)
        // events
        if let eventsData = txt[TXTKey.rawEvents] {
            if let stopWires = try? JSONDecoder().decode([StopEventWire].self, from: eventsData) {
                let rawStops = stopWires.map {
                    StopEvent(eventTime: $0.eventTime, duration: $0.duration)
                }
                // Hand those raw stops to SyncSettings
                self.syncSettings?.setRawStops(rawStops)
            }
        }
    }
}

// MARK: – NetServiceBrowserDelegate (Child)
extension BonjourSyncManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        print("🔍 Found service: \(service.name) type:\(service.type)")
        pendingResolve.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }



    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didNotSearch errorDict: [String: NSNumber]) {
        DispatchQueue.main.async {
            self.syncSettings?.statusMessage = "Bonjour: search failed"
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        // If user toggled off, ignore. If we found one, connect is already in progress.
    }
}

// MARK: – NetServiceDelegate (for both publishing & resolving)
extension BonjourSyncManager: NetServiceDelegate {
    
  func netServiceDidResolveAddress(_ sender: NetService) {
      print("[OK] Published:", sender.name, "→", sender.type, "@", sender.port)

    
      func netService(_ sender: NetService,
                      didNotPublish errorDict: [String : NSNumber]) {
          print("[ERR] Failed to publish:", sender.name, "error =", errorDict)
      }
      
      guard let txtData = sender.txtRecordData() else { return }
      let txtDict = NetService.dictionary(fromTXTRecord: txtData)
        
    // 1) Lobby‐filter & UI update
    syncSettings?.handleResolvedService(sender, txt: txtDict)

    // 2) RSSI
    if let rssiData   = txtDict["rssi"],
       let rssiString = String(data: rssiData, encoding: .utf8),
       let rssi       = Int(rssiString)
    {
      let peerID: UUID = {
        if let hostUUIDData = txtDict["hostUUID"],
           let hostUUIDString = String(data: hostUUIDData, encoding: .utf8),
           let hostUUID = UUID(uuidString: hostUUIDString) {
          return hostUUID
        }
        return uuid(from: sender.name)
      }()
      DispatchQueue.main.async {
        self.syncSettings?.updateSignalStrength(peerID: peerID, to: rssi)
      }
    }

    // 3) *** NEW: actually open the TCP connection ***
    // Only connect once, of course
      if self.syncSettings?.connectToResolvedBonjourParent(service: sender, txt: txtDict) == true {
        return
      }
      maybeConnectTo(sender)

    
  }



    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        DispatchQueue.main.async {
            self.syncSettings?.statusMessage = "Bonjour: resolve failed"
        }
    }
}

extension NetService {
    /// Helper that tries to extract a (host, port) from raw sockaddr data
    enum Endpoint {
        case hostPort(host: NWEndpoint.Host, port: NWEndpoint.Port)
        case none
    }

    static func fromSockAddr(data: Data) -> Endpoint {
        var storage = sockaddr_storage()
        (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)

        switch Int32(storage.ss_family) {
        case AF_INET:
            var addr4 = sockaddr_in()
            memcpy(&addr4, &storage, MemoryLayout<sockaddr_in>.size)
            let ip = String(cString: inet_ntoa(addr4.sin_addr), encoding: .ascii) ?? ""
            let host = NWEndpoint.Host(ip)
            let port = NWEndpoint.Port(rawValue: UInt16(bigEndian: addr4.sin_port))!
            return .hostPort(host: host, port: port)

        case AF_INET6:
            var addr6 = sockaddr_in6()
            memcpy(&addr6, &storage, MemoryLayout<sockaddr_in6>.size)
            let ipString = withUnsafePointer(to: &addr6.sin6_addr) {
                $0.withMemoryRebound(to: UInt8.self, capacity: 16) { ptr in
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    inet_ntop(AF_INET6, ptr, &buffer, socklen_t(INET6_ADDRSTRLEN))
                    return String(cString: buffer)
                }
            }
            let host = NWEndpoint.Host(ipString)
            let port = NWEndpoint.Port(rawValue: UInt16(bigEndian: addr6.sin6_port))!
            return .hostPort(host: host, port: port)

        default:
            return .none
        }
    }
}
