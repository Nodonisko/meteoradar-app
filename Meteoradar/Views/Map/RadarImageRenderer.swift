//
//  RadarImageRenderer.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import MapKit
import UIKit

class RadarImageRenderer: MKOverlayRenderer {
    let radarOverlay: RadarImageOverlay
    var onRenderCompleted: ((Date?) -> Void)?
    
    init(overlay: RadarImageOverlay) {
        self.radarOverlay = overlay
        super.init(overlay: overlay)
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let image = radarOverlay.image else { return }
        
        let rect = self.rect(for: radarOverlay.boundingMapRect)
        
        // Save the current graphics state
        context.saveGState()
        
        // Fix coordinate system mismatch between Core Graphics and MapKit
        // Core Graphics origin is bottom-left, MapKit is top-left
        context.translateBy(x: 0, y: rect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Set interpolation to nearest neighbor for sharp radar boundaries
        context.interpolationQuality = .medium
        
        // Disable antialiasing for crisp pixel boundaries
        context.setShouldAntialias(false)
        
        // Optional: Set additional rendering options for better performance
        context.setAllowsAntialiasing(false)
        
        // Set blend mode for transparency
        // Use different alpha for forecast vs observed images
        context.setBlendMode(.normal)
        let settings = SettingsService.shared
        let alpha = radarOverlay.isForecast ? settings.forecastOverlayOpacity : settings.overlayOpacity
        context.setAlpha(alpha)
        
        // Draw the image
        context.draw(image.cgImage!, in: rect)
        
        // Restore graphics state
        context.restoreGState()
        
        // Draw hairline border around radar coverage area
        context.saveGState()
        let borderWidth: CGFloat = 0.5 / zoomScale  // Scale-independent hairline border
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(borderWidth)
        context.stroke(rect)
        context.restoreGState()

        if let callback = onRenderCompleted {
            DispatchQueue.main.async {
                callback(self.radarOverlay.timestamp)
            }
        }
    }
}
