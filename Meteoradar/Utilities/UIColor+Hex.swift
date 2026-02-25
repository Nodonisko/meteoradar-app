//
//  UIColor+Hex.swift
//  Meteoradar
//
//  Created by Cursor on 25.02.2026.
//

import UIKit

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch cleaned.count {
        case 6:
            r = (int >> 16) & 0xFF
            g = (int >> 8) & 0xFF
            b = int & 0xFF
            a = 0xFF
        case 8:
            r = (int >> 24) & 0xFF
            g = (int >> 16) & 0xFF
            b = (int >> 8) & 0xFF
            a = int & 0xFF
        default:
            r = 0; g = 0x7A; b = 0xFF; a = 0xFF
        }

        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}
