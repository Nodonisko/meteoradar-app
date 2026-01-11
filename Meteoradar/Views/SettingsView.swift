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
    @Environment(\.openURL) private var openURL
    
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.time_interval")
                        Picker("settings.time_interval", selection: $settings.radarImageIntervalMinutes) {
                            ForEach(SettingsService.availableIntervals, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("settings.time_interval_section")
                } footer: {
                    Text("settings.time_interval_footer")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.image_quality")
                        Picker("settings.image_quality", selection: $settings.imageQuality) {
                            Text("settings.quality_best").tag(Constants.ImageQuality.best)
                            Text("settings.quality_lower").tag(Constants.ImageQuality.lower)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("settings.image_quality_section")
                } footer: {
                    Text("settings.image_quality_footer")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.map_appearance")
                        Picker("settings.map_appearance", selection: $settings.mapAppearance) {
                            Text("settings.appearance_light").tag(Constants.MapAppearance.light)
                            Text("settings.appearance_dark").tag(Constants.MapAppearance.dark)
                            Text("settings.appearance_auto").tag(Constants.MapAppearance.auto)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("settings.map_appearance_section")
                } footer: {
                    Text("settings.map_appearance_footer")
                }
                
                Section {
                    Button(String(localized: "settings.reset_to_defaults")) {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
                
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack {
                            Image(systemName: "info.circle")
                            Text("settings.about")
                        }
                    }
                    
                    Button {
                        let subject = String(localized: "settings.email_subject")
                        if let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "mailto:suchydan@gmail.com?subject=\(encodedSubject)") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "envelope")
                            Text("settings.contact_us")
                        }
                    }
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

