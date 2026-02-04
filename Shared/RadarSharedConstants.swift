//
//  RadarSharedConstants.swift
//  Meteoradar
//
//  Shared radar constants for app + widget.
//

import Foundation

enum RadarSharedConstants {
    static let baseURL = "https://radar.danielsuchy.cz/output/radar_%@_overlay%@.png"
    static let forecastBaseURL = "https://radar.danielsuchy.cz/output_forecast/radar_%@_forecast_fct%d_overlay%@.png"
    static let radarIntervalSeconds: TimeInterval = 300
    static let serverLatencyOffsetSeconds: Int = 20
    static let requestTimeout: TimeInterval = 25
    static let filenamePattern = #"(\d{8}_\d{4})"#
}
