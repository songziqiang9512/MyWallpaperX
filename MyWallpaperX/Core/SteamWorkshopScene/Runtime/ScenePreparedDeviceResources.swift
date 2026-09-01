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
    private let deferredTextureLoader = SceneTextureLoader()
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
        cancellationCheck: () throws -> Void
    ) throws -> ScenePreparedBaseImageResources {
        let textureLoader = SceneTextureLoader()
        let resolver = SceneTexturePathResolver(
            resourceView: resourceView,
            descriptor: descriptor
        )
        var entries: [Int: Entry] = [:]
        var loadedCount = 0
        var failedCount = 0
        var deferredRequests: [Int: DeferredRequest] = [:]
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

    var device: MTLDevice { pipelineRepository.device }
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
        cancellationCheck: @escaping () throws -> Void
    ) {
        self.descriptor = descriptor
        self.resourceView = resourceView
        self.device = device
        self.sceneGeneration = sceneGeneration
        self.dynamicImageModelPaths = dynamicImageModelPaths
        self.deferredBaseImageLayerIDs = deferredBaseImageLayerIDs
        externalCancellationCheck = cancellationCheck
    }

    func start() {
        Self.queue.async { [self] in
            let prepared = Result {
                try checkCancellation()
                guard let imageLayerPipeline = SceneImageLayerPipeline(
                    device: device
                ) else {
                    throw SceneDesktopWallpaperHostLaunchError
                        .requiredImagePipelineUnavailable
                }
                let pipelineRepository = SceneImageEffectPipelineRepository(
                    device: device
                )
                let spriteTextureLoader = SceneMultiImageSpriteTextureLoader()
                let baseImages = try ScenePreparedBaseImageResources.prepare(
                    descriptor: descriptor,
                    resourceView: resourceView,
                    device: device,
                    spriteTextureLoader: spriteTextureLoader,
                    sceneGeneration: sceneGeneration,
                    dynamicImageModelPaths: dynamicImageModelPaths,
                    deferredBaseImageLayerIDs: deferredBaseImageLayerIDs,
                    cancellationCheck: checkCancellation
                )
                return ScenePreparedDeviceResources(
                    pipelineRepository: pipelineRepository,
                    imageLayerPipeline: imageLayerPipeline,
                    spriteTextureLoader: spriteTextureLoader,
                    baseImages: baseImages
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
    private let externalCancellationCheck: () throws -> Void
    private var result: Result<SceneResolvedMaterialRuntimeBridge, Error>?
    private var cancellationRequested = false

    init(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        device: MTLDevice,
        visibleExecutionRootLayerIDs: Set<Int>,
        cancellationCheck: @escaping () throws -> Void
    ) {
        self.catalog = catalog
        self.capabilities = capabilities
        self.assets = assets
        self.device = device
        self.visibleExecutionRootLayerIDs = visibleExecutionRootLayerIDs
        externalCancellationCheck = cancellationCheck
    }

    func start() {
        Self.queue.async { [self] in
            let prepared = Result {
                try checkCancellation()
                let runtime = SceneResolvedMaterialRuntimeBridge(
                    catalog: catalog,
                    capabilities: capabilities,
                    assets: assets,
                    device: device,
                    visibleExecutionRootLayerIDs:
                        visibleExecutionRootLayerIDs
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
