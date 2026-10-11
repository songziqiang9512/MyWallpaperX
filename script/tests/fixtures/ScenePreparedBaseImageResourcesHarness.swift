import Foundation
import Metal

// Controlled decoder/upload boundaries. The production preparation owner and
// path resolver compile whole below; actual MTLTexture identities are observed.
struct SceneResourceView {
    let projectRootURL: URL
    let packageRootURL: URL?
    struct Resource { let url: URL }
    func resource(relativePath: String) -> Resource? {
        let url = projectRootURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? .init(url: url) : nil
    }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        var contentKind = "image"
        var imagePath: String? = "models/shared.json"
        var staticBaseTexturePath: String? = nil
        var puppetMeshPath: String? = nil
        var colorBlendMode: Int? = nil
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
    var layers: [Layer]
    var modelMaterialLinks: [ModelMaterialLink] = [
        .init(modelPath: "models/shared.json", materialPath: "materials/shared.json")
    ]
    var materialPasses: [MaterialPass]
    var colorTargetFormat = TestColorFormat()
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
struct SceneBaseImageTextureLoad {
    struct Loaded {
        let texture: MTLTexture
        let candidate: TestCandidate?
        let animation: String?
        let loadOrdinal: Int
    }
    enum Outcome { case loaded(Loaded), failed(SceneTextureLoadOutcome) }
    static func specializedLoadReason(url: URL, container: String?, usesPuppet: Bool) -> String? {
        if usesPuppet { return "puppet" }
        return container
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
    func texContainer(from url: URL, source: SourceKey) -> String? {
        url.lastPathComponent == "animated.tex" ? "animation" : nil
    }
    func controlledLoad(url: URL, device: MTLDevice) -> SceneBaseImageTextureLoad.Outcome {
        loadCount += 1
        let name = url.lastPathComponent
        if name == "decode-failure.png" { return .failed(.decodeFailed) }
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

// Link-only surfaces from the rest of the whole production source. No worker,
// shader, static-model, or material-runtime algorithm is exercised by this test.
enum SceneDesktopWallpaperHostLaunchError: Error { case requiredImagePipelineUnavailable }
final class SceneImageLayerPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {}
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
enum TestReference { case asset(String), unavailable }
struct TestSampler { func purpose(for reference: TestReference) -> String? { nil } }
struct TestTemplate {
    struct Slot { struct Candidate { let reference: TestReference }; let candidates: [Candidate] }
    let textureSlots: [Slot?]
    let renderState: Int
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
    let sourceMaterialEntries: [Int: Entry] = [:]
}
struct SceneMaterialAssetTextureCatalog { let launchFormatFacts = 0; let launchStates = 0 }
struct SceneResolvedMaterialVariantCache {
    struct Variant {
        struct Shader {
            struct Vertex { let frontendSchemaVersion: Int }
            let cacheKey: String
            let vertex: Vertex
        }
        let activeSamplers: [Int: TestSampler]
        let preparedShader: Shader
        let frontendProgram: Int
    }
    struct Envelope { let allEntriesReady: Bool; let variants: [Variant] }
    static func launchValidated(template: TestTemplate, maximumVariantCount: Int,
                                assetFormatFacts: Int) -> Result<Self, TestError> { .failure(.unused) }
    func precompileLaunchEnvelope(implicitFramebufferIdentity: String?, outputIsRGBA8Unorm: Bool,
                                 assetStates: Int) -> Result<Void, TestError> { .failure(.unused) }
    func launchEnvelopeCapabilitySnapshot() -> Envelope { .init(allEntriesReady: false, variants: []) }
}
enum TestError: Error { case unused }
struct SceneResolvedMaterialPassEncoder {
    struct WarmupPlan {
        init?(identity: String, preparedKey: String, frontend: Int, renderState: Int,
              frontendSchemaVersion: Int, pixelFormat: MTLPixelFormat,
              writeMask: MTLColorWriteMask, device: MTLDevice) { return nil }
    }
    struct Report { let failedKeyCount: Int; let readyKeyCount: Int }
    func warmup(_ plans: [WarmupPlan]) -> Report { .init(failedKeyCount: 0, readyKeyCount: 0) }
}
struct SceneResolvedMaterialProgramFinalizer {
    static func finalize(_ input: Int, variantCache: SceneResolvedMaterialVariantCache) -> Int { input }
}
final class SceneResolvedMaterialRuntimeBridge {
    typealias LogSink = (String) -> Void
    struct PreparedSourceMaterial {
        init(template: TestTemplate, bindFrame: @escaping (Int) -> Int, pixelFormat: MTLPixelFormat,
             sourceIdentity: SceneAssetTextureIdentity, sharedModelPath: String?) {}
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
        let names = ["canonical.png", "override.png", "animated.tex", "decode-failure.png",
                     "upload-failure.png", "no-candidate.png", "mismatched-candidate.png", "loaded-animation.png"]
        for name in names {
            try Data(name.utf8).write(to: root.appendingPathComponent("materials/" + name))
        }
        var results: [String: [String: Any]] = [:]
        func check(_ name: String, layers: [SceneRenderDescriptor.Layer], texture: String = "canonical.png",
                   explicit: Set<String> = [], deferred: Set<Int> = [],
                   editDescriptor: ((inout SceneRenderDescriptor) -> Void)? = nil) throws {
            let texturePath = "materials/" + texture
            var descriptor = SceneRenderDescriptor(layers: layers, materialPasses: [
                .init(materialPath: "materials/shared.json", texturePaths: [texturePath], textureSlots: [texturePath])
            ])
            editDescriptor?(&descriptor)
            let view = SceneResourceView(projectRootURL: root, packageRootURL: nil)
            let resolver = SceneTexturePathResolver(resourceView: view, descriptor: descriptor)
            let prepared = try ScenePreparedBaseImageResources.prepare(descriptor: descriptor,
                resourceView: view, device: device, spriteTextureLoader: .init(), sceneGeneration: 1,
                dynamicImageModelPaths: explicit, deferredBaseImageLayerIDs: deferred,
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
                "loads": prepared.textureLoader.loadCount, "loadedCount": prepared.loadedCount,
                "failedCount": prepared.failedCount, "dynamicCount": prepared.dynamicImageResources.count,
                "sameTexture": resource != nil && first != nil && resource!.loaded.texture === first!.texture,
                "sameCandidate": resource != nil && first != nil && sameCandidate,
                "sameCanonicalTexture": resource != nil && second != nil && resource!.loaded.texture === second!.texture,
                "differentOverrideTexture": resource != nil && first != nil && resource!.loaded.texture !== first!.texture,
                "size": resource?.renderSizeWH ?? [], "hasOutcome": first != nil,
                "evicted": prepared.textureLoader.evictionCount,
                "pending": layers.first.map { prepared.deferredStatus(for: $0.id) == .pending } ?? false,
                "dynamicLoadOrdinal": resource?.loaded.loadOrdinal ?? 0,
                "entryLoadOrdinal": first?.loadOrdinal ?? 0,
            ]
        }
        let ordinary = SceneRenderDescriptor.Layer(id: 1)
        let peer = SceneRenderDescriptor.Layer(id: 2)
        let override = SceneRenderDescriptor.Layer(id: 1, staticBaseTexturePath: "materials/override.png")
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
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
