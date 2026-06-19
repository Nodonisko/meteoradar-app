//
//  RadarProduct.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 12.06.2026.
//

import Foundation
import MapKit

/// A radar product (country or composite) loaded from products.json.
/// Display strings are localized via Localizable.xcstrings using the product ID.
struct RadarProduct: Decodable, Identifiable, Equatable {
    let id: String

    /// Configured bounds from products.json. Used for instant map centering when
    /// switching products and as a fallback before per-image `GeoBox` metadata
    /// is available. The displayed overlay positions itself from image metadata.
    let bounds: GeoBounds

    /// Map coordinate where this product's country-switch marker is anchored.
    /// Tuned in products.json to sit near where Apple Maps draws the country
    /// label, independent of `bounds.center` (which can fall over sea).
    let center: CLLocationCoordinate2D

    /// Soft lower bound (seconds after the 5-minute mark) before this product's
    /// image can realistically exist on the server. It only suppresses the
    /// guaranteed-useless early requests - the retry loop keeps trying past it
    /// until the image actually appears, so a late frame is still picked up.
    /// Defaults to the shared latency offset when omitted from products.json.
    let publishDelaySeconds: Int

    private enum CodingKeys: String, CodingKey {
        case id, bounds, center, publishDelaySeconds
    }

    private struct Coordinate: Decodable {
        let latitude: Double
        let longitude: Double
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        bounds = try container.decode(GeoBounds.self, forKey: .bounds)
        let center = try container.decode(Coordinate.self, forKey: .center)
        self.center = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        publishDelaySeconds = try container.decodeIfPresent(Int.self, forKey: .publishDelaySeconds)
            ?? RadarSharedConstants.serverLatencyOffsetSeconds
    }

    var pickerTitle: String {
        localizedString(for: "picker_title")
    }

    var pickerButtonTitle: String {
        localizedString(for: "picker_button_title")
    }

    /// Flag emoji for this product (the same asset shown on the picker button).
    var flagEmoji: String {
        pickerButtonTitle
    }

    static func == (lhs: RadarProduct, rhs: RadarProduct) -> Bool {
        lhs.id == rhs.id
            && lhs.bounds == rhs.bounds
            && lhs.center.latitude == rhs.center.latitude
            && lhs.center.longitude == rhs.center.longitude
            && lhs.publishDelaySeconds == rhs.publishDelaySeconds
    }

    /// Default map region showing the whole product coverage
    var region: MKCoordinateRegion {
        bounds.region
    }

    private func localizedString(for suffix: String) -> String {
        NSLocalizedString("product.\(id).\(suffix)", comment: "")
    }
}
