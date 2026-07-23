import Metal

final class SceneMainPassEncoder {
    private let commandBuffer: MTLCommandBuffer
    private let target: MTLTexture
    private let clearColor: MTLClearColor
    private var nextLoadAction: MTLLoadAction = .clear
    private var activeEncoder: MTLRenderCommandEncoder?
    private var isFinished = false

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
        guard !isFinished else { return nil }
        if let activeEncoder { return activeEncoder }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = nextLoadAction
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        encoder.label = "Scene main layer composite"
        activeEncoder = encoder
        nextLoadAction = .load
        return encoder
    }

    func closeForOffscreen() {
        activeEncoder?.endEncoding()
        activeEncoder = nil
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
