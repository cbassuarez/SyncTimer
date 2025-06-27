import Foundation
import WatchConnectivity
import Combine


public final class ConnectivityManager: NSObject, ObservableObject {
    public static let shared = ConnectivityManager()


    /// Last‐seen TimerMessage, for when the watch wakes up later
    private var lastTimerMessage: TimerMessage?


    /// WCSession wrapper
    private let session: WCSession


    /// Publishes the most recent TimerMessage on both iOS & watchOS
    @Published public private(set) var incoming: TimerMessage?


    private override init() {
        // 1) grab the default session
        guard WCSession.isSupported() else {
            fatalError("WCSession not supported on this device")
        }
        session = .default


        super.init()


        // 2) set up delegate & activate *immediately*
        session.delegate = self
        session.activate()
        print("[WC] ConnectivityManager init → session.activate() called")
    }


    /// Send any Codable.  TimerMessage payloads get stickied.
    public func send<T: Codable>(_ payload: T) {
        
        guard let data = try? JSONEncoder().encode(payload) else {
            print("⚠️ ConnectivityManager: failed to encode \(payload)")
            return
        }


        // 1) Live update if reachable
        if session.activationState == .activated && session.isReachable {
            session.sendMessageData(data,
                                    replyHandler: nil,
                                    errorHandler: { err in
                                        print("❌ WCSession.sendMessageData error: \(err.localizedDescription)")
                                    })
        }


        // 2) If it's a TimerMessage, stash & push snapshot
        if let tm = payload as? TimerMessage {
            lastTimerMessage = tm
            do {
                try session.updateApplicationContext(["timer": data])
                print("[WC] updateApplicationContext → pushed snapshot for TimerMessage")
            } catch {
                print("❌ WCSession.updateApplicationContext failed: \(error.localizedDescription)")
            }
        }
    }
}


//──────────────────────────────────────────────────────────────────────────────
// MARK: – WCSessionDelegate
//──────────────────────────────────────────────────────────────────────────────
extension ConnectivityManager: WCSessionDelegate {
    // 1) Called on both sides when activation finishes
    public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?)
    {
        if let e = error {
            print("❌ WCSession activation error: \(e.localizedDescription)")
            return
        }
        print("✅ WCSession didActivate (state = \(activationState.rawValue))")


        #if os(iOS)
        // re-push the last TimerMessage so a newly-launched watch can catch up
        if let tm = lastTimerMessage,
           let data = try? JSONEncoder().encode(tm)
        {
            try? session.updateApplicationContext(["timer": data])
            print("[WC-iOS] re-pushed lastTimerMessage on activation")
        }
        #endif
    }


    #if os(iOS)
    // required for iPhone → watch hand-off on pairing/unpairing
    public func sessionDidBecomeInactive(_ session: WCSession) {
        session.activate()
    }
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif


    // 2) Sticky snapshot arrives here on the *other* device
    public func session(_ session: WCSession,
                        didReceiveApplicationContext applicationContext: [String : Any])
    {
        if let data = applicationContext["timer"] as? Data {
            print("[WC] didReceiveApplicationContext → found ‘timer’ key, decoding…")
            deliver(data)
        } else {
            print("⚠️ WC] didReceiveApplicationContext but no ‘timer’ key; keys = \(applicationContext.keys)")
        }
    }


    // 3) Live message arrives here on the *other* device
    public func session(_ session: WCSession,
                        didReceiveMessageData data: Data)
    {
        print("[WC] didReceiveMessageData → live hop, decoding…")
        deliver(data)
    }


    // common decode + publish
    private func deliver(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(TimerMessage.self, from: data) else {
            print("⚠️ ConnectivityManager: failed to decode TimerMessage from data")
            return
        }
        DispatchQueue.main.async {
            self.incoming = msg
        }
    }
}
