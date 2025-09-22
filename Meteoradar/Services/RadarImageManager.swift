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
    private var pendingFetches: Set<String> = []
    private var cancellables = Set<AnyCancellable>()
    
    
    init() {
        setupPublishedForwarding()
        fetchLatestRadarImages()
        setupUpdateTimer()
    }
    
    deinit {
        stopAllTimers()
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
        
        let fetchGroup = DispatchGroup()
        var fetchErrors: [Error] = []
        var successCount = 0
        
        for timestamp in timestampsToFetch {
            let timestampString = timestamp.radarTimestampString
            let urlString = String(format: Constants.Radar.baseURL, timestampString)
            
            // Skip if already fetching this URL
            guard !pendingFetches.contains(urlString) else { continue }
            
            // Find the placeholder and mark it as loading
            if let placeholder = radarSequence.images.first(where: { 
                Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute) 
            }) {
                placeholder.state = .loading
                placeholder.startTime = Date()
            }
            
            pendingFetches.insert(urlString)

            fetchGroup.enter()
            
            networkService.fetchRadarImage(from: urlString) { [weak self] result in
                defer {
                    fetchGroup.leave()
                    self?.pendingFetches.remove(urlString)
                }
                
                DispatchQueue.main.async {
                    // Find the placeholder to update
                    guard let placeholder = self?.radarSequence.images.first(where: { 
                        Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute) 
                    }) else { return }
                    
                    placeholder.endTime = Date()
                    
                    switch result {
                    case .success(let image):
                        self?.radarSequence.updateImage(placeholder, with: image, fromCache: false)
                        successCount += 1
                        
                        // If user was on newest before fetching, jump to newest available image
                        if wasOnNewest {
                            self?.radarSequence.currentImageIndex = 0
                        }
                    case .failure(let error):
                        placeholder.state = .failed(error, attemptCount: placeholder.attemptCount + 1)
                        placeholder.lastError = error
                        fetchErrors.append(error)
                        print("Failed to fetch radar image for \(timestampString): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        fetchGroup.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            self?.lastUpdateTime = Date()
            
            if successCount > 0 {
                self?.errorMessage = nil
            } else if !fetchErrors.isEmpty {
                self?.errorMessage = "Failed to fetch radar images"
                // If we couldn't fetch the latest images, retry in a bit
                self?.scheduleRetry()
            }
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
