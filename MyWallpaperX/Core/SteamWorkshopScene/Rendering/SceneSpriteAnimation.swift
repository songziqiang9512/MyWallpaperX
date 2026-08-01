import Foundation
import Metal
import simd

protocol SceneSpriteTexturePlayback: AnyObject {
    func encode(sceneTime: Float, wallDate: Date, commandBuffer: MTLCommandBuffer)
}

private final class SceneSpriteAnimationPlaybackState {
    private var clock: SceneTextureAnimationPlaybackClock

    init(plan: SceneTextureAnimationPlaybackPlan, frames: [SceneTexContainer.SpriteFrame]) {
        clock = SceneTextureAnimationPlaybackClock(
            plan: plan,
            frameDurations: frames.map(\.duration)
        )
    }

    func frameIndex(sceneTime: Float, wallDate: Date) -> Int {
        clock.frameIndex(at: sceneTime, wallDate: wallDate)
    }
}

struct SceneSpriteAnimation {
    let frames: [SceneTexContainer.SpriteFrame]
    let duration: Float
    private let texturePlayback: SceneSpriteTexturePlayback?
    private let playbackState: SceneSpriteAnimationPlaybackState?

    init?(
        frames: [SceneTexContainer.SpriteFrame],
        texturePlayback: SceneSpriteTexturePlayback? = nil,
        playbackPlan: SceneTextureAnimationPlaybackPlan? = nil
    ) {
        guard !frames.isEmpty,
              texturePlayback != nil || frames.allSatisfy({ $0.imageIndex == 0 }) else {
            return nil
        }
        self.frames = frames
        self.duration = frames.reduce(0) { $0 + Self.effectiveDuration($1.duration) }
        self.texturePlayback = texturePlayback
        playbackState = texturePlayback == nil
            ? playbackPlan.map { SceneSpriteAnimationPlaybackState(plan: $0, frames: frames) }
            : nil
    }

    static func load(from url: URL) -> SceneSpriteAnimation? {
        guard url.pathExtension.localizedLowercase == "tex",
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let container = try? SceneTexContainerReader().read(data: data) else {
            return nil
        }
        return SceneSpriteAnimation(frames: container.spriteFrames)
    }

    func transform(at elapsed: Float) -> SceneTextureUVTransform {
        transform(at: elapsed, wallDate: Date(timeIntervalSince1970: 0))
    }

    func transform(at elapsed: Float, wallDate: Date) -> SceneTextureUVTransform {
        guard texturePlayback == nil else { return .identity }
        guard frames.count > 1, duration > 0 else {
            return transform(for: frames[0])
        }
        if let frameIndex = playbackState?.frameIndex(
            sceneTime: elapsed,
            wallDate: wallDate
        ) {
            return transform(for: frames[frameIndex])
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

    func encode(sceneTime: Float, wallDate: Date, commandBuffer: MTLCommandBuffer) {
        texturePlayback?.encode(
            sceneTime: sceneTime,
            wallDate: wallDate,
            commandBuffer: commandBuffer
        )
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
}

extension SceneLayerFragmentUniforms {
    static func neutral(
        alpha: Float = 1,
        dependencyBlendMode: Int? = nil
    ) -> SceneLayerFragmentUniforms {
        let frame = SceneTextureUVTransform.identity
        var flags = SceneEffectFlags()
        if dependencyBlendMode != nil {
            flags.insert(.dependencyBlend)
        }
        return SceneLayerFragmentUniforms(
            time: 0,
            alpha: alpha,
            effectFlags: flags.rawValue,
            dependencyBlendMode: UInt32(dependencyBlendMode ?? 0),
            cursorUV: .zero,
            _pad1: .zero,
            tint: SIMD4(repeating: 1),
            effectParams0: .zero,
            effectParams1: .zero,
            effectParams2: .zero,
            effectParams3: .zero,
            effectParams4: .zero,
            effectParams5: SIMD4(1, 1, 0, 0),
            textureFrame0: frame.uniform0,
            textureFrame1: frame.uniform1
        )
    }
}
