import Foundation

nonisolated struct SceneResolvedMaterialVariantKey: Hashable {
    let readinessMask: UInt8
    let textureFormats: [SceneShaderTextureFormat?]
    /// Only slots whose authored candidate chain can select more than one
    /// proven texture representation participate here. Static slots retain
    /// their existing launch contract, while a mixed provider slot cannot
    /// accidentally reuse the ABI compiled for another selected candidate.
    let selectedTexturePurposes: [SceneTextureLoadPurpose?]

    init?(
        readinessMask: UInt8,
        textureFormats: [SceneShaderTextureFormat?],
        selectedTexturePurposes: [SceneTextureLoadPurpose?] = Array(
            repeating: nil,
            count: 8
        )
    ) {
        guard textureFormats.count == 8,
              selectedTexturePurposes.count == 8 else { return nil }
        self.readinessMask = readinessMask
        self.textureFormats = textureFormats
        self.selectedTexturePurposes = selectedTexturePurposes
    }

    var resolvedTextureFormats: [Int: SceneShaderTextureFormat] {
        Dictionary(uniqueKeysWithValues: textureFormats.enumerated().compactMap {
            index, format in format.map { (index, $0) }
        })
    }
}

extension SceneResolvedMaterialVariantCache {
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse

    /// A singular effect projection is usable only when no prepared launch
    /// variant consumes an effect-projection host uniform. Uniform ownership
    /// was already compiled with the variant; do not reconstruct it here.
    var requiresInvertibleEffectTextureProjection: Bool {
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else {
            return true
        }
        return snapshot.variants.contains(
            where: \.requiresInvertibleEffectTextureProjection
        )
    }

    /// At least one launch-envelope variant must consume the slot, and every
    /// consuming variant must either observe the stored red scalar directly or
    /// consume the complete vector supplied by a typed Metal R texture.
    func provesScalarRedConsumer(slot: Int) -> Bool {
        guard let uses = compiledChannelUses(for: slot) else { return false }
        return Self.channelEnvelopeIsScalarRedCompatible(uses)
    }

    /// At least one launch-envelope variant must consume the slot, and every
    /// consuming variant must either observe a nonempty subset of stored R/G
    /// or the complete vector supplied by a typed Metal R/G texture.
    func provesRedGreenConsumer(slot: Int) -> Bool {
        guard let uses = compiledChannelUses(for: slot) else { return false }
        return Self.channelEnvelopeIsRedGreenCompatible(uses)
    }

    /// Every precompiled launch variant must preserve one exact independent
    /// RGBA signal slot. A single matching variant cannot type a feedback
    /// target whose other launch variants observe a different color contract.
    func provesIndependentAlphaSignalPreserving(slot: Int) -> Bool {
        launchEnvelopeProvesColorTransfer(
            .independentAlphaSignalPreserving(textureSlot: slot),
            requiredSlots: [slot]
        )
    }

    /// Every precompiled launch variant must consume the same independent
    /// signal and compositable color slots. The graph classifier separately
    /// binds those slots to exact authored identities.
    func provesIndependentAlphaSignalCompositing(
        signalSlot: Int,
        colorSlot: Int
    ) -> Bool {
        guard signalSlot != colorSlot else { return false }
        return launchEnvelopeProvesColorTransfer(
            .independentAlphaSignalCompositing(
                signalSlot: signalSlot,
                colorSlot: colorSlot
            ),
            requiredSlots: [signalSlot, colorSlot]
        )
    }

    /// Alpha-only reads preserve the signal's storage semantics without
    /// claiming that this reader produces or modifies the feedback signal.
    func provesAlphaOnlySampling(slot: Int) -> Bool {
        guard (0 ..< 8).contains(slot) else { return false }
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else { return false }
        return snapshot.variants.allSatisfy { variant in
            let bindings = variant.frontendProgram.textureBindings
            let samples = bindings.filter { $0.slot == slot }
            guard Set(bindings.map(\.slot)).count == bindings.count,
                  samples.count == 1, samples[0].channelUse == .alphaOnly,
                  variant.activeSamplers[slot] != nil,
                  let boundary = variant.frontendProgram.colorBoundary,
                  boundary.isValid, boundary.alphaInputSlots.contains(slot) else {
                return false
            }
            return true
        }
    }

    private func launchEnvelopeProvesColorTransfer(
        _ transfer: SceneShaderColorTransfer,
        requiredSlots: Set<Int>
    ) -> Bool {
        guard requiredSlots.allSatisfy({ (0 ..< 8).contains($0) }) else {
            return false
        }
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else {
            return false
        }
        return snapshot.variants.allSatisfy { variant in
            let bindings = variant.frontendProgram.textureBindings
            let activeSlots = Set(bindings.map(\.slot))
            return variant.frontendProgram.colorTransfer == transfer
                && activeSlots.count == bindings.count
                && requiredSlots.isSubset(of: activeSlots)
                && requiredSlots.allSatisfy { slot in
                    bindings.filter { $0.slot == slot }.count == 1
                        && variant.activeSamplers[slot] != nil
                }
        }
    }

    static func channelEnvelopeIsScalarRedCompatible(
        _ uses: [ChannelUse]
    ) -> Bool {
        !uses.isEmpty && uses.allSatisfy {
            [.redOnly, .wholeVector].contains($0)
        }
    }

    static func channelEnvelopeIsRedGreenCompatible(_ uses: [ChannelUse]) -> Bool {
        !uses.isEmpty && uses.allSatisfy {
            [.redOnly, .greenOnly, .redGreenOnly, .wholeVector].contains($0)
        }
    }

#if DEBUG || SCENE_GRAPH_TESTING
    struct Counters: Equatable {
        let cachedVariantCount: Int
        let shaderPreparationCount: Int
        /// Bounded Swift frontend invocations; generic artifact hits do not increment.
        let frontendCompilationCount: Int
        let capacityRejectionCount: Int
    }

#endif

    enum LaunchEnvelopeFailure: Error {
        enum Kind: String {
            case capacity
            case shaderPreparation = "shader-preparation"
            case frontend
            case samplerSchema = "sampler-schema"
            case uniformSchema = "uniform-schema"
            case texturePurpose = "texture-purpose"
            case textureBinding = "texture-binding"
            case animatedFrameMetadata = "animated-frame-metadata"
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
                case .authoredSamplerSchemaInvalid: .samplerSchema
                case .uniformBindingInvalid: .uniformSchema
                case .texturePurposeUnproven: .texturePurpose
                case .animatedFrameMetadataInvalid: .animatedFrameMetadata
                case .textureBindingInvalid, .textureReferenceInvalid:
                    .textureBinding
                case .colorContractUnproven: .colorContract
                default: .invariant
                }
            }
        }
    }

    struct LaunchReadinessProjection {
        let requiredMask: UInt8
        let optionalMask: UInt8

        func mask(optionalAvailability: UInt8) -> UInt8 {
            requiredMask | (optionalMask & optionalAvailability)
        }
    }

    enum LaunchAuthoredReference {
        case none
        case selected(
            Template.TextureReference,
            purpose: SceneTextureLoadPurpose?
        )
        case deferred
    }

    /// Enumerates only representation choices that can be selected by the
    /// named publication or mixed-provider contract. Combined with readiness and
    /// format profiles before launch so frame finalization never compiles.
    static func launchSelectedTexturePurposeProfiles(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        readinessMask: UInt8
    ) throws -> [[SceneTextureLoadPurpose?]] {
        let facts = SceneResolvedMaterialVariantCache.mixedProviderSlotFacts(
            in: template,
            samplers: samplers
        )
        let purposeSlots = Set(facts.keys).union(
            SceneResolvedMaterialVariantCache.regularNamedProviderPurposeSlots(
                in: template, samplers: samplers
            )
        )
        var profiles = [Array<SceneTextureLoadPurpose?>(
            repeating: nil,
            count: 8
        )]
        // An absent conditional input has no representation to select. Its
        // inactive Program must use the same nil purpose key as frame selection.
        for slot in purposeSlots.sorted() where readinessMask & (1 << UInt8(slot)) != 0 {
            var expanded: [[SceneTextureLoadPurpose?]] = []
            for profile in profiles {
                for purpose in [
                    SceneTextureLoadPurpose.preservedChannels,
                    .premultipliedColor,
                ] {
                    var next = profile
                    next[slot] = purpose
                    expanded.append(next)
                    guard expanded.count <= 256 else {
                        throw failure(
                            .shaderPreparationFailed,
                            slot: slot
                        )
                    }
                }
            }
            profiles = expanded
        }
        return profiles
    }

    /// Mirrors frame precedence for immutable asset candidates. Only an exact
    /// absent state may expose a lower-priority candidate; all other unready
    /// states fail launch admission instead of becoming a fallback.
    static func launchAuthoredReference(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler?,
        slot: Int,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) throws -> LaunchAuthoredReference {
        guard template.textureSlots.indices.contains(slot),
              let textureSlot = template.textureSlots[slot] else { return .none }
        for ordinal in textureSlot.candidates.indices.reversed() {
            let candidate = textureSlot.candidates[ordinal]
            switch candidate.reference {
            case .asset:
                guard let sampler else { return .deferred }
                // Reachability is settled by the prepared Program fixed point.
                // An unproven candidate purpose cannot be loaded yet, but it
                // also cannot revoke a material before the compiler determines
                // whether this sampler is active. Active uses still fail closed
                // in launchProgramFailure and capability demand admission.
                guard let purpose = SceneResolvedMaterialTextureSlotPurpose.fact(
                    in: textureSlot,
                    candidateOrdinal: ordinal,
                    sampler: sampler
                )?.purpose else {
                    return .deferred
                }
                switch try launchAssetState(
                    candidate.reference,
                    purpose: purpose,
                    assetStates: assetStates,
                    slot: slot
                ) {
                case .ready, .preparedVideo:
                    return .selected(candidate.reference, purpose: purpose)
                case .absent: continue
                case .effectLocalUnavailable(.animatedFrameMetadataInvalid):
                    throw failure(
                        .animatedFrameMetadataInvalid,
                        slot: slot
                    )
                case .pending, .unavailable:
                    throw failure(.textureBindingInvalid, slot: slot)
                }
            case .userProperty:
                // A property-backed texture has no launch-time publication,
                // but the exact mixed property/named envelope proves both
                // selectable representations before frames begin. Treat its
                // high-precedence reference like another typed provider once
                // the sampler is known; arbitrary property slots remain
                // deferred and cannot acquire product authority here.
                guard let sampler,
                      let mixed = SceneResolvedMaterialMixedProviderSlotFact
                        .resolve(in: textureSlot, sampler: sampler),
                      case .userProperty = mixed.optionalInput,
                      let purpose = mixed.purpose(for: candidate.reference)
                else { return .deferred }
                return .selected(candidate.reference, purpose: purpose)
            case .provider, .graph:
                return .selected(
                    candidate.reference,
                    purpose: sampler.flatMap { SceneResolvedMaterialShaderSchema.purpose(for: candidate.reference, sampler: $0) }
                )
            }
        }
        return .none
    }

    /// One default selection for launch readiness, format and color contracts.
    /// Only exact asset absence reaches the same registered-noise substitution
    /// used by frame selection; publication completion remains authoritative.
    static func launchDefaultReference(
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState]
    ) throws -> LaunchAuthoredReference {
        guard case let .asset(path)? = sampler.defaultTexture else { return .none }
        let reference = Template.TextureReference.asset(path)
        let purpose = SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler)
        switch try launchAssetState(
            reference, sampler: sampler, assetStates: assetStates, slot: slot
        ) {
        case .ready, .preparedVideo: return .selected(reference, purpose: purpose)
        case .absent:
            guard SceneStockTextureSemanticRegistry.canSubstituteNoise(
                path, purpose: purpose
            ) else { return .none }
            let identity = SceneSystemProviderTextureIdentity(name: path.value, purpose: .noise)
            guard case let .ready(publication)? = systemProviderStates[identity],
                  publication.requestIdentity == .system(identity),
                  publication.isComplete, publication.generationIsCurrent,
                  publication.candidate.purpose == .noise,
                  publication.candidate.content == .data else {
                throw failure(.textureBindingInvalid, slot: slot)
            }
            return .selected(.provider(.system(path.value)), purpose: .noise)
        case .effectLocalUnavailable(.animatedFrameMetadataInvalid):
            throw failure(.animatedFrameMetadataInvalid, slot: slot)
        case .pending, .unavailable:
            throw failure(.textureBindingInvalid, slot: slot)
        }
    }

    static func launchAssetState(
        _ reference: Template.TextureReference,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        slot: Int
    ) throws -> SceneAssetTextureLaunchState {
        guard let purpose = SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler) else {
            throw failure(.texturePurposeUnproven, slot: slot)
        }
        return try launchAssetState(
            reference,
            purpose: purpose,
            assetStates: assetStates,
            slot: slot
        )
    }

    static func launchAssetState(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        slot: Int
    ) throws -> SceneAssetTextureLaunchState {
        guard case let .asset(path) = reference else {
            throw failure(.texturePurposeUnproven, slot: slot)
        }
        let identity = SceneAssetTextureIdentity(path: path, purpose: purpose)
        guard let state = assetStates[identity] else {
            throw failure(.textureBindingInvalid, slot: slot)
        }
        return state
    }

    /// Projects runtime texture precedence without consulting a frame.
    static func launchReadinessProjection(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:],
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ] = [:]
    ) -> Result<LaunchReadinessProjection, Failure> {
        do {
            guard template.textureSlots.count == 8,
                  samplers.keys.allSatisfy((0 ..< 8).contains)
            else {
                throw failure(.identityInvariant, phase: .invariant)
            }
            let structuralFacts = SceneResolvedMaterialShaderSchema
                .graphInputSourceSlotFacts(
                    template: template,
                    samplers: samplers,
                    inputIdentity: implicitFramebufferIdentity
                )
            var graphFacts = structuralFacts
            for (slot, fact) in graphInputSourceSlotFacts
                where fact.provenance == .dormantUnresolvedMaterialAlias
            {
                guard samplers[slot] != nil,
                      fact.slot == slot,
                      fact.inputIdentity == implicitFramebufferIdentity
                else {
                    throw failure(
                        .textureReferenceInvalid,
                        slot: slot
                    )
                }
                graphFacts[slot] = fact
            }
            var required: UInt8 = 0
            var optional: UInt8 = 0
            for index in 0 ..< 8 {
                let bit = UInt8(1) << UInt8(index)
                let sampler = samplers[index]
                var reachesFallback = true
                var hasOptionalSource = false
                if let slot = template.textureSlots[index] {
                    guard slot.index == index else {
                        throw failure(.identityInvariant, phase: .invariant)
                    }
                    switch try launchAuthoredReference(
                        template: template,
                        sampler: sampler,
                        slot: index,
                        assetStates: assetStates
                    ) {
                    case .selected:
                        if sampler == nil {
                            // The candidate may be a readiness signal for a
                            // conditional declaration, but it is not required
                            // consumption until that sampler becomes active.
                            hasOptionalSource = true
                            // A readiness-combo asset may disappear between the
                            // immutable launch census and a concrete frame. Cache
                            // both combo-off and combo-on Programs even when the
                            // launch snapshot is ready; frame selection still
                            // refuses pending/unavailable instead of silently
                            // substituting the combo-off result.
                        } else if sampler?.readinessCombo != nil {
                            hasOptionalSource = true
                        } else {
                            required |= bit
                            reachesFallback = false
                        }
                    case .none:
                        break
                    case .deferred:
                        hasOptionalSource = true
                    }
                }
                if reachesFallback, let sampler {
                    switch sampler.defaultTexture {
                    case .asset where sampler.readinessCombo == nil:
                        if case .selected = try launchDefaultReference(
                            sampler: sampler, slot: index,
                            assetStates: assetStates,
                            systemProviderStates: systemProviderStates
                        ) { required |= bit }
                    case .internalTarget where SceneResolvedMaterialShaderSchema.renderTargetDefault(
                        template: template, sampler: sampler, slot: index,
                        inputIdentity: implicitFramebufferIdentity
                    ) != nil:
                        required |= bit
                    case .internalTarget where sampler.readinessCombo == nil:
                        throw failure(.textureBindingInvalid, slot: index)
                    case .asset, .internalTarget, nil:
                        break
                    }
                    if let fact = graphFacts[index] {
                        let reference = Template.TextureReference.graph(
                            fact.inputIdentity
                        )
                        guard SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler) != nil else {
                            throw failure(
                                .textureReferenceInvalid,
                                slot: index
                            )
                        }
                        required |= bit
                    } else if SceneResolvedMaterialShaderSchema.usesGraphInputMaterialAlias(sampler)
                        || SceneResolvedMaterialShaderSchema
                        .implicitFramebufferSlots(
                            template: template,
                            samplers: samplers
                        ).contains(index)
                    {
                        throw failure(
                            .textureReferenceInvalid,
                            slot: index
                        )
                    }
                }
                if required & bit == 0, hasOptionalSource {
                    if sampler == nil || sampler?.readinessCombo != nil {
                        optional |= bit
                    } else {
                        required |= bit
                    }
                }
            }
            return .success(.init(
                requiredMask: required,
                optionalMask: optional
            ))
        } catch let error as Failure {
            return .failure(error)
        } catch {
            return .failure(failure(.identityInvariant, phase: .invariant))
        }
    }

    static func launchTextureFormatProfiles(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        readinessMask: UInt8,
        formatSlots: Set<Int>,
        implicitFramebufferIdentity: Graph.TextureIdentity? = nil,
        graphTextureFormatFacts: [
            Graph.TextureIdentity: SceneShaderTextureFormat
        ],
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:]
    ) -> Result<[[SceneShaderTextureFormat?]], Failure> {
        guard template.textureSlots.count == 8,
              formatSlots.allSatisfy((0 ..< 8).contains)
        else {
            return .failure(failure(
                .identityInvariant,
                phase: .invariant
            ))
        }
        var profiles = [[SceneShaderTextureFormat?](
            repeating: nil,
            count: 8
        )]
        for slot in formatSlots.sorted() {
            let isReady = readinessMask & (UInt8(1) << UInt8(slot)) != 0
            let options: [SceneShaderTextureFormat?]
            if !isReady {
                options = [nil]
            } else {
                var possible = Set<SceneShaderTextureFormat?>()
                let sampler = samplers[slot]
                let authored: LaunchAuthoredReference
                do {
                    authored = try launchAuthoredReference(
                        template: template,
                        sampler: sampler,
                        slot: slot,
                        assetStates: assetStates
                    )
                } catch let failure as Failure {
                    return .failure(failure)
                } catch {
                    return .failure(failure(
                        .identityInvariant,
                        phase: .invariant,
                        slot: slot
                    ))
                }
                switch authored {
                case let .selected(reference, purpose):
                    possible.formUnion(formats(
                        for: reference,
                        resolvedPurpose: purpose,
                        sampler: sampler,
                        graphTextureFormatFacts: graphTextureFormatFacts,
                        assetFormatFacts: assetFormatFacts
                    ))
                case .deferred:
                    possible.insert(nil)
                case .none:
                    if let sampler {
                        switch sampler.defaultTexture {
                        case .asset where sampler.readinessCombo == nil:
                            do {
                                if case let .selected(reference, purpose) = try launchDefaultReference(
                                    sampler: sampler, slot: slot,
                                    assetStates: assetStates,
                                    systemProviderStates: systemProviderStates
                                ) {
                                    if case let .provider(.system(name)) = reference,
                                       let purpose,
                                       case let .ready(publication)? = systemProviderStates[
                                           .init(name: name, purpose: purpose)
                                       ] {
                                        possible.insert(publication.candidate.authoredFormat)
                                    } else {
                                        possible.formUnion(formats(
                                            for: reference, resolvedPurpose: purpose,
                                            sampler: sampler,
                                            graphTextureFormatFacts: graphTextureFormatFacts,
                                            assetFormatFacts: assetFormatFacts
                                        ))
                                    }
                                }
                            } catch let failure as Failure {
                                return .failure(failure)
                            } catch {
                                return .failure(failure(.identityInvariant, phase: .invariant))
                            }
                        case .internalTarget where sampler.readinessCombo == nil:
                            if let reference = SceneResolvedMaterialShaderSchema.renderTargetDefault(
                                template: template, sampler: sampler, slot: slot,
                                inputIdentity: implicitFramebufferIdentity ?? template.effectContext?.input
                            ) {
                                possible.formUnion(formats(
                                    for: reference, resolvedPurpose: SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler),
                                    sampler: sampler, graphTextureFormatFacts: graphTextureFormatFacts,
                                    assetFormatFacts: assetFormatFacts
                                ))
                            } else { possible.insert(nil) }
                        case .asset, .internalTarget, nil:
                            break
                        }
                        if SceneResolvedMaterialShaderSchema.usesGraphInputMaterialAlias(sampler) {
                            possible.insert(nil)
                        }
                    }
                }
                if possible.isEmpty { possible.insert(nil) }
                options = possible.sorted(by: less)
            }
            var expanded: [[SceneShaderTextureFormat?]] = []
            for profile in profiles {
                for option in options {
                    var next = profile
                    next[slot] = option
                    expanded.append(next)
                    guard expanded.count <= 256 else {
                        return .failure(failure(
                            .shaderPreparationFailed,
                            phase: .preparation
                        ))
                    }
                }
            }
            profiles = expanded
        }
        return .success(profiles)
    }

    private static func formats(
        for reference: Template.TextureReference,
        resolvedPurpose: SceneTextureLoadPurpose?,
        sampler: SceneResolvedMaterialShaderSchema.Sampler?,
        graphTextureFormatFacts: [
            Graph.TextureIdentity: SceneShaderTextureFormat
        ],
        assetFormatFacts: [String: Int]
    ) -> Set<SceneShaderTextureFormat?> {
        switch reference {
        case let .graph(identity):
            return [graphTextureFormatFacts[identity]]
        case let .asset(path):
            guard let sampler,
                  let purpose = resolvedPurpose
                  ?? SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler) else { return [nil] }
            let identity = SceneAssetTextureIdentity(path: path, purpose: purpose)
            guard let value = assetFormatFacts[identity.reportToken] else {
                return [nil]
            }
            if value == -1 { return [] }
            guard let rawValue = UInt32(exactly: value),
                  let format = SceneShaderTextureFormat(rawValue: rawValue)
            else {
                return [nil]
            }
            return [format]
        case .userProperty, .provider:
            return [nil]
        }
    }

    private static func less(
        _ lhs: SceneShaderTextureFormat?,
        _ rhs: SceneShaderTextureFormat?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): false
        case (nil, _): true
        case (_, nil): false
        case let (lhs?, rhs?): lhs.rawValue < rhs.rawValue
        }
    }

    static func consensusPurposes(
        _ profiles: [[Int: [SceneTextureLoadPurpose?]]]
    ) -> [Int: [SceneTextureLoadPurpose?]] {
        var result: [Int: [SceneTextureLoadPurpose?]] = [:]
        for profile in profiles {
            for (slot, purposes) in profile {
                if let prior = result[slot] {
                    // One unproven or conflicting reachable variant keeps
                    // this candidate unproven for an inactive sampler.
                    result[slot] = zip(prior, purposes).map { $0.0 == $0.1 ? $0.0 : nil }
                } else {
                    result[slot] = purposes
                }
            }
        }
        return result
    }

}
