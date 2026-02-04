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
        if let uiColor = UIColor(named: "WidgetBackground", in: .main, compatibleWith: traitCollection) {
            return Color(uiColor: uiColor)
        }
        return Color("WidgetBackground")
    }
}

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
    let isPlaceholder: Bool
    let appearance: WidgetAppearance
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RadarEntry {
        let userCoordinate = SharedLocationStore.load()?.coordinate
        if let cached = WidgetRadarImageLoader.loadLastImage() {
            return RadarEntry(
                date: Date(),
                radarTimestamp: cached.timestamp,
                radarImage: cached.image,
                userCoordinate: userCoordinate,
                isPlaceholder: true,
                appearance: .system
            )
        }
        return RadarEntry(
            date: Date(),
            radarTimestamp: Date.utcNow.roundedToNearestRadarTime,
            radarImage: nil,
            userCoordinate: userCoordinate,
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
        let latestTimestamp = Date.latestAvailableRadarTimestamp
        if let image = await WidgetRadarImageLoader.fetchImage(for: latestTimestamp) {
            return RadarEntry(
                date: Date(),
                radarTimestamp: latestTimestamp,
                radarImage: image,
                userCoordinate: userCoordinate,
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
                isPlaceholder: false,
                appearance: appearance
            )
        }
        return RadarEntry(
            date: Date(),
            radarTimestamp: nil,
            radarImage: nil,
            userCoordinate: userCoordinate,
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
                        .scaleEffect(imageScale, anchor: imageAnchor)
                        .clipped()
                        .opacity(entry.radarImage == nil ? 0.6 : 1.0)

                    if let image = entry.radarImage {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: imageAlignment)
                            .scaleEffect(imageScale, anchor: imageAnchor)
                            .clipped()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                if let coordinate = entry.userCoordinate,
                   let point = WidgetRadarLayout.point(
                    for: coordinate,
                    containerSize: proxy.size,
                    imageSize: imageSize,
                    alignment: imageAlignmentUnitPoint,
                    scale: imageScale,
                    anchor: imageAnchor
                   ) {
                    LocationDotView()
                        .position(point)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let coreColor = Color(red: 1.0, green: 0.23, blue: 0.19)
        
        Circle()
            .fill(coreColor)
            .frame(width: 6, height: 6)
        
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
        isPlaceholder: true,
        appearance: .system
    )
}
