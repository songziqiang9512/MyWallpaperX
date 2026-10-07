import Foundation
import Metal

struct ScenePreparedDynamicImageResource {
    let modelPath: String
    let loaded: SceneBaseImageTextureLoad.Loaded

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
/// puppet, video, and other surface-scoped providers keep their lifecycle owners.
final class ScenePreparedBaseImageResources {
    private struct Entry {
        let source: SceneTextureLoader.SourceKey
        let outcome: SceneBaseImageTextureLoad.Outcome
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
        deferredBaseImageLayerIDs: Set<Int> = [],
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
        var entries: [Int: Entry] = [:]
        var loadedCount = 0
        var failedCount = 0
        var deferredRequests: [Int: DeferredRequest] = [:]
        // AS2 experiment 1: every mipmap generation in this load pass joins
        // one command buffer, committed and awaited once after the loops.
        uploadCommandQueue.beginMipmapBatch()
        for layer in descriptor.layers where layer.isImageRenderable {
            try cancellationCheck()
            guard layer.contentKind != "solid",
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
                usesPuppet: layer.puppetMeshPath != nil
            ) == nil else {
                continue
            }
            if deferredBaseImageLayerIDs.contains(layer.id) {
                deferredRequests[layer.id] = .init(
                    layerID: layer.id,
                    url: url,
                    source: source
                )
                continue
            }
            let outcome = SceneBaseImageTextureLoad.load(
                from: url,
                usesPuppet: false,
                loader: textureLoader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
            switch outcome {
            case .loaded:
                entries[layer.id] = .init(source: source, outcome: outcome)
                loadedCount += 1
            case .failed:
                failedCount += 1
            }
        }
        var dynamicImageResources: [String: ScenePreparedDynamicImageResource] = [:]
        for modelPath in dynamicImageModelPaths.sorted() {
            try cancellationCheck()
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
                    modelPath: modelPath, loaded: loaded
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
            func isFailed(_ outcome: SceneBaseImageTextureLoad.Outcome) -> Bool {
                guard case let .loaded(loaded) = outcome else { return false }
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
        // Every launch texture is GPU-published past this point: drop the
        // loader's CPU-side decoded bytes so they do not sit next to their
        // GPU copies for the whole session. Later loads hit the GPU cache;
        // a miss re-decodes from the source file.
        textureLoader.evictDecodedCaches()
        return ScenePreparedBaseImageResources(
            textureLoader: textureLoader,
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
        if let prepared = entries[layerID] {
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
                    outcome: outcome
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
        "prepared static base resources: entries=\(entries.count)"
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

    private static func prepareSourceMaterialPrograms(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        device: MTLDevice,
        encoder: SceneResolvedMaterialPassEncoder?,
        logSink: SceneResolvedMaterialRuntimeBridge.LogSink
    ) -> [Int: SceneResolvedMaterialRuntimeBridge.PreparedSourceMaterial] {
        guard let encoder else { return [:] }
        let format = catalog.sourceMaterialTargetFormat.metalPixelFormat
        var prepared: [Int: SceneResolvedMaterialRuntimeBridge.PreparedSourceMaterial] = [:]
        for (layerID, entry) in catalog.sourceMaterialEntries.sorted(by: { $0.key < $1.key }) {
            func reject(_ reason: String) {
                logSink("source material unavailable: owner=\(entry.key.reportToken) reason=\(reason)")
            }
            guard case let .template(template) = entry.entry else {
                if case let .failure(failure) = entry.entry { reject(String(describing: failure)) }
                continue
            }
            guard case let .success(variants) = SceneResolvedMaterialVariantCache.launchValidated(
                template: template, maximumVariantCount: 32, assetFormatFacts: assets.launchFormatFacts
            ) else { reject("variant-schema"); continue }
            switch variants.precompileLaunchEnvelope(
                implicitFramebufferIdentity: nil,
                outputIsRGBA8Unorm: format != .rgba16Float,
                assetStates: assets.launchStates
            ) {
            case let .failure(failure): reject(String(describing: failure)); continue
            case .success: break
            }
            let envelope = variants.launchEnvelopeCapabilitySnapshot()
            guard envelope.allEntriesReady, !envelope.variants.isEmpty else {
                reject("variant-envelope-incomplete"); continue
            }
            // Source geometry inherits the selected slot-zero asset domain,
            // not the separately cropped ordinary-image upload. All admitted
            // variants must agree on that static source representation.
            guard let reference = template.textureSlots.first??.candidates.last?.reference,
                  case let .asset(path) = reference else {
                reject("source-domain-unavailable"); continue
            }
            let purposes = envelope.variants.compactMap {
                $0.activeSamplers[0]?.purpose(for: reference)
            }
            guard purposes.count == envelope.variants.count,
                  Set(purposes).count == 1, let purpose = purposes.first else {
                reject("source-domain-variant-dependent"); continue
            }
            let sourceIdentity = SceneAssetTextureIdentity(path: path, purpose: purpose)
            let plans = envelope.variants.compactMap { variant in
                SceneResolvedMaterialPassEncoder.WarmupPlan(
                    identity: entry.key.reportToken, preparedKey: variant.preparedShader.cacheKey,
                    frontend: variant.frontendProgram, renderState: template.renderState,
                    frontendSchemaVersion: variant.preparedShader.vertex.frontendSchemaVersion,
                    pixelFormat: format, writeMask: .all, device: device)
            }
            guard plans.count == envelope.variants.count else {
                reject("pipeline-plan-incomplete"); continue
            }
            let report = encoder.warmup(plans)
            guard report.failedKeyCount == 0, report.readyKeyCount > 0 else {
                reject("pipeline-warmup"); continue
            }
            prepared[layerID] = .init(template: template, bindFrame: { input in
                SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: variants)
            }, pixelFormat: format, sourceIdentity: sourceIdentity)
            logSink("source material prepared: owner=\(entry.key.reportToken) variants=\(envelope.variants.count)")
        }
        return prepared
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
    private let dynamicImageModelPaths: Set<String>
    private let deferredBaseImageLayerIDs: Set<Int>
    private let sceneGeneration: UInt64
    private let textureUploadCommandQueue: SceneTextureUploadCommandQueue
    private let textureDecodeCacheBudget: SceneTextureDecodeCacheBudget
    private let externalCancellationCheck: () throws -> Void
    private var result: Result<ScenePreparedDeviceResources, Error>?
    private var cancellationRequested = false

    init(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        device: MTLDevice,
        sceneGeneration: UInt64,
        dynamicImageModelPaths: Set<String> = [],
        deferredBaseImageLayerIDs: Set<Int> = [],
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
        self.dynamicImageModelPaths = dynamicImageModelPaths
        self.deferredBaseImageLayerIDs = deferredBaseImageLayerIDs
        externalCancellationCheck = cancellationCheck
    }

    func start() {
        Self.queue.async { [self] in
            let prepared = Result {
                try checkCancellation()
                guard let imageLayerPipeline = SceneImageLayerPipeline(
                    device: device,
                    pixelFormat: descriptor.colorTargetFormat.metalPixelFormat
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
                    dynamicImageModelPaths: dynamicImageModelPaths,
                    deferredBaseImageLayerIDs: deferredBaseImageLayerIDs,
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
            condition.broadcast()
            condition.unlock()
        }
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
