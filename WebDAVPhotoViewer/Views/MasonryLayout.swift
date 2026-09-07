import SwiftUI

/// 瀑布流（Masonry）布局：把子视图按「最短列优先」放入多列
struct MasonryLayout: Layout {
    var columns: Int
    var spacing: CGFloat
    var columnWidth: CGFloat
    var heights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let totalWidth = columnWidth * CGFloat(columns) + spacing * CGFloat(columns - 1)
        var colHeights = [CGFloat](repeating: 0, count: max(columns, 1))
        for (i, _) in subviews.enumerated() {
            let h = height(at: i)
            let c = shortestColumn(colHeights)
            colHeights[c] += h + spacing
        }
        let maxH = colHeights.max() ?? 0
        return CGSize(width: totalWidth, height: max(0, maxH - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var colHeights = [CGFloat](repeating: bounds.minY, count: max(columns, 1))
        for (i, subview) in subviews.enumerated() {
            let h = height(at: i)
            let c = shortestColumn(colHeights)
            let x = bounds.minX + CGFloat(c) * (columnWidth + spacing)
            let y = colHeights[c]
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: columnWidth, height: h))
            colHeights[c] = y + h + spacing
        }
    }

    private func height(at index: Int) -> CGFloat {
        index < heights.count ? heights[index] : 200
    }

    private func shortestColumn(_ heights: [CGFloat]) -> Int {
        var minIdx = 0
        for i in 1..<heights.count where heights[i] < heights[minIdx] {
            minIdx = i
        }
        return minIdx
    }
}
