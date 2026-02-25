import SwiftUI

struct SearchDateRangeFilterButton: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @State private var isPresentingDateSheet = false

    private var hasDateFilter: Bool {
        startDate != nil || endDate != nil
    }

    var body: some View {
        Button {
            isPresentingDateSheet = true
        } label: {
            Image(systemName: "calendar")
                .symbolVariant(hasDateFilter ? .fill : .none)
        }
        #if os(macOS)
        .popover(isPresented: $isPresentingDateSheet, arrowEdge: .bottom) {
            SearchDateRangeSheet(startDate: $startDate, endDate: $endDate)
                .frame(width: 380)
        }
        #else
        .sheet(isPresented: $isPresentingDateSheet) {
            SearchDateRangeSheet(startDate: $startDate, endDate: $endDate)
        }
        #endif
    }
}

private struct SearchDateRangeSheet: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    private let minDate: Date

    init(startDate: Binding<Date?>, endDate: Binding<Date?>) {
        _startDate = startDate
        _endDate = endDate

        let now = Date()
        _draftStartDate = State(initialValue: startDate.wrappedValue ?? now)
        _draftEndDate = State(initialValue: endDate.wrappedValue ?? now)

        minDate = Calendar.current.date(from: DateComponents(year: 2007, month: 8, day: 1)) ?? .distantPast
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "日期范围"))
                .font(.headline)

            DatePicker(
                String(localized: "开始日期"),
                selection: $draftStartDate,
                in: minDate...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)

            DatePicker(
                String(localized: "结束日期"),
                selection: $draftEndDate,
                in: minDate...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)

            HStack {
                Button(String(localized: "清除日期筛选")) {
                    startDate = nil
                    endDate = nil
                    dismiss()
                }

                Spacer()

                Button(String(localized: "取消")) {
                    dismiss()
                }

                Button(String(localized: "应用")) {
                    applyDateRange()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        #else
        NavigationStack {
            Form {
                Section(String(localized: "日期范围")) {
                    DatePicker(
                        String(localized: "开始日期"),
                        selection: $draftStartDate,
                        in: minDate...Date(),
                        displayedComponents: .date
                    )

                    DatePicker(
                        String(localized: "结束日期"),
                        selection: $draftEndDate,
                        in: minDate...Date(),
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle(String(localized: "日期筛选"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "应用")) {
                        applyDateRange()
                    }
                }

                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Button(String(localized: "清除日期筛选")) {
                        startDate = nil
                        endDate = nil
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button(String(localized: "清除日期筛选")) {
                        startDate = nil
                        endDate = nil
                        dismiss()
                    }
                }
                #endif
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
        #endif
    }

    private func applyDateRange() {
        var normalizedStartDate = Calendar.current.startOfDay(for: draftStartDate)
        var normalizedEndDate = Calendar.current.startOfDay(for: draftEndDate)

        if normalizedStartDate > normalizedEndDate {
            swap(&normalizedStartDate, &normalizedEndDate)
        }

        startDate = normalizedStartDate
        endDate = normalizedEndDate
        dismiss()
    }
}

#Preview {
    SearchDateRangeFilterButton(startDate: .constant(nil), endDate: .constant(nil))
}

#Preview("已选日期") {
    SearchDateRangeFilterButton(startDate: .constant(Date()), endDate: .constant(Date()))
}
