//
//  ArticleSummarizer.swift
//  NetNewsWire
//

import Foundation
import RSCore

/// Produces a short summary for an article.
protocol Summarizing: Sendable {
	func summarize(title: String, content: String) async throws -> String
}

/// The text-generation engine behind `ArticleSummarizer`.
protocol SummaryGenerating: Sendable {
	func generate(prompt: String) async throws -> String
}

/// Summarizes article content into one sentence using an on-device language model.
/// Callers pass only the title and content; model details stay in here.
final class ArticleSummarizer: Summarizing {

	enum SummarizerError: Error {
		case noContent
		case emptySummary
	}

	static let shared = ArticleSummarizer()

	private static let maxContentCharacters = 6000

	private let generator: SummaryGenerating

	init(generator: SummaryGenerating = MLXSummaryGenerator()) {
		self.generator = generator
	}

	func summarize(title: String, content: String) async throws -> String {
		let text = content.strippingHTML(maxCharacters: Self.maxContentCharacters)
		guard !text.isEmpty else {
			throw SummarizerError.noContent
		}

		let prompt = """
		Summarize the following article in exactly one short sentence. Reply with only that sentence.

		Title: \(title)

		Article:
		\(text)
		"""

		let output = try await generator.generate(prompt: prompt)
		let summary = Self.firstSentence(of: Self.removingThinking(from: output))
		guard !summary.isEmpty else {
			throw SummarizerError.emptySummary
		}
		return summary
	}
}

private extension ArticleSummarizer {

	/// Qwen3 models may emit a `<think>…</think>` reasoning block before the answer.
	static func removingThinking(from output: String) -> String {
		var result = output
		while let start = result.range(of: "<think>") {
			if let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
				result.removeSubrange(start.lowerBound..<end.upperBound)
			} else {
				result.removeSubrange(start.lowerBound..<result.endIndex)
			}
		}
		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	static func firstSentence(of text: String) -> String {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		var sentence: String?
		trimmed.enumerateSubstrings(in: trimmed.startIndex..<trimmed.endIndex, options: [.bySentences]) { substring, _, _, stop in
			sentence = substring
			stop = true
		}
		return (sentence ?? trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
