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
    
    // MARK: - Image Quality
    enum ImageQuality: String, CaseIterable, Identifiable {
        case best = "2x"
        case lower = "1x"
        
        var id: String { rawValue }
        
        /// URL suffix to append before .png extension
        var urlSuffix: String {
            switch self {
            case .best: return "2x"
            case .lower: return ""
            }
        }
    }
    
    // MARK: - Map Appearance
    enum MapAppearance: String, CaseIterable, Identifiable {
        case light
        case dark
        case auto
        
        var id: String { rawValue }
    }
    
    // MARK: - Radar Configuration
    struct Radar {
        // Default image quality (lower = 1x resolution for faster loading)
        static let defaultImageQuality: ImageQuality = .lower
        
        // Base URL pattern for radar images (timestamp will be inserted, suffix comes before .png)
        static let baseURL = RadarSharedConstants.baseURL
        static let forecastBaseURL = RadarSharedConstants.forecastBaseURL
        
        // URL parsing pattern - matches any datetime string (YYYYMMDD_HHMM) in the URL
        static let filenamePattern = RadarSharedConstants.filenamePattern
        
        // Animation configuration
        static let imageCount = 10 // Number of radar images to fetch and animate
        static let animationInterval: TimeInterval = 0.5 // Seconds between frames for rain movement visualization
        static let updateInterval: TimeInterval = 300 // 5 minutes in seconds
        static let retryInterval: TimeInterval = 10 // Retry every 10 seconds if image not available
        static let radarImageInterval: TimeInterval = RadarSharedConstants.radarIntervalSeconds // New radar image every 5 minutes
        static let serverLatencyOffset: Int = RadarSharedConstants.serverLatencyOffsetSeconds // Seconds to wait after 5-min mark for server to generate images
        
        // Sequential loading configuration
        static let maxRetryAttempts = 5 // Observed frames: initial attempt + one retry
        static let retryDelay: TimeInterval = 5.0 // Observed frame retry delay
        static let forecastMaxRetryAttempts = 10 // Forecast frames: allow retries for roughly one minute
        static let forecastRetryDelay: TimeInterval = 10.0 // Forecast frames wait longer before retry
        
        // Forecast configuration
        static let forecastHorizonMinutes: Int = 60 // Forecast range into future
        static let forecastIntervalMinutes: Int = 10 // Step between forecast frames

        // Overlay alpha configuration
        static let overlayAlpha: CGFloat = 0.7
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
        
        static func forecastOffsets() -> [Int] {
            guard forecastHorizonMinutes > 0, forecastIntervalMinutes > 0 else { return [] }
            return stride(from: forecastIntervalMinutes, through: forecastHorizonMinutes, by: forecastIntervalMinutes).map { $0 }
        }
        
        static func forecastURL(for sourceTimestamp: Date, offsetMinutes: Int, quality: ImageQuality) -> String {
            return String(format: forecastBaseURL, sourceTimestamp.radarTimestampString, offsetMinutes, quality.urlSuffix)
        }
        
        static func observedURL(for timestamp: Date, quality: ImageQuality) -> String {
            return String(format: baseURL, timestamp.radarTimestampString, quality.urlSuffix)
        }
    }
    
    // MARK: - Network Configuration
    struct Network {
        // Timeout for individual radar image requests (Edge network ~100 Kbps → 20 KB ≈ 2 seconds, but we allow headroom)
        static let radarRequestTimeout: TimeInterval = RadarSharedConstants.requestTimeout
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
