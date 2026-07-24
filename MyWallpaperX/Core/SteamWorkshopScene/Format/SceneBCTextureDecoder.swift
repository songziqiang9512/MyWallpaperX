import Foundation

/// CPU decoder for the BC1/BC2/BC3 color payloads stored in TEX containers.
///
/// The compositor's blend state is premultiplied source-over, but BC blocks
/// store straight alpha: uploading them directly makes fully transparent
/// texels contribute their (usually white) RGB and bloom into opaque-looking
/// mattes. Decoding to RGBA8 lets the loader premultiply on CPU — the same
/// contract the raw format-0 path already follows — and crop the padded
/// storage size down to the authored image size.
///
/// Standard public block-compression layout; BC5 normal payloads are not
/// color sources and stay on the direct-upload path. The hot loop is written
/// against raw pointers because unoptimized Debug builds run this on the
/// wallpaper load path for multi-megapixel backgrounds.
nonisolated enum SceneBCTextureDecoder {
    struct DecodedImage {
        let width: Int
        let height: Int
        /// Tightly packed RGBA8, straight alpha.
        let rgba: Data
    }

    enum Format: Equatable {
        case bc1
        case bc2
        case bc3

        nonisolated var bytesPerBlock: Int {
            self == .bc1 ? 8 : 16
        }

        nonisolated init?(texFormat: UInt32) {
            switch texFormat {
            case 4: self = .bc3
            case 6: self = .bc2
            case 7: self = .bc1
            default: return nil
            }
        }
    }

    /// Decodes the stored block grid, then crops to `imageWidth`/`imageHeight`
    /// when the authored image is smaller than the padded storage.
    static func decode(
        blockData: Data,
        storedWidth: Int,
        storedHeight: Int,
        imageWidth: Int,
        imageHeight: Int,
        format: Format
    ) -> DecodedImage? {
        guard storedWidth > 0, storedHeight > 0 else { return nil }
        let blocksWide = (storedWidth + 3) / 4
        let blocksHigh = (storedHeight + 3) / 4
        guard blockData.count == blocksWide * blocksHigh * format.bytesPerBlock else {
            return nil
        }
        let targetWidth = (1 ... storedWidth).contains(imageWidth) ? imageWidth : storedWidth
        let targetHeight = (1 ... storedHeight).contains(imageHeight) ? imageHeight : storedHeight

        var rgba = Data(count: targetWidth * targetHeight * 4)
        let decoded = rgba.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) -> Bool in
            guard let outputBase = output.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }
            return blockData.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Bool in
                guard let inputBase = input.bindMemory(to: UInt8.self).baseAddress else {
                    return false
                }
                decodeGrid(
                    input: inputBase,
                    output: outputBase,
                    blocksWide: blocksWide,
                    blocksHigh: blocksHigh,
                    targetWidth: targetWidth,
                    targetHeight: targetHeight,
                    format: format
                )
                return true
            }
        }
        guard decoded else { return nil }
        return DecodedImage(width: targetWidth, height: targetHeight, rgba: rgba)
    }

    /// Non-Sendable pointers handed to the row-parallel loop. Rows write
    /// disjoint ranges, so sharing these across `concurrentPerform` lanes is
    /// data-race-free by construction.
    private struct GridPointers: @unchecked Sendable {
        let input: UnsafePointer<UInt8>
        let output: UnsafeMutablePointer<UInt8>
    }

    private static func decodeGrid(
        input: UnsafePointer<UInt8>,
        output: UnsafeMutablePointer<UInt8>,
        blocksWide: Int,
        blocksHigh: Int,
        targetWidth: Int,
        targetHeight: Int,
        format: Format
    ) {
        let visibleBlockRows = min(blocksHigh, (targetHeight + 3) / 4)
        let bytesPerBlock = format.bytesPerBlock
        let pointers = GridPointers(input: input, output: output)
        // Block rows write disjoint output regions, so they decode in
        // parallel. This runs on the synchronous wallpaper load path where a
        // 4K background would otherwise stall an unoptimized Debug build.
        DispatchQueue.concurrentPerform(iterations: visibleBlockRows) { blockY in
            // Per-row scratch: 64 B block pixels, 16 B color palette,
            // 8 B alpha palette.
            withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 88) { scratch in
                guard let block = scratch.baseAddress else { return }
                let palette = block + 64
                let pixelY = blockY * 4
                let rowBase = pointers.input + blockY * blocksWide * bytesPerBlock
                for blockX in 0 ..< blocksWide {
                    let pixelX = blockX * 4
                    if pixelX >= targetWidth { continue }
                    decodeBlock(
                        source: rowBase + blockX * bytesPerBlock,
                        format: format,
                        into: block,
                        palette: palette
                    )
                    let copyWidth = min(4, targetWidth - pixelX)
                    let copyHeight = min(4, targetHeight - pixelY)
                    for row in 0 ..< copyHeight {
                        let destination = pointers.output
                            + ((pixelY + row) * targetWidth + pixelX) * 4
                        let source = block + row * 16
                        destination.update(from: source, count: copyWidth * 4)
                    }
                }
            }
        }
    }

    /// Writes one 4x4 block as 64 bytes of RGBA8 into `destination` using the
    /// caller-provided 16-byte palette scratch space.
    private static func decodeBlock(
        source: UnsafePointer<UInt8>,
        format: Format,
        into destination: UnsafeMutablePointer<UInt8>,
        palette: UnsafeMutablePointer<UInt8>
    ) {
        let colorOffset = format == .bc1 ? 0 : 8
        // BC1's punch-through transparent mode only exists in standalone BC1;
        // BC2/BC3 always use the four-color mode.
        decodeColorBlock(
            source: source + colorOffset,
            allowPunchThroughAlpha: format == .bc1,
            into: destination,
            palette: palette
        )
        switch format {
        case .bc1:
            break
        case .bc2:
            decodeExplicitAlpha(source: source, into: destination)
        case .bc3:
            decodeInterpolatedAlpha(source: source, into: destination, palette: palette + 16)
        }
    }

    private static func decodeColorBlock(
        source: UnsafePointer<UInt8>,
        allowPunchThroughAlpha: Bool,
        into destination: UnsafeMutablePointer<UInt8>,
        palette: UnsafeMutablePointer<UInt8>
    ) {
        let c0 = UInt16(source[0]) | (UInt16(source[1]) << 8)
        let c1 = UInt16(source[2]) | (UInt16(source[3]) << 8)
        expand565(c0, into: palette)
        expand565(c1, into: palette + 4)
        palette[3] = 255
        palette[7] = 255
        palette[11] = 255
        palette[15] = 255
        if c0 > c1 || allowPunchThroughAlpha == false {
            for channel in 0 ..< 3 {
                let a = Int(palette[channel])
                let b = Int(palette[4 + channel])
                palette[8 + channel] = UInt8((2 * a + b + 1) / 3)
                palette[12 + channel] = UInt8((a + 2 * b + 1) / 3)
            }
        } else {
            for channel in 0 ..< 3 {
                let a = Int(palette[channel])
                let b = Int(palette[4 + channel])
                palette[8 + channel] = UInt8((a + b + 1) / 2)
            }
            palette[12] = 0
            palette[13] = 0
            palette[14] = 0
            palette[15] = 0
        }
        for row in 0 ..< 4 {
            let bits = source[4 + row]
            let out = destination + row * 16
            for column in 0 ..< 4 {
                let index = Int((bits >> (UInt8(column) * 2)) & 0b11)
                let entry = palette + index * 4
                let pixel = out + column * 4
                pixel[0] = entry[0]
                pixel[1] = entry[1]
                pixel[2] = entry[2]
                pixel[3] = entry[3]
            }
        }
    }

    private static func decodeExplicitAlpha(
        source: UnsafePointer<UInt8>,
        into destination: UnsafeMutablePointer<UInt8>
    ) {
        for row in 0 ..< 4 {
            let bits = UInt16(source[row * 2]) | (UInt16(source[row * 2 + 1]) << 8)
            for column in 0 ..< 4 {
                let alpha4 = UInt8((bits >> (UInt16(column) * 4)) & 0xF)
                destination[(row * 16 + column * 4) + 3] = alpha4 << 4 | alpha4
            }
        }
    }

    private static func decodeInterpolatedAlpha(
        source: UnsafePointer<UInt8>,
        into destination: UnsafeMutablePointer<UInt8>,
        palette: UnsafeMutablePointer<UInt8>
    ) {
        let a0 = Int(source[0])
        let a1 = Int(source[1])
        palette[0] = UInt8(a0)
        palette[1] = UInt8(a1)
        if a0 > a1 {
            for step in 1 ... 6 {
                palette[step + 1] = UInt8(((7 - step) * a0 + step * a1 + 3) / 7)
            }
        } else {
            for step in 1 ... 4 {
                palette[step + 1] = UInt8(((5 - step) * a0 + step * a1 + 2) / 5)
            }
            palette[6] = 0
            palette[7] = 255
        }
        var bits: UInt64 = 0
        for byte in 0 ..< 6 {
            bits |= UInt64(source[2 + byte]) << (UInt64(byte) * 8)
        }
        for pixel in 0 ..< 16 {
            let index = Int((bits >> (UInt64(pixel) * 3)) & 0b111)
            destination[pixel * 4 + 3] = palette[index]
        }
    }

    private static func expand565(_ value: UInt16, into out: UnsafeMutablePointer<UInt8>) {
        let r5 = UInt8((value >> 11) & 0x1F)
        let g6 = UInt8((value >> 5) & 0x3F)
        let b5 = UInt8(value & 0x1F)
        out[0] = (r5 << 3) | (r5 >> 2)
        out[1] = (g6 << 2) | (g6 >> 4)
        out[2] = (b5 << 3) | (b5 >> 2)
    }
}
