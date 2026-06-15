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

    /// Soft lower bound (seconds after the 5-minute mark) before this product's
    /// image can realistically exist on the server. It only suppresses the
    /// guaranteed-useless early requests - the retry loop keeps trying past it
    /// until the image actually appears, so a late frame is still picked up.
    /// Defaults to the shared latency offset when omitted from products.json.
    let publishDelaySeconds: Int

    private enum CodingKeys: String, CodingKey {
        case id, bounds, publishDelaySeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        bounds = try container.decode(GeoBounds.self, forKey: .bounds)
        publishDelaySeconds = try container.decodeIfPresent(Int.self, forKey: .publishDelaySeconds)
            ?? RadarSharedConstants.serverLatencyOffsetSeconds
    }

    var pickerTitle: String {
        localizedString(for: "picker_title")
    }

    var pickerButtonTitle: String {
        localizedString(for: "picker_button_title")
    }

    /// Default map region showing the whole product coverage
    var region: MKCoordinateRegion {
        bounds.region
    }

    private func localizedString(for suffix: String) -> String {
        NSLocalizedString("product.\(id).\(suffix)", comment: "")
    }
}
