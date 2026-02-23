import Foundation

enum SpotlightListSource: Equatable {
    case category(SpotlightCategory)
    case search(query: String)

    var title: String {
        switch self {
        case .category(let category):
            return category.displayName
        case .search(let query):
            return String(localized: "搜索: \(query)")
        }
    }

    var isSearch: Bool {
        if case .search = self {
            return true
        }
        return false
    }

    var searchQuery: String? {
        if case .search(let query) = self {
            return query
        }
        return nil
    }
}
