//
//  WidgetUsageStore.swift
//  Meteoradar
//
//  Shared widget usage tracking for app + widget.
//

import Foundation

enum WidgetUsageStore {
    private static let lastUsedKey = "WidgetUsageLastUsedTimestamp"
    private static let messageShownKey = "WidgetUsageMessageShown"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedLocationStore.appGroupID)
    }

    static func markWidgetUsed(timestamp: Date = Date()) {
        defaults?.set(timestamp.timeIntervalSince1970, forKey: lastUsedKey)
    }

    static func hasWidgetBeenUsed() -> Bool {
        (defaults?.double(forKey: lastUsedKey) ?? 0) > 0
    }

    static func shouldShowUsageMessage() -> Bool {
        hasWidgetBeenUsed() && !(defaults?.bool(forKey: messageShownKey) ?? false)
    }

    static func markUsageMessageShown() {
        defaults?.set(true, forKey: messageShownKey)
    }
}
