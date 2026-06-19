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
    
    static func == (lhs: ImageLoadingState, rhs: ImageLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.loading, .loading), (.success, .success):
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

/// Stable identity of a radar frame within a product: its kind (observed, or a
/// forecast at a given offset) plus the 5-minute publish mark it belongs to.
/// Deliberately quality-independent, so a network result always matches its
/// placeholder even if the image-quality setting changed while it was in flight.
/// All source timestamps are radar boundaries, so `Date` equality is exact.
struct RadarFrameID: Hashable {
    let kind: RadarFrameKind
    let source: Date

    init(kind: RadarFrameKind, source: Date) {
        self.kind = kind
        self.source = source.roundedToNearestRadarTime
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

    /// Geographic bounds parsed from the image's `GeoBox` metadata. Drives the
    /// overlay position. `nil` if the loaded image carried no metadata, in which
    /// case the map falls back to the product's configured bounds.
    @Published var geoBox: GeoBounds?
    
    // Loading metadata
    @Published var state: ImageLoadingState = .pending
    @Published var attemptCount: Int = 0
    @Published var lastError: Error?

    /// Stable, quality-independent identity used to match network results back to
    /// this placeholder and to compare frames without `Calendar` date math.
    var frameID: RadarFrameID {
        RadarFrameID(kind: kind, source: sourceTimestamp)
    }

    /// Filename used both as the disk-cache key and as a stable SwiftUI list id.
    var cacheKey: String {
        guard let url = URL(string: urlString) else { return urlString }
        return RadarCacheHelpers.cacheFilename(for: url)
    }
    
    init(timestamp: Date, urlString: String, kind: RadarFrameKind, sourceTimestamp: Date, forecastTimestamp: Date) {
        self.timestamp = timestamp
        self.urlString = urlString
        self.kind = kind
        self.sourceTimestamp = sourceTimestamp
        self.forecastTimestamp = forecastTimestamp
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
    
    /// The forecast source currently chosen for display: the newest source that
    /// has at least one successfully-loaded frame - NOT the newest observed
    /// frame's source. This keeps the previous forecast on screen until the new
    /// one produces its first frame, and can never get ahead of real data because
    /// a forecast source only has successes after its observed frame loaded.
    /// `nil` until a forecast frame has loaded.
    var displayedForecastSource: Date? {
        images
            .filter { $0.hasSucceeded && $0.kind.isForecast }
            .map { $0.sourceTimestamp }
            .max()
    }

    // Only successfully loaded images for animation (skips failed ones)
    // Sorted newest first so index 0 shows the latest image
    var loadedImages: [RadarImageData] {
        let observed = images
            .filter { $0.hasSucceeded && $0.kind.isObserved }
            .sorted { $0.timestamp > $1.timestamp }

        guard let forecastSource = displayedForecastSource else {
            return observed
        }
        let forecasts = images
            .filter { $0.hasSucceeded && $0.kind.isForecast && $0.sourceTimestamp.roundedToNearestRadarTime == forecastSource.roundedToNearestRadarTime }
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

    /// Frames that make up the progress bar / timeline UI, in display order:
    /// observed oldest → newest, then the forecast frames for exactly ONE source
    /// by ascending offset. The number of boxes is fixed (observed count +
    /// forecast offset count): forecast placeholders are always seeded for the
    /// newest generation, and since every generation we create carries its full
    /// set of offsets, picking a single source always yields the same number of
    /// forecast slots regardless of load state.
    ///
    /// The order is built structurally (observed group, then forecast group) and
    /// NOT by raw `timestamp`: a retained previous generation lags ~5 min on a
    /// normal handoff and can be far more stale right after a long background, so
    /// its absolute forecast times (`source + offset`) overlap the current
    /// observed window. Sorting the combined list by `timestamp` would then
    /// interleave those forecast boxes among the observed ones - the timeline
    /// must always show observed first, then a single coherent forecast tail.
    var timelineFrames: [RadarImageData] {
        let observed = images
            .filter { $0.kind.isObserved }
            .sorted { $0.timestamp < $1.timestamp }
        guard let source = timelineForecastSource else { return observed }
        let forecasts = images
            .filter { $0.kind.isForecast && $0.sourceTimestamp.roundedToNearestRadarTime == source }
            .sorted { ($0.kind.forecastOffsetMinutes ?? 0) < ($1.kind.forecastOffsetMinutes ?? 0) }
        return observed + forecasts
    }

    /// The single forecast generation the timeline displays:
    /// 1. what we've actually loaded (`displayedForecastSource`), else
    /// 2. the newest generation we can still show - its source is at or before the
    ///    newest loaded observed (so it isn't gated out of fetching) and it isn't
    ///    fully failed. This deliberately SKIPS a newest generation whose observed
    ///    never loaded (e.g. the newest mark 404'd past its publish delay): that
    ///    forecast is gated forever, so picking it would only show permanent dead
    ///    boxes instead of the forecast for the observed we actually have.
    /// 3. before any observed loads (true cold start), the newest source present.
    /// Always resolves to a source with a full set of offsets, so the box count
    /// never changes as frames load.
    private var timelineForecastSource: Date? {
        if let displayed = displayedForecastSource {
            return displayed.roundedToNearestRadarTime
        }
        let forecastSources = Set(
            images.filter { $0.kind.isForecast }
                .map { $0.sourceTimestamp.roundedToNearestRadarTime }
        )
        if let newestLoaded = newestSuccessfulObservedImage?.timestamp.roundedToNearestRadarTime {
            let showable = forecastSources.filter {
                $0 <= newestLoaded && forecastGenerationIsLive(source: $0)
            }
            if let best = showable.max() { return best }
        }
        return forecastSources.max()
    }

    /// A forecast generation is still worth showing while any of its frames has
    /// loaded, is loading, or still holds retry budget. Once every frame has
    /// permanently failed the generation is dead and must not win the timeline.
    private func forecastGenerationIsLive(source: Date) -> Bool {
        let frames = forecastImages(for: source)
        guard !frames.isEmpty else { return false }
        return frames.contains { $0.hasSucceeded || $0.isLoading || $0.shouldRetry }
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

    /// Geographic bounds of the currently displayed frame, parsed from its
    /// `GeoBox` metadata. `nil` until a frame with metadata is displayed.
    var currentGeoBox: GeoBounds? {
        currentImageData?.geoBox
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

    // MARK: - Selection preservation

    /// Re-anchors `currentImageIndex` after `loadedImages` changed so the user
    /// keeps viewing the same frame. `currentImageIndex` is positional, but
    /// `loadedImages` reshuffles as frames load (a new observed shifts everything
    /// down, a forecast handoff swaps the whole forecast tail), so the raw index
    /// would otherwise drift onto a neighbouring frame.
    ///
    /// Matching is by `RadarFrameID` (kind + source), never by timestamp: an
    /// observed and a forecast frame can share a wall-clock time, and timestamp
    /// matching would jump a forecast selection onto the observed frame.
    ///
    /// - `wasOnNewest`: stay pinned to newest (follow-newest) if we were on it.
    /// - exact `frameID`: same observed moment / same forecast frame still shown.
    /// - forecast fallback: the generation rolled over, so keep the nearest
    ///   forecast offset in the now-displayed generation rather than snapping to
    ///   newest.
    /// - otherwise: the frame is gone (rolled off the window) -> newest.
    private func restoreSelection(previous: RadarImageData?, wasOnNewest: Bool) {
        guard !wasOnNewest, let previous else {
            currentImageIndex = 0
            return
        }
        let frames = loadedImages
        if let index = frames.firstIndex(where: { $0.frameID == previous.frameID }) {
            currentImageIndex = index
            return
        }
        if let offset = previous.kind.forecastOffsetMinutes,
           let index = nearestForecastIndex(to: offset, in: frames) {
            currentImageIndex = index
            return
        }
        currentImageIndex = 0
    }

    /// Index of the loaded forecast frame whose offset is closest to `offset`,
    /// used to keep a forecast selection in place across a generation handoff
    /// when the exact offset hasn't loaded yet in the new generation.
    private func nearestForecastIndex(to offset: Int, in frames: [RadarImageData]) -> Int? {
        frames.enumerated()
            .filter { $0.element.kind.isForecast }
            .min { lhs, rhs in
                abs((lhs.element.kind.forecastOffsetMinutes ?? 0) - offset)
                    < abs((rhs.element.kind.forecastOffsetMinutes ?? 0) - offset)
            }?
            .offset
    }
    
    /// Brings the observed frames in line with `timestamps` (newest first),
    /// reusing existing frames (in any state, so retries/successes are preserved)
    /// and creating pending placeholders for new ones. Forecast frames are NOT
    /// created here - they're seeded by the manager only for an observed source
    /// that has actually loaded, which enforces "observed before forecast".
    ///
    /// Idempotent: if nothing structurally changed the `images` array is left
    /// untouched, so this can be called on every reconcile without churning the UI
    /// or resetting in-flight retry state.
    func syncObservedPlaceholders(for timestamps: [Date], productID: String) {
        var rebuilt: [RadarImageData] = []

        for timestamp in timestamps {
            let targetID = RadarFrameID(kind: .observed, source: timestamp)
            if let existing = images.first(where: { $0.frameID == targetID }) {
                rebuilt.append(existing)
            } else {
                let urlString = Constants.Radar.observedURL(for: timestamp, quality: SettingsService.shared.imageQuality, productID: productID)
                rebuilt.append(RadarImageData(
                    timestamp: timestamp,
                    urlString: urlString,
                    kind: .observed,
                    sourceTimestamp: timestamp,
                    forecastTimestamp: timestamp
                ))
            }
        }

        // Carry over forecast frames whose source is still relevant: the current
        // observed window (the anchor's forecasts live here), the previous-of-newest
        // generation (kept warm for the 5-minute handoff), and whatever we're
        // displaying now (e.g. a cold-start fallback that lags the newest observed).
        var relevantSources = Set(timestamps.map { $0.roundedToNearestRadarTime })
        if let newest = timestamps.first { relevantSources.insert(newest.previousRadarTime.roundedToNearestRadarTime) }
        if let displayed = displayedForecastSource { relevantSources.insert(displayed.roundedToNearestRadarTime) }
        let retainedForecasts = images.filter { data in
            data.kind.isForecast && relevantSources.contains(data.sourceTimestamp.roundedToNearestRadarTime)
        }
        rebuilt.append(contentsOf: retainedForecasts)

        // Skip the assignment when nothing changed, to avoid needless UI updates.
        if rebuilt.count == images.count && zip(rebuilt, images).allSatisfy({ $0 === $1 }) {
            return
        }

        let previousSelection = currentImageData
        let wasOnNewest = currentImageIndex == 0
        images = rebuilt
        restoreSelection(previous: previousSelection, wasOnNewest: wasOnNewest)
    }
    
    /// Creates a single forecast placeholder for a given source + offset.
    private func makeForecastPlaceholder(source: Date, offset: Int, productID: String) -> RadarImageData {
        let forecastTimestamp = source.addingTimeInterval(TimeInterval(offset * 60))
        let urlString = Constants.Radar.forecastURL(for: source, offsetMinutes: offset, quality: SettingsService.shared.imageQuality, productID: productID)
        return RadarImageData(
            timestamp: forecastTimestamp,
            urlString: urlString,
            kind: .forecast(offsetMinutes: offset),
            sourceTimestamp: source,
            forecastTimestamp: forecastTimestamp
        )
    }

    /// Seeds the forecast placeholders for a reconcile pass. Owns all forecast
    /// generation policy so the manager just calls this once:
    ///
    /// 1. Always seed the newest generation's slots so the timeline shows a fixed
    ///    number of forecast boxes from the start. Fetching them is still gated on
    ///    the matching observed frame existing (see `framesPendingFetch`), so this
    ///    never fetches a forecast before its observed frame.
    /// 2. Cold-start fallback: if the newest generation's forecast isn't generated
    ///    yet and nothing is on screen, also seed the previous generation (which the
    ///    server keeps) so we show that instead of red boxes until the newest
    ///    arrives. `displayedForecastSource` shows whichever loads and promotes to
    ///    the newest once it does.
    func syncForecastPlaceholders(newestSource: Date?, offsets: [Int], productID: String) {
        guard let newestSource else { return }
        ensureForecastPlaceholders(source: newestSource, offsets: offsets, productID: productID)

        if let anchor = newestSuccessfulObservedImage?.timestamp, shouldFallbackForecast(anchor: anchor) {
            ensureForecastPlaceholders(source: anchor.previousRadarTime, offsets: offsets, productID: productID)
        }

        // Failed-newest re-anchor: if the newest mark didn't load (e.g. it 404'd
        // past its publish delay) but an older observed did, seed the forecast for
        // that newest LOADED observed right away - do NOT wait for the newest mark
        // to burn its retry budget. The newest mark's own forecast is gated until
        // it loads anyway, so leaving the user staring at disabled boxes for the
        // whole ~50s retry window, when we already hold a real observed image and
        // the server keeps older generations (~24h), is exactly the lag we avoid.
        // If the newest mark later succeeds on retry, follow-newest promotes its
        // generation over this one.
        if let loaded = newestSuccessfulObservedImage?.timestamp,
           loaded.roundedToNearestRadarTime != newestSource.roundedToNearestRadarTime {
            ensureForecastPlaceholders(source: loaded, offsets: offsets, productID: productID)
        }
    }

    /// Ensures forecast placeholders exist for the given source, creating any that
    /// are missing. Forecast frames are never created by `syncObservedPlaceholders`,
    /// so they only ever exist for a source `syncForecastPlaceholders` seeded.
    private func ensureForecastPlaceholders(source: Date, offsets: [Int], productID: String) {
        let missing = offsets.filter { offset in
            let id = RadarFrameID(kind: .forecast(offsetMinutes: offset), source: source)
            return !images.contains { $0.frameID == id }
        }
        guard !missing.isEmpty else { return }
        images.append(contentsOf: missing.map { makeForecastPlaceholder(source: source, offset: $0, productID: productID) })
    }

    // MARK: - Fetch coordination

    /// Frames ready to be fetched right now: freshly created placeholders that
    /// haven't been attempted. Failed frames are NOT included here - they wait for
    /// the retry timer to promote them, so a completed pass never re-fires them
    /// immediately. Ordered observed-newest-first, then forecast by offset, so the
    /// frames the user is most likely looking at load first.
    ///
    /// Forecast frames are gated: we only fetch a generation that's at or before
    /// the newest observed image we actually have. A generation is published as a
    /// unit (observed image + its forecast), so until its observed image exists the
    /// forecast can't either - this is what keeps "observed before forecast" true
    /// even though the forecast placeholders are seeded up front for display.
    var framesPendingFetch: [RadarImageData] {
        let newestLoadedObserved = images
            .filter { $0.kind.isObserved && $0.hasSucceeded }
            .map { $0.timestamp }
            .max()

        return images
            .filter { frame in
                guard frame.state == .pending else { return false }
                if frame.kind.isForecast {
                    guard let newestLoadedObserved else { return false }
                    return frame.sourceTimestamp <= newestLoadedObserved
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.kind.sortPriority != rhs.kind.sortPriority {
                    return lhs.kind.sortPriority < rhs.kind.sortPriority
                }
                if lhs.kind.isObserved {
                    return lhs.timestamp > rhs.timestamp // newest observed first
                }
                return lhs.forecastTimestamp < rhs.forecastTimestamp // nearest forecast first
            }
    }

    /// Any failed frame that still has retry budget left.
    var hasRetryableFrames: Bool {
        images.contains { $0.hasFailed && $0.shouldRetry }
    }

    /// Moves retryable failures back to `pending` so the next fetch pass picks
    /// them up. Attempt counts are preserved so the budget keeps shrinking.
    func promoteRetryableToPending() {
        for image in images where image.hasFailed && image.shouldRetry {
            image.state = .pending
            image.lastError = nil
        }
    }

    /// Clears the retry budget of every failed frame still in the window,
    /// returning them to `pending` so the next fetch pass attempts them again.
    /// Triggered only by explicit "try again" moments - the publish boundary
    /// (update timer), manual reload, and foreground - NEVER from the reconcile
    /// loop itself, which would turn the bounded fast-retry into a tight no-delay
    /// loop.
    ///
    /// Without this, a frame that 404'd only because the server hadn't generated
    /// it yet (typical for the newest frame on a late-publishing product) exhausts
    /// its ~50s fast-retry budget and is then abandoned: `framesPendingFetch`
    /// skips non-pending frames and `promoteRetryableToPending` skips
    /// budget-exhausted ones, so neither a passing publish cycle nor the reload
    /// button revives it - only an app relaunch (which rebuilds the sequence).
    func requeueFailedFrames() {
        for image in images where image.hasFailed {
            image.state = .pending
            image.attemptCount = 0
            image.lastError = nil
        }
    }

    /// Locates the placeholder a network result belongs to by its stable frame
    /// identity (kind + source mark). The manager has already filtered the result
    /// to the current product, and the sequence only holds current-product frames.
    func placeholder(for result: RadarImageResult) -> RadarImageData? {
        images.first { $0.frameID == result.frameID }
    }

    /// True when the newest forecast generation has been tried but isn't available
    /// yet and nothing is on screen - the trigger for the cold-start fallback to
    /// the previous generation (which the server keeps until the new one exists).
    func shouldFallbackForecast(anchor: Date) -> Bool {
        guard displayedForecastSource == nil else { return false }
        let frames = forecastImages(for: anchor)
        guard !frames.isEmpty,
              !frames.contains(where: { $0.hasSucceeded }),
              !frames.contains(where: { $0.isLoading }) else { return false }
        return frames.contains { $0.attemptCount > 0 }
    }

    /// The newest observed frame that has actually loaded. Used to anchor the
    /// forecast to real data rather than a not-yet-arrived placeholder.
    var newestSuccessfulObservedImage: RadarImageData? {
        return images
            .filter { $0.kind.isObserved && $0.hasSucceeded }
            .max { $0.timestamp < $1.timestamp }
    }
    
    private func forecastImages(for sourceTimestamp: Date) -> [RadarImageData] {
        images.filter { data in
            data.kind.isForecast && data.sourceTimestamp.roundedToNearestRadarTime == sourceTimestamp.roundedToNearestRadarTime
        }
    }

    /// Marks a placeholder loaded with its decoded image and parsed bounds.
    /// Loading a frame changes `loadedImages` (a new observed shifts the list, the
    /// first frame of a new generation swaps the forecast tail), so the selection
    /// is re-anchored to keep the user on the frame they were viewing.
    func updateImage(_ imageData: RadarImageData, with image: UIImage, geoBox: GeoBounds?) {
        let previousSelection = currentImageData
        let wasOnNewest = currentImageIndex == 0
        imageData.image = image
        imageData.geoBox = geoBox
        imageData.state = .success
        imageData.attemptCount = 0
        imageData.lastError = nil

        // Follow-newest, including from a forecast: when a fresh observed frame
        // becomes the newest available and the user is at the leading edge of the
        // timeline (newest observed, or any forecast - i.e. the "future"), jump to
        // it. Scrubbing back to an older observed frame opts out and keeps that
        // position. Suppressed while animating so it doesn't fight the play cursor.
        let arrivedNewestObserved = imageData.kind.isObserved && imageData === loadedImages.first
        let wasAtLeadingEdge = wasOnNewest || (previousSelection?.kind.isForecast ?? false)
        if arrivedNewestObserved && wasAtLeadingEdge && !isAnimating {
            currentImageIndex = 0
            return
        }

        restoreSelection(previous: previousSelection, wasOnNewest: wasOnNewest)
    }
    
    /// Removes all frames. Used when the radar product changes - frames from the
    /// previous product must not be reused by timestamp for the new one.
    func removeAllImages() {
        images = []
        currentImageIndex = 0
        isAnimating = false
    }

}
