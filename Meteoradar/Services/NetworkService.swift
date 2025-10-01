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
    let wasFromCache: Bool = false
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
                loadTime: 0
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
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Constants.Network.radarRequestTimeout)
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
            
            task.resume()
        }
        .eraseToAnyPublisher()
            .tryMap { data, response -> UIImage in
                // Apply testing configuration if enabled
                if Constants.Testing.simulateRandomFailures && Double.random(in: 0...1) < Constants.Testing.failureRate {
                    throw NetworkError.simulatedFailure
                }
                
                guard let image = UIImage(data: data) else {
                    throw NetworkError.invalidImageData
                }
                return image
            }
            .delay(
                for: Constants.Testing.enableSlowLoading ? .seconds(Constants.Testing.artificialLoadingDelay) : .seconds(0),
                scheduler: DispatchQueue.global()
            )
            .map { image in
                RadarImageResult(
                    timestamp: targetTimestamp,
                    sourceTimestamp: sourceTimestamp,
                    kind: kind,
                    forecastOffsetMinutes: offsetMinutes,
                    result: .success(image),
                    loadTime: Date().timeIntervalSince(startTime)
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
                    loadTime: Date().timeIntervalSince(startTime)
                ))
                .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Fetch multiple radar images with different loading strategies
    func fetchRadarSequence(
        timestamps: [Date], 
        strategy: RadarLoadingStrategy = .sequential
    ) -> AnyPublisher<[RadarImageResult], Never> {
        
        switch strategy {
        case .sequential:
            return timestamps.publisher
                .flatMap(maxPublishers: .max(1)) { timestamp in
                    self.fetchRadarImage(for: timestamp)
                }
                .collect()
                .eraseToAnyPublisher()
            
        case .parallel(let maxConcurrent):
            return timestamps.publisher
                .flatMap(maxPublishers: .max(maxConcurrent)) { timestamp in
                    self.fetchRadarImage(for: timestamp)
                }
                .collect()
                .eraseToAnyPublisher()
        }
    }

    func fetchForecastSequence(sourceTimestamp: Date, offsets: [Int]) -> AnyPublisher<[RadarImageResult], Never> {
        let sortedOffsets = offsets.sorted()
        return sortedOffsets.publisher
            .flatMap(maxPublishers: .max(1)) { offset -> AnyPublisher<RadarImageResult, Never> in
                self.fetchForecastImage(sourceTimestamp: sourceTimestamp, offsetMinutes: offset)
            }
            .collect()
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
    case simulatedFailure
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .invalidImageData:
            return "Failed to create image from data"
        case .simulatedFailure:
            return "Simulated failure for testing"
        }
    }
}
