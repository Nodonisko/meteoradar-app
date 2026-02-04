//
//  RadarCacheHelpers.swift
//  Meteoradar
//
//  Shared cache helpers for app + widget.
//

import Foundation

enum RadarCacheHelpers {
    static let appGroupID = "group.com.danielsuchy.meteoradar"
    static let cacheFolderName = "RadarImageCache"

    static func cacheDirectoryURL(fileManager: FileManager = .default) -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let cacheRoot = container.appendingPathComponent("Library/Caches", isDirectory: true)
        let cacheDirectory = cacheRoot.appendingPathComponent(cacheFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        return cacheDirectory
    }

    static func cacheFilename(for url: URL) -> String {
        url.lastPathComponent
    }

    static func cacheFileURL(for url: URL, fileManager: FileManager = .default) -> URL? {
        guard let cacheDirectory = cacheDirectoryURL(fileManager: fileManager) else { return nil }
        return cacheDirectory.appendingPathComponent(cacheFilename(for: url), isDirectory: false)
    }

    static func timestampString(from filename: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: RadarSharedConstants.filenamePattern) else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range),
              match.numberOfRanges >= 2,
              let stringRange = Range(match.range(at: 1), in: filename) else {
            return nil
        }
        return String(filename[stringRange])
    }

    static func timestamp(from filename: String) -> Date? {
        guard let timestampString = timestampString(from: filename) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.date(from: timestampString)
    }
}
