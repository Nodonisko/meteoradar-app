//
//  RadarImageManager.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import Foundation
import UIKit
import Combine

class RadarImageManager: ObservableObject {
    @Published var radarSequence = RadarImageSequence()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdateTime: Date?
    
    private let networkService = NetworkService.shared
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
        
        radarSequence.isAnimating = true
        
        // If we're on the newest image (index 0), immediately advance to start the sequence
        if radarSequence.currentImageIndex == 0 {
            radarSequence.nextFrame()
        }
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.animationInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.radarSequence.nextFrame()
            
            // Stop animation when we reach the newest image (index 0)
            if self.radarSequence.currentImageIndex == 0 {
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
        
        guard !timestampsToFetch.isEmpty else {
            isLoading = false
            return
        }
        
        // Mark placeholders as loading
        for timestamp in timestampsToFetch {
            if let placeholder = radarSequence.images.first(where: { 
                Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute) 
            }) {
                placeholder.state = .loading
                placeholder.startTime = Date()
            }
        }
        
        // Use simplified radar-aware network service
        networkService.fetchRadarSequence(
            timestamps: timestampsToFetch,
            strategy: .sequential
        )
        .sink { [weak self] radarResults in
            self?.processRadarResults(radarResults, wasOnNewest: wasOnNewest)
        }
        .store(in: &cancellables)
    }
    
    /// Process radar results and update placeholders
    private func processRadarResults(_ radarResults: [RadarImageResult], wasOnNewest: Bool) {
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
            }
        }
        
        // Update loading state and handle errors
        isLoading = false
        lastUpdateTime = Date()
        
        if successCount > 0 {
            errorMessage = nil
        } else if !fetchErrors.isEmpty {
            errorMessage = "Failed to fetch radar images"
            scheduleRetry()
        }
    }
    
    /// Handle individual image fetch errors with appropriate state updates
    private func handleImageFetchError(_ error: Error, placeholder: RadarImageData, timestamp: Date) {
        // Don't treat cancellation as a real error for UI purposes
        if let urlError = error as? URLError, urlError.code == .cancelled {
            placeholder.state = .pending
            placeholder.startTime = nil
            print("Radar image request cancelled for \(timestamp.radarTimestampString) - reset to pending")
        } else {
            placeholder.state = .failed(error, attemptCount: placeholder.attemptCount + 1)
            placeholder.lastError = error
            print("Failed to fetch radar image for \(timestamp.radarTimestampString): \(error.localizedDescription)")
        }
    }
    
    
    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.retryInterval, repeats: false) { [weak self] _ in
            self?.fetchLatestRadarImages() // Retry fetching all missing images, not just latest
        }
    }
    
    private func stopAllTimers() {
        animationTimer?.invalidate()
        updateTimer?.invalidate()
        retryTimer?.invalidate()
        animationTimer = nil
        updateTimer = nil
        retryTimer = nil
    }
}
