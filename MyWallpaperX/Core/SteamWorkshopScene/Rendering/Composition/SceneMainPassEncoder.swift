import Metal
import simd

final class SceneMainPassEncoder {
    private let commandBuffer: MTLCommandBuffer
    private let target: MTLTexture
    private let clearColor: MTLClearColor
    private var initialLoadAction: MTLLoadAction?
    private var activeEncoder: MTLRenderCommandEncoder?
    private var activeDepthTexture: MTLTexture?
    private let submissionOwner: SceneMainPassEncoder?
    private let worldClipToTargetClip: simd_float4x4?
    private var auxiliaryReleases: [() -> Void] = []
    private var isFinished = false
    private var encodingFailed = false

    var targetExtent: (width: Int, height: Int) {
        (target.width, target.height)
    }

    var targetPixelFormat: MTLPixelFormat { target.pixelFormat }
    var isSceneRoot: Bool { submissionOwner == nil }
#if DEBUG
    var compositionTrace: SceneEffectExecutionFrameTrace?
    var compositionTarget: SceneCompositionTextureObservation {
        .init(target, role: submissionOwner == nil ? "main-color" : "group-color")
    }
#endif

    func rasterModelViewProjection(_ worldMVP: simd_float4x4) -> simd_float4x4 {
        worldClipToTargetClip.map { $0 * worldMVP } ?? worldMVP
    }

    func rasterClipProjection(_ viewProjection: simd_float4x4) -> simd_float4x4 {
        guard worldClipToTargetClip != nil else { return viewProjection }
        let rows = rasterClipRows
        let map = simd_float4x4(columns: (
            SIMD4(rows.x.x, rows.y.x, 0, 0),
            SIMD4(rows.x.y, rows.y.y, 0, 0),
            SIMD4(rows.x.z, rows.y.z, 1, 0),
            SIMD4(rows.x.w, rows.y.w, 0, 1)
        ))
        return map * viewProjection
    }

    var rasterFrontFacing: MTLWinding {
        let rows = rasterClipRows
        let determinant = Double(rows.x.x) * Double(rows.y.y)
            - Double(rows.x.y) * Double(rows.y.x)
        return determinant < 0 ? .clockwise : .counterClockwise
    }

    var rasterClipRows: (x: SIMD4<Float>, y: SIMD4<Float>) {
        guard let map = worldClipToTargetClip else {
            return (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0))
        }
        // The source plane's affine homogeneous scale must not rescale the
        // camera's Z/W when a draw keeps its own depth relationship.
        let scale = map.columns.3.w
        return (
            SIMD4(map.columns.0.x, map.columns.1.x, map.columns.2.x, map.columns.3.x) / scale,
            SIMD4(map.columns.0.y, map.columns.1.y, map.columns.2.y, map.columns.3.y) / scale
        )
    }

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
        submissionOwner: SceneMainPassEncoder? = nil,
        worldClipToTargetClip: simd_float4x4? = nil
    ) {
        self.submissionOwner = submissionOwner
        self.worldClipToTargetClip = worldClipToTargetClip
        self.commandBuffer = commandBuffer
        self.target = target
        self.clearColor = clearColor
        self.initialLoadAction = clearEnabled ? .clear : .load
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

    func encoder(required: Bool = true) -> MTLRenderCommandEncoder? {
        encoder(depthTexture: nil, clearsDepth: false, clearDepth: 1, required: required)
    }

    func encoder(
        depthTexture: MTLTexture?,
        clearsDepth: Bool,
        clearDepth: Double = 1,
        required: Bool = true
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
        descriptor.colorAttachments[0].loadAction = initialLoadAction ?? .load
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store
        if let depthTexture {
            descriptor.depthAttachment.texture = depthTexture
            descriptor.depthAttachment.loadAction = clearsDepth ? .clear : .load
            descriptor.depthAttachment.clearDepth = clearDepth
            descriptor.depthAttachment.storeAction = .store
        }
        #if DEBUG
        let timestampEncoder = SceneGPUStageTimestampHook.render(commandBuffer, descriptor, role: "main-composite")
        #else
        let timestampEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        #endif
        guard let encoder = timestampEncoder else {
            if required { encodingFailed = true }
            return nil
        }
        encoder.label = "Scene main layer composite"
#if DEBUG
        SceneGPUCensus.recordMainPassRender(usesDepth: depthTexture != nil)
#endif
#if DEBUG
        if initialLoadAction == .clear, let trace = compositionTrace, trace.isCompositionSelected {
            trace.recordComposition(.init(kind: "clear", target: compositionTarget,
                access: "attachment-clear", outcome: "encoded"))
        }
#endif
        activeEncoder = encoder
        activeDepthTexture = depthTexture
        initialLoadAction = nil
        return encoder
    }

    func closeForOffscreen() {
#if DEBUG
        if let activeEncoder { SceneGPUStageTimestampHook.endedMain(activeEncoder) }
#endif
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
        guard !isFinished else { return nil }
        if initialLoadAction != nil, encoder() == nil { return nil }
        closeForOffscreen()
        return operation(target, commandBuffer)
    }

    @discardableResult
    func finishEnsuringClear() -> Bool {
        guard !isFinished else { return !encodingFailed }
        if initialLoadAction != nil { _ = encoder() }
        closeForOffscreen()
        isFinished = true
        return !encodingFailed
    }
}
