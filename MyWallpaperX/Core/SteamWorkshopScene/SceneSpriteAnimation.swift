import Foundation
import simd

struct SceneTextureUVTransform {
    let origin: SIMD2<Float>
    let xAxis: SIMD2<Float>
    let yAxis: SIMD2<Float>

    nonisolated static let identity = SceneTextureUVTransform(
        origin: .zero,
        xAxis: SIMD2(1, 0),
        yAxis: SIMD2(0, 1)
    )

    var uniform0: SIMD4<Float> {
        SIMD4(origin.x, origin.y, xAxis.x, xAxis.y)
    }

    var uniform1: SIMD4<Float> {
        SIMD4(yAxis.x, yAxis.y, 0, 0)
    }
}

struct SceneSpriteAnimation {
    let frames: [SceneTexContainer.SpriteFrame]
    let duration: Float

    init?(frames: [SceneTexContainer.SpriteFrame]) {
        guard !frames.isEmpty, frames.allSatisfy({ $0.imageIndex == 0 }) else {
            return nil
        }
        self.frames = frames
        self.duration = frames.reduce(0) { $0 + Self.effectiveDuration($1.duration) }
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
            textureFrame0: frame.uniform0,
            textureFrame1: frame.uniform1
        )
    }
}
