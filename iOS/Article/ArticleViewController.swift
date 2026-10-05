//
//  ArticleViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import FoundationModels
import os
import SafariServices
import WebKit
import RSCore
import Account
import Articles

final class ArticleViewController: UIViewController {

	typealias State = (extractedArticle: ExtractedArticle?,
		isShowingExtractedArticle: Bool,
		articleExtractorButtonState: ArticleExtractorButtonState,
		windowScrollY: Int)

	@IBOutlet private weak var nextUnreadBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var prevArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var nextArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var readBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var starBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var actionBarButtonItem: UIBarButtonItem!

	@IBOutlet private var searchBar: ArticleSearchBar!
	@IBOutlet private var searchBarBottomConstraint: NSLayoutConstraint!
	private var defaultControls: [UIBarButtonItem]?
	private var summarizeBarButtonItem: UIBarButtonItem!
	private var summaryTask: Task<Void, Never>?
	private static var summaryCache = [String: String]()
	private static let maximumSummaryInputCharacters = 12_000
	private static let maximumSummaryResponseTokens = 250

	private var pageViewController: UIPageViewController!
	private var isPageTransitionInProgress = false
	private var pendingSetViewController: WebViewController?

	private var currentWebViewController: WebViewController? {
		return pageViewController?.viewControllers?.first as? WebViewController
	}

	private var articleExtractorButton: ArticleExtractorButton = {
		let button = ArticleExtractorButton(type: .system)
		button.frame = CGRect(x: 0, y: 0, width: 44.0, height: 44.0)
		button.setImage(Assets.Images.articleExtractorOff, for: .normal)
		if #unavailable(iOS 26) {
			button.tintColor = Assets.Colors.primaryAccent
		} else {
			button.tintColor = .label
		}
		return button
	}()

	weak var coordinator: SceneCoordinator!

	private let poppableDelegate = PoppableGestureRecognizerDelegate()
	private weak var originalPopGestureRecognizerDelegate: UIGestureRecognizerDelegate?
	private static let logger = Logger(subsystem: Logger.nnwSubsystem, category: "ArticleViewController")

	var article: Article? {
		didSet {
			Self.logger.debug("ArticleViewController: article didSet: \(self.article?.accountID ?? "nil") \(self.article?.articleID ?? "nil") \(self.article?.title ?? "nil")")

			if oldValue != article {
				// The launch-restoration scroll position belongs only to the restored article.
				// <https://github.com/Ranchero-Software/NetNewsWire/issues/5243>
				restoreScrollPosition = nil
				summaryTask?.cancel()
			}

			if let controller = currentWebViewController, controller.article != article {
				controller.setArticle(article)
				controller.hideSummaryBanner()
				if isPageTransitionInProgress {
					// Calling setViewControllers during an active page transition trips a UIPageViewController
					// internal assertion (NSInternalInconsistencyException) and crashes the app. Stash the
					// controller and flush it from didFinishAnimating once the transition has ended.
					pendingSetViewController = controller
				} else {
					DispatchQueue.main.async {
						// You have to set the view controller to clear out the UIPageViewController child controller cache.
						// You also have to do it in an async call or you will get a strange assertion error.
						// Re-check the transition state: a user swipe between enqueue and execution can flip
						// isPageTransitionInProgress to true, and calling setViewControllers then would crash.
						if self.isPageTransitionInProgress {
							self.pendingSetViewController = controller
						} else {
							self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
							self.syncArticleExtractorButtonState()
						}
					}
				}
			}
			updateUI()
			syncArticleExtractorButtonState()
		}
	}

	var restoreScrollPosition: (isShowingExtractedArticle: Bool, articleWindowScrollY: Int)? {
		didSet {
			if let rsp = restoreScrollPosition {
				currentWebViewController?.setScrollPosition(isShowingExtractedArticle: rsp.isShowingExtractedArticle, articleWindowScrollY: rsp.articleWindowScrollY)
			}
		}
	}

	var currentState: State? {
		guard let controller = currentWebViewController else { return nil}
		return State(extractedArticle: controller.extractedArticle,
					 isShowingExtractedArticle: controller.isShowingExtractedArticle,
					 articleExtractorButtonState: controller.articleExtractorButtonState,
					 windowScrollY: controller.windowScrollY)
	}

	var restoreState: State?

	private let keyboardManager = KeyboardManager(type: .detail)
	override var keyCommands: [UIKeyCommand]? {
		return keyboardManager.keyCommands
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)

		let appearance = UINavigationBarAppearance()
		appearance.configureWithDefaultBackground()
		navigationItem.standardAppearance = appearance
		navigationItem.scrollEdgeAppearance = appearance
		navigationItem.compactAppearance = appearance

		let fullScreenTapZone = UIView()
		NSLayoutConstraint.activate([
			fullScreenTapZone.widthAnchor.constraint(equalToConstant: 150),
			fullScreenTapZone.heightAnchor.constraint(equalToConstant: 44)
		])
		fullScreenTapZone.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapNavigationBar)))
		navigationItem.titleView = fullScreenTapZone

		articleExtractorButton.addTarget(self, action: #selector(toggleArticleExtractor(_:)), for: .touchUpInside)
		let articleExtractorBarButtonItem = UIBarButtonItem(customView: articleExtractorButton)
		summarizeBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "sparkles"),
												 style: .plain,
												 target: self,
												 action: #selector(summarizeArticle(_:)))
		summarizeBarButtonItem.accessibilityLabel = NSLocalizedString("Summarize Article", comment: "Summarize Article")

		if #available(iOS 26, *) {
			toolbarItems?.insert(summarizeBarButtonItem, at: 5)
			toolbarItems?.insert(articleExtractorBarButtonItem, at: 6)
		} else {
			let flex = { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
			toolbarItems = [
				readBarButtonItem,
				flex(),
				starBarButtonItem,
				flex(),
				nextUnreadBarButtonItem,
				flex(),
				summarizeBarButtonItem,
				flex(),
				articleExtractorBarButtonItem,
				flex(),
				actionBarButtonItem
			]
		}

		pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [:])
		pageViewController.delegate = self
		pageViewController.dataSource = self

		// This code is to disallow paging if we scroll from the left edge.  If this code is removed
		// PoppableGestureRecognizerDelegate will allow us to both navigate back and page back at the
		// same time. That is really weird when it happens.
		let panGestureRecognizer = UIPanGestureRecognizer()
		panGestureRecognizer.delegate = self
		pageViewController.scrollViewInsidePageControl?.addGestureRecognizer(panGestureRecognizer)

		pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(pageViewController.view)
		addChild(pageViewController!)
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: pageViewController.view.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: pageViewController.view.trailingAnchor),
			view.topAnchor.constraint(equalTo: pageViewController.view.topAnchor),
			view.bottomAnchor.constraint(equalTo: pageViewController.view.bottomAnchor)
		])

		let controller: WebViewController
		if let state = restoreState {
			controller = createWebViewController(article, updateView: false)
			controller.extractedArticle = state.extractedArticle
			controller.isShowingExtractedArticle = state.isShowingExtractedArticle
			controller.articleExtractorButtonState = state.articleExtractorButtonState
			controller.windowScrollY = state.windowScrollY
		} else {
			controller = createWebViewController(article, updateView: true)
		}

		if let rsp = restoreScrollPosition {
			controller.setScrollPosition(isShowingExtractedArticle: rsp.isShowingExtractedArticle, articleWindowScrollY: rsp.articleWindowScrollY)
		}

		articleExtractorButton.buttonState = controller.articleExtractorButtonState

		self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			controller.hideBars()
		}

		// Search bar
		searchBar.translatesAutoresizingMaskIntoConstraints = false
		NotificationCenter.default.addObserver(self, selector: #selector(beginFind(_:)), name: .FindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(endFind(_:)), name: .EndFindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIWindow.keyboardWillChangeFrameNotification, object: nil)
		searchBar.delegate = self
		view.bringSubviewToFront(searchBar)

		updateUI()
	}

	override func viewWillAppear(_ animated: Bool) {
		let hideToolbars = AppDefaults.shared.logicalArticleFullscreenEnabled
		if hideToolbars {
			currentWebViewController?.hideBars()
		} else {
			currentWebViewController?.showBars()
		}
		super.viewWillAppear(animated)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if #available(iOS 26, *) {
			navigationController?.navigationBar.topItem?.subtitle = nil
		}
		coordinator.isArticleViewControllerPending = false
		searchBar.shouldBeginEditing = true
		// Scoped to the article screen — restored in viewDidDisappear.
		if let parentNavController = navigationController?.parent as? UINavigationController,
			let gestureRecognizer = parentNavController.interactivePopGestureRecognizer {
			if gestureRecognizer.delegate !== poppableDelegate {
				originalPopGestureRecognizerDelegate = gestureRecognizer.delegate
			}
			poppableDelegate.navigationController = parentNavController
			gestureRecognizer.delegate = poppableDelegate
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if searchBar != nil && !searchBar.isHidden {
			endFind()
			searchBar.shouldBeginEditing = false
		}
		// Pass animated: false — animating the nav bar / toolbar visibility change during the
		// disappear transition triggers an Auto Layout assertion (NSISEngine) and crashes.
		currentWebViewController?.showBars(animated: false)
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		restoreOriginalPopGestureRecognizerDelegate()
	}

	override func viewSafeAreaInsetsDidChange() {
		// This will animate if the show/hide bars animation is happening.
		view.layoutIfNeeded()
	}

	func updateUI() {

		guard let article = article else {
			articleExtractorButton.isEnabled = false
			summarizeBarButtonItem.isEnabled = false
			nextUnreadBarButtonItem.isEnabled = false
			prevArticleBarButtonItem.isEnabled = false
			nextArticleBarButtonItem.isEnabled = false
			readBarButtonItem.isEnabled = false
			starBarButtonItem.isEnabled = false
			actionBarButtonItem.isEnabled = false
			return
		}

		nextUnreadBarButtonItem.isEnabled = coordinator.isNextUnreadAvailable
		prevArticleBarButtonItem.isEnabled = coordinator.isPrevArticleAvailable
		nextArticleBarButtonItem.isEnabled = coordinator.isNextArticleAvailable
		readBarButtonItem.isEnabled = true
		starBarButtonItem.isEnabled = true
		summarizeBarButtonItem.isEnabled = isSummarizeButtonAvailable()

		let permalinkPresent = article.preferredLink != nil
		articleExtractorButton.isEnabled = permalinkPresent && !AppDefaults.shared.isDeveloperBuild
		actionBarButtonItem.isEnabled = permalinkPresent

		if article.status.read {
			readBarButtonItem.image = Assets.Images.circleOpen
			readBarButtonItem.isEnabled = article.isAvailableToMarkUnread
			readBarButtonItem.accLabelText = NSLocalizedString("Mark Article Unread", comment: "Mark Article Unread")
		} else {
			readBarButtonItem.image = Assets.Images.circleClosed
			readBarButtonItem.isEnabled = true
			readBarButtonItem.accLabelText = NSLocalizedString("Selected - Mark Article Unread", comment: "Selected - Mark Article Unread")
		}

		if article.status.starred {
			starBarButtonItem.image = Assets.Images.starClosed
			starBarButtonItem.accLabelText = NSLocalizedString("Selected - Star Article", comment: "Selected - Star Article")
		} else {
			starBarButtonItem.image = Assets.Images.starOpen
			starBarButtonItem.accLabelText = NSLocalizedString("Star Article", comment: "Star Article")
		}
	}

	// MARK: Notifications

	@objc dynamic func unreadCountDidChange(_ notification: Notification) {
		updateUI()
	}

	@objc func statusesDidChange(_ note: Notification) {
		guard let articleIDs = note.userInfo?[Account.UserInfoKey.articleIDs] as? Set<String> else {
			return
		}
		guard let article = article else {
			return
		}
		if articleIDs.contains(article.articleID) {
			updateUI()
		}
	}

	@objc func contentSizeCategoryDidChange(_ note: Notification) {
		currentWebViewController?.fullReload()
	}

	@objc func willEnterForeground(_ note: Notification) {
		// The toolbar will come back on you if you don't hide it again
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			currentWebViewController?.hideBars()
		}
		updateUI()
	}

	// MARK: Actions

	@objc func didTapNavigationBar() {
		currentWebViewController?.hideBars()
	}

	@objc func showBars(_ sender: Any) {
		currentWebViewController?.showBars()
	}

	@IBAction func toggleArticleExtractor(_ sender: Any) {
		currentWebViewController?.toggleArticleExtractor()
	}

	@IBAction func summarizeArticle(_ sender: Any) {
		guard let article, let cacheKey = summaryCacheKey(for: article) else {
			return
		}

		if let cachedSummary = Self.summaryCache[cacheKey] {
			currentWebViewController?.showSummary(.summary(cachedSummary), animated: true)
			currentWebViewController?.scrollToTop(animated: true)
			return
		}

		let promptText = summaryPromptText(for: article)
		guard !promptText.isEmpty else {
			currentWebViewController?.showSummary(.error(NSLocalizedString("There is no article text to summarize.", comment: "Summary error")), animated: true)
			currentWebViewController?.scrollToTop(animated: true)
			return
		}

		summaryTask?.cancel()
		currentWebViewController?.showSummary(.loading, animated: true)
		currentWebViewController?.scrollToTop(animated: true)

		summaryTask = Task { [weak self] in
			guard let self else { return }
			let result = await summarize(promptText: promptText)
			guard !Task.isCancelled else { return }
			guard cacheKey == summaryCacheKey(for: self.article) else { return }

			switch result {
			case .success(let summary):
				Self.summaryCache[cacheKey] = summary
				currentWebViewController?.showSummary(.summary(summary), animated: true)
			case .failure(let error):
				currentWebViewController?.showSummary(.error(error.localizedDescription), animated: true)
			}
			currentWebViewController?.scrollToTop(animated: true)
		}
	}

	@IBAction func nextUnread(_ sender: Any) {
		coordinator.selectNextUnread()
	}

	@IBAction func prevArticle(_ sender: Any) {
		coordinator.selectPrevArticle()
	}

	@IBAction func nextArticle(_ sender: Any) {
		coordinator.selectNextArticle()
	}

	@IBAction func toggleRead(_ sender: Any) {
		coordinator.toggleReadForCurrentArticle()
	}

	@IBAction func toggleStar(_ sender: Any) {
		coordinator.toggleStarredForCurrentArticle()
	}

	@IBAction func showActivityDialog(_ sender: Any) {
		currentWebViewController?.showActivityDialog(popOverBarButtonItem: actionBarButtonItem)
	}

	@objc func toggleReaderView(_ sender: Any?) {
		currentWebViewController?.toggleArticleExtractor()
	}

	// MARK: Keyboard Shortcuts

	@objc func navigateToTimeline(_ sender: Any?) {
		coordinator.navigateToTimeline()
	}

	// MARK: API

	func focus() {
		currentWebViewController?.focus()
	}

	func canScrollDown() -> Bool {
		return currentWebViewController?.canScrollDown() ?? false
	}

	func canScrollUp() -> Bool {
		return currentWebViewController?.canScrollUp() ?? false
	}

	func scrollPageDown() {
		currentWebViewController?.scrollPageDown()
	}

	func scrollPageUp() {
		currentWebViewController?.scrollPageUp()
	}

	func stopArticleExtractorIfProcessing() {
		currentWebViewController?.stopArticleExtractorIfProcessing()
	}

	func openInAppBrowser() {
		currentWebViewController?.openInAppBrowser()
	}

	func setScrollPosition(isShowingExtractedArticle: Bool, articleWindowScrollY: Int) {
		currentWebViewController?.setScrollPosition(isShowingExtractedArticle: isShowingExtractedArticle, articleWindowScrollY: articleWindowScrollY)
	}
}

// MARK: Find in Article
public extension Notification.Name {
	static let FindInArticle = Notification.Name("FindInArticle")
	static let EndFindInArticle = Notification.Name("EndFindInArticle")
}

extension ArticleViewController: SearchBarDelegate {

	func searchBar(_ searchBar: ArticleSearchBar, textDidChange searchText: String) {
		currentWebViewController?.searchText(searchText) { found in
			searchBar.resultsCount = found.count

			if let index = found.index {
				searchBar.selectedResult = index + 1
			}
		}
	}

	func doneWasPressed(_ searchBar: ArticleSearchBar) {
		NotificationCenter.default.post(name: .EndFindInArticle, object: nil)
	}

	func nextWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult < searchBar.resultsCount {
			currentWebViewController?.selectNextSearchResult()
			searchBar.selectedResult += 1
		}
	}

	func previousWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult > 1 {
			currentWebViewController?.selectPreviousSearchResult()
			searchBar.selectedResult -= 1
		}
	}
}

extension ArticleViewController {

	@objc func beginFind(_ _: Any? = nil) {
		searchBar.isHidden = false
		navigationController?.setToolbarHidden(true, animated: true)
		currentWebViewController?.additionalSafeAreaInsets.bottom = searchBar.frame.height
		searchBar.becomeFirstResponder()
	}

	@objc func endFind(_ _: Any? = nil) {
		searchBar.resignFirstResponder()
		searchBar.isHidden = true
		navigationController?.setToolbarHidden(false, animated: true)
		currentWebViewController?.additionalSafeAreaInsets.bottom = 0
		currentWebViewController?.endSearch()
	}

	@objc func keyboardWillChangeFrame(_ notification: Notification) {
		if !searchBar.isHidden,
			let duration = notification.userInfo?[UIWindow.keyboardAnimationDurationUserInfoKey] as? Double,
			let curveRaw = notification.userInfo?[UIWindow.keyboardAnimationCurveUserInfoKey] as? UInt,
			let frame = notification.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect {

			let curve = UIView.AnimationOptions(rawValue: curveRaw)
			let newHeight = view.safeAreaLayoutGuide.layoutFrame.maxY - frame.minY
			currentWebViewController?.additionalSafeAreaInsets.bottom = newHeight + searchBar.frame.height + 10
			self.searchBarBottomConstraint.constant = newHeight
			UIView.animate(withDuration: duration, delay: 0, options: curve, animations: {
				self.view.layoutIfNeeded()
			})
		}
	}

}

// MARK: WebViewControllerDelegate

extension ArticleViewController: WebViewControllerDelegate {

	func webViewController(_ webViewController: WebViewController, articleExtractorButtonStateDidUpdate buttonState: ArticleExtractorButtonState) {
		guard webViewController === currentWebViewController else {
			return
		}
		syncArticleExtractorButtonState()
	}

}

// MARK: UIPageViewControllerDataSource

extension ArticleViewController: UIPageViewControllerDataSource {

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
		guard let webViewController = viewController as? WebViewController,
			let currentArticle = webViewController.article,
			let article = coordinator.findPrevArticle(currentArticle) else {
			return nil
		}
		return createWebViewController(article)
	}

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
		guard let webViewController = viewController as? WebViewController,
			let currentArticle = webViewController.article,
			let article = coordinator.findNextArticle(currentArticle) else {
			return nil
		}
		return createWebViewController(article)
	}

}

// MARK: UIPageViewControllerDelegate

extension ArticleViewController: UIPageViewControllerDelegate {

	func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
		isPageTransitionInProgress = true
	}

	func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
		isPageTransitionInProgress = false

		if let pending = pendingSetViewController {
			pendingSetViewController = nil
			// Async because UIKit is still finishing the swipe — a synchronous
			// setViewControllers here triggers an assertion in _UIQueuingScrollView.
			DispatchQueue.main.async {
				if self.isPageTransitionInProgress {
					self.pendingSetViewController = pending
				} else {
					self.pageViewController.setViewControllers([pending], direction: .forward, animated: false, completion: nil)
					self.syncArticleExtractorButtonState()
				}
			}
		}

		syncArticleExtractorButtonState()

		guard finished, completed else { return }
		guard let article = currentWebViewController?.article else { return }

		coordinator.selectArticle(article, animations: [.select, .scroll, .navigation])
		syncArticleExtractorButtonState()

		for viewController in previousViewControllers {
			if let webViewController = viewController as? WebViewController {
				webViewController.stopWebViewActivity()
			}
		}
	}
}

// MARK: UIGestureRecognizerDelegate

extension ArticleViewController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		let point = gestureRecognizer.location(in: nil)
		if point.x > 40 {
			return true
		}
		return false
    }

}

// MARK: Private

private extension ArticleViewController {

	func createWebViewController(_ article: Article?, updateView: Bool = true) -> WebViewController {
		let controller = WebViewController()
		controller.coordinator = coordinator
		controller.delegate = self
		controller.setArticle(article, updateView: updateView)
		return controller
	}

	func syncArticleExtractorButtonState() {
		articleExtractorButton.buttonState = currentWebViewController?.articleExtractorButtonState ?? .off
	}

	func isSummarizeButtonAvailable() -> Bool {
		guard #available(iOS 26, *) else {
			return false
		}

		switch SystemLanguageModel.default.availability {
		case .available, .unavailable(.modelNotReady):
			return true
		case .unavailable:
			return false
		@unknown default:
			return false
		}
	}

	func summaryCacheKey(for article: Article?) -> String? {
		guard let article else { return nil }
		return "\(article.accountID)-\(article.articleID)"
	}

	func summaryPromptText(for article: Article) -> String {
		let articleContent: String
		if currentState?.isShowingExtractedArticle == true, let extractedArticle = currentState?.extractedArticle {
			articleContent = extractedArticle.content ?? ""
		} else {
			articleContent = article.body ?? ""
		}

		let title = ArticleStringFormatter.sanitizedTitle(article.title, forHTML: false) ?? ""
		let text = articleContent.strippingHTML(maxCharacters: Self.maximumSummaryInputCharacters)
		guard !text.isEmpty else { return "" }
		return """
		Summarize this article in 3 concise bullet points. Keep the summary factual and avoid adding information that is not present in the article.

		Title:
		\(title)

		Article:
		\(text)
		"""
	}

	func summarize(promptText: String) async -> Result<String, Error> {
		guard #available(iOS 26, *) else {
			return .failure(SummaryError.unavailable(NSLocalizedString("Article summaries require iOS 26 or later.", comment: "Summary error")))
		}

		return await summarizeWithFoundationModels(promptText: promptText)
	}

	@available(iOS 26, *)
	func summarizeWithFoundationModels(promptText: String) async -> Result<String, Error> {
		let model = SystemLanguageModel.default
		guard model.isAvailable else {
			return .failure(SummaryError.unavailable(summaryUnavailableMessage(for: model.availability)))
		}

		do {
			let session = LanguageModelSession(instructions: "You summarize RSS articles for a reader app. Keep summaries short, accurate, and neutral.")
			let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: Self.maximumSummaryResponseTokens)
			let response = try await session.respond(to: promptText, options: options)
			let summary = response.content.trimmingWhitespace
			if summary.isEmpty {
				return .failure(SummaryError.emptyResponse)
			}
			return .success(summary)
		} catch {
			return .failure(error)
		}
	}

	@available(iOS 26, *)
	func summaryUnavailableMessage(for availability: SystemLanguageModel.Availability) -> String {
		switch availability {
		case .available:
			return NSLocalizedString("Article summaries are available.", comment: "Summary availability")
		case .unavailable(.appleIntelligenceNotEnabled):
			return NSLocalizedString("Apple Intelligence is not enabled.", comment: "Summary error")
		case .unavailable(.deviceNotEligible):
			return NSLocalizedString("This device does not support Apple Intelligence.", comment: "Summary error")
		case .unavailable(.modelNotReady):
			return NSLocalizedString("The language model is not ready yet. Try again later.", comment: "Summary error")
		case .unavailable:
			return NSLocalizedString("Article summaries are not available right now.", comment: "Summary error")
		@unknown default:
			return NSLocalizedString("Article summaries are not available right now.", comment: "Summary error")
		}
	}

	func restoreOriginalPopGestureRecognizerDelegate() {
		guard let gestureRecognizer = poppableDelegate.navigationController?.interactivePopGestureRecognizer,
			gestureRecognizer.delegate === poppableDelegate else {
			return
		}
		gestureRecognizer.delegate = originalPopGestureRecognizerDelegate
	}

}

private enum SummaryError: LocalizedError {
	case unavailable(String)
	case emptyResponse

	var errorDescription: String? {
		switch self {
		case .unavailable(let message):
			return message
		case .emptyResponse:
			return NSLocalizedString("The summary was empty.", comment: "Summary error")
		}
	}
}
