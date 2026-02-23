import Foundation
import os.log

/// 标签翻译服务单例
final class TagTranslationService {
    static let shared = TagTranslationService()

    private let logger = Logger(subsystem: "com.pixiv.app", category: "TagTranslation")

    private var translations: [String: String] = [:]
    private(set) var timestamp: String = ""
    private(set) var isLoaded: Bool = false

    /// 元标签正则表达式，匹配 "前缀+数字+users入り" 格式
    private let metaTagRegex = try? NSRegularExpression(pattern: "^(.*?)(\\d+)users入り$", options: [])

    private init() {
        loadTranslations()
    }

    /// 从 Bundle 加载翻译数据
    private func loadTranslations() {
        guard let url = Bundle.main.url(forResource: "tags", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            logger.error("Failed to load tags.json from Bundle")
            return
        }

        do {
            let tagTranslations = try JSONDecoder().decode(TagTranslations.self, from: data)
            self.translations = tagTranslations.tags
            self.timestamp = tagTranslations.timestamp
            self.isLoaded = true
            logger.info("Successfully loaded \(self.translations.count) tag translations")
        } catch {
            logger.error("Failed to decode tags.json: \(error.localizedDescription)")
        }
    }

    /// 获取标签翻译
    /// - Parameter tagName: 标签名称
    /// - Returns: 中文翻译，如果不存在则返回 nil
    func getTranslation(for tagName: String) -> String? {
        return translations[tagName]
    }

    /// 处理元标签（如 xxx100users入り）
    /// - Parameter tagName: 标签名称
    /// - Returns: 优化后的翻译，如果不是元标签格式则返回 nil
    private func getMetaTagTranslation(for tagName: String) -> String? {
        guard let regex = metaTagRegex else { return nil }

        let range = NSRange(tagName.startIndex..., in: tagName)
        guard let match = regex.firstMatch(in: tagName, options: [], range: range) else {
            return nil
        }

        guard let prefixRange = Range(match.range(at: 1), in: tagName),
              let numberRange = Range(match.range(at: 2), in: tagName) else {
            return nil
        }

        let prefix = String(tagName[prefixRange])
        let number = String(tagName[numberRange])

        guard !prefix.isEmpty else { return nil }

        let prefixTranslation = getTranslation(for: prefix) ?? prefix

        return "\(prefixTranslation)\(number)用户收藏"
    }

    /// 获取显示的翻译（优先本地，其次官方）
    /// - Parameters:
    ///   - tagName: 标签名称
    ///   - officialTranslation: API 官方翻译
    /// - Returns: 优先返回本地翻译，如果不存在则返回官方翻译
    func getDisplayTranslation(for tagName: String, officialTranslation: String?) -> String? {
        let displayMode = UserSettingStore.shared.userSetting.tagTranslationDisplayMode
        switch displayMode {
        case 0:
            return nil
        case 1:
            return officialTranslation
        case 2:
            if let metaTranslation = getMetaTagTranslation(for: tagName) {
                return metaTranslation
            }
            if let localTranslation = getTranslation(for: tagName) {
                return localTranslation
            }
            return officialTranslation
        default:
            return officialTranslation
        }
    }

    /// 检查是否有本地翻译
    func hasTranslation(for tagName: String) -> Bool {
        return translations[tagName] != nil
    }

    /// 搜索标签（支持 tag 名和翻译双向搜索）
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - limit: 最大返回数量
    /// - Returns: 统一搜索建议数组
    func searchTags(query: String, limit: Int = 20) -> [UnifiedSearchSuggestion] {
        guard !query.isEmpty else { return [] }

        let lowercasedQuery = query.lowercased()
        var exactMatches: [UnifiedSearchSuggestion] = []
        var prefixMatches: [UnifiedSearchSuggestion] = []
        var containsMatches: [UnifiedSearchSuggestion] = []
        var seenTags = Set<String>()

        for (tagName, translation) in translations {
            let lowercasedTagName = tagName.lowercased()
            let lowercasedTranslation = translation.lowercased()

            var matchType: TagMatchType?

            if lowercasedTagName == lowercasedQuery {
                matchType = .exactName
            } else if lowercasedTranslation == lowercasedQuery {
                matchType = .exactTranslation
            } else if lowercasedTagName.hasPrefix(lowercasedQuery) {
                matchType = .prefixName
            } else if lowercasedTranslation.hasPrefix(lowercasedQuery) {
                matchType = .prefixTranslation
            } else if lowercasedTagName.contains(lowercasedQuery) {
                matchType = .containsName
            } else if lowercasedTranslation.contains(lowercasedQuery) {
                matchType = .containsTranslation
            }

            guard let type = matchType, !seenTags.contains(tagName) else { continue }
            seenTags.insert(tagName)

            let suggestion = UnifiedSearchSuggestion(
                tagName: tagName,
                displayTranslation: translation,
                source: .localTranslation(matchType: type)
            )

            switch type {
            case .exactName, .exactTranslation:
                exactMatches.append(suggestion)
            case .prefixName, .prefixTranslation:
                prefixMatches.append(suggestion)
            case .containsName, .containsTranslation:
                containsMatches.append(suggestion)
            }
        }

        exactMatches.sort { $0.tagName.count < $1.tagName.count }
        prefixMatches.sort { $0.tagName.count < $1.tagName.count }
        containsMatches.sort { $0.tagName.count < $1.tagName.count }

        let maxExact = 4
        let maxPrefix = 6
        let maxContains = 4

        var results: [UnifiedSearchSuggestion] = []
        results.append(contentsOf: Array(exactMatches.prefix(maxExact)))
        results.append(contentsOf: Array(prefixMatches.prefix(maxPrefix)))
        results.append(contentsOf: Array(containsMatches.prefix(maxContains)))

        return results
    }

    /// 获取所有翻译数据（用于外部搜索）
    func getAllTranslations() -> [String: String] {
        return translations
    }
}
