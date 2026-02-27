import Foundation
import SwiftSoup

final class SpotlightAPI {
    private let client = NetworkClient.shared
    private let baseUrl = "https://www.pixivision.net"

    struct ArticleListResult {
        let articles: [SpotlightArticle]
        let currentPage: Int
        let hasNextPage: Bool
    }

    func getSpotlightArticles(category: String = "all") async throws -> (articles: [SpotlightArticle], nextUrl: String?) {
        var components = URLComponents(string: APIEndpoint.baseURL + "/v1/spotlight/articles")
        components?.queryItems = [
            URLQueryItem(name: "filter", value: "for_android"),
            URLQueryItem(name: "category", value: category)
        ]

        guard let url = components?.url else {
            throw NetworkError.invalidResponse
        }

        let response = try await client.get(
            from: url,
            headers: [:],
            responseType: SpotlightResponse.self
        )

        return (response.spotlightArticles, response.nextUrl)
    }

    func getSpotlightArticlesByURL(_ urlString: String) async throws -> (articles: [SpotlightArticle], nextUrl: String?) {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidResponse
        }

        let response = try await client.get(
            from: url,
            headers: [:],
            responseType: SpotlightResponse.self
        )

        return (response.spotlightArticles, response.nextUrl)
    }

    func getCategoryArticles(category: SpotlightCategory, page: Int = 1) async throws -> ArticleListResult {
        let urlString: String
        if page == 1 {
            urlString = "\(baseUrl)\(category.urlPath)"
        } else {
            urlString = "\(baseUrl)\(category.urlPath)/?p=\(page)"
        }
        let html = try await fetchHTML(url: urlString)
        return try parseArticleListHTML(html, page: page)
    }

    func searchArticles(query: String, page: Int = 1) async throws -> ArticleListResult {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NetworkError.invalidResponse
        }
        let urlString: String
        if page == 1 {
            urlString = "\(baseUrl)/zh/s/?q=\(encodedQuery)"
        } else {
            urlString = "\(baseUrl)/zh/s/?q=\(encodedQuery)&p=\(page)"
        }
        let html = try await fetchHTML(url: urlString)
        return try parseArticleListHTML(html, page: page)
    }

    private func parseArticleListHTML(_ html: String, page: Int) throws -> ArticleListResult {
        let doc = try SwiftSoup.parse(html)
        var articles: [SpotlightArticle] = []

        let articleCards = try doc.select("ul.main-column-container > li.article-card-container")

        for card in articleCards {
            do {
                guard let article = try parseArticleCard(card) else { continue }
                articles.append(article)
            } catch {
                continue
            }
        }

        let hasNextPage = try checkHasNextPage(doc: doc)

        return ArticleListResult(
            articles: articles,
            currentPage: page,
            hasNextPage: hasNextPage
        )
    }

    private func parseArticleCard(_ card: Element) throws -> SpotlightArticle? {
        guard let titleLink = try card.select(".arc__title a").first(),
              let href = try titleLink.attr("href").nilIfEmpty,
              let title = try titleLink.text().nilIfEmpty else {
            return nil
        }

        let articleId: Int
        if let lastComponent = href.split(separator: "/").last,
           let id = Int(lastComponent) {
            articleId = id
        } else {
            return nil
        }

        let thumbnail: String
        if let thumbDiv = try card.select("._thumbnail").first(),
           let style = try thumbDiv.attr("style").nilIfEmpty {
            thumbnail = extractBackgroundImageUrl(from: style) ?? ""
        } else {
            thumbnail = ""
        }

        if thumbnail.isEmpty {
            return nil
        }

        let articleUrl = href.hasPrefix("http") ? href : baseUrl + href

        let category: String
        if let categoryLabel = try card.select(".arc__thumbnail-label").first() {
            category = try categoryLabel.text()
        } else {
            category = ""
        }

        let tags = try card.select(".tls__list-item").compactMap { try $0.text().nilIfEmpty }

        let publishDate: Date
        if let timeElement = try card.select("time._date").first(),
           let datetime = try timeElement.attr("datetime").nilIfEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            publishDate = formatter.date(from: datetime) ?? Date()
        } else {
            publishDate = Date()
        }

        let pureTitle = title
            .replacingOccurrences(of: "^#\\S+\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return SpotlightArticle(
            id: articleId,
            title: title,
            pureTitle: pureTitle.isEmpty ? title : pureTitle,
            thumbnail: thumbnail,
            articleUrl: articleUrl,
            publishDate: publishDate,
            tags: tags,
            category: category
        )
    }

    private func extractBackgroundImageUrl(from style: String) -> String? {
        let pattern = #"background-image:\s*url\(['"]?([^'")\s]+)['"]?\)"#
        guard let range = style.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let urlMatch = style[range]
        guard let startIndex = urlMatch.firstIndex(of: "("),
              let endIndex = urlMatch.lastIndex(of: ")") else {
            return nil
        }
        let urlStart = urlMatch.index(after: startIndex)
        return String(urlMatch[urlStart..<endIndex])
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
    }

    private func checkHasNextPage(doc: Document) throws -> Bool {
        if let nextLink = try doc.select("._pager a.next").first() {
            let href = try nextLink.attr("href")
            return !href.isEmpty
        }
        return false
    }

    func fetchArticleDetail(url: String, languageCode: Int = 0) async throws -> SpotlightArticleDetail {
        let html = try await fetchHTML(url: url)
        return try parseArticleHTML(html, languageCode: languageCode)
    }

    private func fetchHTML(url: String) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw NetworkError.invalidResponse
        }

        let headers: [String: String] = [
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.26 Safari/537.36",
            "Referer": "https://www.pixivision.net/zh/"
        ]

        return try await client.getRaw(url: requestURL, headers: headers)
    }

    private func parseArticleHTML(_ html: String, languageCode: Int) throws -> SpotlightArticleDetail {
        let doc = try SwiftSoup.parse(html)

        guard let article = try doc.getElementsByTag("article").first(),
              let amBody = try article.getElementsByClass("am__body").first() else {
            return SpotlightArticleDetail(description: "", works: [], rankingArticles: [], recommendedArticles: [])
        }

        var nodes = amBody.children()
        var description = ""

        if let firstClass = try nodes.first()?.attr("class"), firstClass.contains("_feature") {
            if let featureContainer = nodes.first() {
                description = try extractFeatureDescription(from: featureContainer)
            }
            nodes = nodes.first()?.children() ?? nodes
        } else {
            if let header = try article.getElementsByClass("am__header").first() {
                description = try extractDescription(from: header)
            }
        }

        if description.isEmpty {
            description = try extractFallbackDescription(doc: doc, amBody: amBody)
        }

        var works: [SpotlightWork] = []

        for node in nodes {
            do {
                guard let nodeClass = try node.attr("class").nilIfEmpty,
                      nodeClass.contains("illust") else {
                    continue
                }

                var artworkLink: String?
                var showImage: String?
                var title: String?
                var userLink: String?
                var user: String?
                var userImage: String?

                let links = try node.getElementsByTag("a")
                for link in links {
                    guard let href = try link.attr("href").nilIfEmpty else { continue }

                    if href.contains("/artworks/") {
                        artworkLink = href
                        let imgs = try node.getElementsByTag("img")
                        if imgs.count > 1 {
                            showImage = try imgs[1].attr("src")
                        }
                        if let titleElement = try node.getElementsByTag("h3").first() {
                            title = try titleElement.text()
                        }
                    } else if href.contains("/users/") {
                        userLink = href
                        if let userElement = try node.getElementsByTag("p").first() {
                            user = try userElement.text()
                        }
                        let imgs = try node.getElementsByTag("img")
                        if !imgs.isEmpty {
                            userImage = try imgs[0].attr("src")
                        }
                    }
                }

                if let work = SpotlightWork(
                    title: title,
                    user: user,
                    userImage: userImage,
                    userLink: userLink,
                    showImage: showImage,
                    artworkLink: artworkLink
                ) {
                    works.append(work)
                }
            } catch {
                continue
            }
        }

        let rankingArticles = try extractRelatedArticles(doc: doc, category: "Ranking Area")
        let recommendedArticles = try extractRelatedArticles(doc: doc, category: "Osusume Area")

        return SpotlightArticleDetail(
            description: description,
            works: works,
            rankingArticles: rankingArticles,
            recommendedArticles: recommendedArticles
        )
    }

    private func extractRelatedArticles(doc: Document, category: String) throws -> [SpotlightRelatedArticle] {
        guard let sidebar = try doc.getElementsByClass("sidebar-container").first() else {
            return []
        }

        guard let section = try sidebar.getElementsByAttributeValue("data-gtm-category", category).first() else {
            return []
        }

        var articles: [SpotlightRelatedArticle] = []
        let listItems = try section.getElementsByClass("alc__articles-list-item")

        for item in listItems {
            guard let link = try item.getElementsByClass("asc__thumbnail-container").first()?.getElementsByTag("a").first(),
                  let href = try link.attr("href").nilIfEmpty else {
                continue
            }

            let thumbnail: String
            if let thumbDiv = try item.getElementsByClass("_thumbnail").first(),
               let style = try thumbDiv.attr("style").nilIfEmpty {
                let pattern = #"background-image:\s*url\(['"]?([^'")\s]+)['"]?\)"#
                if let range = style.range(of: pattern, options: .regularExpression) {
                    let urlMatch = style[range]
                    let start = urlMatch.firstIndex(of: "(") ?? urlMatch.startIndex
                    let end = urlMatch.lastIndex(of: ")") ?? urlMatch.endIndex
                    let urlString = String(urlMatch[urlMatch.index(after: start)..<end])
                        .replacingOccurrences(of: "'", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                    thumbnail = urlString
                } else {
                    continue
                }
            } else {
                continue
            }

            let title: String
            if let titleElement = try item.getElementsByClass("asc__title").first() {
                title = try titleElement.text()
            } else {
                continue
            }

            let categoryLabel: String
            if let categoryElement = try item.getElementsByClass("_category-label").first() {
                categoryLabel = try categoryElement.text()
            } else {
                categoryLabel = ""
            }

            let articleId: Int
            if let lastComponent = href.split(separator: "/").last,
               let id = Int(lastComponent) {
                articleId = id
            } else {
                articleId = 0
            }

            let baseUrl = "https://www.pixivision.net"
            let articleUrl = href.hasPrefix("http") ? href : baseUrl + href

            let relatedArticle = SpotlightRelatedArticle(
                id: articleId,
                title: title,
                thumbnail: thumbnail,
                articleUrl: articleUrl,
                category: categoryLabel
            )
            articles.append(relatedArticle)
        }

        return articles
    }

    private func extractFeatureDescription(from container: Element) throws -> String {
        let paragraphElements = try container.getElementsByClass("_feature-article-body__paragraph")
        for element in paragraphElements {
            let text = try extractStructuredText(from: element)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }

    private func extractDescription(from header: Element) throws -> String {
        return try extractStructuredText(from: header)
    }

    private func extractFallbackDescription(doc: Document, amBody: Element) throws -> String {
        if let featureContainer = try amBody.getElementsByClass("_feature-article-body").first() {
            let featureDescription = try extractFeatureDescription(from: featureContainer)
            if !featureDescription.isEmpty {
                return featureDescription
            }
        }

        if let firstParagraph = try amBody.getElementsByClass("_feature-article-body__paragraph").first() {
            let text = try extractStructuredText(from: firstParagraph)
            if !text.isEmpty {
                return text
            }
        }

        if let ogDescription = try doc.select("meta[property=og:description]").first(),
           let content = try ogDescription.attr("content").nilIfEmpty {
            return sanitizeDescriptionLine(content)
        }

        if let metaDescription = try doc.select("meta[name=description]").first(),
           let content = try metaDescription.attr("content").nilIfEmpty {
            return sanitizeDescriptionLine(content.replacingOccurrences(of: "[pixivision]", with: ""))
        }

        return ""
    }

    private func extractStructuredText(from element: Element) throws -> String {
        let blocks = try element.select("div.fab__paragraph._medium-editor-text > div, div.fab__paragraph._medium-editor-text > p, p")
        if !blocks.isEmpty {
            var lines: [String] = []
            for block in blocks {
                let line = sanitizeDescriptionLine(try extractTextPreservingInlineStyles(from: block))
                if !line.isEmpty {
                    lines.append(line)
                }
            }
            if !lines.isEmpty {
                return lines.joined(separator: "\n\n")
            }
        }

        return sanitizeDescriptionLine(try extractTextPreservingInlineStyles(from: element))
    }

    private func extractTextPreservingInlineStyles(from element: Element) throws -> String {
        var text = ""
        for child in element.getChildNodes() {
            text += try extractTextPreservingInlineStyles(from: child)
        }
        return text
    }

    private func extractTextPreservingInlineStyles(from node: Node) throws -> String {
        if let textNode = node as? TextNode {
            return textNode.text()
        }

        if let element = node as? Element {
            let tag = element.tagName().lowercased()
            if tag == "br" {
                return "\n"
            }

            var content = ""
            for child in element.getChildNodes() {
                content += try extractTextPreservingInlineStyles(from: child)
            }

            if tag == "b" || tag == "strong" {
                return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "[[B]]\(content)[[/B]]"
            }

            if tag == "i" || tag == "em" {
                return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "[[I]]\(content)[[/I]]"
            }

            return content
        }

        return ""
    }

    private func sanitizeDescriptionLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var nilIfEmpty: String? {
        return self.isEmpty ? nil : self
    }
}
