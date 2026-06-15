//
//  RadarProductService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 12.06.2026.
//

import Foundation
import os

/// Service providing available radar products (countries/composites) from products.json.
/// The selected product ID is persisted by SettingsService; this service resolves it
/// to a concrete RadarProduct.
final class RadarProductService {
    static let shared = RadarProductService()

    /// All available products, in the order defined in products.json
    let products: [RadarProduct]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meteoradar", category: "RadarProductService")

    private init() {
        guard let url = Bundle.main.url(forResource: "products", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RadarProduct].self, from: data),
              !decoded.isEmpty else {
            fatalError("products.json is missing or invalid - it must be bundled with the app")
        }
        products = decoded
    }

    /// Currently selected product, resolved from the persisted ID.
    /// Falls back to the first product if the stored ID is unknown.
    var selectedProduct: RadarProduct {
        let selectedID = SettingsService.shared.selectedRadarProductID
        if let product = products.first(where: { $0.id == selectedID }) {
            return product
        }
        logger.warning("Unknown radar product ID '\(selectedID, privacy: .public)', falling back to '\(self.products[0].id, privacy: .public)'")
        return products[0]
    }

    func product(withID id: String) -> RadarProduct? {
        products.first { $0.id == id }
    }
}
