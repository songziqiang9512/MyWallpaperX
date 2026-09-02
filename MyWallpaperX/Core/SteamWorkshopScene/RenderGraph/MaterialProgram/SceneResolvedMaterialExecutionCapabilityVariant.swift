import Foundation

/// Strictly bounded per-material cache. Failed variants consume a slot too, so
/// malformed authored data cannot turn every frame into another compiler run.
nonisolated final class SceneResolvedMaterialVariantCache: @unchecked Sendable {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate
    typealias Variant = SceneResolvedMaterialCompiledVariant
    typealias OutputStorage = SceneResolvedMaterialProgram.OutputStorage

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
    private var cachedLaunchEnvelopeKeys = Set<SceneResolvedMaterialVariantKey>()
    private var cachedReachableSamplers: [
        Int: Set<SceneResolvedMaterialShaderSchema.Sampler>
    ]?
    private var cachedReachabilityIdentity: Graph.TextureIdentity?
    private var hasCachedReachability = false
    private var cachedOutputStorage: SceneResolvedMaterialProgram.OutputStorage?
    private var cachedOutputIsRGBA8Unorm: Bool?
    private var cachedGraphTextureFormatFacts: [
        Graph.TextureIdentity: SceneShaderTextureFormat
    ]?
    private var cachedGraphTextureContentFacts: [
        Graph.TextureIdentity: SceneTextureContent
    ]?

    private init(
        template: Template,
        maximumVariantCount: Int,
        assetFormatFacts: [String: Int],
        seedSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        textureFormatSlots: Set<Int>
    ) {
        self.template = template
        self.seedSamplers = seedSamplers
        self.textureFormatSlots = textureFormatSlots
        self.assetFormatFacts = assetFormatFacts
        self.maximumVariantCount = maximumVariantCount
    }

    static func launchValidated(
        template: Template,
        maximumVariantCount: Int,
        assetFormatFacts: [String: Int] = [:]
    ) -> Result<SceneResolvedMaterialVariantCache, Failure> {
        guard (1 ... 256).contains(maximumVariantCount) else {
            return .failure(Self.failure(.identityInvariant, phase: .invariant))
        }
        let seed: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        do {
            seed = try SceneResolvedMaterialShaderSchema.unconditionalSamplers(template)
        } catch {
            return .failure(Self.failure(
                .authoredSamplerSchemaInvalid,
                details: ["unconditional-sampler-schema"]
            ))
        }
        let formatSlots: Set<Int>
        do {
            formatSlots = try SceneResolvedMaterialTextureResolver
                .launchTextureFormatSlots(template: template)
        } catch {
            return .failure(Self.failure(
                .authoredSamplerSchemaInvalid,
                details: ["texture-format-schema"]
            ))
        }
        return .success(.init(
            template: template,
            maximumVariantCount: maximumVariantCount,
            assetFormatFacts: assetFormatFacts,
            seedSamplers: seed,
            textureFormatSlots: formatSlots
        ))
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
        return cachedLaunchEnvelopeKeys.compactMap { key in
            guard case let .ready(variant)? = entries[key] else { return nil }
            return variant.frontendProgram.textureBindings.first(where: { $0.slot == slot })?.channelUse
        }
    }

    func launchEnvelopeCapabilitySnapshot() -> LaunchEnvelopeCapabilitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        let variants = cachedLaunchEnvelopeKeys.compactMap { key -> Variant? in
            guard case let .ready(variant)? = entries[key] else { return nil }
            return variant
        }
        return .init(
            template: template,
            variants: variants,
            allEntriesReady: variants.count == cachedLaunchEnvelopeKeys.count,
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

    /// Publishes only the one launch-time graph content fact that can be
    /// derived without a frame resource: every admitted variant writes opaque
    /// color. Graph author order remains owned by capability compilation, and
    /// frame finalization still validates the actual publication.
    var launchEnvelopeProvesOpaqueColorOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard cachedOutputStorage == .color,
              !cachedLaunchEnvelopeKeys.isEmpty else { return false }
        return cachedLaunchEnvelopeKeys.allSatisfy { key in
            guard case let .ready(variant)? = entries[key] else { return false }
            return variant.frontendProgram.colorTransfer == .opaque
        }
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
              reachable[0] == nil,
              cachedLaunchEnvelopeKeys.allSatisfy({ key in
                  guard case let .ready(variant)? = entries[key] else {
                      return false
                  }
                  return variant.graphInputSourceSlotFacts.isEmpty
              }) else {
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
        outputStorage: SceneResolvedMaterialProgram.OutputStorage = .color,
        outputIsRGBA8Unorm: Bool = false,
        graphTextureFormatFacts: [Graph.TextureIdentity: SceneShaderTextureFormat] = [:],
        graphTextureContentFacts: [Graph.TextureIdentity: SceneTextureContent] = [:],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:]
    ) -> Result<[UInt8], LaunchEnvelopeFailure> {
        lock.lock()
        defer { lock.unlock() }
        if let cachedOutputStorage, cachedOutputStorage != outputStorage {
            return .failure(.material(Self.failure(
                .identityInvariant,
                phase: .invariant,
                details: ["launch-output-storage-changed"]
            )))
        }
        if let cachedGraphTextureFormatFacts,
           cachedGraphTextureFormatFacts != graphTextureFormatFacts {
            return .failure(.material(Self.failure(
                .identityInvariant,
                phase: .invariant,
                details: ["launch-graph-texture-formats-changed"]
            )))
        }
        if let cachedGraphTextureContentFacts,
           cachedGraphTextureContentFacts != graphTextureContentFacts {
            return .failure(.material(Self.failure(
                .identityInvariant,
                phase: .invariant,
                details: ["launch-graph-texture-content-changed"]
            )))
        }
        if let cachedOutputIsRGBA8Unorm,
           cachedOutputIsRGBA8Unorm != outputIsRGBA8Unorm {
            return .failure(.material(Self.failure(
                .identityInvariant,
                phase: .invariant,
                details: ["launch-output-rgba8-unorm-changed"]
            )))
        }
        cachedOutputStorage = outputStorage
        cachedOutputIsRGBA8Unorm = outputIsRGBA8Unorm
        cachedGraphTextureFormatFacts = graphTextureFormatFacts
        cachedGraphTextureContentFacts = graphTextureContentFacts
        var reached = Set<UInt8>()
        var admittedKeys = Set<SceneResolvedMaterialVariantKey>()
        var reachableSamplers: [
            Int: Set<SceneResolvedMaterialShaderSchema.Sampler>
        ] = [:]
        var dormantLaunchFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ]?
        for rawAvailability in UInt16(0) ... UInt16(UInt8.max) {
            let availability = UInt8(rawAvailability)
            var samplers = seedSamplers
            var graphInputFacts: [
                Int: SceneResolvedMaterialGraphInputSourceSlotFact
            ] = [:]
            var seen = Set<UInt8>()
            var stable = false
            for _ in 0 ..< Self.maximumReadinessPasses {
                let projection: SceneResolvedMaterialTextureResolver.LaunchReadinessProjection
                switch SceneResolvedMaterialTextureResolver.launchReadinessProjection(
                    template: template, samplers: samplers,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    assetStates: assetStates,
                    graphInputSourceSlotFacts: graphInputFacts
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
                        graphTextureFormatFacts: graphTextureFormatFacts,
                        assetFormatFacts: assetFormatFacts,
                        assetStates: assetStates
                    ) {
                case let .success(value): profiles = value
                case let .failure(failure):
                    return .failure(.material(failure))
                }
                let purposeProfiles: [[SceneTextureLoadPurpose?]]
                do {
                    purposeProfiles = try SceneResolvedMaterialTextureResolver
                        .launchSelectedTexturePurposeProfiles(
                            template: template,
                            samplers: samplers
                        )
                } catch let failure as Failure {
                    return .failure(.material(failure))
                } catch {
                    return .failure(.material(Self.failure(
                        .identityInvariant,
                        phase: .invariant
                    )))
                }
                var variants: [Variant] = []
                var keys: [SceneResolvedMaterialVariantKey] = []
                do {
                    for profile in profiles {
                        for purposeProfile in purposeProfiles {
                            guard let key = SceneResolvedMaterialVariantKey(
                                readinessMask: mask,
                                textureFormats: profile,
                                selectedTexturePurposes: purposeProfile
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
                            keys.append(key)
                            variants.append(try entry(
                                for: key,
                                outputStorage: outputStorage,
                                outputIsRGBA8Unorm: outputIsRGBA8Unorm,
                                implicitFramebufferIdentity:
                                    implicitFramebufferIdentity,
                                graphTextureFormatFacts: graphTextureFormatFacts
                            ))
                        }
                    }
                } catch let failure as Failure {
                    return .failure(.material(failure))
                } catch {
                    return .failure(.material(Self.failure(
                        .identityInvariant, phase: .invariant
                    )))
                }
                if let failure = Self.samplerVariantSchemaFailure(variants.map {
                    ($0.activeSamplers, $0.frontendProgram.textureBindings)
                }) {
                    return .failure(.material(failure))
                }
                let variant = variants[0]
                guard variants.dropFirst().allSatisfy({
                    $0.graphInputSourceSlotFacts
                        == variant.graphInputSourceSlotFacts
                }) else {
                    return .failure(.material(Self.failure(
                        .samplerVariantSchemaDivergence,
                        phase: .preparation,
                        details: ["graph-input-source-fact-divergence"]
                    )))
                }
                let nextProjection: SceneResolvedMaterialTextureResolver.LaunchReadinessProjection
                switch SceneResolvedMaterialTextureResolver.launchReadinessProjection(
                    template: template, samplers: variant.activeSamplers,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    assetStates: assetStates,
                    graphInputSourceSlotFacts:
                        variant.graphInputSourceSlotFacts
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
                            outputStorage: outputStorage,
                            implicitFramebufferIdentity: implicitFramebufferIdentity,
                            graphTextureContentFacts: graphTextureContentFacts,
                            assetStates: assetStates
                        ) {
                        // A readiness combo cannot make an unconditionally
                        // sampled slot executable when its optional asset is
                        // absent. Keep that hypothetical mask out of the
                        // launch envelope; the ready mask remains the owner,
                        // while a later missing publication still fails the
                        // smallest effect at frame selection.
                        if failure.phase == .texture,
                           failure.code == .textureBindingInvalid,
                           let slot = failure.slot,
                           (0 ..< 8).contains(slot),
                           nextProjection.requiredMask
                            & (UInt8(1) << UInt8(slot)) == 0,
                           nextProjection.optionalMask
                            & (UInt8(1) << UInt8(slot)) != 0 {
                            stable = true
                            break
                        }
                        return .failure(.material(failure))
                    }
                    reached.insert(mask)
                    for compiled in variants {
                        if compiled.graphInputSourceSlotFacts.values.contains(
                            where: {
                                $0.provenance
                                    == .dormantUnresolvedMaterialAlias
                            }
                        ) {
                            if let dormantLaunchFacts {
                                guard dormantLaunchFacts
                                        == compiled.graphInputSourceSlotFacts else {
                                    return .failure(.material(Self.failure(
                                        .samplerVariantSchemaDivergence,
                                        phase: .preparation,
                                        details: [
                                            "dormant-graph-input-variant-divergence",
                                        ]
                                    )))
                                }
                            } else {
                                dormantLaunchFacts =
                                    compiled.graphInputSourceSlotFacts
                            }
                        }
                        for (slot, sampler) in compiled.activeSamplers {
                            reachableSamplers[slot, default: []].insert(sampler)
                        }
                    }
                    admittedKeys.formUnion(keys)
                    stable = true
                    break
                }
                samplers = variant.activeSamplers
                graphInputFacts = variant.graphInputSourceSlotFacts
            }
            guard stable else {
                return .failure(.material(Self.failure(
                    .shaderPreparationFailed,
                    phase: .preparation,
                    details: ["texture-schema-budget"]
                )))
            }
        }
        cachedLaunchEnvelopeKeys = admittedKeys
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
                  input.template.uniformDeclarations == template.uniformDeclarations,
                  input.template.compatibilityTarget
                    == template.compatibilityTarget,
                  input.template.effectContext == template.effectContext else {
                throw Self.failure(
                    .variantSelectionTemplateIdentityInvariant,
                    phase: .invariant
                )
            }
            guard hasCachedReachability,
                  cachedReachabilityIdentity == input.implicitFramebufferIdentity,
                  let reachableSamplers = cachedReachableSamplers else {
                throw Self.failure(
                    .variantSelectionReachabilityIdentityInvariant,
                    phase: .invariant
                )
            }
            var matches: [Variant] = []
            var selectionFailures: [Failure] = []
            var resolvedCandidateCount = 0
            var keyMismatchDetails: [String] = []
            for key in cachedLaunchEnvelopeKeys {
                guard case let .ready(variant)? = entries[key] else { continue }
                do {
                    let channelUses = try Self.validatedSamplerChannelUses(
                        variant.activeSamplers,
                        bindings: variant.frontendProgram.textureBindings
                    )
                    let resolvedKey = try SceneResolvedMaterialTextureResolver
                        .variantKey(
                            input,
                            samplers: variant.activeSamplers,
                            reachableSamplers: reachableSamplers,
                            formatSlots: textureFormatSlots,
                            channelUses: channelUses,
                            allowPresenceIndependentDefaults: true,
                            restrictToSamplerSlots: false,
                            graphInputSourceSlotFacts:
                                variant.graphInputSourceSlotFacts
                        )
                    resolvedCandidateCount += 1
                    if resolvedKey == key {
                        matches.append(variant)
                    } else if keyMismatchDetails.count < 4 {
                        keyMismatchDetails.append(Self.variantKeyMismatchDetail(
                            expected: key,
                            resolved: resolvedKey,
                            activeSamplerSlots: Set(variant.activeSamplers.keys)
                        ))
                    }
                } catch let failure as Failure {
                    selectionFailures.append(failure)
                } catch {
                    throw Self.failure(
                        .variantSelectionUnexpectedFailure,
                        phase: .invariant
                    )
                }
            }
            guard matches.count == 1, let variant = matches.first else {
                if resolvedCandidateCount == 0,
                   let failure = selectionFailures.first,
                   selectionFailures.allSatisfy({ $0 == failure }) {
                    throw failure
                }
                throw Self.failure(
                    .variantSelectionKeyInvariant,
                    phase: .invariant,
                    details: [([
                        "admitted-\(cachedLaunchEnvelopeKeys.count)",
                        "resolved-\(resolvedCandidateCount)",
                        "matches-\(matches.count)",
                    ] + keyMismatchDetails).joined(separator: ",")]
                )
            }
            return .success(.init(
                variant: variant,
                reachableSamplers: reachableSamplers
            ))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Self.failure(
                .variantSelectionUnexpectedFailure,
                phase: .invariant
            ))
        }
    }

    private static func variantKeyMismatchDetail(
        expected: SceneResolvedMaterialVariantKey,
        resolved: SceneResolvedMaterialVariantKey,
        activeSamplerSlots: Set<Int>
    ) -> String {
        let differingFormats = (0 ..< 8).compactMap { slot -> String? in
            guard expected.textureFormats[slot] != resolved.textureFormats[slot] else {
                return nil
            }
            let lhs = expected.textureFormats[slot].map { String($0.rawValue) } ?? "nil"
            let rhs = resolved.textureFormats[slot].map { String($0.rawValue) } ?? "nil"
            return "s\(slot)-\(lhs)-\(rhs)"
        }.joined(separator: "_")
        let activeMask = activeSamplerSlots.reduce(UInt8(0)) { partial, slot in
            partial | (UInt8(1) << UInt8(slot))
        }
        let differingPurposes = (0 ..< 8).compactMap { slot -> String? in
            guard expected.selectedTexturePurposes[slot]
                    != resolved.selectedTexturePurposes[slot] else { return nil }
            return "s\(slot)-\(String(describing: expected.selectedTexturePurposes[slot]))"
                + "-\(String(describing: resolved.selectedTexturePurposes[slot]))"
        }.joined(separator: "_")
        return "key-e\(expected.readinessMask)-r\(resolved.readinessMask)"
            + "-a\(activeMask)-f\(differingFormats.isEmpty ? "none" : differingFormats)"
            + (differingPurposes.isEmpty ? "" : "-p\(differingPurposes)")
    }

    private func entry(
        for key: SceneResolvedMaterialVariantKey,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage,
        outputIsRGBA8Unorm: Bool,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphTextureFormatFacts: [Graph.TextureIdentity: SceneShaderTextureFormat]
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
                outputStorage: outputStorage,
                outputIsRGBA8Unorm: outputIsRGBA8Unorm,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                graphTextureFormatFacts: graphTextureFormatFacts,
                onBoundedFrontendCompilation: { frontendCompilations += 1 }
            )
            entries[key] = .ready(variant)
            return variant
        } catch let failure as Failure {
            entries[key] = .failed(failure)
            throw failure
        }
    }
}

nonisolated extension SceneResolvedMaterialVariantCache {
    static func premultipliedAuxiliaryColorSlots(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        externalSlots: Set<Int>,
        terminalNamedSlots: Set<Int>,
        sceneBackgroundSlots: Set<Int>,
        conditionalFact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact?
    ) -> Set<Int> {
        let terminalNamed = externalSlots == terminalNamedSlots
            ? terminalNamedSlots
            : []
        guard let conditionalFact,
              !sceneBackgroundSlots.isEmpty,
              externalSlots == sceneBackgroundSlots,
              sceneBackgroundSlots.isSubset(
                  of: conditionalFact.generatedOpaqueColorSlots
              ), sceneBackgroundSlots.allSatisfy({ slot in
                  guard let sampler = samplers[slot],
                        let reference = SceneResolvedMaterialTextureResolver
                            .sceneBackgroundDefault(
                                template: template,
                                sampler: sampler,
                                slot: slot
                            ) else { return false }
                  return sampler.purpose(for: reference) == .premultipliedColor
              }) else { return terminalNamed }
        return terminalNamed.union(sceneBackgroundSlots)
    }
}
