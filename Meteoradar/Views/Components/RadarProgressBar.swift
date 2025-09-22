//
//  RadarProgressBar.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 15.09.2025.
//

import SwiftUI

// MARK: - RadarProgressBar Layout Constants
extension RadarProgressBar {
    enum Constants {
        static let boxHeight: CGFloat = 32
        static let topPadding: CGFloat = 12
        static let bottomPadding: CGFloat = 36
        static let horizontalPadding: CGFloat = 20
        static let boxSpacing: CGFloat = 8
        
        // Shadow properties
        static let shadowRadius: CGFloat = 6
        static let shadowOffsetY: CGFloat = -2
        static let shadowColor = Color.black.opacity(0.4)
        
        // Computed properties for common calculations
        static var totalHeight: CGFloat {
            topPadding + boxHeight + bottomPadding
        }
        
        // Height from bottom of screen to top of visible boxes (including shadow effect)
        static var visibleContentHeight: CGFloat {
            topPadding + boxHeight + abs(shadowOffsetY)
        }
        
        static func controlsBottomPadding(gapAboveProgressBar: CGFloat) -> CGFloat {
            visibleContentHeight + gapAboveProgressBar
        }
    }
}

struct RadarProgressBar: View {
    @ObservedObject var radarSequence: RadarImageSequence
    let radarImageManager: RadarImageManager
    
    
    // Create stable snapshot to avoid race conditions (cached)
    private var stableImages: [(id: String, data: RadarImageData)] {
        radarSequence.images
            .sorted { $0.timestamp < $1.timestamp }
            .map { (id: $0.timestamp.radarTimestampString, data: $0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(stableImages, id: \.id) { item in
                    ProgressBarBox(
                        imageData: item.data,
                        radarSequence: radarSequence,
                        radarImageManager: radarImageManager
                    )
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(at: value.location)
                    }
            )
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.top, Constants.topPadding)
            .padding(.bottom, Constants.bottomPadding)
            
            // Extra spacing that extends to safe area
            GeometryReader { geometry in
                Color.clear
                    .frame(height: geometry.safeAreaInsets.bottom)
            }
            .frame(height: 0)
        }
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.8))
        )
        .shadow(color: Constants.shadowColor, radius: Constants.shadowRadius, x: 0, y: Constants.shadowOffsetY)
    }
    
    
    
    private func handleDrag(at location: CGPoint) {
        // Calculate which box is under the finger
        let totalBoxes = stableImages.count
        guard totalBoxes > 0 else { return }
        
        // Get the HStack width (total width minus horizontal padding)
        let hStackPadding: CGFloat = Constants.horizontalPadding * 2 // padding on each side
        let boxSpacing: CGFloat = Constants.boxSpacing
        let totalSpacing = CGFloat(totalBoxes - 1) * boxSpacing
        
        // Calculate available width for boxes
        let estimatedContainerWidth: CGFloat = UIScreen.main.bounds.width
        let availableWidth = estimatedContainerWidth - hStackPadding
        let boxWidth = (availableWidth - totalSpacing) / CGFloat(totalBoxes)
        
        // Calculate which box index based on x position
        let adjustedX = location.x + (boxWidth / 2) // Adjust for box center
        let boxIndex = Int(adjustedX / (boxWidth + boxSpacing))
        
        // Ensure index is within bounds
        let clampedIndex = max(0, min(boxIndex, totalBoxes - 1))
        
        // Early return if box is not enabled
        guard clampedIndex < stableImages.count else { return }
        let imageData = stableImages[clampedIndex].data
        guard imageData.state == .success else { return }
        
        // Early return if this image is already the current one (using existing state!)
        if let currentTimestamp = radarSequence.currentTimestamp,
           Calendar.current.isDate(imageData.timestamp, equalTo: currentTimestamp, toGranularity: .minute) {
            return // Already selected - no work needed
        }
        
        print("Drag selecting new box \(clampedIndex): \(imageData.timestamp.radarTimestampString)")
        
        // Perform the selection
        selectImage(imageData)
    }
    
    
    private func selectImage(_ imageData: RadarImageData) {
        // Stop animation if running (only once)
        if radarSequence.isAnimating {
            radarImageManager.stopAnimation()
        }
        
        // Find and select the image efficiently
        let loadedImages = radarSequence.loadedImages
        if let index = loadedImages.firstIndex(where: { loadedImage in
            Calendar.current.isDate(loadedImage.timestamp, equalTo: imageData.timestamp, toGranularity: .minute)
        }) {
            radarSequence.currentImageIndex = index
        }
    }
}

// Separate component for each progress bar box to avoid race conditions
struct ProgressBarBox: View {
    let imageData: RadarImageData
    @ObservedObject var radarSequence: RadarImageSequence
    let radarImageManager: RadarImageManager
    
    // Capture state at render time to avoid mid-render changes
    private var isCurrentFrame: Bool {
        guard let currentTimestamp = radarSequence.currentTimestamp else { return false }
        return Calendar.current.isDate(imageData.timestamp, equalTo: currentTimestamp, toGranularity: .minute)
    }
    
    private var isEnabled: Bool {
        imageData.state == .success
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isCurrentFrame ? borderColor : Color.clear)
            .frame(height: RadarProgressBar.Constants.boxHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(borderColor, lineWidth: 1.0)
            )
            .opacity(opacity)
            .scaleEffect(isCurrentFrame ? 1.1 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture {
                if isEnabled {
                    print("Tap gesture triggered for: \(imageData.timestamp.radarTimestampString)")
                    handleSelection()
                } else {
                    print("Tap ignored - button not enabled")
                }
            }
    }
    
    private var borderColor: Color {
        switch imageData.state {
        case .success: return .blue
        case .loading, .retrying: return .yellow
        case .failed: return .red
        case .pending: return .gray
        case .skipped: return .gray.opacity(0.6)
        }
    }
    
    private var opacity: Double {
        switch imageData.state {
        case .success: return 1.0
        case .loading, .retrying: return 0.8
        case .failed: return 0.7
        case .pending: return 0.4
        case .skipped: return 0.3
        }
    }
    
    private func handleSelection() {
        guard isEnabled else { 
            print("Button disabled, ignoring selection")
            return 
        }
        
        print("Handling selection for timestamp: \(imageData.timestamp.radarTimestampString)")
        
        // Stop animation if running
        if radarSequence.isAnimating {
            print("Stopping animation")
            radarImageManager.stopAnimation()
        }
        
        // Find the image in loadedImages and set it as current
        let loadedImages = radarSequence.loadedImages
        for (index, loadedImage) in loadedImages.enumerated() {
            if Calendar.current.isDate(loadedImage.timestamp, equalTo: imageData.timestamp, toGranularity: .minute) {
                print("Found matching image at loadedImages index: \(index)")
                radarSequence.currentImageIndex = index
                return
            }
        }
        
        print("ERROR: Could not find selected image in loadedImages array")
    }
}

// Custom button style for progress bar boxes
struct ProgressBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    // Create a sample radar sequence for preview
    let sequence = RadarImageSequence()
    let manager = RadarImageManager()
    manager.radarSequence = sequence
    
    // Add some sample images to show the progress bar
    let sampleTimestamps = Date.radarTimestamps(count: 12)
    sequence.createPlaceholders(for: sampleTimestamps)
    
    // Set up different loading states for preview
    if sequence.images.count >= 8 {
        sequence.images[0].state = .success
        sequence.images[0].image = UIImage()
        
        sequence.images[1].state = .success
        sequence.images[1].image = UIImage()
        
        sequence.images[2].state = .loading
        
        sequence.images[3].state = .success
        sequence.images[3].image = UIImage()
        
        sequence.images[4].state = .failed(NSError(domain: "test", code: 404), attemptCount: 1)
        
        sequence.images[5].state = .retrying(attemptCount: 1)
        
        sequence.images[6].state = .success
        sequence.images[6].image = UIImage()
        
        sequence.images[7].state = .pending
    }
    
    return VStack(spacing: 20) {
        Text("Interactive Progress Bar Preview")
            .foregroundColor(.white)
        
        Text("Tap on blue boxes to jump to that frame")
            .foregroundColor(.gray)
            .font(.caption)
        
        RadarProgressBar(radarSequence: sequence, radarImageManager: manager)
        
        // Legend
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Rectangle().fill(Color.blue).frame(width: 12, height: 6).border(Color.blue)
                Text("Loaded (Tappable)").foregroundColor(.white).font(.caption)
            }
            HStack {
                Rectangle().fill(Color.clear).frame(width: 12, height: 6).border(Color.yellow)
                Text("Loading").foregroundColor(.white).font(.caption)
            }
            HStack {
                Rectangle().fill(Color.clear).frame(width: 12, height: 6).border(Color.red)
                Text("Failed").foregroundColor(.white).font(.caption)
            }
            HStack {
                Rectangle().fill(Color.clear).frame(width: 12, height: 6).border(Color.gray).opacity(0.4)
                Text("Pending").foregroundColor(.white).font(.caption)
            }
        }
    }
    .padding()
    .background(Color.black)
}
