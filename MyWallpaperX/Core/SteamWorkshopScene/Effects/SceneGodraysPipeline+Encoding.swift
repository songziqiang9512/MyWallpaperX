import Metal

extension SceneGodraysPipeline {
    func draw<Uniforms>(
        state: MTLRenderPipelineState,
        textures: [MTLTexture],
        uniforms: inout Uniforms,
        length: Int,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard commandBuffer.commandQueue.device.registryID == deviceRegistryID,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return false
        }
        encoder.setRenderPipelineState(state)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setFragmentBytes(&uniforms, length: length, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    func validColor(_ texture: MTLTexture, usage: MTLTextureUsage) -> Bool {
        texture.textureType == .type2D
            && [.bgra8Unorm, .rgba8Unorm, .r8Unorm].contains(texture.pixelFormat)
            && texture.width > 0
            && texture.height > 0
            && (usage.contains(.renderTarget)
                ? texture.mipmapLevelCount == 1
                : texture.mipmapLevelCount > 0)
            && texture.sampleCount == 1
            && texture.usage.contains(usage)
            && texture.device.registryID == deviceRegistryID
    }
}
