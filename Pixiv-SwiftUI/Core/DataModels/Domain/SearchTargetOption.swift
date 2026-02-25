import Foundation

enum SearchTargetOption: String, CaseIterable, Identifiable, Hashable {
    case partialMatchForTags = "partial_match_for_tags"
    case exactMatchForTags = "exact_match_for_tags"
    case titleAndCaption = "title_and_caption"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .partialMatchForTags:
            return String(localized: "标签部分一致")
        case .exactMatchForTags:
            return String(localized: "标签完全一致")
        case .titleAndCaption:
            return String(localized: "标题和说明文字")
        }
    }
}
