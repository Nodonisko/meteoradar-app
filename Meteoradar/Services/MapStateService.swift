//
//  MapStateService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 05.01.2026.
//

import Foundation
import MapKit

/// Service responsible for persisting and restoring map view state (position and zoom level)
final class MapStateService {
    static let shared = MapStateService()
    
    private let defaults = UserDefaults.standard
    
    // UserDefaults keys
    private enum Keys {
        static let centerLatitude = "mapState.centerLatitude"
        static let centerLongitude = "mapState.centerLongitude"
        static let spanLatitudeDelta = "mapState.spanLatitudeDelta"
        static let spanLongitudeDelta = "mapState.spanLongitudeDelta"
    }
    
    private init() {}
    
    /// Saves the current map region to UserDefaults
    func saveRegion(_ region: MKCoordinateRegion) {
        defaults.set(region.center.latitude, forKey: Keys.centerLatitude)
        defaults.set(region.center.longitude, forKey: Keys.centerLongitude)
        defaults.set(region.span.latitudeDelta, forKey: Keys.spanLatitudeDelta)
        defaults.set(region.span.longitudeDelta, forKey: Keys.spanLongitudeDelta)
    }
    
    /// Loads the previously saved map region, or returns nil if no region was saved
    func loadRegion() -> MKCoordinateRegion? {
        // object(forKey:) returns nil if key doesn't exist, unlike double(forKey:) which returns 0.0
        guard defaults.object(forKey: Keys.centerLatitude) != nil else {
            return nil
        }
        
        let centerLatitude = defaults.double(forKey: Keys.centerLatitude)
        let centerLongitude = defaults.double(forKey: Keys.centerLongitude)
        let spanLatitudeDelta = defaults.double(forKey: Keys.spanLatitudeDelta)
        let spanLongitudeDelta = defaults.double(forKey: Keys.spanLongitudeDelta)
        
        // Validate the span values are reasonable
        guard spanLatitudeDelta > 0, spanLongitudeDelta > 0 else {
            return nil
        }
        
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude),
            span: MKCoordinateSpan(latitudeDelta: spanLatitudeDelta, longitudeDelta: spanLongitudeDelta)
        )
    }
}

