//
//  ColorTools.swift
//  SyncTimer
//
//  Created by seb on 9/13/25.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Readable foreground (black/white) for a background Color
extension Color {
    var readableOnColor: Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        func lin(_ c: CGFloat) -> CGFloat {
            let d = Double(c)
            return d <= 0.03928 ? CGFloat(d/12.92) : CGFloat(pow((d+0.055)/1.055, 2.4))
        }
        let L = 0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b)
        return L > 0.54 ? .black : .white
    }
}

// MARK: - HEX / HSB (opaque only)
struct RGB { var r: Int; var g: Int; var b: Int }
struct HSB: Equatable { var h: Int; var s: Int; var b: Int }

extension Color {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                     .replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self = Color(UIColor(red: r, green: g, blue: b, alpha: 1))
    }
    func toHexRGB() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
        return String(format:"#%02X%02X%02X", Int(round(r*255)), Int(round(g*255)), Int(round(b*255)))
    }
    func toHSB() -> HSB {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 1
        ui.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        return .init(h: Int(round(h*360)), s: Int(round(s*100)), b: Int(round(br*100)))
    }
    static func fromHSB(_ hsb: HSB) -> Color {
        Color(UIColor(hue: CGFloat(hsb.h)/360, saturation: CGFloat(hsb.s)/100, brightness: CGFloat(hsb.b)/100, alpha: 1))
    }
}

// MARK: - Compact “recent colors” store (CSV under the hood)
struct ColorRecents {
    private let key: String
    private let max: Int
    init(key: String, max: Int = 6) { self.key = key; self.max = max }
    var all: [String] {
        (UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: ",").map { "#"+$0 }
    }
    mutating func push(_ hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "").uppercased()
        var arr = (UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: ",").map(String.init)
        arr.removeAll { $0 == cleaned }
        arr.insert(cleaned, at: 0)
        if arr.count > max { arr = Array(arr.prefix(max)) }
        UserDefaults.standard.set(arr.joined(separator: ","), forKey: key)
    }
}
