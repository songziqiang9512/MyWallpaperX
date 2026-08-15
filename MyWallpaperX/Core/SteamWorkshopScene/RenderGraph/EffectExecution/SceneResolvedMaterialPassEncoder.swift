import Foundation
import Metal

/// Prepares one already-finalized material Program before any commands are
/// encoded. A graph executor can therefore prepare every pass first and only
/// start its command buffer after the complete transaction is admissible.
final class SceneResolvedMaterialPassEncoder {
    struct PreparedPass {
        let fragmentOutput: SceneShaderColorRepresentation
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

    let device: MTLDevice
    private let samplers: SceneTextureSamplerStateSet
    private let ownerToken = UUID()
    let lock = NSLock()
    var entries: [SceneResolvedMaterialProgram.MetalCompileStateKey: PipelineEntry] = [:]
    var resetGeneration: UInt64 = 0
    var compilationAttempts = 0
    var failedPipelines = 0
    var launchWarmupHits = 0
    var launchWarmupFailureHits = 0
    var consumedLaunchWarmupKeys = Set<SceneResolvedMaterialProgram.MetalCompileStateKey>()
    var consumedLaunchWarmupFailureKeys = Set<SceneResolvedMaterialProgram.MetalCompileStateKey>()

    var cachedPipelineCount: Int { withLock { entries.count } }
    var pipelineCompilationAttemptCount: Int { withLock { compilationAttempts } }
    var failedPipelineCount: Int { withLock { failedPipelines } }
    var launchWarmupHitCount: Int { withLock { launchWarmupHits } }
    var launchWarmupFailureHitCount: Int { withLock { launchWarmupFailureHits } }

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
        guard let fragmentOutput = SceneResolvedMaterialAttachmentStorage
            .acceptedColorOutput(program.colorContract.fragmentOutput)
        else { return .failure(.fragmentOutputRejected) }
        let storedContent = attachmentStorage.storedContent(
            fragmentOutput: fragmentOutput
        )
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
            fragmentOutput: fragmentOutput,
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
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return false
        }
        encoder.label = "Scene resolved material pass"
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
        encoder.endEncoding()
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true)
        resetGeneration &+= 1
        compilationAttempts = 0
        failedPipelines = 0
        launchWarmupHits = 0
        launchWarmupFailureHits = 0
        consumedLaunchWarmupKeys.removeAll(keepingCapacity: true)
        consumedLaunchWarmupFailureKeys.removeAll(keepingCapacity: true)
    }

    private func validUniforms(_ program: SceneResolvedMaterialProgram) -> Bool {
        let layout = program.frontendProgram.uniformLayout
        guard layout.byteSize == program.uniformBytes.count,
              (0 ..< 31).contains(program.frontendProgram.uniformBufferIndex),
              layout.byteSize >= 0,
              layout.byteSize <= 4_096,
              layout.byteSize.isMultiple(of: 16),
              program.exactIdentity.uniformBytes == program.uniformBytes,
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
        var occupied = Set<Int>()
        for (field, resolved) in zip(layout.fields, program.resolvedUniforms) {
            let end = field.offset + field.storageByteSize
            guard resolved.field == field,
                  field.offset >= 0,
                  field.offset.isMultiple(of: field.type.alignment),
                  end <= layout.byteSize,
                  resolved.encodedValue.count == field.storageByteSize,
                  Data(program.uniformBytes[field.offset ..< end]) == resolved.encodedValue,
                  (field.offset ..< end).allSatisfy({ !occupied.contains($0) }) else {
                return false
            }
            occupied.formUnion(field.offset ..< end)
        }
        return program.uniformBytes.indices
            .filter { !occupied.contains($0) }
            .allSatisfy { program.uniformBytes[$0] == 0 }
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
        guard renderState.matchesFullscreenOverwrite(
            alphaWriting: .unspecified
        ) else { return cacheFailure(.renderStateRejected, for: key, origin: origin) }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(
                source: frontend.metalSource,
                options: nil
            )
        } catch {
            let failure = PreparationFailure.libraryCompilationRejected(
                diagnostic: String(describing: error)
            )
            NSLog("MWX resolved material Metal library rejection: %@", String(describing: error))
            return cacheFailure(failure, for: key, origin: origin)
        }
        guard let vertex = library.makeFunction(
            name: frontend.vertexFunctionName
        ) else {
            return cacheFailure(.vertexFunctionRejected, for: key, origin: origin)
        }
        guard let fragment = library.makeFunction(
            name: frontend.fragmentFunctionName
        ) else {
            return cacheFailure(.fragmentFunctionRejected, for: key, origin: origin)
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
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            entries[key] = .ready(pipeline, origin: origin)
            return .success((pipeline, resetGeneration, origin))
        } catch {
            let failure = PreparationFailure.pipelineCompilationRejected(
                diagnostic: String(describing: error)
            )
            NSLog("MWX resolved material Metal pipeline rejection: %@", String(describing: error))
            return cacheFailure(failure, for: key, origin: origin)
        }
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
