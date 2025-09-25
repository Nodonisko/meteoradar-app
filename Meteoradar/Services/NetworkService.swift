//
//  NetworkService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import Foundation
import UIKit
import Combine

// MARK: - Radar-Specific Types

struct RadarImageResult {
    let timestamp: Date
    let result: Result<UIImage, Error>
    let loadTime: TimeInterval?
    let wasFromCache: Bool = false
}

enum RadarLoadingStrategy {
    case sequential
    case parallel(maxConcurrent: Int)
}

// MARK: - Network Service

class NetworkService {
    static let shared = NetworkService()
    
    private let session: URLSession
    
    // Radar-specific request deduplication by timestamp
    private var activeRadarRequests: [Date: AnyPublisher<RadarImageResult, Never>] = [:]
    private let requestLock = NSLock()
    
    private init() {
        // Configure URLSession for better performance
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.Network.radarRequestTimeout
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Radar-Specific API
    
    /// Fetch radar image for specific timestamp with deduplication and error handling
    func fetchRadarImage(for timestamp: Date) -> AnyPublisher<RadarImageResult, Never> {
        requestLock.lock()
        defer { requestLock.unlock() }
        
        // Return existing request if already active
        if let existingRequest = activeRadarRequests[timestamp] {
            return existingRequest
        }
        
        // Generate URL for timestamp
        let urlString = String(format: Constants.Radar.baseURL, timestamp.radarTimestampString)
        guard let url = URL(string: urlString) else {
            let errorResult = RadarImageResult(
                timestamp: timestamp,
                result: .failure(NetworkError.invalidURL),
                loadTime: 0
            )
            return Just(errorResult).eraseToAnyPublisher()
        }
        
        // Create radar-specific request
        let startTime = Date()
        let request = createRadarRequest(for: url, timestamp: timestamp, startTime: startTime)
            .handleEvents(
                receiveCompletion: { [weak self] _ in
                    // Clean up when done
                    self?.requestLock.lock()
                    self?.activeRadarRequests.removeValue(forKey: timestamp)
                    self?.requestLock.unlock()
                }
            )
            .share()
            .eraseToAnyPublisher()
        
        activeRadarRequests[timestamp] = request
        return request
    }
    
    /// Create the actual radar network request
    private func createRadarRequest(for url: URL, timestamp: Date, startTime: Date) -> AnyPublisher<RadarImageResult, Never> {
        return session.dataTaskPublisher(for: url)
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
                    timestamp: timestamp,
                    result: .success(image),
                    loadTime: Date().timeIntervalSince(startTime)
                )
            }
            .catch { error in
                Just(RadarImageResult(
                    timestamp: timestamp,
                    result: .failure(error),
                    loadTime: Date().timeIntervalSince(startTime)
                ))
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
    
    /// Cancel all active radar requests and reset state
    func cancelAllRadarRequests() {
        requestLock.lock()
        activeRadarRequests.removeAll()
        requestLock.unlock()
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
