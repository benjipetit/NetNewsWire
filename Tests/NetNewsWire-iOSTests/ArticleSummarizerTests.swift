//
//  ArticleSummarizerTests.swift
//  NetNewsWire-iOSTests
//

import Testing
import Foundation
@testable import NetNewsWire

private final class StubGenerator: SummaryGenerating, @unchecked Sendable {
	var output: String
	private(set) var prompts = [String]()

	init(output: String) {
		self.output = output
	}

	func generate(prompt: String) async throws -> String {
		prompts.append(prompt)
		return output
	}
}

@Suite struct ArticleSummarizerTests {

	@Test func promptContainsTitleAndContent() async throws {
		let generator = StubGenerator(output: "Done.")
		let summarizer = ArticleSummarizer(generator: generator)
		_ = try await summarizer.summarize(title: "Swift 7 Released", content: "<p>Swift 7 brings <b>new</b> concurrency.</p>")
		let prompt = try #require(generator.prompts.first)
		#expect(prompt.contains("Swift 7 Released"))
		#expect(prompt.contains("Swift 7 brings new concurrency."))
		#expect(!prompt.contains("<p>"))
	}

	@Test func longContentIsTruncated() async throws {
		let generator = StubGenerator(output: "Done.")
		let summarizer = ArticleSummarizer(generator: generator)
		_ = try await summarizer.summarize(title: "T", content: String(repeating: "word ", count: 20_000))
		let prompt = try #require(generator.prompts.first)
		#expect(prompt.count < 12_000)
	}

	@Test func thinkingBlockIsRemoved() async throws {
		let generator = StubGenerator(output: "<think>\nLet me consider.\n</think>\n\nThe article explains X.")
		let summarizer = ArticleSummarizer(generator: generator)
		let summary = try await summarizer.summarize(title: "T", content: "Body")
		#expect(summary == "The article explains X.")
	}

	@Test func onlyFirstSentenceIsReturned() async throws {
		let generator = StubGenerator(output: "  It covers X. It also covers Y.  ")
		let summarizer = ArticleSummarizer(generator: generator)
		let summary = try await summarizer.summarize(title: "T", content: "Body")
		#expect(summary == "It covers X.")
	}

	@Test func emptyContentThrowsWithoutCallingTheModel() async {
		let generator = StubGenerator(output: "Unused.")
		let summarizer = ArticleSummarizer(generator: generator)
		await #expect(throws: ArticleSummarizer.SummarizerError.self) {
			_ = try await summarizer.summarize(title: "T", content: "   <p> </p> ")
		}
		#expect(generator.prompts.isEmpty)
	}

	@Test func emptyModelOutputThrows() async {
		let generator = StubGenerator(output: "<think>hmm</think>")
		let summarizer = ArticleSummarizer(generator: generator)
		await #expect(throws: ArticleSummarizer.SummarizerError.self) {
			_ = try await summarizer.summarize(title: "T", content: "Body")
		}
	}
}
