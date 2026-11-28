import Foundation
import Metal

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
enum ScenePuppetLayerLoad {
    struct Clip { let maskTexturePath: String }
    struct Mesh { let clipRecords: [Clip] }
    struct PreparedAsset { let meshPath: String; let mesh: Mesh }
    enum AssetPreparation { case ready(PreparedAsset), unavailable }
    struct PreparedPose {
        enum Geometry { case bind(PreparedAsset, Int), evaluated(PreparedAsset, Int, Int, Int, Int), unavailable }
        let geometry: Geometry
    }
}
struct ScenePreparedPuppetResources {
    static var fixtureAssets: [String: ScenePuppetLayerLoad.AssetPreparation] = [:]
    let assetsByMeshPath: [String: ScenePuppetLayerLoad.AssetPreparation]
    static func prepare(descriptor: SceneRenderDescriptor, resourceView: SceneResourceView,
                        cancellationCheck: () throws -> Void) throws -> Self {
        try cancellationCheck(); return .init(assetsByMeshPath: fixtureAssets)
    }
    func defaultPose(for layer: SceneRenderDescriptor.Layer) -> ScenePuppetLayerLoad.PreparedPose? { nil }
}
struct SceneRenderDescriptor {
    struct Camera {
        var authoredOrthographicProjectionActive: Bool?
        var default2DInputLayerID: Int?
        var orthoWidth: Float?
        var orthoHeight: Float?
        var generalZoom: Float?
    }
    struct Dependency { let layerID: Int; let index: Int; let type: String }
    struct EffectDescriptor {
        struct PassDescriptor {
            struct UserTexture {
                enum Kind { case system, property }
                let kind: Kind
                let value: String
            }
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [UserTexture?]
        }
        let id: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
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
        var renderSizeWH: [Float]? { sizeWH }
        var scaleXYZ: [Float]?
        var anglesXYZ: [Float]?
        var usesPerspective: Bool?
        var scalableStaticColorSource: Bool?
        var effects: [EffectDescriptor] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Dependency] = []
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
    var camera = Camera()
    var modelMaterialLinks: [ModelMaterialLink] = [
        .init(modelPath: "models/shared.json", materialPath: "materials/shared.json")
    ]
    var materialPasses: [MaterialPass]
    var colorTargetFormat = TestColorFormat()
    var requiresImageDepthAttachment = false
    var requiresImageAdditiveRGB = false
    var requiresImageNormalDepth = false
    var preparedImageMaterialStatesByModelPath: [String: SceneMaterialRenderState]? = nil
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
struct SceneParticleLayerImageEmitterCompilation {
    let textures: [Int: MTLTexture]
    let animated: Set<Int>
    let destroyed: Set<Int>
}
enum SceneParticleLayerImageEmitterCompiler {
    static func compile(descriptor: SceneRenderDescriptor, texturesByLayerID: [Int: MTLTexture],
        animatedSourceLayerIDs: Set<Int>, destroyedAuthoredLayerIDs: Set<Int>) -> SceneParticleLayerImageEmitterCompilation {
        .init(textures: texturesByLayerID, animated: animatedSourceLayerIDs, destroyed: destroyedAuthoredLayerIDs)
    }
}
enum SceneDesktopWallpaperHostLaunchError: Error { case requiredImagePipelineUnavailable }
final class SceneImageLayerPipeline {
    static var reject = false
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat,
          preparesDepth: Bool = false, preparesAdditive: Bool = false,
          preparesNormalDepth: Bool = false, rasterSampleCount: Int = 1,
          preparesMultisampleSeed: Bool = true) {
        if Self.reject { return nil }
    }
}
final class SceneImageEffectPipelineRepository {
    let device: MTLDevice
    init(device: MTLDevice, pixelFormat: MTLPixelFormat, usesSixPointQuadrature: Bool = false) {
        self.device = device
    }
    func prepareDirectDraw() -> Bool { true }
    func preparePuppetClipping() -> Bool { fatalError("device factory is outside this carrier") }
    func layerColorBlendState() -> Int { 0 }
}
enum SceneMdlStaticModel { struct PreparedSource {} }
struct ScenePreparedStaticModelResources {
    struct MaterialPlan { static let empty = Self() }
    static func prepare(descriptor: SceneRenderDescriptor, directionalShadowDimensionLimit: Int?, pointVolumeEnabled: Bool, modelReflectionsEnabled: Bool, rasterSampleCount: Int,
                        resourceView: SceneResourceView, device: MTLDevice, textureLoader: SceneTextureLoader,
                        materialPlan: MaterialPlan,
                        albedoStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
                        preparedSources: inout [String: SceneMdlStaticModel.PreparedSource],
                        cancellationCheck: () throws -> Void) throws -> Self { .init() }
}
struct SceneResolvedMaterialExecutionCapabilityCatalog {}
enum SceneTextureLoadPurpose: String { case straightAlbedo, premultipliedColor, normal }
struct SceneAssetTextureIdentity: Hashable { let path: String; let purpose: SceneTextureLoadPurpose }
enum SceneAssetTextureLaunchState { case unavailable }
enum TestProvider: Hashable { case sceneBackground(consumerLayerID: Int) }
enum TestReference: Hashable { case asset(String), provider(TestProvider), unavailable }
struct TestSampler {
    // Prepared typed facts supplied by the external compiler boundary. This
    // does not replace or test production shader-purpose derivation.
    let purposes: [TestReference: SceneTextureLoadPurpose]
}
enum SceneResolvedMaterialShaderSchema {
    static func purpose(for reference: TestReference, sampler: TestSampler) -> SceneTextureLoadPurpose? {
        sampler.purposes[reference]
    }
}
enum SceneDynamicTarget: String, Hashable { case declaredLive, declaredInactive }
struct TestTemplate {
    struct Slot { struct Candidate { let reference: TestReference }; let candidates: [Candidate] }
    struct UniformDeclaration {
        struct Dynamic: Hashable { let target: SceneDynamicTarget }
        enum Value { case staticExact, dynamic(Dynamic) }
        let value: Value
    }
    let textureSlots: [Slot?]
    let bindsImageLayerColor: Bool
    var uniformDeclarations: [UniformDeclaration] = []
    var fixture = TestVariantFixture()
}
struct TestVariantFixture {
    var schemaAccepted = true
    var precompileAccepted = true
    var allEntriesReady = true
    var variants: [SceneResolvedMaterialVariantCache.Variant] = []
    var preparedDynamicUniforms: Set<TestTemplate.UniformDeclaration.Dynamic> = []
    var hasSceneEnvironmentConsumer = false
}
struct SceneResolvedMaterialRuntimeCatalog {
    struct Entry {
        struct Key { let reportToken: String }
        enum Value {
            case template(TestTemplate, textureFormatSlots: Result<Set<Int>, TestError>)
            case failure(String)
        }
        let key: Key
        let entry: Value
        let sharedModelPath: String?
        var capturesMainTarget = false
        var formatSeedSamplers: [Int: TestSampler] = [:]
    }
    let sourceMaterialTargetFormat = TestColorFormat()
    let userPropertyDemands: Set<Never> = []
    let systemProviderDemands: Set<Never> = []
    var sourceMaterialEntries: [Int: Entry] = [:]
}
struct SceneMaterialAssetTextureCatalog {
    struct ConditionalAsset {
        let input: SceneResourceView.FileInput
        let conditions: SceneTextureAtlasConditions
        let selection: Set<UInt32>
        let identities: Set<SceneAssetTextureIdentity>
    }
    let launchFormatFacts = 0
    let launchStates = 0
}
struct SceneResolvedMaterialVariantCache {
    struct Frontend { let planAvailable: Bool }
    struct Variant {
        struct PreparedAssembly {
            let frontendProgram: Frontend
        }
        struct TextureSelectionFacts { let candidatePurposes: [Int: Set<SceneTextureLoadPurpose>] }
        let activeSamplers: [Int: TestSampler]
        let preparedAssembly: PreparedAssembly
        var textureSelectionFacts: TextureSelectionFacts {
            .init(candidatePurposes: activeSamplers.mapValues { Set($0.purposes.values) })
        }
    }
    struct Envelope {
        let allEntriesReady: Bool
        let variants: [Variant]
        let dynamicUniforms: Set<TestTemplate.UniformDeclaration.Dynamic>
    }
    let fixture: TestVariantFixture
    var hasAudioSpectrumConsumer: Bool { false }
    var hasSceneEnvironmentConsumer: Bool { fixture.hasSceneEnvironmentConsumer }
    static func launchValidated(template: TestTemplate,
                                textureFormatSlots: Result<Set<Int>, TestError>, maximumVariantCount: Int,
                                assetFormatFacts: Int, formatSeedSamplers: [Int: TestSampler]) -> Result<Self, TestError> {
        if case let .failure(failure) = textureFormatSlots { return .failure(failure) }
        return template.fixture.schemaAccepted ? .success(.init(fixture: template.fixture))
            : .failure(.controlledSchemaFailure)
    }
    func precompileLaunchEnvelope(implicitFramebufferIdentity: String?, outputIsRGBA8Unorm: Bool,
                                 assetStates: Int) -> Result<Void, TestError> {
        fixture.precompileAccepted ? .success(()) : .failure(.controlledPrecompileFailure)
    }
    func launchEnvelopeCapabilitySnapshot() -> Envelope {
        .init(allEntriesReady: fixture.allEntriesReady, variants: fixture.variants,
            dynamicUniforms: fixture.preparedDynamicUniforms)
    }
}
enum TestError: Error { case controlledSchemaFailure, controlledPrecompileFailure }
final class SceneResolvedMaterialPassEncoder {
    struct WarmupPlan {
        init?(identity: String,
              prepared: SceneResolvedMaterialVariantCache.Variant.PreparedAssembly,
              pixelFormat: MTLPixelFormat, writeMask: MTLColorWriteMask, device: MTLDevice) {
            // Fault injection at the external pipeline boundary only.
            guard prepared.frontendProgram.planAvailable else { return nil }
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
        enum OutputDomain { case sampledAsset(SceneAssetTextureIdentity), baseImage, capturedMain }
        let declaredDynamicTargets: Set<SceneDynamicTarget>
        let bindsImageLayerColor: Bool
        let requiresSceneEnvironment: Bool
        let outputDomain: OutputDomain
        let sharedModelPath: String?
        init(declaredDynamicTargets: Set<SceneDynamicTarget>,
             hasAudioSpectrumConsumer _: Bool, requiresSceneEnvironment: Bool,
             bindFrame: @escaping (Int) -> Int, pixelFormat: MTLPixelFormat,
             outputDomain: OutputDomain, sharedModelPath: String?, bindsImageLayerColor: Bool) {
            self.declaredDynamicTargets = declaredDynamicTargets
            self.bindsImageLayerColor = bindsImageLayerColor
            self.requiresSceneEnvironment = requiresSceneEnvironment
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
    init(userPropertyDemands: Set<Never>, systemProviderDemands: Set<Never>,
         capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
         assets: SceneMaterialAssetTextureCatalog, device: MTLDevice,
         visibleExecutionRootLayerIDs: Set<Int>, capturesExecutionObservations: Bool) {}
}

@main
enum Checks {
    @MainActor
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"skip\":\"native Metal device unavailable\"}"); return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("materials"),
                                               withIntermediateDirectories: true)
        let names = ["canonical.png", "override.png", "animated.tex", "video.tex", "renamed-video.tex",
                     "video-failure.tex", "video-cancel.tex", "webm.tex", "decode-failure.png",
                     "upload-failure.png", "no-candidate.png", "mismatched-candidate.png", "loaded-animation.png"]
        for name in names {
            try Data(name.utf8).write(to: root.appendingPathComponent("materials/" + name))
        }
        var results: [String: [String: Any]] = [:]
        func check(_ name: String, layers: [SceneRenderDescriptor.Layer], texture: String = "canonical.png",
                   explicit: Set<String> = [], deferred: Set<Int> = [],
                   models: [SceneAssetCatalog.ModelAsset] = [],
                   replacementAfterGeometry: Data? = nil,
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
            let videoPreparations = SceneVideoOwnedFile.snapshotCount
            let prepared = try ScenePreparedBaseImageResources.prepare(descriptor: descriptor,
                resourceView: view, device: device, spriteTextureLoader: .init(), sceneGeneration: 1,
                cacheDirectory: root,
                dynamicImageModelPaths: explicit, deferredBaseImageLayerIDs: deferred,
                imageGeometryModels: models, geometryPrepared: {
                    geometry = $0
                    loadsAtGeometry = SceneTextureLoader.totalLoadCount - loadsBeforeGeometry
                    if let replacementAfterGeometry {
                        try! replacementAfterGeometry.write(to: root.appendingPathComponent(texturePath), options: .atomic)
                    }
                },
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
            let image: SceneTextureCandidate?
            if case let .image(candidate)? = resource?.product { image = candidate } else { image = nil }
            let videoSource: SceneTextureLoader.SourceKey?
            let videoFile: SceneVideoOwnedFile?
            if case let .video(source, file, _)? = resource?.product {
                videoSource = source; videoFile = file
            } else { videoSource = nil; videoFile = nil }
            let sameCandidate = image?.loadOrdinal == first?.candidate?.loadOrdinal
                && image?.samplingMarker == first?.candidate?.samplingMarker
            let canonicalSource = resolver.resolvePrimaryTexture(modelPath: "models/shared.json")
                .flatMap { try? $0.currentIdentity() }
            results[name] = [
                "geometry": Dictionary(uniqueKeysWithValues: geometry.map { (String($0.key), $0.value) }),
                "geometryPublished": loadsAtGeometry == 0,
                "loads": prepared.textureLoader.loadCount, "loadedCount": prepared.loadedCount,
                "failedCount": prepared.failedCount, "dynamicCount": prepared.dynamicImageResources.count,
                "sameTexture": image != nil && first != nil && image!.texture === first!.texture,
                "sameCandidate": image != nil && first != nil && sameCandidate,
                "sameCanonicalTexture": image != nil && second != nil && image!.texture === second!.texture,
                "differentOverrideTexture": image != nil && first != nil && image!.texture !== first!.texture,
                "size": resource?.renderSizeWH ?? [],
                "naturalSize": resource?.naturalSizeWH ?? [], "hasOutcome": first != nil,
                "evicted": prepared.textureLoader.evictionCount,
                "pending": layers.first.map { prepared.deferredStatus(for: $0.id) == .pending } ?? false,
                "dynamicLoadOrdinal": image?.loadOrdinal ?? 0,
                "entryLoadOrdinal": first?.loadOrdinal ?? 0,
                "hasMaterialRecipe": resource?.lightingProfile != nil,
                "litRecipe": resource?.lightingProfile?.lightingEnabled ?? false,
                "videoProduct": videoFile != nil,
                "videoPreparations": SceneVideoOwnedFile.snapshotCount - videoPreparations,
                "videoSourceMatchesModel": videoSource != nil && videoSource == canonicalSource,
                "videoPayload": videoFile.map { String(decoding: $0.payload, as: UTF8.self) } ?? "",
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
        try check("videoExplicit", layers: [], texture: "video.tex", explicit: ["models/shared.json"])
        try check("videoRenamed", layers: [ordinary], texture: "renamed-video.tex")
        try check("videoOverrideOnly", layers: [override], texture: "video.tex")
        try check("videoOverrideWithCanonicalPeer", layers: [override, peer], texture: "video.tex")
        let videoOverride = SceneRenderDescriptor.Layer(id: 1, staticBaseTexturePath: "materials/renamed-video.tex")
        try check("videoOverrideKeepsUnusedStaticDefaultCold", layers: [videoOverride])
        try check("videoOverrideKeepsUnusedVideoDefaultCold", layers: [videoOverride], texture: "video.tex")
        try check("videoWriteFailure", layers: [ordinary], texture: "video-failure.tex",
                  explicit: ["models/shared.json"])
        try check("videoWebM", layers: [], texture: "webm.tex", explicit: ["models/shared.json"])
        try check("videoDeferred", layers: [ordinary], texture: "video.tex", deferred: [1])
        let revisionURL = root.appendingPathComponent("materials/renamed-video.tex")
        let replacement = Data("replacement revision".utf8)
        let revisionWrites = SceneVideoOwnedFile.snapshotCount
        var sourceChanged = false
        do {
            try check("videoRevisionChanged", layers: [ordinary], texture: revisionURL.lastPathComponent,
                      replacementAfterGeometry: replacement)
        } catch SceneResourceView.ReadError.sourceChanged { sourceChanged = true }
        results["videoRevisionChanged"] = ["replacedAtGeometry": try Data(contentsOf: revisionURL) == replacement, "sourceChanged": sourceChanged,
            "videoPreparations": SceneVideoOwnedFile.snapshotCount - revisionWrites]
        func videoModels(_ name: String, firstTexture: String = "video.tex",
                         secondTexture: String = "video.tex") throws {
            let paths = ["models/renamed-a.json", "models/renamed-b.json"]
            let textures = ["materials/" + firstTexture, "materials/" + secondTexture]
            let descriptor = SceneRenderDescriptor(
                layers: paths.enumerated().map { .init(id: $0.offset + 1, imagePath: $0.element) },
                modelMaterialLinks: paths.enumerated().map {
                    .init(modelPath: $0.element, materialPath: "materials/video-\($0.offset).json")
                }, materialPasses: textures.enumerated().map {
                    .init(materialPath: "materials/video-\($0.offset).json", texturePaths: [$0.element], textureSlots: [$0.element])
                })
            let writes = SceneVideoOwnedFile.snapshotCount
            let prepared = try ScenePreparedBaseImageResources.prepare(descriptor: descriptor,
                resourceView: .init(projectRootURL: root, packageRootURL: nil), device: device,
                spriteTextureLoader: .init(), sceneGeneration: 1, cacheDirectory: root, cancellationCheck: {})
            defer { prepared.cancelDeferredPreparation() }
            let videos = paths.compactMap { path -> (SceneTextureLoader.SourceKey, SceneVideoOwnedFile)? in
                guard let resource = prepared.dynamicImageResources[path],
                      case let .video(source, file, _) = resource.product else { return nil }
                return (source, file)
            }
            results[name] = [
                "dynamicCount": prepared.dynamicImageResources.count,
                "videoProducts": videos.count, "loads": prepared.textureLoader.loadCount,
                "videoPreparations": SceneVideoOwnedFile.snapshotCount - writes,
                "sameSource": videos.count == 2 && videos[0].0 == videos[1].0,
                "sameFile": videos.count == 2 && videos[0].1 === videos[1].1,
                "failedCount": prepared.failedCount,
                "evicted": prepared.textureLoader.evictionCount,
                "healthyPeer": prepared.dynamicImageResources[paths[1]] != nil,
                "failedPeerAbsent": prepared.dynamicImageResources[paths[0]] == nil,
            ]
        }
        let liveVideoFiles = SceneVideoOwnedFile.liveCount
        try videoModels("videoSharedModels")
        results["videoSharedModels"]?["leasesReleased"] = SceneVideoOwnedFile.liveCount == liveVideoFiles
        try videoModels("videoDistinctSources", firstTexture: "renamed-video.tex")
        results["videoDistinctSources"]?["leasesReleased"] = SceneVideoOwnedFile.liveCount == liveVideoFiles
        try videoModels("videoFailedPeer", firstTexture: "video-failure.tex")
        results["videoFailedPeer"]?["leasesReleased"] = SceneVideoOwnedFile.liveCount == liveVideoFiles
        try videoModels("videoRepeatedFailure", firstTexture: "video-failure.tex", secondTexture: "video-failure.tex")
        try videoModels("videoSurvivesStaticUploadFailure", firstTexture: "upload-failure.png")
        var videoCancelled = false, videoReturned = false
        let videoWrites = SceneVideoOwnedFile.snapshotCount
        SceneVideoOwnedFile.snapshotHook = { videoCancelled = true }
        do {
            let path = "materials/video-cancel.tex"
            let descriptor = SceneRenderDescriptor(layers: [], materialPasses: [
                .init(materialPath: "materials/shared.json", texturePaths: [path], textureSlots: [path])
            ])
            let prepared = try ScenePreparedBaseImageResources.prepare(descriptor: descriptor,
                resourceView: .init(projectRootURL: root, packageRootURL: nil), device: device,
                spriteTextureLoader: .init(), sceneGeneration: 1, cacheDirectory: root,
                dynamicImageModelPaths: ["models/shared.json"], cancellationCheck: {
                    if videoCancelled { throw CancellationError() }
                })
            prepared.cancelDeferredPreparation()
            videoReturned = true
        } catch is CancellationError { videoCancelled = true }
        SceneVideoOwnedFile.snapshotHook = nil
        results["videoCancelled"] = ["cancelled": videoCancelled, "returnedPreparation": videoReturned,
            "videoPreparations": SceneVideoOwnedFile.snapshotCount - videoWrites,
            "leasesReleased": SceneVideoOwnedFile.liveCount == liveVideoFiles]
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
        try check("stockVersionLowercase", layers: [ordinary]) {
            $0.materialPasses[0].combos = ["version": 2]
        }
        try check("stockVersionRenamedExplicit", layers: [], texture: "override.png",
                  explicit: ["models/shared.json"]) {
            $0.materialPasses[0].combos = ["version": 2]
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
            cacheDirectory: root,
            deferredBaseImageLayerIDs: [1], imageGeometryModels: [automatic], cancellationCheck: {})
        let beforeDeferred = deferredPrepared.textureLoader.loadCount
        _ = deferredPrepared.requestDeferredBaseImage(layerID: 1, requestGeneration: 1)
        let deadline = Date().addingTimeInterval(3)
        while deferredPrepared.deferredStatus(for: 1) != .ready && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        let preparedInput = SceneTexturePathResolver(resourceView: deferredView, descriptor: deferredDescriptor)
            .resolvePrimaryTexture(for: ordinary)!
        let canonical = root.appendingPathComponent("materials/canonical.png")
        let moved = root.appendingPathComponent("materials/temporarily-moved.png")
        try FileManager.default.moveItem(at: canonical, to: moved)
        let afterReady = deferredPrepared.outcome(for: 1, url: preparedInput, device: device)
        let foreign = deferredPrepared.outcome(for: 1, url: .externalFile(canonical), device: device)
        try FileManager.default.moveItem(at: moved, to: canonical)
        var readyHasOutcome = false, foreignInputRejected = false
        if case .loaded? = afterReady { readyHasOutcome = true }
        if case .failed(.resourceReadFailed)? = foreign { foreignInputRejected = true }
        deferredPrepared.cancelDeferredPreparation()
        results["deferredReady"] = ["beforeLoads": beforeDeferred, "ready": deferredPrepared.deferredStatus(for: 1) == .ready,
            "hasOutcome": readyHasOutcome, "foreignInputRejected": foreignInputRejected, "cancelRejectsRequest": deferredPrepared.requestDeferredBaseImage(layerID: 1, requestGeneration: 2) == .failed("cancelled")]
        results["deferredQuality"] = try deferredQuality(root: root, device: device)
        let heldPrepared = try ScenePreparedBaseImageResources.prepare(descriptor:deferredDescriptor,
            resourceView:deferredView,device:device,spriteTextureLoader:.init(),sceneGeneration:2,
            cacheDirectory:root,
            deferredBaseImageLayerIDs:[1],imageGeometryModels:[automatic],cancellationCheck:{})
        let heldEntered=DispatchSemaphore(value:0),heldRelease=DispatchSemaphore(value:0),heldDrained=DispatchSemaphore(value:0)
        SceneTextureLoader.loadHook={heldEntered.signal();heldRelease.wait()}
        _ = heldPrepared.requestDeferredBaseImage(layerID:1,requestGeneration:1)
        precondition(heldEntered.wait(timeout:.now()+5) == .success)
        heldPrepared.cancelDeferredPreparation()
        heldPrepared.cancelAndDrainDeferredPreparation {heldDrained.signal()}
        heldPrepared.cancelAndDrainDeferredPreparation {heldDrained.signal()}
        let deferredDrainPending=heldDrained.wait(timeout:.now()) == .timedOut
        let closedRejects=heldPrepared.requestDeferredBaseImage(layerID:1,requestGeneration:2) == .failed("cancelled")
        heldRelease.signal()
        let firstDeferredDrained=heldDrained.wait(timeout:.now()+5) == .success
        let repeatedDeferredDrained=heldDrained.wait(timeout:.now()+5) == .success
        SceneTextureLoader.loadHook=nil
        heldPrepared.cancelAndDrainDeferredPreparation {heldDrained.signal()}
        results["deferredDrain"] = ["pendingWhileActualLoadHeld":deferredDrainPending,
            "rejectsNewAdmission":closedRejects,"actualLoadReturnedBeforeDrain":firstDeferredDrained,
            "coalescedTailsComplete":repeatedDeferredDrained,
            "completedDrainStillCompletes":heldDrained.wait(timeout:.now()+5) == .success,
            "cancelledWorkerCannotPublishReady":heldPrepared.deferredStatus(for:1) != .ready]
        func task() -> ScenePreparedDeviceResourcesTask {
            .init(descriptor: deferredDescriptor, directionalShadowDimensionLimit: 4096, pointVolumeQuality: .enabled, modelReflectionsEnabled: true, resourceView: deferredView, device: device,
                sceneGeneration: 1, cacheDirectory: root, deferredBaseImageLayerIDs: [1], imageGeometryModels: [automatic],
                cancellationCheck: {})
        }
        let staged = task(); staged.start()
        let stageGeometry = try staged.preparedImageGeometry()
        staged.completeResourcePlanning(.init(dynamicImageModelPaths: [], modelMaterialPlan: .empty, modelAlbedoStates: [:]))
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
        let pending = ScenePreparedDeviceResourcesTask(descriptor: deferredDescriptor, directionalShadowDimensionLimit: 4096, pointVolumeQuality: .enabled, modelReflectionsEnabled: true,
            resourceView: deferredView, device: device, sceneGeneration: 1,
            cacheDirectory: root,
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
        try check("wrongVersionLowercase", layers: [ordinary]) { $0.materialPasses[0].combos = ["version": 3] }
        try check("duplicateVersionSpellings", layers: [ordinary]) { $0.materialPasses[0].combos["version"] = 2 }
        try check("additive", layers: [ordinary]) { $0.materialPasses[0].blending = "additive" }
        try check("depthEnabled", layers: [ordinary]) { $0.materialPasses[0].depthTest = "enabled" }
        try check("alphaWriting", layers: [ordinary]) { $0.materialPasses[0].alphaWriting = "enabled" }

        // External prepared variant metadata drives the whole production source
        // owner. No copied admission predicate or shader/GPU surrogate is run.
        let colorReference = TestReference.asset("materials/renamed-color.png")
        let colorSlot = TestTemplate.Slot(candidates: [.init(reference: colorReference)])
        func variant(samplerZero: TestSampler? = nil,
                     otherSampler: Bool = false, planAvailable: Bool = true)
            -> SceneResolvedMaterialVariantCache.Variant {
            var samplers: [Int: TestSampler] = [:]
            if let samplerZero { samplers[0] = samplerZero }
            if otherSampler { samplers[2] = .init(purposes: [colorReference: .normal]) }
            return .init(activeSamplers: samplers, preparedAssembly: .init(
                frontendProgram: .init(planAvailable: planAvailable)))
        }
        let colorSampler = TestSampler(purposes: [colorReference: .straightAlbedo])
        let unknownSampler = TestSampler(purposes: [:])
        let normalSampler = TestSampler(purposes: [colorReference: .normal])
        let inactiveVariants = [variant(), variant()]
        let activeVariants = [variant(samplerZero: colorSampler),
                              variant(samplerZero: colorSampler)]
        func sourceCase(_ name: String,
                        variants: [SceneResolvedMaterialVariantCache.Variant],
                        slots: [TestTemplate.Slot?]? = nil,
                        uniformDeclarations: [TestTemplate.UniformDeclaration] = [],
                        preparedDynamicUniforms: Set<TestTemplate.UniformDeclaration.Dynamic> = [],
                        hasSceneEnvironmentConsumer: Bool = false, bindsImageLayerColor: Bool = false,
                        allEntriesReady: Bool = true, schemaAccepted: Bool = true,
                        precompileAccepted: Bool = true,
                        capturesMainTarget: Bool = false,
                        warmupReport: SceneResolvedMaterialPassEncoder.Report? = nil) {
            let template = TestTemplate(textureSlots: slots ?? [colorSlot], bindsImageLayerColor: bindsImageLayerColor,
                uniformDeclarations: uniformDeclarations,
                fixture: .init(schemaAccepted: schemaAccepted,
                    precompileAccepted: precompileAccepted, allEntriesReady: allEntriesReady,
                    variants: variants, preparedDynamicUniforms: preparedDynamicUniforms,
                    hasSceneEnvironmentConsumer: hasSceneEnvironmentConsumer))
            let catalog = SceneResolvedMaterialRuntimeCatalog(sourceMaterialEntries: [17: .init(
                key: .init(reportToken: "source:17:renamed-owned-source"),
                entry: .template(template, textureFormatSlots: .success([])),
                sharedModelPath: "models/renamed-source.json", capturesMainTarget: capturesMainTarget)])
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
                case .capturedMain: domain = "capturedMain"
                case let .sampledAsset(identity):
                    domain = "sampledAsset"
                    sampledPath = identity.path
                    sampledPurpose = identity.purpose.rawValue
                }
            }
            results[name] = [
                "preparedCount": prepared.count, "outputDomain": domain,
                "sampledPath": sampledPath, "sampledPurpose": sampledPurpose,
                "sharedModelPath": prepared[17]?.sharedModelPath ?? "",
                "declaredDynamicTargets": prepared[17]?.declaredDynamicTargets.map(\.rawValue).sorted() ?? [],
                "requiresSceneEnvironment": prepared[17]?.requiresSceneEnvironment ?? false,
                "warmupCalls": encoder.warmupCalls, "warmupPlanCount": encoder.warmupPlanCount,
                "reasons": logs.compactMap { $0.components(separatedBy: " reason=").dropFirst().first },
                "bindsImageLayerColor": prepared[17]?.bindsImageLayerColor ?? false,
            ]
        }
        sourceCase("sourceInactive", variants: inactiveVariants)
        sourceCase("sourcePreparedTargets", variants: inactiveVariants, uniformDeclarations: [
            .init(value: .dynamic(.init(target: .declaredLive))),
            .init(value: .dynamic(.init(target: .declaredInactive))),
            .init(value: .staticExact),
        ], preparedDynamicUniforms: [.init(target: .declaredLive)], hasSceneEnvironmentConsumer: true, bindsImageLayerColor: true)
        sourceCase("sourceInactiveNoCandidate", variants: inactiveVariants, slots: [])
        sourceCase("sourceOtherSamplerOnly", variants: [variant(otherSampler: true),
                                                         variant(otherSampler: true)])
        sourceCase("sourceActiveSamePurpose", variants: activeVariants)
        sourceCase("sourceActiveUnknownPurpose", variants: [variant(samplerZero: unknownSampler)])
        sourceCase("sourceActiveConflictingPurposes", variants: [activeVariants[0],
            variant(samplerZero: normalSampler)])
        sourceCase("sourceMixedActiveInactive", variants: [activeVariants[0], inactiveVariants[0]])
        sourceCase("sourceIncompleteEnvelope", variants: inactiveVariants, allEntriesReady: false)
        sourceCase("sourceEmptyEnvelope", variants: [])
        sourceCase("sourceSchemaFailure", variants: inactiveVariants, schemaAccepted: false)
        sourceCase("sourcePrecompileFailure", variants: inactiveVariants, precompileAccepted: false)
        sourceCase("sourceActiveMissingCandidate", variants: activeVariants, slots: [])
        sourceCase("sourcePlanFailure", variants: [variant(planAvailable: false), inactiveVariants[0]])
        sourceCase("sourceWarmupFailure", variants: inactiveVariants,
                   warmupReport: .init(failedKeyCount: 1, readyKeyCount: 1))
        sourceCase("sourceWarmupNoReady", variants: inactiveVariants,
                   warmupReport: .init(failedKeyCount: 0, readyKeyCount: 0))
        let mainReference = TestReference.provider(.sceneBackground(consumerLayerID: 17))
        let mainSampler = TestSampler(purposes: [mainReference: .premultipliedColor])
        let mainSlot = TestTemplate.Slot(candidates: [.init(reference: mainReference)])
        let mainSlots: [TestTemplate.Slot?] = [mainSlot] + Array(repeating: nil, count: 7)
        let mainVariants = [variant(samplerZero: mainSampler),
                            variant(samplerZero: mainSampler)]
        sourceCase("sourceCapturedMain", variants: mainVariants, slots: mainSlots, capturesMainTarget: true)
        sourceCase("sourceCapturedInactive", variants: [mainVariants[0], inactiveVariants[0]],
                   slots: mainSlots, capturesMainTarget: true)
        sourceCase("sourceCapturedWrongPurpose", variants: activeVariants,
                   slots: mainSlots, capturesMainTarget: true)
        sourceCase("sourceCapturedOtherSampler", variants: [variant(samplerZero: mainSampler,
                   otherSampler: true)], slots: mainSlots, capturesMainTarget: true)
        let wrongMain = TestTemplate.Slot(candidates: [.init(reference: .provider(.sceneBackground(consumerLayerID: 99)))])
        sourceCase("sourceCapturedWrongConsumer", variants: mainVariants,
                   slots: [wrongMain] + Array(repeating: nil, count: 7), capturesMainTarget: true)
        sourceCase("sourceCapturedAsset", variants: activeVariants, capturesMainTarget: true)
        sourceCase("sourceCapturedMissing", variants: mainVariants, slots: [], capturesMainTarget: true)
        sourceCase("sourceCapturedWarmupFailure", variants: mainVariants, slots: mainSlots,
                   capturesMainTarget: true, warmupReport: .init(failedKeyCount: 1, readyKeyCount: 1))
        for name in ["paint-r8.tex", "paint-wrong.tex", "paint-read-failure.tex"] {
            try Data(name.utf8).write(to: root.appendingPathComponent("materials/" + name))
        }
        let goodAsset = ScenePuppetLayerLoad.PreparedAsset(meshPath: "models/healthy.mdl",
            mesh: .init(clipRecords: [.init(maskTexturePath: "materials/paint-r8.tex")]))
        let badAsset = ScenePuppetLayerLoad.PreparedAsset(meshPath: "models/local-failure.mdl",
            mesh: .init(clipRecords: ["paint-r8.tex", "paint-absent.tex", "paint-wrong.tex", "paint-read-failure.tex"]
                .map { .init(maskTexturePath: "materials/" + $0) }))
        ScenePreparedPuppetResources.fixtureAssets = ["models/healthy.mdl": .ready(goodAsset),
            "models/local-failure.mdl": .ready(badAsset)]
        let paintView = SceneResourceView(projectRootURL: root, packageRootURL: nil)
        let paintDescriptor = SceneRenderDescriptor(layers: [], materialPasses: [])
        let paintResources = try ScenePreparedBaseImageResources.prepare(descriptor: paintDescriptor,
            resourceView: paintView, device: device, spriteTextureLoader: .init(),
            sceneGeneration: 1, cacheDirectory: root, cancellationCheck: {})
        let paints = paintResources.puppetClipping
        let good = paints["models/healthy.mdl"]!, bad = paints["models/local-failure.mdl"]!
        try FileManager.default.removeItem(at: root.appendingPathComponent("materials/paint-r8.tex"))
        let loads = paintResources.textureLoader.dataLoads
        for _ in 0..<128 { _ = paintResources.puppetClipping["models/healthy.mdl"] }
        var cancelled = false
        do {
            _ = try ScenePreparedBaseImageResources.preparePuppetClipping(
                resources: paintResources.puppets, dynamicResources: [:],
                resolver: .init(resourceView: paintView, descriptor: paintDescriptor),
                textureLoader: paintResources.textureLoader, device: device,
                cancellationCheck: { throw CancellationError() })
        } catch is CancellationError { cancelled = true }
        results["puppetPaints"] = ["loads": loads,
            "shared": good.paintTextures[0] === bad.paintTextures[0],
            "missingLocal": bad.paintTextures.count == 1,
            "readFailure": bad.readFailed, "healthy": !good.readFailed && good.paintTextures.count == 1,
            "stable": paintResources.textureLoader.dataLoads == loads,
            "cancelled": cancelled]

        results["particleImageInputs"] = try particleImageInputChecks(root: root, device: device).mapValues { $0 as Any }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    @MainActor
    static func deferredQuality(root: URL, device: MTLDevice) throws -> [String: Bool] {
        let texturePath = "materials/quality-mip.tex"
        try Data("authored mip input".utf8).write(to: root.appendingPathComponent(texturePath))
        let view = SceneResourceView(projectRootURL: root, packageRootURL: nil)
        let eager = SceneRenderDescriptor.Layer(id: 10, sizeWH: [1024, 512], scalableStaticColorSource: true)
        let hidden = SceneRenderDescriptor.Layer(id: 20, sizeWH: [4096, 2048], scalableStaticColorSource: true)
        let exact = SceneRenderDescriptor.Layer(id: 30)
        var descriptor = SceneRenderDescriptor(layers: [eager, hidden], materialPasses: [
            .init(materialPath: "materials/shared.json", texturePaths: [texturePath], textureSlots: [texturePath])
        ])
        descriptor.camera = .init(authoredOrthographicProjectionActive: true, orthoWidth: 4096,
            orthoHeight: 2048, generalZoom: 1)
        let input = SceneTexturePathResolver(resourceView: view, descriptor: descriptor).resolvePrimaryTexture(for: hidden)!
        func prepare(_ layers: [SceneRenderDescriptor.Layer], deferred: Set<Int>, auto: Bool,
                     models: Set<String> = [], retainsAliases: Bool = false) throws -> ScenePreparedBaseImageResources {
            var configured = descriptor
            configured.layers = layers
            return try ScenePreparedBaseImageResources.prepare(descriptor: configured, resourceView: view,
                device: device, spriteTextureLoader: .init(), sceneGeneration: 1, cacheDirectory: root,
                dynamicImageRequestsProvider: {
                    .init(models: models, retainsModelDefaultAliases: retainsAliases,
                        automaticMipConstraints: .init(preservedLayerIDs: [], exactSources: []))
                }, deferredBaseImageLayerIDs: deferred, ordinaryColorMipLongEdge: auto ? nil : 2048,
                automaticMipDensity: auto ? 0.25 : nil, cancellationCheck: {})
        }
        func texture(_ prepared: ScenePreparedBaseImageResources, _ layerID: Int) -> MTLTexture? {
            guard case let .loaded(loaded)? = prepared.outcome(for: layerID, url: input, device: device) else { return nil }
            return loaded.texture
        }
        func width(_ prepared: ScenePreparedBaseImageResources, _ layerID: Int) -> Int? {
            texture(prepared, layerID)?.width
        }
        func wait(for condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
            }
            return condition()
        }
        func reveal(_ prepared: ScenePreparedBaseImageResources, _ layerID: Int) -> Bool {
            _ = prepared.requestDeferredBaseImage(layerID: layerID, requestGeneration: 1)
            return wait { prepared.deferredStatus(for: layerID) == .ready }
        }

        let performance = try prepare([hidden], deferred: [hidden.id], auto: false)
        let noColdUpload = performance.textureLoader.loadCount == 0 && width(performance, hidden.id) == nil
        let performanceRevealsMip = reveal(performance, hidden.id) && width(performance, hidden.id) == 2048
        let automatic = try prepare([eager, hidden], deferred: [hidden.id], auto: true)
        let coldSharedProjection = width(automatic, eager.id) == 1024 && width(automatic, hidden.id) == nil
        let autoRevealsSameMip = reveal(automatic, hidden.id) && width(automatic, hidden.id) == 1024
        let autoRevealReusesTexture = autoRevealsSameMip && texture(automatic, eager.id) === texture(automatic, hidden.id)
        var promoted: [Int: Int] = [:]
        automatic.promoteAutomaticMips(to: 0.5) {
            promoted = $0.mapValues { $0.texture.width }
        }
        let promotedPeers = wait { promoted == [eager.id: 2048, hidden.id: 2048] }
            && width(automatic, eager.id) == 2048 && width(automatic, hidden.id) == 2048

        let dormant = try prepare([hidden], deferred: [hidden.id], auto: true)
        dormant.promoteAutomaticMips(to: 0.5) { _ in }
        let noResizeUpload = noColdUpload && dormant.deferredStatus(for: hidden.id) == .pending
            && width(dormant, hidden.id) == nil
        let resizedBeforeReveal = noResizeUpload && reveal(dormant, hidden.id) && width(dormant, hidden.id) == 2048
        let exactSharing = try prepare([hidden, exact], deferred: [hidden.id], auto: true)
        let exactStaysFull = reveal(exactSharing, hidden.id)
            && width(exactSharing, exact.id) == 4096 && width(exactSharing, hidden.id) == 4096
        let modelKey = eager.imagePath!
        let alias = try prepare([hidden], deferred: [hidden.id], auto: false, retainsAliases: true)
        let dormantIsNotAnAlias = reveal(alias, hidden.id) && width(alias, hidden.id) == 2048
            && alias.dynamicImageResources[modelKey] == nil
        let sharedAlias = try prepare([eager, hidden], deferred: [hidden.id], auto: false, retainsAliases: true)
        let eagerAliasKeepsMipZero = reveal(sharedAlias, hidden.id) && width(sharedAlias, hidden.id) == 2048
            && width(sharedAlias, eager.id) == 4096 && sharedAlias.dynamicImageResources[modelKey]?.renderSizeWH == [4096, 2048]
        let automaticAlias = try prepare([eager, hidden], deferred: [hidden.id], auto: true, retainsAliases: true)
        let automaticKeepsUnknownScriptGeometryFull = reveal(automaticAlias, hidden.id)
            && width(automaticAlias, hidden.id) == 4096 && width(automaticAlias, eager.id) == 4096
        descriptor.modelMaterialLinks += [.init(modelPath: "models/literal.json", materialPath: "materials/shared.json"),
            .init(modelPath: "models/plain.json", materialPath: "materials/plain.json")]
        descriptor.materialPasses.append(.init(materialPath: "materials/plain.json", texturePaths: [texturePath],
            textureSlots: [texturePath], combos: ["VERSION": 2, "VARIANT": 0]))
        let plain = SceneRenderDescriptor.Layer(id: 40, imagePath: "models/plain.json", scalableStaticColorSource: true)
        let requested = try prepare([eager, plain], deferred: [], auto: false, models: ["models/literal.json"])
        let requestProtectsOnlyAliasDonors = width(requested, plain.id) == 2048 && width(requested, eager.id) == 4096
            && requested.dynamicImageResources[modelKey]?.renderSizeWH == [4096, 2048]
            && requested.dynamicImageResources["models/literal.json"]?.renderSizeWH == [4096, 2048]

        let concurrent = try prepare([eager, hidden], deferred: [hidden.id], auto: true)
        let started = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        SceneTextureLoader.loadHook = {
            SceneTextureLoader.loadHook = nil
            started.signal()
            resume.wait()
        }
        var firstPublication: [Int: Int]?
        concurrent.promoteAutomaticMips(to: 0.5) { updates in
            if firstPublication == nil { firstPublication = updates.mapValues { $0.texture.width } }
        }
        let midPromotion = started.wait(timeout: .now() + 3) == .success
        concurrent.promoteAutomaticMips(to: 1) { _ in }
        _ = concurrent.requestDeferredBaseImage(layerID: hidden.id, requestGeneration: 1)
        resume.signal()
        let revealDeadline = Date().addingTimeInterval(3)
        while concurrent.deferredStatus(for: hidden.id) != .ready && Date() < revealDeadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        let newerRevealWon = midPromotion && width(concurrent, hidden.id) == 4096
            && wait { firstPublication != nil } && firstPublication == [eager.id: 4096, hidden.id: 4096]

        let resizingReveal = try prepare([hidden], deferred: [hidden.id], auto: true)
        let revealStarted = DispatchSemaphore(value: 0)
        let resumeReveal = DispatchSemaphore(value: 0)
        weak var discardedMip: MTLTexture?
        var observedDiscardedMip = false
        SceneTextureLoader.loadedTextureHook = { loaded in
            if loaded.width == 1024 {
                discardedMip = loaded
                observedDiscardedMip = true
            }
        }
        SceneTextureLoader.loadHook = {
            SceneTextureLoader.loadHook = nil
            revealStarted.signal()
            resumeReveal.wait()
        }
        _ = resizingReveal.requestDeferredBaseImage(layerID: hidden.id, requestGeneration: 1)
        let resizeDuringReveal = revealStarted.wait(timeout: .now() + 3) == .success
        resizingReveal.promoteAutomaticMips(to: 0.5) { _ in }
        resumeReveal.signal()
        let firstReadyAtLatestSize = resizeDuringReveal
            && wait { resizingReveal.deferredStatus(for: hidden.id) == .ready }
            && width(resizingReveal, hidden.id) == 2048
        SceneTextureLoader.loadedTextureHook = nil
        let discardedMipReleased = firstReadyAtLatestSize && observedDiscardedMip && wait { discardedMip == nil }
        let staleAlias = try prepare([eager, hidden], deferred: [hidden.id], auto: true)
        try Data("replaced after the eager peer loaded".utf8).write(to: root.appendingPathComponent(texturePath), options: .atomic)
        _ = staleAlias.requestDeferredBaseImage(layerID: hidden.id, requestGeneration: 1)
        let staleAliasRejected = wait { staleAlias.deferredStatus(for: hidden.id) == .failed("resource-read-failed") }
            && texture(staleAlias, hidden.id) == nil && width(staleAlias, eager.id) == 1024
        return ["noColdUpload": noColdUpload, "performanceRevealsMip": performanceRevealsMip,
            "coldSharedProjection": coldSharedProjection, "autoRevealsSameMip": autoRevealsSameMip,
            "autoRevealReusesTexture": autoRevealReusesTexture, "staleAliasRejected": staleAliasRejected,
            "promotedPeers": promotedPeers, "resizedBeforeReveal": resizedBeforeReveal,
            "exactStaysFull": exactStaysFull, "dormantIsNotAnAlias": dormantIsNotAnAlias, "newerRevealWon": newerRevealWon,
            "eagerAliasKeepsMipZero": eagerAliasKeepsMipZero, "automaticKeepsUnknownScriptGeometryFull": automaticKeepsUnknownScriptGeometryFull,
            "requestProtectsOnlyAliasDonors": requestProtectsOnlyAliasDonors,
            "firstReadyAtLatestSize": firstReadyAtLatestSize, "discardedMipReleased": discardedMipReleased]
    }
}
