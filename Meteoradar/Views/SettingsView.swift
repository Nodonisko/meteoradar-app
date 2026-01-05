//
//  SettingsView.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 05.01.2026.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("settings.radar_opacity")
                            Spacer()
                            Text("\(Int(settings.overlayOpacity * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.overlayOpacity, in: 0.1...1.0, step: 0.05)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("settings.forecast_opacity")
                            Spacer()
                            Text("\(Int(settings.forecastOverlayOpacity * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.forecastOverlayOpacity, in: 0.1...1.0, step: 0.05)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("settings.overlay_section")
                } footer: {
                    Text("settings.overlay_footer")
                }
                
                Section {
                    Button(String(localized: "settings.reset_to_defaults")) {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "settings.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}

