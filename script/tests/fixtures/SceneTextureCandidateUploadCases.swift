extension Harness {
    static func embeddedUploadCases(
        device: MTLDevice,
        loader: SceneTextureLoader,
        directory: URL,
        normalizedColorURL: URL,
        mappedEmbeddedURL: URL,
        mappedTexb3EmbeddedURL: URL,
        oversizedTexb3MipChainURL: URL,
        malformedTexb3EmbeddedURL: URL,
        decodedMismatchTexb3URL: URL,
        lowerMipMismatchTexb3URL: URL,
        freeFormatMismatchTexb3URL: URL,
        mappedTexb3JPEGURL: URL,
        normalizedStraightAlbedoJPEGURL: URL,
        normalizedStraightAlbedoPNGURL: URL,
        transparentStraightAlbedoPNGURL: URL,
        authoredStraightAlbedoMipsPNGURL: URL,
        paddedStraightAlbedoJPEGURL: URL,
        mislabeledTexb4StraightAlbedoPNGURL: URL,
        mappedTexb2MipURL: URL
    ) throws -> (directTransparent: SceneTextureCandidate, result: [String: Any]) {
        let mappedEmbeddedColor = try candidate((try loader.loadCandidate(
            from: mappedEmbeddedURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let mappedEmbeddedNormalRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: mappedEmbeddedURL,
                purpose: .normal,
                device: device
            ))
        )
        let mappedTexb3EmbeddedColor = try candidate((try loader.loadCandidate(
            from: mappedTexb3EmbeddedURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let oversizedTexb3MipChainColor = try candidate((try loader.loadCandidate(
            from: oversizedTexb3MipChainURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let mappedTexb3EmbeddedNormal = try candidate((try loader.loadCandidate(
            from: mappedTexb3EmbeddedURL,
            purpose: .normal,
            device: device
        )))
        let malformedTexb3EmbeddedRejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: malformedTexb3EmbeddedURL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let decodedMismatchTexb3Rejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: decodedMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let lowerMipMismatchTexb3Rejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: lowerMipMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let freeFormatMismatchTexb3Rejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: freeFormatMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let mappedTexb3JPEG = try candidate((try loader.loadCandidate(
            from: mappedTexb3JPEGURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let normalizedStraightAlbedoJPEG = try candidate((try loader.loadCandidate(
            from: normalizedStraightAlbedoJPEGURL,
            purpose: .straightAlbedo,
            device: device
        )))
        let normalizedStraightAlbedoPNG = try candidate((try loader.loadCandidate(
            from: normalizedStraightAlbedoPNGURL,
            purpose: .straightAlbedo,
            device: device
        )))
        let transparentStraightAlbedoPNG = try candidate((try loader.loadCandidate(
            from: transparentStraightAlbedoPNGURL,
            purpose: .straightAlbedo,
            device: device
        )))
        let transparentStraightAlbedoPixel = try readFirstPixel(
            texture: transparentStraightAlbedoPNG.texture, device: device
        )
        let directTransparentURL = directory.appendingPathComponent("transparent-large.png")
        try pngData(width: 4097, height: 2).write(to: directTransparentURL)
        let directTransparent = try candidate((try loader.loadCandidate(
            from: directTransparentURL, purpose: .straightAlbedo, device: device
        )))
        let legacyMappedStraight = try candidate((try loader.loadCandidate(
            from: mappedEmbeddedURL, purpose: .straightAlbedo, device: device)))
        let normalizedLegacyStraight = try candidate((try loader.loadCandidate(
            from: normalizedColorURL, purpose: .straightAlbedo, device: device)))
        let paddedMipsURL = directory.appendingPathComponent("padded-straight-mips.tex")
        try embeddedImageTex(textureWidth: 8192, textureHeight: 8,
            imageWidth: 4096, imageHeight: 8, payload: try pngData(width: 8192, height: 8),
            containerVersion: "TEXB0003", freeImageFormat: 13, mipWidth: 8192, mipHeight: 8,
            additionalMips: [(4096, 4, try pngData(width: 4096, height: 4))]).write(to: paddedMipsURL)
        let paddedStraightMips = try candidate((try loader.loadCandidate(
            from: paddedMipsURL, purpose: .straightAlbedo, device: device)))
        let straightResize = try straightResizeProbe(device: device)
        let authoredStraightAlbedoMipsPNG = try candidate(
            (try loader.loadCandidate(
                from: authoredStraightAlbedoMipsPNGURL,
                purpose: .straightAlbedo,
                device: device
            ))
        )
        let authoredStraightAlbedoMipsPixel = try readFirstPixel(
            texture: authoredStraightAlbedoMipsPNG.texture,
            device: device
        )
        let paddedStraightAlbedoJPEGRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: paddedStraightAlbedoJPEGURL,
                purpose: .straightAlbedo,
                device: device
            ))
        )
        let mislabeledTexb4StraightAlbedoPNGRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: mislabeledTexb4StraightAlbedoPNGURL,
                purpose: .straightAlbedo,
                device: device
            ))
        )
        let mappedTexb2MipRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: mappedTexb2MipURL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let result: [String: Any] = [
            "mappedEmbeddedColorIdentity":
                mappedEmbeddedColor.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedEmbeddedNormalRejected": mappedEmbeddedNormalRejected,
            "mappedTexb3EmbeddedColorIdentity":
                mappedTexb3EmbeddedColor.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedTexb3EmbeddedColorPreservesMipChain":
                mappedTexb3EmbeddedColor.texture.mipmapLevelCount == 2,
            "oversizedTexb3MipChainPreservesAuthoredBase":
                oversizedTexb3MipChainColor.texture.width == 4097
                    && oversizedTexb3MipChainColor.texture.height == 2
                    && oversizedTexb3MipChainColor.texture.mipmapLevelCount == 2
                    && oversizedTexb3MipChainColor.physicalSize
                        == CGSize(width: 4097, height: 2)
                    && oversizedTexb3MipChainColor.mappedSize
                        == CGSize(width: 4097, height: 2),
            "mappedTexb3EmbeddedNormalIdentity":
                mappedTexb3EmbeddedNormal.axisAlignedMappedUVScale(
                    expectedPurpose: .normal
                ) == SIMD2(repeating: 1),
            "malformedTexb3EmbeddedRejected": malformedTexb3EmbeddedRejected,
            "decodedMismatchTexb3Rejected": decodedMismatchTexb3Rejected,
            "lowerMipMismatchTexb3Rejected": lowerMipMismatchTexb3Rejected,
            "freeFormatMismatchTexb3Rejected":
                freeFormatMismatchTexb3Rejected,
            "mappedTexb3JPEGIdentity":
                mappedTexb3JPEG.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedTexb3JPEGOpaque":
                mappedTexb3JPEG.content == .color(.resolved(.opaque)),
            "mappedTexb3PNGPreservesAlphaContract":
                mappedTexb3EmbeddedColor.content
                    == .color(.resolved(.premultipliedAlpha)),
            "normalizedStraightAlbedoJPEGIdentity":
                normalizedStraightAlbedoJPEG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && normalizedStraightAlbedoJPEG.texture.width == 4096
                    && normalizedStraightAlbedoJPEG.texture.height == 1,
            "normalizedStraightAlbedoPNGIdentity":
                normalizedStraightAlbedoPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && normalizedStraightAlbedoPNG.texture.width == 4096
                    && normalizedStraightAlbedoPNG.texture.height == 1,
            "transparentStraightAlbedoPNG":
                transparentStraightAlbedoPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2<Float>(repeating: 1)
                    && transparentStraightAlbedoPNG.texture.width == 4096
                    && transparentStraightAlbedoPNG.texture.height == 1
                    && transparentStraightAlbedoPNG.texture.mipmapLevelCount == 1,
            "transparentStraightAlbedoPixel": transparentStraightAlbedoPixel,
            "directTransparentPNG": directTransparent.texture.width == 4096
                && directTransparent.texture.height == 1
                && directTransparent.texture.mipmapLevelCount == 13
                && directTransparent.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo) == SIMD2<Float>(repeating: 1),
            "normalizedLegacyStraight": normalizedLegacyStraight.texture.width == 4096
                && normalizedLegacyStraight.texture.height == 1
                && normalizedLegacyStraight.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo) == SIMD2<Float>(repeating: 1),
            "paddedStraightMips": paddedStraightMips.texture.width == 8192
                && paddedStraightMips.texture.height == 8 && paddedStraightMips.texture.mipmapLevelCount == 2
                && paddedStraightMips.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo) == SIMD2<Float>(0.5, 1),
            "legacyMappedStraight": legacyMappedStraight.axisAlignedMappedUVScale(
                expectedPurpose: .straightAlbedo) == SIMD2<Float>(repeating: 1),
            "straightResize": straightResize,
            "authoredStraightAlbedoMipsPNG":
                authoredStraightAlbedoMipsPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && authoredStraightAlbedoMipsPNG.texture.width == 8192
                    && authoredStraightAlbedoMipsPNG.texture.height == 2
                    && authoredStraightAlbedoMipsPNG.texture.mipmapLevelCount == 2
                    && authoredStraightAlbedoMipsPNG.content
                        == .color(.resolved(.straightAlpha)),
            "authoredStraightAlbedoMipsPixel":
                authoredStraightAlbedoMipsPixel,
            "paddedStraightAlbedoJPEGRejected":
                paddedStraightAlbedoJPEGRejected,
            "mislabeledTexb4StraightAlbedoPNGRejected":
                mislabeledTexb4StraightAlbedoPNGRejected,
            "mappedTexb2MipRejected": mappedTexb2MipRejected,
        ]
        return (directTransparent, result)
    }

    static func straightResizeProbe(device: MTLDevice) throws -> [String: Any] {
        func image(_ pixels: [UInt8], _ width: Int, _ height: Int,
                   alpha: CGImageAlphaInfo = .last) throws -> CGImage {
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(width: width, height: height,
                    bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false,
                    intent: .defaultIntent) else { throw HarnessError.imageCreationFailed }
            return image
        }
        let colors: [UInt8] = [255,0,0,0, 0,0,255,255]
        let horizontal = try image(colors, 2, 1)
        let vertical = try image(colors, 1, 2)
        let nonInteger = try image([255,0,0,0, 0,0,255,255, 0,255,0,0], 3, 1)
        let zeroAlpha = try image([17,91,203,0, 17,91,203,0], 2, 1)
        let premultiplied = try image(colors, 2, 1, alpha: .premultipliedLast)
        func scaled(_ image: CGImage, width: Int = 1) -> [Int] {
            SceneImageTextureUploader.rgbaData(image: image, width: width, height: 1,
                purpose: .straightAlbedo)?.map(Int.init) ?? []
        }
        let encoded = try encodeImage(horizontal, type: "public.png" as CFString)
        guard let source = CGImageSourceCreateWithData(encoded as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              case let .loaded(texture) = SceneImageTextureUploader.upload(
                image: decoded, purpose: .straightAlbedo, maxDimension: 1,
                device: device) else { throw HarnessError.loadFailed }
        // A source beyond the previous full-RGBA scratch limit is now
        // sampled directly into the one-pixel output.
        let oversized = try image([UInt8](repeating: 127, count: 4097 * 4096 * 4),
                                  4097, 4096)
        let rows: [UInt8] = [0,0,255,0, 255,0,0,255, 9,9,9,9,
                              0,255,0,128, 255,255,255,64, 9,9,9,9]
        func strided(_ bytes: [UInt8], decode: UnsafePointer<CGFloat>? = nil,
                     order: CGBitmapInfo = .byteOrder32Little) -> CGImage? {
            CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | order.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: decode,
                shouldInterpolate: false, intent: .defaultIntent)
        }
        let stridedImage = strided(rows)!
        let truncated = strided(Array(rows.dropLast()))
        let invalidOrder = strided(rows, order: .byteOrder16Big)
        let invalidDecode = [CGFloat](repeating: 1, count: 8).withUnsafeBufferPointer {
            strided(rows, decode: $0.baseAddress)
        }
        func converted(_ bits: Int, gray: Bool, little: Bool) throws -> [Int] {
            let values: [UInt16] = gray ? [200,0,64,255] : [255,0,0,0,0,0,255,255]
            var bytes: [UInt8] = []
            for (index, value) in values.enumerated() {
                if bits == 8 { bytes.append(UInt8(value)) }
                else {
                    let word: UInt16 = gray ? value * 257 : [65535,0x1234,0,0,0,0,0xABCD,0x8001][index]
                    bytes += little ? [UInt8(word & 255),UInt8(word >> 8)]
                        : [UInt8(word >> 8),UInt8(word & 255)]
                }
            }
            let order: CGBitmapInfo = bits == 16
                ? (little ? .byteOrder16Little : .byteOrder16Big) : .byteOrderDefault
            let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let value = CGImage(width: 2, height: 1, bitsPerComponent: bits,
                bitsPerPixel: (gray ? 2 : 4) * bits, bytesPerRow: bytes.count,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | order.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let raw = scaled(value)
            let png = try encodeImage(value, type: "public.png" as CFString)
            let source = CGImageSourceCreateWithData(png as CFData, nil)!
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            return raw + scaled(decoded)
        }
        return [
            "stridedFirst": SceneImageTextureUploader.rgbaData(image: stridedImage,
                width: 2, height: 2, purpose: .straightAlbedo)?.map(Int.init) ?? [],
            "stridedResize": scaled(stridedImage),
            "truncatedRejected": truncated.map { scaled($0).isEmpty } ?? true,
            "decodeRejected": invalidDecode.map { scaled($0).isEmpty } ?? true,
            "bitmapRejected": invalidOrder.map { scaled($0).isEmpty } ?? true,
            "gray8": try converted(8, gray: true, little: false),
            "gray16": try converted(16, gray: true, little: false),
            "rgba16Big": try converted(16, gray: false, little: false),
            "rgba16Little": try converted(16, gray: false, little: true),
            "horizontal": scaled(horizontal),
            "vertical": scaled(vertical),
            "nonInteger": scaled(nonInteger, width: 2),
            "zeroAlpha": scaled(zeroAlpha),
            "premultipliedRejected": scaled(premultiplied).isEmpty,
            "dataResizeRejected": SceneImageTextureUploader.rgbaData(
                image: horizontal, width: 1, height: 1, purpose: .normal) == nil,
            "largeSourcePreserved": scaled(oversized) == [127,127,127,127],
            "directPNG": try readFirstPixel(texture: texture, device: device),
        ]
    }
}
