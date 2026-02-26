//
//  MeteoradarWidget.swift
//  MeteoradarWidget
//
//  Created by Daniel Suchý on 31.01.2026.
//

import WidgetKit
import SwiftUI
import UIKit
import CoreLocation
import AppIntents

enum WidgetAppearance: String, AppEnum {
    case system
    case light
    case dark

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("widget.settings_appearance_label"))
    }

    static var caseDisplayRepresentations: [WidgetAppearance: DisplayRepresentation] {
        [
            .system: DisplayRepresentation(title: LocalizedStringResource("widget.appearance_auto")),
            .light: DisplayRepresentation(title: LocalizedStringResource("widget.appearance_light")),
            .dark: DisplayRepresentation(title: LocalizedStringResource("widget.appearance_dark"))
        ]
    }

    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func backgroundColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .system:
            return Color("WidgetBackground")
        case .light:
            return WidgetAppearance.widgetBackgroundColor(for: .light)
        case .dark:
            return WidgetAppearance.widgetBackgroundColor(for: .dark)
        }
    }

    private static func widgetBackgroundColor(for interfaceStyle: UIUserInterfaceStyle) -> Color {
        let traitCollection = UITraitCollection(userInterfaceStyle: interfaceStyle)
        let bundle = Bundle(for: WidgetBundleToken.self)
        if let uiColor = UIColor(named: "WidgetBackground", in: bundle, compatibleWith: traitCollection) {
            // Resolve to a concrete variant so manual appearance overrides stay stable.
            return Color(uiColor: uiColor.resolvedColor(with: traitCollection))
        }
        return Color("WidgetBackground")
    }
}

private final class WidgetBundleToken {}

struct RadarWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.settings_title"
    static var description = IntentDescription(LocalizedStringResource("widget.settings_description"))

    @Parameter(title: LocalizedStringResource("widget.settings_appearance_label"), default: .system)
    var appearance: WidgetAppearance
}

struct RadarEntry: TimelineEntry {
    let date: Date
    let radarTimestamp: Date?
    let radarImage: UIImage?
    let userCoordinate: CLLocationCoordinate2D?
    let customMarkers: [WidgetCustomMarker]
    let isPlaceholder: Bool
    let appearance: WidgetAppearance
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RadarEntry {
        let userCoordinate = SharedLocationStore.load()?.coordinate
        let customMarkers = SharedCustomMarkerStore.load()
        if let cached = WidgetRadarImageLoader.loadLastImage() {
            return RadarEntry(
                date: Date(),
                radarTimestamp: cached.timestamp,
                radarImage: cached.image,
                userCoordinate: userCoordinate,
                customMarkers: customMarkers,
                isPlaceholder: true,
                appearance: .system
            )
        }
        return RadarEntry(
            date: Date(),
            radarTimestamp: Date.utcNow.roundedToNearestRadarTime,
            radarImage: nil,
            userCoordinate: userCoordinate,
            customMarkers: customMarkers,
            isPlaceholder: true,
            appearance: .system
        )
    }

    func snapshot(for configuration: RadarWidgetConfigurationIntent, in context: Context) async -> RadarEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return await makeEntry(appearance: configuration.appearance)
    }

    func timeline(for configuration: RadarWidgetConfigurationIntent, in context: Context) async -> Timeline<RadarEntry> {
        let entry = await makeEntry(appearance: configuration.appearance)
        let nextRefresh = Date().addingTimeInterval(Date.utcNow.secondsUntilNextRadarUpdate)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func makeEntry(appearance: WidgetAppearance) async -> RadarEntry {
        await MainActor.run {
            WidgetLocationService.shared.requestLocationIfNeeded()
        }
        WidgetUsageStore.markWidgetUsed()
        let userCoordinate = SharedLocationStore.load()?.coordinate
        let customMarkers = SharedCustomMarkerStore.load()
        let latestTimestamp = Date.latestAvailableRadarTimestamp
        if let image = await WidgetRadarImageLoader.fetchImage(for: latestTimestamp) {
            return RadarEntry(
                date: Date(),
                radarTimestamp: latestTimestamp,
                radarImage: image,
                userCoordinate: userCoordinate,
                customMarkers: customMarkers,
                isPlaceholder: false,
                appearance: appearance
            )
        }

        let fallbackTimestamp = latestTimestamp.previousRadarTime
        if let fallbackImage = await WidgetRadarImageLoader.fetchImage(for: fallbackTimestamp) {
            return RadarEntry(
                date: Date(),
                radarTimestamp: fallbackTimestamp,
                radarImage: fallbackImage,
                userCoordinate: userCoordinate,
                customMarkers: customMarkers,
                isPlaceholder: false,
                appearance: appearance
            )
        }

        if let cached = WidgetRadarImageLoader.loadLastImage() {
            return RadarEntry(
                date: Date(),
                radarTimestamp: cached.timestamp,
                radarImage: cached.image,
                userCoordinate: userCoordinate,
                customMarkers: customMarkers,
                isPlaceholder: false,
                appearance: appearance
            )
        }
        return RadarEntry(
            date: Date(),
            radarTimestamp: nil,
            radarImage: nil,
            userCoordinate: userCoordinate,
            customMarkers: customMarkers,
            isPlaceholder: false,
            appearance: appearance
        )
    }
}

struct MeteoradarWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var imageAlignment: Alignment {
        switch family {
        case .systemSmall:
            return .bottom
        default:
            return .center
        }
    }

    private var imageAnchor: UnitPoint {
        switch family {
        case .systemSmall:
            return .bottom
        default:
            return .center
        }
    }

    private var imageAlignmentUnitPoint: UnitPoint {
        switch family {
        case .systemSmall:
            return .bottom
        default:
            return .center
        }
    }

    private var imageScale: CGFloat {
        switch family {
        case .systemSmall:
            return 0.75
        case .systemMedium:
            return 0.9
        case .systemLarge:
            return 0.7
        default:
            return 0.9
        }
    }

    private var timestampAlignment: Alignment {
        switch family {
        case .systemSmall, .systemLarge:
            return .top
        default:
            return .topLeading
        }
    }

    private var timestampPadding: EdgeInsets {
        switch family {
        case .systemSmall, .systemLarge:
            return EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0)
        default:
            return EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 0)
        }
    }


    // Keep vertical guide below timestamp pill.
    private var verticalCrosshairTopInset: CGFloat {
        switch family {
        case .systemSmall:
            return 46
        case .systemLarge:
            return 56
        default:
            return 0
        }
    }

    var body: some View {
        let content = GeometryReader { proxy in
            let imageSize = entry.radarImage?.size
                ?? UIImage(named: "CzechBorderOutline")?.size
                ?? proxy.size
            ZStack {
                ZStack {
                    Image("CzechBorderOutline")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: imageAlignment)
                        .opacity(entry.radarImage == nil ? 0.6 : 1.0)

                    if let image = entry.radarImage {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: imageAlignment)
                    }
                }
                .overlay {
                    ForEach(entry.customMarkers) { marker in
                        if let point = WidgetRadarLayout.point(
                            for: marker.coordinate,
                            containerSize: proxy.size,
                            imageSize: imageSize,
                            alignment: imageAlignmentUnitPoint
                        ) {
                            MarkerLocationDotView(color: marker.color)
                                .position(point)
                        }
                    }
                    if let coordinate = entry.userCoordinate,
                       let point = WidgetRadarLayout.point(
                        for: coordinate,
                        containerSize: proxy.size,
                        imageSize: imageSize,
                        alignment: imageAlignmentUnitPoint
                       ) {
                        LocationDotView()
                            .position(point)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(imageScale, anchor: imageAnchor)
                .clipped()

                if let coordinate = entry.userCoordinate,
                   let point = WidgetRadarLayout.point(
                    for: coordinate,
                    containerSize: proxy.size,
                    imageSize: imageSize,
                    alignment: imageAlignmentUnitPoint
                   ) {
                    let transformedPoint = WidgetRadarLayout.scaledPoint(
                        point,
                        in: proxy.size,
                        scale: imageScale,
                        anchor: imageAnchor
                    )
                    LocationCrosshairLinesView(
                        point: transformedPoint,
                        size: proxy.size,
                        verticalTopInset: verticalCrosshairTopInset
                    )
                }

                WidgetTimestampView(timestamp: entry.radarTimestamp)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: timestampAlignment)
                    .padding(timestampPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }

        if #available(iOS 17.0, *) {
            content
                .containerBackground(entry.appearance.backgroundColor(for: colorScheme), for: .widget)
        } else {
            content
                .background(entry.appearance.backgroundColor(for: colorScheme))
                .padding(-12)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            self.environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}

struct WidgetTimestampView: View {
    let timestamp: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let timestamp = timestamp {
                Text(timestamp.localTimeString)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                Text("--:--")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
        .padding(.top, 4)
        .padding(.leading, 4)
    }
}

struct LocationDotView: View {
    @Environment(\.widgetFamily) private var family

    private var dotSize: CGFloat {
        switch family {
        case .systemExtraLarge:
            return 10
        case .systemLarge:
            return 8
        default:
            return 6
        }
    }

    var body: some View {
        let coreColor = Color(uiColor: .systemRed)
        
        Circle()
            .fill(coreColor)
            .frame(width: dotSize, height: dotSize)
        
    }
}

struct MarkerLocationDotView: View {
    @Environment(\.widgetFamily) private var family
    let color: Color

    private var dotSize: CGFloat {
        switch family {
        case .systemExtraLarge:
            return 10
        case .systemLarge:
            return 8
        default:
            return 6
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
    }
}

struct LocationCrosshairLinesView: View {
    let point: CGPoint
    let size: CGSize
    let verticalTopInset: CGFloat

    var body: some View {
        let clampedVerticalTopInset = min(max(verticalTopInset, 0), size.height)
        let gapRadius: CGFloat = 5.0
        let leftX = max(0, point.x - gapRadius)
        let rightX = min(size.width, point.x + gapRadius)
        let topY = max(clampedVerticalTopInset, point.y - gapRadius)
        let bottomY = min(size.height, point.y + gapRadius)
        Path { path in
            // Horizontal dashed line with a gap around the user dot.
            path.move(to: CGPoint(x: 0, y: point.y))
            path.addLine(to: CGPoint(x: leftX, y: point.y))
            path.move(to: CGPoint(x: rightX, y: point.y))
            path.addLine(to: CGPoint(x: size.width, y: point.y))

            // Vertical dashed line with a gap around the user dot.
            path.move(to: CGPoint(x: point.x, y: clampedVerticalTopInset))
            path.addLine(to: CGPoint(x: point.x, y: topY))
            path.move(to: CGPoint(x: point.x, y: bottomY))
            path.addLine(to: CGPoint(x: point.x, y: size.height))
        }
        .stroke(
            Color.primary.opacity(0.65),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
        )
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

struct MeteoradarWidget: Widget {
    let kind: String = "MeteoradarWidget"

    var body: some WidgetConfiguration {
        let configuration = AppIntentConfiguration(kind: kind, intent: RadarWidgetConfigurationIntent.self, provider: Provider()) { entry in
            let colorScheme = entry.appearance.colorSchemeOverride
            MeteoradarWidgetEntryView(entry: entry)
                .applyColorScheme(colorScheme)
        }
        .configurationDisplayName("Meteoradar")
        .description(String(localized: "widget.description"))

        if #available(iOS 17.0, *) {
            return configuration.contentMarginsDisabled()
        }
        return configuration
    }
}

#Preview(as: .systemSmall) {
    MeteoradarWidget()
} timeline: {
    RadarEntry(
        date: .now,
        radarTimestamp: .now,
        radarImage: nil,
        userCoordinate: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
        customMarkers: [],
        isPlaceholder: true,
        appearance: .system
    )
}
