import SwiftUI
import Combine
import CoreBluetooth
import UIKit


    
/// A UIHostingController subclass that only allows portrait
final class PortraitOnlyHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
}

/// A SwiftUI wrapper that embeds any View in our portrait-only host
struct PortraitLocked<Content: View>: UIViewControllerRepresentable {
    let rootView: Content

    func makeUIViewController(context: Context) -> PortraitOnlyHostingController<Content> {
        PortraitOnlyHostingController(rootView: rootView)
    }
    func updateUIViewController(_ vc: PortraitOnlyHostingController<Content>, context: Context) {
        vc.rootView = rootView
    }
}


/// Shadow for walkthrough pages
struct PageShadow: ViewModifier {
    var color: Color = .black.opacity(0.2)
    var radius: CGFloat = 8
    var x: CGFloat = 0
    var y: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: radius, x: x, y: y)
    }
}

/// Shadow for in-app elements (timer cards, bars, etc.)
struct ElementShadow: ViewModifier {
    var color: Color = .black.opacity(0.1)
    var radius: CGFloat = 4
    var x: CGFloat = 0
    var y: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: radius, x: x, y: y)
    }
}

extension View {
    func pageShadow(
        color: Color = .black.opacity(0.2),
        radius: CGFloat = 8,
        x: CGFloat = 0,
        y: CGFloat = 4
    ) -> some View {
        modifier(PageShadow(color: color, radius: radius, x: x, y: y))
    }

    func elementShadow(
        color: Color = .black.opacity(0.1),
        radius: CGFloat = 4,
        x: CGFloat = 0,
        y: CGFloat = 2
    ) -> some View {
        modifier(ElementShadow(color: color, radius: radius, x: x, y: y))
    }
}

// ─────────────────────────────────────────────────────────────────
// 1) A simple wrapper class to handle CBCentralManagerDelegate events
// ─────────────────────────────────────────────────────────────────
private class CentralDelegate: NSObject, CBCentralManagerDelegate, ObservableObject {
    @Published var state: CBManagerState = .unknown
    private var manager: CBCentralManager!

    override init() {
        super.init()
        // As soon as this manager is created, iOS automatically shows:
        //    ““SyncTimer” Would Like to Use Bluetooth”
        manager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
    }
}


// ─────────────────────────────────────────────────────────────────
// 2) PageZero_BLEPermission: “alert‐style” card that expands on Deny
// ─────────────────────────────────────────────────────────────────
private struct PageZero_BLEPermission: View {
    @Binding var mode: Int                // bound to WalkthroughView.currentPage
    @StateObject private var centralDelegate = CentralDelegate()
    @State private var didDeny: Bool = false

    private let titleFont = Font.custom("Roboto-SemiBold", size: 24)
    private let bodyFont  = Font.custom("Roboto-Regular", size: 16)

    var body: some View {
        VStack(spacing: 16) {
            // ─── (a) Title (always visible) ───────────────────
            Text("SyncTimer needs Bluetooth")
                .font(titleFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 20)

            // ─── (b) Body text: ALWAYS drawn, *full height* behind the system alert ───
            Text("""
                In order to discover and synchronize timers with nearby devices, \
                SyncTimer requires Bluetooth LE access—even if SyncTimer is in the background. \
                Please choose “Allow” in the system dialog below.
                """)
                .font(bodyFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 48)
                // Force this to occupy ≈300 pt, so that the system alert (≈140 pt tall)
                // floats in its middle.  You see text above & below the alert.
                .frame(height: 300)

            // ─── (c) If the user tapped “Don’t Allow,” show our hidden buttons now ───
            if didDeny {
                VStack(spacing: 16) {
                    Button(action: {
                        // Open this app’s Settings page so they can re-enable BT
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }) {
                        Text("Go to Settings")
                            .font(Font.custom("Roboto-SemiBold", size: 18))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 24)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button(action: {
                        mode = 1  // advance to page 1
                    }) {
                        Text("Next")
                            .font(Font.custom("Roboto-SemiBold", size: 18))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 24)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.top, 0)
            } else {
                // If they haven't denied yet, we leave a small spacer here,
                // so that the VStack’s total height fits nicely:
                Spacer(minLength: 20)
            }
        }
        // Listen for changes in the real CBCentralManager state
        .onReceive(centralDelegate.$state) { newState in
            switch newState {
            case .poweredOn:
                // The user tapped “Allow” → automatically advance after 0.3 s
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    mode = 1
                }
            case .unauthorized, .poweredOff:
                // The user tapped “Don’t Allow” → reveal our buttons underneath
                didDeny = true
            default:
                break
            }
        }
    }
}
// ─────────────────────────────────────────────────────────────────
// 3) WalkthroughView (showing Page 0 plus Pages 1–4 unchanged)
// ─────────────────────────────────────────────────────────────────
struct WalkthroughView: View {
    @AppStorage("hasSeenWalkthrough") private var hasSeenWalkthrough: Bool = false
    @AppStorage("walkthroughPage")     private var currentPage: Int     = 0
    @State private var justFinished: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var didAutoSkipBLE = false
    @StateObject private var centralDelegate = CentralDelegate()
    private let totalWithBLE = 6
    private let totalWithoutBLE = 5
    private var bgImageName: String {
           colorScheme == .dark ? "MainBG2" : "MainBG1"
       }

    var body: some View {
        ZStack {
            
            // 1) Dynamic backdrop
            AppBackdrop(imageName: bgImageName)

            // 2) Your dimming overlay
                .ignoresSafeArea()


                

            // Wrap all possible page‐views in a single Group
            Group {
                if currentPage == 0 {
                    // Page 0: BLE‐permission explanation, styled like the other cards
                    PageZero_BLEPermission(mode: $currentPage)
                        .frame(maxWidth: 360, maxHeight: 640)
                        .padding(.horizontal, 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                           .pageShadow(
                               color: Color.black.opacity(0.15),
                               radius: 8,
                               x: 0,
                               y: 4
                           )

                    
                        


                } else if currentPage == 1 {
                    PageOne_TimerCard(mode: $currentPage)
                        .frame(maxWidth: 360, maxHeight: 640)
                        .padding(.horizontal, 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                           .pageShadow(
                               color: Color.black.opacity(0.15),
                               radius: 8,
                               x: 0,
                               y: 4
                           )
                        


                } else if currentPage == 2 {
                    PageTwo_Countdown(mode: $currentPage)
                        .frame(maxWidth: 360, maxHeight: 640)
                        .padding(.horizontal, 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                           .pageShadow(
                               color: Color.black.opacity(0.15),
                               radius: 8,
                               x: 0,
                               y: 4
                           )

                        


                } else if currentPage == 3 {
                    PageThree_AddEvent(mode: $currentPage)
                        .frame(maxWidth: 360, maxHeight: 640)
                        .padding(.horizontal, 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                           .pageShadow(
                               color: Color.black.opacity(0.15),
                               radius: 8,
                               x: 0,
                               y: 4
                           )

                        

                } else if currentPage == 4 {
                    PageFour_Sync(mode: $currentPage) {
                                        // Instead of ending the walkthrough here,
                                        // advance to our new Support page at index 5
                                        currentPage = 5
                                    }
                    .frame(maxWidth: 360, maxHeight: 640)
                    .padding(.horizontal, 20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                       .pageShadow(
                           color: Color.black.opacity(0.15),
                           radius: 8,
                           x: 0,
                           y: 4
                       )

                    

                } else if currentPage == 5 {
                                    // ── PAGE 5: Support & Quick Start ──────────────────
                                    VStack(spacing: 24) {
                                        Spacer(minLength: 40)
                
                                        Text("Still stuck?")
                                            .font(.custom("Roboto-SemiBold", size: 24))
                                            .multilineTextAlignment(.center)
                                        Text("Watch our quick-start video, or browse the full docs for more details.")
                                            .font(.custom("Roboto-Regular", size: 14))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 16)
                                        Button("Watch Quick Start Video") {
                                            guard let url = URL(string: "https://www.stagedevices.com/support/quickstart") else { return }
                                            UIApplication.shared.open(url)
                                        }
                                        .font(.custom("Roboto-SemiBold", size: 18))
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 32)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                        .colorScheme(.dark)
                                        .foregroundColor(.primary)
                                        .cornerRadius(8)
                
                                        Button("View Full Documentation") {
                                            guard let url = URL(string: "https://stagedevices.com/support/docs") else { return }
                                            UIApplication.shared.open(url)
                                        }
                                        .font(.custom("Roboto-SemiBold", size: 18))
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 32)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                        .colorScheme(.dark)
                                        .foregroundColor(.primary)
                                        .cornerRadius(8)
                
                                        // Done button to exit the walkthrough
                                                                Button("Done") {
                                                                    finishWalkthrough()
                                                                }
                                                                .font(.custom("Roboto-SemiBold", size: 18))
                                                                .padding(.vertical, 12)
                                                                .padding(.horizontal, 32)
                                                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                                                .colorScheme(.dark)
                                                                .foregroundColor(.primary)
                                                                .cornerRadius(8)
                                                                Spacer()                                    }
                                    .frame(maxWidth: 360, maxHeight: 640)
                                    .padding(.horizontal, 20)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                       .pageShadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                                } else {
                                    // Fallback for any out‐of‐range page index:
                    EmptyView()
                        .frame(maxWidth: 360, maxHeight: 640)
                        .padding(.horizontal, 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                           .pageShadow(
                               color: Color.black.opacity(0.15),
                               radius: 8,
                               x: 0,
                               y: 4
                           )

                }
            }
            // overlay the skip button on every page
            .overlay(
                Button {
                    finishWalkthrough()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .opacity(0.1125)
                        .padding(12)
                }
                , alignment: .topTrailing )
            .overlay(alignment: .bottomLeading) {
                if currentPage > 0 {
                    let total = didAutoSkipBLE ? totalWithoutBLE : totalWithBLE
                    let step  = didAutoSkipBLE ? currentPage : (currentPage + 1)
                    Text("\((step) - 1)/\((total) - 1)")
                        .font(.custom("Roboto-Regular", size: 14))
                        .foregroundColor(.gray)
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                }
            }

            // Attach .onAppear to that single Group
            .onAppear {
                // if BLE already on, skip page 0 immediately
                if centralDelegate.state == .poweredOn && currentPage == 0 {
                    didAutoSkipBLE = true
                    currentPage = 1
                }
            }
            .onAppear {
                // If the user has already seen the walkthrough, do nothing
                guard !hasSeenWalkthrough else { return }
                
            }
        }
    }


    private func finishWalkthrough() {
        hasSeenWalkthrough = true
        justFinished = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            justFinished = false
        }
    }
}


private struct PageOne_TimerCard: View {
    @Binding var mode: Int          // bound to WalkthroughView’s currentPage


    // ── Simulate a running timer ───────────────────────────
    @State private var elapsed: TimeInterval = Double.random(in: 0...30)
    @State private var ticker: AnyCancellable?


    // ── Flip between .sync & .stop so TimerCard updates visually ─
    @State private var previewMode: ViewMode = .sync


    // ── Track that user did tap into Events at least once ───────
    @State private var didEnterEventsView: Bool = false
    @StateObject private var cueDisplay = CueDisplayController()


    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)


            Text("Welcome to SyncTimer")
                .font(.custom("Roboto-SemiBold", size: 24))

            Text("SyncTimer makes syncing multiple devices easy, meant for musicians who need synced countdowns.")
                .font(.custom("Roboto-Regular", size: 16))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            
            Text("This is your timer card: it displays a countdown, your timer, timer entries, and timer events.")
                .font(.custom("Roboto-Regular", size: 16))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            
            Text("1. Tap the left half (“EVENTS VIEW”) to switch to Events.")
                .font(.custom("Roboto-Regular", size: 16))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)


            Text("2. Tap the right half (“SYNC VIEW”) to return to Sync.")
                .font(.custom("Roboto-Regular", size: 16))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)


            ZStack {
                // Live TimerCard bound to previewMode
                TimerCard(
                    mode: $previewMode,
                    flashZero: .constant(false),
                    isRunning: true,
                    flashStyle: .fullTimer,
                    flashColor: .red,
                    syncDigits: [],
                    stopDigits: [],
                    phase: .running,
                    mainTime: elapsed,
                    stopActive: false,
                    stopRemaining: 0,
                    leftHint: "START POINT",
                    rightHint: "DURATION",
                    stopStep: 0,
                    makeFlashed: { AttributedString("") },
                    isCountdownActive: false,
                    events: []
                )
                .frame(height: 200)
                .environmentObject(AppSettings())
                .environmentObject(SyncSettings())
                .environmentObject(cueDisplay)


                // Two clear, half-width tap buttons
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        // Left half: switch to Events View
                        Button(action: {
                            previewMode = .stop
                            didEnterEventsView = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            Color.clear
                        }
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width/2, height: geo.size.height)


                        // Right half: switch back to Sync View & advance
                        Button(action: {
                            guard didEnterEventsView else { return }
                            previewMode = .sync
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            mode = 2
                        }) {
                            Color.clear
                        }
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width/2, height: geo.size.height)
                    }
                }
                .frame(height: 200)
            }


            Spacer()
        }
        .onAppear {
            // start live count-up from random value
            ticker?.cancel()
            ticker = Timer.publish(every: 0.01, on: .main, in: .common)
                .autoconnect()
                .sink { _ in elapsed += 0.01 }
        }
        .onDisappear {
            ticker?.cancel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: – Page 2: “Set Up Your Countdown” with a squeezed-row NumPad
// Page 2 of the walkthrough: “Set a 3-second countdown using the exact NumPad UI (with tighter vertical spacing).”
/// Page 2 of the walkthrough: “Set a 6-second countdown using the exact NumPad UI (with tighter vertical spacing, scaled down).”
private struct PageTwo_Countdown: View {
    @Binding var mode: Int   // bound to WalkthroughView’s currentPage

    // ── Preview state for digits & countdown ─────────────────────
    @State private var previewDigits: [Int] = []
    @State private var previewCountdownRemaining: TimeInterval = 0
    @State private var previewPhase: Phase = .idle
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var flashZero: Bool = false
    @State private var showSecondLine: Bool = false
    @StateObject private var cueDisplay = CueDisplayController()


    // ── Convert “raw digits” [3, 0, 0] → 3.00s ───────────────────
    private func digitsToTime(_ d: [Int]) -> TimeInterval {
        var a = d
        while a.count < 8 { a.insert(0, at: 0) }
        let h  = a[0] * 10 + a[1]
        let m  = a[2] * 10 + a[3]
        let s  = a[4] * 10 + a[5]
        let cs = a[6] * 10 + a[7]
        return TimeInterval(h * 3600 + m * 60 + s) + TimeInterval(cs) / 100.0
    }

    // ── What the TimerCard should display as “mainTime” ──────────
    private func displayMainTime() -> TimeInterval {
        let raw: TimeInterval
        switch previewPhase {
        case .idle:
            raw = previewDigits.isEmpty ? 0 : digitsToTime(previewDigits)
        case .running, .paused, .countdown:
            raw = previewCountdownRemaining
        }
        // always return a positive time for display
        return abs(raw)
    }


    // ── Start the 6-second countdown when “Start” is tapped ───────
    private func beginCountdown() {
        previewPhase = .running
        showSecondLine = false                         // reset for each run
        previewCountdownRemaining = -digitsToTime(previewDigits)
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.01, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let previous = previewCountdownRemaining
                previewCountdownRemaining += 0.01


                // when we hit zero, fire the flash and schedule the fade-in
                if previous < 0 && previewCountdownRemaining >= 0 {
                    flashZero = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        flashZero = false
                    }
                    // delay showing the second line by 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSecondLine = true
                        }
                    }
                }


                // when we cross +target, advance page
                if previewCountdownRemaining >= digitsToTime(previewDigits) {
                    timerCancellable?.cancel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        mode = 3
                    }
                }
            }
    }


    // ── Which digit is allowed next: 3 → 0 → 0 ───────────────────
    private var allowedDigit: Int? {
        switch previewDigits.count {
        case 0: return 3
        case 1, 2: return 0
        default: return nil
        }
    }

    // ── Handle taps on our custom NumPad ─────────────────────────
    private func handleTap(digit: Int) {
        guard previewPhase == .idle,
              let allowed = allowedDigit,
              digit == allowed
        else { return }

        previewDigits.append(digit)
        // **always** update the visible time
        previewCountdownRemaining = digitsToTime(previewDigits)
    }

    // ── Handle backspace in edit mode (only before countdown starts) ─
    private func handleBackspace() {
        guard previewPhase == .idle else { return }
        if !previewDigits.isEmpty {
            previewDigits.removeLast()
            previewCountdownRemaining = previewDigits.isEmpty
                ? 0
                : digitsToTime(previewDigits)
        }
    }

    var body: some View {
        VStack {
            VStack(spacing: 16) {
                Spacer(minLength: 24)

                // ── Title ───────────────────────────────────────────
                Text("Set a Countdown for 3s")
                    .font(.custom("Roboto-SemiBold", size: 36))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                ZStack {
                    Text("You will see the screen flash at 0...")
                        .font(.custom("Roboto-Regular", size: 16))
                        .multilineTextAlignment(.center)
                        .opacity(showSecondLine ? 0 : 1)


                    Text("... and then continue counting up.")
                        .font(.custom("Roboto-Regular", size: 16))
                        .multilineTextAlignment(.center)
                        .opacity(showSecondLine ? 1 : 0)
                }
            

                    

                // ── Live TimerCard preview ───────────────────────────
                TimerCard(
                    mode: .constant(.sync),
                    flashZero: $flashZero,
                    isRunning: (previewPhase == .running),
                    flashStyle: .fullTimer,
                    flashColor: .red,
                    syncDigits: [],
                    stopDigits: [],
                    phase: previewPhase,
                    mainTime: displayMainTime(),
                    stopActive: false,
                    stopRemaining: 0,
                    leftHint: "",
                    rightHint: "",
                    stopStep: 0,
                    makeFlashed: { AttributedString("") },
                    isCountdownActive: (previewPhase == .running),
                    events: []
                )
                .frame(height: 200)
                .environmentObject(AppSettings())
                .environmentObject(SyncSettings())
                .environmentObject(cueDisplay)

                // ── Custom NumPad (same layout as app, but tighter vertical spacing) ─
                VStack(spacing: 8) {
                    ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                        HStack(spacing: 16) {
                            ForEach(row, id: \.self) { num in
                                Button {
                                    handleTap(digit: num)
                                } label: {
                                    Text("\(num)")
                                        .font(.custom("Roboto-Regular", size: 32))
                                        .foregroundColor((allowedDigit == num) ? .primary : .gray)
                                        .frame(width: 80, height: 80)
                                }
                                .disabled(allowedDigit != num)
                            }
                        }
                    }
                    HStack(spacing: 16) {
                        Spacer().frame(width: 80, height: 80)
                        Button { handleTap(digit: 0) } label: {
                            Text("0")
                                .font(.custom("Roboto-Regular", size: 32))
                                .foregroundColor((allowedDigit == 0) ? .primary : .gray)
                                .frame(width: 80, height: 80)
                        }
                        .disabled(allowedDigit != 0)

                        Button(action: handleBackspace) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 28))
                                .foregroundColor(previewDigits.isEmpty ? .gray : .primary)
                                .frame(width: 80, height: 80)
                        }
                        .disabled(previewDigits.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // ── Bottom “Start” button ───────────────────────────
                SyncBottomButtons(
                    isCounting: (previewPhase == .running),
                    startStop: {
                        guard previewPhase == .idle, previewDigits.count == 3 else { return }
                        beginCountdown()
                    },
                    reset: { /* no-op for walkthrough */ }
                )
                .disabled(previewPhase != .idle || previewDigits.count < 3)

                Spacer(minLength: 24)
            }
            .scaleEffect(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


//–––––––––––––––––––––––––––––––––––––––––––––––––––––
//PAGE THREE
//–––––––––––––––––––––––––––––––––––––––––––––––––––––
private struct PageThree_AddEvent: View {
    @Binding var mode: Int     // bound to WalkthroughView’s currentPage
    @Environment(\.colorScheme) private var colorScheme: ColorScheme



    // ── Walkthrough state ───────────────────────────────────────────
    @State private var previewEvents: [Event] = []
    @State private var eventMode: EventMode = .stop
    @State private var didAddStop = false
    @State private var didAddCue  = false
    @State private var advanceWorkItem: DispatchWorkItem?
    @StateObject private var cueDisplay = CueDisplayController()


    // Pre-chosen times
    private let randomStart    = Double.random(in: 0...30)
    private let randomDuration = Double.random(in: 1...10)


    var body: some View {
        VStack(spacing: 16) {
            Text("Add Stop & Cue Events")
                .font(.custom("Roboto-SemiBold", size: 24))
                .padding(.top, 20)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("EVENTS VIEW is where you can add any events which stop, loop, cue, or restart the timer(s). In EVENTS VIEW, you use the numpad to set values, then bind those values to a timer event with the add button. Here, you can press the add button to add a random event without the numpad:")
                .font(.custom("Roboto-Regular", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)

            Group {
                if !didAddStop {
                    Text("1. Tap **ADD** below to schedule a random **STOP** event.")
                }
                else if !didAddCue {
                    Text("2. Tap **ADD** again to schedule a random **CUE** event.")
                }
                else {
                    Text("3. Use the ←/→ arrows above to cycle between your events.")
                }
            }
            .font(.custom("Roboto-Regular", size: 16))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 12)


            // Live TimerCard
            TimerCard(
                mode: .constant(.stop),
                flashZero: .constant(false),
                isRunning: false,
                flashStyle: .fullTimer,
                flashColor: .red,
                syncDigits: [],
                stopDigits: [],
                phase: .idle,
                mainTime: 0,
                stopActive: false,
                stopRemaining: 0,
                leftHint: "START POINT",
                rightHint: "DURATION",
                stopStep: 0,
                makeFlashed: { AttributedString("00:00:00.00") },
                isCountdownActive: false,
                events: previewEvents
            )
            .frame(height: 160)
            .environmentObject(AppSettings())
            .environmentObject(SyncSettings())
            .environmentObject(cueDisplay)


            // THINMATERIAL CARD + SHADOW + OFFSET
            EventsBar(
                events: $previewEvents,
                eventMode: $eventMode,
                isCounting: false,
                onAddStop:    { },
                onAddCue:     { },
                onAddRestart: { }
            )
            .frame(height: 80)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .offset(y: 38)
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard didAddStop, didAddCue, advanceWorkItem == nil else { return }
                    let job = DispatchWorkItem { mode += 1 }
                    advanceWorkItem = job
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: job)
                }
            )


            // Bottom ADD button
            EventBottomButtons(
                canAdd:    (eventMode == .stop && !didAddStop)
                        || (eventMode == .cue  &&  didAddStop && !didAddCue),
                eventMode: eventMode,
                add: {
                    if eventMode == .stop && !didAddStop {
                        let stopEv = StopEvent(eventTime: randomStart, duration: randomDuration)
                        previewEvents.append(.stop(stopEv))
                        didAddStop = true
                        eventMode = .cue
                    }
                    else if eventMode == .cue && didAddStop && !didAddCue {
                        let cueEv = CueEvent(cueTime: randomStart)
                        previewEvents.append(.cue(cueEv))
                        didAddCue = true
                    }
                },
                reset: { }
            )
            .disabled(!((eventMode == .stop && !didAddStop)
                    || (eventMode == .cue  &&  didAddStop && !didAddCue)))
            .offset(y: 40)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            Spacer()
        }
    }


    private func formattedTime(_ t: TimeInterval) -> String {
        let totalCs = Int((t * 100).rounded())
        let cs = totalCs % 100
        let s  = (totalCs / 100) % 60
        let m  = (totalCs / 6000) % 60
        let h  = totalCs / 360000
        return String(format: "%02d:%02d:%02d.%02d", h, m, s, cs)
    }
}
//–––––––––––––––––––––––––––––––––––––––––––––––––––––
//PAGE FOUR
//–––––––––––––––––––––––––––––––––––––––––––––––––––––
private struct PageFour_Sync: View {
    @Binding var mode: Int
    var didFinish: () -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme


    @State private var parentElapsed    = TimeInterval.random(in: 0...30)
    @State private var childElapsed     = TimeInterval.random(in: 0...30)
    @State private var synced           = false
    @State private var showPostSyncText = false
    @State private var finishScheduled  = false
    @State private var ticker: AnyCancellable?
    @StateObject private var cueDisplay = CueDisplayController()
    private let dt: TimeInterval = 1.0 / 100.0


    private let introText = """
SyncTimer supports three modes: LAN, Bluetooth, or Automatic Pairing. Tap SYNC below; once connected (green dot), devices stay in sync.
"""
    private let postSync = """
All set! Timers are aligned—changes on one reflect on the other instantly.
"""


    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("Sync with Others")
                .font(.custom("Roboto-SemiBold", size: 24))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.top, 20)


            // Body text (fades to post-sync after syncing)
            Text(showPostSyncText ? postSync : introText)
                .font(.custom("Roboto-Regular", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.3), value: showPostSyncText)


            // Two out-of-sync TimerCards
            VStack(spacing: 12) {
                TimerCard(
                    mode: .constant(.sync),
                    flashZero: .constant(false),
                    isRunning: true,
                    flashStyle: .fullTimer,
                    flashColor: .red,
                    syncDigits: [],
                    stopDigits: [],
                    phase: .running,
                    mainTime: parentElapsed,
                    stopActive: false,
                    stopRemaining: 0,
                    leftHint: "PARENT",
                    rightHint: "TIMER",
                    stopStep: 0,
                    makeFlashed: { AttributedString("") },
                    isCountdownActive: false,
                    events: []
                )
                .environmentObject(AppSettings())
                .environmentObject(mockSyncSettings)
                .environmentObject(cueDisplay)
                .frame(height: 150)


                TimerCard(
                    mode: .constant(.sync),
                    flashZero: .constant(false),
                    isRunning: true,
                    flashStyle: .fullTimer,
                    flashColor: .red,
                    syncDigits: [],
                    stopDigits: [],
                    phase: .running,
                    mainTime: childElapsed,
                    stopActive: false,
                    stopRemaining: 0,
                    leftHint: "CHILD",
                    rightHint: "TIMER",
                    stopStep: 0,
                    makeFlashed: { AttributedString("") },
                    isCountdownActive: false,
                    events: []
                )
                .environmentObject(AppSettings())
                .environmentObject(mockSyncSettings)
                .environmentObject(cueDisplay)
                .frame(height: 150)
                .padding(.top, 50) // <-- shifted down by 50pt
            }


            Spacer()


            // SYNC button + lamp
            HStack(spacing: 8) {
                Button(action: {
                    guard !synced else { return }
                    childElapsed = parentElapsed
                    withAnimation { showPostSyncText = true }
                    synced = true
                }) {
                    Text("SYNC")
                        .font(.custom("Roboto-SemiBold", size: 24))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .disabled(synced)


                Circle()
                    .fill(synced ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
            }
            .frame(width: 100,
                   height: 35)
            //.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            //.shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .padding(.bottom, 20)
            
        }
        .onAppear {
            // Start both timers
            ticker?.cancel()
            ticker = Timer.publish(every: dt, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    parentElapsed += dt
                    if synced {
                        childElapsed = parentElapsed
                    } else {
                        childElapsed += dt
                    }
                }
        }
        .onDisappear {
            ticker?.cancel()
        }
        .onChange(of: synced) { isNowSynced in
            // Schedule the walkthrough to finish 5s after syncing
            guard isNowSynced, !finishScheduled else { return }
            finishScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                didFinish()
            }
        }
    }


    private var mockSyncSettings: SyncSettings {
        let s = SyncSettings()
        s.isEnabled = synced
        s.isEstablished = synced
        return s
    }
}
