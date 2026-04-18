import SwiftUI
import Kingfisher

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private typealias KFImage = Kingfisher.KFImage
private typealias KFSource = Kingfisher.Source

/// 使用 Kingfisher 加载图片的异步图片组件（支持 Referer 请求头和缓存）
public struct CachedAsyncImage: View {
    public let urlString: String?
    public let placeholder: AnyView?
    public var aspectRatio: CGFloat?
    public var contentMode: SwiftUI.ContentMode
    public var idealWidth: CGFloat?
    public var expiration: CacheExpiration
    public var targetCache: ImageCache?

    public init(
        urlString: String?,
        placeholder: AnyView? = nil,
        aspectRatio: CGFloat? = nil,
        contentMode: SwiftUI.ContentMode = .fill,
        idealWidth: CGFloat? = nil,
        expiration: CacheExpiration? = nil,
        targetCache: ImageCache? = nil
    ) {
        self.urlString = urlString
        self.placeholder = placeholder
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.idealWidth = idealWidth
        self.expiration = expiration ?? .days(7)
        self.targetCache = targetCache
    }

    @State private var isLoaded = false

    public var body: some View {
        Group {
            if let urlString = urlString, let url = URL(string: urlString), !urlString.isEmpty {
                buildKFImage(url: url)
                    .placeholder {
                        placeholderView
                    }
                    .fade(duration: 0.5)
                    .cacheOriginalImage()
                    .requestModifier(PixivImageLoader.shared)
                    .diskCacheExpiration(expiration.kingfisherExpiration)
                    .memoryCacheExpiration(expiration.kingfisherExpiration)
                    .onSuccess { _ in
                        isLoaded = true
                    }
                    .resizable()
            } else {
                placeholderView
            }
        }
        .aspectRatio(aspectRatio, contentMode: contentMode)
        .clipped()
    }

    private func buildKFImage(url: URL) -> KFImage {
        var image: KFImage
        if shouldUseDirectConnection(url: url) {
            image = KFImage.source(.directNetwork(url))
        } else {
            image = KFImage.source(.network(url))
        }
        if let targetCache = targetCache {
            image = image.targetCache(targetCache)
        }
        return image
    }

    private func shouldUseDirectConnection(url: URL) -> Bool {
        guard let host = url.host else { return false }
        return NetworkModeStore.shared.useDirectConnection &&
               (host.contains("i.pximg.net") || host.contains("img-master.pixiv.net"))
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let placeholder = placeholder {
            placeholder
                .aspectRatio(aspectRatio, contentMode: contentMode)
        } else {
            let safeAspectRatio = (aspectRatio ?? 0) > 0 ? (aspectRatio ?? 1.0) : 1.0
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(safeAspectRatio, contentMode: .fill)
        }
    }
}

/// 使用 Kingfisher 的支持尺寸回调的异步图片组件
public struct DynamicSizeCachedAsyncImage: View {
    public let urlString: String?
    public let placeholder: AnyView?
    public var aspectRatio: CGFloat?
    public var contentMode: SwiftUI.ContentMode
    public var onSizeChange: ((CGSize) -> Void)?
    public var expiration: CacheExpiration

    public init(
        urlString: String?,
        placeholder: AnyView? = nil,
        aspectRatio: CGFloat? = nil,
        contentMode: SwiftUI.ContentMode = .fill,
        onSizeChange: ((CGSize) -> Void)? = nil,
        expiration: CacheExpiration? = nil
    ) {
        self.urlString = urlString
        self.placeholder = placeholder
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.onSizeChange = onSizeChange
        self.expiration = expiration ?? .days(7)
    }

    public var body: some View {
        Group {
            if let urlString = urlString, let url = URL(string: urlString), !urlString.isEmpty {
                buildKFImage(url: url)
                    .placeholder {
                        if let placeholder = placeholder {
                            placeholder
                                .aspectRatio(aspectRatio, contentMode: contentMode)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(aspectRatio, contentMode: .fill)
                        }
                    }
                    .fade(duration: 0.5)
                    .cacheOriginalImage()
                    .requestModifier(PixivImageLoader.shared)
                    .diskCacheExpiration(expiration.kingfisherExpiration)
                    .memoryCacheExpiration(expiration.kingfisherExpiration)
                    .onSuccess { result in
                        onSizeChange?(CGSize(width: result.image.size.width, height: result.image.size.height))
                    }
                    .resizable()
            } else {
                if let placeholder = placeholder {
                    placeholder
                        .aspectRatio(aspectRatio, contentMode: contentMode)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(aspectRatio, contentMode: .fill)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: contentMode)
        .clipped()
    }

    private func buildKFImage(url: URL) -> KFImage {
        if shouldUseDirectConnection(url: url) {
            return KFImage.source(.directNetwork(url))
        } else {
            return KFImage.source(.network(url))
        }
    }

    private func shouldUseDirectConnection(url: URL) -> Bool {
        guard let host = url.host else { return false }
        return NetworkModeStore.shared.useDirectConnection &&
               (host.contains("i.pximg.net") || host.contains("img-master.pixiv.net"))
    }
}

/// 图片 URL 工具函数
struct ImageURLHelper {
    /// 根据质量设置获取封面图片 URL（用于列表卡片和单页详情）
    static func getImageURL(
        from illusts: Illusts,
        quality: Int,
        isPicture: Bool = true
    ) -> String {
        switch quality {
        case 0:  // 中等
            return illusts.imageUrls.medium.isEmpty
                ? illusts.imageUrls.large
                : illusts.imageUrls.medium
        case 1:  // 大
            return illusts.imageUrls.large.isEmpty
                ? illusts.imageUrls.medium
                : illusts.imageUrls.large
        case 2:  // 原始
            if let url = illusts.metaSinglePage?.originalImageUrl, !url.isEmpty {
                return url
            }
            if let url = illusts.metaPages.first?.imageUrls?.original, !url.isEmpty {
                return url
            }
            return illusts.imageUrls.large.isEmpty
                ? illusts.imageUrls.medium
                : illusts.imageUrls.large
        default:
            return illusts.imageUrls.medium.isEmpty
                ? illusts.imageUrls.large
                : illusts.imageUrls.medium
        }
    }

    /// 获取特定页面的图片 URL（用于多页详情）
    static func getPageImageURL(
        from illusts: Illusts,
        page: Int,
        quality: Int
    ) -> String? {
        guard page >= 0 && page < illusts.metaPages.count else { return nil }
        guard let urls = illusts.metaPages[page].imageUrls else { return nil }

        switch quality {
        case 0:
            return urls.medium.isEmpty ? urls.large : urls.medium
        case 1:
            return urls.large.isEmpty ? urls.medium : urls.large
        case 2:
            if !urls.original.isEmpty { return urls.original }
            return urls.large.isEmpty ? urls.medium : urls.large
        default:
            return urls.medium.isEmpty ? urls.large : urls.medium
        }
    }
}

struct ImageQualityHelper {
    static let qualityLevels: [Int] = [0, 1, 2]

    static func getLowerQualityURLs(
        from illust: Illusts,
        targetQuality: Int,
        isManga: Bool = false
    ) -> [String] {
        var urls: [String] = []
        let lowerQualities = qualityLevels.filter { $0 < targetQuality }.sorted()

        for quality in lowerQualities {
            let url = ImageURLHelper.getImageURL(from: illust, quality: quality, isPicture: !isManga)
            if !url.isEmpty {
                urls.append(url)
            }
        }

        return urls
    }

    static func getLowerQualityPageURLs(
        from illust: Illusts,
        targetQuality: Int,
        page: Int
    ) -> [String] {
        var urls: [String] = []
        let lowerQualities = qualityLevels.filter { $0 < targetQuality }.sorted()

        for quality in lowerQualities {
            if let url = ImageURLHelper.getPageImageURL(from: illust, page: page, quality: quality) {
                urls.append(url)
            }
        }

        return urls
    }

    static func getAllQualityURLs(from illust: Illusts, isManga: Bool = false) -> [Int: String] {
        var urls: [Int: String] = [:]
        for quality in qualityLevels {
            let url = ImageURLHelper.getImageURL(from: illust, quality: quality, isPicture: !isManga)
            if !url.isEmpty {
                urls[quality] = url
            }
        }
        return urls
    }
}

/// 日期格式化工具
struct DateFormatterHelper {
    static func formatDate(_ date: String) -> String {
        let formatter = Foundation.DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

        if let parsedDate = formatter.date(from: date) {
            let displayFormatter = Foundation.DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            displayFormatter.locale = Locale.current
            return displayFormatter.string(from: parsedDate)
        }

        return date
    }

    static func formatRelativeTime(_ date: String) -> String {
        let formatter = Foundation.DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

        guard let parsedDate = formatter.date(from: date) else {
            return date
        }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day, .hour, .minute], from: parsedDate, to: now)

        if let day = components.day, day > 0 {
            return "\(day) 天前"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour) 小时前"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute) 分钟前"
        } else {
            return "刚刚"
        }
    }
}

/// 文本清理工具
struct TextCleaner {
    /// 清理 HTML 标签
    static func stripHTMLTags(_ text: String) -> String {
        let regex = try? NSRegularExpression(pattern: "<[^>]*>", options: [])
        let range = NSRange(text.startIndex..., in: text)
        let result = regex?.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: "")
        return result ?? text
    }

    /// 解码 HTML 实体（简化版本，不需要 AppKit）
    static func decodeHTMLEntities(_ text: String) -> String {
        // 简化实现：只处理常见的 HTML 实体
        var result = text
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        return result
    }

    /// 清理简介文本（处理换行和 HTML 实体）
    static func cleanDescription(_ text: String) -> String {
        // 1. 替换换行符
        var result = text.replacingOccurrences(of: "<br />", with: "\n")
        result = result.replacingOccurrences(of: "<br>", with: "\n")

        // 2. 移除其他 HTML 标签
        result = stripHTMLTags(result)

        // 3. 解码 HTML 实体
        result = decodeHTMLEntities(result)

        return result
    }
}

/// 数值格式化工具
struct NumberFormatter {
    static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return String(count)
        }
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// 验证工具
struct Validator {
    /// 验证邮箱格式
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }

    /// 验证用户名格式
    static func isValidUsername(_ username: String) -> Bool {
        return !username.trimmingCharacters(in: .whitespaces).isEmpty && username.count >= 3
    }
}
