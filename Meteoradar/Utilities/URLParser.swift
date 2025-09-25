//
//  URLParser.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 22.09.2025.
//

import Foundation

/// Simple utility for parsing radar image URLs
struct URLParser {
    
    /// Extracts radar timestamp from a radar image URL
    /// - Parameter urlString: The full URL string of the radar image
    /// - Returns: The radar timestamp string (YYYYMMDD_HHMM) or nil if parsing fails
    static func extractRadarTimestamp(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        let filename = url.lastPathComponent
        
        guard let regex = try? NSRegularExpression(pattern: Constants.Radar.filenamePattern),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let timestampRange = Range(match.range(at: 1), in: filename) else {
            return nil
        }
        
        return String(filename[timestampRange])
    }
    
    /// Extracts radar timestamp and converts to Date
    /// - Parameter urlString: The full URL string of the radar image
    /// - Returns: Date object or nil if parsing fails
    static func extractRadarDate(from urlString: String) -> Date? {
        guard let timestampString = extractRadarTimestamp(from: urlString) else { return nil }
        return Date.fromRadarTimestampString(timestampString)
    }
    
    /// Generates a radar image URL for a given timestamp
    /// - Parameter timestamp: The radar timestamp
    /// - Returns: Complete radar image URL
    static func generateRadarURL(for timestamp: Date) -> String {
        let timestampString = timestamp.radarTimestampString
        return String(format: Constants.Radar.baseURL, timestampString)
    }
}