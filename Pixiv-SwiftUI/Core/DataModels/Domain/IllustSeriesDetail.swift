import Foundation

/// 插画系列详情
struct IllustSeriesDetail: Codable, Identifiable {
    var id: Int
    var title: String
    var caption: String?
    var coverImageUrls: ProfileImageUrls?
    var seriesWorkCount: Int
    var createDate: String?
    var width: Int?
    var height: Int?
    var user: IllustSeriesUser
    var watchlistAdded: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case caption
        case coverImageUrls = "cover_image_urls"
        case seriesWorkCount = "series_work_count"
        case createDate = "create_date"
        case width
        case height
        case user
        case watchlistAdded = "watchlist_added"
    }
}

/// 系列用户信息 (插画系列)
struct IllustSeriesUser: Codable {
    var id: StringIntValue
    var name: String
    var account: String
    var profileImageUrls: ProfileImageUrls

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case account
        case profileImageUrls = "profile_image_urls"
    }
}

/// 插画系列响应
struct IllustSeriesResponse: Codable {
    var illustSeriesDetail: IllustSeriesDetail
    var illusts: [Illusts]
    var nextUrl: String?

    enum CodingKeys: String, CodingKey {
        case illustSeriesDetail = "illust_series_detail"
        case illusts
        case nextUrl = "next_url"
    }
}
