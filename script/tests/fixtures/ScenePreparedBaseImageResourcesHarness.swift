import Foundation
import Metal

// Controlled decoder/upload boundaries. The production preparation owner and
// path resolver compile whole below; actual MTLTexture identities are observed.
struct SceneResourceView {
    let projectRootURL: URL
    let packageRootURL: URL?
    var primaryRootURL: URL { packageRootURL ?? projectRootURL }
    struct Resource { let url: URL }
    func resource(relativePath: String) -> Resource? {
        let url = projectRootURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? .init(url: url) : nil
    }
}

struct SceneAssetCatalog {
    struct ModelAsset {
        let relativePath: String
        var autosize: Bool? = nil
        var declaredSizeWH: [Float]? = nil
        var hasDeclaredSizeFields = false
        var puppetPath: String? = nil
    }
}
// Puppet model parsing is outside this controlled ordinary-image ownership
// gate. The complete CPU preparation contract has its own production-source gate.
enum ScenePuppetLayerLoad { struct PreparedPose {} }
struct ScenePreparedPuppetResources {
    static func prepare(descriptor: SceneRenderDescriptor, cacheDirectory: URL,
                        cancellationCheck: () throws -> Void) throws -> Self {
        try cancellationCheck(); return .init()
    }
    func defaultPose(for layer: SceneRenderDescriptor.Layer) -> ScenePuppetLayerLoad.PreparedPose? { nil }
}
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        var contentKind = "image"
        var imagePath: String? = "models/shared.json"
        var staticBaseTexturePath: String? = nil
        var puppetMeshPath: String? = nil
        var colorBlendMode: Int? = nil
        var initialConfiguration: SceneJSONValue? = nil
        var size: String? = "3 4"
        var sizeWH: [Float]? = [3, 4]
        var isImageRenderable: Bool { ["image", "solid"].contains(contentKind) }
    }
    struct ModelMaterialLink { let modelPath: String; let materialPath: String? }
    struct MaterialPass {
        let materialPath: String
        let texturePaths: [String]
        var textureSlots: [String?]
        var passIndex = 0
        var shaderPath: String? = "genericimage2"
        var userTextureInputs: [String?] = []
        var constantShaderValues: [String: Float] = [:]
        var userShaderValues: [String: String] = [:]
        var combos = ["VERSION": 2]
        var blending: String? = "translucent"
        var depthTest: String? = "disabled"
        var depthWrite: String? = "disabled"
        var cullMode: String? = "nocull"
        var alphaWriting: String? = nil
    }
    typealias MaterialPassDescriptor = MaterialPass
    var layers: [Layer]
    var modelMaterialLinks: [ModelMaterialLink] = [
        .init(modelPath: "models/shared.json", materialPath: "materials/shared.json")
    ]
    var materialPasses: [MaterialPass]
    var colorTargetFormat = TestColorFormat()
}
// Material-value compilation has its own production-source gate. This owner
// gate controls only its result; no shader, light or pixel behavior is claimed.
struct SceneBaseMaterialLightingProfile {
    let lightingEnabled: Bool
    var surfaceEnabled: Bool { lightingEnabled }
}
enum SceneBaseMaterialLightingProfileCompiler {
    static func profile(layerID: Int, usesPuppet: Bool, materialInstance: Never?,
        materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor],
        materialPropertyTargets: Set<Int>, builtinSurface: Bool) -> SceneBaseMaterialLightingProfile {
        .init(lightingEnabled: materialPasses.first?.combos["LIGHTING"] == 1)
    }
}
enum SceneMaterialPropertyBindingCompiler {
    static func staticComponents(_ key: String, instance: Never?,
        pass: SceneRenderDescriptor.MaterialPassDescriptor, count: Int,
        fallback: [Double], requiresCompleteScalar: Bool) -> [Double]? {
        guard let value = pass.constantShaderValues[key] else { return fallback }
        return value.isFinite ? [Double(value)] : nil
    }
}
struct TestColorFormat { let metalPixelFormat: MTLPixelFormat = .rgba16Float }
struct SceneTextureDecodeCacheBudget { let maximumBytes: Int }
final class SceneMultiImageSpriteTextureLoader {}

final class SceneTextureUploadCommandQueue {
    struct Flush { let failedTextures: [MTLTexture] }
    var failedTextures: [MTLTexture] = []
    func beginMipmapBatch() {}
    func flushMipmapBatch() -> Flush { .init(failedTextures: failedTextures) }
    func flushUncommittedCommandBuffers() -> [MTLTexture] { [] }
}

enum SceneTextureLoadOutcome {
    case loaded, unsupportedFormat, unsupportedTexFormat, texNoEmbeddedImage
    case texContainsVideoPayload, decodeFailed, textureAllocationFailed
}
struct TestCandidate {
    let texture: MTLTexture
    let loadOrdinal: Int
    let samplingMarker = "authored-sampling"
}
struct TestContainer {
    var reason: String? = nil
    var isVideoMp4 = false
}
struct SceneBaseImageTextureLoad {
    struct Loaded {
        let texture: MTLTexture
        let candidate: TestCandidate?
        let animation: String?
        let loadOrdinal: Int
    }
    enum Outcome { case loaded(Loaded), failed(SceneTextureLoadOutcome) }
    static func specializedLoadReason(url: URL, container: TestContainer?, usesPuppet: Bool) -> String? {
        if usesPuppet { return "puppet" }
        return container?.reason
    }
    static func load(from url: URL, usesPuppet: Bool, loader: SceneTextureLoader,
                     spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
                     device: MTLDevice) -> Outcome {
        loader.controlledLoad(url: url, device: device)
    }
}

final class SceneTextureLoader {
    struct SourceKey: Equatable { let path: String; let bytes: UInt64 }
    let uploadCommandQueue: SceneTextureUploadCommandQueue
    let decodeCacheBudget: SceneTextureDecodeCacheBudget
    static var totalLoadCount = 0
    var loadCount = 0
    var evictionCount = 0
    private var textures: [String: MTLTexture] = [:]
    init(uploadCommandQueue: SceneTextureUploadCommandQueue, decodeCacheBudget: SceneTextureDecodeCacheBudget) {
        self.uploadCommandQueue = uploadCommandQueue
        self.decodeCacheBudget = decodeCacheBudget
    }
    func sourceKey(for url: URL) -> SourceKey? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attributes[.size] as? NSNumber else { return nil }
        return .init(path: url.standardizedFileURL.path, bytes: bytes.uint64Value)
    }
    func texContainer(from url: URL, source: SourceKey) -> TestContainer? {
        if url.lastPathComponent == "animated.tex" { return .init(reason: "animation") }
        if url.lastPathComponent == "video.tex" { return .init(isVideoMp4: true) }
        return nil
    }
    func preparedNaturalImageSize(from url: URL, source: SourceKey) -> CGSize? {
        // Controlled source metadata deliberately differs from the uploaded 2x1 texture.
        guard source == sourceKey(for: url) else { return nil }
        return CGSize(width: 20, height: 10)
    }
    func controlledLoad(url: URL, device: MTLDevice) -> SceneBaseImageTextureLoad.Outcome {
        loadCount += 1
        Self.totalLoadCount += 1
        let name = url.lastPathComponent
        if name == "decode-failure.png" { return .failed(.decodeFailed) }
        if name == "video.tex" { return .failed(.texContainsVideoPayload) }
        let texture: MTLTexture
        if let cached = textures[url.path] { texture = cached }
        else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
            descriptor.storageMode = .shared
            guard let allocated = device.makeTexture(descriptor: descriptor) else {
                return .failed(.textureAllocationFailed)
            }
            texture = allocated
            textures[url.path] = texture
        }
        if name == "upload-failure.png" { uploadCommandQueue.failedTextures.append(texture) }
        let candidateTexture = name == "mismatched-candidate.png"
            ? device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))! : texture
        let candidate: TestCandidate? = name == "no-candidate.png" ? nil
            : .init(texture: candidateTexture, loadOrdinal: loadCount)
        return .loaded(.init(texture: texture, candidate: candidate,
            animation: name == "loaded-animation.png" ? "animation" : nil, loadOrdinal: loadCount))
    }
    func evictTextures(containedIn failed: [MTLTexture]) {
        evictionCount += failed.count
        textures = textures.filter { entry in !failed.contains { $0 === entry.value } }
    }
    func evictDecodedCaches() {}
}

// External boundaries for the whole production preparation owners. The source
// material cases below exercise the actual prepareSourceMaterialPrograms method;
// shader compilation, pipeline creation and draws remain controlled, not tested.
enum SceneDesktopWallpaperHostLaunchError: Error { case requiredImagePipelineUnavailable }
final class SceneImageLayerPipeline {
    static var reject = false
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        if Self.reject { return nil }
    }
}
final class SceneImageEffectPipelineRepository {
    let device: MTLDevice
    init(device: MTLDevice, pixelFormat: MTLPixelFormat) { self.device = device }
    func prepareDirectDraw() -> Bool { true }
    func layerColorBlendState() -> Int { 0 }
}
struct ScenePreparedStaticModelResources {
    static func prepare(descriptor: SceneRenderDescriptor, resourceView: SceneResourceView,
                        device: MTLDevice, textureLoader: SceneTextureLoader,
                        cancellationCheck: () throws -> Void) throws -> Self { .init() }
}
struct SceneResolvedMaterialExecutionCapabilityCatalog {}
struct SceneAssetTextureIdentity { let path: String; let purpose: String }
enum TestReference: Hashable { case asset(String), unavailable }
struct TestSampler {
    // Prepared typed facts supplied by the external compiler boundary. This
    // does not replace or test production shader-purpose derivation.
    let purposes: [TestReference: String]
    func purpose(for reference: TestReference) -> String? { purposes[reference] }
}
struct TestTemplate {
    struct Slot { struct Candidate { let reference: TestReference }; let candidates: [Candidate] }
    let textureSlots: [Slot?]
    let renderState: Int
    var fixture = TestVariantFixture()
}
struct TestVariantFixture {
    var schemaAccepted = true
    var precompileAccepted = true
    var allEntriesReady = true
    var variants: [SceneResolvedMaterialVariantCache.Variant] = []
}
struct SceneResolvedMaterialRuntimeCatalog {
    struct Entry {
        struct Key { let reportToken: String }
        enum Value { case template(TestTemplate), failure(String) }
        let key: Key
        let entry: Value
        let sharedModelPath: String?
    }
    let sourceMaterialTargetFormat = TestColorFormat()
    var sourceMaterialEntries: [Int: Entry] = [:]
}
struct SceneMaterialAssetTextureCatalog { let launchFormatFacts = 0; let launchStates = 0 }
struct SceneResolvedMaterialVariantCache {
    struct Frontend { let planAvailable: Bool }
    struct Variant {
        struct Shader {
            struct Vertex { let frontendSchemaVersion: Int }
            let cacheKey: String
            let vertex: Vertex
        }
        let activeSamplers: [Int: TestSampler]
        let preparedShader: Shader
        let frontendProgram: Frontend
    }
    struct Envelope { let allEntriesReady: Bool; let variants: [Variant] }
    let fixture: TestVariantFixture
    static func launchValidated(template: TestTemplate, maximumVariantCount: Int,
                                assetFormatFacts: Int) -> Result<Self, TestError> {
        template.fixture.schemaAccepted ? .success(.init(fixture: template.fixture))
            : .failure(.controlledSchemaFailure)
    }
    func precompileLaunchEnvelope(implicitFramebufferIdentity: String?, outputIsRGBA8Unorm: Bool,
                                 assetStates: Int) -> Result<Void, TestError> {
        fixture.precompileAccepted ? .success(()) : .failure(.controlledPrecompileFailure)
    }
    func launchEnvelopeCapabilitySnapshot() -> Envelope {
        .init(allEntriesReady: fixture.allEntriesReady, variants: fixture.variants)
    }
}
enum TestError: Error { case controlledSchemaFailure, controlledPrecompileFailure }
final class SceneResolvedMaterialPassEncoder {
    struct WarmupPlan {
        init?(identity: String, preparedKey: String,
              frontend: SceneResolvedMaterialVariantCache.Frontend, renderState: Int,
              frontendSchemaVersion: Int, pixelFormat: MTLPixelFormat,
              writeMask: MTLColorWriteMask, device: MTLDevice) {
            // Fault injection at the external pipeline boundary only.
            guard frontend.planAvailable else { return nil }
        }
    }
    struct Report { let failedKeyCount: Int; let readyKeyCount: Int }
    var reportOverride: Report?
    private(set) var warmupCalls = 0
    private(set) var warmupPlanCount = 0
    func warmup(_ plans: [WarmupPlan]) -> Report {
        warmupCalls += 1
        warmupPlanCount += plans.count
        return reportOverride ?? .init(failedKeyCount: 0, readyKeyCount: plans.count)
    }
}
struct SceneResolvedMaterialProgramFinalizer {
    static func finalize(_ input: Int, variantCache: SceneResolvedMaterialVariantCache) -> Int { input }
}
final class SceneResolvedMaterialRuntimeBridge {
    typealias LogSink = (String) -> Void
    struct PreparedSourceMaterial {
        enum OutputDomain { case sampledAsset(SceneAssetTextureIdentity), baseImage }
        let outputDomain: OutputDomain
        let sharedModelPath: String?
        init(template: TestTemplate, bindFrame: @escaping (Int) -> Int, pixelFormat: MTLPixelFormat,
             outputDomain: OutputDomain, sharedModelPath: String?) {
            self.outputDomain = outputDomain
            self.sharedModelPath = sharedModelPath
        }
    }
    struct Submissions {
        struct Executor { let materialEncoder: SceneResolvedMaterialPassEncoder? }
        let executor: Executor? = nil
        let logSink: LogSink = { _ in }
    }
    let submissions = Submissions()
    var sourceMaterials: [Int: PreparedSourceMaterial] = [:]
    init(catalog: SceneResolvedMaterialRuntimeCatalog,
         capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
         assets: SceneMaterialAssetTextureCatalog, device: MTLDevice,
         visibleExecutionRootLayerIDs: Set<Int>, capturesExecutionObservations: Bool) {}
}

@main
enum Checks {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"skip\":\"native Metal device unavailable\"}"); return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("materials"),
                                               withIntermediateDirectories: true)
        let names = ["canonical.png", "override.png", "animated.tex", "video.tex", "decode-failure.png",
                     "upload-failure.png", "no-candidate.png", "mismatched-candidate.png", "loaded-animation.png"]
        for name in names {
            try Data(name.utf8).write(to: root.appendingPathComponent("materials/" + name))
        }
        var results: [String: [String: Any]] = [:]
        func check(_ name: String, layers: [SceneRenderDescriptor.Layer], texture: String = "canonical.png",
                   explicit: Set<String> = [], deferred: Set<Int> = [],
                   models: [SceneAssetCatalog.ModelAsset] = [],
                   editDescriptor: ((inout SceneRenderDescriptor) -> Void)? = nil) throws {
            let texturePath = "materials/" + texture
            var descriptor = SceneRenderDescriptor(layers: layers, materialPasses: [
                .init(materialPath: "materials/shared.json", texturePaths: [texturePath], textureSlots: [texturePath])
            ])
            editDescriptor?(&descriptor)
            for index in descriptor.layers.indices where descriptor.layers[index].initialConfiguration == nil {
                descriptor.layers[index].initialConfiguration = .object(
                    descriptor.layers[index].size.map { ["size": .string($0)] } ?? [:])
            }
            let view = SceneResourceView(projectRootURL: root, packageRootURL: nil)
            let resolver = SceneTexturePathResolver(resourceView: view, descriptor: descriptor)
            var geometry: [Int: [Float]] = [:]
            var loadsAtGeometry = -1
            let loadsBeforeGeometry = SceneTextureLoader.totalLoadCount
            let prepared = try ScenePreparedBaseImageResources.prepare(descriptor: descriptor,
                resourceView: view, device: device, spriteTextureLoader: .init(), sceneGeneration: 1,
                dynamicImageModelPaths: explicit, deferredBaseImageLayerIDs: deferred,
                imageGeometryModels: models, geometryPrepared: { geometry = $0; loadsAtGeometry = SceneTextureLoader.totalLoadCount - loadsBeforeGeometry },
                cancellationCheck: {})
            defer { prepared.cancelDeferredPreparation() }
            let resource = prepared.dynamicImageResources["models/shared.json"]
            func loaded(_ layer: SceneRenderDescriptor.Layer) -> SceneBaseImageTextureLoad.Loaded? {
                guard let url = resolver.resolvePrimaryTexture(for: layer),
                      case let .loaded(value)? = prepared.outcome(for: layer.id, url: url, device: device)
                else { return nil }
                return value
            }
            let first = layers.first.flatMap(loaded)
            let second = layers.dropFirst().first.flatMap(loaded)
            let sameCandidate = resource?.loaded.candidate?.loadOrdinal == first?.candidate?.loadOrdinal
                && resource?.loaded.candidate?.samplingMarker == first?.candidate?.samplingMarker
            results[name] = [
                "geometry": Dictionary(uniqueKeysWithValues: geometry.map { (String($0.key), $0.value) }),
                "geometryPublished": loadsAtGeometry == 0,
                "loads": prepared.textureLoader.loadCount, "loadedCount": prepared.loadedCount,
                "failedCount": prepared.failedCount, "dynamicCount": prepared.dynamicImageResources.count,
                "sameTexture": resource != nil && first != nil && resource!.loaded.texture === first!.texture,
                "sameCandidate": resource != nil && first != nil && sameCandidate,
                "sameCanonicalTexture": resource != nil && second != nil && resource!.loaded.texture === second!.texture,
                "differentOverrideTexture": resource != nil && first != nil && resource!.loaded.texture !== first!.texture,
                "size": resource?.renderSizeWH ?? [],
                "naturalSize": resource?.naturalSizeWH ?? [], "hasOutcome": first != nil,
                "evicted": prepared.textureLoader.evictionCount,
                "pending": layers.first.map { prepared.deferredStatus(for: $0.id) == .pending } ?? false,
                "dynamicLoadOrdinal": resource?.loaded.loadOrdinal ?? 0,
                "entryLoadOrdinal": first?.loadOrdinal ?? 0,
                "hasMaterialRecipe": resource?.lightingProfile != nil,
                "litRecipe": resource?.lightingProfile?.lightingEnabled ?? false,
            ]
        }
        let automatic = SceneAssetCatalog.ModelAsset(relativePath: "models/shared.json", autosize: true)
        let manual = SceneAssetCatalog.ModelAsset(relativePath: "models/shared.json", autosize: false)
        let absent = SceneAssetCatalog.ModelAsset(relativePath: "models/shared.json")
        let ordinary = SceneRenderDescriptor.Layer(id: 1)
        let peer = SceneRenderDescriptor.Layer(id: 2)
        let override = SceneRenderDescriptor.Layer(id: 1, staticBaseTexturePath: "materials/override.png")
        try check("staticAuto", layers: [ordinary, peer], models: [automatic])
        try check("staticManual", layers: [ordinary], models: [manual])
        try check("staticOmittedPolicy", layers: [ordinary], models: [absent])
        let missingSize = SceneRenderDescriptor.Layer(id: 1, size: nil, sizeWH: [0,0])
        try check("staticDefault", layers: [missingSize], models: [manual])
        try check("staticDefaultOmittedPolicy", layers: [missingSize], models: [absent])
        try check("staticAutoMissing", layers: [missingSize], models: [automatic])
        try check("staticRawNull", layers: [.init(id: 1, initialConfiguration: .object(["size":.null]), size: nil, sizeWH:[0,0])], models:[manual])
        try check("staticRawArray", layers: [.init(id: 1, initialConfiguration: .object(["size":.array([])]), size: nil, sizeWH:[0,0])], models:[manual])
        try check("staticRawValueNumber", layers: [.init(id: 1, initialConfiguration: .object(["size":.object(["value":.number(0)])]), size: nil, sizeWH:[0,0])], models:[manual])
        try check("staticExplicitZero", layers: [.init(id: 1, size: "0 0", sizeWH: [0,0])], models: [manual])
        try check("staticDeclaredAuto", layers: [missingSize], models: [.init(relativePath: "models/shared.json", autosize: true, declaredSizeWH: [80,40])])
        try check("staticDeclaredExplicitAuto", layers: [ordinary], models: [.init(relativePath: "models/shared.json", autosize: true, declaredSizeWH: [80,40])])
        try check("staticPartialDeclaration", layers: [missingSize], models: [.init(relativePath: "models/shared.json", autosize: false, hasDeclaredSizeFields: true)])
        try check("staticDeclared", layers: [missingSize], models: [.init(relativePath: "models/shared.json", autosize: false, declaredSizeWH: [80,40])])
        try check("staticDeferred", layers: [ordinary], deferred: [1], models: [automatic])
        try check("staticSpecial", layers: [ordinary], texture: "animated.tex", models: [automatic])
        try check("staticVideoAuto", layers: [ordinary], texture: "video.tex", models: [automatic])
        try check("staticVideoManualDefault", layers: [missingSize], texture: "video.tex", models: [manual])
        try check("staticText", layers: [.init(id: 1, contentKind: "text")], models: [automatic])
        try check("staticNamedOutput", layers: [ordinary], texture: "_rt_imageLayerComposite_2", models: [automatic])
        try check("staticSolidTexture", layers: [.init(id: 1, contentKind: "solid", staticBaseTexturePath: "materials/canonical.png")], models: [automatic])
        try check("staticSolid", layers: [.init(id: 1, contentKind: "solid")], models: [automatic])
        try check("staticPuppet", layers: [.init(id: 1, puppetMeshPath: "models/puppet.mdl")], models: [automatic])
        try check("staticMissing", layers: [ordinary], texture: "missing.png", models: [automatic])
        try check("staticBroad", layers: [ordinary], models: [automatic]) { $0.materialPasses[0].shaderPath = "shaders/custom" }
        try check("shared", layers: [ordinary, peer])
        try check("overrideWithCanonicalPeer", layers: [override, peer])
        try check("overrideOnly", layers: [override])
        try check("missingCanonical", layers: [override], texture: "missing.png")
        try check("deferred", layers: [ordinary], deferred: [1])
        try check("missing", layers: [ordinary], texture: "missing.png")
        try check("puppet", layers: [.init(id: 1, puppetMeshPath: "models/puppet.mdl")])
        try check("composition", layers: [.init(id: 1, contentKind: "composition")])
        try check("solid", layers: [.init(id: 1, contentKind: "solid")])
        try check("animated", layers: [ordinary], texture: "animated.tex")
        for (name, texture) in [("decodeFailure", "decode-failure.png"),
                                ("uploadFailure", "upload-failure.png"),
                                ("noCandidate", "no-candidate.png"),
                                ("mismatchedCandidate", "mismatched-candidate.png"),
                                ("loadedAnimation", "loaded-animation.png")] {
            try check(name, layers: [ordinary], texture: texture)
        }
        try check("explicitWithEntry", layers: [ordinary], explicit: ["models/shared.json"])
        try check("explicitOnly", layers: [], explicit: ["models/shared.json"])
        for (name, explicit) in [("litIndirect", Set<String>()),
                                 ("litExplicit", Set(["models/shared.json"]))] {
            try check(name, layers: [ordinary], explicit: explicit) {
                $0.materialPasses[0].combos["LIGHTING"] = 1
                $0.materialPasses[0].constantShaderValues = ["metallic": 0, "roughness": 0.7]
            }
        }
        try check("litPuppet", layers: [.init(id: 1, puppetMeshPath: "models/puppet.mdl")]) {
            $0.materialPasses[0].combos["LIGHTING"] = 1
        }
        try check("unknownBuiltinExplicit", layers: [ordinary], explicit: ["models/shared.json"]) {
            $0.materialPasses[0].combos["UNKNOWN"] = 1
        }
        try check("sourceExplicit", layers: [ordinary], explicit: ["models/shared.json"]) {
            $0.materialPasses[0].shaderPath = "shaders/custom"
        }
        let deferredDescriptor = SceneRenderDescriptor(layers: [ordinary], materialPasses: [
            .init(materialPath: "materials/shared.json", texturePaths: ["materials/canonical.png"], textureSlots: ["materials/canonical.png"])
        ])
        let deferredView = SceneResourceView(projectRootURL: root, packageRootURL: nil)
        let deferredPrepared = try ScenePreparedBaseImageResources.prepare(descriptor: deferredDescriptor,
            resourceView: deferredView, device: device, spriteTextureLoader: .init(), sceneGeneration: 1,
            deferredBaseImageLayerIDs: [1], imageGeometryModels: [automatic], cancellationCheck: {})
        let beforeDeferred = deferredPrepared.textureLoader.loadCount
        _ = deferredPrepared.requestDeferredBaseImage(layerID: 1, requestGeneration: 1)
        let deadline = Date().addingTimeInterval(3)
        while deferredPrepared.deferredStatus(for: 1) != .ready && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        let afterReady = deferredPrepared.outcome(for: 1, url: root.appendingPathComponent("materials/canonical.png"), device: device)
        var readyHasOutcome = false
        if case .loaded? = afterReady { readyHasOutcome = true }
        deferredPrepared.cancelDeferredPreparation()
        results["deferredReady"] = ["beforeLoads": beforeDeferred, "ready": deferredPrepared.deferredStatus(for: 1) == .ready,
            "hasOutcome": readyHasOutcome, "cancelRejectsRequest": deferredPrepared.requestDeferredBaseImage(layerID: 1, requestGeneration: 2) == .failed("cancelled")]
        func task() -> ScenePreparedDeviceResourcesTask {
            .init(descriptor: deferredDescriptor, resourceView: deferredView, device: device,
                sceneGeneration: 1, deferredBaseImageLayerIDs: [1], imageGeometryModels: [automatic],
                cancellationCheck: {})
        }
        let staged = task(); staged.start()
        let stageGeometry = try staged.preparedImageGeometry()
        let stageResources = try staged.value()
        staged.cancel()
        var cancelledGeometry = false
        do { _ = try staged.preparedImageGeometry() } catch is CancellationError { cancelledGeometry = true }
        SceneImageLayerPipeline.reject = true
        let rejected = task(); rejected.start()
        var earlyFailure = false
        do { _ = try rejected.preparedImageGeometry() } catch { earlyFailure = true }
        _ = try? rejected.value(); rejected.cancel()
        SceneImageLayerPipeline.reject = false
        let workerEntered = DispatchSemaphore(value: 0)
        let workerRelease = DispatchSemaphore(value: 0)
        let waiterEntered = DispatchSemaphore(value: 0)
        let waiterReturned = DispatchSemaphore(value: 0)
        let pending = ScenePreparedDeviceResourcesTask(descriptor: deferredDescriptor,
            resourceView: deferredView, device: device, sceneGeneration: 1,
            imageGeometryModels: [automatic], cancellationCheck: {
                workerEntered.signal(); workerRelease.wait()
            })
        pending.start()
        let pausedBeforeMetadata = workerEntered.wait(timeout: .now() + 3) == .success
        var pendingCancellation = false
        DispatchQueue.global().async {
            waiterEntered.signal()
            do { _ = try pending.preparedImageGeometry() }
            catch is CancellationError { pendingCancellation = true }
            catch {}
            waiterReturned.signal()
        }
        _ = waiterEntered.wait(timeout: .now() + 3)
        pending.cancel()
        let returnedBeforeWorkerRelease = waiterReturned.wait(timeout: .now() + 3) == .success
        workerRelease.signal()
        _ = try? pending.value()
        results["taskStages"] = ["geometry": stageGeometry[1] ?? [],
            "deferredStillPending": stageResources.baseImages.deferredStatus(for: 1) == .pending,
            "loads": stageResources.baseImages.textureLoader.loadCount,
            "cancelledGeometry": cancelledGeometry, "earlyFailure": earlyFailure,
            "pausedBeforeMetadata": pausedBeforeMetadata,
            "pendingCancellation": pendingCancellation,
            "returnedBeforeWorkerRelease": returnedBeforeWorkerRelease]
        try check("customShader", layers: [ordinary]) { $0.materialPasses[0].shaderPath = "shaders/custom" }
        try check("multiplePasses", layers: [ordinary]) { $0.materialPasses.append($0.materialPasses[0]) }
        try check("duplicateModelLinks", layers: [ordinary]) { $0.modelMaterialLinks.append($0.modelMaterialLinks[0]) }
        try check("secondSlot", layers: [ordinary]) { $0.materialPasses[0].textureSlots.append("materials/override.png") }
        try check("provider", layers: [ordinary]) { $0.materialPasses[0].userTextureInputs = ["mediaThumbnail"] }
        try check("constant", layers: [ordinary]) { $0.materialPasses[0].constantShaderValues = ["Alpha": 0.5] }
        try check("userShaderValue", layers: [ordinary]) { $0.materialPasses[0].userShaderValues = ["Alpha": "userAlpha"] }
        try check("unknownCombo", layers: [ordinary]) { $0.materialPasses[0].combos["UNKNOWN"] = 0 }
        try check("wrongVersion", layers: [ordinary]) { $0.materialPasses[0].combos["VERSION"] = 3 }
        try check("additive", layers: [ordinary]) { $0.materialPasses[0].blending = "additive" }
        try check("depthEnabled", layers: [ordinary]) { $0.materialPasses[0].depthTest = "enabled" }
        try check("alphaWriting", layers: [ordinary]) { $0.materialPasses[0].alphaWriting = "enabled" }

        // External prepared variant metadata drives the whole production source
        // owner. No copied admission predicate or shader/GPU surrogate is run.
        let colorReference = TestReference.asset("materials/renamed-color.png")
        let colorSlot = TestTemplate.Slot(candidates: [.init(reference: colorReference)])
        func variant(_ key: String, samplerZero: TestSampler? = nil,
                     otherSampler: Bool = false, planAvailable: Bool = true)
            -> SceneResolvedMaterialVariantCache.Variant {
            var samplers: [Int: TestSampler] = [:]
            if let samplerZero { samplers[0] = samplerZero }
            if otherSampler { samplers[2] = .init(purposes: [colorReference: "normal"]) }
            return .init(activeSamplers: samplers,
                preparedShader: .init(cacheKey: key, vertex: .init(frontendSchemaVersion: 1)),
                frontendProgram: .init(planAvailable: planAvailable))
        }
        let colorSampler = TestSampler(purposes: [colorReference: "straightAlbedo"])
        let unknownSampler = TestSampler(purposes: [:])
        let normalSampler = TestSampler(purposes: [colorReference: "normal"])
        let inactiveVariants = [variant("inactive-a"), variant("inactive-b")]
        let activeVariants = [variant("active-a", samplerZero: colorSampler),
                              variant("active-b", samplerZero: colorSampler)]
        func sourceCase(_ name: String,
                        variants: [SceneResolvedMaterialVariantCache.Variant],
                        slots: [TestTemplate.Slot?]? = nil,
                        allEntriesReady: Bool = true, schemaAccepted: Bool = true,
                        precompileAccepted: Bool = true,
                        warmupReport: SceneResolvedMaterialPassEncoder.Report? = nil) {
            let template = TestTemplate(textureSlots: slots ?? [colorSlot], renderState: 0,
                fixture: .init(schemaAccepted: schemaAccepted,
                    precompileAccepted: precompileAccepted, allEntriesReady: allEntriesReady,
                    variants: variants))
            let catalog = SceneResolvedMaterialRuntimeCatalog(sourceMaterialEntries: [17: .init(
                key: .init(reportToken: "source:17:renamed-owned-source"), entry: .template(template),
                sharedModelPath: "models/renamed-source.json")])
            let encoder = SceneResolvedMaterialPassEncoder()
            encoder.reportOverride = warmupReport
            var logs: [String] = []
            let prepared = ScenePreparedDeviceResources.prepareSourceMaterialPrograms(
                catalog: catalog, assets: .init(), device: device, encoder: encoder,
                logSink: { logs.append($0) })
            var domain = "absent", sampledPath = "", sampledPurpose = ""
            if let value = prepared[17] {
                switch value.outputDomain {
                case .baseImage: domain = "baseImage"
                case let .sampledAsset(identity):
                    domain = "sampledAsset"
                    sampledPath = identity.path
                    sampledPurpose = identity.purpose
                }
            }
            results[name] = [
                "preparedCount": prepared.count, "outputDomain": domain,
                "sampledPath": sampledPath, "sampledPurpose": sampledPurpose,
                "sharedModelPath": prepared[17]?.sharedModelPath ?? "",
                "warmupCalls": encoder.warmupCalls, "warmupPlanCount": encoder.warmupPlanCount,
                "reasons": logs.compactMap { $0.components(separatedBy: " reason=").dropFirst().first },
                "logs": logs,
            ]
        }
        sourceCase("sourceInactive", variants: inactiveVariants)
        sourceCase("sourceInactiveNoCandidate", variants: inactiveVariants, slots: [])
        sourceCase("sourceOtherSamplerOnly", variants: [variant("other-a", otherSampler: true),
                                                         variant("other-b", otherSampler: true)])
        sourceCase("sourceActiveSamePurpose", variants: activeVariants)
        sourceCase("sourceActiveUnknownPurpose", variants: [variant("unknown", samplerZero: unknownSampler)])
        sourceCase("sourceActiveConflictingPurposes", variants: [activeVariants[0],
            variant("conflict", samplerZero: normalSampler)])
        sourceCase("sourceMixedActiveInactive", variants: [activeVariants[0], inactiveVariants[0]])
        sourceCase("sourceIncompleteEnvelope", variants: inactiveVariants, allEntriesReady: false)
        sourceCase("sourceEmptyEnvelope", variants: [])
        sourceCase("sourceSchemaFailure", variants: inactiveVariants, schemaAccepted: false)
        sourceCase("sourcePrecompileFailure", variants: inactiveVariants, precompileAccepted: false)
        sourceCase("sourceActiveMissingCandidate", variants: activeVariants, slots: [])
        sourceCase("sourcePlanFailure", variants: [variant("no-plan", planAvailable: false), inactiveVariants[0]])
        sourceCase("sourceWarmupFailure", variants: inactiveVariants,
                   warmupReport: .init(failedKeyCount: 1, readyKeyCount: 1))
        sourceCase("sourceWarmupNoReady", variants: inactiveVariants,
                   warmupReport: .init(failedKeyCount: 0, readyKeyCount: 0))
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
