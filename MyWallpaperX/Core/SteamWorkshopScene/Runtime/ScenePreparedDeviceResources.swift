import Foundation
import Metal

struct ScenePreparedDynamicImageResource {
    let modelPath: String
    let loaded: SceneBaseImageTextureLoad.Loaded

    var renderSizeWH: [Float] {
        [Float(loaded.texture.width), Float(loaded.texture.height)]
    }
}

/// Immutable, device-bound ordinary base images prepared before AppKit surface
/// activation. Animated, puppet, video, and other surface-scoped providers are
/// deliberately excluded and keep their existing lifecycle owners.
final class ScenePreparedBaseImageResources {
    private struct Entry {
        let source: SceneTextureLoader.SourceKey
        let outcome: SceneBaseImageTextureLoad.Outcome
    }

    let textureLoader: SceneTextureLoader
    private let deviceRegistryID: UInt64
    private let entries: [Int: Entry]
    let dynamicImageResources: [String: ScenePreparedDynamicImageResource]
    let loadedCount: Int
    let failedCount: Int

    private init(
        textureLoader: SceneTextureLoader,
        deviceRegistryID: UInt64,
        entries: [Int: Entry],
        dynamicImageResources: [String: ScenePreparedDynamicImageResource],
        loadedCount: Int,
        failedCount: Int
    ) {
        self.textureLoader = textureLoader
        self.deviceRegistryID = deviceRegistryID
        self.entries = entries
        self.dynamicImageResources = dynamicImageResources
        self.loadedCount = loadedCount
        self.failedCount = failedCount
    }

    static func prepare(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        device: MTLDevice,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        dynamicImageModelPaths: Set<String> = [],
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
            deviceRegistryID: device.registryID,
            entries: entries,
            dynamicImageResources: dynamicImageResources,
            loadedCount: loadedCount,
            failedCount: failedCount
        )
    }

    func outcome(
        for layerID: Int,
        url: URL,
        device: MTLDevice
    ) -> SceneBaseImageTextureLoad.Outcome? {
        guard device.registryID == deviceRegistryID,
              let entry = entries[layerID],
              textureLoader.sourceKey(for: url) == entry.source else {
            return nil
        }
        return entry.outcome
    }

    var reportLine: String {
        "prepared static base resources: entries=\(entries.count)"
            + " dynamicImages=\(dynamicImageResources.count)"
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

/// One bounded worker overlaps all immutable, device-bound launch resources
/// with CPU Program/VM compilation. The result is joined before the launch
/// context can be published, so no detached resource owner survives commit.
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
    private let externalCancellationCheck: () throws -> Void
    private var result: Result<ScenePreparedDeviceResources, Error>?
    private var cancellationRequested = false

    init(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        device: MTLDevice,
        dynamicImageModelPaths: Set<String> = [],
        cancellationCheck: @escaping () throws -> Void
    ) {
        self.descriptor = descriptor
        self.resourceView = resourceView
        self.device = device
        self.dynamicImageModelPaths = dynamicImageModelPaths
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
                    dynamicImageModelPaths: dynamicImageModelPaths,
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
