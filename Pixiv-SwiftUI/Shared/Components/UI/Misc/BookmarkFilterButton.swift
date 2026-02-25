import SwiftUI

struct BookmarkFilterButton: View {
    @Binding var selectedFilter: BookmarkFilterOption

    var body: some View {
        Menu {
            ForEach(BookmarkFilterOption.allCases) { option in
                Button {
                    selectedFilter = option
                } label: {
                    HStack {
                        Text(option.displayName)
                        if selectedFilter == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .symbolVariant(selectedFilter == .none ? .none : .fill)
        }
    }
}

#Preview {
    BookmarkFilterButton(selectedFilter: .constant(.none))
}

#Preview("已选") {
    BookmarkFilterButton(selectedFilter: .constant(.users1000))
}
