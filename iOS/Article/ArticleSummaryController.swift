//
//  ArticleSummaryController.swift
//  NetNewsWire
//

import Foundation
import os
import RSCore

/// Drives the summary banner state: serves cached summaries instantly, otherwise
/// asks the summarizer and caches the result.
@MainActor final class ArticleSummaryController {

	private static let logger = Logger(subsystem: Logger.nnwSubsystem, category: "ArticleSummaryController")

	private(set) var state = ArticleSummaryState.idle
	var onStateChange: ((ArticleSummaryState) -> Void)?

	private let summarizer: Summarizing
	private let cache: SummaryCache
	private var generation = 0

	init(summarizer: Summarizing = ArticleSummarizer.shared, cache: SummaryCache = SummaryCache()) {
		self.summarizer = summarizer
		self.cache = cache
	}

	func summarize(articleID: String, title: String, content: String) async {
		if let cached = cache.summary(for: articleID) {
			setState(.loaded(cached))
			return
		}

		if state == .loading {
			return
		}
		setState(.loading)
		let requestGeneration = generation

		do {
			let summary = try await summarizer.summarize(title: title, content: content)
			cache.setSummary(summary, for: articleID)
			if requestGeneration == generation {
				setState(.loaded(summary))
			}
		} catch {
			Self.logger.error("Summary failed for article \(articleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
			if requestGeneration == generation {
				setState(.failed)
			}
		}
	}

	/// Hides the banner and discards the result of any request still in flight.
	func reset() {
		generation += 1
		setState(.idle)
	}

	private func setState(_ newState: ArticleSummaryState) {
		state = newState
		onStateChange?(newState)
	}
}
