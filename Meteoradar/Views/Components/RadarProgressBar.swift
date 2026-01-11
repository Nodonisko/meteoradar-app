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
        
        // iPad-specific layout
        static let maxWidth: CGFloat = 450  // approximately 1/3 of screen
        static let iPadBottomPadding: CGFloat = 24
        static let iPadInternalBottomPadding: CGFloat = 12  // smaller internal padding on iPad
        
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
    @ObservedObject var radarImageManager: RadarImageManager
    
    @State private var toastMessage: String?
    @State private var showToast = false
    
    // Create stable snapshot to avoid race conditions (cached)
    private var stableImages: [(id: String, data: RadarImageData)] {
        radarSequence.images
            .sorted { $0.timestamp < $1.timestamp }
            .map { (id: $0.cacheKey, data: $0) }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    HStack(spacing: 8) {
                        ForEach(stableImages, id: \.id) { item in
                            ProgressBarBox(
                                imageData: item.data,
                                radarSequence: radarSequence,
                                radarImageManager: radarImageManager,
                                onErrorTap: { errorMessage in
                                    showErrorToast(errorMessage)
                                }
                            )
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDrag(at: value.location, containerWidth: geometry.size.width)
                            }
                    )
                }
                .frame(height: Constants.boxHeight)
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.top, Constants.topPadding)
                .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? Constants.iPadInternalBottomPadding : Constants.bottomPadding)
                
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
                    .cornerRadius(16)
            )
            .shadow(color: Constants.shadowColor, radius: Constants.shadowRadius, x: 0, y: Constants.shadowOffsetY)
            
        }
        .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? Constants.maxWidth : .infinity)
        .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? Constants.iPadBottomPadding : 0)
        .overlay(alignment: .top) {
            // Toast overlay - positioned above the progress bar
            if showToast, let message = toastMessage {
                ErrorToastView(message: message)
                    .offset(y: -70)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .animation(.easeInOut(duration: 0.25), value: showToast)
            }
        }
    }
    
    private func showErrorToast(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        
        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation {
                showToast = false
            }
        }
    }
    
    
    
    private func handleDrag(at location: CGPoint, containerWidth: CGFloat) {
        // Calculate which box is under the finger
        let totalBoxes = stableImages.count
        guard totalBoxes > 0 else { return }
        
        let boxSpacing: CGFloat = Constants.boxSpacing
        let totalSpacing = CGFloat(totalBoxes - 1) * boxSpacing
        
        // Use actual container width from GeometryReader
        let boxWidth = (containerWidth - totalSpacing) / CGFloat(totalBoxes)
        
        // Calculate which box index based on x position
        // Each box occupies (boxWidth + boxSpacing) except the last one
        let boxIndex = Int(location.x / (boxWidth + boxSpacing))
        
        // Ensure index is within bounds
        let clampedIndex = max(0, min(boxIndex, totalBoxes - 1))
        
        // Early return if box is not enabled
        guard clampedIndex < stableImages.count else { return }
        let imageData = stableImages[clampedIndex].data
        guard imageData.state == .success else { return }
        
        // Early return if this image is already the current one (using existing state!)
        if let displayedTimestamp = radarImageManager.displayedTimestamp,
           Calendar.current.isDate(imageData.timestamp, equalTo: displayedTimestamp, toGranularity: .minute) {
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
            loadedImage.cacheKey == imageData.cacheKey
        }) {
            radarSequence.currentImageIndex = index
            radarImageManager.userSelectedImage(timestamp: imageData.timestamp)
        }
    }
}

// Separate component for each progress bar box to avoid race conditions
struct ProgressBarBox: View {
    @ObservedObject var imageData: RadarImageData
    @ObservedObject var radarSequence: RadarImageSequence
    @ObservedObject var radarImageManager: RadarImageManager
    var onErrorTap: ((String) -> Void)?
    
    // Capture state at render time to avoid mid-render changes
    private var isCurrentFrame: Bool {
        guard let displayedTimestamp = radarImageManager.displayedTimestamp else { return false }
        return Calendar.current.isDate(imageData.timestamp, equalTo: displayedTimestamp, toGranularity: .minute)
    }

    // log whole imageData
    private var imageDataString: String {
        return "imageData: \(imageData.timestamp.radarTimestampString), state: \(imageData.state), kind: \(imageData.kind), sourceTimestamp: \(imageData.sourceTimestamp.radarTimestampString), forecastTimestamp: \(imageData.forecastTimestamp.radarTimestampString)"
    }
    
    private var isEnabled: Bool {
        imageData.state == .success
    }
    
    private var isFailed: Bool {
        if case .failed = imageData.state { return true }
        return false
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(fillColor)
            .frame(height: RadarProgressBar.Constants.boxHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(strokeColor, lineWidth: 1.0)
            )
            .opacity(opacity)
            .scaleEffect(isCurrentFrame ? 1.1 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture {
                if isEnabled {
                    print("Tap gesture triggered for: \(imageData.timestamp.radarTimestampString)")
                    radarImageManager.userSelectedImage(timestamp: imageData.timestamp)
                    handleSelection()
                } else if isFailed {
                    // Show error toast when tapping on failed box
                    let errorMessage = buildErrorMessage()
                    onErrorTap?(errorMessage)
                } else {
                    print("Tap ignored - button not enabled")
                    print("imageDataString: \(imageDataString)")
                }
            }
    }
    
    private func buildErrorMessage() -> String {
        if let error = imageData.lastError {
            return error.localizedDescription
        } else {
            return String(localized: "error.unknown")
        }
    }
    
    private var strokeColor: Color {
        switch imageData.state {
        case .success: return baseColor
        case .loading, .retrying: return .yellow
        case .failed: return .red
        case .pending: return .gray
        case .skipped: return .gray.opacity(0.6)
        }
    }
    
    private var baseColor: Color {
        switch imageData.kind {
        case .observed:
            return .blue
        case .forecast:
            return .orange
        }
    }
    
    private var fillColor: Color {
        guard case .success = imageData.state else {
            return isCurrentFrame ? strokeColor.opacity(0.25) : Color.clear
        }
        if imageData.kind.isForecast {
            return isCurrentFrame ? Color.orange.opacity(0.45) : Color.orange.opacity(0.22)
        }
        return isCurrentFrame ? Color.blue.opacity(0.45) : Color.blue.opacity(0.15)
    }
    
    private var opacity: Double {
        switch imageData.state {
        case .success: return imageData.kind.isForecast ? 0.85 : 1.0
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

// Toast view for displaying error messages
struct ErrorToastView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 16, weight: .semibold))
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 20)
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
        .padding()
        .background(Color.black)
        .cornerRadius(16)
    }
    .background(Color.white)
}
