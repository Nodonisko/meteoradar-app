//
//  GeoBounds.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.06.2026.
//

import Foundation
import CoreLocation
import MapKit
import ImageIO

/// A geographic bounding box (WGS84) used to position radar imagery on the map.
///
/// This is the single source of truth for the lat/lon → `MKMapRect` math. Bounds
/// come from two places: `products.json` (used for instant map centering on a
/// product switch, before any image has loaded) and per-image `GeoBox` metadata
/// embedded in each rendered PNG (used to position the actual overlay).
struct GeoBounds: Decodable, Equatable {
    let west: Double
    let south: Double
    let east: Double
    let north: Double

    var northEast: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: north, longitude: east)
    }

    var southWest: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: south, longitude: west)
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (north + south) / 2,
            longitude: (east + west) / 2
        )
    }

    /// Map rect covering the bounding box.
    var mapRect: MKMapRect {
        let neMapPoint = MKMapPoint(northEast)
        let swMapPoint = MKMapPoint(southWest)
        return MKMapRect(
            x: swMapPoint.x,                      // West edge
            y: neMapPoint.y,                      // North edge
            width: neMapPoint.x - swMapPoint.x,   // East - West
            height: swMapPoint.y - neMapPoint.y   // South - North
        )
    }

    /// Region showing the whole bounding box with a small margin.
    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: (north - south) * 1.1,
                longitudeDelta: (east - west) * 1.1
            )
        )
    }
}

// MARK: - PNG GeoBox Metadata

extension GeoBounds {
    /// Parses bounds from a rendered PNG's `Comment` metadata.
    ///
    /// The radar pipeline embeds `GeoBox=west,south,east,north` in the PNG
    /// `Comment` text chunk of every variant. Reading it requires the original
    /// file bytes (a re-encoded `UIImage` drops text chunks), so this is parsed
    /// at the network/cache boundary where the raw `Data` is still available.
    ///
    /// Returns `nil` if the metadata is missing or malformed, in which case the
    /// caller falls back to the product's configured bounds.
    init?(pngData data: Data) {
        guard let comment = GeoBounds.pngComment(from: data),
              let parsed = GeoBounds(geoBoxComment: comment) else {
            return nil
        }
        self = parsed
    }

    private init?(geoBoxComment comment: String) {
        // Defensive: locate the GeoBox token anywhere in the comment (it may be
        // one of several lines), read to the end of that line, then parse the four
        // comma-separated doubles that follow it.
        guard let range = comment.range(of: "GeoBox=") else { return nil }
        let line = comment[range.upperBound...].prefix { $0 != "\n" && $0 != "\r" }
        let values = line
            .split(separator: ",", omittingEmptySubsequences: false)
            .prefix(4)
            .map { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        guard values.count == 4,
              let west = values[0],
              let south = values[1],
              let east = values[2],
              let north = values[3] else {
            return nil
        }

        self.init(west: west, south: south, east: east, north: north)
    }

    private static func pngComment(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
              let comment = pngProperties[kCGImagePropertyPNGComment] as? String else {
            return nil
        }
        return comment
    }
}
