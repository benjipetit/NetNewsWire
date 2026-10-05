//
//  SummaryCache.swift
//  NetNewsWire
//

import Foundation

/// Persists generated article summaries, keyed by article ID, in the app’s key-value store.
struct SummaryCache {

	private static let keyPrefix = "articleSummary."

	private let store: UserDefaults

	init(store: UserDefaults = AppDefaults.store) {
		self.store = store
	}

	func summary(for articleID: String) -> String? {
		store.string(forKey: Self.key(for: articleID))
	}

	func setSummary(_ summary: String, for articleID: String) {
		store.set(summary, forKey: Self.key(for: articleID))
	}

	private static func key(for articleID: String) -> String {
		keyPrefix + articleID
	}
}
