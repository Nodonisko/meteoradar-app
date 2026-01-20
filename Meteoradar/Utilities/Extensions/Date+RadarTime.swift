//
//  Date+RadarTime.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 15.09.2025.
//

import Foundation

extension Date {
    
    /// Returns the current UTC date
    static var utcNow: Date {
        return Date()
    }
    
    /// Rounds the date down to the nearest 5-minute interval in UTC
    var roundedToNearestRadarTime: Date {
        return roundedToInterval(minutes: 5)
    }
    
    /// Rounds the date down to the nearest interval in UTC
    /// - Parameter minutes: The interval in minutes to round down to (must be a divisor of 60 for hourly alignment)
    /// - Returns: Date rounded down to the nearest interval boundary
    func roundedToInterval(minutes: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!
        
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        let minute = components.minute ?? 0
        let roundedMinute = (minute / minutes) * minutes // Round down to nearest interval
        
        var newComponents = components
        newComponents.minute = roundedMinute
        newComponents.second = 0
        newComponents.nanosecond = 0
        
        return utcCalendar.date(from: newComponents) ?? self
    }
    
    /// Returns the previous radar time (5 minutes earlier)
    var previousRadarTime: Date {
        return self.addingTimeInterval(-Constants.Radar.radarImageInterval)
    }
    
    /// Returns the next radar time (5 minutes later)
    var nextRadarTime: Date {
        return self.addingTimeInterval(Constants.Radar.radarImageInterval)
    }
    
    /// Formats the date for radar image filename (YYYYMMDD_HHMM)
    var radarTimestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: self)
    }
    
    /// Creates a date from a radar timestamp string (YYYYMMDD_HHMM)
    static func from(radarTimestamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.date(from: radarTimestamp)
    }
    
    /// Creates a date from a radar timestamp string (YYYYMMDD_HHMM) - alternative method name
    static func fromRadarTimestampString(_ timestamp: String) -> Date? {
        return from(radarTimestamp: timestamp)
    }
    
    /// Returns an array of radar timestamps going back in time
    /// - Parameters:
    ///   - count: Number of timestamps to generate
    ///   - intervalMinutes: Time interval between images in minutes (default: 5)
    /// - Returns: Array of dates in descending chronological order (newest first)
    static func radarTimestamps(count: Int, intervalMinutes: Int = 5) -> [Date] {
        // Always start from the nearest 5-minute boundary, regardless of display interval.
        //
        // Why: The server generates new radar images every 5 minutes (e.g., 12:00, 12:05, 12:10...).
        // Forecast files are only kept for the LATEST radar image - older forecasts are deleted.
        //
        // Example problem this fixes:
        //   - Current time: 12:26
        //   - User selects 20-minute interval
        //   - Old behavior: Round to 20-min boundary → 12:20, but forecast files for 12:20 are gone
        //   - New behavior: Round to 5-min boundary → 12:25, forecast files exist
        //
        // The display interval only affects how far back we step for historical images.
        // Since all intervals (5, 10, 15, 20) are multiples of 5, all timestamps remain valid.
        let latestTime = Date.utcNow.roundedToNearestRadarTime
        let intervalSeconds = Double(intervalMinutes * 60)
        var timestamps: [Date] = []
        
        for i in 0..<count {
            let timestamp = latestTime.addingTimeInterval(-Double(i) * intervalSeconds)
            timestamps.append(timestamp)
        }
        
        return timestamps
    }
    
    /// Checks if the current time is at a 5-minute interval boundary (with server latency offset)
    var isRadarUpdateTime: Bool {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!
        
        let components = utcCalendar.dateComponents([.minute, .second], from: self)
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        
        let serverLatencyOffset = Constants.Radar.serverLatencyOffset
        // Check window: serverLatencyOffset to serverLatencyOffset+30 seconds after the 5-minute mark
        return (minute % 5 == 0) && (second >= serverLatencyOffset) && (second <= serverLatencyOffset + 30)
    }
    
    /// Returns the number of seconds until the next 5-minute interval check (with server latency offset)
    var secondsUntilNextRadarUpdate: TimeInterval {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!
        
        let components = utcCalendar.dateComponents([.minute, .second], from: self)
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        
        let serverLatencyOffset = Constants.Radar.serverLatencyOffset
        let minutesUntilNext = 5 - (minute % 5)
        // Add serverLatencyOffset to account for server latency
        var secondsUntilNext = (minutesUntilNext * 60) - second + serverLatencyOffset
        
        // If we're already past the serverLatencyOffset mark in the current 5-min window, wait for the next one
        if secondsUntilNext > 300 {
            secondsUntilNext -= 300
        }
        
        return TimeInterval(secondsUntilNext)
    }
    
    /// Formats the date for display in local time (HH:mm)
    var localTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: self)
    }
}
