import SwiftUI

struct SpotlightSearchHistory: View {
    let history: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "搜索历史"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if !history.isEmpty {
                    Button {
                        onClear()
                    } label: {
                        Text(String(localized: "清除"))
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if history.isEmpty {
                Text(String(localized: "暂无搜索记录"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(history, id: \.self) { item in
                        HistoryChip(
                            text: item,
                            onTap: { onSelect(item) },
                            onRemove: { onRemove(item) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.05))
    }
}

private struct HistoryChip: View {
    let text: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onTap()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                    Text(text)
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    VStack {
        SpotlightSearchHistory(
            history: ["原神", "猫猫", "风景", "角色设计"],
            onSelect: { _ in },
            onRemove: { _ in },
            onClear: {}
        )

        SpotlightSearchHistory(
            history: [],
            onSelect: { _ in },
            onRemove: { _ in },
            onClear: {}
        )
    }
    .padding()
}
