//
//  WidgetRadarHelpers.swift
//  MeteoradarWidget
//
//  Created by Daniel Suchý on 31.01.2026.
//

import Foundation
import UIKit
import SwiftUI
import CoreLocation

enum WidgetRadarConstants {
    static let baseURL = RadarSharedConstants.baseURL
    static let imageQualitySuffix = "" // 1x only
    static let highQualitySuffix = "2x"
    static let radarIntervalSeconds: TimeInterval = RadarSharedConstants.radarIntervalSeconds
    static let serverLatencyOffsetSeconds: Int = RadarSharedConstants.serverLatencyOffsetSeconds
    static let requestTimeout: TimeInterval = RadarSharedConstants.requestTimeout

    static func observedURL(for timestamp: Date, qualitySuffix: String) -> URL? {
        let urlString = String(format: baseURL, timestamp.radarTimestampString, qualitySuffix)
        return URL(string: urlString)
    }

    static func observedURL(for timestamp: Date) -> URL? {
        observedURL(for: timestamp, qualitySuffix: imageQualitySuffix)
    }
}

struct WidgetCustomMarker: Identifiable, Decodable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let colorHex: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var color: Color {
        Color(uiColor: UIColor.widgetColor(hexRGB: colorHex) ?? .systemRed)
    }
}

enum SharedCustomMarkerStore {
    private static let storageKey = "customMapMarkers.v1"

    static func load() -> [WidgetCustomMarker] {
        guard let defaults = UserDefaults(suiteName: SharedLocationStore.appGroupID),
              let data = defaults.data(forKey: storageKey),
              let markers = try? JSONDecoder().decode([WidgetCustomMarker].self, from: data) else {
            return []
        }
        return markers
    }
}

enum WidgetRadarImageLoader {
    static func fetchImage(for timestamp: Date) async -> UIImage? {
        if let cached = loadCachedImage(for: timestamp) {
            return cached
        }
        guard let url = WidgetRadarConstants.observedURL(for: timestamp) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: WidgetRadarConstants.requestTimeout)
        request.assumesHTTP3Capable = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            saveToCache(data: data, url: url)
            return image
        } catch {
            return nil
        }
    }

    static func loadLastImage() -> (image: UIImage, timestamp: Date?)? {
        guard let cacheDirectory = RadarCacheHelpers.cacheDirectoryURL() else { return nil }
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        let candidates: [(url: URL, timestamp: Date, isHighQuality: Bool)] = contents.compactMap { url in
            let filename = url.lastPathComponent
            guard filename.lowercased().hasSuffix(".png") else { return nil }
            guard !isForecastFilename(filename) else { return nil }
            guard let timestamp = RadarCacheHelpers.timestamp(from: filename) else { return nil }
            return (url: url, timestamp: timestamp, isHighQuality: isHighQualityFilename(filename))
        }
        guard let best = candidates.max(by: { left, right in
            if left.timestamp != right.timestamp {
                return left.timestamp < right.timestamp
            }
            if left.isHighQuality != right.isHighQuality {
                return !left.isHighQuality && right.isHighQuality
            }
            return left.url.lastPathComponent < right.url.lastPathComponent
        }) else {
            return nil
        }
        guard let data = try? Data(contentsOf: best.url),
              let image = UIImage(data: data) else {
            return nil
        }
        return (image: image, timestamp: best.timestamp)
    }

    private static func loadCachedImage(for timestamp: Date) -> UIImage? {
        let candidates = [
            WidgetRadarConstants.observedURL(for: timestamp, qualitySuffix: WidgetRadarConstants.highQualitySuffix),
            WidgetRadarConstants.observedURL(for: timestamp, qualitySuffix: WidgetRadarConstants.imageQualitySuffix)
        ]
        for candidate in candidates {
            if let url = candidate, let cached = loadCachedImage(for: url) {
                return cached
            }
        }
        return nil
    }

    private static func loadCachedImage(for url: URL) -> UIImage? {
        guard let fileURL = RadarCacheHelpers.cacheFileURL(for: url) else { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private static func saveToCache(data: Data, url: URL) {
        guard let fileURL = RadarCacheHelpers.cacheFileURL(for: url) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private static func isForecastFilename(_ filename: String) -> Bool {
        filename.contains("_forecast_")
    }

    private static func isHighQualityFilename(_ filename: String) -> Bool {
        filename.contains("overlay2x")
    }
}

enum WidgetRadarBounds {
    static let northEast = CLLocationCoordinate2D(latitude: 51.458, longitude: 19.624)
    static let southWest = CLLocationCoordinate2D(latitude: 48.047, longitude: 11.267)
}

enum WidgetRadarLayout {
    static func scaledPoint(
        _ point: CGPoint,
        in containerSize: CGSize,
        scale: CGFloat,
        anchor: UnitPoint
    ) -> CGPoint {
        guard scale != 1 else { return point }
        let anchorPoint = CGPoint(
            x: containerSize.width * anchor.x,
            y: containerSize.height * anchor.y
        )
        return CGPoint(
            x: anchorPoint.x + (point.x - anchorPoint.x) * scale,
            y: anchorPoint.y + (point.y - anchorPoint.y) * scale
        )
    }

    static func radarImageRect(
        containerSize: CGSize,
        imageSize: CGSize,
        alignment: UnitPoint
    ) -> CGRect {
        aspectFillRect(
            containerSize: containerSize,
            imageSize: imageSize,
            alignment: alignment
        )
    }

    private static func aspectFillRect(
        containerSize: CGSize,
        imageSize: CGSize,
        alignment: UnitPoint
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = max(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let filledSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        let containerAnchor = CGPoint(
            x: containerSize.width * alignment.x,
            y: containerSize.height * alignment.y
        )
        let imageAnchor = CGPoint(
            x: filledSize.width * alignment.x,
            y: filledSize.height * alignment.y
        )
        let origin = CGPoint(
            x: containerAnchor.x - imageAnchor.x,
            y: containerAnchor.y - imageAnchor.y
        )
        return CGRect(origin: origin, size: filledSize)
    }

    static func point(
        for coordinate: CLLocationCoordinate2D,
        containerSize: CGSize,
        imageSize: CGSize,
        alignment: UnitPoint
    ) -> CGPoint? {
        let bounds = WidgetRadarBounds.self
        let latRange = bounds.northEast.latitude - bounds.southWest.latitude
        let lonRange = bounds.northEast.longitude - bounds.southWest.longitude
        guard latRange > 0, lonRange > 0 else { return nil }

        let normalizedX = (coordinate.longitude - bounds.southWest.longitude) / lonRange
        let normalizedY = (bounds.northEast.latitude - coordinate.latitude) / latRange

        guard normalizedX >= 0, normalizedX <= 1, normalizedY >= 0, normalizedY <= 1 else { return nil }

        let rect = radarImageRect(
            containerSize: containerSize,
            imageSize: imageSize,
            alignment: alignment
        )
        let x = rect.minX + (rect.width * normalizedX)
        let y = rect.minY + (rect.height * normalizedY)
        return CGPoint(x: x, y: y)
    }
}

final class WidgetLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = WidgetLocationService()

    private let locationManager = CLLocationManager()
    private var isRequesting = false
    private let minimumRequestInterval: TimeInterval = 3600

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 5000
    }

    @MainActor
    func requestLocationIfNeeded() {
        guard !isRequesting else { return }

        guard locationManager.isAuthorizedForWidgetUpdates else { return }

        let cached = SharedLocationStore.load()
        let managerLocation = locationManager.location

        if let managerLocation {
            let managerTimestamp = managerLocation.timestamp
            if cached == nil || managerTimestamp > cached?.timestamp ?? .distantPast {
                SharedLocationStore.save(location: managerLocation, timestamp: managerTimestamp)
            }
        }

        let lastTimestamp = max(
            cached?.timestamp ?? .distantPast,
            managerLocation?.timestamp ?? .distantPast
        )
        if lastTimestamp != .distantPast,
           Date().timeIntervalSince(lastTimestamp) <= minimumRequestInterval {
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isRequesting = true
            locationManager.requestLocation()
        default:
            return
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            requestLocationIfNeeded()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isRequesting = false
        guard let location = locations.last else { return }
        SharedLocationStore.save(location: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
    }
}

extension Date {
    static var utcNow: Date {
        Date()
    }

    var roundedToNearestRadarTime: Date {
        roundedToInterval(minutes: 5)
    }

    func roundedToInterval(minutes: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!

        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        let minute = components.minute ?? 0
        let roundedMinute = (minute / minutes) * minutes

        var newComponents = components
        newComponents.minute = roundedMinute
        newComponents.second = 0
        newComponents.nanosecond = 0

        return utcCalendar.date(from: newComponents) ?? self
    }

    var previousRadarTime: Date {
        addingTimeInterval(-WidgetRadarConstants.radarIntervalSeconds)
    }

    var radarTimestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: self)
    }

    var localTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: self)
    }

    static var latestAvailableRadarTimestamp: Date {
        let now = Date.utcNow
        let rounded = now.roundedToNearestRadarTime
        let secondsSinceRounded = now.timeIntervalSince(rounded)
        if secondsSinceRounded < Double(WidgetRadarConstants.serverLatencyOffsetSeconds) {
            return rounded.previousRadarTime
        }
        return rounded
    }

    var secondsUntilNextRadarUpdate: TimeInterval {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!

        let components = utcCalendar.dateComponents([.minute, .second], from: self)
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        let serverLatencyOffset = WidgetRadarConstants.serverLatencyOffsetSeconds
        let minutesUntilNext = 5 - (minute % 5)
        var secondsUntilNext = (minutesUntilNext * 60) - second + serverLatencyOffset

        if secondsUntilNext > 300 {
            secondsUntilNext -= 300
        }

        return TimeInterval(secondsUntilNext)
    }
}

private extension UIColor {
    static func widgetColor(hexRGB: String) -> UIColor? {
        let trimmed = hexRGB.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
