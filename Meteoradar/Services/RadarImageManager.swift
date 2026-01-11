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
    private let settingsService = SettingsService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meteoradar", category: "RadarImageManager")
    private var animationTimer: Timer?
    private var updateTimer: Timer?
    private var retryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var forecastFetchCancellable: AnyCancellable?
    private var activeForecastSourceTimestamp: Date?
    private var forecastRetryTimer: Timer?
    private var lastUsedIntervalMinutes: Int?
    
    
    init() {
        setupPublishedForwarding()
        setupSettingsObserver()
        setupAppLifecycleObserver()
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
        
        // Prepare animation - this jumps to the start frame
        guard radarSequence.prepareAnimation() else {
            radarSequence.isAnimating = false
            return
        }
        
        radarSequence.isAnimating = true
        animationTimer?.invalidate()
        
        // Start animation timer
        animationTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.animationInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let shouldStop = self.radarSequence.nextAnimationFrame()
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
        // Stop animation if running
        stopAnimation()
        
        // Jump to latest available frame
        radarSequence.reset()
        
        // Cancel all ongoing operations first
        cancelAllFetches()
        retryTimer?.invalidate()
        retryTimer = nil
        
        // Start fresh
        fetchLatestRadarImages()
    }
    
    func cancelAllFetches() {
        networkService.cancelAllRadarRequests()
        cancelForecastFetch()
        // Reset any loading placeholders to pending state
        for image in radarSequence.images where image.isLoading {
            image.state = .pending
            image.startTime = nil
        }
        for image in radarSequence.images where image.kind.isForecast {
            switch image.state {
            case .failed where image.shouldRetry,
                 .loading,
                 .retrying:
                image.state = .pending
                image.startTime = nil
                image.endTime = nil
                image.lastError = nil
            default:
                break
            }
        }
    }
    
    private func cancelForecastFetch() {
        forecastFetchCancellable?.cancel()
        forecastFetchCancellable = nil
        forecastRetryTimer?.invalidate()
        forecastRetryTimer = nil
        activeForecastSourceTimestamp = nil
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
    
    private func setupSettingsObserver() {
        // Observe changes to radar image interval and refresh when it changes
        settingsService.$radarImageIntervalMinutes
            .dropFirst() // Skip initial value (we already fetch on init)
            .removeDuplicates()
            .sink { [weak self] newInterval in
                guard let self = self else { return }
                // Only refresh if interval actually changed from what we last used
                if self.lastUsedIntervalMinutes != newInterval {
                    self.logger.info("Radar interval changed to \(newInterval) minutes, refreshing images")
                    self.cancelAllFetches()
                    self.fetchLatestRadarImages()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupAppLifecycleObserver() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .dropFirst() // Skip initial activation on app launch (we already fetch in init)
            .sink { [weak self] _ in
                self?.logger.info("App became active, refreshing radar images")
                self?.refreshRadarImages()
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

        let interval = settingsService.radarImageIntervalMinutes
        lastUsedIntervalMinutes = interval
        let timestamps = Date.radarTimestamps(count: Constants.Radar.imageCount, intervalMinutes: interval)

        // Cancel any active forecast fetch BEFORE creating new placeholders
        // This ensures old network operations don't try to update stale placeholders
        cancelForecastFetch()

        // Create placeholders for all timestamps first (this ensures progress bar shows immediately)
        let forecastOffsets = Constants.Radar.forecastOffsets()
        radarSequence.createPlaceholders(for: timestamps, forecastOffsets: forecastOffsets)
        activeForecastSourceTimestamp = timestamps.first
        
        // Fetch images that we don't already have
        let timestampsToFetch = timestamps.filter { timestamp in
            !radarSequence.hasImage(for: timestamp)
        }

        if timestampsToFetch.isEmpty {
            isLoading = false
            DispatchQueue.main.async { [weak self] in
                self?.startForecastFetchIfNeeded(force: true)
            }
            return
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
                $0.kind.isObserved && Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute)
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
        .sink(
            receiveCompletion: { [weak self] _ in
                // When all fetches complete, do final cleanup
                self?.handleFetchCompletion(attemptedTimestamps: timestamps)
            },
            receiveValue: { [weak self] radarResult in
                // Process each result immediately as it arrives
                self?.processIndividualResult(radarResult, wasOnNewest: wasOnNewest)
            }
        )
        .store(in: &cancellables)
    }
    
    /// Process individual result as it arrives (for progressive UI updates)
    private func processIndividualResult(_ radarResult: RadarImageResult, wasOnNewest: Bool) {
        // Find the placeholder to update
        guard let placeholder = radarSequence.images.first(where: { 
            $0.kind.isObserved && Calendar.current.isDate($0.timestamp, equalTo: radarResult.timestamp, toGranularity: .minute) 
        }) else {
            logger.error("Received radar result for \(radarResult.timestamp.radarTimestampString) but no matching placeholder found")
            return
        }
        
        placeholder.endTime = Date()
        
        switch radarResult.result {
        case .success(let image):
            radarSequence.updateImage(placeholder, with: image, fromCache: radarResult.wasFromCache)
            
            // If user was on newest before fetching, jump to newest available image
            if wasOnNewest {
                radarSequence.currentImageIndex = 0
            }
            
            logger.info("Successfully loaded radar image for \(radarResult.timestamp.radarTimestampString) (\(radarResult.wasFromCache ? "cache" : "network"))")
            
        case .failure(let error):
            handleImageFetchError(error, placeholder: placeholder, timestamp: radarResult.timestamp)
        }
    }
    
    /// Handle completion of all fetch attempts - cleanup and schedule next steps
    private func handleFetchCompletion(attemptedTimestamps: [Date]) {
        lastUpdateTime = Date()
        
        // Mark any still-loading timestamps as failed (shouldn't happen, but handle edge cases)
        let unresolvedCount = attemptedTimestamps.filter { timestamp in
            guard let placeholder = radarSequence.images.first(where: {
                $0.kind.isObserved && Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute)
            }) else { return false }
            
            if case .loading = placeholder.state {
                let error = RadarPipelineError.missingResult(timestamp: timestamp)
                placeholder.state = .failed(error, attemptCount: placeholder.attemptCount)
                placeholder.lastError = error
                placeholder.endTime = Date()
                logger.error("No network result received for \(timestamp.radarTimestampString); marking as failure")
                return true
            }
            if case .retrying = placeholder.state {
                let error = RadarPipelineError.missingResult(timestamp: timestamp)
                placeholder.state = .failed(error, attemptCount: placeholder.attemptCount)
                placeholder.lastError = error
                placeholder.endTime = Date()
                logger.error("No network result received for \(timestamp.radarTimestampString); marking as failure")
                return true
            }
            return false
        }.count
        
        // Check placeholders to see if we have successes and/or failures
        let attemptedPlaceholders = radarSequence.images.filter { imageData in
            attemptedTimestamps.contains(where: { Calendar.current.isDate($0, equalTo: imageData.timestamp, toGranularity: .minute) })
        }
        
        let hasSuccesses = attemptedPlaceholders.contains { $0.hasSucceeded }
        let failedCount = attemptedPlaceholders.filter { $0.hasFailed }.count
        
        // Update UI state
        if hasSuccesses {
            errorMessage = nil
            // Start forecast fetch if all observed images are done loading
            if radarSequence.hasLoadingObservedImages == false {
                startForecastFetchIfNeeded()
            }
        } else if failedCount > 0 {
            errorMessage = "Failed to fetch radar images"
            // If observed fetch failed entirely, cancel any forecast operations
            forecastFetchCancellable?.cancel()
            forecastFetchCancellable = nil
            forecastRetryTimer?.invalidate()
            forecastRetryTimer = nil
        }
        
        // Schedule retries for failed images
        let retryCandidates = attemptedPlaceholders.compactMap { imageData -> Date? in
            imageData.shouldRetry ? imageData.timestamp : nil
        }
        
        if !retryCandidates.isEmpty {
            let wasOnNewest = (radarSequence.currentImageIndex == 0)
            scheduleIndividualRetry(for: retryCandidates, wasOnNewest: wasOnNewest)
            isLoading = true
        } else {
            isLoading = false
            if !hasSuccesses && failedCount > 0 {
                scheduleRetry()
            }
        }
        
        if unresolvedCount > 0 {
            logger.warning("Detected \(unresolvedCount) unresolved timestamp(s) during fetch completion")
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
        forecastRetryTimer?.invalidate()
        animationTimer = nil
        updateTimer = nil
        retryTimer = nil
        forecastRetryTimer = nil
    }

    private func startForecastFetchIfNeeded(force: Bool = false) {
        // Prevent concurrent forecast fetches for the same source
        guard let newestObserved = radarSequence.newestObservedImage, newestObserved.hasSucceeded else { return }
        
        // If already fetching and source hasn't changed, don't start another unless forced
        if !force {
            if forecastFetchCancellable != nil {
                if let activeSource = activeForecastSourceTimestamp,
                   Calendar.current.isDate(activeSource, equalTo: newestObserved.timestamp, toGranularity: .minute) {
                    return // Already fetching for this source
                }
                // Different source, cancel old fetch
                cancelForecastFetch()
            }
        } else {
            // Force means cancel everything and restart
            cancelForecastFetch()
        }
        
        guard radarSequence.hasLoadingObservedImages == false else { return }

        let forecastPlaceholders = radarSequence.forecastImages(for: newestObserved.timestamp)
        let targets = forecastPlaceholders.filter { data in
            switch data.state {
            case .pending:
                return true
            case .failed where data.shouldRetry:
                return true
            case .loading, .retrying:
                // Should not happen since we cancelled above, but include them
                return true
            case .success:
                // Never re-fetch successful images, even with force
                return false
            default:
                return false
            }
        }

        guard !targets.isEmpty else {
            cancelForecastFetch()
            return
        }

        activeForecastSourceTimestamp = newestObserved.timestamp

        for placeholder in targets {
            // Reset loading/retrying state to pending before starting
            if case .loading = placeholder.state {
                placeholder.state = .pending
            }
            if case .retrying = placeholder.state {
                placeholder.state = .pending
            }

            placeholder.startTime = Date()
            placeholder.attemptCount += 1
            if placeholder.attemptCount > 1 {
                placeholder.state = .retrying(attemptCount: placeholder.attemptCount)
            } else {
                placeholder.state = .loading
            }
        }

        let offsets = Array(Set(targets.compactMap { $0.kind.forecastOffsetMinutes })).sorted()
        guard !offsets.isEmpty else {
            forecastFetchCancellable = nil
            forecastRetryTimer?.invalidate()
            forecastRetryTimer = nil
            return
        }

        let sourceTimestamp = newestObserved.timestamp
        forecastFetchCancellable = networkService.fetchForecastSequence(sourceTimestamp: sourceTimestamp, offsets: offsets)
            .sink(
                receiveCompletion: { [weak self] _ in
                    guard let self = self else { return }
                    
                    // Check for pending forecasts on completion
                    let pending = self.radarSequence.forecastImages(for: sourceTimestamp).filter { data in
                        switch data.state {
                        case .success:
                            return false
                        case .failed:
                            return data.shouldRetry
                        case .pending, .loading, .retrying:
                            return true
                        case .skipped:
                            return false
                        }
                    }

                    self.forecastFetchCancellable = nil

                    if pending.isEmpty {
                        self.forecastRetryTimer?.invalidate()
                        self.forecastRetryTimer = nil
                    } else {
                        self.scheduleForecastRetry()
                    }
                },
                receiveValue: { [weak self] result in
                    guard let self = self else { return }
                    
                    // Verify we're still working with the same source timestamp
                    // If source changed (e.g., user hit reload), ignore these results
                    guard let activeSource = self.activeForecastSourceTimestamp,
                          Calendar.current.isDate(activeSource, equalTo: sourceTimestamp, toGranularity: .minute) else {
                        self.logger.notice("Forecast result discarded - source timestamp changed")
                        return
                    }
                    
                    // Process each forecast result immediately as it arrives
                    guard let placeholder = self.placeholder(for: result) else {
                        self.logger.warning("No placeholder found for forecast result: \(result.timestamp.radarTimestampString)")
                        return
                    }

                    placeholder.endTime = Date()

                    switch result.result {
                    case .success(let image):
                        self.radarSequence.updateImage(placeholder, with: image, fromCache: result.wasFromCache)
                        self.logger.info("Successfully loaded forecast image for \(result.timestamp.radarTimestampString) (\(result.wasFromCache ? "cache" : "network"))")
                    case .failure(let error):
                        self.handleImageFetchError(error, placeholder: placeholder, timestamp: result.timestamp)
                    }
                }
            )
    }

    private func placeholder(for result: RadarImageResult) -> RadarImageData? {
        let targetKey: String
        switch result.kind {
        case .observed:
            targetKey = result.timestamp.radarTimestampString
        case .forecast:
            targetKey = "\(result.sourceTimestamp.radarTimestampString)-\(result.timestamp.radarTimestampString)"
        }

        return radarSequence.images.first { $0.cacheKey == targetKey }
    }

    private func scheduleForecastRetry() {
        forecastRetryTimer?.invalidate()
        forecastRetryTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.forecastRetryDelay, repeats: false) { [weak self] _ in
            self?.startForecastFetchIfNeeded()
        }
    }

    // MARK: - Rendering Coordination

    func overlayDidUpdate(imageTimestamp: Date?) {
        setDisplayedTimestamp(imageTimestamp, deferred: true)
    }

    func userSelectedImage(timestamp: Date?) {
        // Ensure immediate UI update for taps, while keeping SwiftUI warnings away
        setDisplayedTimestamp(timestamp, deferred: false)
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
