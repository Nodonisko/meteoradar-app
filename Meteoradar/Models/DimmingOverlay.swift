//
//  DimmingOverlay.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 10.01.2026.
//

import MapKit
import CoreLocation

/// Overlay that covers a large area around the radar coverage to create a dimming effect
/// outside the radar coverage area.
class DimmingOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    
    /// The rectangular area that should NOT be dimmed (the radar coverage area)
    let radarCoverageRect: MKMapRect
    
    override init() {
        // Get radar bounds from Constants
        let northEast = Constants.Radar.northEast
        let southWest = Constants.Radar.southWest
        
        // Calculate radar coverage rect
        let neMapPoint = MKMapPoint(northEast)
        let swMapPoint = MKMapPoint(southWest)
        
        self.radarCoverageRect = MKMapRect(
            x: swMapPoint.x,
            y: neMapPoint.y,
            width: neMapPoint.x - swMapPoint.x,
            height: swMapPoint.y - neMapPoint.y
        )
        
        // Create a much larger bounding rect that extends well beyond the radar coverage
        // This ensures the dimming extends to the edges of the visible map
        let expansion = max(radarCoverageRect.width, radarCoverageRect.height) * 10
        
        self.boundingMapRect = MKMapRect(
            x: radarCoverageRect.minX - expansion,
            y: radarCoverageRect.minY - expansion,
            width: radarCoverageRect.width + expansion * 2,
            height: radarCoverageRect.height + expansion * 2
        )
        
        // Center coordinate
        self.coordinate = CLLocationCoordinate2D(
            latitude: (northEast.latitude + southWest.latitude) / 2,
            longitude: (northEast.longitude + southWest.longitude) / 2
        )
        
        super.init()
    }
}

