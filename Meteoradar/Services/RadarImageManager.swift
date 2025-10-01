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
    private var forecastFetchCancellable: AnyCancellable?
    private var activeForecastSourceTimestamp: Date?
    private var forecastRetryTimer: Timer?
    
    
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
        fetchLatestRadarImages()
    }
    
    func cancelAllFetches() {
        networkService.cancelAllRadarRequests()
        forecastFetchCancellable?.cancel()
        forecastFetchCancellable = nil
        forecastRetryTimer?.invalidate()
        forecastRetryTimer = nil
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
        let forecastOffsets = Constants.Radar.forecastOffsets()
        radarSequence.createPlaceholders(for: timestamps, forecastOffsets: forecastOffsets)
        activeForecastSourceTimestamp = timestamps.first
        forecastFetchCancellable?.cancel()
        forecastFetchCancellable = nil
        forecastRetryTimer?.invalidate()
        forecastRetryTimer = nil
        
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
                $0.kind.isObserved && Calendar.current.isDate($0.timestamp, equalTo: radarResult.timestamp, toGranularity: .minute) 
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
                $0.kind.isObserved && Calendar.current.isDate($0.timestamp, equalTo: timestamp, toGranularity: .minute)
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
            if radarSequence.hasLoadingObservedImages == false {
                startForecastFetchIfNeeded()
            }
        } else if !fetchErrors.isEmpty {
            // If observed fetch failed entirely, ensure forecast retry is cancelled
            forecastFetchCancellable?.cancel()
            forecastFetchCancellable = nil
            forecastRetryTimer?.invalidate()
            forecastRetryTimer = nil
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
        forecastRetryTimer?.invalidate()
        animationTimer = nil
        updateTimer = nil
        retryTimer = nil
        forecastRetryTimer = nil
    }

    private func startForecastFetchIfNeeded(force: Bool = false) {
        if !force && forecastFetchCancellable != nil { return }
        guard let newestObserved = radarSequence.newestObservedImage, newestObserved.hasSucceeded else { return }
        guard radarSequence.hasLoadingObservedImages == false else { return }

        let forecastPlaceholders = radarSequence.forecastImages(for: newestObserved.timestamp)
        let targets = forecastPlaceholders.filter { data in
            switch data.state {
            case .pending:
                return true
            case .failed where data.shouldRetry:
                return true
            case .loading, .retrying:
                return forecastFetchCancellable == nil || force
            case .success:
                return force
            default:
                return false
            }
        }

        guard !targets.isEmpty else {
            forecastFetchCancellable = nil
            forecastRetryTimer?.invalidate()
            forecastRetryTimer = nil
            return
        }

        activeForecastSourceTimestamp = newestObserved.timestamp

        for placeholder in targets {
            if force {
                placeholder.image = nil
                placeholder.startTime = nil
                placeholder.endTime = nil
                placeholder.attemptCount = 0
                placeholder.state = .pending
                placeholder.lastError = nil
            }

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

        forecastFetchCancellable = networkService.fetchForecastSequence(sourceTimestamp: newestObserved.timestamp, offsets: offsets)
            .sink(
                receiveCompletion: { [weak self] _ in
                    self?.forecastFetchCancellable = nil
                },
                receiveValue: { [weak self] results in
                    guard let self = self else { return }
                    for result in results {
                        guard let placeholder = self.placeholder(for: result) else {
                            continue
                        }

                        placeholder.endTime = Date()

                        switch result.result {
                        case .success(let image):
                            self.radarSequence.updateImage(placeholder, with: image, fromCache: result.wasFromCache)
                        case .failure(let error):
                            self.handleImageFetchError(error, placeholder: placeholder, timestamp: result.timestamp)
                        }
                    }

                    let pending = self.radarSequence.forecastImages(for: newestObserved.timestamp).filter { data in
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
