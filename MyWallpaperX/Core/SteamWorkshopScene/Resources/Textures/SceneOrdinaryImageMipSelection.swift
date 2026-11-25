import Foundation

nonisolated enum SceneOrdinaryImageMipSelection {
    case maximumLongEdge(Int)
    case minimumExtent(SIMD2<Int>)

    func baseIndex(in sizes: [(width: Int, height: Int)], maximumSingleLevelDimension: Int) -> Int {
        let index: Int
        switch self {
        case let .maximumLongEdge(limit):
            index = sizes.firstIndex { max($0.width, $0.height) <= limit } ?? 0
        case let .minimumExtent(extent):
            index = sizes.lastIndex { $0.width >= extent.x && $0.height >= extent.y } ?? 0
        }
        // A compiled chain can exceed the loose-image limit that applies to one level.
        if index > 0, index == sizes.count - 1,
           max(sizes[index].width, sizes[index].height) > maximumSingleLevelDimension {
            return index - 1
        }
        return index
    }
}

nonisolated struct SceneAutomaticTextureProjection {
    let canvas: SIMD2<Double>
    let zoom: Double

    init?(canvasWidth: Float?, canvasHeight: Float?, zoom: Float?) {
        guard let canvasWidth, let canvasHeight,
              canvasWidth.isFinite, canvasHeight.isFinite,
              canvasWidth > 0, canvasHeight > 0 else { return nil }
        let zoom = zoom ?? 1
        guard zoom.isFinite, zoom > 0 else { return nil }
        canvas = SIMD2(Double(max(canvasWidth, 2)), Double(max(canvasHeight, 2)))
        self.zoom = Double(zoom)
    }

    func coverScale(for drawable: CGSize) -> Double {
        max(Double(drawable.width) / canvas.x, Double(drawable.height) / canvas.y) * zoom
    }

    static func worldExtent(size: [Float]?, scale: [Float]?) -> SIMD2<Double>? {
        guard let size, size.count >= 2 else { return nil }
        let scale = scale ?? [1, 1]
        guard scale.count >= 2 else { return nil }
        let extent = SIMD2(Double(size[0]) * abs(Double(scale[0])), Double(size[1]) * abs(Double(scale[1])))
        guard extent.x.isFinite, extent.y.isFinite, extent.x > 0, extent.y > 0 else { return nil }
        return extent
    }

    static func minimumExtent(worldExtent: SIMD2<Double>, coverScale: Double) -> SIMD2<Int>? {
        guard coverScale.isFinite, coverScale > 0,
              let width = Int(exactly: ceil(worldExtent.x * coverScale)),
              let height = Int(exactly: ceil(worldExtent.y * coverScale)),
              width > 0, height > 0 else { return nil }
        return SIMD2(width, height)
    }

    struct Source {
        var worldExtent: SIMD2<Double>
        var layerIDs: [Int]

        mutating func include(layerID: Int, worldExtent other: SIMD2<Double>) {
            layerIDs.append(layerID)
            worldExtent = SIMD2(max(worldExtent.x, other.x), max(worldExtent.y, other.y))
        }

        func maximumCoverScale(for physical: CGSize) -> Double {
            min(Double(physical.width) / worldExtent.x, Double(physical.height) / worldExtent.y)
        }
    }
}
