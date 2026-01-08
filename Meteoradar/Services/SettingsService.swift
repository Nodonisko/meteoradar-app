//
//  SettingsService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 05.01.2026.
//

import Foundation
import Combine

/// Service responsible for persisting and managing app settings
final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    private let defaults = UserDefaults.standard
    
    /// Available time interval options in minutes for observed radar images
    static let availableIntervals = [5, 10, 15, 20]
    
    /// Default time interval in minutes
    static let defaultIntervalMinutes = 5
    
    // UserDefaults keys
    private enum Keys {
        static let overlayOpacity = "settings.overlayOpacity"
        static let forecastOverlayOpacity = "settings.forecastOverlayOpacity"
        static let radarImageIntervalMinutes = "settings.radarImageIntervalMinutes"
        static let imageQuality = "settings.imageQuality"
    }
    
    /// Opacity for observed radar frames (0.0 - 1.0)
    @Published var overlayOpacity: CGFloat {
        didSet {
            defaults.set(overlayOpacity, forKey: Keys.overlayOpacity)
        }
    }
    
    /// Opacity for forecast radar frames (0.0 - 1.0)
    @Published var forecastOverlayOpacity: CGFloat {
        didSet {
            defaults.set(forecastOverlayOpacity, forKey: Keys.forecastOverlayOpacity)
        }
    }
    
    /// Time interval between observed radar images in minutes (5, 10, 15, or 20)
    @Published var radarImageIntervalMinutes: Int {
        didSet {
            // Validate the value is one of the allowed options
            if !Self.availableIntervals.contains(radarImageIntervalMinutes) {
                radarImageIntervalMinutes = Self.defaultIntervalMinutes
            }
            defaults.set(radarImageIntervalMinutes, forKey: Keys.radarImageIntervalMinutes)
        }
    }
    
    /// Image quality setting (best = 2x resolution, lower = 1x for slower networks)
    @Published var imageQuality: Constants.ImageQuality {
        didSet {
            defaults.set(imageQuality.rawValue, forKey: Keys.imageQuality)
        }
    }
    
    private init() {
        // Load saved values or use defaults from Constants
        if defaults.object(forKey: Keys.overlayOpacity) != nil {
            self.overlayOpacity = defaults.double(forKey: Keys.overlayOpacity)
        } else {
            self.overlayOpacity = Constants.Radar.overlayAlpha
        }
        
        if defaults.object(forKey: Keys.forecastOverlayOpacity) != nil {
            self.forecastOverlayOpacity = defaults.double(forKey: Keys.forecastOverlayOpacity)
        } else {
            self.forecastOverlayOpacity = Constants.Radar.forecastOverlayAlpha
        }
        
        if defaults.object(forKey: Keys.radarImageIntervalMinutes) != nil {
            let savedInterval = defaults.integer(forKey: Keys.radarImageIntervalMinutes)
            // Validate saved value is valid, otherwise use default
            self.radarImageIntervalMinutes = Self.availableIntervals.contains(savedInterval) ? savedInterval : Self.defaultIntervalMinutes
        } else {
            self.radarImageIntervalMinutes = Self.defaultIntervalMinutes
        }
        
        if let savedQuality = defaults.string(forKey: Keys.imageQuality),
           let quality = Constants.ImageQuality(rawValue: savedQuality) {
            self.imageQuality = quality
        } else {
            self.imageQuality = Constants.Radar.defaultImageQuality
        }
    }
    
    /// Resets all settings to their default values
    func resetToDefaults() {
        overlayOpacity = Constants.Radar.overlayAlpha
        forecastOverlayOpacity = Constants.Radar.forecastOverlayAlpha
        radarImageIntervalMinutes = Self.defaultIntervalMinutes
        imageQuality = Constants.Radar.defaultImageQuality
    }
}

