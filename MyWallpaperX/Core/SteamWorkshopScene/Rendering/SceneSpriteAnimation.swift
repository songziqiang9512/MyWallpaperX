import CoreFoundation
import Foundation
import Metal
import simd

protocol SceneSpriteTexturePlayback: AnyObject {
    func encode(
        sceneTime: Float,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    )
}

struct SceneSpriteAnimation {
    let frames: [SceneTexContainer.SpriteFrame]
    let duration: Float
    /// Immutable playback timeline shared by every particle using this texture.
    /// Particle assembly must not rebuild/map the same authored frame durations
    /// once per live particle and once per rendered frame.
    let frameDurations: [Float]
    let frameEndTimes: [Float]
    private let frameAspectRatios: [Float]
    private let texturePlayback: SceneSpriteTexturePlayback?

    init?(
        frames: [SceneTexContainer.SpriteFrame],
        texturePlayback: SceneSpriteTexturePlayback? = nil,
        textureSize: SIMD2<Int>? = nil,
        nominalFrameSize: SIMD2<Float>? = nil
    ) {
        guard !frames.isEmpty,
              texturePlayback != nil || frames.allSatisfy({ $0.imageIndex == 0 }) else {
            return nil
        }
        self.frames = frames
        frameDurations = frames.map { Self.effectiveDuration($0.duration) }
        var elapsed: Float = 0
        frameEndTimes = frameDurations.map { value in
            elapsed += value
            return elapsed
        }
        duration = elapsed
        frameAspectRatios = frames.map {
            Self.frameAspectRatio(
                for: $0,
                textureSize: textureSize,
                nominalFrameSize: nominalFrameSize
            )
        }
        self.texturePlayback = texturePlayback
    }

    init?(container: SceneTexContainer, sourceURL: URL) {
        self.init(
            frames: container.spriteFrames,
            textureSize: SIMD2(container.textureWidth, container.textureHeight),
            nominalFrameSize: Self.nominalFrameSize(
                from: sourceURL,
                expectedFrameCount: container.spriteFrames.count
            )
        )
    }

    static func load(from url: URL) -> SceneSpriteAnimation? {
        guard url.pathExtension.localizedLowercase == "tex",
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let container = try? SceneTexContainerReader().read(data: data) else {
            return nil
        }
        return SceneSpriteAnimation(container: container, sourceURL: url)
    }

    func transform(at elapsed: Float) -> SceneTextureUVTransform {
        guard texturePlayback == nil else { return .identity }
        guard frames.count > 1, duration > 0 else {
            return transform(for: frames[0])
        }
        var remaining = elapsed.truncatingRemainder(dividingBy: duration)
        if remaining < 0 { remaining += duration }
        for frame in frames {
            let frameDuration = Self.effectiveDuration(frame.duration)
            if remaining < frameDuration {
                return transform(for: frame)
            }
            remaining -= frameDuration
        }
        return transform(for: frames[frames.count - 1])
    }

    func encode(
        sceneTime: Float,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) {
        texturePlayback?.encode(
            sceneTime: sceneTime,
            commandBuffer: commandBuffer,
            transaction: transaction
        )
    }

    func aspectRatio(forFrameAt index: Int) -> Float {
        guard frameAspectRatios.indices.contains(index) else { return 1 }
        return frameAspectRatios[index]
    }

    static func nominalFrameSize(
        from textureURL: URL,
        expectedFrameCount: Int
    ) -> SIMD2<Float>? {
        guard expectedFrameCount > 0,
              let data = try? Data(
                  contentsOf: URL(fileURLWithPath: textureURL.path + "-json"),
                  options: .mappedIfSafe
              ),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sequences = root["spritesheetsequences"] as? [[String: Any]],
              sequences.count == 1,
              let sequence = sequences.first,
              let frameCount = finiteNumber(sequence["frames"]),
              frameCount.rounded() == frameCount,
              Int(frameCount) == expectedFrameCount,
              let width = finiteNumber(sequence["width"]),
              let height = finiteNumber(sequence["height"]),
              width > 0, height > 0,
              width <= Double(Float.greatestFiniteMagnitude),
              height <= Double(Float.greatestFiniteMagnitude),
              validAspect(width / height) else {
            return nil
        }
        return SIMD2(Float(width), Float(height))
    }

    var reportSummary: String {
        String(
            format: "; sprite animation frames=%d duration=%.3fs",
            frames.count,
            duration
        )
    }

    private func transform(for frame: SceneTexContainer.SpriteFrame) -> SceneTextureUVTransform {
        SceneTextureUVTransform(
            origin: frame.origin,
            xAxis: frame.xAxis,
            yAxis: frame.yAxis
        )
    }

    private static func effectiveDuration(_ duration: Float) -> Float {
        duration.isFinite && duration > 0 ? duration : 1.0 / 60.0
    }

    private static func frameAspectRatio(
        for frame: SceneTexContainer.SpriteFrame,
        textureSize: SIMD2<Int>?,
        nominalFrameSize: SIMD2<Float>?
    ) -> Float {
        if let nominalFrameSize,
           validAspect(Double(nominalFrameSize.x / nominalFrameSize.y)) {
            return nominalFrameSize.x / nominalFrameSize.y
        }
        guard let textureSize, textureSize.x > 0, textureSize.y > 0 else { return 1 }
        let pixels = SIMD2(Float(textureSize.x), Float(textureSize.y))
        let width = simd_length(frame.xAxis * pixels)
        let height = simd_length(frame.yAxis * pixels)
        let aspect = width / height
        return validAspect(Double(aspect)) ? aspect : 1
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func validAspect(_ aspect: Double) -> Bool {
        aspect.isFinite && aspect >= 1.0 / 64.0 && aspect <= 64
    }
}

extension SceneLayerFragmentUniforms {
    static func neutral(
        alpha: Float = 1,
        dependencyBlendMode: Int? = nil
    ) -> SceneLayerFragmentUniforms {
        let frame = SceneTextureUVTransform.identity
        return SceneLayerFragmentUniforms(
            time: 0,
            alpha: alpha,
            dependencyBlendMode: UInt32(dependencyBlendMode ?? 0),
            usesDependencyBlend: dependencyBlendMode == nil ? 0 : 1,
            cursorUV: .zero,
            sourceSampling: .zero,
            tint: SIMD4(repeating: 1),
            textureFrame0: frame.uniform0,
            textureFrame1: frame.uniform1
        )
    }
}
