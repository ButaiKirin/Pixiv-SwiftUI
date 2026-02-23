import Foundation

/// 搜索导航目标
struct SearchResultTarget: Hashable, Sendable {
    let word: String
}

struct SauceNaoMatch: Hashable, Sendable {
    let illustId: Int
    let similarity: Double?
}

/// SauceNAO 以图搜图导航目标
struct SauceNaoResultTarget: Hashable, Sendable {
    let requestId: UUID
}
