#if targetEnvironment(macCatalyst)
import Foundation

final class TapPairingManager: NSObject {
  enum Role { case parent, child }
  enum State { case idle, advertising, browsing, tokenExchange, verifying, ready, failed(Error) }
  struct ResolvedEndpoint: Codable { let host: String; let port: UInt16 }

  var endpointProvider: (() -> ResolvedEndpoint?)?
  var onResolved: ((ResolvedEndpoint) -> Void)?
  var onState: ((State) -> Void)?

  private let role: Role

  init(role: Role) { self.role = role; super.init() }

  func start(ephemeral: [String:String]) {
    struct UnsupportedPlatformError: Error {}
    onState?(.failed(UnsupportedPlatformError()))
  }

  func cancel() {
    onState?(.idle)
  }
}
#else
//
//  TapPairingManager.swift
//  SyncTimer
//
//  Created by seb on 9/11/25.
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import UIKit

final class TapPairingManager: NSObject {
   enum Role { case parent, child }
   enum State { case idle, advertising, browsing, tokenExchange, verifying, ready, failed(Error) }
   struct ResolvedEndpoint: Codable { let host: String; let port: UInt16 }
     var endpointProvider: (() -> ResolvedEndpoint?)?
   private let service = "synctimer-tap"
   private let role: Role
   private var advertiser: MCNearbyServiceAdvertiser?
   private var browser: MCNearbyServiceBrowser?
   private var mcSession: MCSession?
   private var niSession: NISession?
   private var peer: MCPeerID?

   var onResolved: ((ResolvedEndpoint)->Void)?
   var onState: ((State)->Void)?

   init(role: Role) { self.role = role; super.init() }

   func start(ephemeral: [String:String]) {
     onState?(.idle)
     let me = MCPeerID(displayName: UIDevice.current.name)
     let sess = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
     sess.delegate = self; mcSession = sess
     switch role {
     case .parent:
       advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: ephemeral, serviceType: service)
       advertiser?.delegate = self
       advertiser?.startAdvertisingPeer()
       onState?(.advertising)
     case .child:
       browser = MCNearbyServiceBrowser(peer: me, serviceType: service)
       browser?.delegate = self
       browser?.startBrowsingForPeers()
       onState?(.browsing)
     }
   }

   func cancel() {
     advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
     mcSession?.disconnect(); niSession?.invalidate()
     onState?(.idle)
   }
 }

 extension TapPairingManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
   // Invite/accept
   func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer p: MCPeerID, withContext c: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
     peer = p; invitationHandler(true, mcSession)
   }
   func browser(_ b: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String : String]?) {
     guard let s = mcSession else { return }
     browser?.invitePeer(p, to: s, withContext: nil, timeout: 10)
   }
   func browser(_ b: MCNearbyServiceBrowser, lostPeer p: MCPeerID) {}

   // Session: exchange NI tokens and (parent→child) endpoint after <15 cm
   func session(_ s: MCSession, peer p: MCPeerID, didChange state: MCSessionState) {
     if state == .connected {
       DispatchQueue.main.async { self.onState?(.tokenExchange) }
       let ni = NISession(); ni.delegate = self; niSession = ni
       if let myToken = ni.discoveryToken,
          let data = try? NSKeyedArchiver.archivedData(withRootObject: myToken, requiringSecureCoding: true) {
         try? s.send(data, toPeers: [p], with: .reliable)
       }
     }
   }
   func session(_ s: MCSession, didReceive data: Data, fromPeer p: MCPeerID) {
     if let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
       let cfg = NINearbyPeerConfiguration(peerToken: token)
       niSession?.run(cfg)
       DispatchQueue.main.async { self.onState?(.verifying) }
     }
     // Parent sends endpoint once NI confirms close range; child receives here:
     else if let ep = try? JSONDecoder().decode(ResolvedEndpoint.self, from: data) {
       DispatchQueue.main.async { self.onState?(.ready); self.onResolved?(ep) }
     }
   }
   // Unused stream/resource
   func session(_ s: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
   func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
   func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
 }

 extension TapPairingManager: NISessionDelegate {
   func session(_ ni: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
     guard let o = nearbyObjects.first, let s = mcSession, role == .parent else { return }
       // NISessionDelegate
       if let d = o.distance, d < 0.15, role == .parent {
           guard let ep = endpointProvider?() else { return }
           if let data = try? JSONEncoder().encode(ep), let peer = self.peer {
               try? s.send(data, toPeers: [peer], with: .reliable)
           }
       }

   }
   func session(_ ni: NISession, didInvalidateWith error: Error) {}
   func sessionWasSuspended(_ ni: NISession) {}
   func sessionSuspensionEnded(_ ni: NISession) {}
 }
#endif
