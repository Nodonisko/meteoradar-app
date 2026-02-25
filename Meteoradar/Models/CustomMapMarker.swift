//
//  CustomMapMarker.swift
//  Meteoradar
//
//  Created by Cursor on 25.02.2026.
//

import Foundation
import CoreLocation

struct CustomMapMarker: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var colorHex: String
    var glyph: String

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        colorHex: String,
        glyph: String
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.colorHex = colorHex
        self.glyph = glyph
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
