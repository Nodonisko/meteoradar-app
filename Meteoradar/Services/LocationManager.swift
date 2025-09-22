//
//  LocationManager.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private var lastLocationUpdate: Date?
    private let locationUpdateInterval: TimeInterval = Constants.Location.updateInterval
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest // Less accurate but more battery efficient
        locationManager.distanceFilter = Constants.Location.distanceFilter
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    deinit {
        locationManager.stopUpdatingLocation()
        locationManager.delegate = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        let now = Date()
        
        // Check if this is the first update or if 5 minutes have passed
        if let lastUpdate = lastLocationUpdate {
            let timeSinceLastUpdate = now.timeIntervalSince(lastUpdate)
            if timeSinceLastUpdate < locationUpdateInterval {
                return // Skip this update - not enough time has passed
            }
        }
        
        // Update the location and timestamp
        location = newLocation
        lastLocationUpdate = now
        
        print("Location updated: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    // Method to manually request a location update (useful for user-triggered updates)
    func requestLocationUpdate() {
        lastLocationUpdate = nil // Reset the timer to allow immediate update
        locationManager.requestLocation()
    }
}
