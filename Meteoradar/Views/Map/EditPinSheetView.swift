//
//  EditPinSheetView.swift
//  Meteoradar
//
//  Created by Cursor on 25.02.2026.
//

import SwiftUI

struct EditPinSheetView: View {
    let marker: CustomMapMarker
    let defaultName: String
    let onDelete: () -> Void
    let onSave: (_ name: String, _ colorHex: String, _ glyph: String) -> Void

    @State private var name: String
    @State private var selectedColorHex: String
    @State private var selectedGlyph: String
    @State private var showDeleteConfirmation = false

    init(
        marker: CustomMapMarker,
        defaultName: String,
        onDelete: @escaping () -> Void,
        onSave: @escaping (_ name: String, _ colorHex: String, _ glyph: String) -> Void
    ) {
        self.marker = marker
        self.defaultName = defaultName
        self.onDelete = onDelete
        self.onSave = onSave

        _name = State(initialValue: marker.name)
        _selectedColorHex = State(initialValue: marker.colorHex)
        _selectedGlyph = State(initialValue: marker.glyph)
    }

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
            .navigationTitle("pin.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("pin.save") {
                        onSave(name, selectedColorHex, selectedGlyph)
                    }
                }
            }
            .alert("pin.delete.title", isPresented: $showDeleteConfirmation) {
                Button("pin.delete.confirm", role: .destructive) {
                    onDelete()
                }
                Button("pin.cancel", role: .cancel) {}
            } message: {
                Text("pin.delete.message")
            }
        }
    }
}
