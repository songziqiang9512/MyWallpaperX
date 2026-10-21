import Foundation

/// Bounded, nearest-first offscreen demand. The viewport itself is already
/// served by visible consumers; equal-distance candidates favor travel direction.
nonisolated enum GridThumbnailPrefetchDemand {
    static func indices(visibleIndices: [Int], itemCount: Int, neighborLimit: Int, direction: Int) -> [Int] {
        guard itemCount > 0, neighborLimit > 0 else { return [] }
        let valid = visibleIndices.filter { $0 >= 0 && $0 < itemCount }
        guard let first = valid.min(), let last = valid.max() else { return [] }
        var result: [Int] = []
        let limit = min(neighborLimit, itemCount - (last - first + 1))
        result.reserveCapacity(limit)
        var distance = 1
        while result.count < limit {
            let before = first - distance
            let after = last + distance
            let candidates = direction < 0 ? [before, after] : [after, before]
            for index in candidates where index >= 0 && index < itemCount {
                result.append(index)
                if result.count == limit { break }
            }
            distance += 1
        }
        return result
    }
}
