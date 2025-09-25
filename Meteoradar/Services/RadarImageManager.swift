//
//  RadarImageManager.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import Foundation
import UIKit
import Combine
import os

class RadarImageManager: ObservableObject {
    @Published var radarSequence = RadarImageSequence()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdateTime: Date?
    @Published private(set) var displayedTimestamp: Date?
    
    private let networkService = NetworkService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meteoradar", category: "RadarImageManager")
    private var animationTimer: Timer?
    private var updateTimer: Timer?
    private var retryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    
    init() {
        setupPublishedForwarding()
        fetchLatestRadarImages()
        setupUpdateTimer()
    }
    
    deinit {
        stopAllTimers()
        networkService.cancelAllRadarRequests()
    }
    
    // MARK: - Public Methods
    
    func startAnimation() {
        guard !radarSequence.images.isEmpty else { return }

        let loadedFrames = radarSequence.loadedImages
        guard loadedFrames.count > 1 else {
            radarSequence.isAnimating = false
            return
        }

        radarSequence.isAnimating = true

        // Reset any existing timer before starting a new one
        animationTimer?.invalidate()

        // If we're on the newest image (index 0), immediately advance to start the sequence
        if radarSequence.currentImageIndex == 0 {
            advanceSequence(animated: false)
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.animationInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let shouldStop = self.advanceSequence(animated: true)
            if shouldStop {
                self.stopAnimation()
            }
        }
    }
    
    func stopAnimation() {
        radarSequence.isAnimating = false
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    func refreshRadarImages() {
        fetchLatestRadarImages()
    }
    
    func cancelAllFetches() {
        networkService.cancelAllRadarRequests()
        // Reset any loading placeholders to pending state
        for image in radarSequence.images where image.isLoading {
            image.state = .pending
            image.startTime = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func setupPublishedForwarding() {
        // Forward objectWillChange from radarSequence to this RadarImageManager
        radarSequence.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func setupUpdateTimer() {
        // Simple repeating timer - check every 10 seconds for radar updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkForRadarUpdate()
        }
    }
    
    private func checkForRadarUpdate() {
        let now = Date.utcNow
        
        // Only fetch missing images when we're at a 5-minute interval
        if now.isRadarUpdateTime {
            fetchLatestRadarImages() // This will fetch all missing images, not just the latest
        }
    }
    
    
    private func fetchLatestRadarImages() {
        isLoading = true
        errorMessage = nil
        
        // Capture if user was on newest image before we start fetching
        let wasOnNewest = (radarSequence.currentImageIndex == 0)
        
        let timestamps = Date.radarTimestamps(count: Constants.Radar.imageCount)
        
        // Create placeholders for all timestamps first (this ensures progress bar shows immediately)
        radarSequence.createPlaceholders(for: timestamps)
        
        // Fetch images that we don't already have
        let timestampsToFetch = timestamps.filter { timestamp in
            !radarSequence.hasImage(for: timestamp)
        }

        performFetch(for: timestampsToFetch, wasOnNewest: wasOnNewest, isRetryAttempt: false)
    }
    
    private func performFetch(for timestamps: [Date], wasOnNewest: Bool, isRetryAttempt: Bool) {
        guard !timestamps.isEmpty else {
            isLoading = false
            return
        }
        
        isLoading = true
        
        for timestamp in timestamps {
            guard let placeholder = radarSequence.images.first(where: {
                Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute)
            }) else {
                logger.error("Attempted to fetch radar frame \(timestamp.radarTimestampString) but placeholder missing")
                continue
            }
            
            placeholder.startTime = Date()
            placeholder.attemptCount += 1
            
            if isRetryAttempt {
                placeholder.state = .retrying(attemptCount: placeholder.attemptCount)
            } else {
                placeholder.state = .loading
            }
        }
        
        networkService.fetchRadarSequence(
            timestamps: timestamps,
            strategy: .sequential
        )
        .sink { [weak self] radarResults in
            self?.processRadarResults(radarResults, attemptedTimestamps: timestamps, wasOnNewest: wasOnNewest)
        }
        .store(in: &cancellables)
    }
    
    /// Process radar results and update placeholders
    private func processRadarResults(_ radarResults: [RadarImageResult], attemptedTimestamps: [Date], wasOnNewest: Bool) {
        var successCount = 0
        var fetchErrors: [Error] = []

        for radarResult in radarResults {
            // Find the placeholder to update
            if let placeholder = radarSequence.images.first(where: { 
                Calendar.current.isDate($0.timestamp, equalTo: radarResult.timestamp, toGranularity: .minute) 
            }) {
                placeholder.endTime = Date()
                
                switch radarResult.result {
                case .success(let image):
                    radarSequence.updateImage(placeholder, with: image, fromCache: radarResult.wasFromCache)
                    successCount += 1
                    
                    // If user was on newest before fetching, jump to newest available image
                    if wasOnNewest {
                        radarSequence.currentImageIndex = 0
                    }
                    
                case .failure(let error):
                    handleImageFetchError(error, placeholder: placeholder, timestamp: radarResult.timestamp)
                    fetchErrors.append(error)
                }
            } else {
                logger.error("Received radar result for \(radarResult.timestamp.radarTimestampString) but no matching placeholder found")
            }
        }
        
        // Detect timestamps that never produced a result (still marked as loading)
        let unresolvedTimestamps = attemptedTimestamps.compactMap { timestamp -> (Date, RadarImageData)? in
            guard let placeholder = radarSequence.images.first(where: {
                Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute)
            }) else {
                return nil
            }
            switch placeholder.state {
            case .loading, .retrying:
                return (timestamp, placeholder)
            default:
                return nil
            }
        }

        if !unresolvedTimestamps.isEmpty {
            for (timestamp, placeholder) in unresolvedTimestamps {
                let error = RadarPipelineError.missingResult(timestamp: timestamp)
                placeholder.state = .failed(error, attemptCount: placeholder.attemptCount)
                placeholder.lastError = error
                placeholder.endTime = Date()
                logger.error("No network result received for \(timestamp.radarTimestampString); marking as failure")
                fetchErrors.append(error)
            }
        }

        let retryCandidates = radarSequence.images.compactMap { imageData -> Date? in
            guard attemptedTimestamps.contains(where: { Calendar.current.isDate($0, equalTo: imageData.timestamp, toGranularity: .minute) }) else {
                return nil
            }
            if case .failed = imageData.state, imageData.shouldRetry {
                return imageData.timestamp
            }
            return nil
        }
        
        let remainingFailures = radarSequence.images.filter { imageData in
            guard attemptedTimestamps.contains(where: { Calendar.current.isDate($0, equalTo: imageData.timestamp, toGranularity: .minute) }) else {
                return false
            }
            if case .failed = imageData.state, !imageData.shouldRetry {
                return true
            }
            return false
        }
        
        lastUpdateTime = Date()
        
        if successCount > 0 {
            errorMessage = nil
        }

        if !retryCandidates.isEmpty {
            scheduleIndividualRetry(for: retryCandidates, wasOnNewest: wasOnNewest)
            isLoading = true
        } else {
            isLoading = false
            if successCount == 0 && !fetchErrors.isEmpty {
                errorMessage = "Failed to fetch radar images"
                if !remainingFailures.isEmpty {
                    scheduleRetry()
                }
                logger.error("All radar fetches failed for batch: \(attemptedTimestamps.map { $0.radarTimestampString }.joined(separator: ", ")) – errors: \(fetchErrors.map { $0.localizedDescription }.joined(separator: "; "))")
            } else if let unresolved = unresolvedTimestamps.first {
                logger.error("Radar fetch for \(unresolved.0.radarTimestampString) unresolved after processing")
            }
        }
    }
    
    /// Handle individual image fetch errors with appropriate state updates
    private func handleImageFetchError(_ error: Error, placeholder: RadarImageData, timestamp: Date) {
        // Don't treat cancellation as a real error for UI purposes
        if let urlError = error as? URLError, urlError.code == .cancelled {
            placeholder.state = .pending
            placeholder.startTime = nil
            print("Radar image request cancelled for \(timestamp.radarTimestampString) - reset to pending")
            logger.notice("Radar fetch cancelled for \(timestamp.radarTimestampString)")
        } else {
            placeholder.state = .failed(error, attemptCount: placeholder.attemptCount)
            placeholder.lastError = error
            print("Failed to fetch radar image for \(timestamp.radarTimestampString): \(error.localizedDescription)")
            logger.error("Radar fetch failed for \(timestamp.radarTimestampString) [attempt \(placeholder.attemptCount)]: \(error.localizedDescription)")
        }
    }
    
    
    private func scheduleIndividualRetry(for timestamps: [Date], wasOnNewest: Bool) {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.retryDelay, repeats: false) { [weak self] _ in
            self?.performFetch(for: timestamps, wasOnNewest: wasOnNewest, isRetryAttempt: true)
        }
        logger.warning("Retry armed for timestamps: \(timestamps.map { $0.radarTimestampString }.joined(separator: ", "))")
    }
    
    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.retryInterval, repeats: false) { [weak self] _ in
            self?.fetchLatestRadarImages() // Retry fetching all missing images, not just latest
        }
        logger.warning("Full sequence retry scheduled in \(Constants.Radar.retryInterval, format: .fixed(precision: 0))s")
    }
    
    private func stopAllTimers() {
        animationTimer?.invalidate()
        updateTimer?.invalidate()
        retryTimer?.invalidate()
        animationTimer = nil
        updateTimer = nil
        retryTimer = nil
    }

    // MARK: - Rendering Coordination

    func overlayDidUpdate(imageTimestamp: Date?) {
        setDisplayedTimestamp(imageTimestamp, deferred: true)
    }

    func userSelectedImage(timestamp: Date?) {
        // Ensure immediate UI update for taps, while keeping SwiftUI warnings away
        setDisplayedTimestamp(timestamp, deferred: false)
    }

    @discardableResult
    private func advanceSequence(animated: Bool) -> Bool {
        let availableImages = radarSequence.loadedImages
        guard !availableImages.isEmpty else { return true }

        if availableImages.count == 1 {
            radarSequence.currentImageIndex = 0
            return true
        }

        let previousIndex = radarSequence.currentImageIndex
        radarSequence.nextFrame()

        guard animated else { return false }

        return radarSequence.currentImageIndex == 0 && previousIndex != 0
    }

    private func setDisplayedTimestamp(_ timestamp: Date?, deferred: Bool) {
        guard displayedTimestamp != timestamp else { return }

        let updateBlock: () -> Void = { [weak self] in
            guard let self = self, self.displayedTimestamp != timestamp else { return }
            self.displayedTimestamp = timestamp
        }

        if deferred {
            DispatchQueue.main.async(execute: updateBlock)
        } else if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

}

private enum RadarPipelineError: LocalizedError {
    case missingResult(timestamp: Date)

    var errorDescription: String? {
        switch self {
        case .missingResult(let timestamp):
            return "No network result received for \(timestamp.radarTimestampString)"
        }
    }
}
