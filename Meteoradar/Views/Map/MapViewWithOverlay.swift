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
    var userHeading: CLHeading?
    var customMarkers: [CustomMapMarker]
    var onMapLongPress: (CLLocationCoordinate2D) -> Void
    var onCustomMarkerTap: (UUID) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false  // We'll handle user location manually
        mapView.userTrackingMode = .none
        mapView.isRotateEnabled = false
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
        mapView.addOverlay(dimmingOverlay, level: .aboveLabels)
        
        // Create ONE radar overlay that we'll keep updating
        let radarOverlay = RadarImageOverlay.createCzechRadarOverlay(
            image: radarImageManager.radarSequence.currentImage,
            timestamp: radarImageManager.radarSequence.currentTimestamp
        )
        context.coordinator.radarOverlay = radarOverlay
        mapView.addOverlay(radarOverlay, level: .aboveLabels)
        
        // Create ONE user location annotation that we'll reuse forever
        context.coordinator.setupUserLocationAnnotation(on: mapView)

        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.6
        mapView.addGestureRecognizer(longPressGesture)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {        
        if context.coordinator.shouldUpdateRadar(
            currentImage: radarImageManager.radarSequence.currentImage,
            timestamp: radarImageManager.radarSequence.currentTimestamp
        ) {
            // Simply update the radar overlay's image - no removal/addition needed!
            context.coordinator.updateRadarImage(
                radarImageManager: radarImageManager,
                currentImage: radarImageManager.radarSequence.currentImage,
                timestamp: radarImageManager.radarSequence.currentTimestamp
            )
        }
        
        // Update user location annotation coordinate
        context.coordinator.updateUserLocation(userLocation)
        
        // Update heading on the user location annotation
        if let heading = userHeading, heading.headingAccuracy >= 0 {
            context.coordinator.updateUserHeading(heading)
        }
        
        // Update map appearance when setting changes
        applyMapAppearance(to: mapView)

        // Keep custom markers in sync without recreating unchanged annotations
        context.coordinator.syncCustomMarkers(customMarkers, on: mapView)
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
        var userLocationAnnotation: MKPointAnnotation?
        private var settingsCancellables = Set<AnyCancellable>()
        private weak var mapView: MKMapView?
        private weak var userLocationView: UserLocationAnnotationView?
        private var lastRenderedTimestamp: Date?
        private var lastRenderedImageID: ObjectIdentifier?
        private var customMarkerAnnotations: [UUID: CustomMapMarkerAnnotation] = [:]
        
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
            userLocationAnnotation = nil
        }
        
        func updateRadarImage(radarImageManager: RadarImageManager, currentImage: UIImage?, timestamp: Date?) {
            // Check if current image is a forecast
            let isForecast = radarImageManager.radarSequence.currentImageData?.kind.isForecast ?? false
            
            // Simply update the image in the existing overlay
            radarOverlay?.updateImage(currentImage, timestamp: timestamp, isForecast: isForecast)
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
        
        func updateUserHeading(_ heading: CLHeading) {
            // Use trueHeading if available (requires location), otherwise magneticHeading
            let headingValue = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            userLocationView?.updateHeading(headingValue)
        }

        func syncCustomMarkers(_ markers: [CustomMapMarker], on mapView: MKMapView) {
            let incomingById = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
            let existingIds = Set(customMarkerAnnotations.keys)
            let incomingIds = Set(incomingById.keys)

            let idsToRemove = existingIds.subtracting(incomingIds)
            for id in idsToRemove {
                if let annotation = customMarkerAnnotations[id] {
                    mapView.removeAnnotation(annotation)
                    customMarkerAnnotations[id] = nil
                }
            }

            for marker in markers {
                if let existingAnnotation = customMarkerAnnotations[marker.id] {
                    existingAnnotation.update(from: marker)
                    if let existingView = mapView.view(for: existingAnnotation) as? CustomMarkerDotAnnotationView {
                        existingView.update(color: UIColor(hex: marker.colorHex), glyph: marker.glyph)
                    }
                } else {
                    let annotation = CustomMapMarkerAnnotation(marker: marker)
                    customMarkerAnnotations[marker.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        @objc func handleMapLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = mapView else { return }
            let point = gesture.location(in: mapView)

            if customMarkerID(at: point, on: mapView) != nil {
                return
            }

            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onMapLongPress(coordinate)
        }

        private func customMarkerID(at point: CGPoint, on mapView: MKMapView) -> UUID? {
            var touchedView: UIView? = mapView.hitTest(point, with: nil)
            while let currentView = touchedView {
                if let annotationView = currentView as? MKAnnotationView,
                   let annotation = annotationView.annotation as? CustomMapMarkerAnnotation {
                    return annotation.markerID
                }
                touchedView = currentView.superview
            }

            // Fallback: pick the nearest marker if the touch is close enough.
            let selectionRadius: CGFloat = 28
            var nearest: (id: UUID, distance: CGFloat)?
            for (id, annotation) in customMarkerAnnotations {
                let markerPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                let distance = hypot(markerPoint.x - point.x, markerPoint.y - point.y)
                if distance <= selectionRadius {
                    if let currentNearest = nearest {
                        if distance < currentNearest.distance {
                            nearest = (id, distance)
                        }
                    } else {
                        nearest = (id, distance)
                    }
                }
            }
            return nearest?.id
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Handle dimming overlay (areas outside radar coverage)
            if let dimmingOverlay = overlay as? DimmingOverlay {
                return DimmingOverlayRenderer(overlay: dimmingOverlay)
            }
            
            // Handle radar image overlay
            if let radarOverlay = overlay as? RadarImageOverlay {
                let renderer = RadarImageRenderer(overlay: radarOverlay)
                self.radarRenderer = renderer  // Keep a reference
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Custom view for our user location annotation with heading beam
            if annotation === userLocationAnnotation {
                let identifier = "UserLocationWithHeading"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? UserLocationAnnotationView
                
                if annotationView == nil {
                    annotationView = UserLocationAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                } else {
                    annotationView?.annotation = annotation
                }
                
                // Store reference for heading updates
                userLocationView = annotationView
                
                // Apply current heading if available
                if let heading = parent.userHeading, heading.headingAccuracy >= 0 {
                    let headingValue = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
                    annotationView?.updateHeading(headingValue)
                }
                
                return annotationView
            }

            if let customAnnotation = annotation as? CustomMapMarkerAnnotation {
                let identifier = "CustomMarkerDot"
                let annotationView: CustomMarkerDotAnnotationView
                if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? CustomMarkerDotAnnotationView {
                    annotationView = dequeued
                    annotationView.annotation = customAnnotation
                } else {
                    annotationView = CustomMarkerDotAnnotationView(annotation: customAnnotation, reuseIdentifier: identifier)
                }

                annotationView.update(color: UIColor(hex: customAnnotation.marker.colorHex), glyph: customAnnotation.marker.glyph)
                annotationView.displayPriority = .required

                return annotationView
            }
            
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let customAnnotation = view.annotation as? CustomMapMarkerAnnotation else { return }
            parent.onCustomMarkerTap(customAnnotation.markerID)
            mapView.deselectAnnotation(customAnnotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            MapStateService.shared.saveRegion(mapView.region)
        }

        func shouldUpdateRadar(currentImage: UIImage?, timestamp: Date?) -> Bool {
            let currentImageID = currentImage.map { ObjectIdentifier($0) }
            if lastRenderedTimestamp == timestamp && lastRenderedImageID == currentImageID {
                return false
            }
            lastRenderedTimestamp = timestamp
            lastRenderedImageID = currentImageID
            return true
        }
    }
}

private final class CustomMapMarkerAnnotation: NSObject, MKAnnotation {
    let markerID: UUID
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    private(set) var marker: CustomMapMarker

    init(marker: CustomMapMarker) {
        self.markerID = marker.id
        self.marker = marker
        self.coordinate = marker.coordinate
        self.title = marker.name
        self.subtitle = nil
        super.init()
    }

    func update(from marker: CustomMapMarker) {
        self.marker = marker
        coordinate = marker.coordinate
        title = marker.name
    }
}

private final class CustomMarkerDotAnnotationView: MKAnnotationView {
    /// Single value that controls overall marker size. All proportions derive from this.
    private static let markerSize: CGFloat = 22

    private let backgroundCircle = CALayer()
    private let glyphImageView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        let size = Self.markerSize
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        canShowCallout = false

        backgroundCircle.frame = bounds
        backgroundCircle.cornerRadius = size / 2
        backgroundCircle.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        backgroundCircle.borderWidth = size * 0.08
        layer.addSublayer(backgroundCircle)

        let glyphInset = size * 0.19
        glyphImageView.frame = bounds.insetBy(dx: glyphInset, dy: glyphInset)
        glyphImageView.contentMode = .scaleAspectFit
        glyphImageView.tintColor = .white
        addSubview(glyphImageView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(color: UIColor, glyph: String) {
        let size = Self.markerSize

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundCircle.backgroundColor = color.withAlphaComponent(0.7).cgColor
        CATransaction.commit()

        let symbolPointSize = size * 0.42
        let config = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        if let sfImage = UIImage(systemName: glyph, withConfiguration: config) {
            glyphImageView.image = sfImage
        } else if !glyph.isEmpty {
            let glyphInset = size * 0.19
            glyphImageView.image = glyph.prefix(2).textImage(size: bounds.insetBy(dx: glyphInset, dy: glyphInset).size)
        } else {
            glyphImageView.image = nil
        }
    }
}

private extension StringProtocol {
    func textImage(size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let text = String(self)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.height * 0.7, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let origin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )
            text.draw(at: origin, withAttributes: attributes)
        }
    }
}
