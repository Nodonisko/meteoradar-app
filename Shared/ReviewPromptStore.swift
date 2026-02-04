//
//  ReviewPromptStore.swift
//  Meteoradar
//
//  Tracks if review prompt has been completed.
//

import Foundation

enum ReviewPromptStore {
    private static let reviewCompletedKey = "ReviewPromptCompleted"
    private static let minimumSessionsForPrompt = 30

    private static var defaults: UserDefaults {
        UserDefaults.standard
    }

    static func shouldPromptReview(sessionCount: Int) -> Bool {
        sessionCount > minimumSessionsForPrompt && !defaults.bool(forKey: reviewCompletedKey)
    }

    static func markCompleted() {
        defaults.set(true, forKey: reviewCompletedKey)
    }
}
