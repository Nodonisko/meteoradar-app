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
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdatingLocation = false
    
    private var lastLocationUpdate: Date?
    private var locationCompletionHandler: ((Result<CLLocation, Error>) -> Void)?
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    deinit {
        stopLocationUpdates()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = Constants.Location.desiredAccuracy
        locationManager.distanceFilter = Constants.Location.distanceFilter
        
        // Use last known location immediately (cached from previous sessions)
        // This shows the dot right away before we get a fresh update
        if let cachedLocation = locationManager.location {
            location = cachedLocation
            print("Using cached location: \(cachedLocation.coordinate.latitude), \(cachedLocation.coordinate.longitude)")
        }
        
        // Request authorization and get initial location
        locationManager.requestWhenInUseAuthorization()
        
        // Request initial location when manager is set up
        // This will only execute once authorization is granted
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            getInitialLocation()
        }
    }

    // MARK: - Public Methods
    
    /// Requests a one-time location update with completion handler
    func requestLocationUpdate(completion: ((Result<CLLocation, Error>) -> Void)? = nil) {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            completion?(.failure(LocationError.notAuthorized))
            return
        }
        
        guard !isUpdatingLocation else {
            completion?(.failure(LocationError.updateInProgress))
            return
        }
        
        locationCompletionHandler = completion
        isUpdatingLocation = true
        
        // Use requestLocation for one-time updates - more energy efficient
        locationManager.requestLocation()
        
        print("Requesting one-time location update...")
    }
    
    /// Gets initial location when app launches
    func getInitialLocation() {
        requestLocationUpdate { [weak self] result in
            switch result {
            case .success(let location):
                print("Initial location obtained: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                // Start monitoring significant location changes after getting initial location
                self?.startSignificantLocationMonitoring()
            case .failure(let error):
                print("Failed to get initial location: \(error.localizedDescription)")
            }
        }
    }
    
    /// Starts monitoring significant location changes (ultra low energy)
    func startSignificantLocationMonitoring() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Cannot start significant location monitoring - not authorized")
            return
        }
        
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            print("Significant location change monitoring not available on this device")
            return
        }
        
        locationManager.startMonitoringSignificantLocationChanges()
        print("Started monitoring significant location changes (ultra low energy mode)")
    }
    
    /// Stops monitoring significant location changes
    func stopSignificantLocationMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        print("Stopped monitoring significant location changes")
    }
    
    /// Starts heading updates for compass beam on map
    func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else {
            print("Heading not available on this device")
            return
        }
        
        locationManager.headingFilter = 5 // Update every 5 degrees of change
        locationManager.startUpdatingHeading()
        print("Started heading updates for compass beam")
    }
    
    /// Stops heading updates
    func stopHeadingUpdates() {
        locationManager.stopUpdatingHeading()
        print("Stopped heading updates")
    }
    
    /// Stops any ongoing location updates
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        stopSignificantLocationMonitoring()
        stopHeadingUpdates()
        locationManager.delegate = nil
        isUpdatingLocation = false
        locationCompletionHandler = nil
    }

    func pauseForBackground() {
        stopHeadingUpdates()
    }

    func resumeForForeground() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        startHeadingUpdates()
    }
    
    /// Checks if enough time has passed since last update to warrant a new one
    var shouldUpdateLocation: Bool {
        guard let lastUpdate = lastLocationUpdate else { return true }
        let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
        return timeSinceLastUpdate >= Constants.Location.updateInterval
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // Update the location and timestamp
        location = newLocation
        lastLocationUpdate = Date()
        isUpdatingLocation = false
        
        // Call completion handler if one exists
        locationCompletionHandler?(.success(newLocation))
        locationCompletionHandler = nil
        
        print("Location updated: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isUpdatingLocation = false
        
        // Call completion handler with error if one exists
        locationCompletionHandler?(.failure(error))
        locationCompletionHandler = nil
        
        print("Location update failed: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorization granted")
            // Get initial location as soon as authorization is granted
            getInitialLocation()
            // Start heading updates for compass beam
            startHeadingUpdates()
        case .denied, .restricted:
            print("Location authorization denied")
            location = nil
            heading = nil
        case .notDetermined:
            print("Location authorization not determined")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Only update if we have a valid heading (negative accuracy means invalid)
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading
    }
}

// MARK: - Custom Errors

enum LocationError: LocalizedError {
    case notAuthorized
    case updateInProgress
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Location access not authorized"
        case .updateInProgress:
            return "Location update already in progress"
        }
    }
}
