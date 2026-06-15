//
//  RadarProductPicker.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 12.06.2026.
//

import SwiftUI

/// Flag button showing the currently selected radar product (country/composite).
/// Tapping it opens a menu with all products available in products.json.
struct RadarProductPicker: View {
    @ObservedObject private var settings = SettingsService.shared
    private let products = RadarProductService.shared.products
    
    private var selectedProduct: RadarProduct {
        RadarProductService.shared.selectedProduct
    }
    
    var body: some View {
        Menu {
            Picker(String(localized: "product.picker_title"), selection: $settings.selectedRadarProductID) {
                ForEach(products) { product in
                    Text(product.pickerTitle)
                        .tag(product.id)
                }
            }
        } label: {
            Text(selectedProduct.pickerButtonTitle)
                .font(.title2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.7))
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel(Text("product.picker_title"))
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        RadarProductPicker()
    }
}
