import Foundation
import Metal

struct SceneBaseImageTextureSnapshot {
    let textures: [Int: MTLTexture]
    let explicitLayerSources: [Int: SceneTextureProviderPublication]
    private let candidates: [Int: SceneTextureCandidate]

    init(
        textures: [Int: MTLTexture],
        explicitLayerSources: [Int: SceneTextureProviderPublication] = [:],
        candidates: [Int: SceneTextureCandidate]
    ) {
        var validatedTextures = textures
        var validatedPublications: [Int: SceneTextureProviderPublication] = [:]
        for (layerID, publication) in explicitLayerSources {
            guard let texture = textures[layerID],
                  texture === publication.texture,
                  publication.requestIdentity == .layerSource(layerID) else {
                validatedTextures[layerID] = nil
                continue
            }
            validatedPublications[layerID] = publication
        }
        self.textures = validatedTextures
        self.explicitLayerSources = validatedPublications
        self.candidates = candidates.filter { layerID, candidate in
            validatedTextures[layerID] === candidate.texture
        }
    }

    subscript(layerID: Int) -> MTLTexture? {
        textures[layerID]
    }

    func candidate(
        for layerID: Int,
        matching texture: MTLTexture
    ) -> SceneTextureCandidate? {
        guard let candidate = candidates[layerID],
              candidate.texture === texture else {
            return nil
        }
        return candidate
    }

    func replacingLayerSources(
        _ replacements: [Int: SceneTextureProviderPublication]
    ) -> SceneBaseImageTextureSnapshot {
        guard !replacements.isEmpty else { return self }
        var nextTextures = textures
        var nextPublications = explicitLayerSources
        for (layerID, publication) in replacements {
            guard nextTextures[layerID] != nil,
                  publication.requestIdentity == .layerSource(layerID) else { continue }
            nextTextures[layerID] = publication.texture
            nextPublications[layerID] = publication
        }
        return SceneBaseImageTextureSnapshot(
            textures: nextTextures,
            explicitLayerSources: nextPublications,
            candidates: candidates
        )
    }
}

struct SceneBaseImageTextureStore {
    private(set) var textures: [Int: MTLTexture] = [:]
    private(set) var candidates: [Int: SceneTextureCandidate] = [:]
    private(set) var publications: [Int: SceneTextureProviderPublication] = [:]
    private var contentGeneration: UInt64 = 0

    subscript(layerID: Int) -> MTLTexture? {
        get { textures[layerID] }
        set {
            textures[layerID] = newValue
            candidates[layerID] = nil
            publications[layerID] = nil
        }
    }

    mutating func set(
        _ texture: MTLTexture,
        candidate: SceneTextureCandidate?,
        layerID: Int
    ) {
        textures[layerID] = texture
        let matchingCandidate = candidate.flatMap {
            $0.texture === texture ? $0 : nil
        }
        candidates[layerID] = matchingCandidate
        contentGeneration &+= 1
        publications[layerID] = matchingCandidate.flatMap {
            Self.publication(
                for: $0,
                layerID: layerID,
                contentGeneration: contentGeneration
            )
        }
    }

    mutating func merge(_ incoming: [Int: MTLTexture]) {
        textures.merge(incoming) { _, value in value }
        for layerID in incoming.keys {
            candidates[layerID] = nil
            publications[layerID] = nil
        }
    }

    func snapshot(
        textures: [Int: MTLTexture],
        explicitLayerSources: [Int: SceneTextureProviderPublication] = [:]
    ) -> SceneBaseImageTextureSnapshot {
        var combinedPublications = publications.filter { layerID, publication in
            textures[layerID] === publication.texture
        }
        combinedPublications.merge(explicitLayerSources) { _, replacement in
            replacement
        }
        return SceneBaseImageTextureSnapshot(
            textures: textures,
            explicitLayerSources: combinedPublications,
            candidates: candidates
        )
    }

    private static func publication(
        for candidate: SceneTextureCandidate,
        layerID: Int,
        contentGeneration: UInt64
    ) -> SceneTextureProviderPublication? {
        return SceneTextureProviderPublication(
            requestIdentity: .layerSource(layerID),
            candidate: candidate,
            contentGeneration: contentGeneration
        )
    }
}

enum SceneBaseImageTextureLoad {
    struct ReportLayerIdentity {
        let id: Int
        let name: String
    }

    enum Outcome {
        case loaded(Loaded)
        case failed(SceneTextureLoadOutcome)
    }

    struct Loaded {
        let texture: MTLTexture
        let candidate: SceneTextureCandidate?
        let animation: SceneSpriteAnimation?
        let message: String
    }

    static func failureReportLine(
        _ failure: SceneTextureLoadOutcome,
        layer: ReportLayerIdentity,
        url: URL,
        placementSummary: String
    ) -> String {
        let detail: String
        switch failure {
        case .unsupportedFormat(let ext):
            detail = "unsupported \(ext) (\(url.lastPathComponent))"
        case .unsupportedTexFormat(let code):
            detail = "unsupported .tex format \(code) (\(url.lastPathComponent))"
        case .texNoEmbeddedImage:
            detail = ".tex has no embedded JPEG/PNG (likely DXT)"
                + " — \(url.lastPathComponent)"
        case .texContainsVideoPayload:
            detail = ".tex is mp4 payload (animated/video)"
                + " — \(url.lastPathComponent)"
        case .decodeFailed(let message):
            detail = "decode failed (\(message))"
        case .textureAllocationFailed(let width, let height):
            detail = "texture allocation failed at \(width)×\(height)"
        case .loaded:
            detail = "internal candidate route mismatch"
        }
        return "layer \(layer.id) \"\(layer.name)\":"
            + " \(detail); \(placementSummary)"
    }

    static func load(
        from url: URL,
        usesPuppet: Bool,
        loader: SceneTextureLoader,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        device: MTLDevice
    ) -> Outcome {
        let source = loader.sourceKey(for: url)
        let container = source.flatMap {
            loader.texContainer(from: url, source: $0)
        }
        if let legacyReason = legacyReason(
            url: url,
            container: container,
            usesPuppet: usesPuppet
        ) {
            return legacyLoad(
                from: url,
                source: source,
                container: container,
                reason: legacyReason,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        }
        switch loader.loadCandidate(
            from: url,
            purpose: .premultipliedColor,
            device: device
        ) {
        case .failed(let failure):
            return .failed(failure)
        case .loaded(let candidate):
            guard let scale = candidate.axisAlignedMappedUVScale(
                expectedPurpose: .premultipliedColor
            ) else {
                return .failed(.decodeFailed(
                    "base color candidate failed its final purpose/UV validation"
                ))
            }
            guard candidate.sampling == .linearClamp,
                  scale == SIMD2(repeating: 1),
                  candidate.pixelFormat == .rgba8Unorm,
                  candidate.texture.textureType == .type2D,
                  candidate.texture.sampleCount == 1,
                  candidate.texture.usage.contains(.shaderRead) else {
                return .loaded(Loaded(
                    texture: candidate.texture,
                    candidate: nil,
                    animation: nil,
                    message: "; base color legacy binding"
                        + " (unsupported candidate UV/sampler:"
                        + " \(candidate.diagnosticSummary))"
                ))
            }
            return .loaded(Loaded(
                texture: candidate.texture,
                candidate: candidate,
                animation: nil,
                message: "; base color candidate \(candidate.diagnosticSummary)"
            ))
        }
    }

    private static func legacyReason(
        url: URL,
        container: SceneTexContainer?,
        usesPuppet: Bool
    ) -> String? {
        if usesPuppet {
            return "puppet atlas"
        }
        guard url.pathExtension.lowercased() == "tex" else {
            return nil
        }
        guard let container else {
            return "unparsed TEX metadata"
        }
        if container.imageCount != 1 {
            return "multi-image TEX"
        }
        if container.isAnimated {
            return "animated TEX"
        }
        if !container.spriteFrames.isEmpty {
            return "sprite TEX"
        }
        return nil
    }

    private static func legacyLoad(
        from url: URL,
        source: SceneTextureLoader.SourceKey?,
        container: SceneTexContainer?,
        reason: String,
        loader: SceneTextureLoader,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        device: MTLDevice
    ) -> Outcome {
        var crossImageFallbackMessage = ""
        if reason == "multi-image TEX",
           let source, let container, container.imageCount > 1 {
            switch spriteTextureLoader.playback(
                source: source,
                container: container,
                device: device,
                sourceIsCurrent: {
                    loader.sourceKey(for: url) == source
                }
            ) {
            case .loaded(let playback):
                guard let animation = SceneSpriteAnimation(
                    frames: container.spriteFrames,
                    texturePlayback: playback
                ) else {
                    break
                }
                return .loaded(Loaded(
                    texture: playback.texture,
                    candidate: nil,
                    animation: animation,
                    message: "; base color cross-image sprite playback"
                ))
            case .unsupported(let detail):
                crossImageFallbackMessage =
                    "; cross-image sprite playback unavailable (\(detail))"
            }
        }
        guard let source else {
            return .failed(.decodeFailed(
                "file metadata unavailable: \(url.lastPathComponent)"
            ))
        }
        switch loader.load(
            from: url,
            source: source,
            purpose: .premultipliedColor,
            device: device
        ) {
        case .loaded(let texture):
            return .loaded(Loaded(
                texture: texture,
                candidate: nil,
                animation: container.flatMap {
                    SceneSpriteAnimation(frames: $0.spriteFrames)
                },
                message: "; base color legacy route (\(reason))"
                    + crossImageFallbackMessage
            ))
        case let failure:
            return .failed(failure)
        }
    }
}
