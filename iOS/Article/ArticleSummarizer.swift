//
//  ArticleSummarizer.swift
//  NetNewsWire
//
//  Generates a one-sentence summary of an article using Anthropic's Haiku model.
//  Summaries are cached in the app's shared UserDefaults, so asking again is instant.
//

import Foundation
import CryptoKit
import os

final class ArticleSummarizer: @unchecked Sendable {

	enum SummarizerError: Error {
		case missingAPIKey
		case badResponse(statusCode: Int)
		case emptySummary
	}

	/// The app-wide summarizer. The API key is read from the `ANTHROPIC_API_KEY` environment variable.
	static let shared = ArticleSummarizer(apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "")

	private static let logger = Logger(subsystem: Logger.nnwSubsystem, category: "ArticleSummarizer")
	private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
	private static let model = "claude-haiku-4-5-20251001"
	private static let maximumContentLength = 8000
	private static let cacheKeyPrefix = "articleSummary."

	private let apiKey: String
	private let session: URLSession
	private let cache: UserDefaults

	init(apiKey: String, session: URLSession = .shared, cache: UserDefaults = AppDefaults.store) {
		self.apiKey = apiKey
		self.session = session
		self.cache = cache
	}

	/// The previously generated summary for this article, if any.
	func cachedSummary(title: String, content: String) -> String? {
		return cache.string(forKey: Self.cacheKey(title: title, content: content))
	}

	/// Returns a one-sentence summary. Served from cache when available; otherwise asks the model.
	func summarize(title: String, content: String) async throws -> String {
		if let cached = cachedSummary(title: title, content: content) {
			return cached
		}
		guard !apiKey.isEmpty else {
			throw SummarizerError.missingAPIKey
		}

		var request = URLRequest(url: Self.endpoint)
		request.httpMethod = "POST"
		request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
		request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
		request.setValue("application/json", forHTTPHeaderField: "content-type")
		request.httpBody = try JSONSerialization.data(withJSONObject: Self.requestBody(title: title, content: content))

		let (data, response) = try await session.data(for: request)
		if let statusCode = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(statusCode) {
			Self.logger.error("Summary request failed with status \(statusCode)")
			throw SummarizerError.badResponse(statusCode: statusCode)
		}

		let summary = try Self.parseSummary(from: data)
		cache.set(summary, forKey: Self.cacheKey(title: title, content: content))
		return summary
	}
}

private extension ArticleSummarizer {

	static func requestBody(title: String, content: String) -> [String: Any] {
		let text = plainText(fromHTML: content)
		let prompt = """
		Summarize this article in one short sentence. Reply with only the sentence.

		Title: \(title)

		\(text.prefix(maximumContentLength))
		"""
		return [
			"model": model,
			"max_tokens": 150,
			"messages": [["role": "user", "content": prompt]]
		]
	}

	static func parseSummary(from data: Data) throws -> String {
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let blocks = json["content"] as? [[String: Any]],
			  let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
			throw SummarizerError.emptySummary
		}
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw SummarizerError.emptySummary
		}
		return trimmed
	}

	static func plainText(fromHTML html: String) -> String {
		return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
	}

	static func cacheKey(title: String, content: String) -> String {
		let digest = SHA256.hash(data: Data((title + "\n" + content).utf8))
		return cacheKeyPrefix + digest.map { String(format: "%02x", $0) }.joined()
	}
}
