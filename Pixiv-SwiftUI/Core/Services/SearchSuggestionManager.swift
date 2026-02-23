import Foundation

@MainActor
final class SearchSuggestionManager {
    static let shared = SearchSuggestionManager()

    private let tagTranslationService = TagTranslationService.shared
    private let api = PixivAPI.shared

    private init() {}

    /// 获取搜索建议（合并本地翻译和官方 API）
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - limit: 最大返回数量
    /// - Returns: 合并后的搜索建议
    func fetchSuggestions(query: String, limit: Int = 30) async -> [UnifiedSearchSuggestion] {
        guard !query.isEmpty else { return [] }

        let localResults = tagTranslationService.searchTags(query: query)

        var officialResults: [UnifiedSearchSuggestion] = []
        do {
            let apiSuggestions = try await api.getSearchAutoCompleteKeywords(word: query)
            for tag in apiSuggestions {
                let displayTranslation = tagTranslationService.getDisplayTranslation(
                    for: tag.name,
                    officialTranslation: tag.translatedName
                )
                let suggestion = UnifiedSearchSuggestion(
                    tagName: tag.name,
                    displayTranslation: displayTranslation,
                    source: .officialAPI
                )
                officialResults.append(suggestion)
            }
        } catch {
            print("[SearchSuggestionManager] Failed to fetch API suggestions: \(error)")
        }

        let mergedResults = mergeResults(local: localResults, official: officialResults, limit: limit)

        return mergedResults
    }

    /// 合并本地和官方结果
    private func mergeResults(
        local: [UnifiedSearchSuggestion],
        official: [UnifiedSearchSuggestion],
        limit: Int
    ) -> [UnifiedSearchSuggestion] {
        var seen = Set<String>()
        var merged: [UnifiedSearchSuggestion] = []

        for suggestion in local where !seen.contains(suggestion.tagName) {
            seen.insert(suggestion.tagName)
            merged.append(suggestion)
        }

        for suggestion in official where !seen.contains(suggestion.tagName) {
            seen.insert(suggestion.tagName)
            merged.append(suggestion)
        }

        merged.sort { s1, s2 in
            let priority1 = sortPriority(for: s1)
            let priority2 = sortPriority(for: s2)

            if priority1 != priority2 {
                return priority1 < priority2
            }

            return s1.tagName.count < s2.tagName.count
        }

        if merged.count > limit {
            merged = Array(merged.prefix(limit))
        }

        return merged
    }

    /// 计算排序优先级（数值越小优先级越高）
    /// - 精确匹配 = 0, 1
    /// - 前缀匹配 = 2, 3
    /// - 官方 API = 4
    /// - 包含匹配 = 5, 6
    private func sortPriority(for suggestion: UnifiedSearchSuggestion) -> Int {
        switch suggestion.source {
        case .localTranslation(let matchType):
            switch matchType {
            case .exactName:
                return 0
            case .exactTranslation:
                return 1
            case .prefixName:
                return 2
            case .prefixTranslation:
                return 3
            case .containsName:
                return 5
            case .containsTranslation:
                return 6
            }
        case .officialAPI:
            return 4
        }
    }
}
