import Foundation

extension SceneResolvedMaterialShaderSchema {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct ReachabilityVariantKey: Hashable {
        let readinessMask: UInt8
        let textureFormats: [SceneShaderTextureFormat?]
    }

    /// Enumerates the bounded readiness fixed points that launch admission can
    /// reach. The union is used only to preload typed resources; frame-time
    /// variant selection still resolves one exact immutable Program.
    nonisolated static func reachableSamplers(
        _ template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        textureFormatProfiles: [[Int: SceneShaderTextureFormat]]? = nil
    ) throws -> [Int: Set<Sampler>] {
        let profiles = try textureFormatProfiles
            ?? SceneResolvedMaterialTextureResolver
                .exhaustiveLaunchTextureFormatProfiles(template: template)
        guard !profiles.isEmpty else { throw Issue.sampler("texture-format-envelope") }
        var cache: [ReachabilityVariantKey: [Int: Sampler]] = [:]
        func samplers(
            for mask: UInt8,
            textureFormats: [Int: SceneShaderTextureFormat]
        ) throws -> [Int: Sampler] {
            let formatSlots = (0 ..< 8).map { textureFormats[$0] }
            let key = ReachabilityVariantKey(
                readinessMask: mask,
                textureFormats: formatSlots
            )
            if let cached = cache[key] { return cached }
            let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
                ($0, mask & (UInt8(1) << UInt8($0)) != 0)
            })
            let prepared: SceneShaderPreparedProgram
            switch SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: template.shaderContract,
                combos: template.comboValues,
                inactiveComboProviders: Set(template.inheritedInactiveCombos),
                textureReadiness: readiness,
                textureFormats: textureFormats
            ) {
            case let .accepted(value): prepared = value
            case let .rejected(failure):
                throw Issue.sampler(
                    (["reachable-variant", failure.phase.rawValue, failure.code.rawValue]
                        + failure.details).joined(separator: ":")
                )
            case .notApplicable:
                throw Issue.sampler("reachable-variant:not-applicable")
            }
            let result = try activeSamplers(
                prepared,
                runtimeLoopBounds: SceneResolvedMaterialRuntimeLoopBoundResolver.resolve(
                    template: template,
                    prepared: prepared
                )
            )
            cache[key] = result
            return result
        }

        let bootstrap = try unconditionalSamplers(template)
        var reachable: [Int: Set<Sampler>] = [:]
        for availability in launchAvailabilityMasks(template) {
            var active = bootstrap
            var seen: Set<UInt8> = []
            var stable = false
            for _ in 0 ..< 8 {
                let mask = try readinessMask(
                    template,
                    samplers: active,
                    availability: availability,
                    implicitFramebufferIdentity: implicitFramebufferIdentity
                )
                guard seen.insert(mask).inserted else {
                    throw Issue.sampler("readiness-cycle")
                }
                let variants = try profiles.map {
                    try samplers(for: mask, textureFormats: $0)
                }
                guard let representative = variants.first,
                      variants.dropFirst().allSatisfy({ $0 == representative }) else {
                    throw Issue.sampler("texture-format-schema-divergence")
                }
                active = representative
                for variant in variants {
                    for (slot, sampler) in variant {
                        reachable[slot, default: []].insert(sampler)
                    }
                }
                let next = try readinessMask(
                    template,
                    samplers: active,
                    availability: availability,
                    implicitFramebufferIdentity: implicitFramebufferIdentity
                )
                if next == mask {
                    stable = true
                    break
                }
            }
            guard stable else { throw Issue.sampler("readiness-budget") }
        }
        return reachable
    }

    /// Texture availability can only change preprocessing for sampler slots
    /// that actually provide a texture-readiness schema. Enumerating the other
    /// bits repeats the same prepared program under a different dictionary
    /// identity (up to 256 times) without adding a reachable sampler fact.
    ///
    /// Fall back to the historical exhaustive envelope when metadata cannot be
    /// projected cleanly so malformed/unsupported contracts keep their prior
    /// rejection behavior.
    private nonisolated static func launchAvailabilityMasks(
        _ template: Template
    ) -> [UInt8] {
        guard let graph = template.shaderContract.sourceGraph else {
            return Array(UInt8.min ... UInt8.max)
        }
        var readinessSlots: UInt8 = 0
        for node in graph.nodes {
            let parsed = SceneShaderContractSourceParser().parse(
                node.source,
                stageRelativePath: node.virtualPath
            )
            let source = SceneShaderVariantSchemaSource(
                relativePath: node.virtualPath,
                source: node.source,
                annotations: parsed.annotations,
                declarations: parsed.declarations
            )
            guard let schemas = try? SceneShaderVariantResolver.schemas(in: source)
            else { return Array(UInt8.min ... UInt8.max) }
            for slot in schemas.compactMap(\.samplerSlot) {
                guard (0 ..< 8).contains(slot) else {
                    return Array(UInt8.min ... UInt8.max)
                }
                readinessSlots |= UInt8(1) << UInt8(slot)
            }
        }
        var optionalCandidateSlots: UInt8 = 0
        for slot in template.textureSlots.compactMap({ $0 })
            where !slot.candidates.isEmpty {
            guard (0 ..< 8).contains(slot.index) else {
                return Array(UInt8.min ... UInt8.max)
            }
            optionalCandidateSlots |= UInt8(1) << UInt8(slot.index)
        }
        let relevantSlots = readinessSlots & optionalCandidateSlots
        return (UInt16(UInt8.min) ... UInt16(UInt8.max)).compactMap {
            let availability = UInt8($0)
            return availability & ~relevantSlots == 0 ? availability : nil
        }
    }

    private nonisolated static func readinessMask(
        _ template: Template,
        samplers: [Int: Sampler],
        availability: UInt8,
        implicitFramebufferIdentity: Graph.TextureIdentity?
    ) throws -> UInt8 {
        guard template.textureSlots.count == 8,
              samplers.keys.allSatisfy((0 ..< 8).contains) else {
            throw Issue.sampler("readiness-schema")
        }
        var required: UInt8 = 0
        var optional: UInt8 = 0
        for index in 0 ..< 8 {
            let bit = UInt8(1) << UInt8(index)
            let sampler = samplers[index]
            var reachesDefault = true
            var hasOptionalSource = false
            if let slot = template.textureSlots[index] {
                guard slot.index == index else {
                    throw Issue.sampler("g_Texture\(index)")
                }
                for candidate in slot.candidates.reversed() {
                    switch candidate.reference {
                    case .asset, .userProperty:
                        hasOptionalSource = true
                    case .provider, .graph:
                        if sampler == nil {
                            hasOptionalSource = true
                        } else {
                            required |= bit
                            reachesDefault = false
                        }
                    }
                    if !reachesDefault { break }
                }
            }
            if reachesDefault, let sampler {
                switch sampler.defaultTexture {
                case .asset where sampler.readinessCombo == nil:
                    required |= bit
                case .internalTarget where sampler.readinessCombo == nil:
                    throw Issue.sampler(sampler.name)
                case .asset, .internalTarget, nil:
                    break
                }
                if sampler.usesGraphInputMaterialAlias,
                   implicitFramebufferIdentity != nil {
                    required |= bit
                }
            }
            if required & bit == 0, hasOptionalSource { optional |= bit }
        }
        for slot in implicitFramebufferSlots(template: template, samplers: samplers) {
            guard implicitFramebufferIdentity != nil else {
                throw Issue.sampler("implicit-framebuffer")
            }
            required |= UInt8(1) << UInt8(slot)
        }
        return required | (optional & availability)
    }
}
