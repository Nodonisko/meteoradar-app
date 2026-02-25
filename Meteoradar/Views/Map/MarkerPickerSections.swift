//
//  MarkerPickerSections.swift
//  Meteoradar
//
//  Created by Cursor on 25.02.2026.
//

import SwiftUI

struct MarkerColorPickerSection: View {
    @Binding var selectedColorHex: String

    var body: some View {
        Section("Color") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(MarkerColorOption.allCases) { option in
                    Button {
                        selectedColorHex = option.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: option.hex))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.65), lineWidth: selectedColorHex == option.hex ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.displayName)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct MarkerGlyphPickerSection: View {
    @Binding var selectedGlyph: String

    var body: some View {
        Section("Glyph") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(MarkerGlyphOption.allCases) { option in
                    Button {
                        selectedGlyph = option.symbolName
                    } label: {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: option.symbolName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.65), lineWidth: selectedGlyph == option.symbolName ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityName)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
