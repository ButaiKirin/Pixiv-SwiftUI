import SwiftUI
import Combine
import Observation

@MainActor
@Observable
class SearchStore {
    var searchText: String = "" {
        didSet {
            searchTextSubject.send(searchText)
        }
    }
    var searchHistory: [SearchTag] = []
    var suggestions: [UnifiedSearchSuggestion] = []
    var trendTags: [TrendTag] = []
    var isLoadingTrendTags: Bool = false
    var recommendedSearchTags: [TrendTag] = []
    var isLoadingRecommendedTags: Bool = false
    var illustResults: [Illusts] = []
    var userResults: [UserPreviews] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // 分页状态
    var illustOffset: Int = 0
    var illustLimit: Int = 30
    var illustHasMore: Bool = false
    var isLoadingMoreIllusts: Bool = false

    var userOffset: Int = 0
    var userHasMore: Bool = false
    var isLoadingMoreUsers: Bool = false

    var novelResults: [Novel] = []
    var novelOffset: Int = 0
    var novelLimit: Int = 30
    var novelHasMore: Bool = false
    var isLoadingMoreNovels: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let searchTextSubject = PassthroughSubject<String, Never>()
    private let api = PixivAPI.shared
    private let cache = CacheManager.shared
    private let suggestionManager = SearchSuggestionManager.shared

    private let trendTagsExpiration: CacheExpiration = .hours(1)

    init() {
        loadSearchHistory()

        searchTextSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                let trimmedText = text.trimmingCharacters(in: .whitespaces)
                if trimmedText.isEmpty {
                    self.suggestions = []
                    return
                }
                let searchWord = trimmedText.split(separator: " ").last.map(String.init) ?? trimmedText
                Task {
                    await self.fetchSuggestions(word: searchWord)
                }
            }
            .store(in: &cancellables)
    }

    func loadSearchHistory() {
        if let data = UserDefaults.standard.data(forKey: "SearchHistoryTags"),
           let history = try? JSONDecoder().decode([SearchTag].self, from: data) {
            self.searchHistory = history
        }
    }

    func saveSearchHistory() {
        if let data = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(data, forKey: "SearchHistoryTags")
        }
    }

    func addHistory(_ tag: SearchTag) {
        var tagToInsert = tag

        if let index = searchHistory.firstIndex(where: { $0.name == tag.name }) {
            let existingTag = searchHistory[index]
            // 如果新 tag 没有翻译名，但旧 tag 有，则使用旧 tag 的翻译名
            if tagToInsert.translatedName == nil && existingTag.translatedName != nil {
                tagToInsert = existingTag
            }
            searchHistory.remove(at: index)
        }

        searchHistory.insert(tagToInsert, at: 0)
        if searchHistory.count > 100 {
            searchHistory.removeLast()
        }
        saveSearchHistory()
    }

    func addHistory(_ text: String) {
        addHistory(SearchTag(name: text, translatedName: nil))
    }

    func clearHistory() {
        searchHistory = []
        saveSearchHistory()
    }

    func removeHistory(_ name: String) {
        searchHistory.removeAll { $0.name == name }
        saveSearchHistory()
    }

    func fetchTrendTags() async {
        let cacheKey = CacheManager.trendTagsKey()

        if let cached: [TrendTag] = cache.get(forKey: cacheKey) {
            self.trendTags = cached
            return
        }

        guard AccountStore.shared.isLoggedIn else {
            print("[SearchStore] Skip fetching trend tags in guest mode")
            return
        }

        isLoadingTrendTags = true
        defer { isLoadingTrendTags = false }

        do {
            let tags = try await api.getIllustTrendTags()
            self.trendTags = tags
            cache.set(tags, forKey: cacheKey, expiration: trendTagsExpiration)
        } catch {
            print("Failed to fetch trend tags: \(error)")
        }
    }

    func fetchRecommendedTags() async {
        guard AccountStore.shared.isLoggedIn else { return }

        isLoadingRecommendedTags = true
        defer { isLoadingRecommendedTags = false }

        do {
            let response = try await api.getSearchSuggestion(mode: "all")

            // 选取出推荐标签或热门标签
            var displayTags: [SuggestionTag] = []
            if let tags = response.body.recommendByTags?.illust, !tags.isEmpty {
                displayTags = tags
            } else if let tags = response.body.recommendTags?.illust, !tags.isEmpty {
                displayTags = tags
            } else {
                displayTags = response.body.popularTags.illust
            }

            if displayTags.isEmpty { return }

            // 构建索引用于快速寻找缩略图
            var thumbnailMap: [String: SuggestionThumbnail] = [:]
            if let thumbnails = response.body.thumbnails {
                for thumb in thumbnails {
                    thumbnailMap[thumb.id] = thumb
                }
            }

            // 翻译字典
            let translations = response.body.tagTranslation ?? [:]

            self.recommendedSearchTags = displayTags.compactMap { tag -> TrendTag? in
                // 找到第一个 ID 对应的插画
                guard let firstId = tag.ids.first else { return nil }
                let idString: String
                switch firstId {
                case .string(let str): idString = str
                case .int(let i): idString = String(i)
                }

                guard let thumb = thumbnailMap[idString] else { return nil }

                let translatedName = translations[tag.tag]?.zh ?? translations[tag.tag]?.en

                let trendIllust = TrendTagIllust(
                    id: Int(thumb.id) ?? 0,
                    title: thumb.title,
                    imageUrls: ImageUrls(
                        squareMedium: thumb.url,
                        medium: thumb.url,
                        large: thumb.url
                    ),
                    width: nil,
                    height: nil
                )

                return TrendTag(
                    tag: tag.tag,
                    translatedName: translatedName,
                    illust: trendIllust
                )
            }
        } catch {
            print("Failed to fetch recommended tags via Ajax, falling back to Trend Tags: \(error)")
            // 如果 Ajax 失败，Fallback 到普通趋势标签
            if let tags = try? await api.getIllustTrendTags() {
                self.recommendedSearchTags = tags
            }
        }
    }

    func fetchSuggestions(word: String) async {
        self.suggestions = await suggestionManager.fetchSuggestions(query: word)
    }

    func search(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        self.isLoading = true
        self.errorMessage = nil
        self.addHistory(word)

        self.illustOffset = 0
        self.userOffset = 0
        self.novelOffset = 0
        self.illustHasMore = false
        self.userHasMore = false
        self.novelHasMore = false

        let finalWord = word + bookmarkFilter.suffix

        do {
            let fetchedIllusts = try await api.searchIllusts(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: 0,
                limit: illustLimit
            )
            let fetchedUsers = try await api.getSearchUser(word: word, offset: 0)
            let fetchedNovels = try await api.searchNovels(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                startDate: startDate,
                endDate: endDate,
                offset: 0,
                limit: novelLimit
            )

            self.illustResults = fetchedIllusts
            self.userResults = fetchedUsers
            self.novelResults = fetchedNovels

            self.illustOffset = fetchedIllusts.count
            self.illustHasMore = fetchedIllusts.count == illustLimit
            self.userOffset = fetchedUsers.count
            self.userHasMore = !fetchedUsers.isEmpty
            self.novelOffset = fetchedNovels.count
            self.novelHasMore = fetchedNovels.count == novelLimit
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isLoading = false
    }

    /// 加载更多插画
    func loadMoreIllusts(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading, !isLoadingMoreIllusts, illustHasMore else { return }
        isLoadingMoreIllusts = true
        let finalWord = word + bookmarkFilter.suffix
        do {
            let more = try await api.searchIllusts(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: self.illustOffset,
                limit: self.illustLimit
            )
            self.illustResults += more
            self.illustOffset += more.count
            self.illustHasMore = more.count == illustLimit
        } catch {
            print("Failed to load more illusts: \(error)")
        }
        isLoadingMoreIllusts = false
    }

    /// 加载更多用户
    func loadMoreUsers(word: String) async {
        guard !isLoading, !isLoadingMoreUsers, userHasMore else { return }
        isLoadingMoreUsers = true
        do {
            let more = try await api.getSearchUser(word: word, offset: self.userOffset)
            self.userResults += more
            self.userOffset += more.count
            self.userHasMore = !more.isEmpty
        } catch {
            print("Failed to load more users: \(error)")
        }
        isLoadingMoreUsers = false
    }

    /// 搜索小说
    func searchNovels(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let finalWord = word + bookmarkFilter.suffix

        do {
            let fetchedNovels = try await api.searchNovels(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: 0,
                limit: novelLimit
            )
            self.novelResults = fetchedNovels
            self.novelOffset = fetchedNovels.count
            self.novelHasMore = fetchedNovels.count == novelLimit
        } catch {
            print("Failed to search novels: \(error)")
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 加载更多小说
    func loadMoreNovels(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading, !isLoadingMoreNovels, novelHasMore else { return }
        isLoadingMoreNovels = true
        let finalWord = word + bookmarkFilter.suffix
        do {
            let more = try await api.searchNovels(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: self.novelOffset,
                limit: self.novelLimit
            )
            self.novelResults += more
            self.novelOffset += more.count
            self.novelHasMore = more.count == novelLimit
        } catch {
            print("Failed to load more novels: \(error)")
        }
        isLoadingMoreNovels = false
    }
}
