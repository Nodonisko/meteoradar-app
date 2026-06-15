//
//  ImageCacheService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 15.09.2025.
//

import Foundation

protocol ImageCacheService {
    /// Returns the cached image's original bytes, or `nil` on a miss/expiry.
    /// Raw bytes are stored verbatim so the server's size optimization and PNG
    /// metadata (notably the `GeoBox` comment) are preserved across cache hits.
    func cachedData(for key: String) -> Data?
    func store(data: Data, for key: String)
    func removeCached(for key: String)
    func clearCache()
    func cacheSize() -> Int64
    func isCached(key: String) -> Bool
}

class FileSystemImageCache: ImageCacheService {
    static let shared = FileSystemImageCache()
    
    private let cacheDirectory: URL?
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.meteoradar.imagecache", qos: .utility)
    
    private init() {
        cacheDirectory = RadarCacheHelpers.cacheDirectoryURL(fileManager: fileManager)
        
        // Clean up old cache files on init
        cleanupExpiredCache()
    }
    
    func cachedData(for key: String) -> Data? {
        guard let cacheDirectory else { return nil }
        let fileURL = cacheDirectory.appendingPathComponent(key)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // Check if file is expired
        if isCacheExpired(for: fileURL) {
            removeCached(for: key)
            return nil
        }
        
        guard let data = try? Data(contentsOf: fileURL) else {
            removeCached(for: key)
            return nil
        }
        
        return data
    }
    
    func store(data: Data, for key: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let cacheDirectory = self.cacheDirectory else { return }
            
            let fileURL = cacheDirectory.appendingPathComponent(key)
            
            do {
                // Store the original, validated bytes atomically: keeps the
                // server's optimized encoding and the embedded GeoBox metadata,
                // and avoids leaving a corrupt file if the write is interrupted.
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("Failed to cache image for key \(key): \(error.localizedDescription)")
            }
        }
    }
    
    func removeCached(for key: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let cacheDirectory = self.cacheDirectory else { return }
            
            let fileURL = cacheDirectory.appendingPathComponent(key)
            
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
            guard let cacheDirectory = self.cacheDirectory else { return }
            
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                
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
        guard let cacheDirectory else { return 0 }
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
        guard let cacheDirectory else { return false }
        let fileURL = cacheDirectory.appendingPathComponent(key)
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
            guard let cacheDirectory = self.cacheDirectory else { return }
            
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
                
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
            guard let cacheDirectory else { return }
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
