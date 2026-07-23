import Metal
import simd

enum SceneLocalContrastRenderer {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func render(
        targets: SceneGraphRenderTargetTable,
        quarterAIdentity: Graph.TextureIdentity,
        quarterBIdentity: Graph.TextureIdentity,
        strength: Float,
        pipeline: SceneLocalContrastPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let plan = targets.plan
        guard strength.isFinite,
              (0...5).contains(strength),
              plan.logicalTargets.count == 2,
              quarterAIdentity != quarterBIdentity,
              let effect = plan.output.effect,
              validFramebufferIdentity(
                quarterAIdentity,
                effect: effect,
                layerID: plan.layerID
              ), validFramebufferIdentity(
                quarterBIdentity,
                effect: effect,
                layerID: plan.layerID
              ), let quarterASpecification = plan.logicalTargets.first(where: {
                $0.identity == quarterAIdentity
              }), let quarterBSpecification = plan.logicalTargets.first(where: {
                $0.identity == quarterBIdentity
              }), validQuarterA(quarterASpecification),
              validQuarterB(quarterBSpecification),
              Set(plan.logicalTargets.map(\.identity)) == Set([
                quarterAIdentity,
                quarterBIdentity,
              ]), let quarterA = targets.texture(for: quarterAIdentity),
              let quarterB = targets.texture(for: quarterBIdentity),
              validTextures(
                targets: targets,
                quarterA: quarterA,
                quarterB: quarterB
              ) else {
            return nil
        }

        let horizontalStep = 1 / Float(quarterA.width)
        let verticalStep = 1 / Float(quarterA.height)
        guard pipeline.encodeDownsample(
            source: targets.inputTexture,
            target: quarterA,
            commandBuffer: commandBuffer
        ), pipeline.encodeGaussian(
            source: quarterA,
            target: quarterB,
            step: SIMD2(horizontalStep, 0),
            commandBuffer: commandBuffer
        ), pipeline.encodeGaussian(
            source: quarterB,
            target: quarterA,
            step: SIMD2(0, verticalStep),
            commandBuffer: commandBuffer
        ), pipeline.encodeCombine(
            blurred: quarterA,
            previous: targets.inputTexture,
            strength: strength,
            target: targets.outputTexture,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return targets.outputTexture
    }

    private static func validQuarterA(
        _ target: SceneGraphRenderTargetPlan.LogicalTarget
    ) -> Bool {
        target.format == .rgba8888
            && target.lifetime.firstWriteNodeIndex == 0
            && target.lifetime.lastWriteNodeIndex == 2
            && target.lifetime.firstReadNodeIndex == 1
            && target.lifetime.lastReadNodeIndex == 3
    }

    private static func validQuarterB(
        _ target: SceneGraphRenderTargetPlan.LogicalTarget
    ) -> Bool {
        target.format == .rgba8888
            && target.lifetime.firstWriteNodeIndex == 1
            && target.lifetime.lastWriteNodeIndex == 1
            && target.lifetime.firstReadNodeIndex == 2
            && target.lifetime.lastReadNodeIndex == 2
    }

    private static func validTextures(
        targets: SceneGraphRenderTargetTable,
        quarterA: MTLTexture,
        quarterB: MTLTexture
    ) -> Bool {
        let input = targets.inputTexture
        let output = targets.outputTexture
        let expectedWidth = max(1, input.width / 4)
        let expectedHeight = max(1, input.height / 4)
        return input.pixelFormat == .bgra8Unorm
            && output.pixelFormat == .bgra8Unorm
            && quarterA.pixelFormat == .rgba8Unorm
            && quarterB.pixelFormat == .rgba8Unorm
            && output.width == input.width
            && output.height == input.height
            && quarterA.width == expectedWidth
            && quarterA.height == expectedHeight
            && quarterB.width == expectedWidth
            && quarterB.height == expectedHeight
            && ObjectIdentifier(input) != ObjectIdentifier(output)
            && ObjectIdentifier(quarterA) != ObjectIdentifier(quarterB)
    }

    private static func validFramebufferIdentity(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        identity.kind == .framebuffer
            && identity.layerID == layerID
            && identity.effect == effect
            && identity.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
