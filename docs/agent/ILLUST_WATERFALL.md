# 插画瀑布流组件 (Illust Waterfall)

本文档分析了项目中的插画瀑布流组件 `WaterfallGrid` 的结构、实现原理及在各页面中的使用注意事项。

## 组件概览

- **文件路径**: `Pixiv-SwiftUI/Shared/Components/Layout/WaterfallGrid.swift`
- **核心功能**: 提供多列瀑布流布局，支持基于如图片长宽比（Aspect Ratio）的智能排版（最短列优先）。
- **适用场景**: 插画推荐、搜索结果、收藏列表、用户作品集等。

## 架构设计

`WaterfallGrid` 本身不包含滚动容器，它设计为嵌入在外部的 `ScrollView` 中使用。

### 视图层级

```swift
ScrollView {         // 外部滚动容器
    VStack {         // 外部普通容器（必须是 VStack，不能是 LazyVStack）
        // 头部组件...
        
        WaterfallGrid(...) // 瀑布流组件本体
        
        // 底部加载更多...
    }
}
```

### 内部结构

组件内部使用了 **HStack of LazyVStacks** 的结构来模拟瀑布流：

```swift
VStack {
    // 1. 宽度测量器 (GeometryReader)
    // 用于动态获取容器宽度，响应屏幕旋转或窗口缩放

    // 2. 列布局
    HStack(alignment: .top, spacing: spacing) {
        ForEach(0..<columnCount) { columnIndex in
            LazyVStack(spacing: spacing) {
                // 当前列的数据项
                ForEach(columns[columnIndex]) { item in
                    content(item, safeColumnWidth)
                }
            }
            .frame(width: safeColumnWidth)
        }
    }
}
```

## 布局算法

组件使用 **最短列优先 (Shortest Column First)** 的贪心算法来分配数据项，以保证瀑布流底部的相对平整。

1.  **输入**: 数据集 `Data`，列数 `columnCount`，以及可选的 `aspectRatio` (提供者闭包)。
2.  **高度计算**:
    -   如果未提供 `aspectRatio`，退化为简单的 `index % columnCount` 取模分配。
    -   如果提供了 `aspectRatio` (通常返回 `width / height` 长宽比)，则计算归一化高度 `itemHeight = 1.0 / aspectRatio`。
3.  **分配逻辑**:
    -   维护一个 `columnHeights` 数组记录每列当前高度。
    -   遍历数据项，每次将新项追加到当前高度最小的那一列 (`minIndex`)。
    -   更新该列高度。

### 代码位置

```swift
// Pixiv-SwiftUI/Shared/Components/Layout/WaterfallGrid.swift

// 使用 @State 缓存计算结果，并通过 .onChange(of: data) 更新
@State private var columns: [[Data.Element]] = []

private func recalculateColumns() {
    // ... 初始化 ...
    
    // 智能分配
    for item in data {
        if let minIndex = columnHeights.indices.min(by: { columnHeights[$0] < columnHeights[$1] }) {
            result[minIndex].append(item)
            // ... 更新高度 ...
        }
    }
    columns = result
}
```

## 骨架屏 (Skeleton)

- **文件路径**: `Pixiv-SwiftUI/Shared/Components/SkeletonIllustCard.swift`
- **组件**: `SkeletonIllustWaterfallGrid`
- **注意**: 骨架屏组件 **独立实现** 了类似的网格布局逻辑，并没有复用 `WaterfallGrid`。
    -   **维护风险**: 如果修改了 `WaterfallGrid` 的 `spacing` 或宽度计算逻辑，必须同步修改 `SkeletonIllustWaterfallGrid`，否则会导致加载状态切换到内容状态时布局跳动（Layout Shift）。

## 使用注意事项

### 1. 外部容器（极其重要）

由于 `WaterfallGrid` 内部已经使用了 `LazyVStack` 作为列容器，它本身就具备了懒加载渲染的能力。
**绝对不要**将 `WaterfallGrid` 包裹在外部的 `LazyVStack` 中！
在 SwiftUI 中，嵌套的 `LazyVStack` 会导致布局引擎在滚动时无法正确计算高度，从而引发严重的**滚动抽动（Jitter）**和**布局跳动**。

**正确示例**:

```swift
ScrollView {
    VStack { // 必须使用普通的 VStack
        HeaderView()
        
        WaterfallGrid(...)
        
        // 加载更多触发器
        if isLoading {
            LazyVStack { // 仅将底部的 ProgressView 包裹在 LazyVStack 中，或使用 onAppear 触发
                ProgressView()
                    .onAppear { loadMore() }
            }
        }
    }
}
```

### 2. 加载更多 (Infinite Scroll)

不要将 `loadMore` 触发器放在 `WaterfallGrid` 内部。应将其作为 `WaterfallGrid` 的兄弟视图放置在外部容器的底部。
为了确保 `onAppear` 仅在滚动到底部时触发，你有两种选择：
1. 将底部的 `ProgressView` 单独包裹在一个 `LazyVStack` 中。
2. 在 `WaterfallGrid` 的 `content` 闭包中，为最后一个元素添加 `.onAppear` 触发器（推荐，更可靠）。

### 3. macOS 与 iOS 的列数差异

项目通常根据平台动态调整列数：
- **iOS**: 通常 2 列。
- **macOS/iPad**: 根据宽度动态调整，通常 4 列或更多。
- 使用 `.responsiveGridColumnCount` 修饰符（如果存在）或在父视图中计算 `dynamicColumnCount`。

### 4. 性能优化

- `columns` 属性是计算属性 (Computed Property)。每当 `View` 刷新时都会重新计算布局。
- 在数据量极大（如数千项）时，主线程计算布局可能会造成掉帧。但在本应用的分页场景（通常 < 200 项）下，性能是可以接受的。
- 之前曾尝试使用 `@State` 缓存列数据，但为了保证数据一致性（Data Consistency）和响应式更新，目前回退到了实时计算。

## Git 历史演变

1.  **初始版本**: 简单的取模 (`index % columnCount`) 分配，不支持长宽比感知。
2.  **性能优化尝试 (127c478)**: 引入 `@State` 缓存 `columns`，试图通过 `onChange` 更新。
3.  **算法升级 (Latest)**: 引入 `heightProvider` 接口，实现最短列优先算法，实现了真正的参差不齐的瀑布流效果，更美观。

## 常见问题排查

- **布局跳动**: 检查 `SkeletonIllustWaterfallGrid` 的间距设置是否与 `WaterfallGrid` 一致。检查外部容器是否误用了 `LazyVStack`。
- **加载更多不触发**: 检查外部是否误用了 `VStack` 代替 `LazyVStack` 包裹 `ProgressView`，导致底部视图被提前初始化。
- **图片高度异常**: 确保 `heightProvider` 返回的 `aspectRatio` 不为 0 或 NaN。

