import Foundation
import Metal

/// Prepares one already-finalized material Program before any commands are
/// encoded. A chain executor can therefore prepare every pass first and only
/// start its command buffer after the complete transaction is admissible.
final class SceneResolvedMaterialPassEncoder {
    struct PreparedPass {
        let fragmentOutput: SceneShaderColorRepresentation
        let bindingSlots: [Int]
        let bindingSamplings: [SceneTextureSampling]
        let uniformByteCount: Int

        fileprivate let ownerToken: UUID
        fileprivate let resetGeneration: UInt64
        fileprivate let pipeline: MTLRenderPipelineState
        fileprivate let target: MTLTexture
        fileprivate let bindings: [Binding]
        fileprivate let uniformBytes: Data
    }

    fileprivate struct Binding {
        let slot: Int
        let texture: MTLTexture
        let sampler: MTLSamplerState
        let sampling: SceneTextureSampling
    }

    private enum PipelineEntry {
        case ready(MTLRenderPipelineState)
        case failed
    }

    private let device: MTLDevice
    private let samplers: SceneTextureSamplerStateSet
    private let ownerToken = UUID()
    private let lock = NSLock()
    private var entries: [SceneResolvedMaterialProgram.MetalCompileStateKey: PipelineEntry] = [:]
    private var resetGeneration: UInt64 = 0
    private var compilationAttempts = 0
    private var failedPipelines = 0

    var cachedPipelineCount: Int { withLock { entries.count } }
    var pipelineCompilationAttemptCount: Int { withLock { compilationAttempts } }
    var failedPipelineCount: Int { withLock { failedPipelines } }

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
        guard let fragmentOutput = acceptedOutput(program.colorContract.fragmentOutput),
              validTarget(target),
              validUniforms(program),
              let bindings = validatedBindings(program, target: target),
              let key = program.metalCompileStateKey(
                  attachmentPixelFormat: target.pixelFormat,
                  sampleCount: target.sampleCount,
                  device: device
              ),
              let cached = pipeline(for: key, program: program, target: target) else {
            return nil
        }
        return PreparedPass(
            fragmentOutput: fragmentOutput,
            bindingSlots: bindings.map(\.slot),
            bindingSamplings: bindings.map(\.sampling),
            uniformByteCount: program.uniformBytes.count,
            ownerToken: ownerToken,
            resetGeneration: cached.generation,
            pipeline: cached.pipeline,
            target: target,
            bindings: bindings,
            uniformBytes: program.uniformBytes
        )
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
              validTarget(pass.target),
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
                encoder.setVertexBytes(baseAddress, length: bytes.count, index: 0)
                encoder.setFragmentBytes(baseAddress, length: bytes.count, index: 0)
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
    }

    private func acceptedOutput(
        _ resolution: SceneShaderColorRepresentationResolution
    ) -> SceneShaderColorRepresentation? {
        switch resolution {
        case .resolved(.opaque): return .opaque
        case .resolved(.premultipliedAlpha): return .premultipliedAlpha
        case .resolved(.straightAlpha), .unresolved: return nil
        }
    }

    private func validTarget(_ target: MTLTexture) -> Bool {
        let supportedFormats: Set<MTLPixelFormat> = [.bgra8Unorm, .rgba8Unorm]
        return target.device.registryID == device.registryID
            && target.textureType == .type2D
            && supportedFormats.contains(target.pixelFormat)
            && target.width > 0
            && target.height > 0
            && target.mipmapLevelCount == 1
            && target.sampleCount == 1
            && target.usage.contains(.renderTarget)
            && target.usage.contains(.shaderRead)
    }

    private func validUniforms(_ program: SceneResolvedMaterialProgram) -> Bool {
        let layout = program.frontendProgram.uniformLayout
        guard layout.byteSize == program.uniformBytes.count,
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

    private func pipeline(
        for key: SceneResolvedMaterialProgram.MetalCompileStateKey,
        program: SceneResolvedMaterialProgram,
        target: MTLTexture
    ) -> (pipeline: MTLRenderPipelineState, generation: UInt64)? {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[key] {
            guard case let .ready(pipeline) = entry else { return nil }
            return (pipeline, resetGeneration)
        }
        compilationAttempts += 1
        guard program.renderState.matchesFullscreenOverwrite(
                  alphaWriting: .unspecified
              ),
              let library = try? device.makeLibrary(
                  source: program.frontendProgram.metalSource,
                  options: nil
              ),
              let vertex = library.makeFunction(
                  name: program.frontendProgram.vertexFunctionName
              ),
              let fragment = library.makeFunction(
                  name: program.frontendProgram.fragmentFunctionName
              ) else {
            entries[key] = .failed
            failedPipelines += 1
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Scene resolved material pass"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = target.pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = false
        descriptor.colorAttachments[0].writeMask = .all
        guard let pipeline = try? device.makeRenderPipelineState(
                  descriptor: descriptor
              ) else {
            entries[key] = .failed
            failedPipelines += 1
            return nil
        }
        entries[key] = .ready(pipeline)
        return (pipeline, resetGeneration)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
