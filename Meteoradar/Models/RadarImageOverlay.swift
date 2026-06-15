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
    private(set) var isForecast: Bool = false
    
    init(coordinate: CLLocationCoordinate2D, boundingMapRect: MKMapRect, image: UIImage?, timestamp: Date?, isForecast: Bool = false) {
        self.coordinate = coordinate
        self.boundingMapRect = boundingMapRect
        self.image = image
        self.timestamp = timestamp
        self.isForecast = isForecast
        super.init()
    }
    
    func updateImage(_ newImage: UIImage?, timestamp: Date?, isForecast: Bool = false) {
        self.image = newImage
        self.timestamp = timestamp
        self.isForecast = isForecast
    }
    
    // Define the radar coverage area from the image's geographic bounds.
    static func create(bounds: GeoBounds, image: UIImage?, timestamp: Date?, isForecast: Bool = false) -> RadarImageOverlay {
        return RadarImageOverlay(
            coordinate: bounds.center,
            boundingMapRect: bounds.mapRect,
            image: image,
            timestamp: timestamp,
            isForecast: isForecast
        )
    }
}
