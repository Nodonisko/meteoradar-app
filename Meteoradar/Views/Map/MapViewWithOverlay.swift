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
    var userLocation: CLLocation?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false  // We'll handle user location manually
        mapView.userTrackingMode = .none
        mapView.setRegion(region, animated: false)
        
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
        
        // Create ONE radar overlay that we'll keep updating
        let radarOverlay = RadarImageOverlay.createCzechRadarOverlay(
            image: radarImageManager.radarSequence.currentImage,
            timestamp: radarImageManager.radarSequence.currentTimestamp
        )
        context.coordinator.radarOverlay = radarOverlay
        mapView.addOverlay(radarOverlay)
        
        // Create ONE user location annotation that we'll reuse forever
        context.coordinator.setupUserLocationAnnotation(on: mapView)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {        
        // Simply update the radar overlay's image - no removal/addition needed!
        context.coordinator.updateRadarImage(
            radarImageManager: radarImageManager,
            currentImage: radarImageManager.radarSequence.currentImage,
            timestamp: radarImageManager.radarSequence.currentTimestamp
        )
        
        // Update user location annotation coordinate
        context.coordinator.updateUserLocation(userLocation)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithOverlay
        var radarOverlay: RadarImageOverlay?
        var radarRenderer: RadarImageRenderer?
        var userLocationAnnotation: MKPointAnnotation?
        private var settingsCancellables = Set<AnyCancellable>()
        
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
        }
        
        deinit {
            // Clean up references to prevent retain cycles
            settingsCancellables.removeAll()
            radarRenderer = nil
            radarOverlay = nil
            userLocationAnnotation = nil
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
        
        func setupUserLocationAnnotation(on mapView: MKMapView) {
            // Create ONE annotation that we'll reuse forever
            let annotation = MKPointAnnotation()
            annotation.title = "Your Location"
            annotation.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0) // Will be updated when we have location
            mapView.addAnnotation(annotation)
            userLocationAnnotation = annotation
        }
        
        func updateUserLocation(_ location: CLLocation?) {
            guard let annotation = userLocationAnnotation else { return }
            
            if let location = location {
                // Just update coordinate - no removal/addition needed
                annotation.coordinate = location.coordinate
            }
            // Note: We don't hide the annotation when location is nil
            // It will just stay at the last known position
        }
        
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Custom view for our user location annotation
            if annotation === userLocationAnnotation {
                let identifier = "UserLocationView"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                    
                    // Create custom blue dot image
                    let dotSize: CGFloat = 20
                    annotationView?.image = createUserLocationDotImage(size: dotSize)
                } else {
                    annotationView?.annotation = annotation
                }
                
                return annotationView
            }
            
            return nil
        }
        
        // Create a perfect circular user location dot image
        private func createUserLocationDotImage(size: CGFloat) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            
            return renderer.image { context in
                let cgContext = context.cgContext
                let rect = CGRect(x: 0, y: 0, width: size, height: size)
                
                // Draw shadow
                cgContext.saveGState()
                cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
                
                // Draw white border circle
                cgContext.setFillColor(UIColor.white.cgColor)
                cgContext.fillEllipse(in: rect)
                
                cgContext.restoreGState()
                
                // Draw blue center circle
                let innerRect = CGRect(x: 3, y: 3, width: size - 6, height: size - 6)
                cgContext.setFillColor(UIColor.systemBlue.cgColor)
                cgContext.fillEllipse(in: innerRect)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            MapStateService.shared.saveRegion(mapView.region)
        }
    }
}
