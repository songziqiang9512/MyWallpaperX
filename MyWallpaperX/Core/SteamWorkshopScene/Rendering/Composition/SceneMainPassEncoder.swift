import Metal

final class SceneMainPassEncoder {
    private let commandBuffer: MTLCommandBuffer
    private let target: MTLTexture
    private let clearColor: MTLClearColor
    private let clearEnabled: Bool
    private var nextLoadAction: MTLLoadAction
    private var activeEncoder: MTLRenderCommandEncoder?
    private var activeDepthTexture: MTLTexture?
    private let submissionOwner: SceneMainPassEncoder?
    private var compositionPins: [SceneGraphRenderTargetResidencyPin] = []
    private var isFinished = false
    private var encodingFailed = false

    var targetExtent: (width: Int, height: Int) {
        (target.width, target.height)
    }

    var targetPixelFormat: MTLPixelFormat { target.pixelFormat }

    init(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        clearColor: MTLClearColor,
        clearEnabled: Bool,
        submissionOwner: SceneMainPassEncoder? = nil
    ) {
        self.submissionOwner = submissionOwner
        self.commandBuffer = commandBuffer
        self.target = target
        self.clearColor = clearColor
        self.clearEnabled = clearEnabled
        self.nextLoadAction = clearEnabled ? .clear : .load
    }

    /// Group passes share their root submission's lifetime. A source capture
    /// can fail after encoding, so its allocation still lives until completion.
    func retainCompositionPin(_ pin: SceneGraphRenderTargetResidencyPin?) {
        guard let pin else { return }
        if let submissionOwner { submissionOwner.retainCompositionPin(pin) }
        else { compositionPins.append(pin) }
    }

    func armCompositionPins() {
        let pins = compositionPins
        compositionPins.removeAll()
        commandBuffer.addCompletedHandler { _ in pins.forEach { $0.release() } }
    }

    func cancelCompositionPins() {
        compositionPins.forEach { $0.release() }
        compositionPins.removeAll()
    }

    func encoder() -> MTLRenderCommandEncoder? {
        encoder(depthTexture: nil, clearsDepth: false, clearDepth: 1)
    }

    func encoder(
        depthTexture: MTLTexture?,
        clearsDepth: Bool,
        clearDepth: Double = 1
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
            descriptor.depthAttachment.clearDepth = clearDepth
            descriptor.depthAttachment.storeAction = .store
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            encodingFailed = true
            return nil
        }
        encoder.label = "Scene main layer composite"
        SceneGPUCensus.recordMainPassRender(usesDepth: depthTexture != nil)
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

    @discardableResult
    func finishEnsuringClear() -> Bool {
        guard !isFinished else { return !encodingFailed }
        if activeEncoder == nil {
            _ = encoder()
        }
        activeEncoder?.endEncoding()
        activeEncoder = nil
        isFinished = true
        return !encodingFailed
    }
}
