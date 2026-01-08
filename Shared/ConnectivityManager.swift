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

    @Published public private(set) var incoming: TimerMessage?
    @Published public private(set) var incomingSyncEnvelope: SyncEnvelope?
    public let commands = PassthroughSubject<ControlRequest, Never>()
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

    public func sendSyncEnvelope(_ envelope: SyncEnvelope) {
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
        if let data = applicationContext["timer"] as? Data { decodeAndPublish(data) }
    }

    public func session(_ session: WCSession, didReceiveMessageData data: Data) {
        decodeAndPublish(data)
    }

    private func decodeAndPublish(_ data: Data) {
        let dec = JSONDecoder()
        if let msg = try? dec.decode(TimerMessage.self, from: data) {
            DispatchQueue.main.async { self.incoming = msg }; return
        }
        if let env = try? dec.decode(SyncEnvelope.self, from: data) {
            DispatchQueue.main.async { self.incomingSyncEnvelope = env }; return
        }
        if let cmd = try? dec.decode(ControlRequest.self, from: data) {
            DispatchQueue.main.async { self.commands.send(cmd) }; return
        }
        print("⚠️ [WC] unknown payload")
    }
}
