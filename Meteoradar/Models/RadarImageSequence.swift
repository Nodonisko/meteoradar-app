//
//  RadarImageSequence.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 15.09.2025.
//

import Foundation
import UIKit
import Combine

enum ImageLoadingState: Equatable {
    case pending           // Not started yet
    case loading          // Currently fetching
    case success          // Successfully loaded
    case failed(Error, attemptCount: Int)  // Failed with error and retry count
    case retrying(attemptCount: Int)        // Currently retrying
    case skipped          // Skipped due to consecutive failures or other logic
    
    static func == (lhs: ImageLoadingState, rhs: ImageLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.loading, .loading), (.success, .success), (.skipped, .skipped):
            return true
        case (.failed(_, let lCount), .failed(_, let rCount)):
            return lCount == rCount
        case (.retrying(let lCount), .retrying(let rCount)):
            return lCount == rCount
        default:
            return false
        }
    }
}

class RadarImageData: ObservableObject {
    let timestamp: Date
    let urlString: String
    
    // Image data (optional until loaded)
    @Published var image: UIImage?
    
    // Loading metadata
    @Published var state: ImageLoadingState = .pending
    @Published var attemptCount: Int = 0
    @Published var startTime: Date?
    @Published var endTime: Date?
    @Published var lastError: Error?
    
    // Cache metadata (ready for future file system caching)
    @Published var isCached: Bool = false
    @Published var cacheDate: Date?
    var cacheKey: String {
        return timestamp.radarTimestampString
    }
    
    // Source tracking for debugging/UI
    enum ImageSource {
        case cache
        case network
        case unknown
    }
    @Published var imageSource: ImageSource = .unknown
    
    init(timestamp: Date, urlString: String) {
        self.timestamp = timestamp
        self.urlString = urlString
    }
    
    // Legacy initializer for backward compatibility
    init(timestamp: Date, image: UIImage, urlString: String) {
        self.timestamp = timestamp
        self.urlString = urlString
        self.image = image
        self.state = .success
        self.imageSource = .network
    }
    
    // Computed properties
    var loadDuration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    var isLoading: Bool {
        if case .loading = state { return true }
        if case .retrying = state { return true }
        return false
    }
    
    var hasSucceeded: Bool {
        if case .success = state { return true }
        return false
    }
    
    var hasFailed: Bool {
        if case .failed = state { return true }
        return false
    }
    
    var shouldRetry: Bool {
        if case .failed(_, let count) = state {
            return count < Constants.Radar.maxRetryAttempts
        }
        return false
    }
    
    // Cache-specific methods (ready for future implementation)
    func markAsCached(date: Date = Date()) {
        isCached = true
        cacheDate = date
        imageSource = .cache
    }
    
    func markAsNetworkLoaded() {
        imageSource = .network
        isCached = false // Will be cached after successful load
    }
}

class RadarImageSequence: ObservableObject {
    @Published var images: [RadarImageData] = [] {
        didSet {
            // Set up forwarding for new images
            setupImageChangeForwarding()
        }
    }
    @Published var currentImageIndex: Int = 0
    @Published var isAnimating: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setupImageChangeForwarding() {
        // Clear existing subscriptions
        cancellables.removeAll()
        
        // Forward objectWillChange from each RadarImageData to this RadarImageSequence
        for imageData in images {
            imageData.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }
    
    // Only successfully loaded images for animation (skips failed ones)
    // Sorted newest first so index 0 shows the latest image
    var loadedImages: [RadarImageData] {
        return images.filter { $0.hasSucceeded }.sorted { $0.timestamp > $1.timestamp }
    }
    
    var currentImage: UIImage? {
        let availableImages = loadedImages
        guard !availableImages.isEmpty else { return nil }
        
        // If current index is invalid, fall back to newest image (index 0)
        let safeIndex = min(currentImageIndex, availableImages.count - 1)
        return availableImages[safeIndex].image
    }
    
    var currentTimestamp: Date? {
        let availableImages = loadedImages
        guard !availableImages.isEmpty else { return nil }
        
        // If current index is invalid, fall back to newest image (index 0)
        let safeIndex = min(currentImageIndex, availableImages.count - 1)
        return availableImages[safeIndex].timestamp
    }
    
    // Animation methods that skip missing images
    // Since loadedImages is sorted newest first, we need to reverse the animation direction
    func nextFrame() {
        let availableImages = loadedImages
        guard !availableImages.isEmpty else { return }
        let oldIndex = currentImageIndex
        currentImageIndex = currentImageIndex > 0 ? currentImageIndex - 1 : availableImages.count - 1
        print("RadarImageSequence: nextFrame() - index changed from \(oldIndex) to \(currentImageIndex) (total: \(availableImages.count))")
    }
    
    func previousFrame() {
        let availableImages = loadedImages
        guard !availableImages.isEmpty else { return }
        currentImageIndex = (currentImageIndex + 1) % availableImages.count
    }
    
    func reset() {
        // Go to newest image (index 0 since loadedImages is sorted newest first)
        currentImageIndex = 0
    }
    
    // Management methods for sequential loading
    func createPlaceholders(for timestamps: [Date]) {
        // Remember what we're currently viewing before making changes
        let currentViewingTimestamp = currentTimestamp
        
        // Create RadarImageData objects for all timestamps
        let newImages = timestamps.map { timestamp in
            let urlString = String(format: Constants.Radar.baseURL, timestamp.radarTimestampString)
            let imageData = RadarImageData(timestamp: timestamp, urlString: urlString)
            
            // Check if we had this timestamp before and preserve successful state
            if let existingImage = images.first(where: { 
                Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute) 
            }), existingImage.hasSucceeded {
                imageData.image = existingImage.image
                imageData.state = existingImage.state
                imageData.isCached = existingImage.isCached
                imageData.cacheDate = existingImage.cacheDate
                imageData.imageSource = existingImage.imageSource
            }
            
            return imageData
        }
        
        images = newImages
        
        // Restore the viewing state to the same timestamp if it still exists in loaded images
        if let currentTimestamp = currentViewingTimestamp,
           let newIndex = loadedImages.firstIndex(where: { 
               Calendar.current.isDate($0.timestamp, equalTo: currentTimestamp, toGranularity: .minute) 
           }) {
            currentImageIndex = newIndex
            print("RadarImageSequence: Preserved viewing timestamp \(currentTimestamp.radarTimestampString) at new index \(newIndex)")
        } else {
            // Fallback to newest available image (index 0)
            currentImageIndex = 0
            print("RadarImageSequence: Reset to newest image (index 0) - previous timestamp no longer available")
        }
    }
    
    func getNextPendingImage() -> RadarImageData? {
        // Return first image that needs loading (newest first)
        return images.first { image in
            switch image.state {
            case .pending where image.shouldRetry, .failed where image.shouldRetry:
                return true
            default:
                return false
            }
        }
    }
    
    func getFailedImages() -> [RadarImageData] {
        return images.filter { $0.hasFailed && $0.shouldRetry }
    }
    
    func hasImage(for timestamp: Date) -> Bool {
        return images.contains { 
            Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute) && $0.hasSucceeded
        }
    }
    
    // Update image from cache or network
    func updateImage(_ imageData: RadarImageData, with image: UIImage, fromCache: Bool = false) {
        imageData.image = image
        imageData.state = .success
        imageData.endTime = Date()
        
        if fromCache {
            imageData.markAsCached()
        } else {
            imageData.markAsNetworkLoaded()
        }
    }
    
    func removeImage(at index: Int) {
        guard index >= 0 && index < images.count else { return }
        images.remove(at: index)
        
        // Adjust current index if needed
        if currentImageIndex >= images.count {
            currentImageIndex = max(0, images.count - 1)
        }
    }
}
