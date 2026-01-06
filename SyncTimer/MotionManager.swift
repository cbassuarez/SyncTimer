#if canImport(CoreMotion) && !targetEnvironment(macCatalyst)
import SwiftUI
import Foundation
import CoreMotion
import Combine

/// Publishes device pitch & roll (in radians).
final class MotionManager: ObservableObject {
  static let shared = MotionManager()
  private let motion = CMMotionManager()
  private let queue  = OperationQueue()
  @Published var pitch: Double = 0
  @Published var roll:  Double = 0

  private init() {
    motion.deviceMotionUpdateInterval = 1/60
    motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] md, _ in
      guard let md = md else { return }
      DispatchQueue.main.async {
        self?.pitch = md.attitude.pitch
        self?.roll  = md.attitude.roll
      }
    }
  }
}

struct ParallaxEffect: ViewModifier {
  @StateObject private var motion = MotionManager.shared
  /// how “strong” the tilt is, in degrees
  let magnitude: Double

  func body(content: Content) -> some View {
    content
      // tilt around Y-axis for roll
      .rotation3DEffect(
        .degrees(motion.roll * magnitude),
        axis: (x: 0, y: 1, z: 0),
        perspective: 0.7
      )

  }
}

extension View {
  /// Simple parallax: rolls & pitches the view by device motion.
  func parallax(magnitude: Double = 5) -> some View {
    modifier(ParallaxEffect(magnitude: magnitude))
  }
}
#else
import SwiftUI
import Foundation
import Combine

/// Publishes device pitch & roll (in radians) – stubbed for Mac Catalyst.
final class MotionManager: ObservableObject {
  static let shared = MotionManager()
  @Published var pitch: Double = 0
  @Published var roll:  Double = 0

  private init() {}
}

struct ParallaxEffect: ViewModifier {
  @StateObject private var motion = MotionManager.shared
  /// how “strong” the tilt is, in degrees
  let magnitude: Double

  func body(content: Content) -> some View {
    content
  }
}

extension View {
  /// Simple parallax: rolls & pitches the view by device motion.
  func parallax(magnitude: Double = 5) -> some View {
    modifier(ParallaxEffect(magnitude: magnitude))
  }
}
#endif
