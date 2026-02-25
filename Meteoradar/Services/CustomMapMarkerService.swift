//
//  CustomMapMarkerService.swift
//  Meteoradar
//
//  Created by Cursor on 25.02.2026.
//

import Foundation
import CoreLocation
import os.log

@MainActor
final class CustomMapMarkerService: ObservableObject {
    static let shared = CustomMapMarkerService()

    @Published private(set) var markers: [CustomMapMarker]

    private let defaults: UserDefaults
    private let storageKey = "customMapMarkers.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meteoradar", category: "CustomMapMarkerService")

    var nextDefaultMarkerName: String {
        "Marker \(markers.count + 1)"
    }

    func defaultName(for markerID: UUID) -> String {
        guard let index = markers.firstIndex(where: { $0.id == markerID }) else {
            return nextDefaultMarkerName
        }
        return "Marker \(index + 1)"
    }

    private init() {
        self.defaults = UserDefaults(suiteName: SharedLocationStore.appGroupID) ?? .standard

        if let data = defaults.data(forKey: storageKey) {
            do {
                self.markers = try decoder.decode([CustomMapMarker].self, from: data)
            } catch {
                logger.error("Failed to decode custom markers: \(error.localizedDescription)")
                self.markers = []
            }
        } else {
            self.markers = []
        }
    }

    func addMarker(name: String, coordinate: CLLocationCoordinate2D, colorHex: String, glyph: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedGlyph = glyph.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty ? nextDefaultMarkerName : normalizedName

        let marker = CustomMapMarker(
            name: resolvedName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            colorHex: colorHex,
            glyph: normalizedGlyph.isEmpty ? MarkerGlyphOption.defaultGlyph.symbolName : normalizedGlyph
        )
        markers.append(marker)
        persist()
    }

    func updateMarker(id: UUID, name: String, colorHex: String, glyph: String) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedGlyph = glyph.trimmingCharacters(in: .whitespacesAndNewlines)

        markers[index].name = normalizedName.isEmpty ? "Marker \(index + 1)" : normalizedName
        markers[index].colorHex = colorHex
        markers[index].glyph = normalizedGlyph.isEmpty ? MarkerGlyphOption.defaultGlyph.symbolName : normalizedGlyph

        persist()
    }

    func deleteMarker(id: UUID) {
        markers.removeAll { $0.id == id }
        persist()
    }

    func marker(for id: UUID) -> CustomMapMarker? {
        markers.first { $0.id == id }
    }

    private func persist() {
        do {
            let data = try encoder.encode(markers)
            defaults.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to encode custom markers: \(error.localizedDescription)")
        }
    }
}
