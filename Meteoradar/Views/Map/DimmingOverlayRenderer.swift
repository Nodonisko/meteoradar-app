//
//  DimmingOverlayRenderer.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 10.01.2026.
//

import MapKit
import UIKit

/// Renderer that draws a semi-transparent dark overlay outside the radar coverage area.
/// This helps users visually distinguish between areas with radar coverage and areas without.
class DimmingOverlayRenderer: MKOverlayRenderer {
    private let dimmingOverlay: DimmingOverlay
    
    /// The color used to dim areas outside radar coverage
    private let dimmingColor = UIColor.black.withAlphaComponent(0.15)
    
    init(overlay: DimmingOverlay) {
        self.dimmingOverlay = overlay
        super.init(overlay: overlay)
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // Get the full rect we're drawing in (the large bounding area)
        let fullRect = rect(for: overlay.boundingMapRect)
        
        // Get the radar coverage rect (the area to keep clear/not dimmed)
        let radarRect = rect(for: dimmingOverlay.radarCoverageRect)
        
        context.saveGState()
        
        // Create a path that covers the entire drawing area
        let fullPath = CGMutablePath()
        fullPath.addRect(fullRect)
        
        // Add the radar coverage area as a hole (using even-odd fill rule)
        fullPath.addRect(radarRect)
        
        // Set the fill color
        context.setFillColor(dimmingColor.cgColor)
        
        // Use even-odd fill rule to create the "donut" effect
        // This fills the outer rect but leaves the inner rect transparent
        context.addPath(fullPath)
        context.fillPath(using: .evenOdd)
        
        context.restoreGState()
    }
}

