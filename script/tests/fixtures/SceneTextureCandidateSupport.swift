extension Harness {
    static func candidate(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) throws -> SceneTextureCandidate {
        guard case .loaded(let candidate) = outcome else {
            throw HarnessError.loadFailed
        }
        return candidate
    }

    static func baseLoaded(
        _ outcome: SceneBaseImageTextureLoad.Outcome
    ) throws -> SceneBaseImageTextureLoad.Loaded {
        guard case .loaded(let loaded) = outcome else {
            throw HarnessError.loadFailed
        }
        return loaded
    }

    static func copy(
        _ source: SceneTextureCandidate,
        purpose: SceneTextureLoadPurpose? = nil,
        content: SceneTextureContent? = nil,
        physicalSize: CGSize? = nil,
        mappedSize: CGSize? = nil,
        uvTransform: SceneTextureUVTransform? = nil,
        sampling: SceneTextureSampling? = nil,
        isSpriteSheet: Bool? = nil
    ) -> SceneTextureCandidate {
        SceneTextureCandidate(
            texture: source.texture,
            identity: source.identity,
            generation: source.generation,
            purpose: purpose ?? source.purpose,
            content: content ?? source.content,
            physicalSize: physicalSize ?? source.physicalSize,
            mappedSize: mappedSize ?? source.mappedSize,
            uvTransform: uvTransform ?? source.uvTransform,
            isSpriteSheet: isSpriteSheet ?? source.isSpriteSheet,
            sampling: sampling ?? source.sampling,
            authoredFormat: source.authoredFormat
        )
    }

    static func filePath(_ identity: SceneTextureResourceIdentity) -> String? {
        guard case .file(let path) = identity else { return nil }
        return path
    }

    static func generationByteCount(
        _ generation: SceneTextureResourceGeneration
    ) -> UInt64? {
        guard case .file(let byteCount, _, _) = generation else { return nil }
        return byteCount
    }

    static func rejectedDimensions(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("inconsistent physical/mapped dimensions")
    }

    static func rejectedEmbeddedMetadata(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains(
            "compiled TEX embedded mip metadata does not match its payload"
        )
    }

    static func baseRejectedDimensions(
        _ outcome: SceneBaseImageTextureLoad.Outcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("inconsistent physical/mapped dimensions")
    }

    static func rejectedNonSprite(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("one non-sprite image")
    }

    static func rejectedUnparsedMetadata(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("TEX parse failed")
    }

    static func rawR8Tex(
        textureWidth: UInt32,
        textureHeight: UInt32,
        imageWidth: UInt32,
        imageHeight: UInt32,
        flags: UInt32,
        mipWidth: UInt32? = nil,
        mipHeight: UInt32? = nil,
        payloadByte: UInt8 = 127
    ) -> Data {
        let storedWidth = mipWidth ?? textureWidth
        let storedHeight = mipHeight ?? textureHeight
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(9, to: &data)
        append(flags, to: &data)
        append(textureWidth, to: &data)
        append(textureHeight, to: &data)
        append(imageWidth, to: &data)
        append(imageHeight, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(1, to: &data)
        append(1, to: &data)
        append(storedWidth, to: &data)
        append(storedHeight, to: &data)
        append(0, to: &data)
        append(0, to: &data)
        let payload = Data(
            repeating: payloadByte,
            count: Int(storedWidth * storedHeight)
        )
        append(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    static func spriteR8Tex() -> Data {
        var data = rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 4
        )
        data.append(Data("TEXS0002\0".utf8))
        append(1, to: &data)
        append(0, to: &data)
        appendFloat(0.1, to: &data)
        for value: Float in [1, 0, 0, 4, 4, 0] {
            appendFloat(value, to: &data)
        }
        return data
    }

    static func crossImageSpriteBC3Tex(
        rotatedSecondFrame: Bool = false,
        frameCount: Int = 2,
        frameDuration: Float = 0.035
    ) -> Data {
        func block(
            alpha: UInt8,
            colorLow: UInt8,
            colorHigh: UInt8
        ) -> Data {
            Data([
                alpha, alpha, 0, 0, 0, 0, 0, 0,
                colorLow, colorHigh, 0, 0, 0, 0, 0, 0,
            ])
        }

        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(2, to: &data)
        for payload in [
            block(alpha: 128, colorLow: 0x00, colorHigh: 0xF8),
            block(alpha: 64, colorLow: 0xE0, colorHigh: 0x07),
        ] {
            append(1, to: &data)
            append(4, to: &data)
            append(4, to: &data)
            append(0, to: &data)
            append(0, to: &data)
            append(UInt32(payload.count), to: &data)
            data.append(payload)
        }
        data.append(Data("TEXS0002\0".utf8))
        append(UInt32(frameCount), to: &data)
        for index in 0..<frameCount {
            appendSpriteFrame(
                imageIndex: UInt32(index % 2),
                duration: frameDuration,
                coordinates: rotatedSecondFrame && index == 1
                    ? [0, 0, 0, 4, 4, 0] : [0, 0, 4, 0, 0, 4],
                to: &data
            )
        }
        return data
    }

    static func appendSpriteFrame(
        imageIndex: UInt32,
        duration: Float,
        coordinates: [Float],
        to data: inout Data
    ) {
        append(imageIndex, to: &data)
        appendFloat(duration, to: &data)
        for coordinate in coordinates {
            appendFloat(coordinate, to: &data)
        }
    }

    static func emptySpriteR8Tex() -> Data {
        var data = rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 4
        )
        data.append(Data("TEXS0002\0".utf8))
        append(0, to: &data)
        return data
    }

    static func rawRGBA8Tex(
        textureWidth: UInt32,
        textureHeight: UInt32,
        imageWidth: UInt32,
        imageHeight: UInt32,
        flags: UInt32 = 2
    ) -> Data {
        let payload = Data(
            repeating: 127,
            count: Int(textureWidth * textureHeight * 4)
        )
        return embeddedImageTex(
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            payload: payload,
            flags: flags
        )
    }

    static func embeddedImageTex(
        textureWidth: UInt32,
        textureHeight: UInt32,
        imageWidth: UInt32,
        imageHeight: UInt32,
        payload: Data,
        containerVersion: String = "TEXB0002",
        freeImageFormat: UInt32 = 13,
        mipMetadataEntryCount: UInt32 = 0,
        mipWidth: UInt32? = nil,
        mipHeight: UInt32? = nil,
        additionalMips: [(UInt32, UInt32, Data)] = [],
        flags: UInt32 = 2
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(0, to: &data)
        append(flags, to: &data)
        append(textureWidth, to: &data)
        append(textureHeight, to: &data)
        append(imageWidth, to: &data)
        append(imageHeight, to: &data)
        append(0, to: &data)
        data.append(Data("\(containerVersion)\0".utf8))
        append(1, to: &data)
        if containerVersion == "TEXB0003" {
            append(freeImageFormat, to: &data)
        } else if containerVersion == "TEXB0004" {
            append(freeImageFormat, to: &data)
            append(mipMetadataEntryCount, to: &data)
        }
        let mips = [
            (mipWidth ?? textureWidth, mipHeight ?? textureHeight, payload),
        ] + additionalMips
        append(UInt32(mips.count), to: &data)
        for (width, height, mipPayload) in mips {
            for entry in 0..<mipMetadataEntryCount {
                append(0, to: &data)
                append(0, to: &data)
                data.append(Data("metadata-\(entry)\0".utf8))
                append(0, to: &data)
            }
            append(width, to: &data)
            append(height, to: &data)
            append(0, to: &data)
            append(0, to: &data)
            append(UInt32(mipPayload.count), to: &data)
            data.append(mipPayload)
        }
        return data
    }

    // A transparent texel's RGB must survive interpolation. These values
    // distinguish straight lane filtering from filtering premultiplied RGB.
    static func pngData(width: Int, height: Int) throws -> Data {
        try encodedImageData(
            width: width,
            height: height,
            type: "public.png" as CFString
        )
    }

    static func jpegData(width: Int, height: Int) throws -> Data {
        try encodedImageData(
            width: width,
            height: height,
            type: "public.jpeg" as CFString
        )
    }

    static func opaquePNGData(width: Int, height: Int) throws -> Data {
        let pixels = Data(repeating: 127, count: width * height * 3)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 24,
                  bytesPerRow: width * 3,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.none.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw HarnessError.imageCreationFailed
        }
        return try encodeImage(image, type: "public.png" as CFString)
    }

    static func encodedImageData(
        width: Int,
        height: Int,
        type: CFString
    ) throws -> Data {
        let pixels = Data(repeating: 127, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.last.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw HarnessError.imageCreationFailed
        }
        return try encodeImage(image, type: type)
    }

    static func encodeImage(_ image: CGImage, type: CFString) throws -> Data {
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data,
                  type,
                  1,
                  nil
              ) else {
            throw HarnessError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageCreationFailed
        }
        return data as Data
    }

    static func writeImage(_ url: URL) throws {
        let pixels: [UInt8] = [
            231, 17, 149, 0,
            200, 100, 50, 64,
            17, 203, 41, 255,
            89, 7, 211, 128,
        ]
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: 2,
                  height: 2,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.last.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  "public.png" as CFString,
                  1,
                  nil
              ) else {
            throw HarnessError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageCreationFailed
        }
    }

    static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func appendFloat(_ value: Float, to data: inout Data) {
        var littleEndian = value.bitPattern.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func fileStatus(_ url: URL) throws -> Darwin.stat {
        var status = Darwin.stat()
        guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0 else {
            throw HarnessError.metadataFailed
        }
        return status
    }

    static func restoreTimestamps(
        _ status: Darwin.stat,
        at url: URL
    ) throws {
        let timestamps = [status.st_atimespec, status.st_mtimespec]
        let result = timestamps.withUnsafeBufferPointer { buffer in
            url.path.withCString {
                Darwin.utimensat(AT_FDCWD, $0, buffer.baseAddress, 0)
            }
        }
        guard result == 0 else { throw HarnessError.metadataFailed }
    }

    static func readFirstPixel(texture: MTLTexture, device: MTLDevice) throws -> [Int] {
        try SceneTextureSamplingReadback(device: device).pixel(texture).map(Int.init)
    }

    static func constantTextureFrame(
        _ uv: SIMD2<Float>
    ) -> SceneTextureUVTransform {
        .init(origin: uv, xAxis: .zero, yAxis: .zero)
    }

    static func writeInputs(
        url: URL,
        spriteURL: URL,
        crossImageSpriteURL: URL,
        rotatedCrossImageSpriteURL: URL,
        zeroMappedURL: URL,
        oversizedMappedURL: URL,
        mismatchedPhysicalURL: URL,
        emptySpriteURL: URL,
        fallbackPNGURL: URL,
        unparsedFallbackURL: URL,
        croppedColorURL: URL,
        nearestRepeatColorURL: URL,
        clampBorderColorURL: URL,
        unknownSamplerColorURL: URL,
        normalizedColorURL: URL,
        wrongOutputURL: URL,
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
    ) throws -> Void {
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 3
        ).write(to: url)
        try spriteR8Tex().write(to: spriteURL)
        try crossImageSpriteBC3Tex().write(to: crossImageSpriteURL)
        try crossImageSpriteBC3Tex(rotatedSecondFrame: true)
            .write(to: rotatedCrossImageSpriteURL)
        try rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 0,
            imageHeight: 4,
            flags: 0
        ).write(to: zeroMappedURL)
        try rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 8,
            imageHeight: 4,
            flags: 0
        ).write(to: oversizedMappedURL)
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 0,
            mipWidth: 4,
            mipHeight: 4
        ).write(to: mismatchedPhysicalURL)
        try emptySpriteR8Tex().write(to: emptySpriteURL)
        try writeImage(fallbackPNGURL)
        var unparsedFallback = Data("invalid TEX header ".utf8)
        unparsedFallback.append(try Data(contentsOf: fallbackPNGURL))
        try unparsedFallback.write(to: unparsedFallbackURL)
        try rawRGBA8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4
        ).write(to: croppedColorURL)
        try rawRGBA8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 1
        ).write(to: nearestRepeatColorURL)
        try rawRGBA8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 8
        ).write(to: clampBorderColorURL)
        try rawRGBA8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 16
        ).write(to: unknownSamplerColorURL)
        try embeddedImageTex(
            textureWidth: 8192,
            textureHeight: 4,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try pngData(width: 4097, height: 2)
        ).write(to: normalizedColorURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 3)
        ).write(to: wrongOutputURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4)
        ).write(to: mappedEmbeddedURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 4,
            mipHeight: 4,
            additionalMips: [
                (2, 2, try pngData(width: 2, height: 2)),
            ]
        ).write(to: mappedTexb3EmbeddedURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try pngData(width: 4097, height: 2),
            containerVersion: "TEXB0003",
            mipWidth: 4097,
            mipHeight: 2,
            additionalMips: [
                (2048, 1, try pngData(width: 2048, height: 1)),
            ]
        ).write(to: oversizedTexb3MipChainURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 5,
            mipHeight: 4
        ).write(to: malformedTexb3EmbeddedURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 3, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 4,
            mipHeight: 4
        ).write(to: decodedMismatchTexb3URL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 4,
            mipHeight: 4,
            additionalMips: [
                (2, 2, try pngData(width: 1, height: 2)),
            ]
        ).write(to: lowerMipMismatchTexb3URL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 4,
            mipHeight: 4
        ).write(to: freeFormatMismatchTexb3URL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try jpegData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 4,
            mipHeight: 4,
            additionalMips: [
                (2, 2, try jpegData(width: 2, height: 2)),
            ]
        ).write(to: mappedTexb3JPEGURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try jpegData(width: 4097, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: normalizedStraightAlbedoJPEGURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try opaquePNGData(width: 4097, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 13,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: normalizedStraightAlbedoPNGURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try pngData(width: 4097, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 13,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: transparentStraightAlbedoPNGURL)
        try embeddedImageTex(
            textureWidth: 8192,
            textureHeight: 2,
            imageWidth: 8192,
            imageHeight: 2,
            payload: try pngData(width: 8192, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 13,
            mipWidth: 8192,
            mipHeight: 2,
            additionalMips: [
                (4096, 1, try pngData(width: 4096, height: 1)),
            ]
        ).write(to: authoredStraightAlbedoMipsPNGURL)
        try embeddedImageTex(
            textureWidth: 8192,
            textureHeight: 4,
            imageWidth: 4096,
            imageHeight: 2,
            payload: try jpegData(width: 8192, height: 4),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 8192,
            mipHeight: 4
        ).write(to: paddedStraightAlbedoJPEGURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try opaquePNGData(width: 4097, height: 2),
            containerVersion: "TEXB0004",
            freeImageFormat: 2,
            mipMetadataEntryCount: 2,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: mislabeledTexb4StraightAlbedoPNGURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0002",
            mipWidth: 4,
            mipHeight: 4
        ).write(to: mappedTexb2MipURL)
    }

    enum HarnessError: Error {
        case loadFailed
        case imageCreationFailed
        case metadataFailed
    }
}
