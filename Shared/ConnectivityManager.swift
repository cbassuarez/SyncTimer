//
//  ConnectivityManager.swift
//  SyncTimer
//
//  Created by seb on 9/15/25.
//

import Foundation
import WatchConnectivity
import Combine

public final class ConnectivityManager: NSObject, ObservableObject {
    public static let shared = ConnectivityManager()

    private(set) var session: WCSession? = nil
    private var lastTimerMessage: TimerMessage?
    #if os(watchOS)
    private var lastAppliedSeq: UInt64 = 0
    #endif

    @Published public private(set) var incoming: TimerMessage?
    @Published public private(set) var cueSheetIndex: [CueSheetSummaryWire] = []
    @Published public private(set) var isReachable: Bool = false
    @Published private(set) var incomingSyncEnvelope: SyncEnvelope?
    public let commands = PassthroughSubject<ControlRequest, Never>()
    public let snapshotRequests = PassthroughSubject<SnapshotRequest, Never>()
    #if DEBUG
    @Published private(set) var lastInboundDiagnostic: InboundDiagnostic?
    #endif
    /// Convenience: only returns session when supported **and** activated.
        private var activatedSession: WCSession? {
            #if canImport(WatchConnectivity)
            guard WCSession.isSupported(), let s = session, s.activationState == .activated else { return nil }
            return s
            #else
            return nil
            #endif
        }
    // In ConnectivityManager (or wherever this init lives)
    private override init() {
            super.init()
            #if canImport(WatchConnectivity)
            guard WCSession.isSupported() else {
                print("[WC] WatchConnectivity not supported on this device.")
                return
            }
            let s = WCSession.default
            s.delegate = self
            s.activate()
            self.session = s
            print("[WC] activate()")
            #else
            print("[WC] WatchConnectivity not available on this platform.")
            #endif
        }

    public func start() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            print("[WC] WatchConnectivity not supported on this device.")
            return
        }
        let s: WCSession
        if let existing = session {
            s = existing
        } else {
            s = WCSession.default
            session = s
        }
        s.delegate = self
        if s.activationState != .activated {
            s.activate()
        }
        #else
        print("[WC] WatchConnectivity not available on this platform.")
        #endif
    }


    // MARK: Send

    public func send<T: Codable>(_ payload: T) {
         guard let data = try? JSONEncoder().encode(payload) else {
             print("⚠️ [WC] encode failed \(T.self)"); return
         }
         #if canImport(WatchConnectivity)
         guard let s = activatedSession else {
             // Not activated or unsupported; optionally cache lastTimerMessage here
             if let tm = payload as? TimerMessage { lastTimerMessage = tm }
             return
         }
         if s.isReachable {
             s.sendMessageData(data, replyHandler: nil) {
                 print("❌ [WC] sendMessageData: \($0.localizedDescription)")
             }
         }
         if let tm = payload as? TimerMessage {
             lastTimerMessage = tm
             do { try s.updateApplicationContext(["timer": data]) }
             catch { print("❌ [WC] updateApplicationContext: \(error.localizedDescription)") }
         }
         #endif
     }

    public func sendCommand(_ cmd: ControlRequest.Command) {
        send(ControlRequest(cmd))
    }

    public func requestSnapshot(origin: String = "watchOS") {
        send(ControlRequest(.requestSnapshot, origin: origin))
    }

    func sendSyncEnvelope(_ envelope: SyncEnvelope) {
        send(envelope)
    }
}

// MARK: WCSessionDelegate
extension ConnectivityManager: WCSessionDelegate {
    public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?) {
        if let e = error { print("❌ [WC] activation error: \(e.localizedDescription)"); return }
        print("✅ [WC] didActivate=\(activationState.rawValue)")
        #if os(iOS)
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
        #endif
        #if os(iOS)
        if let tm = lastTimerMessage, let data = try? JSONEncoder().encode(tm) {
            try? session.updateApplicationContext(["timer": data])
        }
        #endif
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) { session.activate() }
    public func sessionDidDeactivate(_ session: WCSession)     { session.activate() }
    #endif


    public func session(_ session: WCSession,
                        didReceiveApplicationContext applicationContext: [String : Any]) {
        if let data = applicationContext["timer"] as? Data {
            decodeAndPublish(data, source: .appContext)
        }
    }

    public func session(_ session: WCSession, didReceiveMessageData data: Data) {
        decodeAndPublish(data, source: .messageData)
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        #if os(iOS)
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
        #endif
    }

    private func decodeAndPublish(_ data: Data, source: InboundSource) {
        let dec = JSONDecoder()
        if let msg = try? dec.decode(TimerMessage.self, from: data) {
            handleTimerMessage(msg, source: source); return
        }
        if let index = try? dec.decode(CueSheetIndexWire.self, from: data) {
            Task { @MainActor in
                self.cueSheetIndex = index.items
            }
            return
        }
        if let env = try? dec.decode(SyncEnvelope.self, from: data) {
            Task { @MainActor in
                self.incomingSyncEnvelope = env
            }
            return
        }
        if let cmd = try? dec.decode(ControlRequest.self, from: data) {
            Task { @MainActor in
                self.commands.send(cmd)
            }
            return
        }
        if let request = try? dec.decode(SnapshotRequest.self, from: data) {
            Task { @MainActor in
                self.snapshotRequests.send(request)
            }
            return
        }
        print("⚠️ [WC] unknown payload")
    }

    private func handleTimerMessage(_ msg: TimerMessage, source: InboundSource) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let sequence = sequenceToken(for: msg)
        Task { @MainActor in
            #if DEBUG
            self.lastInboundDiagnostic = InboundDiagnostic(
                source: source,
                phase: msg.phase,
                remaining: msg.remaining,
                isStopActive: msg.isStopActive,
                stopRemainingActive: msg.stopRemainingActive,
                stopIntervalActive: msg.stopIntervalActive,
                stateSeq: msg.stateSeq,
                actionSeq: msg.actionSeq,
                derivedSeq: sequence.value,
                arrivalUptime: uptime
            )
            #endif
            #if os(watchOS)
            if sequence.value < self.lastAppliedSeq {
                return
            }
            self.lastAppliedSeq = sequence.value
            #endif
            self.incoming = msg
        }
    }

    private func sequenceToken(for msg: TimerMessage) -> SequenceToken {
        if let stateSeq = msg.stateSeq {
            return SequenceToken(value: stateSeq)
        }
        if let actionSeq = msg.actionSeq {
            return SequenceToken(value: actionSeq)
        }
        let derived = UInt64((msg.timestamp * 1000.0).rounded())
        return SequenceToken(value: derived)
    }
}

private struct SequenceToken {
    let value: UInt64
}

enum InboundSource: String {
    case messageData
    case appContext
}

#if DEBUG
struct InboundDiagnostic: Equatable {
    let source: InboundSource
    let phase: String
    let remaining: TimeInterval
    let isStopActive: Bool?
    let stopRemainingActive: TimeInterval?
    let stopIntervalActive: TimeInterval?
    let stateSeq: UInt64?
    let actionSeq: UInt64?
    let derivedSeq: UInt64?
    let arrivalUptime: TimeInterval
}
#endif
