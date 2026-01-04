//
//  PadPortraitMetrics.swift
//  SyncTimer
//
//  Created by seb on 9/23/25.
//

import Foundation
import SwiftUI

enum PadBP: CaseIterable { case compact, small, medium, large }

@inline(__always)
func padBP(_ w: CGFloat) -> PadBP {
    switch w {
    case ..<620:       return .compact
    case 620..<768:    return .small
    case 768..<980:    return .medium
    default:           return .large
    }
}


struct PadPortraitMetrics {
    

    let bp: PadBP
    let insets: CGFloat = 20

    init(width: CGFloat) { self.bp = padBP(width) }

    // Card target height (clamped)
    func cardHeight(for winH: CGFloat) -> CGFloat {
        let t = max(300, min(winH * 0.42, maxCard))
        return max(minCard, t)
    }
    private var minCard: CGFloat {
        switch bp { case .compact: 300; case .small: 320; case .medium: 340; case .large: 360 }
    }
    private var maxCard: CGFloat {
        switch bp { case .compact: 520; case .small: 560; case .medium: 600; case .large: 640 }
    }

    // Main time font clamp
    func mainTimeFS(width w: CGFloat, height h: CGFloat) -> CGFloat {
        let base = min(w * 0.16, h * 0.28)
        let (lo, hi): (CGFloat, CGFloat) = {
            switch bp {
            case .compact: (56, 120)
            case .small:   (62, 132)
            case .medium:  (68, 148)
            case .large:   (72, 164)
            }
        }()
        return max(lo, min(hi, base))
    }

    var modeBarH: CGFloat {
            switch bp { case .compact: 72; case .small: 80; case .medium: 88; case .large: 96 }
        }
        var numpadH: CGFloat {
            switch bp { case .compact: 280; case .small: 320; case .medium: 360; case .large: 400 }
        }
        var minKey: CGFloat {
            switch bp { case .compact: 56; case .small: 60; case .medium: 64; case .large: 68 }
        }
        let bottomButtonsH: CGFloat = 64
    }
    
    // ─────────────────────────────────────────────────────────────────────────────
    // NEW: unified metrics for both orientations. Children will read from here.
    // Portrait uses PadPortraitMetrics above; landscape tightens the top band to fit.
    // ─────────────────────────────────────────────────────────────────────────────
    struct PadMetrics {
        // ── 13" tuning (portrait): lower all sections without affecting smaller iPads
        private enum XL13Tuning {
            static let portraitTopPct: CGFloat = 0.36   // was 0.42 → 13" would clamp; now ~492pt instead of 560
            static let portraitTopMax: CGFloat = 520    // was 560
            static let modeBarDelta:  CGFloat = -12     // 96 → 84
            static let numpadDelta:   CGFloat = -60     // 400 → 340
            static let bottomH:       CGFloat = 60      // 64 → 60
        }
        
        // Landscape mild trims for 13"
        private enum XL13Landscape {
            static let topPct:  CGFloat = 0.34          // was 0.36 base
            static let topMax:  CGFloat = 440           // was 480
            static let modeBarDelta: CGFloat = -12
            static let numpadDelta:  CGFloat = -40
            static let bottomH:      CGFloat = 58
        }
        let size: CGSize
        let portrait: Bool
        let bp: PadBP
        let insetsH: CGFloat
        let topH: CGFloat
        let modeBarH: CGFloat
        let numpadH: CGFloat
        let bottomH: CGFloat
    
        // Single-line main timer font size (industry-safe)
        var fsTimer: CGFloat {
            let innerW = max(0, size.width - insetsH*2)
            // Width gate keeps ellipsis rare at compact widths, height gate keeps balance on 13"
            return max(28, min(topH * (portrait ? 0.28 : 0.26), innerW / (portrait ? 4.0 : 4.6)))
        }
    
        static func make(for size: CGSize) -> PadMetrics {
            let w = size.width, h = size.height
            let portrait = h >= w
            let bp = padBP(w)
            let insets: CGFloat = 20
            // Top band + sections with explicit trims for 13" (bp == .large)
                let top: CGFloat
                let modeBar: CGFloat
                let numpad: CGFloat
                let bottom: CGFloat
            
                if portrait {
                    // Portrait
                    let topPct  = (bp == .large) ? XL13Tuning.portraitTopPct : 0.42
                    let topMax  = (bp == .large) ? XL13Tuning.portraitTopMax : 560
                    top = clamp(h * topPct, 300, topMax)
            
                    let baseMode = CGFloat([PadBP.compact:72, .small:80, .medium:88, .large:96][bp]!)
                    modeBar = baseMode + ((bp == .large) ? XL13Tuning.modeBarDelta : 0)
            
                    let baseNumpad = CGFloat([PadBP.compact:280, .small:320, .medium:360, .large:400][bp]!)
                    numpad = baseNumpad + ((bp == .large) ? XL13Tuning.numpadDelta : 0)
            
                    bottom = (bp == .large) ? XL13Tuning.bottomH : 64
                } else {
                    // Landscape
                    let topPct  = (bp == .large) ? XL13Landscape.topPct : 0.36
                    let topMax  = (bp == .large) ? XL13Landscape.topMax : 480
                    top = clamp(h * topPct, 260, topMax)
            
                    let baseMode = CGFloat([PadBP.compact:64, .small:72, .medium:80, .large:88][bp]!) // slightly smaller set in landscape
                modeBar = baseMode + ((bp == .large) ? XL13Landscape.modeBarDelta : 0)
            
                    let baseNumpad = CGFloat([PadBP.compact:260, .small:300, .medium:340, .large:380][bp]!)
                    numpad = baseNumpad + ((bp == .large) ? XL13Landscape.numpadDelta : 0)
            
                    bottom = (bp == .large) ? XL13Landscape.bottomH : 60
                }
            return .init(size: size, portrait: portrait, bp: bp, insetsH: insets,
                         topH: top, modeBarH: modeBar, numpadH: numpad, bottomH: bottom)
        }
    }
    
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }
    
    private struct PadMetricsKey: EnvironmentKey {
        static let defaultValue = PadMetrics.make(for: .init(width: 834, height: 1194))
    }
    extension EnvironmentValues {
        var padMetrics: PadMetrics {
            get { self[PadMetricsKey.self] }
            set { self[PadMetricsKey.self] = newValue }
       }
    }
