import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct SearchView: View {
    @StateObject private var store = SearchStore()
    @State private var selectedTag: String = ""
    @State private var showClearHistoryConfirmation = false
    @State private var showBlockToast = false
    @Environment(UserSettingStore.self) var userSettingStore
    @State private var path = NavigationPath()

    @State private var pendingIllustId: Int?
    @State private var pendingUserId: String?
    @State private var isLoadingDetail = false
    @State private var show404Error = false
    @State private var errorMessage = ""
    @State private var showProfilePanel = false
    @State private var showSauceToast = false
    @State private var sauceToastMessage = ""
    @State private var showImageFileImporter = false
    #if os(iOS)
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    var accountStore: AccountStore = AccountStore.shared

    private var columnCount: Int {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad ? userSettingStore.userSetting.hCrossCount : userSettingStore.userSetting.crossCount
        #else
        userSettingStore.userSetting.hCrossCount
        #endif
    }

    private var trendTagColumns: [[TrendTag]] {
        var result = Array(repeating: [TrendTag](), count: columnCount)
        for (index, item) in store.trendTags.enumerated() {
            result[index % columnCount].append(item)
        }
        return result
    }

    private var extractedNumber: Int? {
        let pattern = #"\b(\d+)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: store.searchText, range: NSRange(store.searchText.startIndex..., in: store.searchText)),
           let range = Range(match.range(at: 1), in: store.searchText) {
            return Int(store.searchText[range])
        }
        return nil
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.setString(text, forType: .string)
        #endif
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func startSauceNaoSearch() {
        guard accountStore.isLoggedIn else {
            showSauceToastMessage(String(localized: "请先登录"))
            return
        }
        #if os(iOS)
        showPhotosPicker = true
        #else
        showImageFileImporter = true
        #endif
    }

    private func showSauceToastMessage(_ message: String) {
        sauceToastMessage = message
        showSauceToast = true
    }

    private func handleImportedImage(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await searchWithImageURL(url)
            }
        case .failure(let error):
            showSauceToastMessage("读取图片失败: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func searchWithImageURL(_ url: URL) async {
        do {
            let data = try loadImageData(from: url)
            let fileName = url.lastPathComponent.isEmpty ? "image.jpg" : url.lastPathComponent
            await searchWithImageData(data, fileName: fileName)
        } catch {
            showSauceToastMessage("读取图片失败: \(error.localizedDescription)")
        }
    }

    private func loadImageData(from url: URL) throws -> Data {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    @MainActor
    private func searchWithImageData(_ data: Data, fileName: String) async {
        let requestId = SauceNaoSearchRequestStore.shared.enqueue(imageData: data, fileName: fileName)
        path.append(SauceNaoResultTarget(requestId: requestId))
    }

    #if os(iOS)
    private func handleSelectedPhotoItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let imageData = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        showSauceToastMessage(String(localized: "读取图片失败"))
                    }
                    return
                }
                await searchWithImageData(imageData, fileName: "photo.jpg")
                await MainActor.run {
                    selectedPhotoItem = nil
                }
            } catch {
                await MainActor.run {
                    showSauceToastMessage("读取图片失败: \(error.localizedDescription)")
                    selectedPhotoItem = nil
                }
            }
        }
    }
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                #if os(iOS)
                if store.searchText.isEmpty {
                    searchHistoryAndTrends
                } else {
                    suggestionList
                }
                #else
                searchHistoryAndTrends
                #endif
            }
            #if os(iOS)
            .searchable(
                text: $store.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: accountStore.isLoggedIn ? String(localized: "搜索插画、小说和画师") : String(localized: "请先登录以使用搜索")
            ) {
                SearchSuggestionView(
                    store: store,
                    accountStore: accountStore,
                    pendingIllustId: $pendingIllustId,
                    pendingUserId: $pendingUserId,
                    triggerHaptic: triggerHaptic,
                    copyToClipboard: copyToClipboard,
                    addBlockedTag: { name, translatedName in
                        try? userSettingStore.addBlockedTagWithInfo(name, translatedName: translatedName)
                        showBlockToast = true
                    },
                    onSearch: { word in
                        store.addHistory(word)
                        selectedTag = word
                        path = NavigationPath()
                        path.append(SearchResultTarget(word: word))
                    }
                )
            }
            #else
            .searchable(
                text: $store.searchText,
                prompt: accountStore.isLoggedIn ? String(localized: "搜索插画、小说和画师") : String(localized: "请先登录以使用搜索")
            ) {
                SearchSuggestionView(
                    store: store,
                    accountStore: accountStore,
                    pendingIllustId: $pendingIllustId,
                    pendingUserId: $pendingUserId,
                    triggerHaptic: triggerHaptic,
                    copyToClipboard: copyToClipboard,
                    addBlockedTag: { name, translatedName in
                        try? userSettingStore.addBlockedTagWithInfo(name, translatedName: translatedName)
                        showBlockToast = true
                    },
                    onSearch: { word in
                        store.addHistory(word)
                        selectedTag = word
                        path = NavigationPath()
                        path.append(SearchResultTarget(word: word))
                    }
                )
            }
            #endif
            .navigationTitle(String(localized: "搜索"))
            .toolbar {
                if accountStore.isLoggedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            startSauceNaoSearch()
                        }) {
                            Image(systemName: "photo.badge.magnifyingglass")
                        }
                    }
                }
                if !store.searchHistory.isEmpty && store.searchText.isEmpty && accountStore.isLoggedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            showClearHistoryConfirmation = true
                        }) {
                            Image(systemName: "trash")
                        }
                        .confirmationDialog(String(localized: "确定要清除所有搜索历史吗？"), isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
                            Button(String(localized: "清除所有"), role: .destructive) {
                                triggerHaptic()
                                store.clearHistory()
                            }
                            Button(String(localized: "取消"), role: .cancel) {}
                        }
                    }
                }
                #if os(iOS)
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
                ToolbarItem(placement: .primaryAction) {
                    ProfileButton(accountStore: accountStore, isPresented: $showProfilePanel)
                }
                #endif
            }
            .onAppear {
                store.loadSearchHistory()
            }
            .onSubmit(of: .search) {
                guard accountStore.isLoggedIn else { return }
                if !store.searchText.isEmpty {
                    // 将搜索关键词添加到历史记录
                    store.addHistory(store.searchText)
                    selectedTag = store.searchText
                    path = NavigationPath()
                    path.append(SearchResultTarget(word: store.searchText))
                }
            }
            .task {
                await store.fetchTrendTags()
            }
            .pixivNavigationDestinations()
            .navigationDestination(for: SauceNaoResultTarget.self) { target in
                SauceNaoResultListView(requestId: target.requestId)
            }
            .task(id: pendingIllustId) {
                if let illustId = pendingIllustId {
                    isLoadingDetail = true
                    defer { pendingIllustId = nil }
                    do {
                        let illust = try await PixivAPI.shared.getIllustDetail(illustId: illustId)
                        await MainActor.run {
                            path.append(illust)
                        }
                    } catch let error as NetworkError {
                        if case .httpError(404) = error {
                            errorMessage = String(localized: "没有找到插画") + " (ID: \(illustId))"
                            show404Error = true
                        }
                    } catch {
                        print("Failed to load illust: \(error)")
                    }
                    isLoadingDetail = false
                }
            }
            .task(id: pendingUserId) {
                if let userId = pendingUserId {
                    isLoadingDetail = true
                    defer { pendingUserId = nil }
                    do {
                        let userDetail = try await PixivAPI.shared.getUserDetail(userId: userId)
                        await MainActor.run {
                            path.append(userDetail.user)
                        }
                    } catch let error as NetworkError {
                        if case .httpError(404) = error {
                            errorMessage = String(localized: "没有找到画师") + " (ID: \(userId))"
                            show404Error = true
                        }
                    } catch {
                        print("Failed to load user: \(error)")
                    }
                    isLoadingDetail = false
                }
            }
            .overlay {
                if isLoadingDetail {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView()
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(12)
                    }
                    .ignoresSafeArea()
                }
            }
            .toast(isPresented: $showBlockToast, message: String(localized: "已屏蔽 Tag"))
            .toast(isPresented: $show404Error, message: errorMessage)
            .toast(isPresented: $showSauceToast, message: sauceToastMessage)
            .sheet(isPresented: $showProfilePanel) {
                #if os(iOS)
                ProfilePanelView(accountStore: accountStore, isPresented: $showProfilePanel)
                #endif
            }
            .fileImporter(
                isPresented: $showImageFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false,
                onCompletion: handleImportedImage
            )
            #if os(iOS)
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                handleSelectedPhotoItem(newItem)
            }
            #endif
            .onChange(of: accountStore.navigationRequest) { _, newValue in
                if let request = newValue {
                    switch request {
                    case .userDetail(let userId):
                        path.append(User(id: .string(userId), name: "", account: ""))
                    case .illustDetail(let illust):
                        path.append(illust)
                    }
                    accountStore.navigationRequest = nil
                }
            }
        }
    }

    private func trendTagContent(_ tag: TrendTag) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(
                urlString: tag.illust.imageUrls.medium,
                aspectRatio: tag.illust.aspectRatio
            )
            .clipped()

            LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading) {
                Text(tag.tag)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let translated = tag.translatedName {
                    Text(translated)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(8)
        }
        .cornerRadius(16)
    }

    private var searchHistoryAndTrends: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if !store.searchHistory.isEmpty {
                    Text("搜索历史")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    FlowLayout(spacing: 6) {
                        ForEach(store.searchHistory) { tag in
                            Group {
                                if accountStore.isLoggedIn {
                                    Button(action: {
                                        store.addHistory(tag)
                                        store.searchText = tag.name
                                        selectedTag = tag.name
                                        path = NavigationPath()
                                        path.append(SearchResultTarget(word: tag.name))
                                    }) {
                                        TagChip(searchTag: tag)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    TagChip(searchTag: tag)
                                }
                            }
                            .contextMenu {
                                Button(action: {
                                    copyToClipboard(tag.name)
                                }) {
                                    Label(String(localized: "复制 tag"), systemImage: "doc.on.doc")
                                }

                                if accountStore.isLoggedIn {
                                    Button(action: {
                                        triggerHaptic()
                                        try? userSettingStore.addBlockedTagWithInfo(tag.name, translatedName: tag.translatedName)
                                        showBlockToast = true
                                    }) {
                                        Label(String(localized: "屏蔽 tag"), systemImage: "eye.slash")
                                    }

                                    Button(role: .destructive, action: {
                                        store.removeHistory(tag.name)
                                    }) {
                                        Label(String(localized: "删除"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                SpotlightPreview()

                IllustRankingPreview()

                Text("热门标签")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)

                if store.isLoadingTrendTags && store.trendTags.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<columnCount, id: \.self) { _ in
                            LazyVStack(spacing: 10) {
                                ForEach(0..<3, id: \.self) { _ in
                                    SkeletonTrendTag()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                } else if !accountStore.isLoggedIn && store.trendTags.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("登录后查看热门标签")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .frame(height: 120)
                } else if !store.trendTags.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<columnCount, id: \.self) { columnIndex in
                            LazyVStack(spacing: 10) {
                                ForEach(trendTagColumns[columnIndex]) { tag in
                                    Group {
                                        if accountStore.isLoggedIn {
                                            Button(action: {
                                                let searchTag = SearchTag(name: tag.tag, translatedName: tag.translatedName)
                                                store.addHistory(searchTag)
                                                store.searchText = tag.tag
                                                selectedTag = tag.tag
                                                path = NavigationPath()
                                                path.append(SearchResultTarget(word: tag.tag))
                                            }) {
                                                trendTagContent(tag)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            trendTagContent(tag)
                                        }
                                    }
                                    .contextMenu {
                                        Button(action: {
                                            copyToClipboard(tag.tag)
                                        }) {
                                            Label(String(localized: "复制 tag"), systemImage: "doc.on.doc")
                                        }

                                        if accountStore.isLoggedIn {
                                            Button(action: {
                                                triggerHaptic()
                                                try? userSettingStore.addBlockedTagWithInfo(tag.tag, translatedName: tag.translatedName)
                                                showBlockToast = true
                                            }) {
                                                Label(String(localized: "屏蔽 tag"), systemImage: "eye.slash")
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func suggestionRow(_ tag: UnifiedSearchSuggestion) -> some View {
        HStack {
            Image(systemName: tag.isLocalMatch ? "checkmark.circle" : "magnifyingglass")
                .foregroundColor(tag.isLocalMatch ? .accentColor : .secondary)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(tag.tagName)
                    .foregroundColor(.primary)
                if let translated = tag.displayTranslation {
                    Text(translated)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var suggestionList: some View {
        List {
            if let number = extractedNumber, accountStore.isLoggedIn {
                Section(String(localized: "ID 快捷跳转")) {
                    Button(action: {
                        triggerHaptic()
                        pendingIllustId = number
                    }) {
                        HStack {
                            Text(String(localized: "查看插画"))
                            Spacer()
                            Text(String(number))
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: {
                        triggerHaptic()
                        pendingUserId = String(number)
                    }) {
                        HStack {
                            Text(String(localized: "查看作者"))
                            Spacer()
                            Text(String(number))
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(String(localized: "标签建议")) {
                ForEach(store.suggestions) { tag in
                    Group {
                        if accountStore.isLoggedIn {
                            Button(action: {
                                let words = store.searchText.split(separator: " ")
                                var newText = ""
                                if words.count > 1 {
                                    newText = String(words.dropLast().joined(separator: " ") + " ")
                                }
                                newText += tag.tagName + " "
                                let completedText = newText.trimmingCharacters(in: .whitespaces)
                                store.searchText = completedText

                                // 立即触发搜索并记录历史
                                store.addHistory(completedText)
                                selectedTag = completedText
                                path = NavigationPath()
                                path.append(SearchResultTarget(word: completedText))
                            }) {
                                suggestionRow(tag)
                            }
                        } else {
                            suggestionRow(tag)
                        }
                    }
                    .contextMenu {
                        Button(action: {
                            copyToClipboard(tag.tagName)
                        }) {
                            Label(String(localized: "复制 tag"), systemImage: "doc.on.doc")
                        }

                        if accountStore.isLoggedIn {
                            Button(action: {
                                triggerHaptic()
                                try? userSettingStore.addBlockedTagWithInfo(tag.tagName, translatedName: tag.displayTranslation)
                                showBlockToast = true
                            }) {
                                Label(String(localized: "屏蔽 tag"), systemImage: "eye.slash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    SearchView()
}
