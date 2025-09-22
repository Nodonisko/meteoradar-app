//
//  MapViewWithOverlay.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import SwiftUI
import MapKit
import UIKit

struct MapViewWithOverlay: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @ObservedObject var radarImageManager: RadarImageManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.setRegion(region, animated: false)
        
        // Create ONE radar overlay that we'll keep updating
        let radarOverlay = RadarImageOverlay.createCzechRadarOverlay(image: radarImageManager.radarSequence.currentImage)
        context.coordinator.radarOverlay = radarOverlay
        mapView.addOverlay(radarOverlay)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {        
        // Simply update the radar overlay's image - no removal/addition needed!
        context.coordinator.updateRadarImage(radarImageManager.radarSequence.currentImage)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithOverlay
        var radarOverlay: RadarImageOverlay?
        var radarRenderer: RadarImageRenderer?
        
        init(_ parent: MapViewWithOverlay) {
            self.parent = parent
        }
        
        deinit {
            // Clean up references to prevent retain cycles
            radarRenderer = nil
            radarOverlay = nil
        }
        
        func updateRadarImage(_ newImage: UIImage?) {
            // Simply update the image in the existing overlay
            radarOverlay?.updateImage(newImage)
            // Trigger a redraw of the renderer
            radarRenderer?.setNeedsDisplay()
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let radarOverlay = overlay as? RadarImageOverlay {
                let renderer = RadarImageRenderer(overlay: radarOverlay)
                self.radarRenderer = renderer  // Keep a reference
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }
    }
}
