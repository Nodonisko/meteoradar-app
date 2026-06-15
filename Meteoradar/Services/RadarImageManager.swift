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

/// Coordinates fetching of the radar image sequence.
///
/// The whole pipeline is driven by a single idempotent `reconcile()` step:
///   1. sync observed placeholders for the newest timestamps,
///   2. anchor the forecast to the newest observed frame that actually loaded,
///   3. fetch whatever is still missing through one sequential network pass.
///
/// Two timers feed `reconcile()`: `updateTimer` pulls the newest image at each
/// publish boundary, and `retryTimer` re-runs while any frame still has retry
/// budget left. Because `NetworkService` dedupes in-flight requests and serves
/// disk cache, calling `reconcile()` repeatedly never causes a double download,
/// which is what lets the logic stay this small.
class RadarImageManager: ObservableObject {
    @Published var radarSequence = RadarImageSequence()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdateTime: Date?

    private let networkService = NetworkService.shared
    private let settingsService = SettingsService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meteoradar", category: "RadarImageManager")

    private var cancellables = Set<AnyCancellable>()
    private var animationTimerCancellable: AnyCancellable?

    /// The single in-flight fetch pass. While non-nil a pass is running and new
    /// `reconcile()` calls only refresh placeholders; the pass re-reconciles when
    /// it completes, so nothing is lost.
    private var fetchCancellable: AnyCancellable?

    /// Fires at the next publish boundary to pull the newest image.
    private var updateTimer: Timer?
    /// Re-runs `reconcile()` after a delay while frames still have retry budget;
    /// re-armed as needed and left idle once everything resolves.
    private var retryTimer: Timer?

    private var lastUsedIntervalMinutes: Int?

    /// The product this manager is operating on. Adopted from the product-change
    /// event payload (never read from the mutable global mid-switch) and threaded
    /// explicitly through the whole pipeline.
    private var currentProductID: String

    /// Publish delay for the current product, used as a soft lower bound so we
    /// don't ping the server before its image can exist.
    private var currentPublishDelaySeconds: Int {
        RadarProductService.shared.product(withID: currentProductID)?.publishDelaySeconds
            ?? RadarSharedConstants.serverLatencyOffsetSeconds
    }

    init() {
        currentProductID = RadarProductService.shared.selectedProduct.id
        setupPublishedForwarding()
        setupSettingsObserver()
        reconcile()
        scheduleNextUpdateTimer()
    }

    deinit {
        stopAllTimers()
        networkService.cancelAllRadarRequests()
    }

    // MARK: - Lifecycle

    func pauseForBackground() {
        stopAnimation()
        stopAllTimers()
        cancelFetch()
    }

    func resumeForForeground() {
        // Returning after a while: realign the timer and jump back to the newest
        // frame (the user expects the latest, not whatever was selected before).
        scheduleNextUpdateTimer()
        refreshRadarImages()
    }

    /// Manual reload: jump back to the newest frame and re-fetch anything missing.
    /// Loaded frames are kept (served from cache), so there's no flash.
    func refreshRadarImages() {
        stopAnimation()
        radarSequence.reset()
        cancelFetch()
        reconcile()
    }

    // MARK: - Animation

    func startAnimation() {
        guard !radarSequence.images.isEmpty else { return }

        guard radarSequence.prepareAnimation() else {
            radarSequence.isAnimating = false
            return
        }

        radarSequence.isAnimating = true

        // Start a fresh timer so the start frame is visible for a full
        // animationInterval before the first transition.
        animationTimerCancellable = Timer.publish(
            every: Constants.Radar.animationInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.advanceAnimationFrame()
        }
    }

    func stopAnimation() {
        radarSequence.isAnimating = false
        animationTimerCancellable = nil
    }

    private func advanceAnimationFrame() {
        guard radarSequence.isAnimating else { return }
        if radarSequence.nextAnimationFrame() {
            stopAnimation()
        }
    }

    // MARK: - Observers

    private func setupPublishedForwarding() {
        radarSequence.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func setupSettingsObserver() {
        // Display interval change: re-fetch with the new spacing.
        settingsService.$radarImageIntervalMinutes
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newInterval in
                guard let self, self.lastUsedIntervalMinutes != newInterval else { return }
                self.logger.info("Radar interval changed to \(newInterval) minutes, refreshing")
                self.cancelFetch()
                self.reconcile()
            }
            .store(in: &cancellables)

        // Image-quality change: the URL (and thus disk-cache filename) differs per
        // quality, so existing placeholders are stale. Rebuild from scratch.
        settingsService.$imageQuality
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.logger.info("Image quality changed, reloading")
                self.stopAnimation()
                self.cancelFetch()
                self.radarSequence.removeAllImages()
                self.reconcile()
            }
            .store(in: &cancellables)

        // Product (country) change: reload the whole sequence. We adopt the ID from
        // the publisher payload, not the global, because @Published emits during
        // willSet when the stored value still reflects the previous product.
        settingsService.$selectedRadarProductID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newProductID in
                guard let self else { return }
                self.logger.info("Radar product changed to \(newProductID, privacy: .public), reloading")
                self.currentProductID = newProductID
                self.stopAnimation()
                self.cancelFetch()
                self.radarSequence.removeAllImages() // never reuse the old product's frames
                self.reconcile()
                self.scheduleNextUpdateTimer() // new product may publish on a different schedule
            }
            .store(in: &cancellables)
    }

    private func scheduleNextUpdateTimer() {
        updateTimer?.invalidate()

        let delay = max(1, Date.utcNow.secondsUntilNextRadarUpdate(publishDelaySeconds: currentPublishDelaySeconds))
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.reconcile()
            self?.scheduleNextUpdateTimer()
        }
        timer.tolerance = min(5, delay * 0.1)
        updateTimer = timer
    }

    // MARK: - Reconcile (the single fetch driver)

    /// Brings the on-screen frame set up to date and kicks off a fetch pass for
    /// anything missing. Safe to call any time, from either timer or a completion.
    private func reconcile() {
        let interval = settingsService.radarImageIntervalMinutes
        lastUsedIntervalMinutes = interval

        let observedTimestamps = Date.radarTimestamps(
            count: Constants.Radar.imageCount,
            intervalMinutes: interval,
            publishDelaySeconds: currentPublishDelaySeconds
        )
        radarSequence.syncObservedPlaceholders(for: observedTimestamps, productID: currentProductID)
        radarSequence.syncForecastPlaceholders(
            newestSource: observedTimestamps.first,
            offsets: Constants.Radar.forecastOffsets(),
            productID: currentProductID
        )

        startFetchPass()
    }

    /// Fetches every frame that is freshly pending. Failed frames are left to the
    /// retry timer so a just-completed pass never re-fires them with no delay.
    private func startFetchPass() {
        guard fetchCancellable == nil else { return }

        let pending = radarSequence.framesPendingFetch
        guard !pending.isEmpty else {
            isLoading = false
            if radarSequence.hasRetryableFrames {
                ensureRetryTimer()
            } else {
                stopRetryTimer()
            }
            updateErrorState()
            return
        }

        isLoading = true
        let specs = pending.map { RadarFrameSpec(kind: $0.kind, sourceTimestamp: $0.sourceTimestamp) }

        // Mark each frame loading only when it reaches the front of the queue, so
        // exactly one frame shows as loading at a time (newest first). This makes
        // the prioritised queue visible instead of lighting every box up at once.
        let queued = pending
        let markStarted: (RadarFrameSpec) -> Void = { [weak self] spec in
            guard let frame = queued.first(where: { $0.frameID == spec.frameID }) else { return }
            self?.markFetchStarted(frame)
        }

        // `fetchFrames` delivers on the main queue, so `onStart`/results stay on
        // main and an all-cached pass completes asynchronously - after this
        // assignment - which is what keeps repeated `reconcile()` calls re-entrant-safe.
        fetchCancellable = networkService.fetchFrames(specs, productID: currentProductID, onStart: markStarted)
            .sink(
                receiveCompletion: { [weak self] _ in self?.handlePassCompletion() },
                receiveValue: { [weak self] result in self?.apply(result) }
            )
    }

    private func markFetchStarted(_ frame: RadarImageData) {
        frame.attemptCount += 1
        frame.state = frame.attemptCount > 1 ? .retrying(attemptCount: frame.attemptCount) : .loading
    }

    /// Applies a single streamed result to its placeholder.
    private func apply(_ result: RadarImageResult) {
        // Drop results for a product we've since switched away from.
        guard result.productID == currentProductID else {
            logger.notice("Discarding stale result for \(result.timestamp.radarTimestampString) from product \(result.productID, privacy: .public)")
            return
        }
        guard let placeholder = radarSequence.placeholder(for: result) else {
            logger.warning("No placeholder for radar result \(result.timestamp.radarTimestampString, privacy: .public)")
            return
        }

        switch result.result {
        case .success(let image):
            // `updateImage` re-anchors the selection (follow-newest / keep the
            // viewed frame), so the manager doesn't touch `currentImageIndex`.
            radarSequence.updateImage(placeholder, with: image, geoBox: result.geoBox)
            errorMessage = nil
            logger.info("Loaded \(String(describing: placeholder.kind), privacy: .public) \(result.timestamp.radarTimestampString, privacy: .public) (\(result.wasFromCache ? "cache" : "network"))")
            if result.geoBox == nil {
                logger.warning("Image \(result.timestamp.radarTimestampString, privacy: .public) (\(result.productID, privacy: .public)) has no GeoBox metadata; using configured product bounds")
            }
        case .failure(let error):
            handleImageFetchError(error, placeholder: placeholder, timestamp: result.timestamp)
        }
    }

    /// Cleans up after a pass and reconciles again: a freshly-loaded observed frame
    /// may have unlocked the forecast anchor (or the cold-start fallback).
    private func handlePassCompletion() {
        fetchCancellable = nil
        lastUpdateTime = Date()

        // A frame still marked loading got no result - fail it so it can retry
        // rather than being stranded (the cause of the old "stuck grey box" bug).
        for frame in radarSequence.images where frame.isLoading {
            let error = RadarPipelineError.missingResult(timestamp: frame.timestamp)
            frame.state = .failed(error, attemptCount: frame.attemptCount)
            frame.lastError = error
            logger.error("No result received for \(frame.timestamp.radarTimestampString, privacy: .public); marking failed")
        }

        reconcile()
    }

    private func handleImageFetchError(_ error: Error, placeholder: RadarImageData, timestamp: Date) {
        // Cancellation isn't a real failure; reset so the next pass can re-fetch.
        if let urlError = error as? URLError, urlError.code == .cancelled {
            placeholder.state = .pending
            logger.notice("Radar fetch cancelled for \(timestamp.radarTimestampString, privacy: .public)")
        } else {
            placeholder.state = .failed(error, attemptCount: placeholder.attemptCount)
            placeholder.lastError = error
            logger.error("Radar fetch failed for \(timestamp.radarTimestampString, privacy: .public) [attempt \(placeholder.attemptCount)]: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Timers & cancellation

    private func ensureRetryTimer() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: Constants.Radar.retryInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.retryTimer = nil
            self.radarSequence.promoteRetryableToPending()
            self.reconcile()
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func stopAllTimers() {
        animationTimerCancellable = nil
        updateTimer?.invalidate()
        updateTimer = nil
        stopRetryTimer()
    }

    /// Cancels the in-flight pass and the underlying downloads, returning any
    /// loading frames to pending so the next reconcile re-fetches them.
    private func cancelFetch() {
        fetchCancellable?.cancel()
        fetchCancellable = nil
        networkService.cancelAllRadarRequests()
        for frame in radarSequence.images where frame.isLoading {
            frame.state = .pending
        }
    }

    private func updateErrorState() {
        // Only surface an error once we've given up with nothing to show.
        if radarSequence.loadedImages.isEmpty, fetchCancellable == nil, !radarSequence.hasRetryableFrames {
            errorMessage = String(localized: "error.service_unavailable")
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
