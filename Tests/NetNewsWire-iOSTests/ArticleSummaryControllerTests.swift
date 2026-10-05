//
//  ArticleSummaryControllerTests.swift
//  NetNewsWire-iOSTests
//

import Testing
import Foundation
@testable import NetNewsWire

private final class StubSummarizer: Summarizing, @unchecked Sendable {
	var result: Result<String, Error> = .success("A summary.")
	private(set) var callCount = 0
	var delay: Duration = .zero

	func summarize(title: String, content: String) async throws -> String {
		callCount += 1
		try await Task.sleep(for: delay)
		return try result.get()
	}
}

@MainActor @Suite struct ArticleSummaryControllerTests {

	private func makeCache() -> SummaryCache {
		SummaryCache(store: UserDefaults(suiteName: "ArticleSummaryControllerTests-\(UUID().uuidString)")!)
	}

	@Test func startsIdle() {
		let controller = ArticleSummaryController(summarizer: StubSummarizer(), cache: makeCache())
		#expect(controller.state == .idle)
	}

	@Test func goesThroughLoadingThenLoaded() async {
		let summarizer = StubSummarizer()
		let controller = ArticleSummaryController(summarizer: summarizer, cache: makeCache())
		var states = [ArticleSummaryState]()
		controller.onStateChange = { states.append($0) }

		await controller.summarize(articleID: "a1", title: "T", content: "Body")

		#expect(states == [.loading, .loaded("A summary.")])
		#expect(controller.state == .loaded("A summary."))
	}

	@Test func resultIsCachedAndSecondRequestIsInstant() async {
		let summarizer = StubSummarizer()
		let cache = makeCache()
		let controller = ArticleSummaryController(summarizer: summarizer, cache: cache)

		await controller.summarize(articleID: "a1", title: "T", content: "Body")
		#expect(cache.summary(for: "a1") == "A summary.")

		var states = [ArticleSummaryState]()
		controller.onStateChange = { states.append($0) }
		await controller.summarize(articleID: "a1", title: "T", content: "Body")

		#expect(summarizer.callCount == 1)
		#expect(states == [.loaded("A summary.")])
	}

	@Test func cachedSummaryFromEarlierSessionIsUsedWithoutTheModel() async {
		let summarizer = StubSummarizer()
		let cache = makeCache()
		cache.setSummary("Cached one.", for: "a1")
		let controller = ArticleSummaryController(summarizer: summarizer, cache: cache)

		await controller.summarize(articleID: "a1", title: "T", content: "Body")

		#expect(summarizer.callCount == 0)
		#expect(controller.state == .loaded("Cached one."))
	}

	@Test func failureIsReportedAndNotCached() async {
		struct Boom: Error {}
		let summarizer = StubSummarizer()
		summarizer.result = .failure(Boom())
		let cache = makeCache()
		let controller = ArticleSummaryController(summarizer: summarizer, cache: cache)

		await controller.summarize(articleID: "a1", title: "T", content: "Body")

		#expect(controller.state == .failed)
		#expect(cache.summary(for: "a1") == nil)
	}

	@Test func requestWhileLoadingDoesNotStartASecondGeneration() async {
		let summarizer = StubSummarizer()
		summarizer.delay = .milliseconds(100)
		let controller = ArticleSummaryController(summarizer: summarizer, cache: makeCache())

		async let first: Void = controller.summarize(articleID: "a1", title: "T", content: "Body")
		try? await Task.sleep(for: .milliseconds(20))
		await controller.summarize(articleID: "a1", title: "T", content: "Body")
		await first

		#expect(summarizer.callCount == 1)
	}
}
