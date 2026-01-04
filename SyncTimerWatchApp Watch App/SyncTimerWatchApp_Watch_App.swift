import SwiftUI
import WatchConnectivity


@main
struct SyncTimerWatchApp_Watch_App: App {
    // grab the shared manager
    @ObservedObject private var cm = ConnectivityManager.shared


    init() {
        print("[Watch] App init")
        _ = ConnectivityManager.shared
        // activate WCSession as soon as the app launches
    }

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                .onAppear {
                    print("[Watch] WatchMainView onAppear")
                }
        }
    }
}
 
