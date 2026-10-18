import Foundation
import Metal

nonisolated struct ScenePreparedDynamicImageResource {
    let modelPath: String
    let loaded: SceneBaseImageTextureLoad.Loaded
    /// Source image extent retained before texture normalization/downscaling.
    /// The same decode owner supplies TEX and direct-image native metadata.
    var naturalSizeWH: [Float]? = nil
    var puppetMeshPath: String? = nil
    var puppetPose: ScenePuppetLayerLoad.PreparedPose? = nil
    /// A model-default built-in recipe, never an authored layer instance.
    var lightingProfile: SceneBaseMaterialLightingProfile? = nil
    var imageMaterialRenderState: SceneMaterialRenderState? = nil

    var renderSizeWH: [Float] {
        [Float(loaded.texture.width), Float(loaded.texture.height)]
    }
}

nonisolated enum SceneDeferredBaseImageStatus: Equatable {
    case notDeferred
    case pending
    case loading
    case ready
    case failed(String)
}

/// Device-bound ordinary base images shared by every AppKit surface. The
/// initially visible entries are prepared before activation; eligible dormant
/// Combo alternatives are published on demand by this same owner. Animated,
/// video and other providers keep their lifecycle owners. Puppet CPU models and
/// static atlases are shared; pose/physics/GPU geometry remain surface-scoped.
final class ScenePreparedBaseImageResources {
    private struct Entry {
        let source: SceneTextureLoader.SourceKey
        let outcome: SceneBaseImageTextureLoad.Outcome?
        let naturalSizeWH: [Float]?
    }

    private struct DeferredRequest {
        let layerID: Int
        let url: URL
        let source: SceneTextureLoader.SourceKey
    }

    private enum DeferredState {
        case pending
        case loading
        case ready(Entry)
        case failed(SceneTextureLoadOutcome, String)
    }

    let textureLoader: SceneTextureLoader
    let puppets: ScenePreparedPuppetResources
    private let deferredTextureLoader: SceneTextureLoader
    private let deferredSpriteTextureLoader = SceneMultiImageSpriteTextureLoader()
    private let deferredLock = NSLock()
    private let deferredQueue: DispatchQueue
    private let sceneGeneration: UInt64
    private let device: MTLDevice
    private let deviceRegistryID: UInt64
    private let entries: [Int: Entry]
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
        sceneGeneration: UInt64,
        device: MTLDevice,
        deviceRegistryID: UInt64,
        entries: [Int: Entry],
        dynamicImageResources: [String: ScenePreparedDynamicImageResource],
        deferredRequests: [Int: DeferredRequest],
        loadedCount: Int,
        failedCount: Int
    ) {
        self.textureLoader = textureLoader
        self.puppets = puppets
        self.deferredTextureLoader = SceneTextureLoader(
            uploadCommandQueue: textureLoader.uploadCommandQueue,
            decodeCacheBudget: textureLoader.decodeCacheBudget
        )
        self.sceneGeneration = sceneGeneration
        self.device = device
        self.deviceRegistryID = deviceRegistryID
        self.entries = entries
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
        dynamicImageModelPaths: Set<String> = [],
        dynamicImageModelPathsProvider: (() throws -> Set<String>)? = nil,
        deferredBaseImageLayerIDs: Set<Int> = [],
        imageGeometryModels: [SceneAssetCatalog.ModelAsset] = [],
        geometryPrepared: ([Int: [Float]]) -> Void = { _ in },
        uploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        decodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        ),
        cancellationCheck: () throws -> Void
    ) throws -> ScenePreparedBaseImageResources {
        let textureLoader = SceneTextureLoader(
            uploadCommandQueue: uploadCommandQueue,
            decodeCacheBudget: decodeCacheBudget
        )
        let resolver = SceneTexturePathResolver(
            resourceView: resourceView,
            descriptor: descriptor
        )
        let puppets = try ScenePreparedPuppetResources.prepare(
            descriptor: descriptor, cacheDirectory: resourceView.primaryRootURL,
            cancellationCheck: cancellationCheck)
        var entries: [Int: Entry] = [:]
        var loadedCount = 0
        var failedCount = 0
        var deferredRequests: [Int: DeferredRequest] = [:]
        let models = Dictionary(uniqueKeysWithValues: imageGeometryModels.map {
            ($0.relativePath, $0)
        })
        var imageRequests: [Int: (url: URL, source: SceneTextureLoader.SourceKey)] = [:]
        var geometry: [Int: [Float]] = [:]
        for layer in descriptor.layers where layer.isImageRenderable {
            try cancellationCheck()
            guard layer.contentKind != "solid" || layer.staticBaseTexturePath != nil,
                  let url = resolver.resolvePrimaryTexture(for: layer),
                  let source = textureLoader.sourceKey(for: url) else {
                continue
            }
            let container = url.pathExtension.lowercased() == "tex"
                ? textureLoader.texContainer(from: url, source: source)
                : nil
            guard SceneBaseImageTextureLoad.specializedLoadReason(
                url: url,
                container: container,
                usesPuppet: false
            ) == nil else {
                continue
            }
            let naturalSize = textureLoader.preparedNaturalImageSize(from: url, source: source)
                .map { [Float($0.width), Float($0.height)] }
            entries[layer.id] = .init(source: source, outcome: nil, naturalSizeWH: naturalSize)
            if layer.contentKind == "image", layer.puppetMeshPath == nil, container?.isVideoMp4 != true,
               let model = layer.imagePath.flatMap({ models[$0] }) {
                if model.autosize == true, let naturalSize,
                   naturalSize.allSatisfy({ $0.isFinite && $0 > 0 }) {
                    geometry[layer.id] = naturalSize
                } else if model.autosize != true, layer.size == nil,
                          !model.hasDeclaredSizeFields, model.declaredSizeWH == nil,
                          case let .object(authored)? = layer.initialConfiguration,
                          authored["size"] == nil {
                    geometry[layer.id] = [1, 1]
                }
            }
            if deferredBaseImageLayerIDs.contains(layer.id) {
                deferredRequests[layer.id] = .init(
                    layerID: layer.id,
                    url: url,
                    source: source
                )
                continue
            }
            imageRequests[layer.id] = (url, source)
        }
        try cancellationCheck()
        geometryPrepared(geometry)
        // GPU uploads continue after metadata publication on the same worker.
        uploadCommandQueue.beginMipmapBatch()
        for layer in descriptor.layers {
            guard let request = imageRequests[layer.id] else { continue }
            try cancellationCheck()
            let outcome = SceneBaseImageTextureLoad.load(
                from: request.url,
                usesPuppet: layer.puppetMeshPath != nil,
                loader: textureLoader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
            switch outcome {
            case .loaded:
                entries[layer.id] = .init(source: request.source, outcome: outcome,
                    naturalSizeWH: entries[layer.id]?.naturalSizeWH)
                loadedCount += 1
            case .failed:
                failedCount += 1
            }
        }
        var dynamicImageResources: [String: ScenePreparedDynamicImageResource] = [:]
        let imageMaterials = ScenePreparedImageMaterialCatalog(descriptor: descriptor)
        let requestedModels = try dynamicImageModelPathsProvider?() ?? dynamicImageModelPaths
        for modelPath in requestedModels.sorted() {
            try cancellationCheck()
            // Puppet resources enter below through mesh + straight atlas, never a quad.
            if models[modelPath]?.puppetPath != nil { continue }
            let modelIdentity = SceneModelResourceIdentity(modelPath).value
            // Built-in literal and indirect requests require the same recipe.
            // Non-built-in source Programs retain their existing preparation.
            if imageMaterials.builtinModelPaths.contains(modelIdentity),
               imageMaterials.profiles[modelIdentity] == nil { continue }
            guard let url = resolver.resolvePrimaryTexture(modelPath: modelPath),
                  let source = textureLoader.sourceKey(for: url) else {
                failedCount += 1
                continue
            }
            let container = url.pathExtension.lowercased() == "tex"
                ? textureLoader.texContainer(from: url, source: source)
                : nil
            guard SceneBaseImageTextureLoad.specializedLoadReason(
                url: url, container: container, usesPuppet: false
            ) == nil else {
                failedCount += 1
                continue
            }
            switch SceneBaseImageTextureLoad.load(
                from: url, usesPuppet: false, loader: textureLoader,
                spriteTextureLoader: spriteTextureLoader, device: device
            ) {
            case let .loaded(loaded):
                dynamicImageResources[modelPath.lowercased()] = .init(
                    modelPath: modelPath, loaded: loaded,
                    naturalSizeWH: textureLoader.preparedNaturalImageSize(from: url, source: source)
                        .map { [Float($0.width), Float($0.height)] },
                    lightingProfile: imageMaterials.profiles[modelIdentity],
                    imageMaterialRenderState: imageMaterials.renderStates[modelIdentity]
                )
                loadedCount += 1
            case .failed:
                failedCount += 1
            }
        }
        try cancellationCheck()
        // Cancellation aborts the pass with pending textures discarded; a
        // successful pass flushes every deferred generation before any frame
        // can sample the returned textures. A flush failure reclaims every
        // entry whose GPU publication cannot be proven AND evicts those
        // textures from the loader's GPU cache: the affected layers and
        // dynamic images lose their prepared outcome, and their render-time
        // inline loads miss the cache, re-decode and retry — the pre-batch
        // single-texture fail-soft semantics. Every device is drained by
        // the flush, so no deferred texture escapes accounting.
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
                entries.removeValue(forKey: layerID)
                reclaimed += 1
            }
            for (modelPath, resource) in dynamicImageResources
            where failedTextures.contains(where: { $0 === resource.loaded.texture }) {
                dynamicImageResources.removeValue(forKey: modelPath)
                reclaimed += 1
            }
            // Shared sources appear under multiple entries while the failed
            // identity list holds each texture once; count reclaims so
            // loaded+failed stays consistent with the entry accounting.
            loadedCount -= reclaimed
            failedCount += reclaimed
            textureLoader.evictTextures(containedIn: failedTextures)
        }
        // An authored ordinary model can be requested through initial config
        // without a literal script reference. Reuse only GPU-published entries
        // whose source is the model default, never a layer-local override.
        for layer in descriptor.layers where layer.contentKind == "image" {
            try cancellationCheck()
            guard let modelPath = layer.imagePath,
                  dynamicImageResources[modelPath.lowercased()] == nil,
                  let profile = imageMaterials.profiles[SceneModelResourceIdentity(modelPath).value],
                  layer.puppetMeshPath == nil || !profile.surfaceEnabled,
                  let entry = entries[layer.id],
                  let modelURL = resolver.resolvePrimaryTexture(modelPath: modelPath),
                  textureLoader.sourceKey(for: modelURL) == entry.source,
                  case let .loaded(loaded)? = entry.outcome,
                  loaded.animation == nil,
                  let candidate = loaded.candidate,
                  candidate.texture === loaded.texture else { continue }
            let pose = puppets.defaultPose(for: layer)
            guard layer.puppetMeshPath == nil || pose != nil else { continue }
            dynamicImageResources[modelPath.lowercased()] = .init(
                modelPath: modelPath, loaded: loaded,
                naturalSizeWH: entry.naturalSizeWH,
                puppetMeshPath: layer.puppetMeshPath, puppetPose: pose,
                lightingProfile: profile
            )
        }
        // Every launch texture is GPU-published past this point: drop the
        // loader's CPU-side decoded bytes so they do not sit next to their
        // GPU copies for the whole session. Later loads hit the GPU cache;
        // a miss re-decodes from the source file.
        textureLoader.evictDecodedCaches()
        return ScenePreparedBaseImageResources(
            textureLoader: textureLoader,
            puppets: puppets,
            sceneGeneration: sceneGeneration,
            device: device,
            deviceRegistryID: device.registryID,
            entries: entries,
            dynamicImageResources: dynamicImageResources,
            deferredRequests: deferredRequests,
            loadedCount: loadedCount,
            failedCount: failedCount
        )
    }

    func outcome(
        for layerID: Int,
        url: URL,
        device: MTLDevice
    ) -> SceneBaseImageTextureLoad.Outcome? {
        guard device.registryID == deviceRegistryID else { return nil }
        let entry: Entry?
        if let prepared = entries[layerID], prepared.outcome != nil {
            entry = prepared
        } else {
            deferredLock.lock()
            if case let .ready(prepared)? = deferredStates[layerID] {
                entry = prepared
            } else {
                entry = nil
            }
            deferredLock.unlock()
        }
        guard let entry,
              textureLoader.sourceKey(for: url) == entry.source else {
            return nil
        }
        return entry.outcome
    }

    @discardableResult
    func requestDeferredBaseImage(
        layerID: Int,
        requestGeneration: UInt64
    ) -> SceneDeferredBaseImageStatus {
        var shouldSchedule = false
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
            if !workerScheduled {
                workerScheduled = true
                shouldSchedule = true
            }
        }
        deferredLock.unlock()
        if shouldSchedule {
            deferredQueue.async { [weak self] in
                self?.runDeferredWorker()
            }
        }
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
        cancelled = true
        requestedGenerations.removeAll(keepingCapacity: false)
        preferredLayerID = nil
        deferredLock.unlock()
    }

    private func runDeferredWorker() {
        while true {
            let request: DeferredRequest
            let generation: UInt64
            deferredLock.lock()
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

            let outcome = SceneBaseImageTextureLoad.load(
                from: request.url,
                usesPuppet: false,
                loader: deferredTextureLoader,
                spriteTextureLoader: deferredSpriteTextureLoader,
                device: device
            )
            // The load returns with its texture GPU-published (the upload
            // paths commit and wait), so the deferred loader's decoded CPU
            // bytes for this source are evictable now — same reasoning as
            // the prepare-tail eviction, applied per deferred load.
            let naturalSize = deferredTextureLoader.preparedNaturalImageSize(
                from: request.url, source: request.source)
                .map { [Float($0.width), Float($0.height)] }
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
                    source: request.source,
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

struct ScenePreparedDeviceResources {
    let pipelineRepository: SceneImageEffectPipelineRepository
    let imageLayerPipeline: SceneImageLayerPipeline
    let spriteTextureLoader: SceneMultiImageSpriteTextureLoader
    let baseImages: ScenePreparedBaseImageResources
    let staticModels: ScenePreparedStaticModelResources

    var device: MTLDevice { pipelineRepository.device }
}

extension ScenePreparedDeviceResources {
    /// Both the first-surface worker and later surfaces use this launch-only
    /// preparation boundary. Rendering receives typed frame binding only.
    static func makeMaterialRuntime(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        device: MTLDevice,
        visibleExecutionRootLayerIDs: Set<Int> = [],
        capturesExecutionObservations: Bool
    ) -> SceneResolvedMaterialRuntimeBridge {
        let runtime = SceneResolvedMaterialRuntimeBridge(catalog: catalog,
            capabilities: capabilities, assets: assets, device: device,
            visibleExecutionRootLayerIDs: visibleExecutionRootLayerIDs,
            capturesExecutionObservations: capturesExecutionObservations)
        runtime.sourceMaterials = prepareSourceMaterialPrograms(catalog: catalog,
            assets: assets, device: device,
            encoder: runtime.submissions.executor?.materialEncoder,
            logSink: runtime.submissions.logSink)
        return runtime
    }



}

/// One bounded launch worker overlaps pipeline and initially visible resource
/// preparation with CPU Program/VM compilation. The result is joined before
/// publication; its base-image owner may then service bounded, generation-safe
/// on-demand Combo alternatives until the scene context is cancelled.
final class ScenePreparedDeviceResourcesTask {
    private static let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-device-resource-preparation",
        qos: .userInitiated
    )

    private let condition = NSCondition()
    private let descriptor: SceneRenderDescriptor
    private let resourceView: SceneResourceView
    private let device: MTLDevice
    private let imageGeometryModels: [SceneAssetCatalog.ModelAsset]
    private let deferredBaseImageLayerIDs: Set<Int>
    private let sceneGeneration: UInt64
    private let textureUploadCommandQueue: SceneTextureUploadCommandQueue
    private let textureDecodeCacheBudget: SceneTextureDecodeCacheBudget
    private let externalCancellationCheck: () throws -> Void
    private var result: Result<ScenePreparedDeviceResources, Error>?
    private var geometryResult: Result<[Int: [Float]], Error>?
    private var cancellationRequested = false
    private var scriptResourcePlanningResult: Set<String>?

    init(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        device: MTLDevice,
        sceneGeneration: UInt64,
        dynamicImageModelPaths: Set<String> = [],
        awaitsScriptResourcePlanning: Bool = false,
        deferredBaseImageLayerIDs: Set<Int> = [],
        imageGeometryModels: [SceneAssetCatalog.ModelAsset] = [],
        textureUploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        textureDecodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        ),
        cancellationCheck: @escaping () throws -> Void
    ) {
        self.descriptor = descriptor
        self.resourceView = resourceView
        self.device = device
        self.sceneGeneration = sceneGeneration
        self.textureUploadCommandQueue = textureUploadCommandQueue
        self.textureDecodeCacheBudget = textureDecodeCacheBudget
        scriptResourcePlanningResult = awaitsScriptResourcePlanning ? nil : dynamicImageModelPaths
        self.imageGeometryModels = imageGeometryModels
        self.deferredBaseImageLayerIDs = deferredBaseImageLayerIDs
        externalCancellationCheck = cancellationCheck
    }

    func start() {
        Self.queue.async { [self] in
            let prepared = Result {
                try checkCancellation()
                guard let imageLayerPipeline = SceneImageLayerPipeline(
                    device: device,
                    pixelFormat: descriptor.colorTargetFormat.metalPixelFormat,
                    preparesDepth: descriptor.requiresImageDepthAttachment
                ) else {
                    throw SceneDesktopWallpaperHostLaunchError
                        .requiredImagePipelineUnavailable
                }
                let pipelineRepository = SceneImageEffectPipelineRepository(
                    device: device,
                    pixelFormat: descriptor.colorTargetFormat.metalPixelFormat
                )
                if descriptor.layers.contains(where: { $0.contentKind == "quad" }) {
                    // This is a required fixed compositor state, like the
                    // image state above. Never launch a partially prepared
                    // renderer that could strand a quad/provider transaction.
                    guard pipelineRepository.prepareDirectDraw() else {
                        throw SceneDesktopWallpaperHostLaunchError
                            .requiredImagePipelineUnavailable
                    }
                }
                if descriptor.layers.contains(where: {
                    ($0.colorBlendMode ?? 0) != 0
                }) {
                    _ = pipelineRepository.layerColorBlendState()
                }
                let spriteTextureLoader = SceneMultiImageSpriteTextureLoader()
                let baseImages = try ScenePreparedBaseImageResources.prepare(
                    descriptor: descriptor,
                    resourceView: resourceView,
                    device: device,
                    spriteTextureLoader: spriteTextureLoader,
                    sceneGeneration: sceneGeneration,
                    dynamicImageModelPathsProvider: plannedDynamicImageModelPaths,
                    deferredBaseImageLayerIDs: deferredBaseImageLayerIDs,
                    imageGeometryModels: imageGeometryModels,
                    geometryPrepared: { geometry in
                        condition.lock()
                        geometryResult = .success(geometry)
                        condition.broadcast()
                        condition.unlock()
                    },
                    uploadCommandQueue: textureUploadCommandQueue,
                    decodeCacheBudget: textureDecodeCacheBudget,
                    cancellationCheck: checkCancellation
                )
                let staticModels = try ScenePreparedStaticModelResources.prepare(
                    descriptor: descriptor,
                    resourceView: resourceView,
                    device: device,
                    textureLoader: baseImages.textureLoader,
                    cancellationCheck: checkCancellation
                )
                baseImages.textureLoader.evictDecodedCaches()
                return ScenePreparedDeviceResources(
                    pipelineRepository: pipelineRepository,
                    imageLayerPipeline: imageLayerPipeline,
                    spriteTextureLoader: spriteTextureLoader,
                    baseImages: baseImages,
                    staticModels: staticModels
                )
            }
            condition.lock()
            result = prepared
            if geometryResult == nil {
                geometryResult = prepared.map { _ in [:] }
            }
            condition.broadcast()
            condition.unlock()
        }
    }

    /// Called once by the final admitted Program candidate, including an empty
    /// set. The original worker alone consumes and prepares these resources.
    func completeScriptResourcePlanning(_ modelPaths: Set<String>) {
        condition.lock()
        precondition(scriptResourcePlanningResult == nil)
        scriptResourcePlanningResult = modelPaths
        condition.broadcast()
        condition.unlock()
    }

    private func plannedDynamicImageModelPaths() throws -> Set<String> {
        condition.lock()
        while scriptResourcePlanningResult == nil && !cancellationRequested { condition.wait() }
        let paths = scriptResourcePlanningResult
        condition.unlock()
        try checkCancellation()
        return paths!
    }

    func preparedImageGeometry() throws -> [Int: [Float]] {
        condition.lock()
        while geometryResult == nil && !cancellationRequested { condition.wait() }
        let geometry = geometryResult
        condition.unlock()
        try checkCancellation()
        return try geometry!.get()
    }

    func value() throws -> ScenePreparedDeviceResources {
        condition.lock()
        while result == nil {
            condition.wait()
        }
        let result = result!
        condition.unlock()
        return try result.get()
    }

    func cancel() {
        condition.lock()
        cancellationRequested = true
        condition.broadcast()
        condition.unlock()
    }

    private func checkCancellation() throws {
        condition.lock()
        let cancelled = cancellationRequested
        condition.unlock()
        if cancelled {
            throw CancellationError()
        }
        try externalCancellationCheck()
    }
}

/// Prepares exactly one surface-scoped resolved-material runtime while the
/// launch worker continues compiling SceneScript Programs. The prepared
/// runtime is consumed by the first surface only; later displays still receive
/// independent graph/history/epoch owners.
final class ScenePreparedFirstSurfaceRuntime {
    private let lock = NSLock()
    private var runtime: SceneResolvedMaterialRuntimeBridge?

    init(_ runtime: SceneResolvedMaterialRuntimeBridge) {
        self.runtime = runtime
    }

    func take() -> SceneResolvedMaterialRuntimeBridge? {
        lock.lock()
        defer { lock.unlock() }
        let value = runtime
        runtime = nil
        return value
    }
}

/// Bounded launch worker for the first surface's independent graph runtime and
/// immutable Metal pipeline warmup. Joining it before context publication
/// preserves cancellation and prevents detached runtime owners.
final class ScenePreparedFirstSurfaceRuntimeTask {
    private static let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-first-surface-runtime-preparation",
        qos: .userInitiated
    )

    private let condition = NSCondition()
    private let catalog: SceneResolvedMaterialRuntimeCatalog
    private let capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    private let assets: SceneMaterialAssetTextureCatalog
    private let device: MTLDevice
    private let visibleExecutionRootLayerIDs: Set<Int>
    private let capturesExecutionObservations: Bool
    private let externalCancellationCheck: () throws -> Void
    private var result: Result<SceneResolvedMaterialRuntimeBridge, Error>?
    private var cancellationRequested = false

    init(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        device: MTLDevice,
        visibleExecutionRootLayerIDs: Set<Int>,
        capturesExecutionObservations: Bool,
        cancellationCheck: @escaping () throws -> Void
    ) {
        self.catalog = catalog
        self.capabilities = capabilities
        self.assets = assets
        self.device = device
        self.visibleExecutionRootLayerIDs = visibleExecutionRootLayerIDs
        self.capturesExecutionObservations = capturesExecutionObservations
        externalCancellationCheck = cancellationCheck
    }

    func start() {
        Self.queue.async { [self] in
            let prepared = Result {
                try checkCancellation()
                let runtime = ScenePreparedDeviceResources.makeMaterialRuntime(
                    catalog: catalog,
                    capabilities: capabilities,
                    assets: assets,
                    device: device,
                    visibleExecutionRootLayerIDs:
                        visibleExecutionRootLayerIDs,
                    capturesExecutionObservations:
                        capturesExecutionObservations
                )
                try checkCancellation()
                return runtime
            }
            condition.lock()
            result = prepared
            condition.broadcast()
            condition.unlock()
        }
    }

    func value() throws -> SceneResolvedMaterialRuntimeBridge {
        condition.lock()
        while result == nil {
            condition.wait()
        }
        let result = result!
        condition.unlock()
        return try result.get()
    }

    func cancel() {
        condition.lock()
        cancellationRequested = true
        condition.broadcast()
        condition.unlock()
    }

    private func checkCancellation() throws {
        condition.lock()
        let cancelled = cancellationRequested
        condition.unlock()
        if cancelled {
            throw CancellationError()
        }
        try externalCancellationCheck()
    }
}
