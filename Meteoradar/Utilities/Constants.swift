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
    
    // MARK: - App
    struct App {
        static let supportEmail = "suchydan@gmail.com"
    }
    
    // MARK: - Image Quality
    enum ImageQuality: String, CaseIterable, Identifiable {
        case best = "2x"
        case lower = "1x"
        
        var id: String { rawValue }
        
        /// URL suffix to append before .png extension
        var urlSuffix: String {
            switch self {
            case .best: return ""
            case .lower: return "_small"
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
        static let radarImageInterval: TimeInterval = RadarSharedConstants.radarIntervalSeconds // New radar image every 5 minutes

        // Retry configuration. A single cadence drives all retries; per-kind
        // attempt budgets below bound how long a frame keeps retrying.
        static let retryInterval: TimeInterval = 10 // Delay between retry passes
        static let maxRetryAttempts = 5 // Observed frames: ~50s of retries
        static let forecastMaxRetryAttempts = 10 // Forecast frames: ~100s (generation can lag)
        
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
        
        // Default map region for the currently selected radar product.
        // Only read for the initial map setup (steady state), never during a product switch.
        static var defaultRegion: MKCoordinateRegion {
            RadarProductService.shared.selectedProduct.region
        }
        
        static func forecastOffsets() -> [Int] {
            guard forecastHorizonMinutes > 0, forecastIntervalMinutes > 0 else { return [] }
            return stride(from: forecastIntervalMinutes, through: forecastHorizonMinutes, by: forecastIntervalMinutes).map { $0 }
        }
        
        // The radar product is always passed explicitly. These builders intentionally
        // do NOT default to the selected product: reading that mutable global mid-switch
        // (while @Published is still in willSet) would resolve to the *previous* product.
        static func forecastURL(for sourceTimestamp: Date, offsetMinutes: Int, quality: ImageQuality, productID: String) -> String {
            return String(format: forecastBaseURL, productID, productID, sourceTimestamp.radarTimestampString, offsetMinutes, quality.urlSuffix)
        }
        
        static func observedURL(for timestamp: Date, quality: ImageQuality, productID: String) -> String {
            return String(format: baseURL, productID, productID, timestamp.radarTimestampString, quality.urlSuffix)
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
        
        // Timeout for location requests (30 seconds)
        static let locationTimeout: TimeInterval = 30
    }
}
