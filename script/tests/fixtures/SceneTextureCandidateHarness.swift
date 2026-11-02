@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        let shaderSource = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let imageLayerLibrary = try device.makeLibrary(
            source: shaderSource,
            options: nil
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-texture-candidate-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("padded-mask.tex")
        let missingURL = directory.appendingPathComponent("missing-mask.tex")
        let spriteURL = directory.appendingPathComponent("sprite-mask.tex")
        let crossImageSpriteURL = directory.appendingPathComponent(
            "cross-image-sprite.tex"
        )
        let rotatedCrossImageSpriteURL = directory.appendingPathComponent(
            "rotated-cross-image-sprite.tex"
        )
        let zeroMappedURL = directory.appendingPathComponent("zero-mapped-mask.tex")
        let oversizedMappedURL = directory.appendingPathComponent(
            "oversized-mapped-mask.tex"
        )
        let mismatchedPhysicalURL = directory.appendingPathComponent(
            "mismatched-physical-mask.tex"
        )
        let emptySpriteURL = directory.appendingPathComponent("empty-sprite-mask.tex")
        let fallbackPNGURL = directory.appendingPathComponent("fallback.png")
        let unparsedFallbackURL = directory.appendingPathComponent(
            "unparsed-fallback-mask.tex"
        )
        let croppedColorURL = directory.appendingPathComponent(
            "cropped-color.tex"
        )
        let nearestRepeatColorURL = directory.appendingPathComponent(
            "nearest-repeat-color.tex"
        )
        let clampBorderColorURL = directory.appendingPathComponent(
            "clamp-border-color.tex"
        )
        let unknownSamplerColorURL = directory.appendingPathComponent(
            "unknown-sampler-color.tex"
        )
        let normalizedColorURL = directory.appendingPathComponent(
            "normalized-color.tex"
        )
        let wrongOutputURL = directory.appendingPathComponent(
            "wrong-output-color.tex"
        )
        let mappedEmbeddedURL = directory.appendingPathComponent(
            "mapped-embedded-color.tex"
        )
        let mappedTexb3EmbeddedURL = directory.appendingPathComponent(
            "mapped-texb3-embedded-color.tex"
        )
        let oversizedTexb3MipChainURL = directory.appendingPathComponent(
            "oversized-texb3-mip-chain-color.tex"
        )
        let malformedTexb3EmbeddedURL = directory.appendingPathComponent(
            "malformed-texb3-embedded-color.tex"
        )
        let decodedMismatchTexb3URL = directory.appendingPathComponent(
            "decoded-mismatch-texb3-embedded-color.tex"
        )
        let lowerMipMismatchTexb3URL = directory.appendingPathComponent(
            "lower-mip-mismatch-texb3-embedded-color.tex"
        )
        let freeFormatMismatchTexb3URL = directory.appendingPathComponent(
            "free-format-mismatch-texb3-embedded-color.tex"
        )
        let mappedTexb3JPEGURL = directory.appendingPathComponent(
            "mapped-texb3-embedded-color-jpeg.tex"
        )
        let normalizedStraightAlbedoJPEGURL = directory.appendingPathComponent(
            "normalized-straight-albedo-jpeg.tex"
        )
        let normalizedStraightAlbedoPNGURL = directory.appendingPathComponent(
            "normalized-straight-albedo-png.tex"
        )
        let transparentStraightAlbedoPNGURL = directory.appendingPathComponent(
            "transparent-straight-albedo-png.tex"
        )
        let authoredStraightAlbedoMipsPNGURL = directory.appendingPathComponent(
            "mip-normalized-straight-albedo-png.tex"
        )
        let paddedStraightAlbedoJPEGURL = directory.appendingPathComponent(
            "padded-straight-albedo-jpeg.tex"
        )
        let mislabeledTexb4StraightAlbedoPNGURL = directory.appendingPathComponent(
            "mislabeled-texb4-straight-albedo-png.tex"
        )
        let mappedTexb2MipURL = directory.appendingPathComponent(
            "mapped-texb2-mip-color.tex"
        )
        try writeInputs(
            url: url,
            spriteURL: spriteURL,
            crossImageSpriteURL: crossImageSpriteURL,
            rotatedCrossImageSpriteURL: rotatedCrossImageSpriteURL,
            zeroMappedURL: zeroMappedURL,
            oversizedMappedURL: oversizedMappedURL,
            mismatchedPhysicalURL: mismatchedPhysicalURL,
            emptySpriteURL: emptySpriteURL,
            fallbackPNGURL: fallbackPNGURL,
            unparsedFallbackURL: unparsedFallbackURL,
            croppedColorURL: croppedColorURL,
            nearestRepeatColorURL: nearestRepeatColorURL,
            clampBorderColorURL: clampBorderColorURL,
            unknownSamplerColorURL: unknownSamplerColorURL,
            normalizedColorURL: normalizedColorURL,
            wrongOutputURL: wrongOutputURL,
            mappedEmbeddedURL: mappedEmbeddedURL,
            mappedTexb3EmbeddedURL: mappedTexb3EmbeddedURL,
            oversizedTexb3MipChainURL: oversizedTexb3MipChainURL,
            malformedTexb3EmbeddedURL: malformedTexb3EmbeddedURL,
            decodedMismatchTexb3URL: decodedMismatchTexb3URL,
            lowerMipMismatchTexb3URL: lowerMipMismatchTexb3URL,
            freeFormatMismatchTexb3URL: freeFormatMismatchTexb3URL,
            mappedTexb3JPEGURL: mappedTexb3JPEGURL,
            normalizedStraightAlbedoJPEGURL: normalizedStraightAlbedoJPEGURL,
            normalizedStraightAlbedoPNGURL: normalizedStraightAlbedoPNGURL,
            transparentStraightAlbedoPNGURL: transparentStraightAlbedoPNGURL,
            authoredStraightAlbedoMipsPNGURL: authoredStraightAlbedoMipsPNGURL,
            paddedStraightAlbedoJPEGURL: paddedStraightAlbedoJPEGURL,
            mislabeledTexb4StraightAlbedoPNGURL: mislabeledTexb4StraightAlbedoPNGURL,
            mappedTexb2MipURL: mappedTexb2MipURL
        )
        let loader = SceneTextureLoader()
        let overflowingRawURL = directory.appendingPathComponent("overflowing-raw.tex")
        try embeddedImageTex(
            textureWidth: .max, textureHeight: .max,
            imageWidth: 1, imageHeight: 1,
            payload: Data(repeating: 0, count: 4)
        ).write(to: overflowingRawURL)
        let overflowingRawRejected: Bool
        if case .decodeFailed = (try loader.load(from: overflowingRawURL, device: device)) {
            overflowingRawRejected = true
        } else {
            overflowingRawRejected = false
        }
        let spriteTextureLoader = SceneMultiImageSpriteTextureLoader()
        let (first, croppedColor, normalizedColor, metadataResult) = try candidateMetadataCases(
            device: device,
            loader: loader,
            url: url,
            missingURL: missingURL,
            spriteURL: spriteURL,
            zeroMappedURL: zeroMappedURL,
            oversizedMappedURL: oversizedMappedURL,
            mismatchedPhysicalURL: mismatchedPhysicalURL,
            emptySpriteURL: emptySpriteURL,
            unparsedFallbackURL: unparsedFallbackURL,
            croppedColorURL: croppedColorURL,
            normalizedColorURL: normalizedColorURL,
            wrongOutputURL: wrongOutputURL
        )
        let (directTransparent, uploadResult) = try embeddedUploadCases(
            device: device,
            loader: loader,
            directory: directory,
            normalizedColorURL: normalizedColorURL,
            mappedEmbeddedURL: mappedEmbeddedURL,
            mappedTexb3EmbeddedURL: mappedTexb3EmbeddedURL,
            oversizedTexb3MipChainURL: oversizedTexb3MipChainURL,
            malformedTexb3EmbeddedURL: malformedTexb3EmbeddedURL,
            decodedMismatchTexb3URL: decodedMismatchTexb3URL,
            lowerMipMismatchTexb3URL: lowerMipMismatchTexb3URL,
            freeFormatMismatchTexb3URL: freeFormatMismatchTexb3URL,
            mappedTexb3JPEGURL: mappedTexb3JPEGURL,
            normalizedStraightAlbedoJPEGURL: normalizedStraightAlbedoJPEGURL,
            normalizedStraightAlbedoPNGURL: normalizedStraightAlbedoPNGURL,
            transparentStraightAlbedoPNGURL: transparentStraightAlbedoPNGURL,
            authoredStraightAlbedoMipsPNGURL: authoredStraightAlbedoMipsPNGURL,
            paddedStraightAlbedoJPEGURL: paddedStraightAlbedoJPEGURL,
            mislabeledTexb4StraightAlbedoPNGURL: mislabeledTexb4StraightAlbedoPNGURL,
            mappedTexb2MipURL: mappedTexb2MipURL
        )
        let baseResult = try baseAndSpriteCases(
            device: device,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            imageLayerLibrary: imageLayerLibrary,
            directory: directory,
            url: url,
            spriteURL: spriteURL,
            crossImageSpriteURL: crossImageSpriteURL,
            rotatedCrossImageSpriteURL: rotatedCrossImageSpriteURL,
            mismatchedPhysicalURL: mismatchedPhysicalURL,
            fallbackPNGURL: fallbackPNGURL,
            unparsedFallbackURL: unparsedFallbackURL,
            croppedColorURL: croppedColorURL,
            nearestRepeatColorURL: nearestRepeatColorURL,
            clampBorderColorURL: clampBorderColorURL,
            unknownSamplerColorURL: unknownSamplerColorURL
        )
        let uvResult = slotAndUVMetadataCases(
            first: first,
            croppedColor: croppedColor,
            normalizedColor: normalizedColor
        )
        let revisionResult = try sourceRevisionCases(
            device: device,
            loader: loader,
            url: url,
            first: first
        )
        var result: [String: Any] = [
            "overflowingRawRejected": overflowingRawRejected,
            "available": true,
            "directTransparentPixel": try readFirstPixel(
                texture: directTransparent.texture, device: device),
        ]
        result.merge(metadataResult) { _, new in new }
        result.merge(uploadResult) { _, new in new }
        result.merge(baseResult) { _, new in new }
        result.merge(uvResult) { _, new in new }
        result.merge(revisionResult) { _, new in new }
        print(String(
            decoding: try JSONSerialization.data(
                withJSONObject: result,
                options: [.sortedKeys]
            ),
            as: UTF8.self
        ))
    }
}
