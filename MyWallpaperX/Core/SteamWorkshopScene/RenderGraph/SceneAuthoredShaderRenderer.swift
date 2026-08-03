import CoreGraphics
import Foundation
import Metal
import simd

enum SceneAuthoredShaderRenderer {
    static func encode(
        plan: SceneAuthoredShaderExecutionPlan,
        source: MTLTexture,
        target: MTLTexture,
        frame: SceneAuthoredShaderFrameInputs,
        pipelineCache: SceneAuthoredShaderPipelineCache,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let width = Float(target.width)
        let height = Float(target.height)
        let modelViewProjection = simd_float4x4(diagonal: SIMD4<Float>(
            2 / width,
            2 / height,
            1,
            1
        ))
        let physicalSize = CGSize(width: source.width, height: source.height)
        return encode(
            plan: plan,
            source: source,
            target: target,
            inputs: SceneAuthoredShaderUniformInputs(
                frameIndex: frame.frameIndex,
                renderSize: CGSize(width: target.width, height: target.height),
                screenSize: frame.screenSize,
                modelViewProjection: modelViewProjection,
                sceneTime: frame.sceneTime,
                dayTime: frame.dayTime,
                frameTime: frame.frameTime,
                pointerCurrentNDC: frame.pointerCurrentNDC,
                pointerPreviousNDC: frame.pointerPreviousNDC,
                texturePhysicalSizes: Dictionary(
                    uniqueKeysWithValues: plan.framebufferTextureSlots.map {
                        ($0, physicalSize)
                    }
                )
            ),
            pipelineCache: pipelineCache,
            commandBuffer: commandBuffer
        )
    }

    static func encode(
        plan: SceneAuthoredShaderExecutionPlan,
        source: MTLTexture,
        target: MTLTexture,
        inputs: SceneAuthoredShaderUniformInputs,
        pipelineCache: SceneAuthoredShaderPipelineCache,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            plan: plan,
            source: source,
            target: target,
            inputs: inputs,
            commandBuffer: commandBuffer
        ),
        let pipeline = pipelineCache.pipeline(for: plan),
        let uniforms = SceneAuthoredShaderUniformBinder.encode(
            plan: plan,
            inputs: inputs
        ) else {
            return false
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return false
        }
        encoder.label = "Scene authored shader pass"
        encoder.setRenderPipelineState(pipeline.state)
        encoder.setCullMode(.none)
        uniforms.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            encoder.setVertexBytes(baseAddress, length: bytes.count, index: 0)
            encoder.setFragmentBytes(baseAddress, length: bytes.count, index: 0)
        }
        for slot in plan.framebufferTextureSlots {
            encoder.setVertexTexture(source, index: slot)
            encoder.setVertexSamplerState(pipeline.sampler, index: slot)
            encoder.setFragmentTexture(source, index: slot)
            encoder.setFragmentSamplerState(pipeline.sampler, index: slot)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private static func valid(
        plan: SceneAuthoredShaderExecutionPlan,
        source: MTLTexture,
        target: MTLTexture,
        inputs: SceneAuthoredShaderUniformInputs,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let deviceID = commandBuffer.commandQueue.device.registryID
        let textureSlots = plan.program.textureBindings.map(\.slot).sorted()
        let plannedSlots = plan.framebufferTextureSlots.sorted()
        let renderWidth = inputs.renderSize.width
        let renderHeight = inputs.renderSize.height
        guard plan.renderState.matchesFullscreenOverwrite(
                  alphaWriting: .unspecified
              ),
              renderWidth.isFinite,
              renderHeight.isFinite,
              renderWidth > 0,
              renderHeight > 0,
              let maximumSize = plan.offscreenSize(for: inputs.renderSize),
              maximumSize.width.isFinite,
              maximumSize.height.isFinite,
              maximumSize.width > 0,
              maximumSize.height > 0 else {
            return false
        }
        guard !plannedSlots.isEmpty,
              plannedSlots == textureSlots,
              Set(plannedSlots).count == plannedSlots.count,
              plan.program.uniformLayout.byteSize > 0,
              plan.program.uniformLayout.byteSize <= 4_096,
              source.textureType == .type2D,
              target.textureType == .type2D,
              source.pixelFormat == .bgra8Unorm,
              target.pixelFormat == .bgra8Unorm,
              source.width > 0,
              source.width == target.width,
              source.height > 0,
              source.height == target.height,
              source.mipmapLevelCount == 1,
              target.mipmapLevelCount == 1,
              source.sampleCount == 1,
              target.sampleCount == 1,
              source.usage.contains(.shaderRead),
              target.usage.contains(.renderTarget),
              source.device.registryID == deviceID,
              target.device.registryID == deviceID,
              ObjectIdentifier(source) != ObjectIdentifier(target),
              Int(renderWidth.rounded()) == target.width,
              Int(renderHeight.rounded()) == target.height,
              target.width <= Int(maximumSize.width.rounded(.up)),
              target.height <= Int(maximumSize.height.rounded(.up)) else {
            return false
        }
        let physicalSize = CGSize(width: source.width, height: source.height)
        return plannedSlots.allSatisfy {
            inputs.texturePhysicalSizes[$0] == physicalSize
        }
    }
}
