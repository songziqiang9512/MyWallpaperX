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
    private var auxiliaryReleases: [() -> Void] = []
    private var isFinished = false
    private var encodingFailed = false

    var targetExtent: (width: Int, height: Int) {
        (target.width, target.height)
    }

    var targetPixelFormat: MTLPixelFormat { target.pixelFormat }

    func belongs(to commandBuffer: MTLCommandBuffer) -> Bool {
        self.commandBuffer === commandBuffer
    }

    /// Validate a prepared draw against the actual attachment and submission
    /// before beginning a render encoder or clearing any main-pass pixels.
    func encodePreparedDraw(
        _ prepare: (MTLTexture, MTLCommandBuffer) -> ((MTLRenderCommandEncoder) -> Void)?
    ) -> Bool {
        guard !isFinished,
              let draw = prepare(target, commandBuffer),
              let encoder = encoder() else { return false }
        draw(encoder)
        return true
    }

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
        retainAuxiliaryRelease { pin.release() }
    }

    /// Geometry auxiliaries and composition targets share this submission's
    /// completion/cancellation boundary, including captures that later fail.
    func retainAuxiliaryRelease(_ release: @escaping () -> Void) {
        if let submissionOwner { submissionOwner.retainAuxiliaryRelease(release) }
        else { auxiliaryReleases.append(release) }
    }

    func armCompositionPins() {
        let releases = auxiliaryReleases
        auxiliaryReleases.removeAll()
        commandBuffer.addCompletedHandler { _ in releases.forEach { $0() } }
    }

    func cancelCompositionPins() {
        let releases = auxiliaryReleases
        auxiliaryReleases.removeAll()
        releases.forEach { $0() }
    }

    deinit { cancelCompositionPins() }

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
