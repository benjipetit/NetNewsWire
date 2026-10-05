//
//  ArticleSummaryBannerTests.swift
//  NetNewsWire-iOSTests
//

import Testing
@testable import NetNewsWire

@Suite struct ArticleSummaryBannerTests {

	@Test func idleRendersNothing() {
		#expect(ArticleSummaryBanner.html(for: .idle).isEmpty)
	}

	@Test func loadingShowsTitleAndProgressMessage() {
		let html = ArticleSummaryBanner.html(for: .loading)
		#expect(html.contains("AI Summary"))
		#expect(html.contains("Summarizing"))
		#expect(html.contains("nnw-summary-spinner"))
	}

	@Test func loadedShowsTitleAndSummary() {
		let html = ArticleSummaryBanner.html(for: .loaded("The article explains X."))
		#expect(html.contains("AI Summary"))
		#expect(html.contains("The article explains X."))
		#expect(!html.contains("nnw-summary-spinner"))
	}

	@Test func loadedSummaryIsHTMLEscaped() {
		let html = ArticleSummaryBanner.html(for: .loaded("<script>alert(1)</script> & more"))
		#expect(!html.contains("<script>"))
		#expect(html.contains("&lt;script&gt;"))
		#expect(html.contains("&amp; more"))
	}

	@Test func failedShowsAnError() {
		let html = ArticleSummaryBanner.html(for: .failed)
		#expect(html.contains("AI Summary"))
		#expect(html.contains("Couldn"))
	}

	@Test func bannerHasYellowBackgroundAndStableID() {
		let html = ArticleSummaryBanner.html(for: .loading)
		#expect(html.contains("id=\"\(ArticleSummaryBanner.elementID)\""))
		#expect(ArticleSummaryBanner.css.contains("background"))
		#expect(ArticleSummaryBanner.css.lowercased().contains("#fff3b0"))
	}
}
