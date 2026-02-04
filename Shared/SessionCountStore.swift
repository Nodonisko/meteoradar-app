//
//  SessionCountStore.swift
//  Meteoradar
//
//  Tracks number of app sessions (cold starts + resumes from background).
//

import Foundation

enum SessionCountStore {
    private static let sessionCountKey = "AppSessionCount"

    private static var defaults: UserDefaults {
        UserDefaults.standard
    }

    @discardableResult
    static func incrementSessionCount() -> Int {
        let newCount = defaults.integer(forKey: sessionCountKey) + 1
        defaults.set(newCount, forKey: sessionCountKey)
        return newCount
    }

    static func sessionCount() -> Int {
        defaults.integer(forKey: sessionCountKey)
    }
}
