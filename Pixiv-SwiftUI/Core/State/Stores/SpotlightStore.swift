import Foundation
import Observation

@MainActor
@Observable
final class SpotlightStore {
    static let shared = SpotlightStore()

    private let api = SpotlightAPI()
    private let cache = CacheManager.shared
    private let userDefaults = UserDefaults.standard
    private let expiration: CacheExpiration = .hours(23)

    var source: SpotlightListSource = .category(.illustration)
    var articles: [SpotlightArticle] = []
    var currentPage: Int = 1
    var hasNextPage: Bool = false
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var error: AppError?

    var searchHistory: [String] = []
    private let maxHistoryCount = 10
    private let historyKey = "spotlight_search_history"

    private var isLocked: Bool = false

    private var cacheKey: String {
        switch source {
        case .category(let category):
            return "spotlight_\(category.rawValue)"
        case .search(let query):
            return "spotlight_search_\(query)"
        }
    }

    init() {
        loadSearchHistory()
    }

    func switchSource(_ newSource: SpotlightListSource) async {
        guard source != newSource else { return }
        source = newSource
        articles = []
        currentPage = 1
        hasNextPage = false
        error = nil
        await fetch()
    }

    func fetch(forceRefresh: Bool = false) async {
        if isLocked { return }
        isLocked = true
        defer { isLocked = false }

        if !forceRefresh {
            if let cached: [SpotlightArticle] = cache.get(forKey: cacheKey) {
                articles = cached
                currentPage = 1
                hasNextPage = true
                return
            }
        }

        isLoading = true
        error = nil

        do {
            let result = try await fetchFromSource(page: 1)
            articles = result.articles
            currentPage = result.currentPage
            hasNextPage = result.hasNextPage
            cache.set(articles, forKey: cacheKey, expiration: expiration)
        } catch {
            self.error = AppError.networkError(error.localizedDescription)
        }

        isLoading = false
    }

    func loadMore() async {
        if isLocked { return }
        guard hasNextPage, !isLoadingMore else { return }

        isLocked = true
        defer { isLocked = false }

        isLoadingMore = true

        do {
            let result = try await fetchFromSource(page: currentPage + 1)
            let newArticles = result.articles.filter { new in
                !articles.contains(where: { $0.id == new.id })
            }
            articles.append(contentsOf: newArticles)
            currentPage = result.currentPage
            hasNextPage = result.hasNextPage
        } catch {
            self.error = AppError.networkError(error.localizedDescription)
        }

        isLoadingMore = false
    }

    private func fetchFromSource(page: Int) async throws -> SpotlightAPI.ArticleListResult {
        switch source {
        case .category(let category):
            return try await api.getCategoryArticles(category: category, page: page)
        case .search(let query):
            return try await api.searchArticles(query: query, page: page)
        }
    }

    func search(_ query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            await switchSource(.category(.illustration))
            return
        }

        addToHistory(trimmedQuery)
        await switchSource(.search(query: trimmedQuery))
    }

    func clearSearch() async {
        await switchSource(.category(.illustration))
    }

    func addToHistory(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        searchHistory.removeAll { $0 == trimmedQuery }
        searchHistory.insert(trimmedQuery, at: 0)

        if searchHistory.count > maxHistoryCount {
            searchHistory = Array(searchHistory.prefix(maxHistoryCount))
        }

        saveSearchHistory()
    }

    func removeFromHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        saveSearchHistory()
    }

    func clearHistory() {
        searchHistory = []
        saveSearchHistory()
    }

    private func loadSearchHistory() {
        if let saved = userDefaults.stringArray(forKey: historyKey) {
            searchHistory = saved
        }
    }

    private func saveSearchHistory() {
        userDefaults.set(searchHistory, forKey: historyKey)
    }

    func clear() {
        articles = []
        currentPage = 1
        hasNextPage = false
        error = nil
    }
}

@MainActor
@Observable
final class SpotlightDetailStore {
    private let api = SpotlightAPI()

    var detail: SpotlightArticleDetail?
    var isLoading: Bool = false
    var error: AppError?

    func fetch(url: String, languageCode: Int = 0) async {
        isLoading = true
        error = nil

        do {
            detail = try await api.fetchArticleDetail(url: url, languageCode: languageCode)
        } catch {
            self.error = AppError.networkError(error.localizedDescription)
        }

        isLoading = false
    }

    func clear() {
        detail = nil
        error = nil
    }
}
