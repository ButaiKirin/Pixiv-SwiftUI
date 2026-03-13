import SwiftUI
import Observation

@MainActor
@Observable
final class SearchResultStore {
    private struct SearchBatch<T> {
        let items: [T]
        let nextOffset: Int
        let hasMore: Bool
    }

    private struct PseudoPopularQuery: Hashable {
        let word: String
        let searchTarget: SearchTargetOption
    }

    var illustResults: [Illusts] = []
    var userResults: [UserPreviews] = []
    var novelResults: [Novel] = []

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

    var novelOffset: Int = 0
    var novelLimit: Int = 30
    var novelHasMore: Bool = false
    var isLoadingMoreNovels: Bool = false

    private let api = PixivAPI.shared
    private let pseudoPopularInitialSamplePageCount = 1
    private let pseudoPopularBackgroundSamplePageCount = 3
    private let pseudoPopularImplicitMinimumBookmarkCount = BookmarkFilterOption.users100.rawValue
    private var illustPseudoPopularTargetCount: Int = 0
    private var novelPseudoPopularTargetCount: Int = 0
    private var illustPseudoPopularSamplePageCount: Int = 0
    private var novelPseudoPopularSamplePageCount: Int = 0
    private var illustPseudoPopularSessionID = UUID()
    private var novelPseudoPopularSessionID = UUID()
    private var illustPseudoPopularEnrichmentTask: Task<Void, Never>?
    private var novelPseudoPopularEnrichmentTask: Task<Void, Never>?

    func search(
        word: String,
        sort: String = "date_desc",
        preferLocalPopularSort: Bool = false,
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        self.isLoading = true
        self.errorMessage = nil
        SearchStore.shared.addHistory(word)

        self.illustOffset = 0
        self.userOffset = 0
        self.novelOffset = 0
        self.illustHasMore = false
        self.userHasMore = false
        self.novelHasMore = false
        self.illustPseudoPopularTargetCount = 0
        self.novelPseudoPopularTargetCount = 0
        self.illustPseudoPopularSamplePageCount = 0
        self.novelPseudoPopularSamplePageCount = 0
        self.illustPseudoPopularSessionID = UUID()
        self.novelPseudoPopularSessionID = UUID()
        cancelIllustPseudoPopularEnrichment()
        cancelNovelPseudoPopularEnrichment()

        let baseWord = normalizeSearchWord(word)
        let usesPseudoPopularSort = preferLocalPopularSort && sort == SearchSortOption.popularDesc.rawValue
        let usesUsersTagPseudoPopularSort = usesPseudoPopularSort && searchTarget != .titleAndCaption
        let pseudoPopularMinimumBookmarkCount = effectivePseudoPopularMinimumBookmarkCount(for: bookmarkFilter)
        let finalWord = baseWord + bookmarkFilter.suffix
        let illustSessionID = illustPseudoPopularSessionID

        do {
            let fetchedIllusts: [Illusts]
            let fetchedNovels: [Novel]

            if usesUsersTagPseudoPopularSort {
                let illustBatch = try await searchIllustsByPseudoPopularTags(
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: illustLimit,
                    samplePageCount: pseudoPopularInitialSamplePageCount
                )
                fetchedIllusts = illustBatch.items
                self.illustPseudoPopularTargetCount = illustLimit
                self.illustPseudoPopularSamplePageCount = pseudoPopularInitialSamplePageCount
                self.illustOffset = fetchedIllusts.count
                self.illustHasMore = illustBatch.hasMore
                fetchedNovels = try await api.searchNovels(
                    word: finalWord,
                    searchTarget: searchTarget.rawValue,
                    sort: SearchSortOption.dateDesc.rawValue,
                    startDate: startDate,
                    endDate: endDate,
                    offset: 0,
                    limit: novelLimit
                )
            } else if usesPseudoPopularSort {
                let illustBatch = try await searchIllustsByBookmarkCount(
                    word: baseWord,
                    searchTarget: searchTarget,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: illustLimit,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    samplePageCount: pseudoPopularInitialSamplePageCount
                )
                fetchedIllusts = illustBatch.items
                self.illustPseudoPopularTargetCount = illustLimit
                self.illustPseudoPopularSamplePageCount = pseudoPopularInitialSamplePageCount
                self.illustOffset = fetchedIllusts.count
                self.illustHasMore = illustBatch.hasMore
                fetchedNovels = try await api.searchNovels(
                    word: finalWord,
                    searchTarget: searchTarget.rawValue,
                    sort: SearchSortOption.dateDesc.rawValue,
                    startDate: startDate,
                    endDate: endDate,
                    offset: 0,
                    limit: novelLimit
                )
            } else {
                fetchedIllusts = try await api.searchIllusts(
                    word: finalWord,
                    searchTarget: searchTarget.rawValue,
                    sort: sort,
                    startDate: startDate,
                    endDate: endDate,
                    offset: 0,
                    limit: illustLimit
                )
                fetchedNovels = try await api.searchNovels(
                    word: finalWord,
                    searchTarget: searchTarget.rawValue,
                    sort: sort,
                    startDate: startDate,
                    endDate: endDate,
                    offset: 0,
                    limit: novelLimit
                )
                self.illustOffset = fetchedIllusts.count
                self.illustHasMore = fetchedIllusts.count == illustLimit
            }

            let fetchedUsers = try await api.getSearchUser(word: word, offset: 0)

            self.illustResults = fetchedIllusts
            self.userResults = fetchedUsers
            self.novelResults = fetchedNovels

            self.userOffset = fetchedUsers.count
            self.userHasMore = !fetchedUsers.isEmpty
            self.novelOffset = fetchedNovels.count
            self.novelHasMore = fetchedNovels.count == novelLimit

            if usesPseudoPopularSort {
                scheduleIllustPseudoPopularEnrichment(
                    sessionID: illustSessionID,
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate
                )
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isLoading = false
    }

    /// 加载更多插画
    func loadMoreIllusts(
        word: String,
        sort: String = "date_desc",
        preferLocalPopularSort: Bool = false,
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading, !isLoadingMoreIllusts, illustHasMore else { return }
        isLoadingMoreIllusts = true
        let baseWord = normalizeSearchWord(word)
        let usesPseudoPopularSort = preferLocalPopularSort && sort == SearchSortOption.popularDesc.rawValue
        let usesUsersTagPseudoPopularSort = usesPseudoPopularSort && searchTarget != .titleAndCaption
        let pseudoPopularMinimumBookmarkCount = effectivePseudoPopularMinimumBookmarkCount(for: bookmarkFilter)
        let finalWord = baseWord + bookmarkFilter.suffix
        cancelIllustPseudoPopularEnrichment()
        do {
            if usesUsersTagPseudoPopularSort {
                let nextTargetCount = max(illustPseudoPopularTargetCount, illustResults.count) + illustLimit
                let nextSamplePageCount = max(
                    illustPseudoPopularSamplePageCount + 1,
                    pseudoPopularBackgroundSamplePageCount
                )
                let batch = try await searchIllustsByPseudoPopularTags(
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: nextTargetCount,
                    samplePageCount: nextSamplePageCount
                )
                self.illustResults = appendNewIllustsPreservingOrder(existing: self.illustResults, fetched: batch.items)
                self.illustPseudoPopularTargetCount = nextTargetCount
                self.illustPseudoPopularSamplePageCount = nextSamplePageCount
                self.illustOffset = batch.nextOffset
                self.illustHasMore = batch.hasMore
                scheduleIllustPseudoPopularEnrichment(
                    sessionID: illustPseudoPopularSessionID,
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate
                )
            } else if usesPseudoPopularSort {
                let nextTargetCount = max(illustPseudoPopularTargetCount, illustResults.count) + illustLimit
                let nextSamplePageCount = max(
                    illustPseudoPopularSamplePageCount + 1,
                    pseudoPopularBackgroundSamplePageCount
                )
                let batch = try await searchIllustsByBookmarkCount(
                    word: baseWord,
                    searchTarget: searchTarget,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: nextTargetCount,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    samplePageCount: nextSamplePageCount
                )
                self.illustResults = appendNewIllustsPreservingOrder(existing: self.illustResults, fetched: batch.items)
                self.illustPseudoPopularTargetCount = nextTargetCount
                self.illustPseudoPopularSamplePageCount = nextSamplePageCount
                self.illustOffset = batch.nextOffset
                self.illustHasMore = batch.hasMore
                scheduleIllustPseudoPopularEnrichment(
                    sessionID: illustPseudoPopularSessionID,
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate
                )
            } else {
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
            }
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

    /// 搜索小说 (带独立状态但目前都合并在一起)
    func searchNovels(
        word: String,
        sort: String = "date_desc",
        preferLocalPopularSort: Bool = false,
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        self.novelPseudoPopularTargetCount = 0
        self.novelPseudoPopularSamplePageCount = 0
        self.novelPseudoPopularSessionID = UUID()
        cancelNovelPseudoPopularEnrichment()

        let baseWord = normalizeSearchWord(word)
        let usesPseudoPopularSort = preferLocalPopularSort && sort == SearchSortOption.popularDesc.rawValue
        let usesUsersTagPseudoPopularSort = usesPseudoPopularSort && searchTarget != .titleAndCaption
        let pseudoPopularMinimumBookmarkCount = effectivePseudoPopularMinimumBookmarkCount(for: bookmarkFilter)
        let finalWord = baseWord + bookmarkFilter.suffix
        let novelSessionID = novelPseudoPopularSessionID

        do {
            let fetchedNovels: [Novel]

            if usesUsersTagPseudoPopularSort {
                let batch = try await searchNovelsByPseudoPopularTags(
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: novelLimit,
                    samplePageCount: pseudoPopularInitialSamplePageCount
                )
                fetchedNovels = batch.items
                self.novelPseudoPopularTargetCount = novelLimit
                self.novelPseudoPopularSamplePageCount = pseudoPopularInitialSamplePageCount
                self.novelOffset = batch.nextOffset
                self.novelHasMore = batch.hasMore
            } else if usesPseudoPopularSort {
                let batch = try await searchNovelsByBookmarkCount(
                    word: baseWord,
                    searchTarget: searchTarget,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: novelLimit,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    samplePageCount: pseudoPopularInitialSamplePageCount
                )
                fetchedNovels = batch.items
                self.novelPseudoPopularTargetCount = novelLimit
                self.novelPseudoPopularSamplePageCount = pseudoPopularInitialSamplePageCount
                self.novelOffset = batch.nextOffset
                self.novelHasMore = batch.hasMore
            } else {
                fetchedNovels = try await api.searchNovels(
                    word: finalWord,
                    searchTarget: searchTarget.rawValue,
                    sort: sort,
                    startDate: startDate,
                    endDate: endDate,
                    offset: 0,
                    limit: novelLimit
                )
                self.novelOffset = fetchedNovels.count
                self.novelHasMore = fetchedNovels.count == novelLimit
            }

            self.novelResults = fetchedNovels

            if usesPseudoPopularSort {
                scheduleNovelPseudoPopularEnrichment(
                    sessionID: novelSessionID,
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 加载更多小说
    func loadMoreNovels(
        word: String,
        sort: String = "date_desc",
        preferLocalPopularSort: Bool = false,
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading, !isLoadingMoreNovels, novelHasMore else { return }
        isLoadingMoreNovels = true
        let baseWord = normalizeSearchWord(word)
        let usesPseudoPopularSort = preferLocalPopularSort && sort == SearchSortOption.popularDesc.rawValue
        let usesUsersTagPseudoPopularSort = usesPseudoPopularSort && searchTarget != .titleAndCaption
        let pseudoPopularMinimumBookmarkCount = effectivePseudoPopularMinimumBookmarkCount(for: bookmarkFilter)
        let finalWord = baseWord + bookmarkFilter.suffix
        cancelNovelPseudoPopularEnrichment()

        do {
            if usesUsersTagPseudoPopularSort {
                let nextTargetCount = max(novelPseudoPopularTargetCount, novelResults.count) + novelLimit
                let nextSamplePageCount = max(
                    novelPseudoPopularSamplePageCount + 1,
                    pseudoPopularBackgroundSamplePageCount
                )
                let batch = try await searchNovelsByPseudoPopularTags(
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: nextTargetCount,
                    samplePageCount: nextSamplePageCount
                )
                self.novelResults = appendNewNovelsPreservingOrder(existing: self.novelResults, fetched: batch.items)
                self.novelPseudoPopularTargetCount = nextTargetCount
                self.novelPseudoPopularSamplePageCount = nextSamplePageCount
                self.novelOffset = batch.nextOffset
                self.novelHasMore = batch.hasMore
                scheduleNovelPseudoPopularEnrichment(
                    sessionID: novelPseudoPopularSessionID,
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate
                )
            } else if usesPseudoPopularSort {
                let nextTargetCount = max(novelPseudoPopularTargetCount, novelResults.count) + novelLimit
                let nextSamplePageCount = max(
                    novelPseudoPopularSamplePageCount + 1,
                    pseudoPopularBackgroundSamplePageCount
                )
                let batch = try await searchNovelsByBookmarkCount(
                    word: baseWord,
                    searchTarget: searchTarget,
                    startDate: startDate,
                    endDate: endDate,
                    targetCount: nextTargetCount,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    samplePageCount: nextSamplePageCount
                )
                self.novelResults = appendNewNovelsPreservingOrder(existing: self.novelResults, fetched: batch.items)
                self.novelPseudoPopularTargetCount = nextTargetCount
                self.novelPseudoPopularSamplePageCount = nextSamplePageCount
                self.novelOffset = batch.nextOffset
                self.novelHasMore = batch.hasMore
                scheduleNovelPseudoPopularEnrichment(
                    sessionID: novelPseudoPopularSessionID,
                    word: baseWord,
                    bookmarkFilter: bookmarkFilter,
                    searchTarget: searchTarget,
                    minimumBookmarkCount: pseudoPopularMinimumBookmarkCount,
                    startDate: startDate,
                    endDate: endDate
                )
            } else {
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
            }
        } catch {
            print("Failed to load more novels: \(error)")
        }
        isLoadingMoreNovels = false
    }

    func cancelBackgroundTasks() {
        illustPseudoPopularSessionID = UUID()
        novelPseudoPopularSessionID = UUID()
        cancelIllustPseudoPopularEnrichment()
        cancelNovelPseudoPopularEnrichment()
    }

    private func searchIllustsByBookmarkCount(
        word: String,
        searchTarget: SearchTargetOption,
        startDate: Date?,
        endDate: Date?,
        targetCount: Int,
        minimumBookmarkCount: Int = 0,
        samplePageCount: Int
    ) async throws -> SearchBatch<Illusts> {
        var merged: [Illusts] = []
        let pageBudget = max(1, samplePageCount)
        var offset = 0
        var lastPageWasFull = false

        for _ in 0..<pageBudget {
            let page = try await api.searchIllusts(
                word: word,
                searchTarget: searchTarget.rawValue,
                sort: SearchSortOption.dateDesc.rawValue,
                startDate: startDate,
                endDate: endDate,
                offset: offset,
                limit: illustLimit
            )

            merged = mergeIllusts(merged, with: page)
            offset += page.count
            lastPageWasFull = page.count == illustLimit

            if page.count < illustLimit {
                break
            }
        }

        let filtered = minimumBookmarkCount > 0
            ? merged.filter { $0.totalBookmarks >= minimumBookmarkCount }
            : merged
        let sorted = sortIllustsByBookmarkCount(filtered)
        let limited = Array(sorted.prefix(targetCount))

        return SearchBatch(
            items: limited,
            nextOffset: limited.count,
            hasMore: sorted.count > targetCount || lastPageWasFull
        )
    }

    private func searchNovelsByBookmarkCount(
        word: String,
        searchTarget: SearchTargetOption,
        startDate: Date?,
        endDate: Date?,
        targetCount: Int,
        minimumBookmarkCount: Int = 0,
        samplePageCount: Int
    ) async throws -> SearchBatch<Novel> {
        var merged: [Novel] = []
        let pageBudget = max(1, samplePageCount)
        var offset = 0
        var lastPageWasFull = false

        for _ in 0..<pageBudget {
            let page = try await api.searchNovels(
                word: word,
                searchTarget: searchTarget.rawValue,
                sort: SearchSortOption.dateDesc.rawValue,
                startDate: startDate,
                endDate: endDate,
                offset: offset,
                limit: novelLimit
            )

            merged = mergeNovels(merged, with: page)
            offset += page.count
            lastPageWasFull = page.count == novelLimit

            if page.count < novelLimit {
                break
            }
        }

        let filtered = minimumBookmarkCount > 0
            ? merged.filter { $0.totalBookmarks >= minimumBookmarkCount }
            : merged
        let sorted = sortNovelsByBookmarkCount(filtered)
        let limited = Array(sorted.prefix(targetCount))

        return SearchBatch(
            items: limited,
            nextOffset: limited.count,
            hasMore: sorted.count > targetCount || lastPageWasFull
        )
    }

    private func searchIllustsByPseudoPopularTags(
        word: String,
        bookmarkFilter: BookmarkFilterOption,
        searchTarget: SearchTargetOption,
        minimumBookmarkCount: Int,
        startDate: Date?,
        endDate: Date?,
        targetCount: Int,
        samplePageCount: Int
    ) async throws -> SearchBatch<Illusts> {
        let desiredCount = targetCount + 1
        var merged: [Illusts] = []
        var hasMore = false

        for threshold in pseudoPopularThresholds(minimumFilter: bookmarkFilter) {
            let bucket = try await fetchIllustBucket(
                word: word,
                threshold: threshold,
                searchTarget: searchTarget,
                startDate: startDate,
                endDate: endDate,
                desiredCount: desiredCount - merged.count,
                samplePageCount: samplePageCount
            )
            merged = mergeIllusts(merged, with: bucket.items)
            hasMore = hasMore || bucket.hasMore

            if merged.count >= desiredCount {
                break
            }
        }

        if merged.count < desiredCount {
            let fallback = try await searchIllustsByBookmarkCount(
                word: word,
                searchTarget: searchTarget,
                startDate: startDate,
                endDate: endDate,
                targetCount: desiredCount,
                minimumBookmarkCount: minimumBookmarkCount,
                samplePageCount: samplePageCount
            )
            merged = mergeIllusts(merged, with: fallback.items)
            hasMore = hasMore || fallback.hasMore
        }

        let sorted = sortIllustsByBookmarkCount(merged)
        let limited = Array(sorted.prefix(targetCount))

        return SearchBatch(
            items: limited,
            nextOffset: limited.count,
            hasMore: sorted.count > targetCount || hasMore
        )
    }

    private func searchNovelsByPseudoPopularTags(
        word: String,
        bookmarkFilter: BookmarkFilterOption,
        searchTarget: SearchTargetOption,
        minimumBookmarkCount: Int,
        startDate: Date?,
        endDate: Date?,
        targetCount: Int,
        samplePageCount: Int
    ) async throws -> SearchBatch<Novel> {
        let desiredCount = targetCount + 1
        var merged: [Novel] = []
        var hasMore = false

        for threshold in pseudoPopularThresholds(minimumFilter: bookmarkFilter) {
            let bucket = try await fetchNovelBucket(
                word: word,
                threshold: threshold,
                searchTarget: searchTarget,
                startDate: startDate,
                endDate: endDate,
                desiredCount: desiredCount - merged.count,
                samplePageCount: samplePageCount
            )
            merged = mergeNovels(merged, with: bucket.items)
            hasMore = hasMore || bucket.hasMore

            if merged.count >= desiredCount {
                break
            }
        }

        if merged.count < desiredCount {
            let fallback = try await searchNovelsByBookmarkCount(
                word: word,
                searchTarget: searchTarget,
                startDate: startDate,
                endDate: endDate,
                targetCount: desiredCount,
                minimumBookmarkCount: minimumBookmarkCount,
                samplePageCount: samplePageCount
            )
            merged = mergeNovels(merged, with: fallback.items)
            hasMore = hasMore || fallback.hasMore
        }

        let sorted = sortNovelsByBookmarkCount(merged)
        let limited = Array(sorted.prefix(targetCount))

        return SearchBatch(
            items: limited,
            nextOffset: limited.count,
            hasMore: sorted.count > targetCount || hasMore
        )
    }

    private func fetchIllustBucket(
        word: String,
        threshold: BookmarkFilterOption,
        searchTarget: SearchTargetOption,
        startDate: Date?,
        endDate: Date?,
        desiredCount: Int,
        samplePageCount: Int
    ) async throws -> SearchBatch<Illusts> {
        guard desiredCount > 0 else {
            return SearchBatch(items: [], nextOffset: 0, hasMore: false)
        }

        var merged: [Illusts] = []
        var hasMore = false

        for query in pseudoPopularQueries(for: word, threshold: threshold, searchTarget: searchTarget) {
            var offset = 0
            var sampledPageCount = 0

            while merged.count < desiredCount && sampledPageCount < max(1, samplePageCount) {
                let page = try await api.searchIllusts(
                    word: query.word,
                    searchTarget: query.searchTarget.rawValue,
                    sort: SearchSortOption.dateDesc.rawValue,
                    startDate: startDate,
                    endDate: endDate,
                    offset: offset,
                    limit: illustLimit
                )

                let filteredPage = page.filter { $0.totalBookmarks >= threshold.rawValue }
                merged = mergeIllusts(merged, with: filteredPage)
                hasMore = hasMore || page.count == illustLimit
                sampledPageCount += 1

                if page.count < illustLimit {
                    break
                }

                offset += page.count
            }

            if merged.count >= desiredCount {
                break
            }
        }

        let sorted = sortIllustsByBookmarkCount(merged)
        let limited = Array(sorted.prefix(desiredCount))

        return SearchBatch(
            items: limited,
            nextOffset: limited.count,
            hasMore: sorted.count > desiredCount || hasMore
        )
    }

    private func fetchNovelBucket(
        word: String,
        threshold: BookmarkFilterOption,
        searchTarget: SearchTargetOption,
        startDate: Date?,
        endDate: Date?,
        desiredCount: Int,
        samplePageCount: Int
    ) async throws -> SearchBatch<Novel> {
        guard desiredCount > 0 else {
            return SearchBatch(items: [], nextOffset: 0, hasMore: false)
        }

        var merged: [Novel] = []
        var hasMore = false

        for query in pseudoPopularQueries(for: word, threshold: threshold, searchTarget: searchTarget) {
            var offset = 0
            var sampledPageCount = 0

            while merged.count < desiredCount && sampledPageCount < max(1, samplePageCount) {
                let page = try await api.searchNovels(
                    word: query.word,
                    searchTarget: query.searchTarget.rawValue,
                    sort: SearchSortOption.dateDesc.rawValue,
                    startDate: startDate,
                    endDate: endDate,
                    offset: offset,
                    limit: novelLimit
                )

                let filteredPage = page.filter { $0.totalBookmarks >= threshold.rawValue }
                merged = mergeNovels(merged, with: filteredPage)
                hasMore = hasMore || page.count == novelLimit
                sampledPageCount += 1

                if page.count < novelLimit {
                    break
                }

                offset += page.count
            }

            if merged.count >= desiredCount {
                break
            }
        }

        let sorted = sortNovelsByBookmarkCount(merged)
        let limited = Array(sorted.prefix(desiredCount))

        return SearchBatch(
            items: limited,
            nextOffset: limited.count,
            hasMore: sorted.count > desiredCount || hasMore
        )
    }

    private func pseudoPopularThresholds(minimumFilter: BookmarkFilterOption) -> [BookmarkFilterOption] {
        BookmarkFilterOption.allCases
            .filter { $0 != .none && $0.rawValue >= minimumFilter.rawValue }
            .sorted { $0.rawValue > $1.rawValue }
    }

    private func pseudoPopularQueries(
        for word: String,
        threshold: BookmarkFilterOption,
        searchTarget: SearchTargetOption
    ) -> [PseudoPopularQuery] {
        let trimmedWord = normalizeSearchWord(word)
        guard !trimmedWord.isEmpty else { return [] }

        let spacedTarget: SearchTargetOption = searchTarget == .exactMatchForTags ? .exactMatchForTags : .partialMatchForTags
        var queries: [PseudoPopularQuery] = [
            PseudoPopularQuery(
                word: "\(trimmedWord) \(threshold.rawValue)users入り",
                searchTarget: spacedTarget
            )
        ]

        if !trimmedWord.contains(where: \.isWhitespace) {
            queries.insert(
                PseudoPopularQuery(
                    word: "\(trimmedWord)\(threshold.rawValue)users入り",
                    searchTarget: .exactMatchForTags
                ),
                at: 0
            )
        }

        var deduplicated: [PseudoPopularQuery] = []
        var seen = Set<PseudoPopularQuery>()
        for query in queries where seen.insert(query).inserted {
            deduplicated.append(query)
        }
        return deduplicated
    }

    private func normalizeSearchWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func effectivePseudoPopularMinimumBookmarkCount(for bookmarkFilter: BookmarkFilterOption) -> Int {
        max(bookmarkFilter.rawValue, pseudoPopularImplicitMinimumBookmarkCount)
    }

    private func cancelIllustPseudoPopularEnrichment() {
        illustPseudoPopularEnrichmentTask?.cancel()
        illustPseudoPopularEnrichmentTask = nil
    }

    private func cancelNovelPseudoPopularEnrichment() {
        novelPseudoPopularEnrichmentTask?.cancel()
        novelPseudoPopularEnrichmentTask = nil
    }

    private func scheduleIllustPseudoPopularEnrichment(
        sessionID: UUID,
        word: String,
        bookmarkFilter: BookmarkFilterOption,
        searchTarget: SearchTargetOption,
        minimumBookmarkCount: Int,
        startDate: Date?,
        endDate: Date?
    ) {
        guard illustHasMore else { return }

        let nextTargetCount = max(illustPseudoPopularTargetCount, illustResults.count) + illustLimit
        let nextSamplePageCount = max(
            illustPseudoPopularSamplePageCount + 1,
            pseudoPopularBackgroundSamplePageCount
        )
        let usesUsersTagPseudoPopularSort = searchTarget != .titleAndCaption

        cancelIllustPseudoPopularEnrichment()
        illustPseudoPopularEnrichmentTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            do {
                let batch: SearchBatch<Illusts>
                if usesUsersTagPseudoPopularSort {
                    batch = try await self.searchIllustsByPseudoPopularTags(
                        word: word,
                        bookmarkFilter: bookmarkFilter,
                        searchTarget: searchTarget,
                        minimumBookmarkCount: minimumBookmarkCount,
                        startDate: startDate,
                        endDate: endDate,
                        targetCount: nextTargetCount,
                        samplePageCount: nextSamplePageCount
                    )
                } else {
                    batch = try await self.searchIllustsByBookmarkCount(
                        word: word,
                        searchTarget: searchTarget,
                        startDate: startDate,
                        endDate: endDate,
                        targetCount: nextTargetCount,
                        minimumBookmarkCount: minimumBookmarkCount,
                        samplePageCount: nextSamplePageCount
                    )
                }

                guard !Task.isCancelled, sessionID == self.illustPseudoPopularSessionID else { return }

                self.illustResults = self.appendNewIllustsPreservingOrder(
                    existing: self.illustResults,
                    fetched: batch.items
                )
                self.illustPseudoPopularTargetCount = nextTargetCount
                self.illustPseudoPopularSamplePageCount = nextSamplePageCount
                self.illustOffset = batch.nextOffset
                self.illustHasMore = batch.hasMore
            } catch is CancellationError {
            } catch {
                print("Failed to enrich pseudo-popular illusts: \(error)")
            }
        }
    }

    private func scheduleNovelPseudoPopularEnrichment(
        sessionID: UUID,
        word: String,
        bookmarkFilter: BookmarkFilterOption,
        searchTarget: SearchTargetOption,
        minimumBookmarkCount: Int,
        startDate: Date?,
        endDate: Date?
    ) {
        guard novelHasMore else { return }

        let nextTargetCount = max(novelPseudoPopularTargetCount, novelResults.count) + novelLimit
        let nextSamplePageCount = max(
            novelPseudoPopularSamplePageCount + 1,
            pseudoPopularBackgroundSamplePageCount
        )
        let usesUsersTagPseudoPopularSort = searchTarget != .titleAndCaption

        cancelNovelPseudoPopularEnrichment()
        novelPseudoPopularEnrichmentTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            do {
                let batch: SearchBatch<Novel>
                if usesUsersTagPseudoPopularSort {
                    batch = try await self.searchNovelsByPseudoPopularTags(
                        word: word,
                        bookmarkFilter: bookmarkFilter,
                        searchTarget: searchTarget,
                        minimumBookmarkCount: minimumBookmarkCount,
                        startDate: startDate,
                        endDate: endDate,
                        targetCount: nextTargetCount,
                        samplePageCount: nextSamplePageCount
                    )
                } else {
                    batch = try await self.searchNovelsByBookmarkCount(
                        word: word,
                        searchTarget: searchTarget,
                        startDate: startDate,
                        endDate: endDate,
                        targetCount: nextTargetCount,
                        minimumBookmarkCount: minimumBookmarkCount,
                        samplePageCount: nextSamplePageCount
                    )
                }

                guard !Task.isCancelled, sessionID == self.novelPseudoPopularSessionID else { return }

                self.novelResults = self.appendNewNovelsPreservingOrder(
                    existing: self.novelResults,
                    fetched: batch.items
                )
                self.novelPseudoPopularTargetCount = nextTargetCount
                self.novelPseudoPopularSamplePageCount = nextSamplePageCount
                self.novelOffset = batch.nextOffset
                self.novelHasMore = batch.hasMore
            } catch is CancellationError {
            } catch {
                print("Failed to enrich pseudo-popular novels: \(error)")
            }
        }
    }

    private func appendNewIllustsPreservingOrder(existing: [Illusts], fetched: [Illusts]) -> [Illusts] {
        var combined = existing
        var existingIds = Set(existing.map(\.id))

        for illust in fetched where !existingIds.contains(illust.id) {
            combined.append(illust)
            existingIds.insert(illust.id)
        }

        return combined
    }

    private func appendNewNovelsPreservingOrder(existing: [Novel], fetched: [Novel]) -> [Novel] {
        var combined = existing
        var existingIds = Set(existing.map(\.id))

        for novel in fetched where !existingIds.contains(novel.id) {
            combined.append(novel)
            existingIds.insert(novel.id)
        }

        return combined
    }

    private func mergeIllusts(_ existing: [Illusts], with incoming: [Illusts]) -> [Illusts] {
        var merged = existing
        var existingIds = Set(existing.map(\.id))

        for illust in incoming where !existingIds.contains(illust.id) {
            merged.append(illust)
            existingIds.insert(illust.id)
        }

        return merged
    }

    private func mergeNovels(_ existing: [Novel], with incoming: [Novel]) -> [Novel] {
        var merged = existing
        var existingIds = Set(existing.map(\.id))

        for novel in incoming where !existingIds.contains(novel.id) {
            merged.append(novel)
            existingIds.insert(novel.id)
        }

        return merged
    }

    private func sortIllustsByBookmarkCount(_ illusts: [Illusts]) -> [Illusts] {
        illusts.sorted { lhs, rhs in
            if lhs.totalBookmarks == rhs.totalBookmarks {
                return lhs.createDate > rhs.createDate
            }
            return lhs.totalBookmarks > rhs.totalBookmarks
        }
    }

    private func sortNovelsByBookmarkCount(_ novels: [Novel]) -> [Novel] {
        novels.sorted { lhs, rhs in
            if lhs.totalBookmarks == rhs.totalBookmarks {
                return lhs.createDate > rhs.createDate
            }
            return lhs.totalBookmarks > rhs.totalBookmarks
        }
    }
}
