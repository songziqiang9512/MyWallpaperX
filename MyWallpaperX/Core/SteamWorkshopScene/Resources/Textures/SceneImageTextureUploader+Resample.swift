import Foundation

nonisolated extension SceneImageTextureUploader {
    /// Resamples a straight RGBA buffer through the shared premultiplied box
    /// kernel. Core Graphics image rasterization premultiplies translucent
    /// pixels, so it cannot preserve authored RGB where alpha is zero or
    /// fractional.
    static func resampledStraightRGBA(
        _ source: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        destinationWidth: Int,
        destinationHeight: Int
    ) -> Data {
        source.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return premultipliedBoxResampledRGBA(
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                destinationWidth: destinationWidth, destinationHeight: destinationHeight
            ) { x, y in
                let offset = (y * sourceWidth + x) * 4
                return SIMD4(Double(bytes[offset]), Double(bytes[offset + 1]),
                             Double(bytes[offset + 2]), Double(bytes[offset + 3]))
            }
        }
    }

    /// Filters straight RGBA in the premultiplied domain, then restores it:
    /// RGB premultiplies by alpha, every destination pixel aggregates the
    /// complete set of source pixels its footprint covers with one overlap
    /// weight per source pixel (integer ratios give uniform integer weights,
    /// so no downscale ratio skips source samples), and alpha > 0 divides the
    /// accumulated energy back out. The straight-albedo and preserved-channel
    /// downscale paths share this kernel, so translucent edges weight RGB by
    /// carried energy instead of averaging colors evenly. A destination pixel
    /// with zero accumulated alpha keeps the authored RGB of the first covered
    /// source pixel — every covered pixel is zero alpha there, so authored RGB
    /// survives resampling. The reader can normalize a packed image without
    /// allocating a full-size RGBA copy.
    static func premultipliedBoxResampledRGBA(
        sourceWidth: Int, sourceHeight: Int,
        destinationWidth: Int, destinationHeight: Int,
        pixel: (Int, Int) -> SIMD4<Double>
    ) -> Data {
        // Per-axis tap tables: for each destination index the covered source
        // start, the tap count, and one overlap weight per covered source
        // index (the footprint intersection length).
        func taps(_ source: Int, _ destination: Int)
            -> (starts: [Int], counts: [Int], weights: [Double]) {
            let ratio = Double(source) / Double(destination)
            var starts = [Int](repeating: 0, count: destination)
            var counts = [Int](repeating: 0, count: destination)
            var weights = [Double]()
            weights.reserveCapacity(source + destination)
            for index in 0..<destination {
                let lower = Double(index) * ratio
                let upper = min(Double(source), Double(index + 1) * ratio)
                starts[index] = min(Int(lower), source - 1)
                var cursor = Int(lower), covered = 0
                while cursor < source, Double(cursor) < upper {
                    weights.append(
                        min(Double(cursor + 1), upper) - max(Double(cursor), lower)
                    )
                    cursor += 1
                    covered += 1
                }
                counts[index] = covered
            }
            return (starts, counts, weights)
        }
        let horizontal = taps(sourceWidth, destinationWidth)
        let vertical = taps(sourceHeight, destinationHeight)
        var destination = Data(count: destinationWidth * destinationHeight * 4)
        destination.withUnsafeMutableBytes { raw in
            let output = raw.bindMemory(to: UInt8.self)
            var rowWeightOffset = 0
            for y in 0..<destinationHeight {
                let rowStart = vertical.starts[y], rowCount = vertical.counts[y]
                var columnWeightOffset = 0
                for x in 0..<destinationWidth {
                    let columnStart = horizontal.starts[x]
                    let columnCount = horizontal.counts[x]
                    var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0
                    var weightSum = 0.0
                    var authored = SIMD3<Double>()
                    for row in 0..<rowCount {
                        let rowWeight = vertical.weights[rowWeightOffset + row]
                        for column in 0..<columnCount {
                            let sample = pixel(columnStart + column, rowStart + row)
                            let weight = horizontal.weights[
                                columnWeightOffset + column
                            ] * rowWeight
                            let energy = sample.w / 255
                            red += sample.x * energy * weight
                            green += sample.y * energy * weight
                            blue += sample.z * energy * weight
                            alpha += sample.w * weight
                            weightSum += weight
                            if row == 0, column == 0 { authored = SIMD3(sample.x, sample.y, sample.z) }
                        }
                    }
                    columnWeightOffset += columnCount
                    // Zero accumulated alpha means every covered source pixel
                    // is zero alpha; straight RGB stays authored there.
                    let value = alpha > 0
                        ? SIMD4(red * 255 / alpha, green * 255 / alpha,
                                blue * 255 / alpha, alpha / weightSum)
                        : SIMD4(authored.x, authored.y, authored.z, 0)
                    for channel in 0..<4 {
                        output[(y * destinationWidth + x) * 4 + channel] =
                            UInt8(clamping: Int(value[channel].rounded()))
                    }
                }
                rowWeightOffset += rowCount
            }
        }
        return destination
    }
}
