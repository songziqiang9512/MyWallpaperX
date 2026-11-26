import Metal
import simd

final class SceneMainPassEncoder {
    struct MultisampleAttachments {
        let color: MTLTexture
        let depth: MTLTexture

        var sampleCount: Int { color.sampleCount }

        init?(color: MTLTexture, depth: MTLTexture) {
            guard color.textureType == .type2DMultisample, depth.textureType == .type2DMultisample,
                  color.storageMode == .memoryless, depth.storageMode == .memoryless,
                  color.usage.contains(.renderTarget), depth.usage.contains(.renderTarget),
                  color.device === depth.device, color.sampleCount > 1,
                  color.sampleCount == depth.sampleCount,
                  color.width == depth.width, color.height == depth.height,
                  depth.pixelFormat == .depth32Float else { return nil }
            self.color = color
            self.depth = depth
        }

        fileprivate func resolves(to target: MTLTexture) -> Bool {
            target.textureType == .type2D && target.sampleCount == 1
                && target.storageMode != .memoryless && target.usage.contains(.renderTarget)
                && target.device === color.device && target.pixelFormat == color.pixelFormat
                && target.width == color.width && target.height == color.height
        }
    }

    private let commandBuffer: MTLCommandBuffer
    private let target: MTLTexture
    private let clearColor: MTLClearColor
    private var initialLoadAction: MTLLoadAction?
    private var activeEncoder: MTLRenderCommandEncoder?
    private var activeDepthTexture: MTLTexture?
    private var openedSingleSampleDepth = false
    private(set) var submittedRasterSampleCount: Int?
    private(set) var didFailMultisamplePreparation = false
    private let submissionOwner: SceneMainPassEncoder?
    private let worldClipToTargetClip: simd_float4x4?
    private(set) var multisampleAttachments: MultisampleAttachments?
    private var auxiliaryReleases: [() -> Void] = []
    private var isFinished = false
    private var encodingFailed = false

    var targetExtent: (width: Int, height: Int) {
        (target.width, target.height)
    }

    var targetPixelFormat: MTLPixelFormat { target.pixelFormat }
    var rasterSampleCount: Int { multisampleAttachments?.sampleCount ?? target.sampleCount }
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

    @discardableResult
    func prepareMultisampling(_ attachments: MultisampleAttachments?) -> Bool {
        guard isSceneRoot, worldClipToTargetClip == nil, initialLoadAction == .clear,
              !isFinished, !encodingFailed, multisampleAttachments == nil else { return false }
        guard let attachments, attachments.resolves(to: target) else {
            didFailMultisamplePreparation = true
            return false
        }
        multisampleAttachments = attachments
        return true
    }

    func beginMultisamplingAfterColorPrefix(
        attachmentsForTarget: (MTLTexture) -> MultisampleAttachments?,
        prepareSeed: (MTLTexture, MTLCommandBuffer) -> ((MTLRenderCommandEncoder) -> Void)?
    ) -> Bool {
        guard isSceneRoot, worldClipToTargetClip == nil, !isFinished, !encodingFailed,
              multisampleAttachments == nil else { return false }
        if initialLoadAction == .clear {
            return prepareMultisampling(attachmentsForTarget(target))
        }
        // The original root color stays readable until the native encoder opens.
        guard initialLoadAction == nil, !openedSingleSampleDepth, !target.isFramebufferOnly else { return false }
        guard let attachments = attachmentsForTarget(target), attachments.resolves(to: target) else {
            didFailMultisamplePreparation = true
            return false
        }
        closeForOffscreen()
        guard let seed = prepareSeed(target, commandBuffer) else {
            didFailMultisamplePreparation = true
            return false
        }
        multisampleAttachments = attachments
        initialLoadAction = .dontCare
        guard let native = encoder(required: false) else {
            multisampleAttachments = nil
            initialLoadAction = nil
            didFailMultisamplePreparation = true
            return false
        }
        seed(native)
        return true
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
        if let multisampleAttachments {
            // A closed memoryless pass has resolved color and discarded its depth.
            guard (depthTexture == nil || depthTexture === multisampleAttachments.depth),
                  !clearsDepth || (activeEncoder == nil && clearDepth == 0),
                  activeEncoder != nil || initialLoadAction != nil else {
                if required { encodingFailed = true }
                return nil
            }
            if let activeEncoder { return activeEncoder }
        } else {
            if let activeEncoder, activeDepthTexture === depthTexture, !clearsDepth {
                return activeEncoder
            }
            closeForOffscreen()
        }

        let descriptor = MTLRenderPassDescriptor()
        let color = descriptor.colorAttachments[0]!
        color.clearColor = clearColor
        if let multisampleAttachments {
            color.texture = multisampleAttachments.color
            color.loadAction = initialLoadAction!
            color.resolveTexture = target
            color.storeAction = .multisampleResolve
            descriptor.depthAttachment.texture = multisampleAttachments.depth
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.clearDepth = 0
            descriptor.depthAttachment.storeAction = .dontCare
        } else {
            color.texture = target
            color.loadAction = initialLoadAction ?? .load
            color.storeAction = .store
        }
        if multisampleAttachments == nil, let depthTexture {
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
        submittedRasterSampleCount = max(submittedRasterSampleCount ?? 1, rasterSampleCount)
#if DEBUG
        SceneGPUCensus.recordMainPassRender(usesDepth: descriptor.depthAttachment.texture != nil)
        if let trace = compositionTrace, trace.isCompositionSelected {
            if initialLoadAction == .clear {
                trace.recordComposition(.init(kind: "clear", target: compositionTarget,
                    access: "attachment-clear", outcome: "encoded"))
            }
            if isSceneRoot {
                let depth = descriptor.depthAttachment!
                var details = ["sampleCount": String(rasterSampleCount),
                    "colorLoad": String(color.loadAction.rawValue), "colorStore": String(color.storeAction.rawValue)]
                if let texture = depth.texture {
                    details["depthToken"] = String(UInt(bitPattern: ObjectIdentifier(texture)))
                    details["depthSamples"] = String(texture.sampleCount)
                    details["depthLoad"] = String(depth.loadAction.rawValue)
                    details["depthClear"] = String(depth.clearDepth)
                    details["depthStore"] = String(depth.storeAction.rawValue)
                }
                trace.recordComposition(.init(kind: "main-raster-open",
                    source: color.resolveTexture == nil ? nil : color.texture.map { .init($0, role: "multisample-color") },
                    target: compositionTarget, access: "render-encoder", outcome: "encoded", details: details))
            }
        }
#endif
        activeEncoder = encoder
        activeDepthTexture = depthTexture
        if multisampleAttachments == nil && depthTexture != nil { openedSingleSampleDepth = true }
        initialLoadAction = nil
        return encoder
    }

    func closeForOffscreen() {
        if multisampleAttachments != nil, activeEncoder != nil { encodingFailed = true }
        endEncoder()
    }

    func resolveForSingleSampleTail() -> Bool {
        guard !encodingFailed, !isFinished else { return false }
        guard multisampleAttachments != nil else { return true }
        if activeEncoder == nil, encoder() == nil { return false }
        endEncoder()
        multisampleAttachments = nil
        return true
    }

    private func endEncoder() {
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
        guard multisampleAttachments == nil else {
            encodingFailed = true
            return nil
        }
        if initialLoadAction != nil, encoder() == nil { return nil }
        closeForOffscreen()
        return operation(target, commandBuffer)
    }

    @discardableResult
    func finishEnsuringClear() -> Bool {
        guard !isFinished else { return !encodingFailed }
        if initialLoadAction != nil { _ = encoder() }
        endEncoder()
        isFinished = true
        return !encodingFailed
    }
}
