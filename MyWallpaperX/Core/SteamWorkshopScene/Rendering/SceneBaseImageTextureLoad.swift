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
                  texture === publication.texture else {
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
            guard nextTextures[layerID] != nil else { continue }
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

    subscript(layerID: Int) -> MTLTexture? {
        get { textures[layerID] }
        set {
            textures[layerID] = newValue
            candidates[layerID] = nil
        }
    }

    mutating func set(
        _ texture: MTLTexture,
        candidate: SceneTextureCandidate?,
        layerID: Int
    ) {
        textures[layerID] = texture
        candidates[layerID] = candidate.flatMap {
            $0.texture === texture ? $0 : nil
        }
    }

    mutating func merge(_ incoming: [Int: MTLTexture]) {
        textures.merge(incoming) { _, value in value }
        for layerID in incoming.keys {
            candidates[layerID] = nil
        }
    }

    func snapshot(
        textures: [Int: MTLTexture],
        explicitLayerSources: [Int: SceneTextureProviderPublication] = [:]
    ) -> SceneBaseImageTextureSnapshot {
        SceneBaseImageTextureSnapshot(
            textures: textures,
            explicitLayerSources: explicitLayerSources,
            candidates: candidates
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
        textureAnimationPlan: SceneTextureAnimationPlaybackPlan? = nil,
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
                textureAnimationPlan: textureAnimationPlan,
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
        textureAnimationPlan: SceneTextureAnimationPlaybackPlan?,
        device: MTLDevice
    ) -> Outcome {
        var crossImageFallbackMessage = ""
        if reason == "multi-image TEX",
           let source, let container, container.imageCount > 1 {
            switch spriteTextureLoader.playback(
                source: source,
                container: container,
                device: device,
                playbackPlan: textureAnimationPlan,
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
                        + (textureAnimationPlan == nil
                            ? "" : "; bounded texture-animation lifecycle")
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
                    SceneSpriteAnimation(
                        frames: $0.spriteFrames,
                        playbackPlan: textureAnimationPlan
                    )
                },
                message: "; base color legacy route (\(reason))"
                    + crossImageFallbackMessage
                    + (textureAnimationPlan == nil
                        ? "" : "; bounded texture-animation lifecycle")
            ))
        case let failure:
            return .failed(failure)
        }
    }
}
