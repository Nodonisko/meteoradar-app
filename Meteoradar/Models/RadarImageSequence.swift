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

enum RadarFrameKind: Equatable, Hashable {
    case observed
    case forecast(offsetMinutes: Int)
}

extension RadarFrameKind {
    var sortPriority: Int {
        switch self {
        case .observed:
            return 0
        case .forecast:
            return 1
        }
    }
    
    var isForecast: Bool {
        if case .forecast = self { return true }
        return false
    }

    var isObserved: Bool {
        if case .observed = self { return true }
        return false
    }

    var forecastOffsetMinutes: Int? {
        if case .forecast(let offset) = self { return offset }
        return nil
    }
}

class RadarImageData: ObservableObject {
    let timestamp: Date
    let urlString: String
    let kind: RadarFrameKind
    let sourceTimestamp: Date
    let forecastTimestamp: Date
    
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
        guard let url = URL(string: urlString) else { return urlString }
        return RadarCacheHelpers.cacheFilename(for: url)
    }
    
    // Source tracking for debugging/UI
    enum ImageSource {
        case cache
        case network
        case unknown
    }
    @Published var imageSource: ImageSource = .unknown
    
    init(timestamp: Date, urlString: String, kind: RadarFrameKind, sourceTimestamp: Date, forecastTimestamp: Date) {
        self.timestamp = timestamp
        self.urlString = urlString
        self.kind = kind
        self.sourceTimestamp = sourceTimestamp
        self.forecastTimestamp = forecastTimestamp
    }
    
    // Legacy initializer for backward compatibility
    init(timestamp: Date, image: UIImage, urlString: String, kind: RadarFrameKind, sourceTimestamp: Date, forecastTimestamp: Date) {
        self.timestamp = timestamp
        self.urlString = urlString
        self.kind = kind
        self.sourceTimestamp = sourceTimestamp
        self.forecastTimestamp = forecastTimestamp
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
        let maxAttempts: Int
        switch kind {
        case .observed:
            maxAttempts = Constants.Radar.maxRetryAttempts
        case .forecast:
            maxAttempts = Constants.Radar.forecastMaxRetryAttempts
        }
        switch state {
        case .failed, .pending, .retrying:
            return attemptCount < maxAttempts
        default:
            return false
        }
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
    @Published private(set) var images: [RadarImageData] = [] {
        didSet {
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
        let observed = images
            .filter { $0.hasSucceeded && $0.kind.isObserved }
            .sorted { $0.timestamp > $1.timestamp }
        guard let latestObserved = observed.first else {
            return observed
        }
        let forecasts = images
            .filter { $0.hasSucceeded && $0.kind.isForecast && Calendar.current.isDate($0.sourceTimestamp, equalTo: latestObserved.sourceTimestamp, toGranularity: .minute) }
            .sorted { lhs, rhs in
                switch (lhs.kind, rhs.kind) {
                case (.forecast(let leftOffset), .forecast(let rightOffset)):
                    if leftOffset != rightOffset { return leftOffset < rightOffset }
                    return lhs.forecastTimestamp < rhs.forecastTimestamp
                default:
                    return lhs.forecastTimestamp < rhs.forecastTimestamp
                }
            }
        return observed + forecasts
    }
    
    var currentImage: UIImage? {
        let availableImages = loadedImages
        guard !availableImages.isEmpty else { return nil }
        
        // If current index is invalid, fall back to newest image (index 0)
        let safeIndex = min(currentImageIndex, availableImages.count - 1)
        return availableImages[safeIndex].image
    }
    
    var currentImageData: RadarImageData? {
        let availableImages = loadedImages
        guard !availableImages.isEmpty else { return nil }
        let safeIndex = min(currentImageIndex, availableImages.count - 1)
        return availableImages[safeIndex]
    }
    
    var currentTimestamp: Date? {
        let availableImages = loadedImages
        guard !availableImages.isEmpty else { return nil }
        
        // If current index is invalid, fall back to newest image (index 0)
        let safeIndex = min(currentImageIndex, availableImages.count - 1)
        return availableImages[safeIndex].timestamp
    }
    
    // MARK: - Animation Control
    
    /// Prepares for animation by jumping to the starting frame
    /// Returns false if animation not possible (< 2 frames)
    func prepareAnimation() -> Bool {
        let available = loadedImages
        guard available.count > 1 else { return false }
        
        let current = min(currentImageIndex, available.count - 1)
        let currentFrame = available[current]
        
        // Determine where to start based on current position
        if currentFrame.kind.isForecast {
            // Check if on last forecast
            let nextIndex = current + 1
            let isLastForecast = nextIndex >= available.count || !available[nextIndex].kind.isForecast
            
            if isLastForecast {
                // On last forecast: jump to first forecast
                if let firstForecast = available.firstIndex(where: { $0.kind.isForecast }) {
                    currentImageIndex = firstForecast
                }
            }
            // else: stay at current forecast position and animate from there
            return true
        } else {
            // On observed: if on current (0), go to oldest; otherwise stay on current position
            if current == 0, let lastObserved = available.lastIndex(where: { $0.kind.isObserved }) {
                currentImageIndex = lastObserved
            }
            // else: stay at current position (will animate forward to current)
            return true
        }
    }
    
    /// Advances to next frame in animation sequence
    /// Returns true if should stop (reached end), false to continue
    func nextAnimationFrame() -> Bool {
        let available = loadedImages
        guard available.count > 1, currentImageIndex < available.count else { return true }
        
        let currentFrame = available[currentImageIndex]
        
        if currentFrame.kind.isForecast {
            // Animating forecast: move forward until last forecast
            let nextIndex = currentImageIndex + 1
            if nextIndex < available.count && available[nextIndex].kind.isForecast {
                currentImageIndex = nextIndex
                return false
            } else {
                // Reached last forecast - stay here and stop
                return true
            }
        } else {
            // Animating observed: move backward (toward index 0 = newest observed)
            if currentImageIndex > 0 {
                currentImageIndex -= 1
                return false  // Continue animating
            } else {
                // At index 0 (newest observed) - stop here, don't jump to forecasts
                return true
            }
        }
    }
    
    func reset() {
        // Go to newest image (index 0 since loadedImages is sorted newest first)
        currentImageIndex = 0
    }
    
    // Management methods for sequential loading
    func createPlaceholders(for timestamps: [Date], forecastOffsets: [Int] = []) {
        // Remember what we're currently viewing before making changes
        let currentViewingTimestamp = currentTimestamp
        
        // Build list of images we need (reusing existing successful ones where possible)
        var newImages: [RadarImageData] = []
        
        for timestamp in timestamps {
            // Try to reuse existing successful observed image
            if let existingObserved = images.first(where: {
                $0.kind == .observed && 
                Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute) &&
                $0.hasSucceeded
            }) {
                newImages.append(existingObserved)
            } else {
                // Create new placeholder only if we don't have a successful one
                let urlString = Constants.Radar.observedURL(for: timestamp, quality: SettingsService.shared.imageQuality)
                let observedData = RadarImageData(
                    timestamp: timestamp,
                    urlString: urlString,
                    kind: .observed,
                    sourceTimestamp: timestamp,
                    forecastTimestamp: timestamp
                )
                newImages.append(observedData)
            }
            
            // Handle forecast images for the newest timestamp
            if timestamp == timestamps.first {
                for offset in forecastOffsets {
                    // Try to reuse existing successful forecast image
                    if let existingForecast = images.first(where: {
                        $0.kind == .forecast(offsetMinutes: offset) && 
                        Calendar.current.isDate($0.sourceTimestamp, equalTo: timestamp, toGranularity: .minute) &&
                        $0.hasSucceeded
                    }) {
                        newImages.append(existingForecast)
                    } else {
                        // Create new placeholder only if we don't have a successful one
                        let forecastTimestamp = timestamp.addingTimeInterval(TimeInterval(offset * 60))
                        let urlString = Constants.Radar.forecastURL(for: timestamp, offsetMinutes: offset, quality: SettingsService.shared.imageQuality)
                        let forecastData = RadarImageData(
                            timestamp: forecastTimestamp,
                            urlString: urlString,
                            kind: .forecast(offsetMinutes: offset),
                            sourceTimestamp: timestamp,
                            forecastTimestamp: forecastTimestamp
                        )
                        newImages.append(forecastData)
                    }
                }
            }
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
    
    var newestObservedImage: RadarImageData? {
        return images
            .filter { data in
                if case .observed = data.kind { return true }
                return false
            }
            .max { $0.timestamp < $1.timestamp }
    }
    
    func forecastImages(for sourceTimestamp: Date) -> [RadarImageData] {
        return images.filter { data in
            guard case .forecast = data.kind else { return false }
            return Calendar.current.isDate(data.sourceTimestamp, equalTo: sourceTimestamp, toGranularity: .minute)
        }
        .sorted { lhs, rhs in
            switch (lhs.kind, rhs.kind) {
            case (.forecast(let lOffset), .forecast(let rOffset)):
                if lOffset != rOffset { return lOffset < rOffset }
                return lhs.forecastTimestamp < rhs.forecastTimestamp
            default:
                return lhs.forecastTimestamp < rhs.forecastTimestamp
            }
        }
    }
    
    var hasLoadingObservedImages: Bool {
        return images.contains { data in
            if case .observed = data.kind {
                return data.isLoading
            }
            return false
        }
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
        imageData.attemptCount = 0
        imageData.lastError = nil
        
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
