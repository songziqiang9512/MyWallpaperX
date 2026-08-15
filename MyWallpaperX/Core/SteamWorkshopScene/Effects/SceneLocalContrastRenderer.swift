import Metal
import simd

enum SceneLocalContrastRenderer {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func render(
        targets: SceneGraphRenderTargetTable,
        quarterAIdentity: Graph.TextureIdentity,
        quarterBIdentity: Graph.TextureIdentity,
        nodeIndices: [Int],
        strength: Float,
        pipeline: SceneLocalContrastPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let plan = targets.plan
        guard strength.isFinite, (0...5).contains(strength),
              plan.logicalTargets.count == 2,
              quarterAIdentity != quarterBIdentity else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=scalar-shape")
            return nil
        }
        guard let effect = plan.output.effect,
              validFramebufferIdentity(
                  quarterAIdentity,
                  effect: effect,
                  layerID: plan.layerID
              ), validFramebufferIdentity(
                  quarterBIdentity,
                  effect: effect,
                  layerID: plan.layerID
              ) else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=identity")
            return nil
        }
        guard let quarterASpecification = plan.logicalTargets.first(where: {
                  $0.identity == quarterAIdentity
              }), let quarterBSpecification = plan.logicalTargets.first(where: {
                  $0.identity == quarterBIdentity
              }) else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=declaration")
            return nil
        }
        guard nodeIndices.count == 4,
              Set(nodeIndices).count == 4,
              nodeIndices == nodeIndices.sorted(),
              validQuarterA(
                  quarterASpecification,
                  nodeIndices: nodeIndices
              ), validQuarterB(
                  quarterBSpecification,
                  nodeIndices: nodeIndices
              ),
              Set(plan.logicalTargets.map(\.identity)) == Set([
                  quarterAIdentity,
                  quarterBIdentity,
              ]) else {
            NSLog(
                "MWX DEBUG SCENE: phase=local-contrast-encode failure=lifetime"
                    + " a=%d,%d,%d,%d b=%d,%d,%d,%d",
                quarterASpecification.lifetime.firstWriteNodeIndex,
                quarterASpecification.lifetime.lastWriteNodeIndex,
                quarterASpecification.lifetime.firstReadNodeIndex ?? -1,
                quarterASpecification.lifetime.lastReadNodeIndex ?? -1,
                quarterBSpecification.lifetime.firstWriteNodeIndex,
                quarterBSpecification.lifetime.lastWriteNodeIndex,
                quarterBSpecification.lifetime.firstReadNodeIndex ?? -1,
                quarterBSpecification.lifetime.lastReadNodeIndex ?? -1
            )
            return nil
        }
        guard let quarterA = targets.texture(for: quarterAIdentity),
              let quarterB = targets.texture(for: quarterBIdentity) else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=allocation")
            return nil
        }
        guard validTextures(
            targets: targets,
            quarterA: quarterA,
            quarterB: quarterB
        ) else {
            NSLog(
                "MWX DEBUG SCENE: phase=local-contrast-encode"
                    + " failure=texture-contract input=%dx%d output=%dx%d"
                    + " quarterA=%dx%d quarterB=%dx%d formats=%lu,%lu,%lu,%lu",
                targets.inputTexture.width,
                targets.inputTexture.height,
                targets.outputTexture.width,
                targets.outputTexture.height,
                quarterA.width,
                quarterA.height,
                quarterB.width,
                quarterB.height,
                targets.inputTexture.pixelFormat.rawValue,
                targets.outputTexture.pixelFormat.rawValue,
                quarterA.pixelFormat.rawValue,
                quarterB.pixelFormat.rawValue
            )
            return nil
        }

        let horizontalStep = 1 / Float(quarterA.width)
        let verticalStep = 1 / Float(quarterA.height)
        guard pipeline.encodeDownsample(
            source: targets.inputTexture,
            target: quarterA,
            commandBuffer: commandBuffer
        ) else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=downsample")
            return nil
        }
        guard pipeline.encodeGaussian(
            source: quarterA,
            target: quarterB,
            step: SIMD2(horizontalStep, 0),
            commandBuffer: commandBuffer
        ) else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=gaussian-x")
            return nil
        }
        guard pipeline.encodeGaussian(
            source: quarterB,
            target: quarterA,
            step: SIMD2(0, verticalStep),
            commandBuffer: commandBuffer
        ) else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=gaussian-y")
            return nil
        }
        guard pipeline.encodeCombine(
            blurred: quarterA,
            previous: targets.inputTexture,
            strength: strength,
            target: targets.outputTexture,
            commandBuffer: commandBuffer
        ) else {
            NSLog("MWX DEBUG SCENE: phase=local-contrast-encode failure=combine")
            return nil
        }
        return targets.outputTexture
    }

    private static func validQuarterA(
        _ target: SceneGraphRenderTargetPlan.LogicalTarget,
        nodeIndices: [Int]
    ) -> Bool {
        guard nodeIndices.count == 4 else { return false }
        return target.format == .rgba8888
            && target.lifetime.firstWriteNodeIndex == nodeIndices[0]
            && target.lifetime.lastWriteNodeIndex == nodeIndices[2]
            && target.lifetime.firstReadNodeIndex == nodeIndices[1]
            && target.lifetime.lastReadNodeIndex == nodeIndices[3]
    }

    private static func validQuarterB(
        _ target: SceneGraphRenderTargetPlan.LogicalTarget,
        nodeIndices: [Int]
    ) -> Bool {
        guard nodeIndices.count == 4 else { return false }
        return target.format == .rgba8888
            && target.lifetime.firstWriteNodeIndex == nodeIndices[1]
            && target.lifetime.lastWriteNodeIndex == nodeIndices[1]
            && target.lifetime.firstReadNodeIndex == nodeIndices[2]
            && target.lifetime.lastReadNodeIndex == nodeIndices[2]
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
