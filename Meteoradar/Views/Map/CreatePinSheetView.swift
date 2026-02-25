//
//  CreatePinSheetView.swift
//  Meteoradar
//
//  Created by Cursor on 25.02.2026.
//

import SwiftUI

struct CreatePinSheetView: View {
    let defaultName: String
    let onCancel: () -> Void
    let onSave: (_ name: String, _ colorHex: String, _ glyph: String) -> Void

    @State private var name = ""
    @State private var selectedColorHex = MarkerColorOption.defaultColor.hex
    @State private var selectedGlyph = MarkerGlyphOption.defaultGlyph.symbolName

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "pin.name.optional",
                        text: $name,
                        prompt: Text(defaultName).foregroundColor(.secondary)
                    )
                } header: {
                    Text("pin.section.marker")
                }

                MarkerColorPickerSection(selectedColorHex: $selectedColorHex)
                MarkerGlyphPickerSection(selectedGlyph: $selectedGlyph)
            }
            .navigationTitle("pin.create.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("pin.cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("pin.save") {
                        onSave(name, selectedColorHex, selectedGlyph)
                    }
                }
            }
        }
    }
}
