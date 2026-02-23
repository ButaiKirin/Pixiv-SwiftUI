import SwiftUI
import Combine

struct SauceNaoResultListView: View {
    let requestId: UUID
    @StateObject private var store: SauceNaoResultListStore
    @Environment(UserSettingStore.self) private var settingStore
    #if os(macOS)
    @State private var dynamicColumnCount: Int = 4
    #else
    @State private var dynamicColumnCount: Int = 2
    #endif

    init(requestId: UUID) {
        self.requestId = requestId
        self._store = StateObject(wrappedValue: SauceNaoResultListStore(requestId: requestId))
    }

    private var filteredItems: [SauceNaoResultItem] {
        let visibleIllustIds = Set(settingStore.filterIllusts(store.items.map { $0.illust }).map { $0.id })
        return store.items.filter { visibleIllustIds.contains($0.illust.id) }
    }

    private var allDetailLoadsFailed: Bool {
        store.hasSearched && !store.matches.isEmpty && filteredItems.isEmpty && store.failedDetailCount > 0
    }

    var body: some View {
        ZStack {
            if let errorMessage = store.errorMessage {
                ContentUnavailableView(
                    "出错了",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if store.isLoading && filteredItems.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在以图搜图...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if allDetailLoadsFailed {
                ContentUnavailableView(
                    "未能加载可显示的插画",
                    systemImage: "wifi.exclamationmark",
                    description: Text("共匹配 \(store.matches.count) 条，详情加载失败 \(store.failedDetailCount) 条")
                )
            } else if store.hasSearched && store.matches.isEmpty {
                ContentUnavailableView(
                    "没有找到结果",
                    systemImage: "photo.badge.questionmark"
                )
            } else if store.hasSearched && filteredItems.isEmpty {
                ContentUnavailableView(
                    "没有可显示的结果",
                    systemImage: "exclamationmark.triangle"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        WaterfallGrid(data: filteredItems, columnCount: dynamicColumnCount, aspectRatio: { $0.illust.safeAspectRatio }) { item, columnWidth in
                            NavigationLink(value: item.illust) {
                                SauceNaoResultWaterfallCard(
                                    item: item,
                                    columnCount: dynamicColumnCount,
                                    columnWidth: columnWidth
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if store.isLoading {
                            ProgressView()
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("以图搜图")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .responsiveGridColumnCount(userSetting: settingStore.userSetting, columnCount: $dynamicColumnCount)
        .task {
            await store.loadIfNeeded()
        }
    }
}

private struct SauceNaoResultWaterfallCard: View {
    let item: SauceNaoResultItem
    let columnCount: Int
    let columnWidth: CGFloat

    var body: some View {
        IllustCard(
            illust: item.illust,
            columnCount: columnCount,
            columnWidth: columnWidth
        )
        .overlay(alignment: .topTrailing) {
            Text(item.similarityTagText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(6)
                .padding(.top, item.illust.pageCount > 1 ? 24 : 0)
                .allowsHitTesting(false)
        }
    }
}

@MainActor
private final class SauceNaoResultListStore: ObservableObject {
    @Published var items: [SauceNaoResultItem] = []
    @Published var matches: [SauceNaoMatch] = []
    @Published var isLoading = false
    @Published var hasSearched = false
    @Published var errorMessage: String?
    @Published var failedDetailCount = 0

    private let requestId: UUID
    private var hasLoaded = false
    private let api = SauceNAOAPI()

    init(requestId: UUID) {
        self.requestId = requestId
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        errorMessage = nil
        failedDetailCount = 0
        defer { isLoading = false }

        guard let request = SauceNaoSearchRequestStore.shared.consume(requestId: requestId) else {
            hasSearched = true
            errorMessage = "请求已过期，请重新选择图片"
            return
        }

        do {
            let foundMatches = try await api.searchMatches(imageData: request.imageData, fileName: request.fileName)
            matches = foundMatches
            hasSearched = true
        } catch {
            hasSearched = true
            errorMessage = "搜图失败: \(error.localizedDescription)"
            return
        }

        guard !matches.isEmpty else {
            return
        }

        for (index, match) in matches.enumerated() {
            // 检查任务是否被取消（例如由于视图消失）
            if Task.isCancelled { return }
            
            do {
                let illust = try await PixivAPI.shared.getIllustDetail(illustId: match.illustId)
                let item = SauceNaoResultItem(index: index, illust: illust, similarity: match.similarity)
                
                // 确保 UI 更新在主线程
                items.append(item)
            } catch {
                failedDetailCount += 1
                print("[SauceNaoResultListView] load illust failed: \(match.illustId), error: \(error.localizedDescription)")
            }
        }
    }
}

private struct SauceNaoResultItem: Identifiable, Equatable {
    let index: Int
    let illust: Illusts
    let similarity: Double?

    var id: Int { illust.id }

    static func == (lhs: SauceNaoResultItem, rhs: SauceNaoResultItem) -> Bool {
        lhs.index == rhs.index && lhs.illust.id == rhs.illust.id && lhs.similarity == rhs.similarity
    }

    var similarityTagText: String {
        guard let similarity else {
            return "--"
        }
        return String(format: "%.1f%%", similarity)
    }
}

#Preview {
    NavigationStack {
        SauceNaoResultListView(requestId: UUID())
    }
}
