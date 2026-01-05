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
    
    // UserDefaults keys
    private enum Keys {
        static let overlayOpacity = "settings.overlayOpacity"
        static let forecastOverlayOpacity = "settings.forecastOverlayOpacity"
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
    }
    
    /// Resets all settings to their default values
    func resetToDefaults() {
        overlayOpacity = Constants.Radar.overlayAlpha
        forecastOverlayOpacity = Constants.Radar.forecastOverlayAlpha
    }
}

