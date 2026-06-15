//
//  NetworkService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import Foundation
import UIKit
import Combine
import OSLog

// MARK: - Radar-Specific Types

struct RadarImageResult {
    /// Product the image was fetched for. Consumers must discard results whose
    /// product no longer matches the current selection (stale in-flight requests).
    let productID: String
    let timestamp: Date
    let sourceTimestamp: Date
    let kind: RadarFrameKind
    let forecastOffsetMinutes: Int?
    let result: Result<UIImage, Error>
    /// Geographic bounds parsed from the image's `GeoBox` metadata, or `nil` if
    /// the image carried none (caller falls back to configured product bounds).
    let geoBox: GeoBounds?
    let loadTime: TimeInterval?
    let wasFromCache: Bool
}

/// A single radar frame to fetch. Lets `fetchFrames` pull observed and forecast
/// frames through one sequential pipeline instead of two specialized methods.
struct RadarFrameSpec {
    let kind: RadarFrameKind
    /// Source (publish) timestamp. For observed frames this equals the frame's
    /// own timestamp; for forecasts it's the observed image the forecast is based on.
    let sourceTimestamp: Date

    var frameID: RadarFrameID {
        RadarFrameID(kind: kind, source: sourceTimestamp)
    }
}

extension RadarImageResult {
    /// Stable identity used to match this result back to its placeholder.
    var frameID: RadarFrameID {
        RadarFrameID(kind: kind, source: sourceTimestamp)
    }
}

// MARK: - Network Service

class NetworkService: NSObject, URLSessionDataDelegate {
    static let shared = NetworkService()
    
    private var session: URLSession!
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meteoradar", category: "NetworkService")
    private let cache = FileSystemImageCache.shared
    
    // Radar-specific request deduplication by product + timestamp
    private struct ActiveRequestKey: Hashable {
        let productID: String
        let kind: RadarFrameKind
        let sourceTimestamp: Date
        let targetTimestamp: Date
        let offsetMinutes: Int?
    }
    private var activeRadarRequests: [ActiveRequestKey: AnyPublisher<RadarImageResult, Never>] = [:]
    // Underlying URLSession tasks so cancelAllRadarRequests can actually stop
    // in-flight downloads (saves data when switching products)
    private var activeRadarTasks: [ActiveRequestKey: URLSessionDataTask] = [:]
    // Recursive: task registration happens inside the eagerly-executed Future body
    // while fetchRadarFrame still holds the lock
    private let requestLock = NSRecursiveLock()
    
    private override init() {
        super.init()
        
        // Configure URLSession for better performance and HTTP/3 support
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.Network.radarRequestTimeout
        
        // Create session with self as delegate to enable HTTP/3 support
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Radar-Specific API
    
    /// Fetch radar image for specific timestamp with deduplication and error handling
    func fetchRadarImage(for timestamp: Date, productID: String) -> AnyPublisher<RadarImageResult, Never> {
        return fetchRadarFrame(kind: .observed, sourceTimestamp: timestamp, targetTimestamp: timestamp, offsetMinutes: nil, productID: productID)
    }
    
    func fetchForecastImage(sourceTimestamp: Date, offsetMinutes: Int, productID: String) -> AnyPublisher<RadarImageResult, Never> {
        let targetTimestamp = sourceTimestamp.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        let kind = RadarFrameKind.forecast(offsetMinutes: offsetMinutes)
        return fetchRadarFrame(kind: kind, sourceTimestamp: sourceTimestamp, targetTimestamp: targetTimestamp, offsetMinutes: offsetMinutes, productID: productID)
    }
    
    private func fetchRadarFrame(kind: RadarFrameKind, sourceTimestamp: Date, targetTimestamp: Date, offsetMinutes: Int?, productID: String) -> AnyPublisher<RadarImageResult, Never> {
        requestLock.lock()
        defer { requestLock.unlock() }
        
        // Return existing request if already active
        let key = ActiveRequestKey(productID: productID, kind: kind, sourceTimestamp: sourceTimestamp, targetTimestamp: targetTimestamp, offsetMinutes: offsetMinutes)
        if let existingRequest = activeRadarRequests[key] {
            return existingRequest
        }
        
        // Generate URL for timestamp with quality setting
        let quality = SettingsService.shared.imageQuality
        let urlString: String
        switch kind {
        case .observed:
            urlString = Constants.Radar.observedURL(for: targetTimestamp, quality: quality, productID: productID)
        case .forecast(let offset):
            urlString = Constants.Radar.forecastURL(for: sourceTimestamp, offsetMinutes: offset, quality: quality, productID: productID)
        }
        guard let url = URL(string: urlString) else {
            logger.error("Invalid radar URL for kind: \(String(describing: kind), privacy: .public), source: \(sourceTimestamp, privacy: .public), target: \(targetTimestamp, privacy: .public)")
            let errorResult = RadarImageResult(
                productID: productID,
                timestamp: targetTimestamp,
                sourceTimestamp: sourceTimestamp,
                kind: kind,
                forecastOffsetMinutes: offsetMinutes,
                result: .failure(NetworkError.invalidURL),
                geoBox: nil,
                loadTime: 0,
                wasFromCache: false
            )
            return Just(errorResult).eraseToAnyPublisher()
        }

        let cacheKey = RadarCacheHelpers.cacheFilename(for: url)
        if Constants.Radar.cacheEnabled, let cachedData = cache.cachedData(for: cacheKey) {
            if let cachedImage = UIImage(data: cachedData) {
                logger.debug("Cache hit for key: \(cacheKey, privacy: .public)")
                let result = RadarImageResult(
                    productID: productID,
                    timestamp: targetTimestamp,
                    sourceTimestamp: sourceTimestamp,
                    kind: kind,
                    forecastOffsetMinutes: offsetMinutes,
                    result: .success(cachedImage),
                    geoBox: GeoBounds(pngData: cachedData),
                    loadTime: 0,
                    wasFromCache: true
                )
                return Just(result).eraseToAnyPublisher()
            } else {
                // Corrupt cache entry: drop it and fall through to a fresh fetch.
                logger.notice("Discarding undecodable cache entry for key: \(cacheKey, privacy: .public)")
                cache.removeCached(for: cacheKey)
            }
        }
        
        // Create radar-specific request
        let startTime = Date()
        let request = createRadarRequest(for: url, requestKey: key, productID: productID, kind: kind, sourceTimestamp: sourceTimestamp, targetTimestamp: targetTimestamp, offsetMinutes: offsetMinutes, startTime: startTime)
            .handleEvents(
                receiveCompletion: { [weak self] _ in
                    // Clean up when done
                    self?.requestLock.lock()
                    self?.activeRadarRequests.removeValue(forKey: key)
                    self?.requestLock.unlock()
                }
            )
            .share()
            .eraseToAnyPublisher()
        
        activeRadarRequests[key] = request
        return request
    }
    
    /// Create the actual radar network request
    private func createRadarRequest(for url: URL, requestKey: ActiveRequestKey, productID: String, kind: RadarFrameKind, sourceTimestamp: Date, targetTimestamp: Date, offsetMinutes: Int?, startTime: Date) -> AnyPublisher<RadarImageResult, Never> {
        // Create URLRequest with HTTP/3 support
        // Use appropriate cache policy based on cacheEnabled setting
        let cachePolicy: URLRequest.CachePolicy = Constants.Radar.cacheEnabled ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: Constants.Network.radarRequestTimeout)
        request.assumesHTTP3Capable = true
        
        // Create a Future publisher that gives us access to the URLSessionTask
        // so we can configure HTTP/3-specific properties
        return Future<(Data, URLResponse), Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NetworkError.invalidURL))
                return
            }
            
            let task = self.session.dataTask(with: request) { [weak self] data, response, error in
                // Unregister the task once it finishes (or is cancelled)
                if let self = self {
                    self.requestLock.lock()
                    self.activeRadarTasks.removeValue(forKey: requestKey)
                    self.requestLock.unlock()
                }
                
                if let error = error {
                    promise(.failure(error))
                } else if let data = data, let response = response {
                    self?.logger.info("Network fetch completed for \(String(describing: kind), privacy: .public) image: \(targetTimestamp.radarTimestampString, privacy: .public) (\(data.count) bytes)")
                    promise(.success((data, response)))
                } else {
                    promise(.failure(NetworkError.invalidImageData))
                }
            }
            
            // Configure HTTP/3 priority and delivery preferences on the task
            // Radar images must be fully downloaded before display (can't render partial PNG)
            task.prefersIncrementalDelivery = false
            
            // Set priority based on frame type and recency
            task.priority = self.determinePriority(for: kind, targetTimestamp: targetTimestamp)
            
            // Register so cancelAllRadarRequests can cancel the download
            self.requestLock.lock()
            self.activeRadarTasks[requestKey] = task
            self.requestLock.unlock()
            
            // Log network fetch start
            self.logger.info("Network fetch started for \(String(describing: kind), privacy: .public) image: \(targetTimestamp.radarTimestampString, privacy: .public)")
            
            task.resume()
        }
        .eraseToAnyPublisher()
            .tryMap { data, response -> (image: UIImage, data: Data) in
                // Check HTTP status code first
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    
                    // Try to extract error message from response body
                    let responseMessage: String? = {
                        guard statusCode >= 400 else { return nil }
                        // Try to parse as string, limit to first 200 chars to avoid huge messages
                        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !text.isEmpty {
                            return String(text.prefix(200))
                        }
                        return nil
                    }()
                    
                    // Handle specific error codes with clear messages
                    switch statusCode {
                    case 200..<300:
                        break // Success, continue to image parsing
                    case 404:
                        throw NetworkError.notFound
                    case 503:
                        throw NetworkError.serviceUnavailable
                    default:
                        throw NetworkError.httpError(statusCode: statusCode, message: responseMessage)
                    }
                }
                
                // Decode once; carry the original bytes alongside so we can cache
                // them verbatim and parse the embedded GeoBox metadata.
                guard let image = UIImage(data: data) else {
                    throw NetworkError.invalidImageData
                }
                return (image: image, data: data)
            }
            .handleEvents(receiveOutput: { [weak self] _, data in
                // Cache the original, validated bytes (preserves metadata).
                guard let self = self else { return }
                if Constants.Radar.cacheEnabled {
                    let cacheKey = RadarCacheHelpers.cacheFilename(for: url)
                    self.cache.store(data: data, for: cacheKey)
                    self.logger.debug("Cached image for key: \(cacheKey, privacy: .public)")
                }
            })
            .map { image, data in
                RadarImageResult(
                    productID: productID,
                    timestamp: targetTimestamp,
                    sourceTimestamp: sourceTimestamp,
                    kind: kind,
                    forecastOffsetMinutes: offsetMinutes,
                    result: .success(image),
                    geoBox: GeoBounds(pngData: data),
                    loadTime: Date().timeIntervalSince(startTime),
                    wasFromCache: false
                )
            }
            .catch { [weak self] error -> AnyPublisher<RadarImageResult, Never> in
                self?.logger.error("Radar request failed for URL: \(url.absoluteString, privacy: .public), kind: \(String(describing: kind), privacy: .public), source: \(sourceTimestamp, privacy: .public), target: \(targetTimestamp, privacy: .public), error: \(String(describing: error), privacy: .public)")
                return Just(RadarImageResult(
                    productID: productID,
                    timestamp: targetTimestamp,
                    sourceTimestamp: sourceTimestamp,
                    kind: kind,
                    forecastOffsetMinutes: offsetMinutes,
                    result: .failure(error),
                    geoBox: nil,
                    loadTime: Date().timeIntervalSince(startTime),
                    wasFromCache: false
                ))
                .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// Fetch a mixed list of radar frames one at a time, streaming each result as
    /// it completes. `maxPublishers: .max(1)` makes this a strict queue: only one
    /// request is ever in flight, processed in the order given (callers pass them
    /// newest-first), so on a slow link the most important frame downloads first.
    /// Already-cached or in-flight frames are deduped/served by `fetchRadarFrame`.
    ///
    /// `onStart` fires for each frame exactly when its turn in the queue begins,
    /// letting the caller reflect the queue in the UI (one frame loading at a time)
    /// instead of marking everything at once.
    ///
    /// Each frame's result is hopped onto the main queue here (the single place
    /// that owns this guarantee). That keeps `onStart`/results on the main thread
    /// as the queue advances, and makes an all-cached pass complete asynchronously
    /// so the caller's subscription is fully assigned before it sees completion.
    func fetchFrames(
        _ frames: [RadarFrameSpec],
        productID: String,
        onStart: ((RadarFrameSpec) -> Void)? = nil
    ) -> AnyPublisher<RadarImageResult, Never> {
        return frames.publisher
            .flatMap(maxPublishers: .max(1)) { frame -> AnyPublisher<RadarImageResult, Never> in
                onStart?(frame)
                let request: AnyPublisher<RadarImageResult, Never>
                switch frame.kind {
                case .observed:
                    request = self.fetchRadarImage(for: frame.sourceTimestamp, productID: productID)
                case .forecast(let offset):
                    request = self.fetchForecastImage(sourceTimestamp: frame.sourceTimestamp, offsetMinutes: offset, productID: productID)
                }
                return request
                    .receive(on: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// Cancel all active radar requests and reset state.
    /// Cancels the underlying downloads too, so stale in-flight images
    /// (e.g. from a previous product) never arrive and waste no data.
    func cancelAllRadarRequests() {
        requestLock.lock()
        let tasks = Array(activeRadarTasks.values)
        activeRadarTasks.removeAll()
        activeRadarRequests.removeAll()
        requestLock.unlock()
        
        for task in tasks {
            task.cancel()
        }
    }
    
    // MARK: - HTTP/3 Priority Management
    
    /// Determine HTTP/3 priority based on frame type and recency
    /// Returns Float 0.0-1.0 where higher values = higher priority
    /// Maps to HTTP/3 urgency levels (0-7, inverted: 0=urgent, 7=background)
    private func determinePriority(for kind: RadarFrameKind, targetTimestamp: Date) -> Float {
        let now = Date()
        let age = now.timeIntervalSince(targetTimestamp)
        
        switch kind {
        case .observed:
            // Recent observed frames are highest priority (user sees immediately)
            if age < 300 { // Last 5 minutes
                return URLSessionTask.highPriority // 1.0 (urgency 0-1: critical)
            } else if age < 1800 { // Last 30 minutes
                return URLSessionTask.defaultPriority // 0.5 (urgency 3-4: normal)
            } else {
                return URLSessionTask.lowPriority // 0.0 (urgency 6-7: background/historical)
            }
            
        case .forecast:
            // Forecast frames are lower priority than current observed data
            // but still more important than old historical data
            return URLSessionTask.defaultPriority // 0.5 (urgency 3-4: normal)
        }
    }
    
    // MARK: - URLSessionDataDelegate
    
    /// Monitor network protocol usage (HTTP/1.1, HTTP/2, HTTP/3)
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let protocols = metrics.transactionMetrics.map { $0.networkProtocolName ?? "-" }
        logger.debug("Network protocols used: \(protocols.joined(separator: ", "), privacy: .public)")
    }
}

// MARK: - Error Types

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidImageData
    case httpError(statusCode: Int, message: String?)
    case notFound
    case serviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "error.invalid_url")
        case .invalidImageData:
            return String(localized: "error.invalid_image_data")
        case .httpError(let statusCode, let message):
            if let message = message, !message.isEmpty {
                return "Error \(statusCode): \(message)"
            }
            return "Error \(statusCode)"
        case .notFound:
            return String(localized: "error.not_generated_yet")
        case .serviceUnavailable:
            return String(localized: "error.service_unavailable")
        }
    }
}
