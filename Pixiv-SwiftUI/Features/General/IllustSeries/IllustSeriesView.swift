import SwiftUI

struct IllustSeriesView: View {
    @Environment(ThemeManager.self) var themeManager
    let seriesId: Int
    @State private var store: IllustSeriesStore
    @State private var dynamicColumnCount: Int = ResponsiveGrid.initialColumnCount(userSetting: UserSettingStore.shared.userSetting)
    @Environment(UserSettingStore.self) var settingStore

    init(seriesId: Int) {
        self.seriesId = seriesId
        self._store = State(initialValue: IllustSeriesStore(seriesId: seriesId))
    }

    var body: some View {
        ScrollView {
            Group {
                if store.isLoading && store.seriesDetail == nil {
                    loadingView
                } else if let error = store.errorMessage {
                    errorView(error)
                } else if let detail = store.seriesDetail {
                    content(detail)
                }
            }
        }
        .navigationTitle(store.seriesDetail?.title ?? String(localized: "系列详情"))
        .onAppear {
            Task {
                await store.fetch()
            }
        }
        .refreshable {
            await store.fetch()
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack {
            SkeletonIllustWaterfallGrid(
                columnCount: dynamicColumnCount,
                itemCount: 12
            )
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "重试")) {
                Task {
                    await store.fetch()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    @ViewBuilder
    private func content(_ detail: IllustSeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                if let imageUrl = detail.coverImageUrls?.medium, !imageUrl.isEmpty {
                    CachedAsyncImage(
                        urlString: imageUrl,
                        contentMode: .fill
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(12)
                }

                Text(detail.title)
                    .font(.title2)
                    .fontWeight(.bold)

                if let caption = detail.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    let user = User(
                        profileImageUrls: detail.user.profileImageUrls,
                        id: detail.user.id,
                        name: detail.user.name,
                        account: detail.user.account
                    )
                    NavigationLink(value: user) {
                        HStack(spacing: 8) {
                            AnimatedAvatarImage(urlString: detail.user.profileImageUrls.medium, size: 24)
                            Text(detail.user.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(detail.seriesWorkCount) 部作品")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()
                .padding(.vertical, 8)

            // List
            LazyVStack(spacing: 12) {
                ForEach(Array(store.illusts.enumerated()), id: \.element.id) { index, illust in
                    NavigationLink(value: illust) {
                        IllustSeriesCard(illust: illust, index: index)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif

                    if index < store.illusts.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)

            // Load more
            if store.nextUrl != nil {
                HStack {
                    Spacer()
                    if store.isLoadingMore {
                        ProgressView()
                    } else {
                        Color.clear
                            .onAppear {
                                Task {
                                    await store.loadMore()
                                }
                            }
                    }
                    Spacer()
                }
                .padding(.vertical)
            }
        }
    }
}
