//
//  ArticleSummaryBanner.swift
//  NetNewsWire
//
//  HTML for the yellow "AI Summary" banner embedded at the top of an article.
//

import Foundation

enum ArticleSummaryBanner {

	enum State: Equatable {
		case loading
		case loaded(String)
		case failed(String)
	}

	static let elementID = "ai-summary-banner"

	static func html(for state: State) -> String {
		let content: String
		switch state {
		case .loading:
			content = "<div class=\"ai-summary-body\"><span class=\"spinner\"></span>Summarizing…</div>"
		case .loaded(let summary):
			content = "<div class=\"ai-summary-body\">\(escaped(summary))</div>"
		case .failed(let message):
			content = "<div class=\"ai-summary-body\">\(escaped(message))</div>"
		}

		return """
		<style>
		#\(elementID) { background: #FFF3B0; color: #3A3000; border-radius: 10px; padding: 12px 14px; margin: 0 0 16px 0; font-size: 15px; line-height: 1.4; }
		#\(elementID) .ai-summary-title { font-weight: 700; font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 6px; }
		#\(elementID) .spinner { display: inline-block; width: 14px; height: 14px; margin-right: 8px; vertical-align: -2px; border: 2px solid #3A3000; border-top-color: transparent; border-radius: 50%; animation: ai-summary-spin 0.8s linear infinite; }
		@keyframes ai-summary-spin { to { transform: rotate(360deg); } }
		</style>
		<div id="\(elementID)"><div class="ai-summary-title">AI Summary</div>\(content)</div>
		"""
	}

	/// JavaScript that inserts or replaces the banner in an already-loaded page.
	static func updateScript(for state: State) -> String {
		let encoded = (try? JSONSerialization.data(withJSONObject: [html(for: state)])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
		return """
		(function() {
			var html = \(encoded)[0];
			var existing = document.getElementById('\(elementID)');
			if (existing) {
				var previous = existing.previousElementSibling;
				if (previous && previous.tagName === 'STYLE') { previous.remove(); }
				existing.remove();
			}
			document.body.insertAdjacentHTML('afterbegin', html);
		})();
		"""
	}

	private static func escaped(_ text: String) -> String {
		return text
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}
}
