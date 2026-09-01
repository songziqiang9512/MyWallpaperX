import Metal

final class SceneMainPassEncoder {
    private let commandBuffer: MTLCommandBuffer
    private let target: MTLTexture
    private let clearColor: MTLClearColor
    private var nextLoadAction: MTLLoadAction = .clear
    private var activeEncoder: MTLRenderCommandEncoder?
    private var activeDepthTexture: MTLTexture?
    private var isFinished = false

    var targetExtent: (width: Int, height: Int) {
        (target.width, target.height)
    }

    init(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        clearColor: MTLClearColor
    ) {
        self.commandBuffer = commandBuffer
        self.target = target
        self.clearColor = clearColor
    }

    func encoder() -> MTLRenderCommandEncoder? {
        encoder(depthTexture: nil, clearsDepth: false)
    }

    func encoder(
        depthTexture: MTLTexture?,
        clearsDepth: Bool
    ) -> MTLRenderCommandEncoder? {
        guard !isFinished else { return nil }
        if let activeEncoder,
           activeDepthTexture === depthTexture,
           !clearsDepth {
            return activeEncoder
        }
        closeForOffscreen()

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = nextLoadAction
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store
        if let depthTexture {
            descriptor.depthAttachment.texture = depthTexture
            descriptor.depthAttachment.loadAction = clearsDepth ? .clear : .load
            descriptor.depthAttachment.clearDepth = 1
            descriptor.depthAttachment.storeAction = .store
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        encoder.label = "Scene main layer composite"
        activeEncoder = encoder
        activeDepthTexture = depthTexture
        nextLoadAction = .load
        return encoder
    }

    func closeForOffscreen() {
        activeEncoder?.endEncoding()
        activeEncoder = nil
        activeDepthTexture = nil
    }

    func encodeOffscreen<Result>(
        _ operation: (MTLCommandBuffer) -> Result
    ) -> Result {
        closeForOffscreen()
        return operation(commandBuffer)
    }

    func withReadableTarget<Result>(
        _ operation: (MTLTexture, MTLCommandBuffer) -> Result
    ) -> Result? {
        guard encoder() != nil else { return nil }
        closeForOffscreen()
        return operation(target, commandBuffer)
    }

    func finishEnsuringClear() {
        guard !isFinished else { return }
        if activeEncoder == nil {
            _ = encoder()
        }
        activeEncoder?.endEncoding()
        activeEncoder = nil
        isFinished = true
    }
}
