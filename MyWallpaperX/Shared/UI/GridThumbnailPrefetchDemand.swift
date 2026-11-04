import Foundation

/// Bounded nearby demand plus the next native layout viewport, ordered for travel.
/// Visible consumers serve the viewport; equal scores favor travel direction.
nonisolated enum GridThumbnailPrefetchDemand {
    static func indices(visibleIndices: [Int], predictedIndices: [Int] = [], itemCount: Int, neighborLimit: Int, direction: Int,
                        forwardBias: Int = 1) -> [Int] {
        guard itemCount > 0, neighborLimit > 0 else { return [] }
        let valid = visibleIndices.filter { $0 >= 0 && $0 < itemCount }
        guard let first = valid.min(), let last = valid.max() else { return [] }
        var result: [Int] = []
        let limit = min(neighborLimit, itemCount - (last - first + 1))
        result.reserveCapacity(limit)
        var before = first - 1, after = last + 1
        let beforeWeight = direction > 0 ? forwardBias : 1
        let afterWeight = direction < 0 ? forwardBias : 1
        while result.count < limit {
            let takeBefore: Bool
            if before < 0 { takeBefore = false }
            else if after >= itemCount { takeBefore = true }
            else {
                let beforeDistance = (first - before) * beforeWeight
                let afterDistance = (after - last) * afterWeight
                takeBefore = direction < 0 ? beforeDistance <= afterDistance : beforeDistance < afterDistance
            }
            if takeBefore { result.append(before); before -= 1 }
            else { result.append(after); after += 1 }
        }
        let predicted = predictedIndices.filter { (0..<itemCount).contains($0) && ($0 < first || $0 > last) }
        guard predicted.contains(where: { $0 <= before || $0 >= after }) else { return result }
        var planned = Array(result.prefix(last - first + 1))
        var seen = Set(planned)
        guard seen.union(predicted).count <= limit else { return result }
        let approaching = direction < 0 ? Array(predicted.reversed()) : predicted
        for index in approaching + result {
            if planned.count == limit { break }
            if seen.insert(index).inserted { planned.append(index) }
        }
        return planned
    }
}
