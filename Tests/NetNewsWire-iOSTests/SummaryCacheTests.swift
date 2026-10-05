//
//  SummaryCacheTests.swift
//  NetNewsWire-iOSTests
//

import Testing
import Foundation
@testable import NetNewsWire

@Suite struct SummaryCacheTests {

	private func makeStore() -> UserDefaults {
		let suiteName = "SummaryCacheTests-\(UUID().uuidString)"
		return UserDefaults(suiteName: suiteName)!
	}

	@Test func missReturnsNil() {
		let cache = SummaryCache(store: makeStore())
		#expect(cache.summary(for: "article-1") == nil)
	}

	@Test func storedSummaryIsReturned() {
		let cache = SummaryCache(store: makeStore())
		cache.setSummary("A short summary.", for: "article-1")
		#expect(cache.summary(for: "article-1") == "A short summary.")
	}

	@Test func summariesAreKeptPerArticle() {
		let cache = SummaryCache(store: makeStore())
		cache.setSummary("First.", for: "article-1")
		cache.setSummary("Second.", for: "article-2")
		#expect(cache.summary(for: "article-1") == "First.")
		#expect(cache.summary(for: "article-2") == "Second.")
	}

	@Test func summariesSurviveANewCacheInstanceOnTheSameStore() {
		let store = makeStore()
		SummaryCache(store: store).setSummary("Persisted.", for: "article-1")
		#expect(SummaryCache(store: store).summary(for: "article-1") == "Persisted.")
	}
}
