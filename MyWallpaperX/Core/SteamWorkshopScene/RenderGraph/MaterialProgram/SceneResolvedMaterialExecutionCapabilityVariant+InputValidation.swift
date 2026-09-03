import Foundation

nonisolated extension SceneResolvedMaterialVariantCache {
    static func typedStaticDataAuxiliarySlots(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        graphInputSlots: Set<Int>
    ) -> Set<Int> {
        var result = Set<Int>()
        for (slot, sampler) in samplers where !graphInputSlots.contains(slot) {
            guard template.textureSlots.indices.contains(slot) else { continue }
            let candidates = template.textureSlots[slot]?.candidates ?? []
            guard candidates.allSatisfy({
                isTypedStaticDataReference($0.reference, sampler: sampler)
            }) else { continue }
            var hasTypedStaticSource = !candidates.isEmpty
            switch sampler.defaultTexture {
            case let .asset(path):
                guard isTypedStaticDataReference(
                    .asset(path), sampler: sampler
                ) else { continue }
                hasTypedStaticSource = true
            case .internalTarget:
                continue
            case nil:
                break
            }
            if hasTypedStaticSource { result.insert(slot) }
        }
        return result
    }

    private static func isTypedStaticDataReference(
        _ reference: Template.TextureReference,
        sampler: SceneResolvedMaterialShaderSchema.Sampler
    ) -> Bool {
        guard case .asset = reference,
              let purpose = sampler.purpose(for: reference) else { return false }
        return isDataPurpose(purpose)
    }

    private static func isDataPurpose(
        _ purpose: SceneTextureLoadPurpose
    ) -> Bool {
        switch purpose {
        case .preservedChannels, .mask, .noise, .flow, .phase, .normal,
             .depth, .lookupTable:
            true
        case .premultipliedColor, .straightAlbedo:
            false
        }
    }

    static func validateSamplerBindings(
        _ samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        bindings: [SceneAuthoredShaderProgram.TextureBinding]
    ) throws {
        let slots = bindings.map(\.slot)
        guard slots == slots.sorted() else {
            throw failure(
                .samplerBindingOrderInvalid,
                phase: .invariant,
                details: slots.map(String.init)
            )
        }
        var seen = Set<Int>()
        for binding in bindings {
            guard seen.insert(binding.slot).inserted else {
                throw failure(
                    .samplerBindingDuplicateSlot,
                    phase: .invariant,
                    slot: binding.slot
                )
            }
            guard (0 ..< 8).contains(binding.slot) else {
                throw failure(
                    .samplerBindingIdentityMismatch,
                    phase: .invariant,
                    slot: binding.slot,
                    details: ["slot-out-of-range"]
                )
            }
            guard let sampler = samplers[binding.slot] else {
                throw failure(
                    .samplerBindingIdentityMismatch,
                    phase: .invariant,
                    slot: binding.slot,
                    details: ["sampler-missing", binding.name]
                )
            }
            guard sampler.slot == binding.slot,
                  sampler.name == binding.name else {
                throw failure(
                    .samplerBindingIdentityMismatch,
                    phase: .invariant,
                    slot: binding.slot,
                    details: ["sampler-name-or-slot", binding.name, sampler.name]
                )
            }
        }
    }

    static func validatedSamplerChannelUses(
        _ samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        bindings: [SceneAuthoredShaderProgram.TextureBinding]
    ) throws -> [Int: ChannelUse] {
        try validateSamplerBindings(samplers, bindings: bindings)
        return Dictionary(uniqueKeysWithValues: bindings.map {
            ($0.slot, $0.channelUse)
        })
    }

    static func samplerVariantSchemaFailure(
        _ schemas: [(
            samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
            bindings: [SceneAuthoredShaderProgram.TextureBinding]
        )]
    ) -> Failure? {
        guard let baseline = schemas.first else {
            return failure(.identityInvariant, phase: .invariant)
        }
        guard schemas.dropFirst().allSatisfy({
            $0.samplers == baseline.samplers
                && $0.bindings == baseline.bindings
        }) else {
            return failure(
                .samplerVariantSchemaDivergence,
                phase: .preparation,
                details: ["texture-format-schema-divergence"]
            )
        }
        return nil
    }
}
