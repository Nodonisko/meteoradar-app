//
//  Color+Hex.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 05.02.2026.
//

import SwiftUI

extension Color {
    init(hex: String) {
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
            r = 0xFF
            g = 0xFF
            b = 0xFF
            a = 0xFF
        }

        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
