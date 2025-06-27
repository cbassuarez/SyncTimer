//
//  SyncManager.swift
//  SyncTimer
//
//  Provides PTP‐style UDP synchronization between a “master” (parent) and multiple “clients” (children).
//  - The master advertises a Bonjour service (“_synctimer._udp”) on `broadcastPort` and listens for FOLLOW_UP.
//  - The master can broadcast a SYNC message followed by a START message to all clients.
//  - Each client browses for the same Bonjour service to discover the master, then listens for SYNC on `listenPort`,
//    replies with FOLLOW_UP, and waits for the START packet.
//  - Alternatively, if a manual override is provided, the client connects directly to the specified IP:port.
//  - When START arrives, the client posts a “didFireSyncEvent” notification so the UI can fire the timer.
//
//  IMPORTANT:
//  • We set `allowLocalEndpointReuse = true` on each UDP listener so that stopping and restarting
//    won’t cause “Address already in use.”
//  • Always call `stopSync()` before `startSync()` to guarantee the previous listener is canceled first.
//
//  Usage:
//
//    // Parent (master) with Bonjour:
//    let manager = SyncManager(
//      isMaster: true,
//      useBonjour: true,
//      manualHost: nil,
//      listenPort: 8888,      // (unused by master)
//      broadcastPort: 9999    // master listens on 9999 for FOLLOW_UP
//    )
//    manager.startSync()
//
//    // Child (client) with Bonjour:
//    let manager = SyncManager(
//      isMaster: false,
//      useBonjour: true,
//      manualHost: nil,
//      listenPort: 8888,      // child listens on 8888 for SYNC
//      broadcastPort: 9999    // parent’s port to reply to and receive START
//    )
//    manager.startSync()
//
//    // Child (client) with manual override (no Bonjour):
//    let manager = SyncManager(
//      isMaster: false,
//      useBonjour: false,
//      manualHost: (host: "192.168.1.100", port: 9999),
//      listenPort: 8888,
//      broadcastPort: 9999
//    )
//    manager.startSync()
//
//

import Foundation
import Network

// ─────────────────────────────────────────────────────────────────────────────
//  1) MachTime: convert between mach_absolute_time() ticks and nanoseconds/sec
// ─────────────────────────────────────────────────────────────────────────────
struct MachTime {
    static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t(numer: 0, denom: 0)
        mach_timebase_info(&info)
        return info
    }()

    /// Current raw mach ticks
    static func now() -> UInt64 {
        return mach_absolute_time()
    }

    /// Convert raw mach ticks to nanoseconds
    static func toNanoseconds(_ ticks: UInt64) -> UInt64 {
        return ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    /// Convert nanoseconds to raw mach ticks
    static func fromNanoseconds(_ ns: UInt64) -> UInt64 {
        return ns * UInt64(timebase.denom) / UInt64(timebase.numer)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  2) Handshake payloads (Codable structs for JSON over UDP)
// ─────────────────────────────────────────────────────────────────────────────
fileprivate struct SyncPayload: Codable {
    let t1_master: UInt64
}

fileprivate struct FollowUpPayload: Codable {
    let t1_master: UInt64
    let t2_client: UInt64
    let t3_client: UInt64
}

fileprivate struct OffsetPayload: Codable {
    let offset: Int64
}

fileprivate struct StartPayload: Codable {
    let startTime: UInt64
}

// ─────────────────────────────────────────────────────────────────────────────
//  3) UDPLinkMaster: advertises Bonjour, listens for FOLLOW_UPs & computes offsets
// ─────────────────────────────────────────────────────────────────────────────
class UDPLinkMaster {
    /// The NWListener that advertises via Bonjour and listens for FOLLOW_UP messages.
    let listener: NWListener
    private var clientOffsets: [NWEndpoint: Int64] = [:]
    private let queue = DispatchQueue(label: "UDPSyncMasterQueue")

    /// Create a master that advertises Bonjour on `_synctimer._udp` and listens on `broadcastPort`.
    init(broadcastPort: UInt16) throws {
        // 1) Configure UDP parameters to allow local endpoint reuse
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        // 2) Create listener on the specified port
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: broadcastPort)!)

        // 3) Advertise as a Bonjour service "_synctimer._udp"
        listener.service = NWListener.Service(
            name: nil,               // Let system choose a name
            type: "_synctimer._udp", // Service type string
            domain: nil,
            txtRecord: nil
        )

        // 4) Accept incoming FOLLOW_UP connections
        listener.newConnectionHandler = { [weak self] conn in
            self?.setupConnection(conn)
        }
        listener.start(queue: queue)
    }

    private func setupConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                self.receiveFollowUp(on: conn)
            }
        }
        conn.start(queue: queue)
    }

    private func receiveFollowUp(on conn: NWConnection) {
        conn.receiveMessage { [weak self] (data, _, _, _) in
            guard
                let self = self,
                let data = data,
                let follow = try? JSONDecoder().decode(FollowUpPayload.self, from: data)
            else {
                // Continue listening even if decoding fails
                self?.receiveFollowUp(on: conn)
                return
            }

            let t4_master = MachTime.now()
            let t1 = follow.t1_master
            let t2 = follow.t2_client
            let t3 = follow.t3_client

            // Compute offset: ((t2 - t1) + (t3 - t4)) / 2
            let delta1 = Int64(bitPattern: t2 &- t1)
            let delta2 = Int64(bitPattern: t3 &- t4_master)
            let offset = (delta1 + delta2) / 2

            self.clientOffsets[conn.endpoint] = offset

            let payload = OffsetPayload(offset: offset)
            if let bytes = try? JSONEncoder().encode(payload) {
                conn.send(content: bytes, completion: .contentProcessed({ _ in
                    // Continue listening for further FOLLOW_UPs
                    self.receiveFollowUp(on: conn)
                }))
            }
        }
    }

    /// Broadcast a SYNC message (with current t1_master) to each client endpoint.
    func broadcastSync(to endpoints: [NWEndpoint]) {
        let t1_master = MachTime.now()
        let payload = SyncPayload(t1_master: t1_master)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        for endpoint in endpoints {
            let conn = NWConnection(to: endpoint, using: .udp)
            conn.start(queue: queue)
            conn.send(content: data, completion: .contentProcessed({ _ in
                conn.cancel()
            }))
        }
    }

    /// Schedule a START packet for each client at t_target (in mach ticks).
    func scheduleStart(atMasterTime t_target: UInt64, to endpoints: [NWEndpoint]) {
        let payload = StartPayload(startTime: t_target)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        for endpoint in endpoints {
            let conn = NWConnection(to: endpoint, using: .udp)
            conn.start(queue: queue)
            conn.send(content: data, completion: .contentProcessed({ _ in
                conn.cancel()
            }))
        }
    }

    /// Return the stored clock offset for a given client endpoint, if any.
    func offsetForClient(_ endpoint: NWEndpoint) -> Int64? {
        return clientOffsets[endpoint]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  4) UDPLinkClient: browses Bonjour (or uses manual override), does SYNC → FOLLOW_UP, then listens for START
// ─────────────────────────────────────────────────────────────────────────────
class UDPLinkClient {
    let listener: NWListener
    var connForStart: NWConnection?
    var browser: NWBrowser?        // Kept as var so we can cancel it

    private var masterEndpoint: NWEndpoint?
    private let listenerQueue = DispatchQueue(label: "UDPSyncClientListenerQueue")
    private let browsingQueue = DispatchQueue(label: "UDPSyncClientBrowsingQueue")

    private(set) var clockOffset: Int64 = 0

    /// Initialize a client that either:
    /// • browses Bonjour on `_synctimer._udp` (if useBonjour == true), or
    /// • connects directly to `manualHost` (if useBonjour == false).
    init(listenPort: UInt16,
         useBonjour: Bool,
         manualHost: (host: String, port: UInt16)? = nil) throws
    {
        // 1) Configure UDP parameters to allow local endpoint reuse
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        // 2) Create listener on `listenPort` for SYNC
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: listenPort)!)
        listener.newConnectionHandler = { [weak self] conn in
            self?.readSync(on: conn)
        }
        listener.start(queue: listenerQueue)

        if useBonjour {
            // 3A) Browse for the Bonjour service "_synctimer._udp"
            let desc = NWBrowser.Descriptor.bonjour(type: "_synctimer._udp", domain: nil)
            let browser = NWBrowser(for: desc, using: params)
            self.browser = browser

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self = self else { return }
                for result in results {
                    let endpoint = result.endpoint
                    self.masterEndpoint = endpoint
                    self.setupConnectionToParent(using: endpoint)
                    browser.cancel()  // Stop once found first instance
                    break
                }
            }
            browser.start(queue: browsingQueue)

        } else {
            // 3B) Manual override: require manualHost
            guard let (h, p) = manualHost else {
                throw NSError(domain: "UDPLinkClient",
                              code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No manualHost provided"])
            }
            let host = NWEndpoint.Host(h)
            let port = NWEndpoint.Port(rawValue: p)!
            let endpoint = NWEndpoint.hostPort(host: host, port: port)
            self.masterEndpoint = endpoint
            setupConnectionToParent(using: endpoint)
        }
    }

    private func setupConnectionToParent(using endpoint: NWEndpoint) {
        // Create a persistent connection to receive START
        let params = listener.parameters
        let connStart = NWConnection(to: endpoint, using: params)
        connForStart = connStart
        connStart.start(queue: listenerQueue)
        readStart(on: connStart)
    }

    private func readSync(on conn: NWConnection) {
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                conn.receiveMessage { [weak self] (data, _, _, _) in
                    guard let self = self,
                          let data = data,
                          let sync = try? JSONDecoder().decode(SyncPayload.self, from: data)
                    else { return }
                    let t1_master = sync.t1_master
                    let t2_client = MachTime.now()
                    self.sendFollowUp(t1: t1_master, t2: t2_client)
                }
            }
        }
        conn.start(queue: listenerQueue)
    }

    private func sendFollowUp(t1: UInt64, t2: UInt64) {
        let t3_client = MachTime.now()
        let follow = FollowUpPayload(t1_master: t1,
                                     t2_client: t2,
                                     t3_client: t3_client)
        guard let data = try? JSONEncoder().encode(follow),
              let endpoint = masterEndpoint
        else { return }

        let params = listener.parameters
        let conn = NWConnection(to: endpoint, using: params)
        conn.start(queue: listenerQueue)
        conn.send(content: data, completion: .contentProcessed({ _ in
            self.readOffset(on: conn)
        }))
    }

    private func readOffset(on conn: NWConnection) {
        conn.receiveMessage { [weak self] (data, _, _, _) in
            guard let self = self,
                  let data = data,
                  let off = try? JSONDecoder().decode(OffsetPayload.self, from: data)
            else { return }
            self.clockOffset = off.offset
            conn.cancel()
        }
    }

    private func readStart(on conn: NWConnection) {
        conn.receiveMessage { [weak self] (data, _, _, _) in
            guard let self = self,
                  let data = data,
                  let start = try? JSONDecoder().decode(StartPayload.self, from: data)
            else { return }

            let t_target_master = start.startTime
            let fireClientTicks = UInt64(Int64(bitPattern: t_target_master) - self.clockOffset)
            let nowTicks = MachTime.now()
            let delayTicks = fireClientTicks > nowTicks ? (fireClientTicks - nowTicks) : 0
            let delayNs = MachTime.toNanoseconds(delayTicks)
            let deadline = DispatchTime(uptimeNanoseconds:
                                        UInt64(DispatchTime.now().uptimeNanoseconds) + delayNs)

            DispatchQueue.main.asyncAfter(deadline: deadline) {
                NotificationCenter.default.post(name: .didFireSyncEvent, object: nil)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  5) SyncManager: wraps master/client logic, advertises/browses Bonjour, and cancels everything
// ─────────────────────────────────────────────────────────────────────────────
final class SyncManager: ObservableObject {
    private var master: UDPLinkMaster?
    private var client: UDPLinkClient?

    /// True if this device is the master (parent). False if child (client).
    let isMaster: Bool

    /// If true, use Bonjour discovery/advertisement. If false, use manualHost (child only).
    let useBonjour: Bool
    let manualHost: (host: String, port: UInt16)?
    let listenPort: UInt16
    let broadcastPort: UInt16

    /// Initialize with:
    ///  • isMaster: true for parent, false for child
    ///  • useBonjour: true to use Bonjour; false to require manualHost (child only)
    ///  • manualHost: optional (host, port) for manual override
    ///  • listenPort: UDP port for SYNC (child) or FOLLOW_UP (parent)
    ///  • broadcastPort: UDP port for FOLLOW_UP (parent) and START (child)
    init(isMaster: Bool,
         useBonjour: Bool = true,
         manualHost: (host: String, port: UInt16)? = nil,
         listenPort: UInt16 = 8888,
         broadcastPort: UInt16 = 9999)
    {
        self.isMaster = isMaster
        self.useBonjour = useBonjour
        self.manualHost = manualHost
        self.listenPort = listenPort
        self.broadcastPort = broadcastPort
    }

    /// Call this once (or toggle on/off) to start the handshake. Always calls `stopSync()` first.
    func startSync() {
        // If already running, do nothing
        if isMaster {
            if master != nil { return }
        } else {
            if client != nil { return }
        }

        stopSync()

        if isMaster {
            do {
                let m = try UDPLinkMaster(broadcastPort: broadcastPort)
                master = m
            } catch {
                print("▶ UDPLinkMaster init failed:", error)
            }

        } else {
            do {
                let c = try UDPLinkClient(
                    listenPort: listenPort,
                    useBonjour: useBonjour,
                    manualHost: manualHost
                )
                client = c
            } catch {
                print("▶ UDPLinkClient init failed:", error)
            }
        }
    }

    /// Broadcast a SYNC message now, then schedule START after `delayMs` milliseconds.
    func sendSyncAndScheduleStart(afterMilliseconds delayMs: UInt64,
                                  to clientEndpoints: [NWEndpoint])
    {
        guard let m = master else { return }
        m.broadcastSync(to: clientEndpoints)

        let delayNs = UInt64(delayMs) * 1_000_000
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delayNs))) {
            let futureTicks = MachTime.now() + MachTime.fromNanoseconds(delayNs)
            m.scheduleStart(atMasterTime: futureTicks, to: clientEndpoints)
        }
    }

    /// Cancel any active listeners/browser and reset state. Call before `startSync()` to avoid “port in use.”
    func stopSync() {
        if let m = master {
            m.listener.cancel()
        }
        master = nil

        if let c = client {
            c.listener.cancel()
            c.connForStart?.cancel()
            c.browser?.cancel()
        }
        client = nil
    }
}

/// Notification posted when the client receives the START event at the correct synchronized time.
extension Notification.Name {
    static let didFireSyncEvent = Notification.Name("SyncManagerDidFireSyncEvent")
}


