import Foundation
import Metal
import MetalPerformanceShaders

fileprivate struct SceneMultiImageSpriteFrameRegion {
    let imageIndex: Int
    let duration: Float
    let sourceX: Int
    let sourceY: Int
    let width: Int
    let height: Int
}

fileprivate struct SceneMultiImageSpriteLayout {
    let frames: [SceneMultiImageSpriteFrameRegion]
    let duration: Float
    let outputWidth: Int
    let outputHeight: Int

    init?(
        authoredFrames: [SceneTexContainer.SpriteFrame],
        imageSizes: [(width: Int, height: Int)]
    ) {
        guard !authoredFrames.isEmpty else { return nil }
        var regions: [SceneMultiImageSpriteFrameRegion] = []
        regions.reserveCapacity(authoredFrames.count)
        for frame in authoredFrames {
            guard imageSizes.indices.contains(frame.imageIndex),
                  frame.duration.isFinite, frame.duration >= 0,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.origin.x >= 0, frame.origin.y >= 0,
                  frame.xAxis.x.isFinite, frame.xAxis.y.isFinite,
                  frame.yAxis.x.isFinite, frame.yAxis.y.isFinite,
                  abs(frame.xAxis.y) < 0.000_001,
                  abs(frame.yAxis.x) < 0.000_001,
                  frame.xAxis.x > 0,
                  frame.yAxis.y > 0 else {
                return nil
            }
            let source = imageSizes[frame.imageIndex]
            let scaled = (
                x: frame.origin.x * Float(source.width),
                y: frame.origin.y * Float(source.height),
                width: frame.xAxis.x * Float(source.width),
                height: frame.yAxis.y * Float(source.height)
            )
            guard scaled.x.isFinite, scaled.y.isFinite,
                  scaled.width.isFinite, scaled.height.isFinite,
                  scaled.x <= Float(source.width),
                  scaled.y <= Float(source.height),
                  scaled.width <= Float(source.width),
                  scaled.height <= Float(source.height),
                  let sourceX = Self.integralPixel(scaled.x),
                  let sourceY = Self.integralPixel(scaled.y),
                  let width = Self.integralPixel(scaled.width),
                  let height = Self.integralPixel(scaled.height) else {
                return nil
            }
            guard sourceX >= 0, sourceY >= 0,
                  width > 0, height > 0,
                  width <= SceneTextureLoader.maxTextureDimension,
                  height <= SceneTextureLoader.maxTextureDimension,
                  sourceX + width <= source.width,
                  sourceY + height <= source.height else {
                return nil
            }
            regions.append(SceneMultiImageSpriteFrameRegion(
                imageIndex: frame.imageIndex,
                duration: Self.effectiveDuration(frame.duration),
                sourceX: sourceX,
                sourceY: sourceY,
                width: width,
                height: height
            ))
        }
        guard let first = regions.first,
              regions.allSatisfy({
                  $0.width == first.width && $0.height == first.height
              }) else {
            return nil
        }
        let totalDuration = regions.reduce(0) { $0 + $1.duration }
        guard totalDuration.isFinite else { return nil }
        frames = regions
        duration = totalDuration
        outputWidth = first.width
        outputHeight = first.height
    }

    private static func effectiveDuration(_ duration: Float) -> Float {
        duration > 0 ? duration : 1.0 / 60.0
    }

    private static func integralPixel(_ value: Float) -> Int? {
        let rounded = value.rounded()
        guard abs(value - rounded) <= 0.000_1 else { return nil }
        return Int(rounded)
    }
}

fileprivate struct SceneMultiImageSpriteAdmissionPlan {
    let pixelFormat: MTLPixelFormat
    let layout: SceneMultiImageSpriteLayout

    init?(container: SceneTexContainer) {
        guard container.imageCount > 1,
              container.imageCount <= SceneMultiImageSpriteTextureSet.maximumImageCount,
              let pixelFormat = container.metalPixelFormat,
              [.bc1_rgba, .bc2_rgba, .bc3_rgba].contains(pixelFormat) else {
            return nil
        }
        let firstMips = container.images.compactMap(\.mips.first)
        guard firstMips.count == container.imageCount,
              firstMips.allSatisfy({
                  $0.width > 0 && $0.height > 0
                      && $0.width <= SceneMultiImageSpriteTextureSet.maximumSourceDimension
                      && $0.height <= SceneMultiImageSpriteTextureSet.maximumSourceDimension
              }) else {
            return nil
        }
        guard let layout = SceneMultiImageSpriteLayout(
            authoredFrames: container.spriteFrames,
            imageSizes: firstMips.map { ($0.width, $0.height) }
        ) else {
            return nil
        }
        self.pixelFormat = pixelFormat
        self.layout = layout
    }
}

fileprivate final class SceneMultiImageSpriteTextureSet {
    static let maximumImageCount = 16
    static let maximumSourceDimension = 16_384

    let textures: [MTLTexture]

    init?(
        container: SceneTexContainer,
        plan: SceneMultiImageSpriteAdmissionPlan,
        device: MTLDevice
    ) {
        var textures: [MTLTexture] = []
        textures.reserveCapacity(container.imageCount)
        for image in container.images {
            let outcome = SceneCompressedTextureUploader.uploadNativeImage(
                image,
                pixelFormat: plan.pixelFormat,
                device: device
            )
            guard case let .loaded(texture) = outcome else { return nil }
            textures.append(texture)
        }
        self.textures = textures
    }
}

final class SceneSpriteFrameSubmissionTracker {
    struct Token {
        let id: UInt64
        let frameIndex: Int
    }

    private let lock = NSLock()
    private var nextID: UInt64 = 0
    private var latest: Token?

    func begin(frameIndex: Int) -> Token? {
        lock.lock()
        defer { lock.unlock() }
        guard latest?.frameIndex != frameIndex else { return nil }
        nextID &+= 1
        let token = Token(id: nextID, frameIndex: frameIndex)
        latest = token
        return token
    }

    func complete(_ token: Token, succeeded: Bool) {
        if !succeeded { cancel(token) }
    }

    func cancel(_ token: Token) {
        lock.lock()
        defer { lock.unlock() }
        if latest?.id == token.id {
            latest = nil
        }
    }
}

final class SceneMultiImageSpritePlayback: SceneSpriteTexturePlayback {
    let texture: MTLTexture
    private let textureSet: SceneMultiImageSpriteTextureSet
    private let frames: [SceneMultiImageSpriteFrameRegion]
    private let duration: Float
    private let device: MTLDevice
    private let residentReservation: SceneMultiImageSpriteResidentBudget.Reservation
    private let submissionTracker = SceneSpriteFrameSubmissionTracker()

    fileprivate init?(
        textureSet: SceneMultiImageSpriteTextureSet,
        layout: SceneMultiImageSpriteLayout,
        device: MTLDevice,
        residentReservation: SceneMultiImageSpriteResidentBudget.Reservation
    ) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: layout.outputWidth,
            height: layout.outputHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        self.texture = texture
        self.textureSet = textureSet
        frames = layout.frames
        duration = layout.duration
        self.device = device
        self.residentReservation = residentReservation
    }

    func encode(
        sceneTime: Float,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) {
        let frameIndex = frameIndex(at: sceneTime)
        guard let submission = submissionTracker.begin(frameIndex: frameIndex) else {
            return
        }

        let frame = frames[frameIndex]
        let conversion = MPSImageConversion(
            device: device,
            srcAlpha: .nonPremultiplied,
            destAlpha: .premultiplied,
            backgroundColor: nil,
            conversionInfo: nil
        )
        conversion.offset = MPSOffset(x: frame.sourceX, y: frame.sourceY, z: 0)
        conversion.clipRect = MTLRegionMake2D(0, 0, frame.width, frame.height)
        conversion.encode(
            commandBuffer: commandBuffer,
            sourceTexture: textureSet.textures[frame.imageIndex],
            destinationTexture: texture
        )
        transaction.registerRollback { [weak self] in
            self?.submissionTracker.cancel(submission)
        }
        commandBuffer.addCompletedHandler { [weak self] completed in
            self?.submissionTracker.complete(
                submission,
                succeeded: completed.status == .completed
            )
        }
    }

    private func frameIndex(at elapsed: Float) -> Int {
        guard frames.count > 1, duration > 0 else { return 0 }
        var remaining = elapsed.truncatingRemainder(dividingBy: duration)
        if remaining < 0 { remaining += duration }
        for (index, frame) in frames.enumerated() {
            if remaining < frame.duration { return index }
            remaining -= frame.duration
        }
        return frames.count - 1
    }
}

final class SceneMultiImageSpriteTextureLoader {
    enum Outcome {
        case loaded(SceneMultiImageSpritePlayback)
        case unsupported(String)
    }

    static let defaultResidentByteBudget = 384 * 1_024 * 1_024

    private struct TextureSetKey: Hashable {
        let source: SceneTextureLoader.SourceKey
        let deviceRegistryID: UInt64
    }

    private struct CachedTextureSet {
        let textureSet: SceneMultiImageSpriteTextureSet
        let residentReservation: SceneMultiImageSpriteResidentBudget.Reservation
    }

    private let residentBudget: SceneMultiImageSpriteResidentBudget
    private var textureSets: [TextureSetKey: CachedTextureSet] = [:]

    init(residentByteBudget: Int = defaultResidentByteBudget) {
        residentBudget = SceneMultiImageSpriteResidentBudget(limit: min(
            max(residentByteBudget, 0),
            Self.defaultResidentByteBudget
        ))
    }

    func playback(
        source: SceneTextureLoader.SourceKey,
        container: SceneTexContainer,
        device: MTLDevice,
        sourceIsCurrent: () -> Bool
    ) -> Outcome {
        guard sourceIsCurrent() else {
            return .unsupported("file changed before sprite allocation")
        }
        guard container.isAnimated, !container.spriteFrames.isEmpty,
              let plan = SceneMultiImageSpriteAdmissionPlan(container: container) else {
            return .unsupported("unsupported image, codec, or frame layout")
        }

        let key = TextureSetKey(source: source, deviceRegistryID: device.registryID)
        let cachedSet = textureSets[key]
        guard let costs = SceneMultiImageSpriteTextureCost.estimate(
            container: container,
            pixelFormat: plan.pixelFormat,
            outputWidth: plan.layout.outputWidth,
            outputHeight: plan.layout.outputHeight,
            device: device
        ) else {
            return .unsupported("texture allocation size unavailable")
        }
        let sourceReservation = cachedSet == nil
            ? residentBudget.reserve(cost: costs.source)
            : nil
        guard cachedSet != nil || sourceReservation != nil else {
            return .unsupported(
                "resident budget exceeded: requested=\(costs.source)"
                    + " remaining=\(residentBudget.remainingCost)"
            )
        }
        guard let destinationReservation = residentBudget.reserve(
            cost: costs.destination
        ) else {
            return .unsupported(
                "resident budget exceeded: requested=\(costs.destination)"
                    + " remaining=\(residentBudget.remainingCost)"
            )
        }

        let textureSet: SceneMultiImageSpriteTextureSet
        if let cachedSet {
            textureSet = cachedSet.textureSet
        } else {
            guard let loaded = SceneMultiImageSpriteTextureSet(
                container: container,
                plan: plan,
                device: device
            ) else {
                return .unsupported("native BC source allocation failed")
            }
            textureSet = loaded
        }
        guard let playback = SceneMultiImageSpritePlayback(
            textureSet: textureSet,
            layout: plan.layout,
            device: device,
            residentReservation: destinationReservation
        ) else {
            return .unsupported("RGBA frame target allocation failed")
        }
        guard sourceIsCurrent() else {
            return .unsupported("file changed while loading sprite textures")
        }
        if cachedSet == nil {
            guard let sourceReservation else {
                return .unsupported("source budget reservation unavailable")
            }
            textureSets[key] = CachedTextureSet(
                textureSet: textureSet,
                residentReservation: sourceReservation
            )
        }
        return .loaded(playback)
    }
}
