import Foundation
import Metal
import CoreGraphics

// Outcome of attempting to load a layer texture. Captured so the preview can
// report exactly *why* a layer's texture didn't show up (file missing, .tex
// uses a compressed codec we don't decode, oversized texture allocation
// failed, etc.) — black previews are otherwise impossible to debug.
nonisolated enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case unsupportedFormat(extension: String)
    case unsupportedTexFormat(code: UInt32)
    case texNoEmbeddedImage             // .tex container is DXT/BC, no JPEG/PNG inside
    case texContainsVideoPayload
    case decodeFailed(String)
    case resourceReadFailed(any Error)
    case textureAllocationFailed(width: Int, height: Int)

    func rethrowResourceReadFailure() throws {
        if case let .resourceReadFailed(error) = self { throw error }
    }
}

/// Shared admission counter for launch-lifetime decoded texture caches. It
/// accounts only re-creatable source/decoded bytes; published Metal textures
/// remain owned by their existing product stores and are never evicted here.
nonisolated final class SceneTextureDecodeCacheBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var limit: Int
    private var reserved = 0
    private var rejectedAdmissions = 0
    private let resourceBudget: SceneResourceBudget

    init(maximumBytes: Int, resourceBudget: SceneResourceBudget = .shared) {
        self.resourceBudget = resourceBudget
        limit = max(maximumBytes, 0)
    }

    var maximumBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return limit
    }

    var residentBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return reserved
    }

    var rejectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rejectedAdmissions
    }

    func updateMaximumBytes(_ maximumBytes: Int) {
        lock.lock()
        limit = max(maximumBytes, 0)
        lock.unlock()
    }

    fileprivate func reserve(_ byteCount: Int) -> Bool {
        guard byteCount >= 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard byteCount <= limit - min(reserved, limit),
              resourceBudget.reserve(byteCount, kind: .decoded) else {
            rejectedAdmissions += 1
            return false
        }
        reserved += byteCount
        return true
    }

    fileprivate func release(_ byteCount: Int) {
        lock.lock()
        precondition(byteCount >= 0 && byteCount <= reserved)
        reserved -= byteCount
        resourceBudget.release(byteCount, kind: .decoded)
        lock.unlock()
    }
}

nonisolated private final class SceneTextureDecodeCacheLease {
    private let budget: SceneTextureDecodeCacheBudget
    private var reservedBytes = 0

    init(budget: SceneTextureDecodeCacheBudget) {
        self.budget = budget
    }

    deinit {
        budget.release(reservedBytes)
    }

    func reserve(_ byteCount: Int) -> Bool {
        guard budget.reserve(byteCount) else { return false }
        reservedBytes += byteCount
        return true
    }

    func releaseAll() {
        let bytes = reservedBytes
        reservedBytes = 0
        budget.release(bytes)
    }
}

nonisolated final class SceneTextureLoader {
    typealias SourceKey = SceneResourceView.ContentIdentity
    typealias Input = SceneResourceView.FileInput

    /// An immutable media input, never a decoded or ready texture.
    struct VideoSourceDeclaration {
        let input: Input
        let source: SourceKey
        let payload: Data
        let isWebM: Bool
    }

    func videoSourceDeclaration(
        from input: Input, checkCancellation: (() throws -> Void)? = nil
    ) throws -> VideoSourceDeclaration? {
        guard let prepared = try prepareTexSource(from: input, checkCancellation: checkCancellation)
        else { return nil }
        return try videoSourceDeclaration(from: prepared, checkCancellation: checkCancellation)
    }

    func videoSourceDeclaration(
        from prepared: PreparedTexSource, checkCancellation: (() throws -> Void)? = nil
    ) throws -> VideoSourceDeclaration? {
        try checkCancellation?()
        guard let container = prepared.container, container.format == 0,
              let payload = container.mips.first?.data,
              SceneTexContainer.isVideoPayload(payload) else { return nil }
        return .init(input: prepared.input, source: prepared.source, payload: payload,
            isWebM: SceneTexContainer.isWebMPayload(payload))
    }

    func videoSourceDeclaration(
        from url: URL, checkCancellation: (() throws -> Void)? = nil
    ) throws -> VideoSourceDeclaration? {
        try videoSourceDeclaration(from: .externalFile(url), checkCancellation: checkCancellation)
    }

    private struct TextureKey: Hashable {
        let source: SourceKey
        let deviceRegistryID: UInt64
        let purpose: SceneTextureLoadPurpose
    }

    struct TexResource {
        let container: SceneTexContainer?
        let parseError: String?
        let firstEmbeddedMipSize: CGSize?
        let hasValidTexb3EmbeddedMipChain: Bool

        init(container: SceneTexContainer?, parseError: String?) {
            self.container = container; self.parseError = parseError
            guard let container, container.format == 0 else {
                firstEmbeddedMipSize = nil; hasValidTexb3EmbeddedMipChain = false
                return
            }
            // Capture ImageIO header facts once with this parsed resource. All
            // purposes and GPU-cache hits consume the same immutable metadata.
            let sizes = container.mips.map { SceneTextureMipUploader.embeddedImagePixelSize($0.data) }
            firstEmbeddedMipSize = sizes.first ?? nil
            let expectedMagic: Data?
            switch container.freeImageFormat {
            case 2: expectedMagic = Data([0xFF, 0xD8, 0xFF])
            case 13: expectedMagic = Data([0x89, 0x50, 0x4E, 0x47])
            default: expectedMagic = nil
            }
            hasValidTexb3EmbeddedMipChain = expectedMagic.map { magic in
                SceneTexContainer.valid2DMipDimensions(container.mips.map { ($0.width, $0.height) })
                    && zip(container.mips, sizes).allSatisfy { mip, size in
                        mip.data.starts(with: magic) && size == CGSize(width: mip.width, height: mip.height)
                    }
            } ?? false
        }

        var decodedByteCost: Int? {
            guard let container else { return 0 }
            let (frameBytes, frameOverflow) = container.spriteFrames.count
                .multipliedReportingOverflow(by: MemoryLayout<SceneTexContainer.SpriteFrame>.stride)
            guard !frameOverflow else { return nil }
            var total = frameBytes
            for image in container.images {
                for mip in image.mips {
                    let (next, overflow) = total.addingReportingOverflow(mip.data.count)
                    guard !overflow else { return nil }
                    total = next
                }
            }
            return total
        }
    }

    /// One stable TEX input for a single preparation request. The existing
    /// loader owns parsing/cache admission; consumers can retain the result
    /// briefly even when the decoded-cache budget declines admission.
    struct PreparedTexSource {
        let input: Input
        let source: SourceKey
        let resource: TexResource

        var container: SceneTexContainer? { resource.container }
    }

    fileprivate enum DirectImageResource {
        case decoded(CGImage)
        case failed(String)
    }

    /// One preparation operation may share captured bytes and a lazy decode.
    /// A metadata queue may retain this value only after source-byte admission;
    /// its consumer removes it before decoding, and releases it after upload.
    final class PreparedDirectImageSource {
        let input: Input
        let source: SourceKey
        fileprivate let data: Data?
        fileprivate let naturalSize: CGSize?
        fileprivate var resource: DirectImageResource?
        fileprivate var didDecode = false
        private let sourceLease: SceneTextureDecodeCacheLease
        private var admitted = false

        fileprivate init(input: Input, source: SourceKey, data: Data?, naturalSize: CGSize?,
                         resource: DirectImageResource?, budget: SceneTextureDecodeCacheBudget) {
            self.input = input; self.source = source; self.data = data
            self.naturalSize = naturalSize; self.resource = resource
            sourceLease = .init(budget: budget)
        }

        /// Uses the loader's existing budget. A cached decoded resource is
        /// already charged there; newly captured encoded bytes have one lease.
        func admitForPreparation() -> Bool {
            guard !didDecode else { return false }
            if admitted { return true }
            guard let data else { return true }
            admitted = sourceLease.reserve(data.count)
            return admitted
        }
    }

    private enum TexEmbeddedImageResource {
        case decoded([CGImage])
        case failed
    }

    private static let directImageExtensions: Set<String> = ["png", "jpg", "jpeg"]
    private static let texExtension = "tex"
    private var textures: [TextureKey: MTLTexture] = [:]
    private var texResources: [SourceKey: TexResource] = [:]
    private var directImageResources: [SourceKey: DirectImageResource] = [:]
    private var directImageNaturalSizes: [SourceKey: CGSize] = [:]
    // Small source facts accompany published GPU textures even after decoded
    // payload eviction; candidate cache hits never reopen an image for alpha.
    struct DirectImageFacts {
        let naturalSize: CGSize
        let isOpaque: Bool
    }
    private(set) var directImageFacts: [SourceKey: DirectImageFacts] = [:]
    private var texEmbeddedImageResources: [SourceKey: TexEmbeddedImageResource] = [:]
    let uploadCommandQueue: SceneTextureUploadCommandQueue
    let decodeCacheBudget: SceneTextureDecodeCacheBudget
    private let decodeCacheLease: SceneTextureDecodeCacheLease
    private(set) var directImageDecodeAttemptCount = 0
    private(set) var texEmbeddedImageDecodeAttemptCount = 0

    // GPUs cope poorly with extremely large textures (e.g. 8192×6144 RGBA8 =
    // 192 MB), and Apple Silicon's maxTexture2DLimit is 16384 but actual
    // allocation can still fail under memory pressure. Cap source images so
    // we always have headroom for several layers worth of textures.
    static let maxTextureDimension = 4096

    init(
        uploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        decodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        )
    ) {
        self.uploadCommandQueue = uploadCommandQueue
        self.decodeCacheBudget = decodeCacheBudget
        self.decodeCacheLease = SceneTextureDecodeCacheLease(
            budget: decodeCacheBudget
        )
    }

    func load(
        from input: Input, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneTextureLoadOutcome {
        try load(from: input, purpose: .premultipliedColor, device: device,
                 checkCancellation: checkCancellation)
    }

    func recordDirectImageDecodeAttempt() { directImageDecodeAttemptCount += 1 }

    /// Purpose participates in cache identity; source identity is checked on
    /// cache hits without rereading payload bytes.
    func load(
        from input: Input, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneTextureLoadOutcome {
        try load(from: input, source: nil, purpose: purpose, device: device,
                 checkCancellation: checkCancellation)
    }

    func load(
        from input: Input, source expectedSource: SourceKey?, purpose: SceneTextureLoadPurpose,
        device: MTLDevice, preparedTexSource: PreparedTexSource? = nil,
        preparedDirectImageSource: PreparedDirectImageSource? = nil,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneTextureLoadOutcome {
        try checkCancellation?()
        let source: SourceKey
        if let preparedTexSource {
            guard preparedTexSource.input == input else { throw SceneResourceView.ReadError.invalidHandle }
            source = preparedTexSource.source
        } else if let preparedDirectImageSource {
            guard preparedDirectImageSource.input == input else { throw SceneResourceView.ReadError.invalidHandle }
            source = preparedDirectImageSource.source
        } else {
            guard let current = try sourceKey(for: input, checkCancellation: checkCancellation) else {
                return .decodeFailed("file metadata unavailable: \(input.lastPathComponent)")
            }
            source = current
        }
        if let expectedSource, expectedSource != source { throw SceneResourceView.ReadError.sourceChanged }
        let key = TextureKey(source: source, deviceRegistryID: device.registryID, purpose: purpose)
        if let cached = textures[key] { return .loaded(cached) }
        let ext = input.pathExtension.lowercased()
        let outcome: SceneTextureLoadOutcome
        if Self.directImageExtensions.contains(ext) {
            outcome = try loadDirectImage(input: input, source: source, purpose: purpose,
                device: device, prepared: preparedDirectImageSource, checkCancellation: checkCancellation)
        } else if ext == Self.texExtension {
            outcome = try loadWallpaperEngineTex(input: input, source: source, purpose: purpose,
                device: device, preparedResource: preparedTexSource?.resource,
                checkCancellation: checkCancellation)
        } else {
            outcome = .unsupportedFormat(extension: ext)
        }
        try checkCancellation?()
        // A failed upload is an attempt, never a successful cache entry.
        if case let .loaded(texture) = outcome { textures[key] = texture }
        return outcome
    }

    // External URL conveniences preserve the independent-file domain. Author
    // resources must pass their already selected Root handle instead.
    func load(from url: URL, device: MTLDevice,
              checkCancellation: (() throws -> Void)? = nil) throws -> SceneTextureLoadOutcome {
        try load(from: .externalFile(url), device: device, checkCancellation: checkCancellation)
    }

    func load(from url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice,
              checkCancellation: (() throws -> Void)? = nil) throws -> SceneTextureLoadOutcome {
        try load(from: .externalFile(url), purpose: purpose, device: device,
                 checkCancellation: checkCancellation)
    }

    func load(from url: URL, source: SourceKey, purpose: SceneTextureLoadPurpose,
              device: MTLDevice, preparedTexSource: PreparedTexSource? = nil,
              preparedDirectImageSource: PreparedDirectImageSource? = nil,
              checkCancellation: (() throws -> Void)? = nil) throws -> SceneTextureLoadOutcome {
        try load(from: .externalFile(url), source: source, purpose: purpose, device: device,
                 preparedTexSource: preparedTexSource, preparedDirectImageSource: preparedDirectImageSource,
                 checkCancellation: checkCancellation)
    }

    func load(from prepared: PreparedDirectImageSource, purpose: SceneTextureLoadPurpose,
              device: MTLDevice, checkCancellation: (() throws -> Void)? = nil) throws -> SceneTextureLoadOutcome {
        try load(from: prepared.input, source: prepared.source, purpose: purpose, device: device,
                 preparedDirectImageSource: prepared, checkCancellation: checkCancellation)
    }

    /// Releases the CPU-side decoded caches (parsed TEX containers and
    /// decoded images) once this launch's GPU textures are published. The
    /// published Metal textures stay in the GPU cache and keep serving
    /// repeat loads byte-identically; a decoded-cache miss after eviction
    /// simply re-decodes from the source file. Callers invoke this at the
    /// GPU-ready point of a launch so decoded bytes do not stay resident for
    /// the whole session next to their GPU copies.
    func evictDecodedCaches() {
        texResources.removeAll()
        directImageResources.removeAll()
        directImageNaturalSizes.removeAll()
        texEmbeddedImageResources.removeAll()
        decodeCacheLease.releaseAll()
    }

    /// Removes GPU-cached textures whose identity matches, so a texture
    /// whose deferred publication could not be proven is never served again
    /// by a later load: affected sources re-decode and re-upload on their
    /// next load — the pre-batch single-texture fail-soft recovery. The
    /// prepare pass invokes this with the identities a batch flush reported
    /// as failed.
    @discardableResult
    func evictTextures(containedIn failedTextures: [MTLTexture]) -> Int {
        guard !failedTextures.isEmpty else { return 0 }
        let evictedKeys = textures.keys.filter { key in
            guard let texture = textures[key] else { return false }
            return failedTextures.contains { $0 === texture }
        }
        guard !evictedKeys.isEmpty else { return 0 }
        for key in evictedKeys {
            textures.removeValue(forKey: key)
        }
        return evictedKeys.count
    }

    func loadDataTexture(from input: Input, device: MTLDevice,
                         checkCancellation: (() throws -> Void)? = nil) throws -> SceneTextureLoadOutcome {
        try load(from: input, purpose: .preservedChannels, device: device,
                 checkCancellation: checkCancellation)
    }

    func loadDataTexture(from url: URL, device: MTLDevice,
                         checkCancellation: (() throws -> Void)? = nil) throws -> SceneTextureLoadOutcome {
        try loadDataTexture(from: .externalFile(url), device: device, checkCancellation: checkCancellation)
    }

    func texContainer(from input: Input, source: SourceKey? = nil,
                      checkCancellation: (() throws -> Void)? = nil) throws -> SceneTexContainer? {
        try prepareTexSource(from: input, source: source, checkCancellation: checkCancellation)?.container
    }

    func texContainer(from url: URL, source: SourceKey? = nil,
                      checkCancellation: (() throws -> Void)? = nil) throws -> SceneTexContainer? {
        try texContainer(from: .externalFile(url), source: source, checkCancellation: checkCancellation)
    }

    func prepareTexSource(from input: Input, source expectedSource: SourceKey? = nil,
                          checkCancellation: (() throws -> Void)? = nil) throws -> PreparedTexSource? {
        try checkCancellation?()
        guard input.pathExtension.lowercased() == Self.texExtension,
              let source = try sourceKey(for: input, checkCancellation: checkCancellation) else { return nil }
        if let expectedSource, expectedSource != source { throw SceneResourceView.ReadError.sourceChanged }
        guard let resource = try texResource(from: input, source: source, checkCancellation: checkCancellation)
        else { return nil }
        return .init(input: input, source: source, resource: resource)
    }

    func prepareTexSource(from url: URL, source: SourceKey? = nil,
                          checkCancellation: (() throws -> Void)? = nil) throws -> PreparedTexSource? {
        try prepareTexSource(from: .externalFile(url), source: source, checkCancellation: checkCancellation)
    }

    /// Header metadata and parsing consume the same captured bytes as their
    /// source key. A cache hit validates identity without rereading payload.
    func preparedNaturalImageSize(from input: Input, source: SourceKey,
                                  checkCancellation: (() throws -> Void)? = nil) throws -> CGSize? {
        if input.pathExtension.lowercased() == Self.texExtension {
            return try texContainer(from: input, source: source, checkCancellation: checkCancellation).map {
                CGSize(width: $0.imageWidth, height: $0.imageHeight)
            }
        }
        guard let current = try sourceKey(for: input, checkCancellation: checkCancellation) else { return nil }
        guard current == source else { throw SceneResourceView.ReadError.sourceChanged }
        if let prepared = directImageNaturalSizes[source] ?? directImageFacts[source]?.naturalSize { return prepared }
        guard let snapshot = try sourceSnapshot(input, source: source, checkCancellation: checkCancellation)
        else { return nil }
        let extent = SceneImageTextureUploader.sourceImageSize(snapshot.data)
        try checkCancellation?()
        guard let extent else { return nil }
        directImageNaturalSizes[source] = extent
        return extent
    }

    func preparedNaturalImageSize(from url: URL, source: SourceKey,
                                  checkCancellation: (() throws -> Void)? = nil) throws -> CGSize? {
        try preparedNaturalImageSize(from: .externalFile(url), source: source, checkCancellation: checkCancellation)
    }

    func prepareDirectImageSource(
        from input: Input, source expectedSource: SourceKey? = nil,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> PreparedDirectImageSource? {
        try checkCancellation?()
        guard Self.directImageExtensions.contains(input.pathExtension.lowercased()),
              let source = try sourceKey(for: input, checkCancellation: checkCancellation) else { return nil }
        if let expectedSource, expectedSource != source { throw SceneResourceView.ReadError.sourceChanged }
        if let cached = directImageResources[source] {
            return .init(input: input, source: source, data: nil, naturalSize: directImageNaturalSizes[source],
                         resource: cached, budget: decodeCacheBudget)
        }
        if let facts = directImageFacts[source] {
            // A published texture's scalar facts survive decoded eviction.
            // A representation cache miss captures payload on actual load.
            return .init(input: input, source: source, data: nil, naturalSize: facts.naturalSize,
                         resource: nil, budget: decodeCacheBudget)
        }
        guard let snapshot = try sourceSnapshot(input, source: source, checkCancellation: checkCancellation)
        else { return nil }
        let naturalSize = SceneImageTextureUploader.sourceImageSize(snapshot.data)
        try checkCancellation?()
        if let naturalSize { directImageNaturalSizes[source] = naturalSize }
        return .init(input: input, source: source, data: snapshot.data, naturalSize: naturalSize,
                     resource: nil, budget: decodeCacheBudget)
    }

    func prepareDirectImageSource(
        from url: URL, source: SourceKey? = nil, checkCancellation: (() throws -> Void)? = nil
    ) throws -> PreparedDirectImageSource? {
        try prepareDirectImageSource(from: .externalFile(url), source: source, checkCancellation: checkCancellation)
    }

    func preparedNaturalImageSize(
        from prepared: PreparedDirectImageSource, checkCancellation: (() throws -> Void)? = nil
    ) throws -> CGSize? {
        try checkCancellation?()
        return prepared.naturalSize
    }

    private func loadDirectImage(
        input: Input, source: SourceKey, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        prepared: PreparedDirectImageSource?, checkCancellation: (() throws -> Void)?
    ) throws -> SceneTextureLoadOutcome {
        let resource: DirectImageResource
        if let cached = prepared?.resource ?? directImageResources[source] {
            resource = cached
        } else {
            let data: Data
            if let captured = prepared?.data { data = captured }
            else {
                guard let snapshot = try sourceSnapshot(input, source: source, checkCancellation: checkCancellation)
                else { return .decodeFailed("read failed: \(input.lastPathComponent)") }
                data = snapshot.data
            }
            directImageDecodeAttemptCount += 1
            if let image = SceneImageTextureUploader.decodeSourceImage(data) {
                resource = .decoded(image)
            } else {
                resource = .failed("CGImageSource failed to decode \(input.lastPathComponent)")
            }
            try checkCancellation?()
            prepared?.resource = resource
            if case let .decoded(image) = resource,
               decodeCacheLease.reserve(Self.decodedByteCost(image)) {
                directImageResources[source] = resource
            } else if case .failed = resource { directImageResources[source] = resource }
        }
        prepared?.didDecode = true
        let cgImage: CGImage
        switch resource {
        case let .decoded(image): cgImage = image
        case let .failed(message): return .decodeFailed(message)
        }
        directImageNaturalSizes[source] = CGSize(width: cgImage.width, height: cgImage.height)
        directImageFacts[source] = .init(naturalSize: CGSize(width: cgImage.width, height: cgImage.height),
            isOpaque: SceneImageTextureUploader.imageHasNoAlpha(cgImage))
        return SceneImageTextureUploader.upload(image: cgImage, purpose: purpose,
            maxDimension: Self.maxTextureDimension, uploadCommandQueue: uploadCommandQueue, device: device)
    }

    // TEX payloads may be raw, BC, embedded images, video, or a bounded volume;
    // dispatch only after the container metadata has been preserved.
    private func loadWallpaperEngineTex(
        input: Input,
        source: SourceKey,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice,
        preparedResource: TexResource? = nil,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneTextureLoadOutcome {
        guard let resource = try preparedResource ?? texResource(from: input, source: source,
                                                               checkCancellation: checkCancellation) else {
            return .decodeFailed("read failed: \(input.lastPathComponent)")
        }
        guard let container = resource.container else {
            return .decodeFailed("TEX parse failed: \(resource.parseError ?? "unknown error")")
        }
        if container.format == 0 {
            return loadFormatZeroContainer(
                container, embeddedMipChainIsValid: resource.hasValidTexb3EmbeddedMipChain,
                source: source, purpose: purpose, device: device
            )
        }
        return makeDirectUploadTexture(
            from: container,
            purpose: purpose,
            device: device
        ) ?? .unsupportedTexFormat(code: container.format)
    }

    private func texResource(from input: Input, source: SourceKey,
                             checkCancellation: (() throws -> Void)?) throws -> TexResource? {
        try checkCancellation?()
        if let cached = texResources[source] { return cached }
        guard let snapshot = try sourceSnapshot(input, source: source, checkCancellation: checkCancellation)
        else { return nil }
        let resource: TexResource
        do {
            resource = TexResource(container: try SceneTexContainerReader().read(data: snapshot.data), parseError: nil)
        } catch {
            // Invalid author TEX remains a local decode failure; IO/cancel is
            // deliberately outside this pure-parser catch.
            resource = TexResource(container: nil, parseError: error.localizedDescription)
        }
        try checkCancellation?()
        if let byteCost = resource.decodedByteCost, decodeCacheLease.reserve(byteCost) {
            texResources[source] = resource
        }
        return resource
    }

    func sourceKey(for input: Input, checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {
        try checkCancellation?()
        return try Self.currentSourceKey(for: input, checkCancellation: checkCancellation)
    }

    func sourceKey(for url: URL, checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {
        try sourceKey(for: .externalFile(url), checkCancellation: checkCancellation)
    }

    static func currentSourceKey(for input: Input, checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {
        do { return try input.currentIdentity(checkCancellation: checkCancellation) }
        catch let error as SceneResourceView.ReadError {
            switch error {
            case .missing, .unreadable: return nil
            default: throw error
            }
        }
    }

    static func currentSourceKey(for url: URL) throws -> SourceKey? {
        try currentSourceKey(for: .externalFile(url))
    }

    func sourceSnapshot(_ input: Input, source: SourceKey,
                                    checkCancellation: (() throws -> Void)?) throws -> SceneResourceView.ReadSnapshot? {
        do { return try input.readSnapshot(expectedIdentity: source, checkCancellation: checkCancellation) }
        catch let error as SceneResourceView.ReadError {
            switch error {
            case .missing, .unreadable: return nil
            default: throw error
            }
        }
    }

    private func loadFormatZeroContainer(
        _ container: SceneTexContainer,
        embeddedMipChainIsValid: Bool,
        source: SourceKey,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = container.mips.first else {
            return .decodeFailed("TEX container has no mip data")
        }

        if container.isVolume || purpose.requiresVolumeTexture {
            return SceneTextureMipUploader.uploadVolume(
                container: container,
                purpose: purpose,
                device: device
            )
        }

        if SceneTexContainer.isVideoPayload(firstMip.data) {
            return .texContainsVideoPayload
        }

        if container.containerVersion == .texb0003,
           SceneTexContainer.isEmbeddedImagePayload(firstMip.data)
            || [2, 13].contains(container.freeImageFormat),
           !embeddedMipChainIsValid {
            return .decodeFailed("compiled TEX embedded mip metadata does not match its payload")
        }

        if SceneTexContainer.isEmbeddedImagePayload(firstMip.data) {
            guard let images = cachedTexEmbeddedImages(
                source: source,
                payloads: container.mips.map(\.data)
            ) else {
                return .decodeFailed("compiled TEX embedded mip chain could not be decoded")
            }
            let uploaded = purpose.preservesSourceChannels
                ? SceneTextureMipUploader.uploadEmbeddedDataImages(
                    images,
                    purpose: purpose,
                    maximumDimension: Self.maxTextureDimension,
                    device: device
                )
                : SceneTextureMipUploader.uploadEmbeddedImages(
                    images,
                    device: device
                )
            if let uploaded {
                return uploaded
            }
            guard container.mips.count == 1, let image = images.first else {
                return .decodeFailed(
                    "compiled TEX embedded mip chain could not be preserved"
                )
            }
            return SceneImageTextureUploader.upload(
                image: image,
                purpose: purpose,
                maxDimension: Self.maxTextureDimension,
                mipmapGeneration: .baseLevelOnly,
                uploadCommandQueue: uploadCommandQueue,
                device: device
            )
        }

        guard let expectedRawByteCount = SceneTexContainer.byteCount2D(
            width: firstMip.width, height: firstMip.height, bytesPerElement: 4
        ) else {
            return .decodeFailed("raw ARGB8888 dimensions exceed addressable byte size")
        }
        if firstMip.data.count == expectedRawByteCount {
            if purpose.preservesSourceChannels {
                return SceneTextureMipUploader.uploadRaw(
                    container: container,
                    pixelFormat: .rgba8Unorm,
                    bytesPerPixel: 4,
                    device: device
                )
            }
            return SceneTextureMipUploader.uploadRawRGBA(
                container: container,
                device: device
            )
        }

        return .decodeFailed("raw ARGB8888 mip data size mismatch: \(firstMip.data.count) != \(expectedRawByteCount)")
    }

    private func cachedTexEmbeddedImages(
        source: SourceKey,
        payloads: [Data]
    ) -> [CGImage]? {
        if let cached = texEmbeddedImageResources[source] {
            guard case let .decoded(images) = cached else { return nil }
            return images
        }
        texEmbeddedImageDecodeAttemptCount += payloads.count
        guard let images = SceneTextureMipUploader.decodeEmbeddedImages(payloads) else {
            texEmbeddedImageResources[source] = .failed
            return nil
        }
        let byteCost = images.reduce(into: 0) { total, image in
            let (next, overflow) = total.addingReportingOverflow(
                Self.decodedByteCost(image)
            )
            total = overflow ? Int.max : next
        }
        if decodeCacheLease.reserve(byteCost) {
            texEmbeddedImageResources[source] = .decoded(images)
        }
        return images
    }

    private static func decodedByteCost(_ image: CGImage) -> Int {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(
            by: image.height
        )
        return overflow ? Int.max : cost
    }

    private func makeDirectUploadTexture(
        from container: SceneTexContainer,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome? {
        if let pixelFormat = container.metalPixelFormat {
            return SceneCompressedTextureUploader.upload(
                container: container,
                pixelFormat: pixelFormat,
                purpose: purpose,
                uploadCommandQueue: uploadCommandQueue,
                device: device
            )
        }
        if let pixelFormat = container.rawMetalPixelFormat,
           let bytesPerPixel = container.rawBytesPerPixel {
            return SceneTextureMipUploader.uploadRaw(
                container: container,
                pixelFormat: pixelFormat,
                bytesPerPixel: bytesPerPixel,
                device: device
            )
        }
        if container.format == 0 {
            return SceneTextureMipUploader.uploadRawRGBA(container: container, device: device)
        }
        return nil
    }

}
