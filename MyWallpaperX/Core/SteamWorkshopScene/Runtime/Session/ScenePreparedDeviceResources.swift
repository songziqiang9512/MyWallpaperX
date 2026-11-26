import Foundation
import CoreGraphics
import Metal

nonisolated struct ScenePreparedDynamicImageResource {
    nonisolated enum Product {
        case image(SceneTextureCandidate)
        case video(source: SceneTextureLoader.SourceKey, file: SceneVideoOwnedFile, sizeWH: [Float])
    }

    let modelPath: String
    let product: Product
    /// Source image extent retained before texture normalization/downscaling.
    /// The same decode owner supplies TEX and direct-image native metadata.
    var naturalSizeWH: [Float]? = nil
    var puppetMeshPath: String? = nil
    var puppetPose: ScenePuppetLayerLoad.PreparedPose? = nil
    /// A model-default built-in recipe, never an authored layer instance.
    var lightingProfile: SceneBaseMaterialLightingProfile? = nil
    var imageMaterialRenderState: SceneMaterialRenderState? = nil

    var renderSizeWH: [Float] {
        switch product {
        case let .image(candidate):
            [Float(candidate.texture.width), Float(candidate.texture.height)]
        case let .video(_, _, sizeWH): sizeWH
        }
    }
}

nonisolated enum SceneDeferredBaseImageStatus: Equatable {
    case notDeferred
    case pending
    case loading
    case ready
    case failed(String)
}

/// Device-bound ordinary base images shared across AppKit surfaces. The same owner
/// prepares visible entries before activation and publishes dormant alternatives on demand.
/// Puppet models and atlases are shared; poses and GPU geometry remain surface-scoped.
final class ScenePreparedBaseImageResources {
    private let automaticMipProjection: SceneAutomaticTextureProjection?
    private var automaticMipTails: [SceneTextureLoader.SourceKey: AutomaticMipTail]
    private var automaticMipDemand = 0.0
    private var preparingAutomaticMips = false

    struct Entry {
        let input: SceneResourceView.FileInput
        let source: SceneTextureLoader.SourceKey
        var outcome: SceneBaseImageTextureLoad.Outcome?
        let naturalSizeWH: [Float]?
    }

    private struct DeferredRequest {
        let layerID: Int
        let url: SceneResourceView.FileInput
        let source: SceneTextureLoader.SourceKey
    }

    private enum DeferredState {
        case pending
        case loading
        case ready(Entry)
        case failed(SceneTextureLoadOutcome, String)
    }

    private struct ConditionalAtlas {
        let input: SceneResourceView.FileInput
        let conditions: SceneTextureAtlasConditions
        var layerIDs: Set<Int> = []
        var assetIdentities: Set<SceneAssetTextureIdentity> = []
    }

    private struct ConditionalProduct {
        let selection: Set<UInt32>
        let loaded: SceneBaseImageTextureLoad.Loaded?
    }

    struct ConditionalUpdates {
        var baseImages: [Int: SceneBaseImageTextureLoad.Loaded] = [:]
        var assets: [SceneAssetTextureIdentity: SceneTextureProviderState] = [:]
    }

    private struct PreparedConditionalTransaction {
        var products: [SceneTextureLoader.SourceKey: ConditionalProduct] = [:]
        var assets: [SceneAssetTextureIdentity: SceneTextureProviderState] = [:]
    }

    typealias ConditionalSelections = [SceneTextureLoader.SourceKey: Set<UInt32>]

    private struct ConditionalRequest {
        let generation: UInt64
        var selections: ConditionalSelections
        var result: Result<PreparedConditionalTransaction, Error>?
    }

    let textureLoader: SceneTextureLoader
    let puppets: ScenePreparedPuppetResources
    let puppetClipping: [String: PuppetClippingPreparation]
    private let deferredTextureLoader: SceneTextureLoader
    private let deferredSpriteTextureLoader = SceneMultiImageSpriteTextureLoader()
    private let deferredLock = NSLock()
    private let deferredQueue: DispatchQueue
    private let sceneGeneration: UInt64
    private let device: MTLDevice
    private let deviceRegistryID: UInt64
    private var entries: [Int: Entry]
    private var conditionalAtlases: [SceneTextureLoader.SourceKey: ConditionalAtlas]
    private(set) var conditionalPropertyKeys: Set<String>
    private var conditionalProducts: [SceneTextureLoader.SourceKey: ConditionalProduct]
    private var conditionalRequest: ConditionalRequest?
    private let deferredRequests: [Int: DeferredRequest]
    private var deferredStates: [Int: DeferredState]
    private var requestedGenerations: [Int: UInt64] = [:]
    private var preferredLayerID: Int?
    private var workerScheduled = false
    private var cancelled = false
    let dynamicImageResources: [String: ScenePreparedDynamicImageResource]
    let deferredLayerIDs: Set<Int>
    let loadedCount: Int
    let failedCount: Int

    private init(
        textureLoader: SceneTextureLoader,
        puppets: ScenePreparedPuppetResources,
        puppetClipping: [String: PuppetClippingPreparation],
        sceneGeneration: UInt64,
        device: MTLDevice,
        deviceRegistryID: UInt64,
        entries: [Int: Entry],
        conditionalAtlases: [SceneTextureLoader.SourceKey: ConditionalAtlas],
        conditionalProducts: [SceneTextureLoader.SourceKey: ConditionalProduct],
        dynamicImageResources: [String: ScenePreparedDynamicImageResource],
        deferredRequests: [Int: DeferredRequest],
        automaticMipProjection: SceneAutomaticTextureProjection?,
        automaticMipTails: [SceneTextureLoader.SourceKey: AutomaticMipTail],
        loadedCount: Int,
        failedCount: Int
    ) {
        self.textureLoader = textureLoader
        self.puppets = puppets
        self.puppetClipping = puppetClipping
        self.deferredTextureLoader = SceneTextureLoader(
            uploadCommandQueue: textureLoader.uploadCommandQueue,
            decodeCacheBudget: textureLoader.decodeCacheBudget
        )
        self.sceneGeneration = sceneGeneration
        self.device = device
        self.deviceRegistryID = deviceRegistryID
        self.entries = entries
        self.automaticMipProjection = automaticMipProjection
        self.automaticMipTails = automaticMipTails
        self.conditionalAtlases = conditionalAtlases
        self.conditionalProducts = conditionalProducts
        self.conditionalPropertyKeys = Set(conditionalAtlases.values.flatMap { $0.conditions.bindings.values.map(\.propertyKey) })
        self.dynamicImageResources = dynamicImageResources
        self.deferredRequests = deferredRequests
        self.deferredStates = deferredRequests.mapValues { _ in .pending }
        self.deferredLayerIDs = Set(deferredRequests.keys)
        self.loadedCount = loadedCount
        self.failedCount = failedCount
        self.deferredQueue = DispatchQueue(
            label: "com.mywallpaperx.scene-deferred-base-images.\(sceneGeneration)",
            qos: .userInitiated
        )
    }

    static func prepare(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        device: MTLDevice,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        sceneGeneration: UInt64,
        cacheDirectory: URL,
        effectivePropertyValues: [String: SceneUserPropertyValue] = [:],
        dynamicImageModelPaths: Set<String> = [],
        dynamicImageRequestsProvider: (() throws -> ImagePlanning)? = nil,
        deferredBaseImageLayerIDs: Set<Int> = [],
        imageGeometryModels: [SceneAssetCatalog.ModelAsset] = [],
        ordinaryColorMipLongEdge: Int? = nil,
        automaticDrawableExtent: CGSize? = nil,
        geometryPrepared: ([Int: [Float]]) -> Void = { _ in },
        uploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        decodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        ),
        cancellationCheck: () throws -> Void
    ) throws -> ScenePreparedBaseImageResources {
        try withoutActuallyEscaping(cancellationCheck) { cancellationCheck in
            let textureLoader = SceneTextureLoader(
                uploadCommandQueue: uploadCommandQueue,
                decodeCacheBudget: decodeCacheBudget
            )
            let resolver = SceneTexturePathResolver(
                resourceView: resourceView,
                descriptor: descriptor
            )
            let puppets = try ScenePreparedPuppetResources.prepare(
                descriptor: descriptor, resourceView: resourceView,
                cancellationCheck: cancellationCheck)
            var entries: [Int: Entry] = [:]
            var loadedCount = 0
            var failedCount = 0
            var deferredRequests: [Int: DeferredRequest] = [:]
            var conditionalAtlases: [SceneTextureLoader.SourceKey: ConditionalAtlas] = [:]
            var conditionalProducts: [SceneTextureLoader.SourceKey: ConditionalProduct] = [:]
            var conditionalInputs: [SceneTextureLoader.SourceKey: SceneTextureLoader.PreparedTexSource] = [:]
            let models = Dictionary(uniqueKeysWithValues: imageGeometryModels.map {
                ($0.relativePath, $0)
            })
            var imageRequests: [Int: (url: SceneResourceView.FileInput, source: SceneTextureLoader.SourceKey,
                direct: SceneTextureLoader.PreparedDirectImageSource?, videoPayload: Bool)] = [:]
            var videoModelPaths: Set<String> = []
            var geometry: [Int: [Float]] = [:]
            for layer in descriptor.layers where layer.isImageRenderable {
                try cancellationCheck()
                guard layer.contentKind != "solid" || layer.staticBaseTexturePath != nil,
                      let url = resolver.resolvePrimaryTexture(for: layer) else {
                    continue
                }
                let preparedTex = try textureLoader.prepareTexSource(from: url, checkCancellation: cancellationCheck)
                let direct = try textureLoader.prepareDirectImageSource(from: url, checkCancellation: cancellationCheck)
                guard let source = preparedTex?.source ?? direct?.source else { continue }
                let container = preparedTex?.container
                let isVideo = container?.isVideoMp4 == true
                let videoModelPath = isVideo && layer.contentKind == "image" ? layer.imagePath.flatMap {
                    url == resolver.resolvePrimaryTexture(modelPath: $0) ? $0 : nil
                } : nil
                if let videoModelPath {
                    videoModelPaths.insert(videoModelPath)
                }
                guard SceneBaseImageTextureLoad.specializedLoadReason(
                    url: url,
                    container: container,
                    usesPuppet: false
                ) == nil else {
                    continue
                }
                let naturalSize = try direct.map {
                    try textureLoader.preparedNaturalImageSize(from: $0, checkCancellation: cancellationCheck)
                } ?? container.map { CGSize(width: $0.imageWidth, height: $0.imageHeight) }
                let naturalSizeWH = naturalSize.map { [Float($0.width), Float($0.height)] }
                entries[layer.id] = .init(input: url, source: source, outcome: nil, naturalSizeWH: naturalSizeWH)
                if layer.contentKind == "image", layer.puppetMeshPath == nil, !isVideo,
                   let model = layer.imagePath.flatMap({ models[$0] }) {
                    if model.autosize == true, let naturalSizeWH,
                       naturalSizeWH.allSatisfy({ $0.isFinite && $0 > 0 }) {
                        geometry[layer.id] = naturalSizeWH
                    } else if model.autosize != true, layer.size == nil,
                              !model.hasDeclaredSizeFields, model.declaredSizeWH == nil,
                              case let .object(authored)? = layer.initialConfiguration,
                              authored["size"] == nil {
                        geometry[layer.id] = [1, 1]
                    }
                }
                if let preparedTex, let variants = container?.conditionalVariants, !variants.isEmpty {
                    if conditionalAtlases[source] == nil {
                        conditionalAtlases[source] = .init(input: url, conditions: SceneTextureAtlasConditions(variants))
                        conditionalInputs[source] = preparedTex
                    }
                    conditionalAtlases[source]?.layerIDs.insert(layer.id)
                    continue
                } else if deferredBaseImageLayerIDs.contains(layer.id) {
                    deferredRequests[layer.id] = .init(
                        layerID: layer.id,
                        url: url,
                        source: source
                    )
                    continue
                }
                let videoPayload = videoModelPath != nil && layer.puppetMeshPath == nil
                    && container?.format == 0 && container?.isVolume == false
                imageRequests[layer.id] = (url, source, direct?.admitForPreparation() == true ? direct : nil, videoPayload)
            }
            try cancellationCheck()
            geometryPrepared(geometry)
            // GPU uploads continue after metadata publication on the same worker.
            uploadCommandQueue.beginMipmapBatch()
            for (source, atlas) in conditionalAtlases {
                try cancellationCheck()
                let selection = atlas.conditions.selection { $0.matches(effectivePropertyValues) }
                if let loaded = try prepareConditionalAtlas(conditionalInputs.removeValue(forKey: source)!,
                    selection: selection, loader: textureLoader, device: device,
                    checkCancellation: cancellationCheck) {
                    conditionalProducts[source] = .init(selection: selection, loaded: loaded)
                    loadedCount += atlas.layerIDs.count
                } else {
                    failedCount += atlas.layerIDs.count
                }
            }
            let (automaticProjection, fullResolutionLayerIDs) = Self.mipPreparationInputs(
                descriptor: descriptor, drawable: automaticDrawableExtent,
                ordinaryColorMipLongEdge: ordinaryColorMipLongEdge)
            let automaticCover = automaticDrawableExtent.flatMap { automaticProjection?.coverScale(for: $0) }
            func loadInitialImage(_ layer: SceneRenderDescriptor.Layer, mipSelection: SceneOrdinaryImageMipSelection? = nil) throws {
                guard let request = imageRequests.removeValue(forKey: layer.id) else { return }
                try cancellationCheck()
                if request.videoPayload {
                    // Preserve the ordinary revision boundary without reparsing a non-uploadable payload.
                    if let source = try textureLoader.sourceKey(for: request.url, checkCancellation: cancellationCheck),
                       source != request.source { throw SceneResourceView.ReadError.sourceChanged }
                    failedCount += 1
                    return
                }
                let outcome = SceneBaseImageTextureLoad.load(
                    from: request.url,
                    usesPuppet: layer.puppetMeshPath != nil,
                    loader: textureLoader,
                    spriteTextureLoader: spriteTextureLoader,
                    device: device, source: request.source, preparedDirectImageSource: request.direct,
                    mipSelection: mipSelection,
                    checkCancellation: cancellationCheck
                )
                if case let .failed(failure) = outcome { try failure.rethrowResourceReadFailure() }
                switch outcome {
                case .loaded:
                    entries[layer.id] = .init(input: request.url, source: request.source, outcome: outcome,
                        naturalSizeWH: entries[layer.id]?.naturalSizeWH)
                    loadedCount += 1
                case .failed:
                    failedCount += 1
                }
            }
            var mipTailLayers: [SceneRenderDescriptor.Layer] = []
            var automaticSources: [SceneTextureLoader.SourceKey: SceneAutomaticTextureProjection.Source] = [:]
            var exactSources: Set<SceneTextureLoader.SourceKey> = []
            for layer in descriptor.layers {
                if layer.scalableStaticColorSource == true, let request = imageRequests[layer.id],
                   request.url.pathExtension.lowercased() == "tex", let size = entries[layer.id]?.naturalSizeWH,
                   !fullResolutionLayerIDs.contains(layer.id) {
                    if let ordinaryColorMipLongEdge, size.contains(where: { $0 > Float(ordinaryColorMipLongEdge) }) {
                        mipTailLayers.append(layer)
                        continue
                    }
                    if let automaticCover, let world = Self.automaticMipWorldExtent(layer, size: geometry[layer.id]),
                       let required = SceneAutomaticTextureProjection.minimumExtent(worldExtent: world, coverScale: automaticCover),
                       size[0] / 2 >= Float(required.x), size[1] / 2 >= Float(required.y) {
                        automaticSources[request.source, default: .init(worldExtent: world, layerIDs: [])]
                            .include(layerID: layer.id, worldExtent: world)
                        mipTailLayers.append(layer)
                        continue
                    }
                }
                if automaticProjection != nil, let source = entries[layer.id]?.source { exactSources.insert(source) }
                try loadInitialImage(layer)
            }
            let planning = try dynamicImageRequestsProvider?() ?? .init(models: dynamicImageModelPaths)
            // Admitted mutation owners can use model aliases without literal requests.
            let requestedModels = planning.models
            let canReduceModelDefaults = requestedModels.isEmpty && !planning.retainsModelDefaultAliases
            let automaticPlans = Self.automaticMipPlans(automaticSources, cover: automaticCover,
                exactSources: exactSources, constraints: canReduceModelDefaults ? planning.automaticMipConstraints : nil)
            let performanceSelection = canReduceModelDefaults
                ? ordinaryColorMipLongEdge.map(SceneOrdinaryImageMipSelection.maximumLongEdge) : nil
            for layer in mipTailLayers {
                let selection = imageRequests[layer.id].flatMap { automaticPlans[$0.source]?.selection } ?? performanceSelection
                try loadInitialImage(layer, mipSelection: selection)
            }

            var dynamicImageResources: [String: ScenePreparedDynamicImageResource] = [:]
            var videoFiles: [SceneTextureLoader.SourceKey: Result<SceneVideoOwnedFile, Error>] = [:]
            let imageMaterials = ScenePreparedImageMaterialCatalog(descriptor: descriptor)
            for modelPath in requestedModels.union(videoModelPaths).sorted() {
                try cancellationCheck()
                // Puppet resources enter below through mesh + straight atlas, never a quad.
                if models[modelPath]?.puppetPath != nil { continue }
                let modelIdentity = SceneModelResourceIdentity(modelPath).value
                let materialState = imageMaterials.renderStates[modelIdentity]
                // Built-in literal and indirect requests require the same recipe.
                // Non-built-in source Programs retain their existing preparation.
                if imageMaterials.builtinModelPaths.contains(modelIdentity),
                   imageMaterials.profiles[modelIdentity] == nil { continue }
                guard let url = resolver.resolvePrimaryTexture(modelPath: modelPath) else {
                    failedCount += 1
                    continue
                }
                let preparedTex = try textureLoader.prepareTexSource(from: url, checkCancellation: cancellationCheck)
                let direct = try textureLoader.prepareDirectImageSource(from: url, checkCancellation: cancellationCheck)
                let container = preparedTex?.container
                if let preparedTex,
                   let declaration = try textureLoader.videoSourceDeclaration(
                    from: preparedTex, checkCancellation: cancellationCheck) {
                    // WebM keeps its existing asynchronous remux owner. This
                    // prepared constructor slice admits completed MP4 files.
                    guard !declaration.isWebM, let container,
                          container.imageWidth > 0, container.imageHeight > 0 else { continue }
                    let prepared = videoFiles[declaration.source] ?? Result {
                        try SceneVideoOwnedFile.snapshot(payload: declaration.payload,
                            cacheDirectory: cacheDirectory, checkCancellation: cancellationCheck)
                    }
                    videoFiles[declaration.source] = prepared
                    try cancellationCheck()
                    guard case let .success(file) = prepared else {
                        failedCount += 1
                        continue
                    }
                    let sizeWH = [Float(container.imageWidth), Float(container.imageHeight)]
                    dynamicImageResources[modelPath.lowercased()] = .init(modelPath: modelPath,
                        product: .video(source: declaration.source, file: file, sizeWH: sizeWH),
                        naturalSizeWH: sizeWH,
                        lightingProfile: imageMaterials.profiles[modelIdentity],
                        imageMaterialRenderState: materialState?.supportsImageNormalDepth == true ? nil : materialState)
                    loadedCount += 1
                    continue
                }
                guard SceneBaseImageTextureLoad.specializedLoadReason(
                    url: url, container: container, usesPuppet: false
                ) == nil else {
                    failedCount += 1
                    continue
                }
                let outcome = SceneBaseImageTextureLoad.load(
                    from: url, usesPuppet: false, loader: textureLoader,
                    spriteTextureLoader: spriteTextureLoader, device: device,
                    preparedTexSource: preparedTex, preparedDirectImageSource: direct,
                    checkCancellation: cancellationCheck)
                if case let .failed(failure) = outcome { try failure.rethrowResourceReadFailure() }
                switch outcome {
                case let .loaded(loaded):
                    guard loaded.animation == nil, let candidate = loaded.candidate,
                          candidate.texture === loaded.texture else { continue }
                    if materialState?.supportsImageNormalDepth == true,
                       candidate.content != .color(.resolved(.straightAlpha)) { continue }
                    dynamicImageResources[modelPath.lowercased()] = .init(
                        modelPath: modelPath, product: .image(candidate),
                        naturalSizeWH: try (direct.map {
                            try textureLoader.preparedNaturalImageSize(from: $0, checkCancellation: cancellationCheck)
                        } ?? container.map { CGSize(width: $0.imageWidth, height: $0.imageHeight) })
                            .map { [Float($0.width), Float($0.height)] },
                        lightingProfile: imageMaterials.profiles[modelIdentity],
                        imageMaterialRenderState: materialState
                    )
                    loadedCount += 1
                case .failed:
                    failedCount += 1
                }
            }
            try cancellationCheck()
            // Failed GPU publications lose their outcome and cache entry. Particle
            // image providers take the existing inline retry here, before prewarm.
            let mipmapFlush = uploadCommandQueue.flushMipmapBatch()
            let conversionFlush = uploadCommandQueue.flushUncommittedCommandBuffers()
            let failedTextures = mipmapFlush.failedTextures + conversionFlush
            if !failedTextures.isEmpty {
                func isFailed(_ outcome: SceneBaseImageTextureLoad.Outcome?) -> Bool {
                    guard case let .loaded(loaded)? = outcome else { return false }
                    return failedTextures.contains { $0 === loaded.texture }
                }
                var reclaimed = 0
                for (layerID, entry) in entries where isFailed(entry.outcome) {
                    entries[layerID] = .init(input: entry.input, source: entry.source,
                        outcome: nil, naturalSizeWH: entry.naturalSizeWH)
                    reclaimed += 1
                }
                for (modelPath, resource) in dynamicImageResources {
                    guard case let .image(candidate) = resource.product,
                          failedTextures.contains(where: { $0 === candidate.texture }) else { continue }
                    dynamicImageResources.removeValue(forKey: modelPath)
                    reclaimed += 1
                }
                // One failed texture may back several layer/model publications.
                loadedCount -= reclaimed
                failedCount += reclaimed
                textureLoader.evictTextures(containedIn: failedTextures)
            }
            let particleImageProviders = Set(descriptor.layers.filter { $0.contentKind == "particle" }
                .flatMap { $0.authoredDependencies.filter { $0.type == "emitterimage" }.map(\.layerID) })
            for layer in descriptor.layers where layer.isImageRenderable
                && particleImageProviders.contains(layer.id) && deferredRequests[layer.id] == nil {
                if case .loaded? = entries[layer.id]?.outcome { continue }
                if let source = entries[layer.id]?.source, conditionalProducts[source] != nil { continue }
                try cancellationCheck()
                guard let url = resolver.resolvePrimaryTexture(for: layer),
                      let source = try entries[layer.id]?.source
                        ?? textureLoader.sourceKey(for: url, checkCancellation: cancellationCheck) else { continue }
                let preparedTex = try textureLoader.prepareTexSource(from: url, source: source,
                    checkCancellation: cancellationCheck)
                guard preparedTex?.container?.isVideoMp4 != true else { continue }
                let outcome = SceneBaseImageTextureLoad.load(from: url, usesPuppet: layer.puppetMeshPath != nil,
                    loader: textureLoader, spriteTextureLoader: spriteTextureLoader, device: device,
                    source: source, preparedTexSource: preparedTex, checkCancellation: cancellationCheck)
                try cancellationCheck()
                let previous = entries[layer.id]
                entries[layer.id] = .init(input: url, source: source, outcome: outcome,
                    naturalSizeWH: previous?.naturalSizeWH ?? preparedTex?.container.map {
                        [Float($0.imageWidth), Float($0.imageHeight)] })
                if previous != nil { failedCount -= 1 }
                switch outcome {
                case .loaded: loadedCount += 1
                case .failed: failedCount += 1
                }
            }
            let automaticMipTails = Self.keepPublishedAutomaticTails(automaticPlans, entries: entries, loader: textureLoader)
            // Model-default aliases reuse published entries, never layer overrides.
            for layer in descriptor.layers where layer.contentKind == "image" {
                try cancellationCheck()
                guard let modelPath = layer.imagePath,
                      dynamicImageResources[modelPath.lowercased()] == nil,
                      let profile = imageMaterials.profiles[SceneModelResourceIdentity(modelPath).value],
                      layer.puppetMeshPath == nil || !profile.surfaceEnabled,
                      let entry = entries[layer.id], automaticMipTails[entry.source] == nil,
                      let modelURL = resolver.resolvePrimaryTexture(modelPath: modelPath),
                      try (modelURL == entry.input || textureLoader.sourceKey(for: modelURL) == entry.source),
                      case let .loaded(loaded)? = entry.outcome,
                      loaded.animation == nil,
                      let candidate = loaded.candidate,
                      candidate.texture === loaded.texture else { continue }
                let pose = puppets.defaultPose(for: layer)
                guard layer.puppetMeshPath == nil || pose != nil else { continue }
                dynamicImageResources[modelPath.lowercased()] = .init(
                    modelPath: modelPath, product: .image(candidate),
                    naturalSizeWH: entry.naturalSizeWH,
                    puppetMeshPath: layer.puppetMeshPath, puppetPose: pose,
                    lightingProfile: profile
                )
            }
            let puppetClipping = try preparePuppetClipping(resources: puppets,
                dynamicResources: dynamicImageResources, resolver: resolver,
                textureLoader: textureLoader, device: device,
                cancellationCheck: cancellationCheck)
            // GPU publications no longer need the loader's decoded CPU copies.
            textureLoader.evictDecodedCaches()
            return ScenePreparedBaseImageResources(
                textureLoader: textureLoader,
                puppets: puppets,
                puppetClipping: puppetClipping,
                sceneGeneration: sceneGeneration,
                device: device,
                deviceRegistryID: device.registryID,
                entries: entries,
                conditionalAtlases: conditionalAtlases.filter { conditionalProducts[$0.key] != nil },
                conditionalProducts: conditionalProducts,
                dynamicImageResources: dynamicImageResources,
                deferredRequests: deferredRequests,
                automaticMipProjection: automaticMipTails.isEmpty ? nil : automaticProjection,
                automaticMipTails: automaticMipTails,
                loadedCount: loadedCount,
                failedCount: failedCount
            )
        }
    }

    func particleLayerImageCompilation(descriptor: SceneRenderDescriptor, destroyedIDs: Set<Int> = [])
        -> SceneParticleLayerImageEmitterCompilation {
        let snapshot = deferredLock.withLock { entries }
        let loaded: [Int: SceneBaseImageTextureLoad.Loaded] = snapshot
            .filter { !destroyedIDs.contains($0.key) }.compactMapValues { entry in
                if let atlas = conditionalOutcome(for: entry.source) { return atlas }
                guard case let .loaded(value)? = entry.outcome else { return nil }
                return value
            }
        return SceneParticleLayerImageEmitterCompiler.compile(descriptor: descriptor,
            texturesByLayerID: loaded.mapValues(\.texture),
            animatedSourceLayerIDs: Set(loaded.compactMap { $0.value.animation == nil ? nil : $0.key }),
            destroyedAuthoredLayerIDs: destroyedIDs)
    }

    func outcome(
        for layerID: Int,
        url: SceneResourceView.FileInput,
        device: MTLDevice
    ) -> SceneBaseImageTextureLoad.Outcome? {
        guard device.registryID == deviceRegistryID else { return nil }
        let entry: Entry?
        if let prepared = entries[layerID], let atlas = conditionalOutcome(for: prepared.source) {
            return prepared.input == url ? .loaded(atlas) : .failed(.resourceReadFailed(SceneResourceView.ReadError.invalidHandle))
        }
        if let prepared = entries[layerID], prepared.outcome != nil {
            entry = prepared
        } else {
            deferredLock.lock()
            if case let .ready(prepared)? = deferredStates[layerID] {
                entry = prepared
            } else {
                entry = entries[layerID]
            }
            deferredLock.unlock()
        }
        guard let entry else { return nil }
        // Reuse the prepared GPU result without reopening the input on the main thread.
        guard entry.input == url else { return .failed(.resourceReadFailed(SceneResourceView.ReadError.invalidHandle)) }
        return entry.outcome
    }

    private func conditionalOutcome(for source: SceneTextureLoader.SourceKey) -> SceneBaseImageTextureLoad.Loaded? {
        guard conditionalAtlases[source] != nil else { return nil }
        deferredLock.lock()
        defer { deferredLock.unlock() }
        return conditionalProducts[source]?.loaded
    }

    // Joins the independently prepared launch inputs before any Surface starts.
    func addConditionalAssets(_ assets: [SceneTextureLoader.SourceKey: SceneMaterialAssetTextureCatalog.ConditionalAsset]) {
        for (source, asset) in assets {
            conditionalAtlases[source, default: .init(input: asset.input, conditions: asset.conditions)]
                .assetIdentities.formUnion(asset.identities)
            if conditionalProducts[source] == nil {
                conditionalProducts[source] = .init(selection: asset.selection, loaded: nil)
            }
            conditionalPropertyKeys.formUnion(asset.conditions.bindings.values.map(\.propertyKey))
        }
    }

    func conditionalSelections(
        values: [String: SceneUserPropertyValue], changedKeys: Set<String>
    ) -> ConditionalSelections {
        guard !conditionalPropertyKeys.isDisjoint(with: changedKeys) else { return [:] }
        deferredLock.lock()
        defer { deferredLock.unlock() }
        return conditionalAtlases.reduce(into: [:]) { result, entry in
            let (source, atlas) = entry
            guard atlas.conditions.bindings.values.contains(where: { changedKeys.contains($0.propertyKey) }) else { return }
            let selection = atlas.conditions.selection { $0.matches(values) }
            if selection != conditionalProducts[source]?.selection { result[source] = selection }
        }
    }

    func requestConditionalAtlases(_ selections: ConditionalSelections, generation: UInt64) {
        deferredLock.lock()
        defer { deferredLock.unlock() }
        conditionalRequest = nil
        guard !selections.isEmpty, !cancelled else { return }
        conditionalRequest = .init(generation: generation, selections: selections)
        scheduleDeferredWorkerLocked()
    }

    func conditionalStatus(generation: UInt64) -> SceneDeferredBaseImageStatus {
        deferredLock.lock()
        defer { deferredLock.unlock() }
        guard let request = conditionalRequest, request.generation == generation else { return .notDeferred }
        switch request.result {
        case .success?: return .ready
        case .failure?: return .failed("conditional-atlas")
        case nil: return .loading
        }
    }

    @discardableResult
    func finishConditionalAtlases(
        generation: UInt64, commit: Bool
    ) -> ConditionalUpdates {
        deferredLock.lock()
        defer { deferredLock.unlock() }
        guard let request = conditionalRequest, request.generation == generation else { return .init() }
        conditionalRequest = nil
        guard commit, case let .success(prepared)? = request.result else { return .init() }
        var updates = ConditionalUpdates(assets: prepared.assets)
        for (source, product) in prepared.products {
            conditionalProducts[source] = product
            for layerID in conditionalAtlases[source]!.layerIDs { updates.baseImages[layerID] = product.loaded }
        }
        return updates
    }

    @MainActor
    func promoteAutomaticMips(for drawable: CGSize, publish: @escaping @MainActor ([Int: SceneBaseImageTextureLoad.Loaded]) -> Void) {
        guard !automaticMipTails.isEmpty, let automaticMipProjection else { return }
        let cover = automaticMipProjection.coverScale(for: drawable)
        guard cover.isFinite, cover > automaticMipDemand else { return }
        automaticMipDemand = cover
        prepareAutomaticMips(publish: publish)
    }

    @MainActor
    private func prepareAutomaticMips(publish: @escaping @MainActor ([Int: SceneBaseImageTextureLoad.Loaded]) -> Void) {
        guard !preparingAutomaticMips else { return }
        let cover = automaticMipDemand
        let requests = automaticMipTails.filter { $0.value.maximumCoverScale < cover }
        guard !requests.isEmpty else { return }
        preparingAutomaticMips = true
        deferredQueue.async { [weak self] in
            guard let self else { return }
            let prepared = Self.prepareAutomaticMipPromotions(requests, cover: cover, loader: self.deferredTextureLoader,
                device: self.device, checkCancellation: self.checkDeferredCancellation)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.preparingAutomaticMips = false
                var updates: [Int: SceneBaseImageTextureLoad.Loaded] = [:]
                let committed = self.deferredLock.withLock {
                    guard !self.cancelled else { return false }
                    for (source, loaded) in prepared {
                        guard var tail = requests[source], let candidate = loaded.candidate else { continue }
                        for layerID in tail.use.layerIDs { updates[layerID] = loaded }
                        tail.maximumCoverScale = tail.use.maximumCoverScale(for: candidate.physicalSize)
                        self.automaticMipTails[source] = candidate.embeddedBaseMip > 0 ? tail : nil
                    }
#if DEBUG
                    Self.reportAutomaticMipRetirement(entries: self.entries, layerIDs: updates.keys)
#endif
                    for (layerID, loaded) in updates { self.entries[layerID]?.outcome = .loaded(loaded) }
                    return true
                }
                guard committed else { return }
                if !updates.isEmpty { publish(updates) }
                if self.automaticMipDemand > cover { self.prepareAutomaticMips(publish: publish) }
            }
        }
    }

    private func prepareRequestedConditionalAtlases(_ request: ConditionalRequest) {
        let checkCancellation = {
            self.deferredLock.lock()
            let valid = !self.cancelled && self.conditionalRequest?.generation == request.generation
            self.deferredLock.unlock()
            if !valid { throw CancellationError() }
        }
        let result = Result { try loadConditionalTransaction(request, checkCancellation: checkCancellation) }
        deferredLock.lock()
        if conditionalRequest?.generation == request.generation { conditionalRequest?.result = result }
        deferredLock.unlock()
    }

    private func loadConditionalTransaction(
        _ request: ConditionalRequest, checkCancellation: () throws -> Void
    ) throws -> PreparedConditionalTransaction {
        try withoutActuallyEscaping(checkCancellation) { checkCancellation in
            let loader = deferredTextureLoader
            var transaction = PreparedConditionalTransaction()
            for (source, selection) in request.selections {
                let atlas = conditionalAtlases[source]!
                defer { loader.evictDecodedCaches() }
                guard let prepared = try loader.prepareTexSource(
                    from: atlas.input, source: source, checkCancellation: checkCancellation)
                else { throw ConditionalAtlasPreparationError.unavailable }
                var loaded: SceneBaseImageTextureLoad.Loaded?
                var candidates: [SceneTextureLoadPurpose: SceneTextureCandidate] = [:]
                if !atlas.layerIDs.isEmpty {
                    loaded = try Self.prepareConditionalAtlas(prepared, selection: selection, loader: loader,
                        device: device, checkCancellation: checkCancellation)
                    guard let loaded else { throw ConditionalAtlasPreparationError.unavailable }
                    candidates[.straightAlbedo] = loaded.candidate
                }
                for identity in atlas.assetIdentities {
                    let candidate: SceneTextureCandidate
                    if let existing = candidates[identity.purpose] {
                        candidate = existing
                    } else {
                        let outcome = try loader.loadCandidate(from: prepared, purpose: identity.purpose,
                            device: device, conditionalVariantIDs: selection, checkCancellation: checkCancellation)
                        guard case let .loaded(newCandidate) = outcome else {
                            throw ConditionalAtlasPreparationError.unavailable
                        }
                        candidate = newCandidate
                        candidates[identity.purpose] = newCandidate
                    }
                    let publication = SceneTextureProviderPublication(requestIdentity: .asset(identity),
                        candidate: candidate, contentGeneration: request.generation + 1)
                    guard publication.isComplete else { throw ConditionalAtlasPreparationError.unavailable }
                    transaction.assets[identity] = .ready(publication)
                }
                transaction.products[source] = .init(selection: selection, loaded: loaded)
            }
            return transaction
        }
    }

    private enum ConditionalAtlasPreparationError: Error { case unavailable }

    @discardableResult
    func requestDeferredBaseImage(
        layerID: Int,
        requestGeneration: UInt64
    ) -> SceneDeferredBaseImageStatus {
        deferredLock.lock()
        guard !cancelled else {
            deferredLock.unlock()
            return .failed("cancelled")
        }
        guard let state = deferredStates[layerID] else {
            deferredLock.unlock()
            return .notDeferred
        }
        let status = Self.status(for: state)
        switch state {
        case .ready, .failed, .loading:
            break
        case .pending:
            let supersededLayerIDs = requestedGenerations.compactMap {
                layerID, generation in
                generation < requestGeneration ? layerID : nil
            }
            for requestedLayerID in supersededLayerIDs {
                requestedGenerations.removeValue(forKey: requestedLayerID)
            }
            requestedGenerations[layerID] = requestGeneration
            preferredLayerID = layerID
            scheduleDeferredWorkerLocked()
        }
        deferredLock.unlock()
        return status
    }

    func deferredStatus(for layerID: Int) -> SceneDeferredBaseImageStatus {
        deferredLock.lock()
        let status = deferredStates[layerID].map(Self.status(for:))
            ?? .notDeferred
        deferredLock.unlock()
        return status
    }

    func cancelDeferredPreparation() {
        deferredLock.lock()
        cancelDeferredPreparationLocked()
        deferredLock.unlock()
    }

    /// Stops admission and joins actual reads/decode/upload on the original queue.
    func cancelAndDrainDeferredPreparation(completion: @escaping @Sendable () -> Void) {
        deferredLock.lock()
        cancelDeferredPreparationLocked()
        deferredQueue.async { [self] in
            withExtendedLifetime(self) { completion() }
        }
        deferredLock.unlock()
    }

    private func cancelDeferredPreparationLocked() {
        cancelled = true
        conditionalRequest = nil
        requestedGenerations.removeAll(keepingCapacity: false)
        preferredLayerID = nil
    }

    private func scheduleDeferredWorkerLocked() {
        guard !workerScheduled else { return }
        workerScheduled = true
        deferredQueue.async { [weak self] in self?.runDeferredWorker() }
    }

    private func runDeferredWorker() {
        while true {
            let request: DeferredRequest
            let generation: UInt64
            deferredLock.lock()
            if let conditionalRequest, !conditionalRequest.selections.isEmpty {
                self.conditionalRequest?.selections.removeAll()
                deferredLock.unlock()
                prepareRequestedConditionalAtlases(conditionalRequest)
                continue
            }
            guard !cancelled,
                  let selectedLayerID = nextRequestedLayerIDLocked(),
                  let selectedRequest = deferredRequests[selectedLayerID] else {
                workerScheduled = false
                deferredLock.unlock()
                return
            }
            request = selectedRequest
            generation = requestedGenerations[selectedLayerID] ?? 0
            deferredStates[selectedLayerID] = .loading
            deferredLock.unlock()

            let (outcome, naturalSize): (SceneBaseImageTextureLoad.Outcome, [Float]?) = {
                do {
                    try checkDeferredCancellation()
                    let preparedTex = try deferredTextureLoader.prepareTexSource(
                        from: request.url, source: request.source, checkCancellation: checkDeferredCancellation)
                    let direct = try deferredTextureLoader.prepareDirectImageSource(
                        from: request.url, source: request.source, checkCancellation: checkDeferredCancellation)
                    let loaded = SceneBaseImageTextureLoad.load(
                        from: request.url, usesPuppet: false, loader: deferredTextureLoader,
                        spriteTextureLoader: deferredSpriteTextureLoader, device: device, source: request.source,
                        preparedTexSource: preparedTex, preparedDirectImageSource: direct,
                        checkCancellation: checkDeferredCancellation)
                    if case let .failed(failure) = loaded { try failure.rethrowResourceReadFailure() }
                    let size = try (direct.map {
                        try deferredTextureLoader.preparedNaturalImageSize(from: $0,
                            checkCancellation: checkDeferredCancellation)
                    } ?? preparedTex?.container.map { CGSize(width: $0.imageWidth, height: $0.imageHeight) })
                        .map { [Float($0.width), Float($0.height)] }
                    return (loaded, size)
                } catch { return (.failed(.resourceReadFailed(error)), nil) }
            }()
            // Upload has completed, so the deferred loader can release decoded CPU bytes.
            deferredTextureLoader.evictDecodedCaches()
            deferredLock.lock()
            guard !cancelled else {
                workerScheduled = false
                deferredLock.unlock()
                return
            }
            switch outcome {
            case .loaded:
                deferredStates[request.layerID] = .ready(.init(
                    input: request.url, source: request.source,
                    outcome: outcome,
                    naturalSizeWH: naturalSize
                ))
            case let .failed(failure):
                deferredStates[request.layerID] = .failed(
                    failure,
                    Self.failureCode(failure)
                )
            }
            requestedGenerations.removeValue(forKey: request.layerID)
            if preferredLayerID == request.layerID {
                preferredLayerID = nil
            }
            let status = Self.status(for: deferredStates[request.layerID]!)
            deferredLock.unlock()
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                NSLog(
                    "MWX deferred base image: schema=deferred-base-image-v2 sceneGeneration=%llu requestGeneration=%llu layer=%d status=%@",
                    sceneGeneration,
                    generation,
                    request.layerID,
                    Self.statusName(status)
                )
            }
#endif
        }
    }

    private func checkDeferredCancellation() throws {
        deferredLock.lock()
        let stopped = cancelled
        deferredLock.unlock()
        if stopped { throw CancellationError() }
    }

    private func nextRequestedLayerIDLocked() -> Int? {
        if let preferredLayerID,
           requestedGenerations[preferredLayerID] != nil,
           case .pending? = deferredStates[preferredLayerID] {
            return preferredLayerID
        }
        return requestedGenerations
            .filter { layerID, _ in
                if case .pending? = deferredStates[layerID] { return true }
                return false
            }
            .max { lhs, rhs in
                lhs.value == rhs.value
                    ? lhs.key > rhs.key
                    : lhs.value < rhs.value
            }?.key
    }

    private nonisolated static func status(
        for state: DeferredState
    ) -> SceneDeferredBaseImageStatus {
        switch state {
        case .pending: .pending
        case .loading: .loading
        case .ready: .ready
        case let .failed(_, code): .failed(code)
        }
    }

    private nonisolated static func failureCode(
        _ failure: SceneTextureLoadOutcome
    ) -> String {
        switch failure {
        case .loaded: "invalid-loaded-failure"
        case .unsupportedFormat: "unsupported-format"
        case .unsupportedTexFormat: "unsupported-tex-format"
        case .texNoEmbeddedImage: "tex-no-embedded-image"
        case .texContainsVideoPayload: "tex-video-payload"
        case .decodeFailed: "decode-failed"
        case .resourceReadFailed: "resource-read-failed"
        case .textureAllocationFailed: "texture-allocation-failed"
        }
    }

    private nonisolated static func statusName(
        _ status: SceneDeferredBaseImageStatus
    ) -> String {
        switch status {
        case .notDeferred: "not-deferred"
        case .pending: "pending"
        case .loading: "loading"
        case .ready: "ready"
        case let .failed(code): "failed:\(code)"
        }
    }

    deinit {
        cancelDeferredPreparation()
    }

    var reportLine: String {
        "prepared static base resources: entries=\(entries.values.filter { $0.outcome != nil }.count)"
            + " dynamicImages=\(dynamicImageResources.count)"
            + " deferred=\(deferredLayerIDs.count)"
            + " loaded=\(loadedCount) failed=\(failedCount)"
            + " device=\(deviceRegistryID)"
    }
}
