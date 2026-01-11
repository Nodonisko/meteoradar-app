//
//  MapViewWithOverlay.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import SwiftUI
import MapKit
import UIKit
import Combine

struct MapViewWithOverlay: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @ObservedObject var radarImageManager: RadarImageManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true  // Use Apple's native user location with heading
        mapView.userTrackingMode = .none  // Don't auto-follow, let user pan freely
        mapView.setRegion(region, animated: false)
        
        // Store reference for settings changes and apply initial map appearance
        context.coordinator.setMapView(mapView)
        applyMapAppearance(to: mapView)
        
        // Hide built-in compass and add custom one in top-left corner
        mapView.showsCompass = false
        let compassButton = MKCompassButton(mapView: mapView)
        compassButton.compassVisibility = .adaptive  // Only shows when map is rotated
        compassButton.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(compassButton)
        
        NSLayoutConstraint.activate([
            compassButton.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 68),
            compassButton.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
        
        // Add dimming overlay first (renders below radar overlay)
        // This darkens areas outside radar coverage
        let dimmingOverlay = DimmingOverlay()
        mapView.addOverlay(dimmingOverlay, level: .aboveRoads)
        
        // Create ONE radar overlay that we'll keep updating
        let radarOverlay = RadarImageOverlay.createCzechRadarOverlay(
            image: radarImageManager.radarSequence.currentImage,
            timestamp: radarImageManager.radarSequence.currentTimestamp
        )
        context.coordinator.radarOverlay = radarOverlay
        mapView.addOverlay(radarOverlay, level: .aboveRoads)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {        
        // Simply update the radar overlay's image - no removal/addition needed!
        context.coordinator.updateRadarImage(
            radarImageManager: radarImageManager,
            currentImage: radarImageManager.radarSequence.currentImage,
            timestamp: radarImageManager.radarSequence.currentTimestamp
        )
        
        // Update map appearance when setting changes
        applyMapAppearance(to: mapView)
    }
    
    private func applyMapAppearance(to mapView: MKMapView) {
        let appearance = SettingsService.shared.mapAppearance
        switch appearance {
        case .light:
            mapView.overrideUserInterfaceStyle = .light
        case .dark:
            mapView.overrideUserInterfaceStyle = .dark
        case .auto:
            mapView.overrideUserInterfaceStyle = .unspecified
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithOverlay
        var radarOverlay: RadarImageOverlay?
        var radarRenderer: RadarImageRenderer?
        private var settingsCancellables = Set<AnyCancellable>()
        private weak var mapView: MKMapView?
        
        init(_ parent: MapViewWithOverlay) {
            self.parent = parent
            super.init()
            
            // Subscribe to settings changes to trigger redraw when opacity changes
            let settings = SettingsService.shared
            settings.$overlayOpacity
                .merge(with: settings.$forecastOverlayOpacity)
                .sink { [weak self] _ in
                    self?.radarRenderer?.setNeedsDisplay()
                }
                .store(in: &settingsCancellables)
            
            // Subscribe to map appearance changes
            settings.$mapAppearance
                .sink { [weak self] appearance in
                    self?.applyMapAppearance(appearance)
                }
                .store(in: &settingsCancellables)
        }
        
        func setMapView(_ mapView: MKMapView) {
            self.mapView = mapView
        }
        
        private func applyMapAppearance(_ appearance: Constants.MapAppearance) {
            guard let mapView = mapView else { return }
            switch appearance {
            case .light:
                mapView.overrideUserInterfaceStyle = .light
            case .dark:
                mapView.overrideUserInterfaceStyle = .dark
            case .auto:
                mapView.overrideUserInterfaceStyle = .unspecified
            }
        }
        
        deinit {
            // Clean up references to prevent retain cycles
            settingsCancellables.removeAll()
            radarRenderer = nil
            radarOverlay = nil
        }
        
        func updateRadarImage(radarImageManager: RadarImageManager, currentImage: UIImage?, timestamp: Date?) {
            // Check if current image is a forecast
            let isForecast = radarImageManager.radarSequence.currentImageData?.kind.isForecast ?? false
            
            // Simply update the image in the existing overlay
            radarOverlay?.updateImage(currentImage, timestamp: timestamp, isForecast: isForecast)
            radarRenderer?.onRenderCompleted = { renderedTimestamp in
                radarImageManager.overlayDidUpdate(imageTimestamp: renderedTimestamp)
            }
            // Trigger a redraw of the renderer
            radarRenderer?.setNeedsDisplay()
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Handle dimming overlay (areas outside radar coverage)
            if let dimmingOverlay = overlay as? DimmingOverlay {
                return DimmingOverlayRenderer(overlay: dimmingOverlay)
            }
            
            // Handle radar image overlay
            if let radarOverlay = overlay as? RadarImageOverlay {
                let renderer = RadarImageRenderer(overlay: radarOverlay)
                renderer.onRenderCompleted = { [weak self] renderedTimestamp in
                    self?.parent.radarImageManager.overlayDidUpdate(imageTimestamp: renderedTimestamp)
                }
                self.radarRenderer = renderer  // Keep a reference
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            MapStateService.shared.saveRegion(mapView.region)
        }
    }
}
