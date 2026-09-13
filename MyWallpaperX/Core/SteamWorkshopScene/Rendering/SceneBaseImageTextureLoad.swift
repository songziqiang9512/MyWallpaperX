import CoreGraphics
import Foundation
import Metal

struct SceneBaseImageTextureSnapshot {
    let textures: [Int: MTLTexture]
    let geometryProducts: [Int: SceneGeometryProduct]
    let explicitLayerSources: [Int: SceneTextureProviderPublication]
    private let layerSourcePublications: [Int: SceneLayerSourcePublication]
    private let candidates: [Int: SceneTextureCandidate]
    private let pendingLayerSourceIDs: Set<Int>

    init(
        textures: [Int: MTLTexture],
        geometryProducts: [Int: SceneGeometryProduct] = [:],
        explicitLayerSources: [Int: SceneTextureProviderPublication] = [:],
        layerSourcePublications: [Int: SceneLayerSourcePublication] = [:],
        candidates: [Int: SceneTextureCandidate],
        pendingLayerSourceIDs: Set<Int> = []
    ) {
        var validatedTextures = textures
        var validatedExplicitLayerSources: [Int: SceneTextureProviderPublication] = [:]
        var validatedLayerSources: [Int: SceneLayerSourcePublication] = [:]
        let atomicLayerIDs = Set(layerSourcePublications.keys)
        for (layerID, publication) in explicitLayerSources
            where !atomicLayerIDs.contains(layerID)
        {
            guard let texture = textures[layerID],
                  texture === publication.texture,
                  publication.requestIdentity == .layerSource(layerID),
                  SceneLayerSourcePublication.supportsDirectTextureLane(
                      layerID: layerID,
                      publication: publication
                  )
            else {
                validatedTextures[layerID] = nil
                continue
            }
            // Existing direct-video publications intentionally carry
            // unresolved color metadata. Preserve their texture lane; typed
            // registry/material lookup remains incomplete for that metadata.
            validatedExplicitLayerSources[layerID] = publication
        }
        for (layerID, layerSource) in layerSourcePublications {
            guard let texture = textures[layerID],
                  layerSource.isComplete(layerID: layerID, matching: texture)
            else {
                validatedTextures[layerID] = nil
                validatedExplicitLayerSources[layerID] = nil
                continue
            }
            validatedLayerSources[layerID] = layerSource
            validatedExplicitLayerSources[layerID] = layerSource.publication
        }
        self.textures = validatedTextures
        self.geometryProducts = geometryProducts
        self.explicitLayerSources = validatedExplicitLayerSources
        self.layerSourcePublications = validatedLayerSources
        var validatedCandidates = candidates.filter { layerID, candidate in
            validatedTextures[layerID] === candidate.texture
        }
        for (layerID, layerSource) in validatedLayerSources {
            validatedCandidates[layerID] = layerSource.publication.candidate
        }
        self.candidates = validatedCandidates
        self.pendingLayerSourceIDs = pendingLayerSourceIDs.subtracting(
            validatedLayerSources.keys
        )
    }

    subscript(layerID: Int) -> MTLTexture? {
        textures[layerID]
    }

    func candidate(
        for layerID: Int,
        matching texture: MTLTexture
    ) -> SceneTextureCandidate? {
        guard let candidate = candidates[layerID],
              candidate.texture === texture
        else {
            return nil
        }
        return candidate
    }

    func explicitLayerSourcePublication(
        for layerID: Int,
        matching texture: MTLTexture
    ) -> SceneTextureProviderPublication? {
        guard let publication = explicitLayerSources[layerID],
              publication.texture === texture,
              publication.requestIdentity == .layerSource(layerID),
              publication.isComplete
        else {
            return nil
        }
        return publication
    }

    func layerSourceRenderSize(for layerID: Int) -> [Float]? {
        guard let texture = textures[layerID],
              let layerSource = layerSourcePublications[layerID],
              layerSource.isComplete(layerID: layerID, matching: texture)
        else {
            return nil
        }
        return layerSource.renderSizeWH
    }

    func layerSourceEffectRenderSize(for layerID: Int) -> [Float]? {
        guard let texture = textures[layerID],
              let layerSource = layerSourcePublications[layerID],
              layerSource.isComplete(layerID: layerID, matching: texture) else {
            return nil
        }
        return layerSource.effectRenderSizeWH ?? layerSource.renderSizeWH
    }

    func isLayerSourcePending(_ layerID: Int) -> Bool {
        pendingLayerSourceIDs.contains(layerID)
    }
}

struct SceneBaseImageTextureStore {
    private(set) var textures: [Int: MTLTexture] = [:]
    private(set) var geometryProducts: [Int: SceneGeometryProduct] = [:]
    private(set) var candidates: [Int: SceneTextureCandidate] = [:]
    private(set) var publications: [Int: SceneTextureProviderPublication] = [:]
    private var contentGeneration: UInt64 = 0

    subscript(layerID: Int) -> MTLTexture? {
        get { textures[layerID] }
        set {
            textures[layerID] = newValue
            candidates[layerID] = nil
            publications[layerID] = nil
            geometryProducts[layerID] = nil
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
        geometryProducts[layerID] = nil
    }

    /// Installs the atlas and geometry atomically. The candidate retains only
    /// the atlas sampling contract used by source capture. The atlas is not a
    /// completed layer-source publication because only a mesh draw composes it.
    mutating func setPuppetGeometry(
        _ product: SceneGeometryProduct,
        samplingAtlas: MTLTexture,
        samplingCandidate: SceneTextureCandidate?,
        layerID: Int
    ) {
        textures[layerID] = samplingAtlas
        geometryProducts[layerID] = product
        candidates[layerID] = samplingCandidate.flatMap {
            $0.texture === samplingAtlas ? $0 : nil
        }
        publications[layerID] = nil
    }

    mutating func merge(_ incoming: [Int: MTLTexture]) {
        textures.merge(incoming) { _, value in value }
        for layerID in incoming.keys {
            candidates[layerID] = nil
            publications[layerID] = nil
            geometryProducts[layerID] = nil
        }
    }

    func snapshot(
        textures: [Int: MTLTexture],
        explicitLayerSources: [Int: SceneTextureProviderPublication] = [:],
        layerSourcePublications: [Int: SceneLayerSourcePublication] = [:],
        pendingLayerSourceIDs: Set<Int> = []
    ) -> SceneBaseImageTextureSnapshot {
        var combinedPublications = publications.filter { layerID, publication in
            textures[layerID] === publication.texture
        }
        combinedPublications.merge(explicitLayerSources) { _, replacement in
            replacement
        }
        var combinedLayerSources: [Int: SceneLayerSourcePublication] = [:]
        combinedLayerSources.merge(layerSourcePublications) { _, replacement in
            replacement
        }
        return SceneBaseImageTextureSnapshot(
            textures: textures,
            geometryProducts: geometryProducts.filter { textures[$0.key] != nil },
            explicitLayerSources: combinedPublications,
            layerSourcePublications: combinedLayerSources,
            candidates: candidates,
            pendingLayerSourceIDs: pendingLayerSourceIDs
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
        /// TEX sampler metadata remains available when specialized loading
        /// cannot publish a normal candidate (animated/sprite/puppet routes).
        let baseTextureSampling: SceneTextureSampling?
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
        case let .unsupportedFormat(ext):
            detail = "unsupported \(ext) (\(url.lastPathComponent))"
        case let .unsupportedTexFormat(code):
            detail = "unsupported .tex format \(code) (\(url.lastPathComponent))"
        case .texNoEmbeddedImage:
            detail = ".tex has no embedded JPEG/PNG (likely DXT)"
                + " — \(url.lastPathComponent)"
        case .texContainsVideoPayload:
            detail = ".tex is mp4 payload (animated/video)"
                + " — \(url.lastPathComponent)"
        case let .decodeFailed(message):
            detail = "decode failed (\(message))"
        case let .textureAllocationFailed(width, height):
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
        if let specializedLoadReason = specializedLoadReason(
            url: url,
            container: container,
            usesPuppet: usesPuppet
        ) {
            return specializedLoad(
                from: url,
                source: source,
                container: container,
                reason: specializedLoadReason,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        }
        return loadOrdinaryCandidate(
            from: url,
            loader: loader,
            device: device
        )
    }

    static func specializedLoadReason(
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

    private static func specializedLoad(
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
           let source, let container, container.imageCount > 1
        {
            switch spriteTextureLoader.playback(
                source: source,
                container: container,
                device: device,
                sourceIsCurrent: {
                    loader.sourceKey(for: url) == source
                }
            ) {
            case let .loaded(playback):
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
                    baseTextureSampling: SceneTextureSampling(texFlags: container.flags),
                    message: "; base color cross-image sprite playback"
                ))
            case let .unsupported(detail):
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
        case let .loaded(texture):
            return .loaded(Loaded(
                texture: texture,
                candidate: nil,
                animation: container.flatMap {
                    SceneSpriteAnimation(frames: $0.spriteFrames)
                },
                baseTextureSampling: container.map {
                    SceneTextureSampling(texFlags: $0.flags)
                },
                message: "; base color specialized authored load (\(reason))"
                    + crossImageFallbackMessage
            ))
        case let failure:
            return .failed(failure)
        }
    }
}
