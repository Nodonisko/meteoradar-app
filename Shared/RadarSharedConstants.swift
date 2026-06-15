//
//  RadarSharedConstants.swift
//  Meteoradar
//
//  Shared radar constants for app + widget.
//

import Foundation

enum RadarSharedConstants {
    /// Product ID used by the widget (app supports multiple products via products.json)
    static let defaultProductID = "cz"
    
    // URL templates: 1st + 2nd argument = product ID, then timestamp, (forecast offset,) quality suffix
    static let baseURL = "https://radar.meteorabbit.io/%@/radar_%@_%@_overlay%@.png"
    static let forecastBaseURL = "https://radar.meteorabbit.io/forecast/%@/radar_%@_%@_fct%d_overlay%@.png"
    static let radarIntervalSeconds: TimeInterval = 300
    static let serverLatencyOffsetSeconds: Int = 20
    static let requestTimeout: TimeInterval = 45
    static let filenamePattern = #"(\d{8}_\d{4})"#
}
