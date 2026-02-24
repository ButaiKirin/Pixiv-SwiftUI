import SwiftUI

struct WaterfallGrid<Data, Content>: View where Data: RandomAccessCollection, Data.Element: Identifiable, Data: Equatable, Content: View {
    let data: Data
    let columnCount: Int
    let spacing: CGFloat
    let width: CGFloat?
    let aspectRatio: ((Data.Element) -> CGFloat)?
    let content: (Data.Element, CGFloat) -> Content

    @State private var containerWidth: CGFloat = 0
    @State private var columns: [[Data.Element]] = []

    init(data: Data, columnCount: Int, spacing: CGFloat = 12, width: CGFloat? = nil, aspectRatio: ((Data.Element) -> CGFloat)? = nil, @ViewBuilder content: @escaping (Data.Element, CGFloat) -> Content) {
        self.data = data
        self.columnCount = columnCount
        self.spacing = spacing
        self.width = width
        self.aspectRatio = aspectRatio
        self.content = content

        // 如果提供了宽度，则直接初始化状态
        if let width = width {
            _containerWidth = State(initialValue: width)
        }
        
        // 尝试初始化时同步计算一次，避免 onAppear 时的闪烁
        let initialColumns = Self.calculateColumnsSynchronously(
            data: data,
            columnCount: columnCount,
            aspectRatio: aspectRatio
        )
        _columns = State(initialValue: initialColumns)
    }

    private static func calculateColumnsSynchronously(
        data: Data,
        columnCount: Int,
        aspectRatio: ((Data.Element) -> CGFloat)?
    ) -> [[Data.Element]] {
        var result = Array(repeating: [Data.Element](), count: columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        guard columnCount > 0 else {
            return result
        }

        if aspectRatio == nil {
            for (index, item) in data.enumerated() {
                result[index % columnCount].append(item)
            }
            return result
        }

        for item in data {
            if let minIndex = columnHeights.indices.min(by: { columnHeights[$0] < columnHeights[$1] }) {
                result[minIndex].append(item)
                if let ratio = aspectRatio?(item) {
                    let itemHeight = (ratio > 0) ? (1.0 / ratio) : 1.0
                    columnHeights[minIndex] += itemHeight
                }
            }
        }
        return result
    }

    private func recalculateColumns() {
        columns = Self.calculateColumnsSynchronously(
            data: data,
            columnCount: columnCount,
            aspectRatio: aspectRatio
        )
    }

    private var safeColumnWidth: CGFloat {
        let currentWidth = width ?? containerWidth
        if currentWidth > 0 {
            return max((currentWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount), 50)
        } else {
            // 当宽度为0时，使用估计值，避免在 iOS 上初始宽度过大
            #if os(iOS)
            return 150
            #else
            return 170
            #endif
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if width == nil {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            containerWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size.width) { _, newValue in
                            if newValue > 0 && abs(newValue - containerWidth) > 1 {
                                containerWidth = newValue
                            }
                        }
                }
                .frame(height: 0)
            }

            if width != nil || containerWidth > 0 {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columnCount, id: \.self) { columnIndex in
                        if columnIndex < columns.count {
                            LazyVStack(spacing: spacing) {
                                ForEach(columns[columnIndex]) { item in
                                    content(item, safeColumnWidth)
                                }
                            }
                            .frame(width: safeColumnWidth)
                        }
                    }
                }
            }
        }
        .onAppear {
            recalculateColumns()
        }
        .onChange(of: data) {
            recalculateColumns()
        }
        .onChange(of: columnCount) {
            recalculateColumns()
        }
    }
}
