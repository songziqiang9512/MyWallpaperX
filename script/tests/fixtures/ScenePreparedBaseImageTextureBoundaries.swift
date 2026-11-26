import Foundation
import Metal

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
    case resourceReadFailed(any Error)
    func rethrowResourceReadFailure() throws { if case let .resourceReadFailed(error) = self { throw error } }
}
struct SceneTextureCandidate {
    enum Content: Equatable {
        enum Representation: Equatable { case straightAlpha }
        enum Resolution: Equatable { case resolved(Representation) }
        case color(Resolution)
    }
    let texture: MTLTexture
    let loadOrdinal: Int
    let embeddedBaseMip = 0
    let content = Content.color(.resolved(.straightAlpha))
    var physicalSize: CGSize { CGSize(width: texture.width, height: texture.height) }
    let samplingMarker = "authored-sampling"
}
enum SceneFrameTextureIdentity { case asset(SceneAssetTextureIdentity) }
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var isComplete: Bool { true }
}
enum SceneTextureProviderState { case ready(SceneTextureProviderPublication) }

struct TestContainer {
    var conditionalVariants: [SceneTexContainer.ConditionalVariant] = []
    var reason: String? = nil
    var format = 0
    var isVolume = false
    var isVideoMp4 = false
    var isWebM = false
    var imageWidth = 20
    var imageHeight = 10
}
// Observe calls and lease identity at the external file boundary. This stub
// writes no media and does not duplicate file preparation or lifetime logic.
final class SceneVideoOwnedFile {
    enum Failure: Error { case controlledWriteFailure }
    static var snapshotCount = 0
    static var liveCount = 0
    static var snapshotHook: (() -> Void)?
    let payload: Data
    private init(payload: Data) { self.payload = payload; Self.liveCount += 1 }
    deinit { Self.liveCount -= 1 }
    static func snapshot(payload: Data, cacheDirectory: URL,
                         checkCancellation: (() throws -> Void)? = nil) throws -> SceneVideoOwnedFile {
        try checkCancellation?()
        snapshotCount += 1
        if payload == Data("video-failure.tex".utf8) { throw Failure.controlledWriteFailure }
        let file = SceneVideoOwnedFile(payload: payload)
        snapshotHook?()
        return file
    }
}
struct SceneBaseImageTextureLoad {
    struct Loaded {
        let texture: MTLTexture
        let candidate: SceneTextureCandidate?
        let animation: String?
        let loadOrdinal: Int
    }
    enum Outcome { case loaded(Loaded), failed(SceneTextureLoadOutcome) }
    static func loadOrdinaryCandidate(from url: SceneResourceView.FileInput, loader: SceneTextureLoader,
        device: MTLDevice, preparedTexSource: SceneTextureLoader.PreparedTexSource,
        conditionalVariantIDs: Set<UInt32>? = nil, checkCancellation: (() throws -> Void)? = nil) throws -> Outcome {
        try checkCancellation?()
        return loader.controlledLoad(url: url, device: device)
    }
    static func specializedLoadReason(url: SceneResourceView.FileInput, container: TestContainer?, usesPuppet: Bool) -> String? {
        if usesPuppet { return "puppet" }
        return container?.reason
    }
    static func load(from url: SceneResourceView.FileInput, usesPuppet: Bool, loader: SceneTextureLoader,
                     spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
                     device: MTLDevice,
                     source expectedSource: SceneTextureLoader.SourceKey? = nil,
                     preparedTexSource: SceneTextureLoader.PreparedTexSource? = nil,
                     preparedDirectImageSource: SceneTextureLoader.PreparedDirectImageSource? = nil,
                     mipSelection: SceneOrdinaryImageMipSelection? = nil,
                     checkCancellation: (() throws -> Void)? = nil) -> Outcome {
        do {
            try checkCancellation?()
            if preparedDirectImageSource != nil { SceneTextureLoader.preparedDirectLoads += 1 }
            let tex = try preparedTexSource ?? loader.prepareTexSource(from: url, source: expectedSource,
                checkCancellation: checkCancellation)
            let direct = try preparedDirectImageSource ?? loader.prepareDirectImageSource(from: url,
                source: expectedSource, checkCancellation: checkCancellation)
            if let expectedSource, expectedSource != (tex?.source ?? direct?.source) {
                throw SceneResourceView.ReadError.sourceChanged
            }
            return loader.controlledLoad(url: url, device: device, videoPayload: tex?.container?.isVideoMp4 == true)
        }
        catch { return .failed(.resourceReadFailed(error)) }
    }
}

final class SceneTextureLoader {
    typealias SourceKey = SceneResourceView.ContentIdentity
    struct PreparedTexSource {
        let input: SceneResourceView.FileInput
        let source: SourceKey
        let container: TestContainer?
    }
    struct VideoSourceDeclaration {
        let input: SceneResourceView.FileInput
        let source: SourceKey
        let payload: Data
        let isWebM: Bool
    }
    final class PreparedDirectImageSource {
        let input: SceneResourceView.FileInput
        let source: SourceKey
        init(input: SceneResourceView.FileInput, source: SourceKey) {
            self.input = input; self.source = source
            SceneTextureLoader.livePreparedDirectSources += 1
        }
        deinit { SceneTextureLoader.livePreparedDirectSources -= 1 }
        func admitForPreparation() -> Bool { SceneTextureLoader.preparationAdmissionAllowed }
    }
    static var sourceHook: (() throws -> Void)?
    static var loadHook: (() -> Void)?
    static var preparationAdmissionAllowed = true
    static var livePreparedDirectSources = 0
    static var preparedDirectLoads = 0
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
    enum DataOutcome { case loaded(MTLTexture) }
    var dataLoads = 0
    func loadDataTexture(from input: SceneResourceView.FileInput, device: MTLDevice) throws -> DataOutcome {
        dataLoads += 1
        let key = input.lastPathComponent
        if key == "paint-read-failure.tex" { throw NSError(domain: "controlled-paint-read", code: 1) }
        if let texture = textures[key] { return .loaded(texture) }
        let format: MTLPixelFormat = key == "paint-wrong.tex" ? .bgra8Unorm : .r8Unorm
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 2, height: 2, mipmapped: false)
        let texture = device.makeTexture(descriptor: descriptor)!
        textures[key] = texture
        return .loaded(texture)
    }
    func sourceKey(for url: SceneResourceView.FileInput,
                   checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {
        try checkCancellation?(); try Self.sourceHook?()
        do { return try url.currentIdentity() }
        catch let error as SceneResourceView.ReadError {
            switch error { case .missing, .unreadable: return nil; default: throw error }
        }
    }
    func texContainer(from url: SceneResourceView.FileInput, source: SourceKey,
                      checkCancellation: (() throws -> Void)? = nil) throws -> TestContainer? {
        try checkCancellation?()
        if url.lastPathComponent == "animated.tex" { return .init(reason: "animation") }
        if ["video.tex", "renamed-video.tex", "video-failure.tex", "video-cancel.tex"].contains(url.lastPathComponent) {
            return .init(isVideoMp4: true, imageWidth: 3750, imageHeight: 2250)
        }
        if url.lastPathComponent == "webm.tex" { return .init(reason: "video", isWebM: true) }
        return nil
    }
    func prepareTexSource(from input: SceneResourceView.FileInput, source expectedSource: SourceKey? = nil,
                          checkCancellation: (() throws -> Void)? = nil) throws -> PreparedTexSource? {
        guard input.pathExtension.lowercased() == "tex",
              let source = try sourceKey(for: input, checkCancellation: checkCancellation) else { return nil }
        if let expectedSource, expectedSource != source { throw SceneResourceView.ReadError.sourceChanged }
        return .init(input: input, source: source,
            container: try texContainer(from: input, source: source, checkCancellation: checkCancellation) ?? .init())
    }
    func videoSourceDeclaration(from prepared: PreparedTexSource,
                                checkCancellation: (() throws -> Void)? = nil) throws -> VideoSourceDeclaration? {
        try checkCancellation?()
        guard let container = prepared.container, container.isVideoMp4 || container.isWebM else { return nil }
        return .init(input: prepared.input, source: prepared.source,
            payload: Data(prepared.input.lastPathComponent.utf8), isWebM: container.isWebM)
    }
    func preparedNaturalImageSize(from url: SceneResourceView.FileInput, source: SourceKey,
                                 checkCancellation: (() throws -> Void)? = nil) throws -> CGSize? {
        try checkCancellation?()
        guard source == (try sourceKey(for: url)) else { throw SceneResourceView.ReadError.sourceChanged }
        return CGSize(width: 20, height: 10)
    }
    func prepareDirectImageSource(from input: SceneResourceView.FileInput, source expectedSource: SourceKey? = nil,
                                  checkCancellation: (() throws -> Void)? = nil) throws -> PreparedDirectImageSource? {
        try checkCancellation?()
        guard ["png", "jpg", "jpeg"].contains(input.pathExtension.lowercased()),
              let source = try sourceKey(for: input) else { return nil }
        if let expectedSource, expectedSource != source { throw SceneResourceView.ReadError.sourceChanged }
        return .init(input: input, source: source)
    }
    func preparedNaturalImageSize(from prepared: PreparedDirectImageSource,
                                 checkCancellation: (() throws -> Void)? = nil) throws -> CGSize? {
        try checkCancellation?()
        return CGSize(width: 20, height: 10)
    }
    enum CandidateOutcome { case loaded(SceneTextureCandidate), failed }
    func loadCandidate(from prepared: PreparedTexSource, purpose: SceneTextureLoadPurpose,
                       device: MTLDevice, conditionalVariantIDs: Set<UInt32>?,
                       checkCancellation: (() throws -> Void)? = nil) throws -> CandidateOutcome {
        try checkCancellation?()
        guard case let .loaded(loaded) = controlledLoad(url: prepared.input, device: device),
              let candidate = loaded.candidate else { return .failed }
        return .loaded(candidate)
    }
    func controlledLoad(url: SceneResourceView.FileInput, device: MTLDevice,
                        videoPayload: Bool = false) -> SceneBaseImageTextureLoad.Outcome {
        loadCount += 1
        Self.totalLoadCount += 1
        Self.loadHook?()
        let name = url.lastPathComponent
        if name == "decode-failure.png" || (name == "retry-decode.png" && loadCount == 1) { return .failed(.decodeFailed) }
        if videoPayload { return .failed(.texContainsVideoPayload) }
        let texture: MTLTexture
        if let cached = textures[url.diagnosticPath] { texture = cached }
        else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
            descriptor.storageMode = .shared
            guard let allocated = device.makeTexture(descriptor: descriptor) else {
                return .failed(.textureAllocationFailed)
            }
            texture = allocated
            textures[url.diagnosticPath] = texture
        }
        if name == "upload-failure.png" || (name == "retry-upload.png" && loadCount == 1) { uploadCommandQueue.failedTextures.append(texture) }
        let candidateTexture = name == "mismatched-candidate.png"
            ? device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))! : texture
        let candidate: SceneTextureCandidate? = name == "no-candidate.png" ? nil
            : .init(texture: candidateTexture, loadOrdinal: loadCount)
        return .loaded(.init(texture: texture, candidate: candidate,
            animation: ["loaded-animation.png", "animated.tex"].contains(name) ? "animation" : nil, loadOrdinal: loadCount))
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
