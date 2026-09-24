import Foundation
import Metal

/// Prepares one already-finalized material Program before any commands are
/// encoded. A graph executor can therefore prepare every pass first and only
/// start its command buffer after the complete transaction is admissible.
final class SceneResolvedMaterialPassEncoder {
    struct PreparedPass {
        let fragmentOutput: SceneShaderColorRepresentation?
        let storedContent: SceneTextureContent
        let bindingSlots: [Int]
        let bindingSamplings: [SceneTextureSampling]
        let uniformByteCount: Int

        fileprivate let ownerToken: UUID
        fileprivate let resetGeneration: UInt64
        fileprivate let pipeline: MTLRenderPipelineState
        fileprivate let target: MTLTexture
        fileprivate let bindings: [Binding]
        fileprivate let uniformBytes: Data
        fileprivate let uniformBufferIndex: Int
    }

    fileprivate struct Binding {
        let slot: Int
        let texture: MTLTexture
        let sampler: MTLSamplerState
        let sampling: SceneTextureSampling
    }

    enum PipelineOrigin: Equatable {
        case launchWarmup
        case framePreparation
    }

    enum PipelineEntry {
        case ready(MTLRenderPipelineState, origin: PipelineOrigin)
        case failed(PreparationFailure, origin: PipelineOrigin)
    }

    private enum MetalLibraryEntry {
        case ready(MTLLibrary)
        case failed(PreparationFailure)
    }

    let device: MTLDevice
    private let samplers: SceneTextureSamplerStateSet
    private let ownerToken = UUID()
    private let libraryCondition = NSCondition()
    private var librariesByMetalSource: [String: MetalLibraryEntry] = [:]
    private var compilingMetalSources = Set<String>()
    private var libraryCompilationAttempts = 0
    let lock = NSLock()
    var entries: [SceneResolvedMaterialProgram.MetalCompileStateKey: PipelineEntry] = [:]
    var resetGeneration: UInt64 = 0
    var compilationAttempts = 0
    var failedPipelines = 0
    var launchWarmupHits = 0
    var launchWarmupFailureHits = 0
    var consumedLaunchWarmupKeys = Set<SceneResolvedMaterialProgram.MetalCompileStateKey>()
    var consumedLaunchWarmupFailureKeys = Set<SceneResolvedMaterialProgram.MetalCompileStateKey>()
    #if SCENE_GRAPH_TESTING
    var testingPreparationFailuresByPreparedKey: [String: PreparationFailure] = [:]
    #endif

    var cachedPipelineCount: Int { withLock { entries.count } }
    var pipelineCompilationAttemptCount: Int { withLock { compilationAttempts } }
    var failedPipelineCount: Int { withLock { failedPipelines } }
    var launchWarmupHitCount: Int { withLock { launchWarmupHits } }
    var launchWarmupFailureHitCount: Int { withLock { launchWarmupFailureHits } }
    var metalLibraryCompilationAttemptCount: Int {
        libraryCondition.lock()
        defer { libraryCondition.unlock() }
        return libraryCompilationAttempts
    }

    init?(device: MTLDevice) {
        guard let samplers = SceneTextureSamplerStateSet(device: device) else {
            return nil
        }
        self.device = device
        self.samplers = samplers
    }

    /// Returns an immutable pass only after all Program, resource, attachment,
    /// sampler, uniform and pipeline facts are ready. No Metal command is
    /// encoded by this operation.
    func prepare(
        program: SceneResolvedMaterialProgram,
        target: MTLTexture
    ) -> PreparedPass? {
        try? prepareResult(program: program, target: target).get()
    }

    func prepareResult(
        program: SceneResolvedMaterialProgram,
        target: MTLTexture
    ) -> Result<PreparedPass, PreparationFailure> {
        prepareAuthorizedResult(
            program: program,
            target: target,
            attachmentStorage: .color
        )
    }

    /// The storage kind must come from the admitted material capability. The
    /// ordinary overload above deliberately authorizes color only.
    func prepareResult(
        program: SceneResolvedMaterialProgram,
        target: MTLTexture,
        attachmentStorage: SceneResolvedMaterialAttachmentKind
    ) -> Result<PreparedPass, PreparationFailure> {
        prepareAuthorizedResult(
            program: program,
            target: target,
            attachmentStorage: attachmentStorage
        )
    }

    private func prepareAuthorizedResult(
        program: SceneResolvedMaterialProgram,
        target: MTLTexture,
        attachmentStorage: SceneResolvedMaterialAttachmentKind
    ) -> Result<PreparedPass, PreparationFailure> {
        guard let output = SceneResolvedMaterialAttachmentStorage.storedOutput(
            program.outputContract,
            attachmentStorage: attachmentStorage
        ) else { return .failure(.fragmentOutputRejected) }
        let storedContent = output.content
        guard SceneResolvedMaterialAttachmentStorage.target(
            target,
            belongsTo: device,
            stores: storedContent
        ) else {
            return .failure(.targetRejected)
        }
        guard validUniforms(program) else { return .failure(.uniformsRejected) }
        guard let bindings = validatedBindings(program, target: target) else {
            return .failure(.bindingsRejected)
        }
        #if SCENE_GRAPH_TESTING
        if let failure = withLock({
            testingPreparationFailuresByPreparedKey[program.preparedShader.cacheKey]
        }) {
            return .failure(failure)
        }
        #endif
        let writeMask = SceneResolvedMaterialAttachmentStorage.writeMask(
            for: storedContent
        )
        guard let key = program.metalCompileStateKey(
            attachmentPixelFormat: target.pixelFormat,
            sampleCount: target.sampleCount,
            colorWriteMask: writeMask,
            device: device
        ) else { return .failure(.compileStateKeyRejected) }
        let cached: (
            pipeline: MTLRenderPipelineState,
            generation: UInt64,
            origin: PipelineOrigin
        )
        switch pipeline(
            for: key,
            frontend: program.frontendProgram,
            renderState: program.renderState,
            pixelFormat: target.pixelFormat,
            sampleCount: target.sampleCount,
            writeMask: writeMask,
            origin: .framePreparation
        ) {
        case let .success(value): cached = value
        case let .failure(failure): return .failure(failure)
        }
        recordLaunchWarmupConsumption(
            key: key,
            origin: cached.origin,
            preparedKey: program.preparedShader.cacheKey
        )
        return .success(PreparedPass(
            fragmentOutput: output.colorRepresentation,
            storedContent: storedContent,
            bindingSlots: bindings.map(\.slot),
            bindingSamplings: bindings.map(\.sampling),
            uniformByteCount: program.uniformBytes.count,
            ownerToken: ownerToken,
            resetGeneration: cached.generation,
            pipeline: cached.pipeline,
            target: target,
            bindings: bindings,
            uniformBytes: program.uniformBytes,
            uniformBufferIndex: program.frontendProgram.uniformBufferIndex
        ))
    }

    #if SCENE_GRAPH_TESTING
    func installTestingPreparationFailure(
        _ failure: PreparationFailure,
        preparedKey: String
    ) {
        withLock {
            testingPreparationFailuresByPreparedKey[preparedKey] = failure
        }
    }
    #endif

    /// `true` means the render commands were appended. GPU completion remains
    /// the transaction owner's responsibility; this method never reports a
    /// completed or committed graph transaction.
    func encode(
        _ pass: PreparedPass,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard pass.ownerToken == ownerToken,
              withLock({ pass.resetGeneration == resetGeneration }),
              commandBuffer.status == .notEnqueued,
              commandBuffer.commandQueue.device.registryID == device.registryID,
              SceneResolvedMaterialAttachmentStorage.target(
                  pass.target,
                  belongsTo: device,
                  stores: pass.storedContent
              ),
              pass.bindings.allSatisfy({ valid($0, target: pass.target) }) else {
            return false
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = pass.target
        // Admission proves a full-channel overwrite pipeline state, not that
        // authored geometry rasterizes every target pixel: vertex displacement
        // (e.g. perspective effects) leaves regions unrasterized, and those
        // regions must compose as premultiplied transparent instead of
        // undefined attachment memory.
        if pass.storedContent.isColorContent {
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0,
                green: 0,
                blue: 0,
                alpha: 0
            )
        } else {
            descriptor.colorAttachments[0].loadAction = .dontCare
        }
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return false
        }
        encoder.label = "Scene resolved material pass"
        SceneGPUCensus.recordOffscreenRender(.resolvedMaterial)
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
        encoder.setRenderPipelineState(pass.pipeline)
        encoder.setCullMode(.none)
        if !pass.uniformBytes.isEmpty {
            pass.uniformBytes.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                encoder.setVertexBytes(
                    baseAddress,
                    length: bytes.count,
                    index: pass.uniformBufferIndex
                )
                encoder.setFragmentBytes(
                    baseAddress,
                    length: bytes.count,
                    index: pass.uniformBufferIndex
                )
            }
        }
        for binding in pass.bindings {
            encoder.setVertexTexture(binding.texture, index: binding.slot)
            encoder.setVertexSamplerState(binding.sampler, index: binding.slot)
            encoder.setFragmentTexture(binding.texture, index: binding.slot)
            encoder.setFragmentSamplerState(binding.sampler, index: binding.slot)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
        encoder.endEncoding()
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        // Prepared commands belong to one reset generation. The immutable
        // compile-state entries are content/device keyed and remain valid for
        // this encoder's lifetime, including negative compiler results.
        resetGeneration &+= 1
    }

    private func validUniforms(_ program: SceneResolvedMaterialProgram) -> Bool {
        let layout = program.frontendProgram.uniformLayout
        guard layout.byteSize == program.uniformBytes.count,
              (0 ..< 31).contains(program.frontendProgram.uniformBufferIndex),
              layout.byteSize >= 0,
              layout.byteSize <= 4_096,
              layout.byteSize.isMultiple(of: 16),
              program.exactIdentity.uniformBytes == program.uniformBytes,
              SceneMaterialTextureTransformABI.validates(
                  layout: layout,
                  activeSlots: Set(program.frontendProgram.textureBindings.map(\.slot))
              ),
              program.resolvedUniforms.count == layout.fields.count,
              Set(layout.fields.map(\.name)).count == layout.fields.count,
            program.semanticIdentity.shader.uniformFields == layout.fields.map({
                .init(
                    name: $0.name,
                    valueType: $0.type.rawValue,
                    arrayCount: $0.arrayCount,
                    offset: $0.offset
                )
            }) else {
            return false
        }
        // Program assembly admits fields in offset order. Check the gaps and
        // payloads directly instead of building a hash-set entry for each byte.
        var occupiedEnd = 0
        for (field, resolved) in zip(layout.fields, program.resolvedUniforms) {
            guard resolved.field == field,
                  field.offset >= occupiedEnd,
                  field.offset.isMultiple(of: field.type.alignment),
                  field.offset <= layout.byteSize,
                  field.storageByteSize <= layout.byteSize - field.offset,
                  resolved.encodedValue.count == field.storageByteSize,
                  program.uniformBytes[occupiedEnd ..< field.offset]
                    .allSatisfy({ $0 == 0 }) else {
                return false
            }
            let end = field.offset + field.storageByteSize
            guard program.uniformBytes[field.offset ..< end]
                == resolved.encodedValue else { return false }
            occupiedEnd = end
        }
        return program.uniformBytes[occupiedEnd ..< layout.byteSize]
            .allSatisfy { $0 == 0 }
    }

    private func validatedBindings(
        _ program: SceneResolvedMaterialProgram,
        target: MTLTexture
    ) -> [Binding]? {
        let frontend = program.frontendProgram.textureBindings
        let slots = frontend.map(\.slot)
        guard program.textureSlots.count == 8,
              program.semanticIdentity.textureSlots.count == 8,
              program.exactIdentity.textureSlots.count == 8,
              slots == slots.sorted(),
              Set(slots).count == slots.count,
              frontend.allSatisfy({
                  (0 ..< 8).contains($0.slot) && $0.name == "g_Texture\($0.slot)"
              }),
              program.semanticIdentity.shader.textureSlots == slots,
              program.textureSlots.enumerated().compactMap({
                  $0.element == nil ? nil : $0.offset
              }) == slots,
              program.semanticIdentity.textureSlots.enumerated().compactMap({
                  $0.element == nil ? nil : $0.offset
              }) == slots,
              program.exactIdentity.textureSlots.enumerated().compactMap({
                  $0.element == nil ? nil : $0.offset
              }) == slots else {
            return nil
        }

        var result: [Binding] = []
        for slotIndex in slots {
            guard let slot = program.textureSlots[slotIndex],
                  let exact = program.exactIdentity.textureSlots[slotIndex],
                  slot.index == slotIndex,
                  slot.resource.publication.isComplete,
                  slot.resource.publication.candidate.sampling
                      .isResolvedForMaterialProgram,
                  let binding = SceneTextureSlotBinding(
                      slotIndex: slotIndex,
                      candidate: slot.resource.publication.candidate
                  ),
                  binding.texture.device.registryID == device.registryID,
                  exact.deviceRegistryID == device.registryID,
                  exact.textureObjectIdentifier == ObjectIdentifier(binding.texture),
                  exact.pixelFormatRawValue == binding.texture.pixelFormat.rawValue,
                  exact.physicalExtent == [binding.texture.width, binding.texture.height],
                  exact.mipLevelCount == binding.texture.mipmapLevelCount,
                  exact.sampling == binding.sampling,
                  exact.samplingRawFlags == binding.sampling.rawFlags,
                  ObjectIdentifier(binding.texture) != ObjectIdentifier(target) else {
                return nil
            }
            result.append(.init(
                slot: slotIndex,
                texture: binding.texture,
                sampler: samplers.state(for: binding.sampling),
                sampling: binding.sampling
            ))
        }
        return result
    }

    private func valid(_ binding: Binding, target: MTLTexture) -> Bool {
        binding.texture.device.registryID == device.registryID
            && binding.texture.textureType == .type2D
            && binding.texture.width > 0
            && binding.texture.height > 0
            && binding.texture.sampleCount == 1
            && binding.texture.usage.contains(.shaderRead)
            && ObjectIdentifier(binding.texture) != ObjectIdentifier(target)
    }

    func pipeline(
        for key: SceneResolvedMaterialProgram.MetalCompileStateKey,
        frontend: SceneAuthoredShaderProgram,
        renderState: SceneMaterialRenderState,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int,
        writeMask: MTLColorWriteMask,
        origin: PipelineOrigin
    ) -> Result<
        (
            pipeline: MTLRenderPipelineState,
            generation: UInt64,
            origin: PipelineOrigin
        ),
        PreparationFailure
    > {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[key] {
            switch entry {
            case let .ready(pipeline, entryOrigin):
                return .success((pipeline, resetGeneration, entryOrigin))
            case let .failed(failure, entryOrigin):
                if entryOrigin == .launchWarmup,
                   consumedLaunchWarmupFailureKeys.insert(key).inserted {
                    launchWarmupFailureHits += 1
                    NSLog(
                        "MWX resolved material pipeline consumption phase=frame-preparation source=launch-warmup outcome=negative-cache reason=%@ attempts=%d hits=%d",
                        failure.code,
                        compilationAttempts,
                        launchWarmupFailureHits
                    )
                }
                return .failure(failure)
            }
        }
        compilationAttempts += 1
        switch compileUncachedPipeline(
            frontend: frontend,
            renderState: renderState,
            pixelFormat: pixelFormat,
            sampleCount: sampleCount,
            writeMask: writeMask
        ) {
        case let .success(pipeline):
            entries[key] = .ready(pipeline, origin: origin)
            return .success((pipeline, resetGeneration, origin))
        case let .failure(failure):
            return cacheFailure(failure, for: key, origin: origin)
        }
    }

    /// Creates one immutable pipeline without touching cache or generation
    /// state. Ordinary frame preparation calls this under `lock`; launch
    /// warmup may call it concurrently for already-deduplicated keys before
    /// the owning graph executor is published.
    func compileUncachedPipeline(
        frontend: SceneAuthoredShaderProgram,
        renderState: SceneMaterialRenderState,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int,
        writeMask: MTLColorWriteMask
    ) -> Result<MTLRenderPipelineState, PreparationFailure> {
        guard renderState.supportsResolvedMaterialFullscreenOverwrite else {
            return .failure(.renderStateRejected)
        }
        let library: MTLLibrary
        switch metalLibrary(for: frontend.metalSource) {
        case let .success(value): library = value
        case let .failure(failure): return .failure(failure)
        }
        guard let vertex = library.makeFunction(
            name: frontend.vertexFunctionName
        ) else {
            return .failure(.vertexFunctionRejected)
        }
        guard let fragment = library.makeFunction(
            name: frontend.fragmentFunctionName
        ) else {
            return .failure(.fragmentFunctionRejected)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Scene resolved material pass"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.rasterSampleCount = sampleCount
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = false
        descriptor.colorAttachments[0].writeMask = writeMask
        do {
            return .success(try device.makeRenderPipelineState(
                descriptor: descriptor
            ))
        } catch {
            let failure = PreparationFailure.pipelineCompilationRejected(
                diagnostic: String(describing: error)
            )
            NSLog("MWX resolved material Metal pipeline rejection: %@", String(describing: error))
            return .failure(failure)
        }
    }

    /// Different attachment/state variants can share the same authored MSL.
    /// Concurrent launch warmup callers rendezvous on one source compilation.
    private func metalLibrary(
        for metalSource: String
    ) -> Result<MTLLibrary, PreparationFailure> {
        libraryCondition.lock()
        while compilingMetalSources.contains(metalSource) {
            libraryCondition.wait()
        }
        if let cached = librariesByMetalSource[metalSource] {
            libraryCondition.unlock()
            switch cached {
            case let .ready(library): return .success(library)
            case let .failed(failure): return .failure(failure)
            }
        }
        compilingMetalSources.insert(metalSource)
        libraryCompilationAttempts += 1
        libraryCondition.unlock()

        let result: Result<MTLLibrary, PreparationFailure>
        do {
            result = .success(try device.makeLibrary(
                source: metalSource,
                options: nil
            ))
        } catch {
            let failure = PreparationFailure.libraryCompilationRejected(
                diagnostic: String(describing: error)
            )
            NSLog(
                "MWX resolved material Metal library rejection: %@",
                String(describing: error)
            )
            result = .failure(failure)
        }

        libraryCondition.lock()
        switch result {
        case let .success(library):
            librariesByMetalSource[metalSource] = .ready(library)
        case let .failure(failure):
            librariesByMetalSource[metalSource] = .failed(failure)
        }
        compilingMetalSources.remove(metalSource)
        libraryCondition.broadcast()
        libraryCondition.unlock()
        return result
    }

    func cacheFailure(
        _ failure: PreparationFailure,
        for key: SceneResolvedMaterialProgram.MetalCompileStateKey,
        origin: PipelineOrigin = .framePreparation
    ) -> Result<
        (
            pipeline: MTLRenderPipelineState,
            generation: UInt64,
            origin: PipelineOrigin
        ),
        PreparationFailure
    > {
        if entries[key] == nil {
            entries[key] = .failed(failure, origin: origin)
            failedPipelines += 1
        }
        return .failure(failure)
    }

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
