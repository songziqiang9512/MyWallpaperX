//
//  SILWaterfallLayout.swift
//  MyWallpaperX — Modules/StaticImageLibrary/UI
//
//  瀑布流布局：每列维护高度累加器，图片按原始比例放入最短列。
//  列数由外部 columnCount 决定，卡片高度由 aspectRatio 计算，
//  限制在 minAspectRatio ~ maxAspectRatio 范围内避免极端比例。
//
import AppKit

final class SILWaterfallLayout: NSCollectionViewLayout {

    // MARK: - 配置

    /// 列数（由 zoomOffset 驱动，外部设置后调用 invalidateLayout）
    var columnCount: Int = 4

    /// 列间距
    var columnSpacing: CGFloat = 8

    /// 行间距
    var rowSpacing: CGFloat = 10

    /// 内边距
    var sectionInset: NSEdgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

    /// 最小宽高比（防止超高竖图），0.25 = 1:4
    var minAspectRatio: CGFloat = 0.25

    /// 最大宽高比（防止超宽横图），3:1
    var maxAspectRatio: CGFloat = 3.0

    /// 每个 item 的宽高比提供者（indexPath -> aspectRatio）
    var aspectRatioProvider: ((IndexPath) -> CGFloat)?

    // MARK: - 内部状态

    private var cache: [NSCollectionViewLayoutAttributes] = []
    /// cache 按 item 顺序存储；最短列的起点 Y 单调不减，前缀最大底边覆盖较早的高卡片。
    private var prefixMaxY: [CGFloat] = []
    private var canUseRectIndex = true
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat {
        guard let cv = collectionView else { return 0 }
        return cv.bounds.width - sectionInset.left - sectionInset.right
    }

    // MARK: - 布局计算

    override func prepare() {
        super.prepare()
        guard let cv = collectionView else { return }
        cache.removeAll(keepingCapacity: true)
        prefixMaxY.removeAll(keepingCapacity: true)
        canUseRectIndex = true

        // 还没有 section 时直接返回，避免 numberOfItems(inSection:0) 崩溃
        guard cv.numberOfSections > 0 else {
            contentHeight = 0
            return
        }

        let cols = max(1, columnCount)
        let colWidth = max(60, (contentWidth - columnSpacing * CGFloat(cols - 1)) / CGFloat(cols))

        var colHeights = [CGFloat](repeating: sectionInset.top, count: cols)

        let itemCount = cv.numberOfItems(inSection: 0)
        for i in 0 ..< itemCount {
            let ip = IndexPath(item: i, section: 0)

            // 找最短列
            let shortestCol = colHeights.indices.min(by: { colHeights[$0] < colHeights[$1] }) ?? 0
            let x = sectionInset.left + CGFloat(shortestCol) * (colWidth + columnSpacing)
            let y = colHeights[shortestCol]

            // 计算卡片高度
            let rawRatio = aspectRatioProvider?(ip) ?? (16.0 / 9.0)
            let clampedRatio = max(minAspectRatio, min(maxAspectRatio, rawRatio))
            let cardH = colWidth / clampedRatio

            let attrs = NSCollectionViewLayoutAttributes(forItemWith: ip)
            attrs.frame = CGRect(x: x, y: y, width: colWidth, height: cardH)
            // 非有限比例或外部异常配置仍保留旧 frame/查询语义，不让二分扩大其影响。
            if !attrs.frame.minY.isFinite || !attrs.frame.maxY.isFinite
                || (cache.last.map { $0.frame.minY > attrs.frame.minY } ?? false) {
                canUseRectIndex = false
            }
            cache.append(attrs)
            prefixMaxY.append(max(prefixMaxY.last ?? attrs.frame.maxY, attrs.frame.maxY))

            colHeights[shortestCol] += cardH + rowSpacing
        }

        contentHeight = (colHeights.max() ?? sectionInset.top) + sectionInset.bottom - rowSpacing
        contentHeight = max(contentHeight, sectionInset.top + sectionInset.bottom)
    }

    override var collectionViewContentSize: NSSize {
        guard let cv = collectionView else { return .zero }
        return NSSize(width: cv.bounds.width, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard canUseRectIndex, !rect.minY.isNaN, !rect.maxY.isNaN else {
            return cache.filter { $0.frame.intersects(rect) }
        }
        // 二分只缩小候选区间，最终仍用原 intersects 判断并保持 cache 的 item 顺序。
        // 不能只按起点查下界，否则会漏掉视口上方起始、仍跨入视口的竖图。
        var lower = 0
        var upper = cache.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if prefixMaxY[middle] < rect.minY { lower = middle + 1 }
            else { upper = middle }
        }
        let start = lower
        upper = cache.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if cache[middle].frame.minY <= rect.maxY { lower = middle + 1 }
            else { upper = middle }
        }
        return cache[start..<lower].filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.count == 2, indexPath.section == 0, cache.indices.contains(indexPath.item) else { return nil }
        return cache[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        collectionView?.bounds.width != newBounds.width
    }
}
