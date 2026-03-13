import Foundation

enum SearchSortOption: String, CaseIterable {
    case dateDesc = "date_desc"
    case dateAsc = "date_asc"
    case popularDesc = "popular_desc"

    var displayName: String {
        displayName(isPremium: true)
    }

    func displayName(isPremium: Bool) -> String {
        switch self {
        case .dateDesc: return String(localized: "发布时间（从新到旧）")
        case .dateAsc: return String(localized: "发布时间（从旧到新）")
        case .popularDesc:
            return isPremium
                ? String(localized: "热门排序（收藏数）")
                : String(localized: "伪·热门排序（收藏数）")
        }
    }

    var requiresPremium: Bool {
        false
    }
}
