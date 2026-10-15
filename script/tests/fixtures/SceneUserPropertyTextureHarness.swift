
import CoreGraphics
import Foundation
import ImageIO
import Metal

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        isWebM: Bool = false,
        cacheDirectory: URL,
        device: MTLDevice
    ) {
        return nil
    }
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingDirectory }
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }

        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let pngURL = directory.appendingPathComponent("cover.png")
        let jpegURL = directory.appendingPathComponent("photo.jpeg")
        let jpgURL = directory.appendingPathComponent("photo-alias.jpg")
        let invalidURL = directory.appendingPathComponent("broken.png")
        let unsupportedURL = directory.appendingPathComponent("disguised.gif")
        try writeStraightPNG(pngURL)
        try writeImage(jpegURL, type: "public.jpeg")
        try Data(contentsOf: jpegURL).write(to: jpgURL)
        try Data("not an image".utf8).write(to: invalidURL)
        try Data(contentsOf: pngURL).write(to: unsupportedURL)
        let embeddedTexURL = directory.appendingPathComponent("embedded.tex")
        try embeddedImageTex(
            width: 2,
            height: 1,
            payload: try Data(contentsOf: pngURL)
        ).write(to: embeddedTexURL)

        let loader = SceneUserPropertyTextureLoader()
        let absentIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "not-selected",
            purpose: .premultipliedColor
        )!
        let maskIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "png",
            purpose: .mask
        )!
        let brokenFlowIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "broken",
            purpose: .flow
        )!
        let jpegStraightIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "jpeg",
            purpose: .straightAlbedo
        )!
        let pngStraightIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "png",
            purpose: .straightAlbedo
        )!
        let pngPreservedIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "png",
            purpose: .preservedChannels
        )!
        let result = loader.load(
            urlsByPropertyKey: [
                "png": pngURL,
                "jpeg": jpegURL,
                "jpg": jpgURL,
                "broken": invalidURL,
                "unsupported": unsupportedURL,
            ],
            requestedIdentities: [
                absentIdentity, maskIdentity, brokenFlowIdentity,
                jpegStraightIdentity, pngStraightIdentity,
                pngPreservedIdentity,
            ],
            device: device
        )
        let embeddedTexLoader = SceneTextureLoader()
        let embeddedTexColor = embeddedTexLoader.load(
            from: embeddedTexURL,
            purpose: .premultipliedColor,
            device: device
        )
        let embeddedTexPreserved = embeddedTexLoader.load(
            from: embeddedTexURL,
            purpose: .preservedChannels,
            device: device
        )
        let embeddedTexDifferentPurpose: Bool
        if case let .loaded(colorTexture) = embeddedTexColor,
           case let .loaded(preservedTexture) = embeddedTexPreserved {
            embeddedTexDifferentPurpose = colorTexture !== preservedTexture
        } else {
            embeddedTexDifferentPurpose = false
        }
        let embeddedTexDecodeAttempts = embeddedTexLoader.texEmbeddedImageDecodeAttemptCount
        let launchUploadQueue = SceneTextureUploadCommandQueue()
        _ = SceneTextureLoader(uploadCommandQueue: launchUploadQueue).load(
            from: pngURL,
            device: device
        )
        _ = SceneTextureLoader(uploadCommandQueue: launchUploadQueue).load(
            from: jpegURL,
            device: device
        )
        let launchUploadQueueAttempts = launchUploadQueue.creationAttemptCount
        let decodeBudget = SceneTextureDecodeCacheBudget(maximumBytes: 1_024)
        let admittedDecodeLoader = SceneTextureLoader(
            decodeCacheBudget: decodeBudget
        )
        _ = admittedDecodeLoader.load(from: pngURL, device: device)
        let admittedDecodeBytes = decodeBudget.residentBytes
        decodeBudget.updateMaximumBytes(0)
        let deniedDecodeLoader = SceneTextureLoader(
            decodeCacheBudget: decodeBudget
        )
        let deniedColorOutcome = deniedDecodeLoader.load(
            from: jpegURL,
            purpose: .premultipliedColor,
            device: device
        )
        let deniedPreservedOutcome = deniedDecodeLoader.load(
            from: jpegURL,
            purpose: .preservedChannels,
            device: device
        )
        guard case .loaded = deniedColorOutcome,
              case .loaded = deniedPreservedOutcome else {
            throw HarnessError.textureRead
        }
        let deniedDecodeAttempts = deniedDecodeLoader.directImageDecodeAttemptCount
        let decodeBudgetRejectedAdmissions = decodeBudget.rejectionCount
        let decodeBudgetBytesAfterDenial = decodeBudget.residentBytes
        let releasedDecodeBudget = SceneTextureDecodeCacheBudget(maximumBytes: 1_024)
        var leasedDecodeBytes = 0
        do {
            let leasedLoader = SceneTextureLoader(
                decodeCacheBudget: releasedDecodeBudget
            )
            _ = leasedLoader.load(from: pngURL, device: device)
            leasedDecodeBytes = releasedDecodeBudget.residentBytes
        }
        let releasedDecodeBytes = releasedDecodeBudget.residentBytes
        let sharedLoader = SceneTextureLoader()
        let embeddedDataOutcome = SceneTextureMipUploader.uploadEmbeddedDataImages(
            [.init(width: 2, height: 1, data: try Data(contentsOf: pngURL))],
            purpose: .preservedChannels,
            device: device
        )
        guard let embeddedDataOutcome else { throw HarnessError.textureRead }
        let embeddedStraightAlbedoOutcome = SceneTextureMipUploader.uploadEmbeddedDataImages(
            [.init(width: 3, height: 2, data: try Data(contentsOf: jpegURL))],
            purpose: .straightAlbedo,
            device: device
        )
        guard let embeddedStraightAlbedoOutcome else {
            throw HarnessError.textureRead
        }
        let premultipliedDataRejected = SceneImageTextureUploader.rgbaData(
            image: try makePremultipliedImage(),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ) == nil
        let resizedDataRejected = SceneImageTextureUploader.rgbaData(
            image: try makeStraightImage(),
            width: 2,
            height: 1,
            purpose: .preservedChannels
        ) == nil
        let decodedDataRejected = SceneImageTextureUploader.rgbaData(
            image: try makeImage(
                pixels: [231, 17, 149, 0],
                alphaInfo: .last,
                decode: [1, 0, 1, 0, 1, 0]
            ),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ) == nil
        guard let resizedOpaqueAlbedo = SceneImageTextureUploader.rgbaData(
            image: try makeOpaqueImage(),
            width: 1,
            height: 1,
            purpose: .straightAlbedo
        ) else {
            throw HarnessError.textureRead
        }
        let resizedTransparentAlbedoRejected = SceneImageTextureUploader.rgbaData(
            image: try makeStraightImage(),
            width: 2,
            height: 1,
            purpose: .straightAlbedo
        ) == nil
        let premultipliedAlbedoRejected = SceneImageTextureUploader.rgbaData(
            image: try makePremultipliedImage(),
            width: 1,
            height: 1,
            purpose: .straightAlbedo
        ) == nil
        guard let explicitBigData = SceneImageTextureUploader.rgbaData(
            image: try makeImage(
                pixels: [231, 17, 149, 0],
                alphaInfo: .last,
                byteOrder: .byteOrder32Big
            ),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ), let explicitLittleData = SceneImageTextureUploader.rgbaData(
            image: try makeImage(
                pixels: [149, 17, 231, 0],
                alphaInfo: .first,
                byteOrder: .byteOrder32Little
            ),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ) else {
            throw HarnessError.textureRead
        }
        let encodedPreserved: MTLTexture
        switch SceneImageTextureUploader.uploadEncodedPreservedChannels(
            try Data(contentsOf: pngURL),
            device: device
        ) {
        case let .success(texture): encodedPreserved = texture
        case .failure: throw HarnessError.textureRead
        }
        let encodedOversize: MTLTexture
        switch SceneImageTextureUploader.uploadEncodedPreservedChannels(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAQEAAAABCAYAAADemxtJAAAAFElEQVR4nGN4LjiVYRSP4lE8cjEASvyOnSmE3ZQAAAAASUVORK5CYII=")!, device: device
        ) {
        case let .success(texture): encodedOversize = texture
        case .failure: throw HarnessError.textureRead
        }
        let encodedSourceLimitRejected: Bool
        if case .failure(.dimensionsOutOfRange(4097, 1, 4096)) =
            SceneImageTextureUploader.uploadEncodedPreservedChannels(
                Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAEAEAAAABCAYAAACx4wBCAAAALUlEQVR4nO3DMQ0AAAgDsFlAPBpnAxk8bdJ0Nqqqqqqqqqqqqqqqqqqqqur/AwVO0vavODdVAAAAAElFTkSuQmCC")!, device: device
            ) { encodedSourceLimitRejected = true } else {
                encodedSourceLimitRejected = false
            }
        let encodedOrientationRejected: Bool
        if case .failure(.nonIdentityOrientation(6)) =
            SceneImageTextureUploader.uploadEncodedPreservedChannels(
                try encodedImage(orientation: 6), device: device
            ) { encodedOrientationRejected = true } else { encodedOrientationRejected = false }
        let encodedPremultipliedRejected: Bool
        if case .failure(.premultipliedPixelLayout) =
            SceneImageTextureUploader.uploadEncodedPreservedChannels(
                try encodedImage(alphaInfo: .premultipliedLast, type: "public.tiff"),
                device: device
            ) { encodedPremultipliedRejected = true } else { encodedPremultipliedRejected = false }
        let encodedOpaque: MTLTexture
        switch SceneImageTextureUploader.uploadEncodedPreservedChannels(
            try Data(contentsOf: jpegURL), device: device
        ) {
        case let .success(texture): encodedOpaque = texture
        case .failure: throw HarnessError.textureRead
        }
        let firstCached = sharedLoader.load(from: pngURL, device: device)
        let secondCached = sharedLoader.load(from: pngURL, device: device)
        let firstPreserved = sharedLoader.load(
            from: pngURL,
            purpose: .preservedChannels,
            device: device
        )
        let secondPreserved = sharedLoader.load(
            from: pngURL,
            purpose: .preservedChannels,
            device: device
        )
        let sharedDecodeAttempts = sharedLoader.directImageDecodeAttemptCount
        let sharedUploadQueueAttempts = sharedLoader.uploadCommandQueue
            .creationAttemptCount
        let reusedTexture: Bool
        let reusedPreservedTexture: Bool
        let differentPurposeTexture: Bool
        if case let .loaded(first) = firstCached,
           case let .loaded(second) = secondCached,
           case let .loaded(preservedFirst) = firstPreserved,
           case let .loaded(preservedSecond) = secondPreserved {
            reusedTexture = first === second
            reusedPreservedTexture = preservedFirst === preservedSecond
            differentPurposeTexture = first !== preservedFirst
        } else {
            reusedTexture = false
            reusedPreservedTexture = false
            differentPurposeTexture = false
        }
        let reversedLoader = SceneTextureLoader()
        let reversedPreserved = reversedLoader.load(
            from: pngURL,
            purpose: .preservedChannels,
            device: device
        )
        let reversedColor = reversedLoader.load(from: pngURL, device: device)
        try Data("changed user image".utf8).write(to: pngURL)
        let changedFileInvalidatedCache: Bool
        if case .decodeFailed = sharedLoader.load(from: pngURL, device: device) {
            changedFileInvalidatedCache = true
        } else {
            changedFileInvalidatedCache = false
        }
        let retry = loader.load(
            urlsByPropertyKey: ["png": invalidURL],
            device: device
        )
        let empty = loader.load(urlsByPropertyKey: [:], device: device)
        let dimensions = result.textures.mapValues { ["width": $0.width, "height": $0.height] }
        let candidate = result.textureCandidates["png"]
        let preservedDimensions = result.preservedTextures.mapValues {
            ["width": $0.width, "height": $0.height]
        }
        let straightAlbedoDimensions = result.straightAlbedoTextures.mapValues {
            ["width": $0.width, "height": $0.height]
        }
        let publicationTokens = result.publications.keys.map(\.reportToken).sorted()
        let publicationAtomsComplete = result.publications.allSatisfy {
            identity, publication in
            publication.isComplete
                && identity.purpose == publication.candidate.purpose
                && publication.requestIdentity
                    == .materialUserProperty(identity)
                && publication.contentGeneration == 1
        }
        let publicationTexturesMatchPurpose = result.publications.allSatisfy {
            identity, publication in
            switch identity.purpose {
            case .premultipliedColor:
                return result.textures[identity.propertyKey] === publication.texture
            case .straightAlbedo:
                return result.straightAlbedoTextures[identity.propertyKey]
                    === publication.texture
            case .preservedChannels:
                return result.preservedTextures[identity.propertyKey] === publication.texture
            default:
                guard case let .ready(statePublication) =
                        result.providerStates[identity] else { return false }
                return statePublication.texture === publication.texture
            }
        }
        let unavailableTokens = result.providerStates.compactMap {
            identity, state -> String? in
            guard case .unavailable = state else { return nil }
            return identity.reportToken
        }.sorted()
        let absentTokens = result.providerStates.compactMap {
            identity, state -> String? in
            guard case .absent = state else { return nil }
            return identity.reportToken
        }.sorted()
        let jpegLayout = try jpegDisplayLayoutChecks(directory: directory, device: device)
        let payload: [String: Any] = [
            "jpegLayout": jpegLayout,
            "loadedKeys": result.textures.keys.sorted(),
            "candidateKeys": result.textureCandidates.keys.sorted(),
            "candidateSharesTexture": candidate?.texture === result.textures["png"],
            "candidatePurpose": candidate?.purpose == .premultipliedColor,
            "candidatePhysicalMapped": [
                candidate?.physicalSize.width ?? -1,
                candidate?.physicalSize.height ?? -1,
                candidate?.mappedSize.width ?? -1,
                candidate?.mappedSize.height ?? -1,
            ],
            "preservedLoadedKeys": result.preservedTextures.keys.sorted(),
            "straightAlbedoLoadedKeys": result.straightAlbedoTextures.keys.sorted(),
            "dimensions": dimensions,
            "preservedDimensions": preservedDimensions,
            "straightAlbedoDimensions": straightAlbedoDimensions,
            "publicationTokens": publicationTokens,
            "publicationAtomsComplete": publicationAtomsComplete,
            "publicationTexturesMatchPurpose": publicationTexturesMatchPurpose,
            "unavailableTokens": unavailableTokens,
            "absentTokens": absentTokens,
            "colorPixels": try pixels(result.textures["png"]),
            "preservedPixels": try pixels(result.preservedTextures["png"]),
            "reversedColorPixels": try pixels(reversedColor),
            "reversedPreservedPixels": try pixels(reversedPreserved),
            "embeddedDataPixels": try pixels(embeddedDataOutcome),
            "embeddedStraightAlbedoPixels": try pixels(embeddedStraightAlbedoOutcome),
            "embeddedTexDifferentPurpose": embeddedTexDifferentPurpose,
            "embeddedTexDecodeAttempts": embeddedTexDecodeAttempts,
            "launchUploadQueueAttempts": launchUploadQueueAttempts,
            "admittedDecodeBytes": admittedDecodeBytes,
            "deniedDecodeAttempts": deniedDecodeAttempts,
            "decodeBudgetRejectedAdmissions": decodeBudgetRejectedAdmissions,
            "decodeBudgetBytesAfterDenial": decodeBudgetBytesAfterDenial,
            "leasedDecodeBytes": leasedDecodeBytes,
            "releasedDecodeBytes": releasedDecodeBytes,
            "reportLines": result.reportLines,
            "retryLoadedKeys": retry.textures.keys.sorted(),
            "retryCandidateKeys": retry.textureCandidates.keys.sorted(),
            "retryPublicationTokens": retry.publications.keys.map(\.reportToken).sorted(),
            "retryUnavailableTokens": retry.providerStates.compactMap {
                identity, state -> String? in
                guard case .unavailable = state else { return nil }
                return identity.reportToken
            }.sorted(),
            "retryPreservedLoadedKeys": retry.preservedTextures.keys.sorted(),
            "retryReportLines": retry.reportLines,
            "emptyLoadedKeys": empty.textures.keys.sorted(),
            "emptyCandidateKeys": empty.textureCandidates.keys.sorted(),
            "emptyPreservedLoadedKeys": empty.preservedTextures.keys.sorted(),
            "emptyStraightAlbedoLoadedKeys": empty.straightAlbedoTextures.keys.sorted(),
            "emptyPublicationTokens": empty.publications.keys.map(\.reportToken).sorted(),
            "emptyProviderStateCount": empty.providerStates.count,
            "emptyReportLines": empty.reportLines,
            "reusedTexture": reusedTexture,
            "reusedPreservedTexture": reusedPreservedTexture,
            "differentPurposeTexture": differentPurposeTexture,
            "sharedDecodeAttempts": sharedDecodeAttempts,
            "sharedUploadQueueAttempts": sharedUploadQueueAttempts,
            "changedFileInvalidatedCache": changedFileInvalidatedCache,
            "premultipliedDataRejected": premultipliedDataRejected,
            "resizedDataRejected": resizedDataRejected,
            "decodedDataRejected": decodedDataRejected,
            "resizedOpaqueAlbedo": [UInt8](resizedOpaqueAlbedo),
            "resizedTransparentAlbedoRejected": resizedTransparentAlbedoRejected,
            "premultipliedAlbedoRejected": premultipliedAlbedoRejected,
            "explicitBigPixels": [UInt8](explicitBigData),
            "explicitLittlePixels": [UInt8](explicitLittleData),
            "encodedPreservedPixels": try pixels(encodedPreserved),
            "encodedOversizeDimensions": [
                encodedOversize.width, encodedOversize.height,
            ],
            "encodedOversizePixels": try pixels(encodedOversize),
            "encodedSourceLimitRejected": encodedSourceLimitRejected,
            "encodedOrientationRejected": encodedOrientationRejected,
            "encodedPremultipliedRejected": encodedPremultipliedRejected,
            "encodedOpaquePixels": try pixels(encodedOpaque),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func jpegDisplayLayoutChecks(directory: URL, device: MTLDevice) throws -> [String: Any] {
        // Same asymmetric source and corner classes as the embedded all-eight gate.
        let width = 48, height = 32
        let colors: [[UInt8]] = [[240, 10, 10, 255], [10, 240, 10, 255],
                                [10, 10, 240, 255], [240, 240, 10, 255]]
        let bytes = (0..<height).flatMap { y in
            (0..<width).flatMap { x in colors[(y >= height / 2 ? 2 : 0) + (x >= width / 2 ? 1 : 0)] }
        }
        let image = CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        func corners(_ texture: MTLTexture) throws -> [Int] {
            let rgba = try pixels(texture)
            return [(1, 1), (3, 1), (1, 3), (3, 3)].map { x, y in
                let offset = ((y * texture.height / 4) * texture.width + x * texture.width / 4) * 4
                return colors.indices.min { a, b in
                    func distance(_ index: Int) -> Int {
                        (0..<3).reduce(0) { $0 + abs(Int(rgba[offset + $1]) - Int(colors[index][$1])) }
                    }
                    return distance(a) < distance(b)
                }!
            }
        }
        var rows: [[String: Any]] = []
        for number in 0...9 {
            let orientation = number == 9 ? 6 : number
            let data = try encodedImage(orientation: orientation == 0 ? nil : orientation,
                type: "public.jpeg", sourceImage: image)
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
            guard ((metadata[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1)
                    == (orientation == 0 ? 1 : orientation) else { throw HarnessError.imageWrite }
            let url = directory.appendingPathComponent(number == 9 ? "renamed-resource.jpeg" : "orientation-\(number).jpg")
            try data.write(to: url)
            let key = number == 9 ? "renamed-property" : "image-input"
            let identities: Set<SceneUserPropertyTextureIdentity> = [
                .init(propertyKey: key, purpose: .premultipliedColor)!,
                .init(propertyKey: key, purpose: .straightAlbedo)!]
            let loaded = SceneUserPropertyTextureLoader().load(urlsByPropertyKey: [key: url],
                requestedIdentities: identities, device: device)
            let headerLoader = SceneTextureLoader()
            guard let color = loaded.textures[key], let straight = loaded.straightAlbedoTextures[key],
                  let candidate = loaded.textureCandidates[key], let identity = headerLoader.sourceKey(for: url),
                  let natural = headerLoader.preparedNaturalImageSize(from: url, source: identity),
                  let dataExtent = SceneImageTextureUploader.sourceImageSize(data),
                  let embeddedExtent = SceneTextureMipUploader.embeddedImagePixelSize(data),
                  let embeddedImages = SceneTextureMipUploader.decodeEmbeddedImages([data]),
                  case let .loaded(embedded)? = SceneTextureMipUploader.uploadEmbeddedDataImages(
                    embeddedImages, purpose: .straightAlbedo, device: device) else { throw HarnessError.textureRead }
            var strictRejectsNonidentity = true
            if orientation > 1 {
                if case let .failure(.nonIdentityOrientation(value)) =
                    SceneImageTextureUploader.uploadEncodedPreservedChannels(data, device: device) {
                    strictRejectsNonidentity = value == orientation
                } else { strictRejectsNonidentity = false }
            }
            rows.append(["case": number, "orientation": orientation,
                "colorSize": [color.width, color.height], "straightSize": [straight.width, straight.height],
                "naturalSize": [natural.width, natural.height], "dataExtent": [dataExtent.width, dataExtent.height],
                "embeddedExtent": [embeddedExtent.width, embeddedExtent.height],
                "embeddedSize": [embedded.width, embedded.height],
                "candidateExtent": [candidate.physicalSize.width, candidate.physicalSize.height,
                    candidate.mappedSize.width, candidate.mappedSize.height],
                "colorCorners": try corners(color), "straightCorners": try corners(straight),
                "embeddedCorners": try corners(embedded), "complete": loaded.hasCompletePublications(for: identities),
                "strictRejectsNonidentity": strictRejectsNonidentity])
        }
        // Truncated EXIF APP1, with no pixel extent/header. Qualify the actual
        // ImageIO input; invalid orientation values can be normalized to 1.
        let invalid = Data([0xFF, 0xD8, 0xFF, 0xE1, 0, 34, 69, 120, 105, 102, 0, 0])
        let invalidMetadata = CGImageSourceCreateWithData(invalid as CFData, nil).flatMap {
            CGImageSourceCopyPropertiesAtIndex($0, 0, nil)
        }
        guard invalidMetadata == nil else { throw HarnessError.imageWrite }
        let invalidURL = directory.appendingPathComponent("invalid-header.jpg")
        try invalid.write(to: invalidURL)
        let rejected = SceneUserPropertyTextureLoader().load(urlsByPropertyKey: ["invalid": invalidURL], device: device)
        let truncated = Data([0xFF, 0xD8, 0xFF])
        return ["rows": rows, "invalidMetadataRejected": rejected.textures.isEmpty && rejected.textureCandidates.isEmpty
            && SceneImageTextureUploader.sourceImageSize(from: invalidURL) == nil
            && SceneImageTextureUploader.sourceImageSize(invalid) == nil
            && SceneImageTextureUploader.decodeSourceImage(invalid) == nil
            && SceneTextureMipUploader.embeddedImagePixelSize(invalid) == nil
            && SceneTextureMipUploader.decodeEmbeddedImages([invalid]) == nil,
            "truncatedMetadataRejected": SceneImageTextureUploader.sourceImageSize(truncated) == nil
                && SceneImageTextureUploader.decodeSourceImage(truncated) == nil]
    }

    private static func writeStraightPNG(_ url: URL) throws {
        // Fixed unassociated RGBA scanlines; no OS encoder can discard RGB at A=0.
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGN4LjiV4USKkQMAECYDLLTCd0EAAAAASUVORK5CYII=")!.write(to: url)
    }

    private static func writeImage(_ url: URL, type: String) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 12,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type as CFString,
            1,
            nil
           ) else {
            throw HarnessError.imageWrite
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
    }

    private static func embeddedImageTex(
        width: UInt32,
        height: UInt32,
        payload: Data
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(0)
        append(2)
        append(width)
        append(height)
        append(width)
        append(height)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(1)
        append(1)
        append(width)
        append(height)
        append(0)
        append(0)
        append(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private static func encodedImage(
        width: Int = 1,
        orientation: Int? = nil,
        alphaInfo: CGImageAlphaInfo = .last,
        type: String = "public.png",
        sourceImage: CGImage? = nil
    ) throws -> Data {
        var pixels = Data()
        pixels.reserveCapacity(width * 4)
        for _ in 0 ..< width {
            pixels.append(contentsOf: [231, 17, 149, 0])
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = sourceImage ?? CGImage(
                  width: width, height: 1, bitsPerComponent: 8,
                  bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { throw HarnessError.imageWrite }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type as CFString, 1, nil
        ) else { throw HarnessError.imageWrite }
        let properties = orientation.map {
            [kCGImagePropertyOrientation: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageWrite
        }
        return output as Data
    }

    private static func makePremultipliedImage() throws -> CGImage {
        try makeImage(
            pixels: [12, 8, 4, 16],
            alphaInfo: .premultipliedLast
        )
    }

    private static func makeStraightImage() throws -> CGImage {
        try makeImage(
            pixels: [231, 17, 149, 0],
            alphaInfo: .last
        )
    }

    private static func makeOpaqueImage() throws -> CGImage {
        guard let provider = CGDataProvider(data: Data([
            240, 80, 40, 0,
            40, 160, 220, 0,
        ]) as CFData),
              let image = CGImage(
                  width: 2,
                  height: 1,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw HarnessError.imageWrite
        }
        return image
    }

    private static func makeImage(
        pixels: [UInt8],
        alphaInfo: CGImageAlphaInfo,
        byteOrder: CGBitmapInfo = .byteOrderDefault,
        decode: [CGFloat]? = nil
    ) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: alphaInfo.rawValue | byteOrder.rawValue
                ),
                provider: provider,
                decode: decode,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw HarnessError.imageWrite
        }
        return image
    }

    private static func pixels(_ texture: MTLTexture?) throws -> [UInt8] {
        guard let texture else { throw HarnessError.textureRead }
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return bytes
    }

    private static func pixels(_ outcome: SceneTextureLoadOutcome) throws -> [UInt8] {
        guard case let .loaded(texture) = outcome else { throw HarnessError.textureRead }
        return try pixels(texture)
    }

    private enum HarnessError: Error {
        case missingDirectory
        case noMetal
        case imageWrite
        case textureRead
    }
}
