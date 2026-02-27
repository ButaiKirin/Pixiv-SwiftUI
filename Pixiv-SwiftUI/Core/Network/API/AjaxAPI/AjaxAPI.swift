import Foundation

/// Pixiv Ajax API 实现
/// 
/// Pixiv Web 端接口，提供了一些 App API 不具备的功能。
/// 该 API 基于 Cookie 认证 (PHPSESSID) 和 CSRF Token (X-CSRF-Token)。
@MainActor
final class AjaxAPI {
    private let client = NetworkClient.shared
    private var csrfToken: String?
    
    // 使用统一的 PC/iOS 浏览器 User-Agent 以获取 Web 版内容
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private var ajaxHeaders: [String: String] {
        var headers = [
            "User-Agent": userAgent,
            "Referer": "https://www.pixiv.net/",
            "Accept": "application/json"
        ]
        if let token = csrfToken {
            headers["X-CSRF-Token"] = token
        }
        return headers
    }

    /// 执行登录流程以获取 PHPSESSID (通过 web_token)
    /// - Parameter webToken: 从 App API 获取的 web_token
    func loginWithWebToken(_ webToken: String) async throws {
        let loginURLString = "https://www.pixiv.net/login.php?token=\(webToken)&ref=www.pixiv.net"
        guard let url = URL(string: loginURLString) else { throw NetworkError.invalidURL }

        // 此请求会由于 Set-Cookie 自动将 PHPSESSID 存入 HTTPCookieStorage.shared
        _ = try await client.get(
            from: url, 
            headers: ["User-Agent": userAgent], 
            responseType: Data.self
        )
        
        // 登录成功后刷新 CSRF Token
        try await refreshCSRFToken()
    }

    /// 获取或刷新 CSRF Token
    /// 从 Pixiv 首页的 __NEXT_DATA__ 中提取
    func refreshCSRFToken() async throws {
        guard let url = URL(string: "https://www.pixiv.net/") else { throw NetworkError.invalidURL }
        
        let htmlData = try await client.get(
            from: url, 
            headers: ["User-Agent": userAgent, "Accept": "text/html"], 
            responseType: Data.self
        )
        guard let html = String(data: htmlData, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }

        // 定位 __NEXT_DATA__ 脚本标签
        let pattern = #"<script id="__NEXT_DATA__" type="application/json">(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            throw NetworkError.invalidResponse
        }

        let nextDataJson = String(html[range])
        
        // 解析嵌套的 JSON
        struct NextData: Decodable {
            let props: Props
            struct Props: Decodable {
                let pageProps: PageProps
            }
            struct PageProps: Decodable {
                let serverSerializedPreloadedState: String
            }
        }
        
        struct PreloadedState: Decodable {
            let api: APIState
            struct APIState: Decodable {
                let token: String
            }
        }

        let decoder = JSONDecoder()
        do {
            let nextData = try decoder.decode(NextData.self, from: nextDataJson.data(using: .utf8)!)
            if let stateData = try? decoder.decode(PreloadedState.self, from: nextData.props.pageProps.serverSerializedPreloadedState.data(using: .utf8)!) {
                self.csrfToken = stateData.api.token
            }
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    /// 获取搜索建议 (Ajax 版)
    /// 包含热门标签、推荐标签及其图标等
    func getSearchSuggestion(mode: String = "all", lang: String = "zh") async throws -> SearchSuggestionResponse {
        var components = URLComponents(string: APIEndpoint.ajaxBaseURL + "/search/suggestion")
        components?.queryItems = [
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "lang", value: lang)
        ]

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        return try await client.get(
            from: url,
            headers: ajaxHeaders,
            responseType: SearchSuggestionResponse.self
        )
    }
}

// MARK: - Models for Search Suggestion

struct SearchSuggestionResponse: Decodable {
    let error: Bool
    let body: SuggestionBody
}

struct SuggestionBody: Decodable {
    let popularTags: SuggestionTagGroup
    let recommendTags: SuggestionTagGroup?
    let recommendByTags: SuggestionTagGroup?
    let tagTranslation: [String: TagTranslation]?
    let thumbnails: [SuggestionThumbnail]?
}

struct SuggestionTagGroup: Decodable {
    let illust: [SuggestionTag]
    let novel: [SuggestionTag]?
}

struct SuggestionTag: Decodable {
    /// 这里的 IDs 可能是 Int(插画ID) 也可能是 String(插画ID)
    let ids: [SuggestionValue]
    let tag: String
}

struct TagTranslation: Decodable {
    let en: String?
    let ko: String?
    let zh: String?
    let zh_tw: String?
    let romaji: String?
}

struct SuggestionThumbnail: Decodable {
    let id: String
    let title: String
    let url: String
    let userId: String
    let userName: String
}

/// 兼容 Int 和 String 的 Codable 模型
enum SuggestionValue: Decodable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        throw DecodingError.typeMismatch(SuggestionValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SuggestionValue"))
    }
}
