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
    
    init(bounds: GeoBounds) {
        self.radarCoverageRect = bounds.mapRect
        
        // Create a much larger bounding rect that extends well beyond the radar coverage
        // This ensures the dimming extends to the edges of the visible map
        let expansion = max(radarCoverageRect.width, radarCoverageRect.height) * 10
        
        self.boundingMapRect = MKMapRect(
            x: radarCoverageRect.minX - expansion,
            y: radarCoverageRect.minY - expansion,
            width: radarCoverageRect.width + expansion * 2,
            height: radarCoverageRect.height + expansion * 2
        )
        
        self.coordinate = bounds.center
        
        super.init()
    }
}

