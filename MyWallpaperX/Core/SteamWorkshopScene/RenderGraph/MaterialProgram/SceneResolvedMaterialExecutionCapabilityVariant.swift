import Foundation

/// Strictly bounded per-material cache. Failed variants consume a slot too, so
/// malformed authored data cannot turn every frame into another compiler run.
nonisolated final class SceneResolvedMaterialVariantCache: @unchecked Sendable {
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

    private let template: Template
    private let seedSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    private let textureFormatSlots: Set<Int>
    private let assetFormatFacts: [String: Int]
    private let maximumVariantCount: Int
    private static let maximumReadinessPasses = 8
    private let lock = NSLock()
    private var entries: [SceneResolvedMaterialVariantKey: Entry] = [:]
    private var shaderPreparations = 0
    private var frontendCompilations = 0
    private var capacityRejections = 0
    private var cachedReachableSamplers: [
        Int: Set<SceneResolvedMaterialShaderSchema.Sampler>
    ]?
    private var cachedReachabilityIdentity: Graph.TextureIdentity?
    private var hasCachedReachability = false

    init?(
        template: Template,
        maximumVariantCount: Int,
        assetFormatFacts: [String: Int] = [:]
    ) {
        guard (1 ... 256).contains(maximumVariantCount),
              let seed = try? SceneResolvedMaterialShaderSchema
                  .unconditionalSamplers(template),
              let formatSlots = try? SceneResolvedMaterialTextureResolver
                  .launchTextureFormatSlots(template: template) else {
            return nil
        }
        self.template = template
        seedSamplers = seed
        textureFormatSlots = formatSlots
        self.assetFormatFacts = assetFormatFacts
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

    func compiledChannelUses(for slot: Int) -> [ChannelUse]? {
        guard (0 ..< 8).contains(slot) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return entries.values.compactMap {
            guard case let .ready(variant) = $0 else { return nil }
            return variant.frontendProgram.textureBindings.first(where: { $0.slot == slot })?.channelUse
        }
    }

    func launchEnvelopeCapabilitySnapshot() -> LaunchEnvelopeCapabilitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        let variants = entries.values.compactMap { entry -> Variant? in
            guard case let .ready(variant) = entry else { return nil }
            return variant
        }
        return .init(
            template: template,
            variants: variants,
            allEntriesReady: variants.count == entries.count,
            reachableSamplers: cachedReachableSamplers,
            inputIdentity: cachedReachabilityIdentity,
            hasCachedReachability: hasCachedReachability
        )
    }

    /// Exact sampler slots consumed by at least one successfully precompiled
    /// launch variant. Resource-demand diagnostics for declarations outside
    /// this set cannot affect product execution and must not revoke the whole
    /// material owner.
    var launchEnvelopeActiveTextureSlots: Set<Int>? {
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else {
            return nil
        }
        return Set(snapshot.variants.flatMap {
            $0.frontendProgram.textureBindings.map(\.slot)
        })
    }

    /// A source-less object route is executable only when the authored
    /// variant explicitly selects DIRECTDRAW and the complete launch envelope
    /// proves that no active sampler can consume the graph input.
    var supportsTransparentDirectDraw: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard template.comboValues["DIRECTDRAW"] == 1,
              template.graphRole.bindings.isEmpty,
              hasCachedReachability,
              let reachable = cachedReachableSamplers,
              reachable[0] == nil else {
            return false
        }
        for (slot, samplers) in reachable {
            guard (0 ..< template.textureSlots.count).contains(slot) else {
                return false
            }
            if samplers.contains(where: \.usesGraphInputMaterialAlias) {
                return false
            }
            if template.textureSlots[slot]?.candidates.contains(where: {
                if case .graph = $0.reference { return true }
                return false
            }) == true {
                return false
            }
        }
        return true
    }

    func precompileLaunchEnvelope(
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:]
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
                let projection: SceneResolvedMaterialTextureResolver.LaunchReadinessProjection
                switch SceneResolvedMaterialTextureResolver.launchReadinessProjection(
                    template: template, samplers: samplers,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    assetStates: assetStates
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
                let profiles: [[SceneShaderTextureFormat?]]
                switch SceneResolvedMaterialTextureResolver
                    .launchTextureFormatProfiles(
                        template: template,
                        samplers: samplers,
                        readinessMask: mask,
                        formatSlots: textureFormatSlots,
                        assetFormatFacts: assetFormatFacts,
                        assetStates: assetStates
                    ) {
                case let .success(value): profiles = value
                case let .failure(failure):
                    return .failure(.material(failure))
                }
                var variants: [Variant] = []
                do {
                    for profile in profiles {
                        guard let key = SceneResolvedMaterialVariantKey(
                            readinessMask: mask,
                            textureFormats: profile
                        ) else {
                            throw Self.failure(
                                .identityInvariant,
                                phase: .invariant
                            )
                        }
                        guard entries[key] != nil
                                || entries.count < maximumVariantCount else {
                            capacityRejections += 1
                            return .failure(.capacity)
                        }
                        variants.append(try entry(for: key))
                    }
                } catch let failure as Failure {
                    return .failure(.material(failure))
                } catch {
                    return .failure(.material(Self.failure(
                        .identityInvariant, phase: .invariant
                    )))
                }
                guard let variant = variants.first,
                      variants.dropFirst().allSatisfy({
                          $0.activeSamplers == variant.activeSamplers
                              && $0.frontendProgram.textureBindings
                                  == variant.frontendProgram.textureBindings
                      }) else {
                    return .failure(.material(Self.failure(
                        .activeSamplerSchemaInvalid,
                        phase: .preparation,
                        details: ["texture-format-schema-divergence"]
                    )))
                }
                reached.insert(mask)
                for compiled in variants {
                    for (slot, sampler) in compiled.activeSamplers {
                        reachableSamplers[slot, default: []].insert(sampler)
                    }
                }
                let nextProjection: SceneResolvedMaterialTextureResolver.LaunchReadinessProjection
                switch SceneResolvedMaterialTextureResolver.launchReadinessProjection(
                    template: template, samplers: variant.activeSamplers,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    assetStates: assetStates
                ) {
                case let .success(value): nextProjection = value
                case let .failure(failure):
                    return .failure(.material(failure))
                }
                let next = nextProjection.mask(optionalAvailability: availability)
                if next == mask {
                    if let failure = SceneResolvedMaterialTextureResolver
                        .launchProgramFailure(
                            template: template,
                            variants: variants,
                            readinessMask: mask,
                            formatSlots: textureFormatSlots,
                            implicitFramebufferIdentity: implicitFramebufferIdentity,
                            assetStates: assetStates
                        ) {
                        return .failure(.material(failure))
                    }
                    stable = true
                    break
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
        cachedReachableSamplers = reachableSamplers
        cachedReachabilityIdentity = implicitFramebufferIdentity
        hasCachedReachability = true
        return .success(reached.sorted())
    }

    func resolveSelection(
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<Selection, Failure> {
        lock.lock()
        defer { lock.unlock() }
        do {
            guard input.template.diagnosticProvenance.contractCanonicalSHA256
                    == template.diagnosticProvenance.contractCanonicalSHA256,
                  input.template.diagnosticProvenance.nodeIndex == template.diagnosticProvenance.nodeIndex,
                  input.template.uniformDeclarations == template.uniformDeclarations else {
                throw Self.failure(.identityInvariant, phase: .invariant)
            }
            let reachableSamplers = try reachableSamplersLocked(
                implicitFramebufferIdentity: input.implicitFramebufferIdentity
            )
            if hasCachedReachability,
               cachedReachabilityIdentity == input.implicitFramebufferIdentity {
                let matches = entries.compactMap { key, entry -> Variant? in
                    guard case let .ready(variant) = entry else { return nil }
                    do {
                        let resolvedKey = try SceneResolvedMaterialTextureResolver
                            .variantKey(
                                input,
                                samplers: variant.activeSamplers,
                                reachableSamplers: reachableSamplers,
                                formatSlots: textureFormatSlots,
                                channelUses: Dictionary(uniqueKeysWithValues:
                                    variant.frontendProgram.textureBindings.map {
                                        ($0.slot, $0.channelUse)
                                    }
                                ),
                                allowPresenceIndependentDefaults: true,
                                restrictToSamplerSlots: true
                            )
                        return resolvedKey == key ? variant : nil
                    } catch {
                        return nil
                    }
                }
                if matches.count == 1, let variant = matches.first {
                    return .success(.init(
                        variant: variant,
                        reachableSamplers: reachableSamplers
                    ))
                }
                guard matches.isEmpty else {
                    throw Self.failure(.identityInvariant, phase: .invariant)
                }
            }
            var activeSamplers = seedSamplers
            var seen: Set<UInt8> = []
            var hasPreparedActiveSamplers = false
            for _ in 0 ..< Self.maximumReadinessPasses {
                let key = try SceneResolvedMaterialTextureResolver.variantKey(
                    input,
                    samplers: activeSamplers,
                    reachableSamplers: reachableSamplers,
                    formatSlots: textureFormatSlots,
                    allowPresenceIndependentDefaults: hasPreparedActiveSamplers
                )
                let mask = key.readinessMask
                guard seen.insert(mask).inserted else {
                    throw Self.failure(
                        .shaderPreparationFailed,
                        phase: .preparation,
                        details: ["texture-schema-cycle"]
                    )
                }
                let variant = try entry(for: key)
                let next = try SceneResolvedMaterialTextureResolver.variantKey(
                    input,
                    samplers: variant.activeSamplers,
                    reachableSamplers: reachableSamplers,
                    formatSlots: textureFormatSlots,
                    channelUses: Dictionary(uniqueKeysWithValues:
                        variant.frontendProgram.textureBindings.map {
                            ($0.slot, $0.channelUse)
                        }
                    ),
                    allowPresenceIndependentDefaults: true
                )
                if next == key {
                    return .success(.init(
                        variant: variant,
                        reachableSamplers: reachableSamplers
                    ))
                }
                activeSamplers = variant.activeSamplers
                hasPreparedActiveSamplers = true
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

    private func entry(
        for key: SceneResolvedMaterialVariantKey
    ) throws -> Variant {
        if let entry = entries[key] {
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
                variantKey: key,
                onFrontendCompilation: { frontendCompilations += 1 }
            )
            entries[key] = .ready(variant)
            return variant
        } catch let failure as Failure {
            entries[key] = .failed(failure)
            throw failure
        }
    }
}
