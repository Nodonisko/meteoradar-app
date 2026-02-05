//
//  ChangelogService.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 30.01.2026.
//

import Foundation

final class ChangelogService {
    static let shared = ChangelogService()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let lastSeenVersion = "changelog.lastSeenVersion"
    }
    
    private init() {
        // We don't want to show the changelog to first time users
        seedLastSeenVersionIfNeeded()
    }
    
    var currentVersionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        
        switch (shortVersion, buildVersion) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return short
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return ""
        }
    }
    
    var shouldShowChangelog: Bool {
        seedLastSeenVersionIfNeeded()
        let current = currentVersionString
        guard !current.isEmpty else { return false }
        let lastSeen = defaults.string(forKey: Keys.lastSeenVersion)
        return lastSeen != current
    }
    
    func markChangelogShown() {
        let current = currentVersionString
        guard !current.isEmpty else { return }
        defaults.set(current, forKey: Keys.lastSeenVersion)
    }

    private func seedLastSeenVersionIfNeeded() {
        guard defaults.string(forKey: Keys.lastSeenVersion) == nil else { return }
        let current = currentVersionString
        guard !current.isEmpty else { return }
        defaults.set(current, forKey: Keys.lastSeenVersion)
    }
}
