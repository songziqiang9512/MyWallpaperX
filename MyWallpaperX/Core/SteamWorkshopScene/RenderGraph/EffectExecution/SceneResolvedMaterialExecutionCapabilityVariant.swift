import Foundation

/// Strictly bounded per-material cache. Failed variants consume a slot too, so
/// malformed authored data cannot turn every frame into another compiler run.
final class SceneResolvedMaterialVariantCache: @unchecked Sendable {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate
    typealias Variant = SceneResolvedMaterialCompiledVariant

    struct Selection {
        let variant: Variant
        let reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
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
    private var cachedBootstrapSamplers: [
        Int: SceneResolvedMaterialShaderSchema.Sampler
    ]?
    private var cachedReachableSamplers: [
        Int: Set<SceneResolvedMaterialShaderSchema.Sampler>
    ]?
    private var cachedReachabilityIdentity: Graph.TextureIdentity?
    private var hasCachedReachability = false

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
        var reachableSamplers: [
            Int: Set<SceneResolvedMaterialShaderSchema.Sampler>
        ] = [:]
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
                for (slot, sampler) in variant.activeSamplers {
                    reachableSamplers[slot, default: []].insert(sampler)
                }
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
        do { _ = try bootstrapSamplersLocked() }
        catch let failure as Failure { return .failure(.material(failure)) }
        catch {
            return .failure(.material(Self.failure(
                .identityInvariant, phase: .invariant
            )))
        }
        cachedReachableSamplers = reachableSamplers
        cachedReachabilityIdentity = implicitFramebufferIdentity
        hasCachedReachability = true
        return .success(reached.sorted())
    }

    func resolve(
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<Variant, Failure> {
        resolveSelection(input).map(\.variant)
    }

    func resolveSelection(
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<Selection, Failure> {
        lock.lock()
        defer { lock.unlock() }
        do {
            guard input.template.diagnosticProvenance.contractCanonicalSHA256
                    == template.diagnosticProvenance.contractCanonicalSHA256,
                  input.template.diagnosticProvenance.nodeIndex
                    == template.diagnosticProvenance.nodeIndex else {
                throw Self.failure(.identityInvariant, phase: .invariant)
            }
            let reachableSamplers = try reachableSamplersLocked(
                implicitFramebufferIdentity: input.implicitFramebufferIdentity
            )
            var activeSamplers = try bootstrapSamplersLocked()
            var seen: Set<UInt8> = []
            for _ in 0 ..< Self.maximumReadinessPasses {
                let mask = try SceneResolvedMaterialTextureResolver.readinessMask(
                    input,
                    samplers: activeSamplers,
                    reachableSamplers: reachableSamplers
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
                    samplers: variant.activeSamplers,
                    reachableSamplers: reachableSamplers
                )
                if next == mask {
                    return .success(.init(
                        variant: variant,
                        reachableSamplers: reachableSamplers
                    ))
                }
                activeSamplers = variant.activeSamplers
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

    private func reachableSamplersLocked(
        implicitFramebufferIdentity: Graph.TextureIdentity?
    ) throws -> [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>] {
        if hasCachedReachability {
            guard cachedReachabilityIdentity == implicitFramebufferIdentity,
                  let cachedReachableSamplers else {
                throw Self.failure(.identityInvariant, phase: .invariant)
            }
            return cachedReachableSamplers
        }
        do {
            let samplers = try SceneResolvedMaterialShaderSchema.reachableSamplers(
                template,
                implicitFramebufferIdentity: implicitFramebufferIdentity
            )
            cachedReachableSamplers = samplers
            cachedReachabilityIdentity = implicitFramebufferIdentity
            hasCachedReachability = true
            return samplers
        } catch {
            throw Self.failure(
                .activeSamplerSchemaInvalid,
                phase: .preparation,
                details: ["reachable-sampler-schema"]
            )
        }
    }

    private func bootstrapSamplersLocked() throws -> [
        Int: SceneResolvedMaterialShaderSchema.Sampler
    ] {
        if let cachedBootstrapSamplers { return cachedBootstrapSamplers }
        do {
            let value = try SceneResolvedMaterialShaderSchema.bootstrapSamplers(template)
            cachedBootstrapSamplers = value
            return value
        } catch {
            throw Self.failure(
                .activeSamplerSchemaInvalid,
                phase: .preparation,
                details: ["bootstrap-variant"]
            )
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

    static func failure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, slot: slot, details: details)
    }
}
