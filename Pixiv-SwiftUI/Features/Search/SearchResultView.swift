import SwiftUI

struct SearchResultView: View {
    let word: String
    let preloadToken: UUID?
    @State var store = SearchResultStore()
    @State private var selectedTab = 0
    @State private var sortOption: SearchSortOption = SearchSortOption(rawValue: UserSettingStore.shared.userSetting.defaultSearchSort) ?? .dateDesc
    @State private var novelSortOption: SearchSortOption = SearchSortOption(rawValue: UserSettingStore.shared.userSetting.defaultSearchSort) ?? .dateDesc
    @State private var bookmarkFilter: BookmarkFilterOption = .none
    @State private var searchTarget: SearchTargetOption = .partialMatchForTags
    @State private var showsAIGeneratedWorks: Bool = true
    @State private var startDate: Date?
    @State private var endDate: Date?
    @Environment(UserSettingStore.self) var settingStore
    @Environment(AccountStore.self) var accountStore
    @Environment(ThemeManager.self) var themeManager
    @Environment(\.dismiss) private var dismiss
    let instanceId = UUID()

    @State private var dynamicColumnCount: Int = ResponsiveGrid.initialColumnCount(userSetting: UserSettingStore.shared.userSetting)
    @State private var userColumnCount: Int = 1

    private var viewId: String {
        "\(instanceId)"
    }

    private var filteredIllusts: [Illusts] {
        settingStore.filterIllusts(store.illustResults)
    }

    private var filteredUsers: [UserPreviews] {
        settingStore.filterUserPreviews(store.userResults)
    }

    private var filteredNovels: [Novel] {
        settingStore.filterNovels(store.novelResults)
    }

    private var skeletonItemCount: Int {
        #if os(macOS)
        32
        #else
        12
        #endif
    }

    private var shouldShowIllustBookmarkCount: Bool {
        sortOption == .popularDesc && settingStore.userSetting.showSearchPopularBookmarkCount
    }

    private var shouldShowNovelBookmarkCount: Bool {
        novelSortOption != .popularDesc || settingStore.userSetting.showSearchPopularBookmarkCount
    }

    private func performIllustSearch() async {
        await store.search(
            word: word,
            sort: sortOption.rawValue,
            preferLocalPopularSort: sortOption == .popularDesc && accountStore.currentAccount?.isPremium != 1,
            prefetchNovelSort: novelSortOption.rawValue,
            prefetchNovelPreferLocalPopularSort: novelSortOption == .popularDesc && accountStore.currentAccount?.isPremium != 1,
            allowsPseudoPopularPreload: accountStore.currentAccount?.isPremium != 1,
            preloadToken: preloadToken,
            showsAIGenerated: showsAIGeneratedWorks,
            bookmarkFilter: bookmarkFilter,
            searchTarget: searchTarget,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func performNovelSearch() async {
        await store.searchNovels(
            word: word,
            sort: novelSortOption.rawValue,
            preferLocalPopularSort: novelSortOption == .popularDesc && accountStore.currentAccount?.isPremium != 1,
            allowsPseudoPopularPreload: accountStore.currentAccount?.isPremium != 1,
            showsAIGenerated: showsAIGeneratedWorks,
            bookmarkFilter: bookmarkFilter,
            searchTarget: searchTarget,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func performCurrentTabSearch() async {
        if selectedTab == 0 {
            await performIllustSearch()
        } else if selectedTab == 1 {
            await performNovelSearch()
        }
    }

    private func loadMoreIllustResults() async {
        await store.loadMoreIllusts(
            word: word,
            sort: sortOption.rawValue,
            preferLocalPopularSort: sortOption == .popularDesc && accountStore.currentAccount?.isPremium != 1,
            showsAIGenerated: showsAIGeneratedWorks,
            bookmarkFilter: bookmarkFilter,
            searchTarget: searchTarget,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func loadMoreNovelResults() async {
        await store.loadMoreNovels(
            word: word,
            sort: novelSortOption.rawValue,
            preferLocalPopularSort: novelSortOption == .popularDesc && accountStore.currentAccount?.isPremium != 1,
            showsAIGenerated: showsAIGeneratedWorks,
            bookmarkFilter: bookmarkFilter,
            searchTarget: searchTarget,
            startDate: startDate,
            endDate: endDate
        )
    }

    @ViewBuilder
    private var resultContent: some View {
        if store.isLoading && store.illustResults.isEmpty && store.novelResults.isEmpty && store.userResults.isEmpty {
            SkeletonIllustWaterfallGrid(
                columnCount: dynamicColumnCount,
                itemCount: skeletonItemCount
            )
            .padding(.horizontal, 12)
        } else if let error = store.errorMessage, store.illustResults.isEmpty && store.novelResults.isEmpty && store.userResults.isEmpty {
            ContentUnavailableView("出错了", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if selectedTab == 0 {
            illustTabContent
        } else if selectedTab == 1 {
            novelTabContent
        } else {
            userTabContent
        }
    }

    @ViewBuilder
    private var illustTabContent: some View {
        if filteredIllusts.isEmpty && !store.illustResults.isEmpty && settingStore.blockedTags.contains(word) {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "eye.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("标签 \"\(word)\" 已被屏蔽")
                    .font(.title2)
                    .foregroundColor(.primary)

                Text("您已屏蔽此标签，因此没有显示相关插画")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: {
                    try? settingStore.removeBlockedTag(word)
                }) {
                    Text("取消屏蔽")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(GlassButtonStyle(color: themeManager.currentColor))

                Spacer()
            }
            .padding()
            .frame(minHeight: 300)
        } else if filteredIllusts.isEmpty && !store.isLoading {
            ContentUnavailableView("没有找到插画", systemImage: "magnifyingglass", description: Text("尝试搜索其他标签"))
                .frame(minHeight: 300)
        } else {
            LazyVStack(spacing: 12) {
                WaterfallGrid(data: filteredIllusts, columnCount: dynamicColumnCount, aspectRatio: { $0.safeAspectRatio }) { illust, columnWidth in
                    NavigationLink(value: illust) {
                        IllustCard(
                            illust: illust,
                            columnCount: dynamicColumnCount,
                            columnWidth: columnWidth,
                            showsBookmarkCount: shouldShowIllustBookmarkCount
                        )
                    }
                    .buttonStyle(.plain)
                }

                if store.illustHasMore {
                    ProgressView()
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                        .padding()
                        .onAppear {
                            Task {
                                await loadMoreIllustResults()
                            }
                        }
                } else if !filteredIllusts.isEmpty {
                    Text(String(localized: "已经到底了"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var novelTabContent: some View {
        if filteredNovels.isEmpty && !store.novelResults.isEmpty && !store.isLoading {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("没有找到小说")
                    .font(.title2)
                    .foregroundColor(.primary)

                Text("尝试搜索其他标签")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .frame(minHeight: 300)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredNovels) { novel in
                    NavigationLink(value: novel) {
                        NovelListCard(novel: novel, showsBookmarkCount: shouldShowNovelBookmarkCount)
                    }
                    .buttonStyle(.plain)
                }

                if store.novelHasMore {
                    ProgressView()
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                        .padding()
                        .onAppear {
                            Task {
                                await loadMoreNovelResults()
                            }
                        }
                } else if !filteredNovels.isEmpty {
                    Text(String(localized: "已经到底了"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var userTabContent: some View {
        if filteredUsers.isEmpty && !store.userResults.isEmpty && !store.isLoading {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "eye.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("没有找到画师")
                    .font(.title2)
                    .foregroundColor(.primary)

                Text("您已屏蔽所有搜索到的画师")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .frame(minHeight: 300)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: userColumnCount), spacing: 12) {
                ForEach(filteredUsers, id: \.id) { userPreview in
                    NavigationLink(value: userPreview.user) {
                        UserPreviewCard(userPreview: userPreview)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            if store.userHasMore {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
                    .padding()
                    .onAppear {
                        Task {
                            await store.loadMoreUsers(word: word)
                        }
                    }
            } else if !filteredUsers.isEmpty {
                Text(String(localized: "已经到底了"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    @ToolbarContentBuilder
    private var searchToolbar: some ToolbarContent {
        if selectedTab == 0 {
            ToolbarItem {
                HStack(spacing: 0) {
                    BookmarkFilterButton(selectedFilter: $bookmarkFilter)
                    SearchTargetFilterButton(selectedTarget: $searchTarget)
                    SearchAIFilterButton(showsAIGeneratedWorks: $showsAIGeneratedWorks)
                    SearchDateRangeFilterButton(startDate: $startDate, endDate: $endDate)
                    SearchSortButton(
                        sortOption: $sortOption,
                        isPremium: accountStore.currentAccount?.isPremium == 1,
                        contentType: .illust
                    )
                }
            }
        } else if selectedTab == 1 {
            ToolbarItem {
                HStack(spacing: 0) {
                    BookmarkFilterButton(selectedFilter: $bookmarkFilter)
                    SearchTargetFilterButton(selectedTarget: $searchTarget)
                    SearchAIFilterButton(showsAIGeneratedWorks: $showsAIGeneratedWorks)
                    SearchDateRangeFilterButton(startDate: $startDate, endDate: $endDate)
                    SearchSortButton(
                        sortOption: $novelSortOption,
                        isPremium: accountStore.currentAccount?.isPremium == 1,
                        contentType: .novel
                    )
                }
            }
        }
    }

    var body: some View {
        GeometryReader { _ in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Picker("类型", selection: $selectedTab) {
                        Text("插画").tag(0)
                        Text("小说").tag(1)
                        Text("画师").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .onChange(of: selectedTab) { _, newValue in
                        print("[SearchResultView] selectedTab changed to \(newValue)")
                    }

                    resultContent
                }
            }
            .navigationTitle(word)
            .toolbar { searchToolbar }
            .onChange(of: sortOption) { _, _ in
                guard selectedTab == 0 else { return }
                Task {
                    await performIllustSearch()
                }
            }
            .onChange(of: novelSortOption) { _, _ in
                guard selectedTab == 1 else { return }
                Task {
                    await performNovelSearch()
                }
            }
            .onChange(of: bookmarkFilter) { _, _ in
                Task {
                    await performCurrentTabSearch()
                }
            }
            .onChange(of: searchTarget) { _, _ in
                Task {
                    await performCurrentTabSearch()
                }
            }
            .onChange(of: showsAIGeneratedWorks) { _, _ in
                Task {
                    await performCurrentTabSearch()
                }
            }
            .onChange(of: startDate) { _, _ in
                Task {
                    await performCurrentTabSearch()
                }
            }
            .onChange(of: endDate) { _, _ in
                Task {
                    await performCurrentTabSearch()
                }
            }
            .onChange(of: selectedTab) { _, newValue in
                print("[SearchResultView] selectedTab changed to \(newValue)")
                if newValue == 1 {
                    Task {
                        await performNovelSearch()
                    }
                }
            }
            .onAppear {
                print("[SearchResultView] Appeared: word='\(word)', viewId=\(viewId)")
            }
            .task {
                print("[SearchResultView] task started: word='\(word)', viewId=\(viewId)")
                if store.illustResults.isEmpty && store.novelResults.isEmpty && store.userResults.isEmpty {
                    print("[SearchResultView] performing search")
                    await performIllustSearch()
                } else {
                    print("[SearchResultView] skipping search - results already exist")
                }
            }
            .onDisappear {
                store.cancelBackgroundTasks()
                print("[SearchResultView] disappeared: word='\(word)', viewId=\(viewId)")
            }
            .responsiveGridColumnCount(userSetting: settingStore.userSetting, columnCount: $dynamicColumnCount)
            .responsiveUserGridColumnCount(columnCount: $userColumnCount)
        }
    }
}

#Preview {
    NavigationStack {
        SearchResultView(word: "测试", preloadToken: nil)
    }
}

private struct SearchAIFilterButton: View {
    @Binding var showsAIGeneratedWorks: Bool

    var body: some View {
        Menu {
            Button {
                showsAIGeneratedWorks.toggle()
            } label: {
                HStack {
                    Text(String(localized: "显示 AI 生成作品"))
                    if showsAIGeneratedWorks {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "sparkles")
                .symbolVariant(showsAIGeneratedWorks ? .none : .fill)
        }
    }
}
