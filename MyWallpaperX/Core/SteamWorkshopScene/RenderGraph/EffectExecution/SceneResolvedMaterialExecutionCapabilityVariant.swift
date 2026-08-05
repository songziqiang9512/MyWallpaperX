import Foundation

/// Immutable shader/frontend/schema facts for one texture-readiness variant.
/// Concrete resources and uniform values are bound by each frame snapshot.
nonisolated struct SceneResolvedMaterialCompiledVariant {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    let readinessMask: UInt8
    let preparedShader: SceneShaderPreparedProgram
    let frontendProgram: SceneAuthoredShaderProgram
    let activeSamplers: [Int: Sampler]
    let activeUniforms: [String: Uniform]

    fileprivate init(
        readinessMask: UInt8,
        preparedShader: SceneShaderPreparedProgram,
        frontendProgram: SceneAuthoredShaderProgram,
        activeSamplers: [Int: Sampler],
        activeUniforms: [String: Uniform]
    ) {
        self.readinessMask = readinessMask
        self.preparedShader = preparedShader
        self.frontendProgram = frontendProgram
        self.activeSamplers = activeSamplers
        self.activeUniforms = activeUniforms
    }
}

/// Strictly bounded per-material cache. Failed variants consume a slot too, so
/// malformed authored data cannot turn every frame into another compiler run.
final class SceneResolvedMaterialVariantCache: @unchecked Sendable {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate
    typealias Variant = SceneResolvedMaterialCompiledVariant

    enum LaunchEnvelopeFailure: Error {
        enum Kind: String {
            case capacity
            case shaderPreparation = "shader-preparation"
            case frontend
            case samplerSchema = "sampler-schema"
            case uniformSchema = "uniform-schema"
            case texturePurpose = "texture-purpose"
            case textureBinding = "texture-binding"
            case colorContract = "color-contract"
            case invariant
        }

        case capacity
        case material(Failure)

        var kind: Kind {
            switch self {
            case .capacity: .capacity
            case let .material(failure): switch failure.code {
                case .shaderPreparationFailed: .shaderPreparation
                case .shaderFrontendFailed: .frontend
                case .activeSamplerSchemaInvalid: .samplerSchema
                case .uniformBindingInvalid: .uniformSchema
                case .texturePurposeUnproven: .texturePurpose
                case .textureBindingInvalid, .textureReferenceInvalid:
                    .textureBinding
                case .colorContractUnproven: .colorContract
                default: .invariant
                }
            }
        }
    }

    private enum Entry {
        case ready(Variant)
        case failed(Failure)
    }

    struct Counters: Equatable {
        let cachedVariantCount: Int
        let shaderPreparationCount: Int
        let frontendCompilationCount: Int
        let capacityRejectionCount: Int
    }

    private let template: Template
    private let seedSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    private let maximumVariantCount: Int
    private static let maximumReadinessPasses = 8
    private let lock = NSLock()
    private var entries: [UInt8: Entry] = [:]
    private var shaderPreparations = 0
    private var frontendCompilations = 0
    private var capacityRejections = 0

    init?(
        template: Template,
        maximumVariantCount: Int
    ) {
        guard (1 ... 256).contains(maximumVariantCount),
              let seed = try? SceneResolvedMaterialShaderSchema
                  .unconditionalSamplers(template) else {
            return nil
        }
        self.template = template
        seedSamplers = seed
        self.maximumVariantCount = maximumVariantCount
    }

    var counters: Counters {
        lock.lock()
        defer { lock.unlock() }
        return .init(
            cachedVariantCount: entries.count,
            shaderPreparationCount: shaderPreparations,
            frontendCompilationCount: frontendCompilations,
            capacityRejectionCount: capacityRejections
        )
    }

    /// Compiles the fixed point for every bounded absent/ready profile before
    /// a layer can own execution. The resulting entries are the same cache
    /// objects consumed by per-frame finalization.
    func precompileLaunchEnvelope(
        implicitFramebufferIdentity: Graph.TextureIdentity?
    ) -> Result<[UInt8], LaunchEnvelopeFailure> {
        lock.lock()
        defer { lock.unlock() }
        var reached = Set<UInt8>()
        for rawAvailability in UInt16(0) ... UInt16(UInt8.max) {
            let availability = UInt8(rawAvailability)
            var samplers = seedSamplers
            var seen = Set<UInt8>()
            var stable = false
            for _ in 0 ..< Self.maximumReadinessPasses {
                let projection: SceneResolvedMaterialTextureResolver
                    .LaunchReadinessProjection
                switch SceneResolvedMaterialTextureResolver
                    .launchReadinessProjection(
                        template: template,
                        samplers: samplers,
                        implicitFramebufferIdentity: implicitFramebufferIdentity
                    ) {
                case let .success(value): projection = value
                case let .failure(failure):
                    return .failure(.material(failure))
                }
                let mask = projection.mask(optionalAvailability: availability)
                guard seen.insert(mask).inserted else {
                    return .failure(.material(Self.failure(
                        .shaderPreparationFailed,
                        phase: .preparation,
                        details: ["texture-schema-cycle"]
                    )))
                }
                guard entries[mask] != nil
                        || entries.count < maximumVariantCount else {
                    capacityRejections += 1
                    return .failure(.capacity)
                }
                let variant: Variant
                do { variant = try entry(for: mask) }
                catch let failure as Failure {
                    return .failure(.material(failure))
                } catch {
                    return .failure(.material(Self.failure(
                        .identityInvariant, phase: .invariant
                    )))
                }
                reached.insert(mask)
                let nextProjection: SceneResolvedMaterialTextureResolver
                    .LaunchReadinessProjection
                switch SceneResolvedMaterialTextureResolver
                    .launchReadinessProjection(
                        template: template,
                        samplers: variant.activeSamplers,
                        implicitFramebufferIdentity: implicitFramebufferIdentity
                    ) {
                case let .success(value): nextProjection = value
                case let .failure(failure):
                    return .failure(.material(failure))
                }
                let next = nextProjection.mask(optionalAvailability: availability)
                if next == mask {
                    guard let invalid = variant.frontendProgram.textureBindings
                        .first(where: { mask & (1 << UInt8($0.slot)) == 0 }) else {
                        if variant.frontendProgram.colorTransfer == .unresolved {
                            return .failure(.material(Self.failure(
                                .colorContractUnproven, phase: .color)))
                        }
                        stable = true
                        break
                    }
                    return .failure(.material(Self.failure(
                        .textureBindingInvalid, slot: invalid.slot
                    )))
                }
                samplers = variant.activeSamplers
            }
            guard stable else {
                return .failure(.material(Self.failure(
                    .shaderPreparationFailed,
                    phase: .preparation,
                    details: ["texture-schema-budget"]
                )))
            }
        }
        return .success(reached.sorted())
    }

    func resolve(
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<Variant, Failure> {
        lock.lock()
        defer { lock.unlock() }
        do {
            guard input.template.diagnosticProvenance.contractCanonicalSHA256
                    == template.diagnosticProvenance.contractCanonicalSHA256,
                  input.template.diagnosticProvenance.nodeIndex
                    == template.diagnosticProvenance.nodeIndex else {
                throw Self.failure(.identityInvariant, phase: .invariant)
            }
            var samplers = seedSamplers
            var seen: Set<UInt8> = []
            for _ in 0 ..< Self.maximumReadinessPasses {
                let mask = try SceneResolvedMaterialTextureResolver.readinessMask(
                    input,
                    samplers: samplers
                )
                guard seen.insert(mask).inserted else {
                    throw Self.failure(
                        .shaderPreparationFailed,
                        phase: .preparation,
                        details: ["texture-schema-cycle"]
                    )
                }
                let variant = try entry(for: mask)
                let next = try SceneResolvedMaterialTextureResolver.readinessMask(
                    input,
                    samplers: variant.activeSamplers
                )
                if next == mask { return .success(variant) }
                samplers = variant.activeSamplers
            }
            throw Self.failure(
                .shaderPreparationFailed,
                phase: .preparation,
                details: ["texture-schema-budget"]
            )
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Self.failure(.identityInvariant, phase: .invariant))
        }
    }

    private func entry(
        for mask: UInt8
    ) throws -> Variant {
        if let entry = entries[mask] {
            switch entry {
            case let .ready(variant): return variant
            case let .failed(failure): throw failure
            }
        }
        guard entries.count < maximumVariantCount else {
            capacityRejections += 1
            throw Self.failure(
                .shaderPreparationFailed,
                phase: .preparation,
                details: ["variant-cache-capacity"]
            )
        }
        shaderPreparations += 1
        do {
            let variant = try Self.compile(
                template: template,
                readinessMask: mask,
                onFrontendCompilation: { frontendCompilations += 1 }
            )
            entries[mask] = .ready(variant)
            return variant
        } catch let failure as Failure {
            entries[mask] = .failed(failure)
            throw failure
        }
    }

    private static func compile(
        template: Template,
        readinessMask: UInt8,
        onFrontendCompilation: () -> Void
    ) throws -> Variant {
        let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, readinessMask & (1 << UInt8($0)) != 0)
        })
        let prepared: SceneShaderPreparedProgram
        switch SceneAuthoredShaderExecutionPlanner.prepareShaderStages(
            contract: template.shaderContract,
            combos: template.comboValues,
            textureReadiness: readiness
        ) {
        case let .accepted(value): prepared = value
        case let .rejected(rejection):
            throw failure(
                .shaderPreparationFailed,
                phase: .preparation,
                details: [rejection.phase.rawValue, rejection.code.rawValue]
                    + rejection.details
            )
        case .notApplicable:
            throw failure(.identityInvariant, phase: .invariant)
        }
        onFrontendCompilation()
        let frontendOutput = SceneAuthoredShaderFrontend.compile(
            vertexSource: prepared.vertex.source,
            fragmentSource: prepared.fragment.source
        )
        guard frontendOutput.diagnostics.isEmpty,
              let frontend = frontendOutput.program,
              SceneResolvedMaterialProgramDerivation.validPreparedStages(prepared),
              SceneResolvedMaterialProgramDerivation.uniqueAndValid(
                  frontend.uniformLayout
              ) else {
            throw failure(
                .shaderFrontendFailed,
                phase: .frontend,
                details: frontendOutput.diagnostics.map { $0.code.rawValue }
            )
        }
        let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        do {
            samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
        } catch {
            throw failure(.activeSamplerSchemaInvalid)
        }
        let bindings = frontend.textureBindings
        guard !hasInternalDefault(samplers),
              bindings.map(\.slot) == bindings.map(\.slot).sorted(),
              Set(bindings.map(\.slot)).count == bindings.count,
              bindings.allSatisfy({ binding in
                  (0 ..< 8).contains(binding.slot)
                      && samplers[binding.slot]?.name == binding.name
              }), !declaresActivePass(prepared) else {
            throw failure(.activeSamplerSchemaInvalid)
        }
        let activeSlots = Set(bindings.map(\.slot))
        let nonHost = frontend.uniformLayout.fields.filter {
            SceneResolvedMaterialUniformEncoder.hostUniform(
                $0,
                activeTextureSlots: activeSlots
            ) == nil
        }
        let uniforms: [String: SceneResolvedMaterialShaderSchema.Uniform]
        do {
            uniforms = try SceneResolvedMaterialShaderSchema.activeUniforms(
                nonHost,
                prepared: prepared
            )
        } catch {
            throw failure(
                .uniformBindingInvalid,
                phase: .uniform
            )
        }
        return .init(
            readinessMask: readinessMask,
            preparedShader: prepared,
            frontendProgram: frontend,
            activeSamplers: samplers,
            activeUniforms: uniforms
        )
    }
    private static func hasInternalDefault(
        _ samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> Bool {
        samplers.values.contains {
            if case .internalTarget? = $0.defaultTexture { return true }
            return false
        }
    }

    private static func declaresActivePass(
        _ prepared: SceneShaderPreparedProgram
    ) -> Bool {
        prepared.all.contains { source in
            source.activeAnnotations.contains { annotation in
                annotation.annotation.marker?.caseInsensitiveCompare("[PASS]")
                    == .orderedSame
            }
        }
    }

    private static func failure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, slot: slot, details: details)
    }
}
