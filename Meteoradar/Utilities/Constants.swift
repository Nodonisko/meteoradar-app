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
        static let baseURL = "http://localhost:8080/radar_%@_overlay2x.png"
        
        // Animation configuration
        static let imageCount = 10 // Number of radar images to fetch and animate
        static let animationInterval: TimeInterval = 0.5 // Seconds between frames for rain movement visualization
        static let updateInterval: TimeInterval = 300 // 5 minutes in seconds
        static let retryInterval: TimeInterval = 10 // Retry every 10 seconds if image not available
        static let radarImageInterval: TimeInterval = 300 // New radar image every 5 minutes
        
        // Sequential loading configuration
        static let maxRetryAttempts = 1 // Try once more if image fails to load
        static let retryDelay: TimeInterval = 1.0 // Brief delay between retries
        
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
    }
    
    // MARK: - Testing Configuration
    struct Testing {
        // Set to true to enable artificial loading delays for testing loading states
        static let enableSlowLoading = false
        static let artificialLoadingDelay: TimeInterval = 2.0 // seconds
        static let simulateRandomFailures = false // Set to true to randomly fail some requests
        static let failureRate: Double = 0.3 // 20% of requests will fail when enabled
    }
    
    // MARK: - Location Configuration
    struct Location {
        static let updateInterval: TimeInterval = 300 // 5 minutes
        static let distanceFilter: CLLocationDistance = 150 // meters
        static let userLocationSpan = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    }
}
