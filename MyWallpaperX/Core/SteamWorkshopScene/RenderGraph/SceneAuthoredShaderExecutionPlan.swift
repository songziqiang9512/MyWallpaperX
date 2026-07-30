import CoreGraphics
import Foundation

nonisolated struct SceneAuthoredShaderExecutionPlan {
    enum Profile {
        case genericFramebuffer
        case scroll
    }

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
    let renderState: SceneMaterialRenderState
    let mappedSize: CGSize
    let framebufferTextureSlots: [Int]
    let uniformBindings: [UniformBinding]
    let profile: Profile

    init(
        cacheKey: String,
        program: SceneAuthoredShaderProgram,
        renderState: SceneMaterialRenderState,
        mappedSize: CGSize,
        framebufferTextureSlots: [Int],
        uniformBindings: [UniformBinding],
        profile: Profile = .genericFramebuffer
    ) {
        self.cacheKey = cacheKey
        self.program = program
        self.renderState = renderState
        self.mappedSize = mappedSize
        self.framebufferTextureSlots = framebufferTextureSlots
        self.uniformBindings = uniformBindings
        self.profile = profile
    }

    func offscreenSize(for requestedSize: CGSize) -> CGSize? {
        program.offscreenSize(viewportSize: requestedSize)
    }
}
