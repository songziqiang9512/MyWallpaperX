import CoreGraphics
import Foundation

nonisolated struct SceneAuthoredShaderExecutionPlan {
    struct UniformBinding {
        enum Source {
            case renderSize
            case modelViewProjection
            case time
            case dayTime
            case frameTime
            case pointerPosition
            case pointerPositionLast
            case screen
            case texelSize(scale: Double)
            case textureResolution(slot: Int)
            case constant([Double])
        }

        let field: SceneAuthoredShaderUniformLayout.Field
        let source: Source
    }

    let cacheKey: String
    let program: SceneAuthoredShaderProgram
    let mappedSize: CGSize
    let framebufferTextureSlots: [Int]
    let uniformBindings: [UniformBinding]

    var offscreenSize: CGSize? {
        program.offscreenSize(viewportSize: mappedSize)
    }
}
