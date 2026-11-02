
import Foundation
import CoreGraphics
import Darwin
import ImageIO
import Metal
import simd

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        isWebM: Bool = false,
        cacheDirectory: URL,
        device: MTLDevice
    ) { return nil }
}

final class SceneSourceUpdateTransaction {
    private var rollbacks: [() -> Void] = []

    func registerRollback(_ action: @escaping () -> Void) {
        rollbacks.append(action)
    }

    func commit() { rollbacks.removeAll() }
}

enum SceneGraphExecutionResetReason { case test }

final class StubResolvedMaterialRuntime {
    var shouldDeferFrame = false
    func invalidate(reason: SceneGraphExecutionResetReason) { _ = reason }
}

struct SceneImageLayerCompositor {
    var resolvedMaterialRuntime: StubResolvedMaterialRuntime? = nil
}

struct SceneRenderDescriptor {
    struct Layer {
        let contentKind: String
        let brightness: Double?
    }
}

struct SceneDependencyEffectInput {
    let blendMode: Int
}

struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
    let tint: SIMD3<Float>
    var brightness: Float? = nil
}

struct SceneLayerEffectSourceExtent {
    let pixelSize: CGSize
}

struct SceneImageLayerDrawRequest {
    let layer: SceneRenderDescriptor.Layer
    let texture: MTLTexture
    let uniforms: SceneImageLayerUniformValues
    let dependencyEffects: [SceneDependencyEffectInput]
    let effectSourceExtent: SceneLayerEffectSourceExtent?
    let sourceSample: SceneBaseImageTextureSample?
    var sourceMaterialAlpha: Float = 1
    var sourceMaterialColor: SIMD3<Float> = SIMD3(repeating: 1)

    func resolvedBaseTextureSample() -> SceneBaseImageTextureSample? {
        sourceSample
    }
}
