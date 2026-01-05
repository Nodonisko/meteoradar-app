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
    let timestamp: Date
    let sourceTimestamp: Date
    let kind: RadarFrameKind
    let forecastOffsetMinutes: Int?
    let result: Result<UIImage, Error>
    let loadTime: TimeInterval?
    let wasFromCache: Bool
}

enum RadarLoadingStrategy {
    case sequential
    case parallel(maxConcurrent: Int)
}

// MARK: - Network Service

class NetworkService: NSObject, URLSessionDataDelegate {
    static let shared = NetworkService()
    
    private var session: URLSession!
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meteoradar", category: "NetworkService")
    private let cache = FileSystemImageCache.shared
    
    // Radar-specific request deduplication by timestamp
    private struct ActiveRequestKey: Hashable {
        let kind: RadarFrameKind
        let sourceTimestamp: Date
        let targetTimestamp: Date
        let offsetMinutes: Int?
    }
    private var activeRadarRequests: [ActiveRequestKey: AnyPublisher<RadarImageResult, Never>] = [:]
    private let requestLock = NSLock()
    
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
    func fetchRadarImage(for timestamp: Date) -> AnyPublisher<RadarImageResult, Never> {
        return fetchRadarFrame(kind: .observed, sourceTimestamp: timestamp, targetTimestamp: timestamp, offsetMinutes: nil)
    }
    
    func fetchForecastImage(sourceTimestamp: Date, offsetMinutes: Int) -> AnyPublisher<RadarImageResult, Never> {
        let targetTimestamp = sourceTimestamp.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        let kind = RadarFrameKind.forecast(offsetMinutes: offsetMinutes)
        return fetchRadarFrame(kind: kind, sourceTimestamp: sourceTimestamp, targetTimestamp: targetTimestamp, offsetMinutes: offsetMinutes)
    }
    
    private func fetchRadarFrame(kind: RadarFrameKind, sourceTimestamp: Date, targetTimestamp: Date, offsetMinutes: Int?) -> AnyPublisher<RadarImageResult, Never> {
        // Generate cache key using cache service utility
        let cacheKey = FileSystemImageCache.cacheKey(for: kind, sourceTimestamp: sourceTimestamp, forecastTimestamp: targetTimestamp)
        
        // Check cache first if caching is enabled
        if Constants.Radar.cacheEnabled, let cachedImage = cache.cachedImage(for: cacheKey) {
            logger.debug("Cache hit for key: \(cacheKey, privacy: .public)")
            let result = RadarImageResult(
                timestamp: targetTimestamp,
                sourceTimestamp: sourceTimestamp,
                kind: kind,
                forecastOffsetMinutes: offsetMinutes,
                result: .success(cachedImage),
                loadTime: 0,
                wasFromCache: true
            )
            return Just(result).eraseToAnyPublisher()
        }
        
        requestLock.lock()
        defer { requestLock.unlock() }
        
        // Return existing request if already active
        let key = ActiveRequestKey(kind: kind, sourceTimestamp: sourceTimestamp, targetTimestamp: targetTimestamp, offsetMinutes: offsetMinutes)
        if let existingRequest = activeRadarRequests[key] {
            return existingRequest
        }
        
        // Generate URL for timestamp
        let urlString: String
        switch kind {
        case .observed:
            urlString = String(format: Constants.Radar.baseURL, targetTimestamp.radarTimestampString)
        case .forecast(let offset):
            urlString = Constants.Radar.forecastURL(for: sourceTimestamp, offsetMinutes: offset)
        }
        guard let url = URL(string: urlString) else {
            logger.error("Invalid radar URL for kind: \(String(describing: kind), privacy: .public), source: \(sourceTimestamp, privacy: .public), target: \(targetTimestamp, privacy: .public)")
            let errorResult = RadarImageResult(
                timestamp: targetTimestamp,
                sourceTimestamp: sourceTimestamp,
                kind: kind,
                forecastOffsetMinutes: offsetMinutes,
                result: .failure(NetworkError.invalidURL),
                loadTime: 0,
                wasFromCache: false
            )
            return Just(errorResult).eraseToAnyPublisher()
        }
        
        // Create radar-specific request
        let startTime = Date()
        let request = createRadarRequest(for: url, kind: kind, sourceTimestamp: sourceTimestamp, targetTimestamp: targetTimestamp, offsetMinutes: offsetMinutes, startTime: startTime)
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
    private func createRadarRequest(for url: URL, kind: RadarFrameKind, sourceTimestamp: Date, targetTimestamp: Date, offsetMinutes: Int?, startTime: Date) -> AnyPublisher<RadarImageResult, Never> {
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
            
            let task = self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    promise(.failure(error))
                } else if let data = data, let response = response {
                    self.logger.info("Network fetch completed for \(String(describing: kind), privacy: .public) image: \(targetTimestamp.radarTimestampString, privacy: .public) (\(data.count) bytes)")
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
            
            // Log network fetch start
            self.logger.info("Network fetch started for \(String(describing: kind), privacy: .public) image: \(targetTimestamp.radarTimestampString, privacy: .public)")
            
            task.resume()
        }
        .eraseToAnyPublisher()
            .tryMap { data, response -> UIImage in
                guard let image = UIImage(data: data) else {
                    throw NetworkError.invalidImageData
                }
                return image
            }
            .handleEvents(receiveOutput: { [weak self] image in
                // Cache the successfully downloaded image if caching is enabled
                guard let self = self else { return }
                if Constants.Radar.cacheEnabled {
                    let cacheKey = FileSystemImageCache.cacheKey(for: kind, sourceTimestamp: sourceTimestamp, forecastTimestamp: targetTimestamp)
                    self.cache.cacheImage(image, for: cacheKey)
                    self.logger.debug("Cached image for key: \(cacheKey, privacy: .public)")
                }
            })
            .map { image in
                RadarImageResult(
                    timestamp: targetTimestamp,
                    sourceTimestamp: sourceTimestamp,
                    kind: kind,
                    forecastOffsetMinutes: offsetMinutes,
                    result: .success(image),
                    loadTime: Date().timeIntervalSince(startTime),
                    wasFromCache: false
                )
            }
            .catch { [weak self] error -> AnyPublisher<RadarImageResult, Never> in
                self?.logger.error("Radar request failed for URL: \(url.absoluteString, privacy: .public), kind: \(String(describing: kind), privacy: .public), source: \(sourceTimestamp, privacy: .public), target: \(targetTimestamp, privacy: .public), error: \(String(describing: error), privacy: .public)")
                return Just(RadarImageResult(
                    timestamp: targetTimestamp,
                    sourceTimestamp: sourceTimestamp,
                    kind: kind,
                    forecastOffsetMinutes: offsetMinutes,
                    result: .failure(error),
                    loadTime: Date().timeIntervalSince(startTime),
                    wasFromCache: false
                ))
                .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Fetch multiple radar images with different loading strategies
    /// Returns individual results as they complete (streaming), not batched
    func fetchRadarSequence(
        timestamps: [Date], 
        strategy: RadarLoadingStrategy = .sequential
    ) -> AnyPublisher<RadarImageResult, Never> {
        
        switch strategy {
        case .sequential:
            // Sequential loading: one at a time, results stream in as each completes
            return timestamps.publisher
                .flatMap(maxPublishers: .max(1)) { timestamp in
                    self.fetchRadarImage(for: timestamp)
                }
                .eraseToAnyPublisher()
            
        case .parallel(let maxConcurrent):
            // Parallel loading: multiple concurrent, results stream in as each completes
            return timestamps.publisher
                .flatMap(maxPublishers: .max(maxConcurrent)) { timestamp in
                    self.fetchRadarImage(for: timestamp)
                }
                .eraseToAnyPublisher()
        }
    }

    /// Fetch forecast images sequentially, streaming results as they complete
    func fetchForecastSequence(sourceTimestamp: Date, offsets: [Int]) -> AnyPublisher<RadarImageResult, Never> {
        let sortedOffsets = offsets.sorted()
        return sortedOffsets.publisher
            .flatMap(maxPublishers: .max(1)) { offset -> AnyPublisher<RadarImageResult, Never> in
                self.fetchForecastImage(sourceTimestamp: sourceTimestamp, offsetMinutes: offset)
            }
            .eraseToAnyPublisher()
    }
    
    /// Cancel all active radar requests and reset state
    func cancelAllRadarRequests() {
        requestLock.lock()
        activeRadarRequests.removeAll()
        requestLock.unlock()
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
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .invalidImageData:
            return "Failed to create image from data"
        }
    }
}
