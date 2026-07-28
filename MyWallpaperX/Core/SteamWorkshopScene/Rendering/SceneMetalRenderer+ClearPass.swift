import Metal
import QuartzCore

extension SceneMetalRenderer {
    func renderClearPass(to drawable: CAMetalDrawable, clearColor: MTLClearColor? = nil) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = clearColor ?? sceneClearColor
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
