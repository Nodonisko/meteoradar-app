//
//  UserLocationAnnotationView.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 11.01.2026.
//

import MapKit
import UIKit

/// Custom annotation view for user location that displays a heading indicator cone
/// Similar to Apple Maps heading beam but works without followWithHeading mode
class UserLocationAnnotationView: MKAnnotationView {
    
    // MARK: - Properties
    
    private let dotSize: CGFloat = 22
    private let coneLength: CGFloat = 60
    private let coneAngle: CGFloat = 50 // degrees
    
    private var dotView: UIView!
    private var dotInnerView: UIView!
    private var headingConeLayer: CAShapeLayer!
    private var headingGradientLayer: CAGradientLayer!
    
    private var currentHeading: CLLocationDirection = 0
    
    // MARK: - Initialization
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        // Make the annotation view larger to accommodate the cone
        let viewSize = coneLength * 2 + dotSize
        frame = CGRect(x: 0, y: 0, width: viewSize, height: viewSize)
        centerOffset = CGPoint.zero
        
        // Create gradient layer for heading cone
        headingGradientLayer = CAGradientLayer()
        headingGradientLayer.frame = bounds
        headingGradientLayer.type = .radial
        headingGradientLayer.colors = [
            UIColor.systemBlue.withAlphaComponent(0.5).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.2).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.0).cgColor
        ]
        headingGradientLayer.locations = [0.0, 0.5, 1.0]
        headingGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        headingGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer.addSublayer(headingGradientLayer)
        
        // Create shape layer as mask for the gradient
        headingConeLayer = CAShapeLayer()
        headingConeLayer.frame = bounds
        headingGradientLayer.mask = headingConeLayer
        
        // Initially hide the cone until we have heading data
        headingGradientLayer.isHidden = true
        
        // Create the blue dot (outer ring)
        dotView = UIView(frame: CGRect(x: 0, y: 0, width: dotSize, height: dotSize))
        dotView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        dotView.backgroundColor = .white
        dotView.layer.cornerRadius = dotSize / 2
        dotView.layer.shadowColor = UIColor.black.cgColor
        dotView.layer.shadowOffset = CGSize(width: 0, height: 1)
        dotView.layer.shadowOpacity = 0.3
        dotView.layer.shadowRadius = 2
        addSubview(dotView)
        
        // Create inner blue circle
        let innerSize = dotSize - 6
        dotInnerView = UIView(frame: CGRect(x: 0, y: 0, width: innerSize, height: innerSize))
        dotInnerView.center = CGPoint(x: dotSize / 2, y: dotSize / 2)
        dotInnerView.backgroundColor = .systemBlue
        dotInnerView.layer.cornerRadius = innerSize / 2
        dotView.addSubview(dotInnerView)
    }
    
    // MARK: - Heading Update
    
    func updateHeading(_ heading: CLLocationDirection) {
        currentHeading = heading
        
        // Show the cone
        headingGradientLayer.isHidden = false
        
        // Update the cone path
        updateConePath()
    }
    
    private func updateConePath() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        // Convert heading to radians (heading is clockwise from north, we need to adjust for Core Graphics)
        // In CG, 0 degrees points to the right, and angles go counter-clockwise
        // Heading: 0 = North (up), 90 = East (right), 180 = South (down), 270 = West (left)
        let headingRadians = (currentHeading - 90) * .pi / 180
        let halfAngleRadians = coneAngle / 2 * .pi / 180
        
        let path = UIBezierPath()
        path.move(to: center)
        
        // Calculate left edge of cone
        let leftAngle = headingRadians - halfAngleRadians
        let leftPoint = CGPoint(
            x: center.x + coneLength * CGFloat(cos(leftAngle)),
            y: center.y + coneLength * CGFloat(sin(leftAngle))
        )
        path.addLine(to: leftPoint)
        
        // Add arc at the end of cone
        path.addArc(
            withCenter: center,
            radius: coneLength,
            startAngle: CGFloat(leftAngle),
            endAngle: CGFloat(headingRadians + halfAngleRadians),
            clockwise: true
        )
        
        // Close back to center
        path.addLine(to: center)
        path.close()
        
        // Animate the path change for smooth rotation
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        headingConeLayer.path = path.cgPath
        CATransaction.commit()
    }
    
    // MARK: - Accuracy Circle (optional enhancement)
    
    func updateAccuracy(_ accuracy: CLLocationAccuracy, mapView: MKMapView) {
        // Could add accuracy circle here if needed
    }
}
