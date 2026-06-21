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

final class MapCameraController: ObservableObject {
    private weak var mapView: MKMapView?

    func attach(_ mapView: MKMapView) {
        self.mapView = mapView
    }

    func detach(_ mapView: MKMapView) {
        guard self.mapView === mapView else { return }
        self.mapView = nil
    }

    func center(on location: CLLocation) {
        guard let mapView else { return }

        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: mapView.region.span
        )
        mapView.setRegion(region, animated: true)
    }
}

struct MapViewWithOverlay: UIViewRepresentable {
    let cameraController: MapCameraController
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
        mapView.setRegion(MapStateService.shared.loadRegion() ?? Constants.Radar.defaultRegion, animated: false)
        
        // Store reference for settings changes and apply initial map appearance
        context.coordinator.setMapView(mapView)
        cameraController.attach(mapView)
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
        
        // Add the dimming + radar overlays. Both position from the displayed
        // frame's GeoBox metadata once it loads; until then we use the product's
        // configured bounds so coverage shows immediately on launch.
        let product = RadarProductService.shared.selectedProduct
        let initialBounds = radarImageManager.radarSequence.currentGeoBox ?? product.bounds
        context.coordinator.applyBounds(initialBounds, recenterTo: nil)
        
        // Create ONE user location annotation that we'll reuse forever
        context.coordinator.setupUserLocationAnnotation(on: mapView)

        // Place tappable country-switch flag markers (every product except the
        // active one); tapping one switches the selected radar product.
        context.coordinator.syncCountryAnnotations(on: mapView, selectedID: product.id)

        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.6
        mapView.addGestureRecognizer(longPressGesture)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Resolve the displayed frame once. `currentGeoBox`, `currentImage` and
        // `currentTimestamp` each rebuild `loadedImages` independently, so reading
        // them from a single `currentImageData` avoids repeating that work several
        // times per update. This is local to this call - nothing is cached across
        // updates, so there's no staleness risk.
        let currentData = radarImageManager.radarSequence.currentImageData
        let currentImage = currentData?.image
        let currentTimestamp = currentData?.timestamp
        let currentGeoBox = currentData?.geoBox
        let isForecast = currentData?.kind.isForecast ?? false

        if let geoBox = currentGeoBox, geoBox != context.coordinator.appliedBounds {
            // The displayed frame's bounds changed (first frame after a switch, or
            // the backend re-projected mid-sequence). Reposition both overlays.
            // This is the rare path; in steady state bounds are identical frame-to-frame.
            context.coordinator.applyBounds(geoBox, recenterTo: nil)
        } else if context.coordinator.shouldUpdateRadar(
            currentImage: currentImage,
            timestamp: currentTimestamp
        ) {
            // Common path: bounds unchanged, just swap the overlay's image.
            context.coordinator.updateRadarImage(
                currentImage: currentImage,
                timestamp: currentTimestamp,
                isForecast: isForecast
            )
        }
        
        // Update user location annotation coordinate
        context.coordinator.updateUserLocation(userLocation)
        
        // Update heading on the user location annotation
        if let heading = userHeading, heading.headingAccuracy >= 0 {
            context.coordinator.updateUserHeading(heading)
        }

        // Map appearance is applied initially in makeUIView and reactively via the
        // $mapAppearance subscription, so it must NOT be re-applied on every update.

        // Keep custom markers in sync without recreating unchanged annotations
        context.coordinator.syncCustomMarkers(customMarkers, on: mapView)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.parent.cameraController.detach(uiView)
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
        var dimmingOverlay: DimmingOverlay?
        var radarRenderer: RadarImageRenderer?
        var userLocationAnnotation: MKPointAnnotation?
        /// Bounds currently applied to the live overlays. Used to detect when a
        /// frame's GeoBox differs and the overlays must be rebuilt.
        fileprivate var appliedBounds: GeoBounds?
        private var settingsCancellables = Set<AnyCancellable>()
        private weak var mapView: MKMapView?
        private weak var userLocationView: UserLocationAnnotationView?
        private var lastRenderedTimestamp: Date?
        private var lastRenderedImageID: ObjectIdentifier?
        private var customMarkerAnnotations: [UUID: CustomMapMarkerAnnotation] = [:]
        private var countryAnnotations: [String: CountrySwitchAnnotation] = [:]
        
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
            
            // Subscribe to radar product (country) changes. Recenter immediately
            // on the product's configured region (no waiting for the first image)
            // and rebuild overlays on those configured bounds. Once the new
            // product's frames load, their GeoBox metadata repositions the overlay.
            settings.$selectedRadarProductID
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] productID in
                    guard let self, let product = RadarProductService.shared.product(withID: productID) else { return }
                    self.applyBounds(product.bounds, recenterTo: product.region)
                    // Re-sync flag markers so the now-active country hides and the
                    // previously active one reappears. Use `productID` (the new
                    // value) — see syncCountryAnnotations for why SettingsService
                    // can't be re-read here.
                    if let mapView = self.mapView {
                        self.syncCountryAnnotations(on: mapView, selectedID: productID)
                    }
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
        
        /// Removes and re-adds the dimming + radar overlays for the given bounds and,
        /// optionally, recenters the camera. `MKOverlay.boundingMapRect` is immutable,
        /// so changing coverage means rebuilding both overlays. Called only when bounds
        /// actually change (product switch, or a frame whose GeoBox differs), keeping
        /// the per-frame fast path a cheap image swap.
        fileprivate func applyBounds(_ bounds: GeoBounds, recenterTo region: MKCoordinateRegion?) {
            guard let mapView = mapView else { return }
            
            // Carry over the current image only if it belongs to these bounds. On a
            // product switch we apply configured bounds while the old/empty sequence
            // doesn't match, so we start blank until the new product's frames arrive.
            let sequence = parent.radarImageManager.radarSequence
            let matchesBounds = sequence.currentGeoBox.map { $0 == bounds } ?? false
            let image = matchesBounds ? sequence.currentImage : nil
            let timestamp = matchesBounds ? sequence.currentTimestamp : nil
            let isForecast = matchesBounds ? (sequence.currentImageData?.kind.isForecast ?? false) : false
            
            if let oldDimming = dimmingOverlay {
                mapView.removeOverlay(oldDimming)
            }
            if let oldRadar = radarOverlay {
                mapView.removeOverlay(oldRadar)
            }
            radarRenderer = nil
            
            let newDimming = DimmingOverlay(bounds: bounds)
            dimmingOverlay = newDimming
            mapView.addOverlay(newDimming, level: .aboveLabels)
            
            let newRadar = RadarImageOverlay.create(bounds: bounds, image: image, timestamp: timestamp, isForecast: isForecast)
            radarOverlay = newRadar
            mapView.addOverlay(newRadar, level: .aboveLabels)
            
            appliedBounds = bounds
            // Record what the freshly built overlay already shows so updateUIView's
            // shouldUpdateRadar doesn't redundantly re-swap the same image.
            lastRenderedTimestamp = timestamp
            lastRenderedImageID = image.map { ObjectIdentifier($0) }
            
            if let region = region {
                mapView.setRegion(region, animated: true)
            }
        }
        
        func updateRadarImage(currentImage: UIImage?, timestamp: Date?, isForecast: Bool) {
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

        /// Adds a tappable circular flag marker for every product except the
        /// active one, and removes the marker for `selectedID`. Idempotent:
        /// reuses existing annotations so repeated calls (launch + each product
        /// switch) don't churn the map.
        ///
        /// Products without a configured `center` get no marker (they stay
        /// reachable through the picker menu only).
        ///
        /// `selectedID` is passed in rather than read from `SettingsService`
        /// because `@Published` emits in `willSet`: inside the product-change
        /// subscription the stored value is still the *previous* product, so
        /// re-reading it here would leave the now-active country's flag on screen.
        func syncCountryAnnotations(on mapView: MKMapView, selectedID: String) {
            let products = RadarProductService.shared.products
            let switchFormat = String(localized: "map.switch_country")

            // Only products that both aren't the active one and have a map anchor.
            let desiredIDs = Set(products.filter { $0.center != nil }.map { $0.id })
                .subtracting([selectedID])

            for (id, annotation) in countryAnnotations where !desiredIDs.contains(id) {
                mapView.removeAnnotation(annotation)
                countryAnnotations[id] = nil
            }

            for product in products where desiredIDs.contains(product.id) && countryAnnotations[product.id] == nil {
                guard let center = product.center else { continue }
                let annotation = CountrySwitchAnnotation(
                    productID: product.id,
                    flag: product.flagEmoji,
                    accessibilityText: String(format: switchFormat, product.pickerTitle),
                    coordinate: center
                )
                countryAnnotations[product.id] = annotation
                mapView.addAnnotation(annotation)
            }
        }

        @objc func handleMapLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = mapView else { return }
            let point = gesture.location(in: mapView)

            if customMarkerID(at: point, on: mapView) != nil {
                return
            }

            // Don't drop a pin when long-pressing on top of a country flag marker.
            if isCountryMarker(at: point, on: mapView) {
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

        private func isCountryMarker(at point: CGPoint, on mapView: MKMapView) -> Bool {
            var touchedView: UIView? = mapView.hitTest(point, with: nil)
            while let currentView = touchedView {
                if let annotationView = currentView as? MKAnnotationView,
                   annotationView.annotation is CountrySwitchAnnotation {
                    return true
                }
                touchedView = currentView.superview
            }
            return false
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

            if let countryAnnotation = annotation as? CountrySwitchAnnotation {
                let identifier = "CountrySwitchFlag"
                let annotationView: CountrySwitchAnnotationView
                if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? CountrySwitchAnnotationView {
                    annotationView = dequeued
                    annotationView.annotation = countryAnnotation
                } else {
                    annotationView = CountrySwitchAnnotationView(annotation: countryAnnotation, reuseIdentifier: identifier)
                }

                annotationView.update(flag: countryAnnotation.flag)
                // Keep country switchers above map labels and other optional map content.
                annotationView.displayPriority = .required
                //annotationView.zPriority = .max
                annotationView.accessibilityLabel = countryAnnotation.accessibilityText
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
            if let countryAnnotation = view.annotation as? CountrySwitchAnnotation {
                mapView.deselectAnnotation(countryAnnotation, animated: false)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Drives the product-change subscription, which recenters the map,
                // rebuilds the overlays, and re-syncs the flag markers.
                SettingsService.shared.selectedRadarProductID = countryAnnotation.productID
                return
            }

            guard let customAnnotation = view.annotation as? CustomMapMarkerAnnotation else { return }
            parent.onCustomMarkerTap(customAnnotation.markerID)
            mapView.deselectAnnotation(customAnnotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
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

private final class CountrySwitchAnnotation: NSObject, MKAnnotation {
    let productID: String
    let flag: String
    let accessibilityText: String
    let coordinate: CLLocationCoordinate2D

    init(productID: String, flag: String, accessibilityText: String, coordinate: CLLocationCoordinate2D) {
        self.productID = productID
        self.flag = flag
        self.accessibilityText = accessibilityText
        self.coordinate = coordinate
        super.init()
    }
}

/// A circular flag badge used to switch to another country's radar by tapping.
/// The flag emoji is aspect-filled into a circle with a thin white ring so it
/// reads as a country "coin" rather than the raw rectangular emoji.
private final class CountrySwitchAnnotationView: MKAnnotationView {
    /// Keep the full size on iPad; shrink by 1/3 on iPhone where screen space is tighter.
    private static let diameter: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 36 : 24

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let size = Self.diameter
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        canShowCallout = false

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(flag: String) {
        image = Self.circularFlagImage(flag: flag, diameter: Self.diameter)
    }

    private static func circularFlagImage(flag: String, diameter: CGFloat) -> UIImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 80)]
        let emoji = NSAttributedString(string: flag, attributes: attributes)
        let emojiSize = emoji.size()
        guard emojiSize.width > 0, emojiSize.height > 0 else { return UIImage() }

        let emojiImage = UIGraphicsImageRenderer(size: emojiSize).image { _ in
            emoji.draw(at: .zero)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            let border = diameter * 0.08
            let clip = UIBezierPath(ovalIn: rect)
            clip.addClip()

            UIColor.systemGray5.setFill()
            clip.fill()

            // Aspect-fill so the flag covers the whole circle, then center it.
            let scale = max(diameter / emojiSize.width, diameter / emojiSize.height)
            let drawSize = CGSize(width: emojiSize.width * scale, height: emojiSize.height * scale)
            let origin = CGPoint(x: (diameter - drawSize.width) / 2, y: (diameter - drawSize.height) / 2)
            emojiImage.draw(in: CGRect(origin: origin, size: drawSize))

            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: border / 2, dy: border / 2))
            ring.lineWidth = border
            ring.stroke()
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
