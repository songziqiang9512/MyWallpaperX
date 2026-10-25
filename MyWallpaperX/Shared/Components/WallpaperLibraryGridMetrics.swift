import AppKit

/// Steam's square-card geometry, shared by every library and browser grid.
/// The clip width already excludes the sidebar and the native scroller.
nonisolated struct WallpaperLibraryGridMetrics {
    static let defaultColumns = 5
    static let minimumColumns = 3
    static let maximumColumns = 6
    static let minimumCardWidth: CGFloat = 100
    static let edgeInset: CGFloat = 8
    static let horizontalSpacing: CGFloat = 8
    static let verticalSpacing: CGFloat = 10
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 8
    let columns: Int
    let coverSide: CGFloat
    let horizontalInset = Self.edgeInset
    private let fittingColumns: Int

    init(clipWidth: CGFloat, preferredColumns: Int) {
        let width = max(0, clipWidth.isFinite ? clipWidth : 0)
        let available = max(1, width - Self.edgeInset * 2)
        fittingColumns = max(1, Int(min(CGFloat(Self.maximumColumns),
            floor((available + Self.horizontalSpacing) / (Self.minimumCardWidth + Self.horizontalSpacing)))))
        columns = min(fittingColumns, max(Self.minimumColumns, min(Self.maximumColumns, preferredColumns)))
        coverSide = max(1, floor((available - CGFloat(columns - 1) * Self.horizontalSpacing) / CGFloat(columns)))
    }

    static func zoomAvailability(preferredColumns: Int, clipWidth: CGFloat) -> (canZoomOut: Bool, canZoomIn: Bool) {
        let metrics = Self(clipWidth: clipWidth, preferredColumns: preferredColumns)
        return (metrics.columns < metrics.fittingColumns, metrics.columns > Self.minimumColumns)
    }

    /// Positive delta enlarges the card. Start at the actual visible density,
    /// so a temporarily constrained six-column preference changes on one click.
    static func zoomedColumns(preferredColumns: Int, delta: Int, clipWidth: CGFloat) -> Int {
        let metrics = Self(clipWidth: clipWidth, preferredColumns: preferredColumns)
        let direction = delta > 0 ? -1 : delta < 0 ? 1 : 0
        return max(Self.minimumColumns, min(Self.maximumColumns, metrics.columns + direction))
    }
}
