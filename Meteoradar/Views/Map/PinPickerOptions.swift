//
//  PinPickerOptions.swift
//  Meteoradar
//
//  Created by Cursor on 25.02.2026.
//

import Foundation

enum MarkerColorOption: String, CaseIterable, Identifiable {
    case red = "FF3B30"
    case orange = "FF9500"
    case yellow = "FFCC00"
    case green = "34C759"
    case mint = "00C7BE"
    case teal = "30B0C7"
    case blue = "007AFF"
    case indigo = "5856D6"
    case purple = "AF52DE"
    case pink = "FF2D55"
    case brown = "A2845E"
    case gray = "8E8E93"

    var id: String { rawValue }
    var hex: String { rawValue }

    static var defaultColor: MarkerColorOption { .red }

    var displayName: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .mint: return "Mint"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .brown: return "Brown"
        case .gray: return "Gray"
        }
    }
}

enum MarkerGlyphOption: String, CaseIterable, Identifiable {
    case locationPin = "mappin"
    case house = "house.fill"
    case apartment = "building.2.fill"
    case building = "building.fill"
    case buildingColumns = "building.columns"
    case car = "car.fill"
    case truckBox = "truck.box"
    case truck = "truck.box.fill"
    case bike = "bicycle"
    case cart = "cart"
    case person = "figure.walk"
    case crossCountrySki = "figure.skiing.crosscountry"
    case airport = "airplane"
    case tram = "tram.fill"
    case ferry = "ferry.fill"
    case sailboat = "sailboat.fill"
    case houseLodge = "house.lodge"
    case mountain = "mountain.2"
    case tree = "tree.fill"
    case leaf = "leaf.fill"
    case tent = "tent.fill"
    case bikeCircle = "bicycle.circle.fill"
    case fish = "fish"
    case pawprint = "pawprint"
    case heart = "heart"
    case cross = "cross"
    case parkingSign = "parkingsign"
    case pet = "pawprint.fill"
    case school = "backpack.fill"
    case antenna = "antenna.radiowaves.left.and.right"
    case parkingCircle = "parkingsign.circle.fill"
    case farm = "leaf.circle.fill"
    case camera = "camera.fill"
    case hospital = "cross.case.fill"
    case fuel = "fuelpump.fill"
    case factory = "building.columns.fill"
    case wrench = "wrench.and.screwdriver.fill"

    var id: String { rawValue }
    var symbolName: String { rawValue }

    static var defaultGlyph: MarkerGlyphOption { .locationPin }

    var accessibilityName: String {
        switch self {
        case .house: return "House"
        case .apartment: return "Apartment"
        case .building: return "Building"
        case .buildingColumns: return "Columns building"
        case .car: return "Car"
        case .truckBox: return "Truck box"
        case .truck: return "Truck"
        case .bike: return "Bicycle"
        case .cart: return "Cart"
        case .person: return "Person"
        case .crossCountrySki: return "Cross-country skiing"
        case .airport: return "Airport"
        case .tram: return "Tram"
        case .ferry: return "Ferry"
        case .sailboat: return "Sailboat"
        case .houseLodge: return "Lodge"
        case .mountain: return "Mountain"
        case .tree: return "Tree"
        case .leaf: return "Garden"
        case .tent: return "Camp"
        case .bikeCircle: return "Bicycle"
        case .fish: return "Fish"
        case .pawprint: return "Pawprint"
        case .heart: return "Heart"
        case .cross: return "Cross"
        case .parkingSign: return "Parking sign"
        case .pet: return "Pet area"
        case .school: return "School"
        case .antenna: return "Station"
        case .locationPin: return "Location pin"
        case .parkingCircle: return "Parking"
        case .farm: return "Farm"
        case .camera: return "Camera"
        case .hospital: return "Hospital"
        case .fuel: return "Fuel"
        case .factory: return "Factory"
        case .wrench: return "Workshop"
        }
    }
}
