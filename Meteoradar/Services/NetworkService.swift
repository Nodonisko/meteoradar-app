//
//  NetworkService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import Foundation
import UIKit

class NetworkService {
    static let shared = NetworkService()
    
    private var activeTasks = Set<URLSessionDataTask>()
    private let taskQueue = DispatchQueue(label: "com.meteoradar.networktasks", attributes: .concurrent)
    
    private init() {}
    
    func fetchRadarImage(from urlString: String, completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            defer {
                // Remove task from tracking when completed
                if let task = self?.activeTasks.first(where: { $0.originalRequest?.url == url }) {
                    self?.taskQueue.async(flags: .barrier) {
                        self?.activeTasks.remove(task)
                    }
                }
            }
            
            // Artificial delay for testing loading states
            let processResponse = {
                if let error = error {
                    // Don't report cancellation errors
                    if (error as NSError).code != NSURLErrorCancelled {
                        completion(.failure(error))
                    }
                    return
                }
                
                // Simulate random failures for testing
                if Constants.Testing.simulateRandomFailures && Double.random(in: 0...1) < Constants.Testing.failureRate {
                    completion(.failure(NetworkError.simulatedFailure))
                    return
                }
                
                guard let data = data, let image = UIImage(data: data) else {
                    completion(.failure(NetworkError.invalidImageData))
                    return
                }
                
                completion(.success(image))
            }
            
            if Constants.Testing.enableSlowLoading {
                // Add artificial delay for testing
                DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Testing.artificialLoadingDelay) {
                    processResponse()
                }
            } else {
                processResponse()
            }
        }
        
        // Track the task for cleanup purposes only
        taskQueue.async(flags: .barrier) { [weak self] in
            self?.activeTasks.insert(task)
        }
        
        task.resume()
    }
    
    func cancelAllTasks() {
        taskQueue.async(flags: .barrier) { [weak self] in
            self?.activeTasks.forEach { $0.cancel() }
            self?.activeTasks.removeAll()
        }
    }
}

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
