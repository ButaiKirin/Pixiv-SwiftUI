import SwiftUI

struct IllustSeriesCard: View {
    @Environment(UserSettingStore.self) var userSettingStore
    let illust: Illusts
    let index: Int

    @State private var isBookmarked: Bool = false

    init(illust: Illusts, index: Int) {
        self.illust = illust
        self.index = index
        _isBookmarked = State(initialValue: illust.isBookmarked)
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(
                urlString: ImageURLHelper.getImageURL(from: illust, quality: userSettingStore.userSetting.feedPreviewQuality),
                expiration: DefaultCacheExpiration.illustDetail
            )
            .frame(width: 80, height: 80)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text("#\(index + 1) \(illust.title)")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text(illust.user.name)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    if illust.pageCount > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "square.fill.on.square.fill")
                                .font(.caption2)
                            Text("\(illust.pageCount)P")
                                .font(.caption)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: isBookmarked ? "heart.fill" : "heart")
                            .font(.caption2)
                            .foregroundColor(isBookmarked ? .red : .secondary)
                        Text(NumberFormatter.formatCount(illust.totalBookmarks))
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
