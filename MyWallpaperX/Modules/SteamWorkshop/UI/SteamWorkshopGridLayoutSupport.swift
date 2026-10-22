//
//  SteamWorkshopGridLayoutSupport.swift
//  MyWallpaperX
//

import AppKit

struct SteamWorkshopGridLayoutMetrics {
    let columns: Int
    let interitemSpacing: CGFloat
    let lineSpacing: CGFloat
    let itemSize: NSSize
}

enum SteamWorkshopGridLayoutSupport {
    static let baseSpacing: CGFloat = 8
    static let verticalSpacingOffset: CGFloat = 2
    static let minimumCardWidth: CGFloat = 100
    static let sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    static func makeFlowLayout() -> NSCollectionViewFlowLayout {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = baseSpacing
        layout.minimumLineSpacing = baseSpacing
        layout.sectionInset = sectionInset
        return layout
    }

    static func shouldAnimateChange(from previous: [String], to next: [String],
                                    visibleCount: Int, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, !previous.isEmpty else { return false }
        let oldIDs = Set(previous), newIDs = Set(next)
        let changes = oldIDs.symmetricDifference(newIDs).count
        return changes > 0 && changes <= max(20, visibleCount + 20)
            && previous.filter(newIDs.contains) == next.filter(oldIDs.contains)
    }

    static func metrics(
        boundsWidth: CGFloat,
        zoomOffset: Int,
        sectionInset: NSEdgeInsets = sectionInset
    ) -> SteamWorkshopGridLayoutMetrics {
        let availableWidth = max(0, boundsWidth - sectionInset.left - sectionInset.right)
        let columns = max(1, GridLayoutHelper.columnCount(
            for: availableWidth,
            zoomOffset: zoomOffset,
            minimumItemWidth: minimumCardWidth
        ))
        let spacing = baseSpacing
        let verticalSpacing = spacing + verticalSpacingOffset
        let totalSpacing = CGFloat(max(0, columns - 1)) * spacing
        let cardWidth = max(minimumCardWidth, (availableWidth - totalSpacing) / CGFloat(columns))

        return SteamWorkshopGridLayoutMetrics(
            columns: columns,
            interitemSpacing: spacing,
            lineSpacing: verticalSpacing,
            itemSize: NSSize(width: floor(cardWidth), height: floor(cardWidth))
        )
    }
}
