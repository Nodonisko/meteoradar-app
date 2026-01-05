//
//  ImageCacheService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 15.09.2025.
//

import Foundation
import UIKit

protocol ImageCacheService {
    func cachedImage(for key: String) -> UIImage?
    func cacheImage(_ image: UIImage, for key: String)
    func removeCachedImage(for key: String)
    func clearCache()
    func cacheSize() -> Int64
    func isCached(key: String) -> Bool
}

// MARK: - Cache Key Generation
extension ImageCacheService {
    /// Generate cache key for radar image data
    /// - Parameters:
    ///   - kind: Type of radar frame (observed or forecast)
    ///   - sourceTimestamp: Source timestamp for the image
    ///   - forecastTimestamp: Forecast timestamp (same as source for observed images)
    /// - Returns: Unique cache key string
    static func cacheKey(for kind: RadarFrameKind, sourceTimestamp: Date, forecastTimestamp: Date) -> String {
        switch kind {
        case .observed:
            return sourceTimestamp.radarTimestampString
        case .forecast:
            return "\(sourceTimestamp.radarTimestampString)-\(forecastTimestamp.radarTimestampString)"
        }
    }
}

class FileSystemImageCache: ImageCacheService {
    static let shared = FileSystemImageCache()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.meteoradar.imagecache", qos: .utility)
    
    private init() {
        // Create cache directory in Documents/ImageCache
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsPath.appendingPathComponent("ImageCache")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Clean up old cache files on init
        cleanupExpiredCache()
    }
    
    func cachedImage(for key: String) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // Check if file is expired
        if isCacheExpired(for: fileURL) {
            removeCachedImage(for: key)
            return nil
        }
        
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            // Remove corrupted cache file
            removeCachedImage(for: key)
            return nil
        }
        
        return image
    }
    
    func cacheImage(_ image: UIImage, for key: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let fileURL = self.cacheDirectory.appendingPathComponent("\(key).png")
            
            guard let data = image.pngData() else {
                print("Failed to convert image to PNG data for key: \(key)")
                return
            }
            
            do {
                try data.write(to: fileURL)
                print("Cached image for key: \(key)")
            } catch {
                print("Failed to cache image for key \(key): \(error.localizedDescription)")
            }
        }
    }
    
    func removeCachedImage(for key: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let fileURL = self.cacheDirectory.appendingPathComponent("\(key).png")
            
            do {
                try self.fileManager.removeItem(at: fileURL)
                print("Removed cached image for key: \(key)")
            } catch {
                // File might not exist, which is fine
            }
        }
    }
    
    func clearCache() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                
                for fileURL in contents {
                    try self.fileManager.removeItem(at: fileURL)
                }
                
                print("Cleared all cached images")
            } catch {
                print("Failed to clear cache: \(error.localizedDescription)")
            }
        }
    }
    
    func cacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            
            for fileURL in contents {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            print("Failed to calculate cache size: \(error.localizedDescription)")
        }
        
        return totalSize
    }
    
    func isCached(key: String) -> Bool {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        return fileManager.fileExists(atPath: fileURL.path) && !isCacheExpired(for: fileURL)
    }
    
    // MARK: - Private Methods
    
    private func isCacheExpired(for fileURL: URL) -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let expirationDate = modificationDate.addingTimeInterval(TimeInterval(Constants.Radar.cacheExpirationDays * 24 * 60 * 60))
                return Date() > expirationDate
            }
        } catch {
            return true // Consider expired if we can't read attributes
        }
        
        return true
    }
    
    private func cleanupExpiredCache() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
                
                for fileURL in contents {
                    if self.isCacheExpired(for: fileURL) {
                        try self.fileManager.removeItem(at: fileURL)
                        print("Removed expired cache file: \(fileURL.lastPathComponent)")
                    }
                }
                
                // Also check if cache is too large and remove oldest files
                self.enforceMaxCacheSize()
                
            } catch {
                print("Failed to cleanup expired cache: \(error.localizedDescription)")
            }
        }
    }
    
    private func enforceMaxCacheSize() {
        let maxSize = Constants.Radar.maxCacheSize
        let currentSize = cacheSize()
        
        guard currentSize > maxSize else { return }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            // Sort by modification date (oldest first)
            let sortedContents = contents.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 < date2
            }
            
            var sizeToRemove = currentSize - maxSize
            
            for fileURL in sortedContents {
                guard sizeToRemove > 0 else { break }
                
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(resourceValues.fileSize ?? 0)
                
                try fileManager.removeItem(at: fileURL)
                sizeToRemove -= fileSize
                
                print("Removed cache file to free space: \(fileURL.lastPathComponent)")
            }
            
        } catch {
            print("Failed to enforce max cache size: \(error.localizedDescription)")
        }
    }
}
