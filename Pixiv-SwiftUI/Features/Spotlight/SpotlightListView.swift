import SwiftUI

struct SpotlightListTarget: Hashable, Identifiable {
    let id = UUID()
}

struct SpotlightListView: View {
    @State private var store = SpotlightStore()
    @State private var navigateToDetail: SpotlightArticle?

    @State private var searchText: String = ""
    @State private var isSearchEditing: Bool = false

    #if os(macOS)
    @State private var columnCount: Int = 4
    #else
    @State private var columnCount: Int = 2
    #endif

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchSection

                if isSearchEditing && !store.searchHistory.isEmpty {
                    SpotlightSearchHistory(
                        history: store.searchHistory,
                        onSelect: { query in
                            searchText = query
                            isSearchEditing = false
                            Task {
                                await store.search(query)
                            }
                        },
                        onRemove: { query in
                            store.removeFromHistory(query)
                        },
                        onClear: {
                            store.clearHistory()
                        }
                    )
                } else {
                    articleGrid
                }
            }
        }
        .navigationTitle(store.source.isSearch ? "" : String(localized: "亮点"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(store.source.isSearch ? .inline : .automatic)
        #endif
        .task {
            if store.articles.isEmpty {
                await store.fetch()
            }
        }
        .refreshable {
            await store.fetch(forceRefresh: true)
        }
        .navigationDestination(item: $navigateToDetail) { article in
            SpotlightDetailView(article: article)
        }
    }

    private var searchSection: some View {
        VStack(spacing: 0) {
            SpotlightSearchBar(
                text: $searchText,
                isEditing: $isSearchEditing,
                onSubmit: { query in
                    Task {
                        await store.search(query)
                    }
                },
                onCancel: {
                    searchText = ""
                    Task {
                        await store.clearSearch()
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, isSearchEditing ? 0 : 12)

            if store.source.isSearch {
                HStack {
                    Text(store.source.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    if store.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    private var articleGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(store.articles) { article in
                Button {
                    navigateToDetail = article
                } label: {
                    SpotlightListCard(article: article)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if article.id == store.articles.last?.id {
                        Task {
                            await store.loadMore()
                        }
                    }
                }
            }

            if store.isLoadingMore {
                ForEach(0..<columnCount, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1.5, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .skeleton()

                        VStack(alignment: .leading, spacing: 2) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 14)
                                .skeleton()
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 60, height: 10)
                                .skeleton()
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

#Preview {
    NavigationStack {
        SpotlightListView()
    }
}
