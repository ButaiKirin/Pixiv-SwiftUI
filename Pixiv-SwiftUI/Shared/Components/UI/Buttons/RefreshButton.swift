import SwiftUI

struct RefreshButton: View {
    let refreshAction: () async -> Void
    @State private var isRefreshing = false

    var body: some View {
        Button {
            guard !isRefreshing else { return }
            isRefreshing = true
            Task {
                await refreshAction()
                await MainActor.run {
                    isRefreshing = false
                }
            }
        } label: {
            if #available(iOS 18.0, macOS 15.0, *) {
                Label("刷新", systemImage: isRefreshing ? "arrow.2.circlepath" : "arrow.clockwise")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isRefreshing)
            } else {
                Label("刷新", systemImage: isRefreshing ? "arrow.2.circlepath" : "arrow.clockwise")
                    .symbolEffect(.variableColor, isActive: isRefreshing)
            }
        }
        .disabled(isRefreshing)
        .help("刷新当前页面 (⌘R)")
    }
}

#Preview {
    RefreshButton(refreshAction: {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    })
}
