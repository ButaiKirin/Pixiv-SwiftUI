import SwiftUI

struct SpotlightSearchBar: View {
    @Binding var text: String
    @Binding var isEditing: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField(String(localized: "搜索特辑"), text: $text)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        onSubmit(text)
                        isFocused = false
                    }

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background {
                if #available(iOS 26.0, macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.1))
                }
            }

            if isEditing {
                Button {
                    text = ""
                    isFocused = false
                    isEditing = false
                    onCancel()
                } label: {
                    Text(String(localized: "取消"))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .onChange(of: isFocused) { _, newValue in
            isEditing = newValue
        }
    }
}

#Preview {
    VStack {
        SpotlightSearchBar(
            text: .constant(""),
            isEditing: .constant(false),
            onSubmit: { _ in },
            onCancel: {}
        )
        .padding()

        SpotlightSearchBar(
            text: .constant("原神"),
            isEditing: .constant(true),
            onSubmit: { _ in },
            onCancel: {}
        )
        .padding()
    }
}
