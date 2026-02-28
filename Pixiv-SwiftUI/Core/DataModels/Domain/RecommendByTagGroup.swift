import Foundation

struct RecommendByTagGroup: Codable, Identifiable, Hashable {
    var id: String { tag }
    let tag: String
    let translatedName: String?
    let illusts: [TrendTagIllust]

    static func == (lhs: RecommendByTagGroup, rhs: RecommendByTagGroup) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }
}
