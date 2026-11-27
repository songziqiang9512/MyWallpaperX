import Foundation
import Metal

/// One bounded launch worker overlaps pipeline and initially visible resource
/// preparation with CPU Program/VM compilation. The result is joined before
/// publication; its base-image owner may then service bounded, generation-safe
/// on-demand Combo alternatives until the scene context is cancelled.
final class ScenePreparedDeviceResourcesTask {
    struct Planning {
        let dynamicImageModelPaths: Set<String>
        var hasStatefulLayerMutationOwner = false
        var automaticMipConstraints: ScenePreparedBaseImageResources.AutomaticMipConstraints?
        var scalableEffectColorLayerIDs: Set<Int> = []
        let modelMaterialPlan: ScenePreparedStaticModelResources.MaterialPlan
        let modelAlbedoStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    }

    private static let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-device-resource-preparation",
        qos: .userInitiated
    )

    private let condition = NSCondition()
    private let descriptor: SceneRenderDescriptor
    private let directionalShadowDimensionLimit: Int?
    private let pointVolumeQuality: SceneVolumeLightingQuality
    private let modelReflectionsEnabled: Bool
    private let rasterSampleCount: Int
    private let ordinaryColorMipLongEdge: Int?
    private let automaticMipDensity: Double?
    private let resourceView: SceneResourceView
    private let device: MTLDevice
    private let cacheDirectory: URL
    private let effectivePropertyValues: [String: SceneUserPropertyValue]
    private let imageGeometryModels: [SceneAssetCatalog.ModelAsset]
    private let deferredBaseImageLayerIDs: Set<Int>
    private let sceneGeneration: UInt64
    private let textureUploadCommandQueue: SceneTextureUploadCommandQueue
    private let textureDecodeCacheBudget: SceneTextureDecodeCacheBudget
    private let externalCancellationCheck: () throws -> Void
    private var result: Result<ScenePreparedDeviceResources, Error>?
    private var geometryResult: Result<[Int: [Float]], Error>?
    private var cancellationRequested = false
    private var resourcePlanningResult: Planning?
    private var preparedStaticModels: [String: SceneMdlStaticModel.PreparedSource]

    init(
        descriptor: SceneRenderDescriptor,
        directionalShadowDimensionLimit: Int?,
        pointVolumeQuality: SceneVolumeLightingQuality,
        modelReflectionsEnabled: Bool,
        rasterSampleCount: Int = 1,
        ordinaryColorMipLongEdge: Int? = nil,
        automaticMipDensity: Double? = nil,
        resourceView: SceneResourceView,
        device: MTLDevice,
        sceneGeneration: UInt64,
        cacheDirectory: URL,
        effectivePropertyValues: [String: SceneUserPropertyValue] = [:],
        deferredBaseImageLayerIDs: Set<Int> = [],
        imageGeometryModels: [SceneAssetCatalog.ModelAsset] = [],
        preparedStaticModels: [String: SceneMdlStaticModel.PreparedSource] = [:],
        textureUploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        textureDecodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        ),
        cancellationCheck: @escaping () throws -> Void
    ) {
        self.descriptor = descriptor
        self.directionalShadowDimensionLimit = directionalShadowDimensionLimit
        self.pointVolumeQuality = pointVolumeQuality
        self.modelReflectionsEnabled = modelReflectionsEnabled
        self.rasterSampleCount = rasterSampleCount
        self.ordinaryColorMipLongEdge = ordinaryColorMipLongEdge
        self.automaticMipDensity = automaticMipDensity
        self.resourceView = resourceView
        self.device = device
        self.cacheDirectory = cacheDirectory
        self.effectivePropertyValues = effectivePropertyValues
        self.sceneGeneration = sceneGeneration
        self.textureUploadCommandQueue = textureUploadCommandQueue
        self.textureDecodeCacheBudget = textureDecodeCacheBudget
        self.imageGeometryModels = imageGeometryModels
        self.preparedStaticModels = preparedStaticModels
        self.deferredBaseImageLayerIDs = deferredBaseImageLayerIDs
        externalCancellationCheck = cancellationCheck
    }

    func start() {
        Self.queue.async { [self] in
            let prepared = Result {
                defer { preparedStaticModels.removeAll() }
                try checkCancellation()
                let preparesModelMultisampling = rasterSampleCount > 1
                    && descriptor.layers.contains { $0.contentKind == "model" }
                let preparesOrdinaryMultisampling = rasterSampleCount > 1
                    && descriptor.layers.contains {
                        $0.contentKind == "image" || $0.contentKind == "solid"
                            || (preparesModelMultisampling && $0.contentKind == "text")
                    }
                let imageRasterSampleCount = preparesOrdinaryMultisampling ? rasterSampleCount : 1
                guard let imageLayerPipeline = SceneImageLayerPipeline(
                    device: device,
                    pixelFormat: descriptor.colorTargetFormat.metalPixelFormat,
                    preparesDepth: descriptor.requiresImageDepthAttachment,
                    preparesAdditive: descriptor.requiresImageAdditiveRGB,
                    preparesNormalDepth: descriptor.requiresImageNormalDepth,
                    rasterSampleCount: imageRasterSampleCount,
                    preparesMultisampleSeed: preparesModelMultisampling
                ) else {
                    throw SceneDesktopWallpaperHostLaunchError
                        .requiredImagePipelineUnavailable
                }
                let pipelineRepository = SceneImageEffectPipelineRepository(
                    device: device,
                    pixelFormat: descriptor.colorTargetFormat.metalPixelFormat,
                    usesSixPointQuadrature: pointVolumeQuality == .ultra
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
                    cacheDirectory: cacheDirectory,
                    effectivePropertyValues: effectivePropertyValues,
                    dynamicImageRequestsProvider: plannedDynamicImageRequests,
                    deferredBaseImageLayerIDs: deferredBaseImageLayerIDs,
                    imageGeometryModels: imageGeometryModels,
                    ordinaryColorMipLongEdge: ordinaryColorMipLongEdge,
                    automaticMipDensity: automaticMipDensity,
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
                if !baseImages.puppetClipping.isEmpty {
                    _ = pipelineRepository.preparePuppetClipping()
                }
                let planning = resourcePlanningResult!
                let staticModels = try ScenePreparedStaticModelResources.prepare(
                    descriptor: descriptor,
                    directionalShadowDimensionLimit: directionalShadowDimensionLimit,
                    pointVolumeEnabled: pointVolumeQuality.isEnabled,
                    modelReflectionsEnabled: modelReflectionsEnabled,
                    rasterSampleCount: rasterSampleCount,
                    resourceView: resourceView,
                    device: device,
                    textureLoader: baseImages.textureLoader,
                    materialPlan: planning.modelMaterialPlan,
                    albedoStates: planning.modelAlbedoStates,
                    preparedSources: &preparedStaticModels,
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

    /// The launch compiler publishes one plan after its final Program candidate.
    /// The original worker alone consumes and prepares these resources.
    func completeResourcePlanning(_ planning: Planning) {
        condition.lock()
        precondition(resourcePlanningResult == nil)
        resourcePlanningResult = planning
        condition.broadcast()
        condition.unlock()
    }

    private func plannedDynamicImageRequests() throws -> ScenePreparedBaseImageResources.ImagePlanning {
        condition.lock()
        while resourcePlanningResult == nil && !cancellationRequested { condition.wait() }
        let planning = resourcePlanningResult
        condition.unlock()
        try checkCancellation()
        return .init(models: planning!.dynamicImageModelPaths,
            retainsModelDefaultAliases: planning!.hasStatefulLayerMutationOwner,
            automaticMipConstraints: planning!.automaticMipConstraints,
            scalableEffectColorLayerIDs: planning!.scalableEffectColorLayerIDs)
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
