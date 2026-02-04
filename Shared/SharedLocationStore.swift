//
//  SharedLocationStore.swift
//  Meteoradar
//
//  Shared location storage for app + widget.
//

import Foundation
import CoreLocation

struct SharedLocation {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
}

enum SharedLocationStore {
    static let appGroupID = "group.com.danielsuchy.meteoradar"

    private static let latitudeKey = "SharedLocationLatitude"
    private static let longitudeKey = "SharedLocationLongitude"
    private static let timestampKey = "SharedLocationTimestamp"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(location: CLLocation, timestamp: Date = Date()) {
        save(coordinate: location.coordinate, timestamp: timestamp)
    }

    static func save(coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
        guard let defaults = defaults else { return }
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
        defaults.set(timestamp.timeIntervalSince1970, forKey: timestampKey)
    }

    static func load() -> SharedLocation? {
        guard let defaults = defaults else { return nil }
        let timestampSeconds = defaults.double(forKey: timestampKey)
        let latitude = defaults.double(forKey: latitudeKey)
        let longitude = defaults.double(forKey: longitudeKey)

        guard timestampSeconds > 0 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return SharedLocation(coordinate: coordinate, timestamp: Date(timeIntervalSince1970: timestampSeconds))
    }

    static func clear() {
        guard let defaults = defaults else { return }
        defaults.removeObject(forKey: latitudeKey)
        defaults.removeObject(forKey: longitudeKey)
        defaults.removeObject(forKey: timestampKey)
    }

    static func shouldRequestLocation(minimumInterval: TimeInterval) -> Bool {
        guard let last = load() else { return true }
        return Date().timeIntervalSince(last.timestamp) > minimumInterval
    }
}
