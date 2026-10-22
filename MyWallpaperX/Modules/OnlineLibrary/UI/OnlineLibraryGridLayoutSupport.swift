//
//  OnlineLibraryGridLayoutSupport.swift
//  MyWallpaperX
//

import AppKit

struct OnlineLibraryGridLayoutMetrics {
    let columns: Int
    let interitemSpacing: CGFloat
    let lineSpacing: CGFloat
    let itemSize: NSSize
}

enum OnlineLibraryGridLayoutSupport {
    static func metrics(
        boundsWidth: CGFloat,
        zoomOffset: Int,
        sectionInset: NSEdgeInsets
    ) -> OnlineLibraryGridLayoutMetrics {
        let available = max(0, boundsWidth - sectionInset.left - sectionInset.right)
        let columns = GridLayoutHelper.columnCount(
            for: available,
            zoomOffset: zoomOffset,
            minCols: 3,
            maxCols: 6,
            minimumItemWidth: 100
        )
        let spacing: CGFloat = 8
        let totalSpacing = CGFloat(max(0, columns - 1)) * spacing
        let cardWidth = max(100, (available - totalSpacing) / CGFloat(columns))
        let cardHeight = max(56, cardWidth / (16.0 / 9.0))

        return OnlineLibraryGridLayoutMetrics(
            columns: columns,
            interitemSpacing: spacing,
            lineSpacing: spacing,
            itemSize: NSSize(width: floor(cardWidth), height: floor(cardHeight + 2))
        )
    }
}
