//
//  Constants.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import Foundation
import CoreLocation
import MapKit

struct Constants {
    
    // MARK: - Radar Configuration
    struct Radar {
        // Base URL pattern for radar images (timestamp will be inserted)
        static let baseURL = "https://radar.danielsuchy.cz/output/radar_%@_overlay2x.png"
        static let forecastBaseURL = "https://radar.danielsuchy.cz/output_forecast/radar_%@_forecast_fct%d_overlay.png"
        
        // URL parsing pattern - matches any datetime string (YYYYMMDD_HHMM) in the URL
        static let filenamePattern = #"(\d{8}_\d{4})"#
        
        // Animation configuration
        static let imageCount = 10 // Number of radar images to fetch and animate
        static let animationInterval: TimeInterval = 0.5 // Seconds between frames for rain movement visualization
        static let updateInterval: TimeInterval = 300 // 5 minutes in seconds
        static let retryInterval: TimeInterval = 10 // Retry every 10 seconds if image not available
        static let radarImageInterval: TimeInterval = 300 // New radar image every 5 minutes
        
        // Sequential loading configuration
        static let maxRetryAttempts = 5 // Observed frames: initial attempt + one retry
        static let retryDelay: TimeInterval = 5.0 // Observed frame retry delay
        static let forecastMaxRetryAttempts = 10 // Forecast frames: allow retries for roughly one minute
        static let forecastRetryDelay: TimeInterval = 10.0 // Forecast frames wait longer before retry
        
        // Forecast configuration
        static let forecastHorizonMinutes: Int = 60 // Forecast range into future
        static let forecastIntervalMinutes: Int = 10 // Step between forecast frames
        static let forecastOverlayAlpha: CGFloat = 0.5
        
        // Cache configuration
        static let cacheEnabled = true // Enable file system caching
        static let maxCacheSize: Int64 = 50 * 1024 * 1024 // 50MB cache limit
        static let cacheExpirationDays = 7 // Remove cached images older than 7 days
        
        // Czech radar coverage bounds
        static let northEast = CLLocationCoordinate2D(latitude: 51.458, longitude: 19.624)
        static let southWest = CLLocationCoordinate2D(latitude: 48.047, longitude: 11.267)
        
        // Default map region for Czech radar
        static let defaultRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (northEast.latitude + southWest.latitude) / 2,
                longitude: (northEast.longitude + southWest.longitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 8.5)
        )
        
        static let overlayAlpha: CGFloat = 0.7
        
        static func forecastOffsets() -> [Int] {
            guard forecastHorizonMinutes > 0, forecastIntervalMinutes > 0 else { return [] }
            return stride(from: forecastIntervalMinutes, through: forecastHorizonMinutes, by: forecastIntervalMinutes).map { $0 }
        }
        
        static func forecastURL(for sourceTimestamp: Date, offsetMinutes: Int) -> String {
            return String(format: forecastBaseURL, sourceTimestamp.radarTimestampString, offsetMinutes)
        }
    }
    
    // MARK: - Testing Configuration
    struct Testing {
        // Set to true to enable artificial loading delays for testing loading states
        static let enableSlowLoading = false
        static let artificialLoadingDelay: TimeInterval = 2.0 // seconds
        static let simulateRandomFailures = false // Set to true to randomly fail some requests
        static let failureRate: Double = 0.3 // 20% of requests will fail when enabled
    }
    
    // MARK: - Network Configuration
    struct Network {
        // Timeout for individual radar image requests (Edge network ~100 Kbps → 20 KB ≈ 2 seconds, but we allow headroom)
        static let radarRequestTimeout: TimeInterval = 25
    }
    
    // MARK: - Location Configuration
    struct Location {
        // Minimum time between location updates (5 minutes)
        static let updateInterval: TimeInterval = 300
        
        // Distance filter for location updates (500m - larger for better battery life)
        static let distanceFilter: CLLocationDistance = 500
        
        // Desired accuracy - balanced for weather radar use case
        // Using kCLLocationAccuracyHundredMeters for better battery life
        // This is sufficient accuracy for weather radar positioning
        static let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
        
        // Map span when centering on user location
        static let userLocationSpan = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        
        // Timeout for location requests (30 seconds)
        static let locationTimeout: TimeInterval = 30
    }
}
