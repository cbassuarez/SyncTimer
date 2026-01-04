//
//  ClockKalman.swift
//  SyncTimer
//
//  Created by seb on 9/10/25.
//

import Foundation


/// Two-state clock Kalman filter:
///  state x = [offset, drift]^T  (seconds, seconds/second)
///  F = [[1, dt],[0,1]]
///  Q = diag([1e-6, 1e-9]) * dt
///  H = [1, 0]
///  R = max((rtt/2)^2, 2.5e-5)
final class ClockKalman {
    private(set) var x0: Double = 0       // offset
    private(set) var x1: Double = 0       // drift
    private var P00: Double = 1
    private var P01: Double = 0
    private var P10: Double = 0
    private var P11: Double = 1
    private var tLast: Double? = nil      // last update time (systemUptime seconds)

    // rolling RTTs for gating (95th percentile)
    private var rttSamples: [Double] = []
    private let rttWindow: Int = 32

    /// Predicted offset at `now` without mutating state (applies drift since last update).
    func predictedOffset(at now: Double) -> Double {
        guard let t = tLast else { return x0 }
        let dt = max(0, now - t)
        return x0 + x1 * dt
    }

    /// Update filter with measurement `z` (seconds) and one-way RTT/2 via `rtt` (seconds),
    /// taken at child receive time `now` (systemUptime).
    func update(z: Double, rtt: Double, now: Double) {
        // ----- Gating (95th percentile of last 32 RTTs) -----
        let p95 = percentile95(of: rttSamples)
        if !p95.isNaN, rtt > p95 { return } // gate outlier

        // ----- Predict -----
        let dt: Double = {
            guard let t = tLast else { return 0 }
            return max(0, now - t)
        }()
        let q0 = 1e-6 * dt
        let q1 = 1e-9 * dt

        // x = F x
        // [x0] = [1 dt][x0]
        // [x1]   [0  1][x1]
        x0 = x0 + x1 * dt
        // x1 unchanged

        // P = F P F^T + Q
        // Expanded for 2x2:
        let P00n = P00 + dt * (P01 + P10) + dt * dt * P11 + q0
        let P01n = P01 + dt * P11
        let P10n = P10 + dt * P11
        let P11n = P11 + q1
        P00 = P00n; P01 = P01n; P10 = P10n; P11 = P11n

        // ----- Update -----
        // H = [1 0]
        let y = z - x0
        let R = max(pow(rtt * 0.5, 2), 2.5e-5)
        let S = P00 + R
        let K0 = P00 / S
        let K1 = P10 / S

        x0 += K0 * y
        x1 += K1 * y

        // P = (I - K H) P
        // I - K H = [[1-K0, 0], [-K1, 1]]
        let P00u = (1 - K0) * P00
        let P01u = (1 - K0) * P01
        let P10u = -K1 * P00 + P10
        let P11u = -K1 * P01 + P11
        P00 = P00u; P01 = P01u; P10 = P10u; P11 = P11u

        tLast = now

        // Update RTT history (for next gates)
        rttSamples.append(rtt)
        if rttSamples.count > rttWindow { rttSamples.removeFirst(rttSamples.count - rttWindow) }
    }

    private func percentile95(of xs: [Double]) -> Double {
        guard xs.count > 0 else { return .nan }
        let s = xs.sorted()
        let idx = Int(Double(s.count - 1) * 0.95)
        return s[min(max(0, idx), s.count - 1)]
    }
}

