//
//  ArticleSummarizerTests.swift
//  NetNewsWire-iOSTests
//

import Testing
import Foundation
@testable import NetNewsWire

/// Intercepts all requests made through a session configured with this protocol.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

	nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
	nonisolated(unsafe) static var requests = [URLRequest]()

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		var captured = request
		if let stream = request.httpBodyStream {
			stream.open()
			var data = Data()
			var buffer = [UInt8](repeating: 0, count: 4096)
			while stream.hasBytesAvailable {
				let count = stream.read(&buffer, maxLength: buffer.count)
				if count <= 0 { break }
				data.append(buffer, count: count)
			}
			stream.close()
			captured.httpBody = data
		}
		Self.requests.append(captured)

		let (status, data) = Self.handler?(captured) ?? (500, Data())
		let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: data)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}

	static func reset(responseText: String? = nil, status: Int = 200) {
		requests = []
		handler = { _ in
			let text = responseText ?? "A short summary."
			let json: [String: Any] = ["content": [["type": "text", "text": text]]]
			return (status, (try? JSONSerialization.data(withJSONObject: json)) ?? Data())
		}
	}
}

@Suite(.serialized) struct ArticleSummarizerTests {

	private func makeSummarizer() -> ArticleSummarizer {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [StubURLProtocol.self]
		let suiteName = "ArticleSummarizerTests-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defaults.removePersistentDomain(forName: suiteName)
		return ArticleSummarizer(apiKey: "test-key", session: URLSession(configuration: configuration), cache: defaults)
	}

	@Test func returnsTheSummaryFromTheModel() async throws {
		StubURLProtocol.reset(responseText: "Swift gets faster.")
		let summarizer = makeSummarizer()

		let summary = try await summarizer.summarize(title: "Swift 7", content: "<p>Lots of text</p>")

		#expect(summary == "Swift gets faster.")
	}

	@Test func sendsAuthenticatedHaikuRequestWithTitleAndContent() async throws {
		StubURLProtocol.reset()
		let summarizer = makeSummarizer()

		_ = try await summarizer.summarize(title: "Unique Title 123", content: "Unique body 456")

		let request = try #require(StubURLProtocol.requests.first)
		#expect(request.url?.host == "api.anthropic.com")
		#expect(request.httpMethod == "POST")
		#expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
		#expect(request.value(forHTTPHeaderField: "anthropic-version") != nil)
		let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
		#expect(body.contains("haiku"))
		#expect(body.contains("Unique Title 123"))
		#expect(body.contains("Unique body 456"))
	}

	@Test func secondRequestForSameArticleIsServedFromCache() async throws {
		StubURLProtocol.reset(responseText: "Cached sentence.")
		let summarizer = makeSummarizer()

		let first = try await summarizer.summarize(title: "T", content: "C")
		let second = try await summarizer.summarize(title: "T", content: "C")

		#expect(first == second)
		#expect(StubURLProtocol.requests.count == 1)
	}

	@Test func cachedSummaryIsAvailableSynchronously() async throws {
		StubURLProtocol.reset(responseText: "Instant.")
		let summarizer = makeSummarizer()
		#expect(summarizer.cachedSummary(title: "T", content: "C") == nil)

		_ = try await summarizer.summarize(title: "T", content: "C")

		#expect(summarizer.cachedSummary(title: "T", content: "C") == "Instant.")
	}

	@Test func differentArticlesAreCachedSeparately() async throws {
		StubURLProtocol.reset()
		let summarizer = makeSummarizer()

		_ = try await summarizer.summarize(title: "A", content: "one")
		_ = try await summarizer.summarize(title: "B", content: "two")

		#expect(StubURLProtocol.requests.count == 2)
	}

	@Test func failedRequestThrowsAndIsNotCached() async {
		StubURLProtocol.reset(status: 401)
		let summarizer = makeSummarizer()

		await #expect(throws: (any Error).self) {
			_ = try await summarizer.summarize(title: "T", content: "C")
		}
		#expect(summarizer.cachedSummary(title: "T", content: "C") == nil)
	}
}

@Suite struct ArticleSummaryBannerTests {

	@Test func loadingBannerShowsTitleMessageAndSpinner() {
		let html = ArticleSummaryBanner.html(for: .loading)
		#expect(html.contains("AI Summary"))
		#expect(html.contains("Summarizing"))
		#expect(html.contains("spinner"))
	}

	@Test func loadedBannerShowsSummaryOnYellowBackground() {
		let html = ArticleSummaryBanner.html(for: .loaded("One sentence."))
		#expect(html.contains("AI Summary"))
		#expect(html.contains("One sentence."))
		#expect(html.lowercased().contains("#fff3b0") || html.lowercased().contains("yellow"))
	}

	@Test func summaryTextIsHTMLEscaped() {
		let html = ArticleSummaryBanner.html(for: .loaded("<script>alert(1)</script>"))
		#expect(!html.contains("<script>alert"))
		#expect(html.contains("&lt;script&gt;"))
	}

	@Test func failedBannerShowsMessage() {
		let html = ArticleSummaryBanner.html(for: .failed("Could not summarize"))
		#expect(html.contains("AI Summary"))
		#expect(html.contains("Could not summarize"))
	}

	@Test func bannerHasStableElementID() {
		#expect(ArticleSummaryBanner.html(for: .loading).contains("id=\"ai-summary-banner\""))
	}
}
