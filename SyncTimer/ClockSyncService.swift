//
//  ClockSyncService.swift
//  SyncTimer
//
//  Created by seb on 9/10/25.
//

import Foundation

import Combine

/// Wire envelopes for the UDP-style time beacons sent over your existing channel.
public enum BeaconType: String, Codable { case beacon, echo, followup }

public struct BeaconEnvelope: Codable {
    public var type: BeaconType
    public var uuidP: String?   // parent id (beacon)
    public var uuidC: String?   // child id  (echo/followup targeting)
    public var seq: UInt64
    public var tP_send: Double?     // uptime when parent sent beacon
    public var tC_recv: Double?     // uptime when child received beacon
    public var tC_echoSend: Double? // uptime when child sent echo
    public var tP_recv: Double?     // uptime when parent received echo
}

/// Child-side Kalman manager. One active KF keyed by master UUID.
public final class ClockSyncService: ObservableObject {
    @Published public private(set) var currentOffset: Double = 0 // seconds

    // Shared mutable state guarded by a private serial queue
        private var kfPerParent: [String: ClockKalman] = [:]
        private var lastSeqPerParent: [String: UInt64] = [:]
        private let stateQ = DispatchQueue(label: "ClockSyncService.state")

    private var seq: UInt64 = 0
    private let uptime: ()->Double = { ProcessInfo.processInfo.systemUptime }

    public init() {}

    // MARK: – Make a parent beacon (20 Hz). Parent only.
    public func makeBeacon(parentUUID: String) -> BeaconEnvelope {
        seq &+= 1
        return BeaconEnvelope(type: .beacon,
                              uuidP: parentUUID,
                              uuidC: nil,
                              seq: seq,
                              tP_send: uptime(),
                              tC_recv: nil,
                              tC_echoSend: nil,
                              tP_recv: nil)
    }

    // MARK: – Handle inbound envelope and produce any response envelope (echo/followup).
    /// - Parameters:
    ///   - env: inbound beacon/echo/followup
    ///   - roleIsChild: true on child, false on parent
    ///   - localUUID: this device uuid string
    /// - Returns: optional envelope to send back (child→echo, parent→followup)
    public func handleInbound(_ env: BeaconEnvelope,
                              roleIsChild: Bool,
                              localUUID: String) -> BeaconEnvelope? {
        let now = uptime()
        switch env.type {
        case .beacon where roleIsChild:
            // Child: reply with Echo to parent
            return BeaconEnvelope(type: .echo,
                                  uuidP: env.uuidP,
                                  uuidC: localUUID,
                                  seq: env.seq,
                                  tP_send: env.tP_send,
                                  tC_recv: now,
                                  tC_echoSend: now,
                                  tP_recv: nil)

        case .echo where !roleIsChild:
            // Parent: respond to that child with FollowUp
            return BeaconEnvelope(type: .followup,
                                  uuidP: env.uuidP,
                                  uuidC: env.uuidC,
                                  seq: env.seq,
                                  tP_send: env.tP_send,
                                  tC_recv: env.tC_recv,
                                  tC_echoSend: env.tC_echoSend,
                                  tP_recv: now)

        case .followup where roleIsChild:
            // Child: compute RTT and z, then update KF
            guard let uuidP = env.uuidP,
                  // Ignore follow-ups not addressed to this child
                env.uuidC == localUUID,
                  let tPsend = env.tP_send,
                  let tPrec  = env.tP_recv,
                  let tCrec  = env.tC_recv,
                  let tCecho = env.tC_echoSend
            else { return nil }

            // Compute then update state under serialization
                        let rtt = (tPrec - tPsend) - (tCecho - tCrec)   // seconds
                        let oneWay = max(0, rtt * 0.5)
                        let z = (tPsend + oneWay) - tCrec               // measured offset at child receive
            
                        var predicted: Double = 0
                        stateQ.sync {
                            // De-dup by seq per parent
                            if let last = lastSeqPerParent[uuidP], env.seq <= last {
                                return
                            }
                            lastSeqPerParent[uuidP] = env.seq
            
                            let kf = kfPerParent[uuidP] ?? ClockKalman()
                            kf.update(z: z, rtt: rtt, now: now)
                            kfPerParent[uuidP] = kf
                            predicted = kf.predictedOffset(at: now)
                        }
                        if predicted != 0 || currentOffset != 0 {
                            DispatchQueue.main.async { self.currentOffset = predicted }
                        }
            return nil

        default:
            return nil
        }
    }
    /// Reset internal state when sync toggles off.
        public func reset() {
            stateQ.sync {
                kfPerParent.removeAll()
                lastSeqPerParent.removeAll()
            }
            DispatchQueue.main.async { self.currentOffset = 0 }
    
        }
}
