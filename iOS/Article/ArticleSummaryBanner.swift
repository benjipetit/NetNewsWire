//
//  ArticleSummaryBanner.swift
//  NetNewsWire
//

import Foundation

enum ArticleSummaryState: Equatable {
	case idle
	case loading
	case loaded(String)
	case failed
}

/// HTML and CSS for the yellow “AI Summary” banner embedded at the top of an article.
enum ArticleSummaryBanner {

	static let elementID = "nnw-ai-summary"

	static let css = """
	#nnw-ai-summary {
		background: #FFF3B0;
		color: #3B3200;
		border-radius: 10px;
		padding: 12px 14px;
		margin: 0 0 20px 0;
		font-size: 0.9em;
		line-height: 1.4;
	}
	#nnw-ai-summary .nnw-summary-title {
		font-weight: 700;
		margin-bottom: 4px;
	}
	#nnw-ai-summary .nnw-summary-text {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.nnw-summary-spinner {
		flex: none;
		width: 14px;
		height: 14px;
		border: 2px solid rgba(59, 50, 0, 0.25);
		border-top-color: #3B3200;
		border-radius: 50%;
		animation: nnw-summary-spin 0.9s linear infinite;
	}
	@keyframes nnw-summary-spin { to { transform: rotate(360deg); } }
	"""

	static func html(for state: ArticleSummaryState) -> String {
		let message: String
		switch state {
		case .idle:
			return ""
		case .loading:
			message = "<span class=\"nnw-summary-spinner\"></span><span>" + NSLocalizedString("Summarizing on this device", comment: "AI summary loading message") + "</span>"
		case .loaded(let summary):
			message = "<span>" + escaped(summary) + "</span>"
		case .failed:
			message = "<span>" + NSLocalizedString("Couldn’t generate a summary.", comment: "AI summary failure message") + "</span>"
		}

		let title = NSLocalizedString("AI Summary", comment: "AI summary banner title")
		return "<div id=\"\(elementID)\"><div class=\"nnw-summary-title\">\(title)</div><div class=\"nnw-summary-text\">\(message)</div></div>"
	}

	/// The `<style>` element plus banner, to prepend to an article body.
	static func bodyPrefix(for state: ArticleSummaryState) -> String {
		let banner = html(for: state)
		guard !banner.isEmpty else {
			return ""
		}
		return "<style>\(css)</style>" + banner
	}

	/// JavaScript that replaces the banner in the live page without re-rendering the article.
	static func updateScript(for state: ArticleSummaryState) -> String {
		let banner = html(for: state)
		let bannerLiteral = jsStringLiteral(banner)
		let styleLiteral = jsStringLiteral(css)
		return """
		(function() {
			var existing = document.getElementById('\(elementID)');
			if (existing) { existing.remove(); }
			if (!\(bannerLiteral)) { return; }
			if (!document.getElementById('\(elementID)-style')) {
				var style = document.createElement('style');
				style.id = '\(elementID)-style';
				style.textContent = \(styleLiteral);
				document.head.appendChild(style);
			}
			var container = document.getElementById('bodyContainer') || document.body;
			container.insertAdjacentHTML('afterbegin', \(bannerLiteral));
		})();
		"""
	}
}

private extension ArticleSummaryBanner {

	static func escaped(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}

	static func jsStringLiteral(_ string: String) -> String {
		guard let data = try? JSONEncoder().encode(string), let literal = String(data: data, encoding: .utf8) else {
			return "\"\""
		}
		return literal
	}
}
