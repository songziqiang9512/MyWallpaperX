//
//  GridLayoutHelper.swift
//  MyWallpaperX
//
//  三模块共享的网格列数计算工具。
//  各模块传入自己的 zoomOffset，不共享状态。
//

import AppKit

enum GridLayoutHelper {
    /// 根据可用宽度计算基础列数（不含缩放偏移）
    static func baseColumnCount(for width: CGFloat) -> Int {
        if width >= 1200 { return 6 }
        if width >= 900  { return 5 }
        if width >= 600  { return 4 }
        return 3
    }

    /// 叠加缩放偏移后的实际列数，限制在 minCols~maxCols 范围内
    /// - Parameters:
    ///   - width: 网格可用宽度
    ///   - zoomOffset: 用户手动调整的列数偏移（负数=更大卡片，正数=更多列）
    ///   - minCols: 最小列数（默认3，在线库可传2）
    ///   - maxCols: 最大列数（默认6）
    static func columnCount(
        for width: CGFloat,
        zoomOffset: Int,
        minCols: Int = 3,
        maxCols: Int = 6,
        minimumItemWidth: CGFloat = 0
    ) -> Int {
        let maximum = fittingMaximum(for: width, maxCols: maxCols, minimumItemWidth: minimumItemWidth)
        return max(min(minCols, maximum), min(maximum, baseColumnCount(for: width) + zoomOffset))
    }

    /// 缩放按钮可用性，返回 (canZoomOut, canZoomIn)
    /// - Parameters:
    ///   - currentOffset: 当前缩放偏移值
    ///   - width: 网格可用宽度
    ///   - minCols: 最小列数
    ///   - maxCols: 最大列数
    static func zoomAvailability(
        currentOffset: Int,
        for width: CGFloat,
        minCols: Int = 3,
        maxCols: Int = 6,
        minimumItemWidth: CGFloat = 0
    ) -> (canZoomOut: Bool, canZoomIn: Bool) {
        let maximum = fittingMaximum(for: width, maxCols: maxCols, minimumItemWidth: minimumItemWidth)
        let current = columnCount(for: width, zoomOffset: currentOffset, minCols: minCols,
                                  maxCols: maxCols, minimumItemWidth: minimumItemWidth)
        let canZoomOut = current > min(minCols, maximum)
        let canZoomIn = current < maximum
        return (canZoomOut, canZoomIn)
    }

    static func zoomedOffset(currentOffset: Int, delta: Int, for width: CGFloat,
                             minCols: Int = 3, maxCols: Int = 6, minimumItemWidth: CGFloat = 0) -> Int {
        let maximum = fittingMaximum(for: width, maxCols: maxCols, minimumItemWidth: minimumItemWidth)
        let current = columnCount(for: width, zoomOffset: currentOffset, minCols: minCols,
                                  maxCols: maxCols, minimumItemWidth: minimumItemWidth)
        let target = max(min(minCols, maximum), min(maximum, current + delta))
        return target - baseColumnCount(for: width)
    }

    @MainActor static func availableWidth(in view: NSView?) -> CGFloat? {
        guard let view, !view.isHiddenOrHasHiddenAncestor else { return nil }
        if let collection = view as? NSCollectionView,
           let flow = collection.collectionViewLayout as? NSCollectionViewFlowLayout,
           let clip = collection.enclosingScrollView?.contentView {
            let width = clip.bounds.width - flow.sectionInset.left - flow.sectionInset.right
            if width.isFinite, width > 1 { return width }
        }
        for child in view.subviews {
            if let width = availableWidth(in: child) { return width }
        }
        return nil
    }

    private static func fittingMaximum(for width: CGFloat, maxCols: Int, minimumItemWidth: CGFloat) -> Int {
        guard minimumItemWidth > 0, width.isFinite else { return maxCols }
        // Flow grids reserve at least eight points between cards. Their
        // minimum card width must not force fewer native columns than declared.
        return max(1, Int(min(CGFloat(maxCols), max(0, width + 8) / (minimumItemWidth + 8))))
    }
}
