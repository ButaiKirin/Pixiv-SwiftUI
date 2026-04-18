import SwiftUI

struct IllustRankingPage: View {
    @Environment(IllustStore.self) var store
    @State private var selectedMode: IllustRankingMode = .day
    @State private var selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var usesLatestDate = true
    @State private var isLoading = false
    @State private var error: String?
    @State private var showProfilePanel = false
    @Environment(UserSettingStore.self) var settingStore
    @Environment(AccountStore.self) var accountStore

    private var rankingModes: [IllustRankingMode] {
        settingStore.enabledIllustRankingModes
    }

    private var illusts: [Illusts] {
        store.illusts(for: selectedMode)
    }

    private var nextUrl: String? {
        store.nextUrl(for: selectedMode)
    }

    private var hasMoreData: Bool {
        nextUrl != nil
    }

    private var filteredIllusts: [Illusts] {
        settingStore.filterIllusts(illusts)
    }

    private var latestDisplayDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    private var rankingRequestDate: Date? {
        usesLatestDate ? nil : selectedDate
    }

    private var dateSelection: Binding<Date> {
        Binding(
            get: { usesLatestDate ? latestDisplayDate : selectedDate },
            set: { newValue in
                selectedDate = newValue
                usesLatestDate = false
            }
        )
    }

    private var dateFilterRow: some View {
        HStack {
            Text(String(localized: "日期"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Button(String(localized: "重置")) {
                usesLatestDate = true
                Task {
                    await loadRankings(forceRefresh: true)
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundColor(usesLatestDate ? .secondary : .accentColor)
            .disabled(usesLatestDate)

            DatePicker("", selection: dateSelection, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                #if os(macOS)
                .controlSize(.small)
                #endif
        }
    }

    private var skeletonItemCount: Int {
        #if os(macOS)
        32
        #else
        12
        #endif
    }

    private func visibleItemCount(for width: CGFloat, spacing: CGFloat, containerPadding: CGFloat) -> Int {
        let targetButtonWidth: CGFloat = 104
        let availableWidth = max(0, width - containerPadding * 2)
        let count = Int((availableWidth + spacing) / (targetButtonWidth + spacing))
        return max(1, min(rankingModes.count, count))
    }

    private func syncSelectedModeIfNeeded() -> Bool {
        guard let firstMode = rankingModes.first else {
            return false
        }

        guard !rankingModes.contains(selectedMode) else {
            return false
        }

        selectedMode = firstMode
        return true
    }

    private func rankingModePicker(width: CGFloat) -> some View {
        let spacing: CGFloat = 6
        let containerPadding: CGFloat = 4
        let visibleItemCount = visibleItemCount(for: width, spacing: spacing, containerPadding: containerPadding)
        let buttonWidth = max(
            88,
            (width - containerPadding * 2 - spacing * CGFloat(visibleItemCount - 1)) / CGFloat(visibleItemCount)
        )

        return ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rankingModes) { mode in
                        let isSelected = selectedMode == mode

                        Button {
                            guard selectedMode != mode else { return }
                            selectedMode = mode
                        } label: {
                            Text(verbatim: mode.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: buttonWidth)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(mode.id)
                    }
                }
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .onAppear {
                reader.scrollTo(selectedMode.id, anchor: .center)
            }
            .onChange(of: selectedMode) { _, newValue in
                withAnimation(.snappy(duration: 0.2)) {
                    reader.scrollTo(newValue.id, anchor: .center)
                }
            }
            .onChange(of: rankingModes.map(\.rawValue)) { _, _ in
                withAnimation(.snappy(duration: 0.2)) {
                    reader.scrollTo(selectedMode.id, anchor: .center)
                }
            }
        }
    }

    private func loadRankings(forceRefresh: Bool = false) async {
        guard !rankingModes.isEmpty else {
            isLoading = false
            return
        }

        if syncSelectedModeIfNeeded() {
            return
        }

        isLoading = true
        await store.loadAllRankings(
            date: rankingRequestDate,
            forceRefresh: forceRefresh,
            modes: rankingModes
        )
        isLoading = false
    }

    var body: some View {
        GeometryReader { proxy in
            let dynamicColumnCount = ResponsiveGrid.columnCount(for: proxy.size.width, userSetting: settingStore.userSetting)
            let horizontalPadding: CGFloat = 24
            let availableWidth = proxy.size.width - horizontalPadding
            let waterfallWidth = availableWidth > 0 ? availableWidth : nil

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        rankingModePicker(width: max(proxy.size.width - 32, 0))
                        dateFilterRow
                    }
                    .padding()

                    if illusts.isEmpty && isLoading {
                        SkeletonIllustWaterfallGrid(
                            columnCount: dynamicColumnCount,
                            itemCount: skeletonItemCount,
                            width: waterfallWidth
                        )
                        .padding(.horizontal, 12)
                        .frame(minHeight: 400)
                    } else if illusts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text(String(localized: "没有排行数据"))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 200)
                    } else {
                        WaterfallGrid(data: filteredIllusts, columnCount: dynamicColumnCount, width: waterfallWidth, aspectRatio: { $0.safeAspectRatio }) { illust, columnWidth in
                            NavigationLink(value: illust) {
                                IllustCard(illust: illust, columnCount: dynamicColumnCount, columnWidth: columnWidth, expiration: DefaultCacheExpiration.recommend)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)

                        if hasMoreData {
                            LazyVStack {
                                ProgressView()
                                    #if os(macOS)
                                    .controlSize(.small)
                                    #endif
                                    .padding()
                                    .id(nextUrl)
                                    .onAppear {
                                        Task {
                                            await store.loadMoreRanking(mode: selectedMode)
                                        }
                                    }
                            }
                        } else if !filteredIllusts.isEmpty {
                            Text(String(localized: "已经到底了"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "插画排行"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .task {
                await loadRankings()
            }
            .refreshable {
                await loadRankings(forceRefresh: true)
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem {
                    Button {
                        Task {
                            await loadRankings(forceRefresh: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
                ToolbarItem {
                    ProfileButton(accountStore: accountStore, isPresented: $showProfilePanel)
                }
                #endif
                #if os(macOS)
                ToolbarItem {
                    RefreshButton(refreshAction: { await loadRankings(forceRefresh: true) })
                }
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $showProfilePanel) {
                ProfilePanelView(accountStore: accountStore, isPresented: $showProfilePanel)
            }
            #endif
            .onChange(of: selectedMode) { _, _ in
                Task {
                    await loadRankings()
                }
            }
            .onChange(of: selectedDate) { _, _ in
                Task {
                    await loadRankings(forceRefresh: true)
                }
            }
            .onChange(of: accountStore.currentUserId) { _, _ in
                Task {
                    await loadRankings(forceRefresh: true)
                }
            }
            .onChange(of: settingStore.userSetting.enabledIllustRankingModes) { _, _ in
                if syncSelectedModeIfNeeded() {
                    return
                }

                Task {
                    await loadRankings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshCurrentPage)) { _ in
                Task {
                    await loadRankings(forceRefresh: true)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        IllustRankingPage()
    }
}
