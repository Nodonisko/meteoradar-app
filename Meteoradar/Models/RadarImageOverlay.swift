//
//  RadarImageOverlay.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import MapKit
import CoreLocation
import UIKit

class RadarImageOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    var image: UIImage?  // Make this mutable so we can update it
    private(set) var timestamp: Date?
    
    init(coordinate: CLLocationCoordinate2D, boundingMapRect: MKMapRect, image: UIImage?, timestamp: Date?) {
        self.coordinate = coordinate
        self.boundingMapRect = boundingMapRect
        self.image = image
        self.timestamp = timestamp
        super.init()
    }
    
    func updateImage(_ newImage: UIImage?, timestamp: Date?) {
        self.image = newImage
        self.timestamp = timestamp
    }
    
    // Define the radar coverage area with exact bounds
    static func createCzechRadarOverlay(image: UIImage?, timestamp: Date?) -> RadarImageOverlay {
        // Exact radar image bounds
        let northEast = Constants.Radar.northEast
        let southWest = Constants.Radar.southWest
        
        // Center coordinate
        let centerCoordinate = CLLocationCoordinate2D(
            latitude: (northEast.latitude + southWest.latitude) / 2,
            longitude: (northEast.longitude + southWest.longitude) / 2
        )
        
        // Convert to map points
        let neMapPoint = MKMapPoint(northEast)
        let swMapPoint = MKMapPoint(southWest)
        
        // Create MKMapRect with proper bounds
        // x = westernmost, y = northernmost, width = east-west span, height = north-south span
        let mapRect = MKMapRect(
            x: swMapPoint.x,                      // West edge
            y: neMapPoint.y,                      // North edge  
            width: neMapPoint.x - swMapPoint.x,   // East - West
            height: swMapPoint.y - neMapPoint.y   // South - North
        )
        
        return RadarImageOverlay(
            coordinate: centerCoordinate,
            boundingMapRect: mapRect,
            image: image,
            timestamp: timestamp
        )
    }
}
