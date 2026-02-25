import SwiftUI

struct SearchTargetFilterButton: View {
    @Binding var selectedTarget: SearchTargetOption

    var body: some View {
        Menu {
            ForEach(SearchTargetOption.allCases) { option in
                Button {
                    selectedTarget = option
                } label: {
                    HStack {
                        Text(option.displayName)
                        if selectedTarget == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "tag")
                .symbolVariant(selectedTarget == .partialMatchForTags ? .none : .fill)
        }
    }
}

#Preview {
    SearchTargetFilterButton(selectedTarget: .constant(.partialMatchForTags))
}

#Preview("已选择其他范围") {
    SearchTargetFilterButton(selectedTarget: .constant(.titleAndCaption))
}
