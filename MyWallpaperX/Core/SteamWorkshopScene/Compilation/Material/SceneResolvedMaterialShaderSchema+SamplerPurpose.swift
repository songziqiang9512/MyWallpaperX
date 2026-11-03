import Foundation

extension SceneResolvedMaterialShaderSchema {
    private nonisolated static func explicitPurpose(for mode: TextureMode) -> SceneTextureLoadPurpose? {
        switch mode {
        case .regular: nil
        case .opacityMask: .mask
        case .rgbMask: .preservedChannels
        case .flowMask: .flow
        case .depth: .depth
        }
    }
}

extension SceneResolvedMaterialShaderSchema {
    /// Authored `format` is loss-preserved metadata. It cannot establish a
    /// texture purpose or Metal storage ABI; those facts come from the typed
    /// candidate/target contract. Keep the value well-formed, retaining the
    /// one executable format rule proven for depth samplers.
    nonisolated static func validateTextureFormat(
        _ value: SceneShaderAnnotationValue?,
        mode: TextureMode,
        name: String
    ) throws {
        guard let value else { return }
        guard let raw = value.stringValue,
              !raw.isEmpty,
              raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            throw Issue.sampler(name)
        }
        if mode == .depth,
           raw.caseInsensitiveCompare("r8") != .orderedSame {
            throw Issue.sampler(name)
        }
    }

    /// Applies source-derived color typing after the existing auxiliary
    /// proofs. Keeping both projections in one preparation step avoids
    /// exposing an untyped sampler to later material admission.
    nonisolated static func sourceTypedColorSamplers(
        _ samplers: [Int: Sampler],
        vertexSource: String,
        fragmentSource: String
    ) -> [Int: Sampler] {
        guard let syntax = SceneAuthoredShaderSyntaxAnalyzer.validatedStages(
            vertexSource: vertexSource, fragmentSource: fragmentSource
        ) else { return samplers }
        return sourceTypedColorSamplers(samplers, vertex: syntax.vertex, fragment: syntax.fragment)
    }

    nonisolated static func sourceTypedColorSamplers(
        _ samplers: [Int: Sampler],
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> [Int: Sampler] {
        let auxiliary = sourceTypedAuxiliarySamplers(
            samplers,
            vertex: vertex,
            fragment: fragment
        )
        var result = auxiliary
        let colorGraphSlots = SceneAuthoredShaderColorMixGraphAnalyzer.straightColorInputSlots(
            vertex: vertex, fragment: fragment
        )
        let rgbGraphSlots = SceneAuthoredShaderColorMixGraphAnalyzer
            .alphaPreservingRGBGraph(vertex: vertex, fragment: fragment)?
            .colorSampleSlots ?? []
        let tintSlot = SceneAuthoredShaderNeutralTextureTintAnalyzer.analyze(
            vertex: vertex, fragment: fragment
        )?.textureSlot
        for (slot, sampler) in auxiliary {
            if sampler.channelUse == .redAlphaOnly,
               permitsSourceChannelProjection(sampler) {
                // A red*alpha sample reads two stored channels, not a color
                // projection. Only an otherwise-untyped regular sampler may
                // receive that role; typed, hidden, aliased or conflicting
                // defaults keep their existing admission.
                result[slot] = sampler.withSourceProvenPurpose(.preservedChannels)
                continue
            }
            guard permitsSourceStraightColorProjection(sampler),
                  (sampler.channelUse == .wholeVector && colorGraphSlots.contains(slot))
                    || rgbGraphSlots.contains(slot)
                    || slot == tintSlot
                    || SceneAuthoredShaderTextureChannelAnalyzer
                      .provesStraightColorUse(
                          samplerName: sampler.name,
                          vertex: vertex,
                          fragment: fragment
                      ) else { continue }
            result[slot] = sampler.withSourceProvenPurpose(.straightAlbedo)
        }
        return result
    }

    nonisolated static func hasOnlyScalarDataInputs(
        _ samplers: [Int: Sampler],
        activeSlots: Set<Int>,
        resolvedFormats: [Int: SceneShaderTextureFormat]
    ) -> Bool {
        activeSlots.allSatisfy { slot in
            if let format = resolvedFormats[slot] {
                return format == .r8 || format == .r16f
            }
            guard let sampler = samplers[slot] else { return false }
            return sampler.mode == .opacityMask || sampler.mode == .depth
        }
    }

    nonisolated static func hasOnlyDefaultedOpacityMaskAuxiliary(
        _ samplers: [Int: Sampler],
        graphInputSlots: Set<Int>
    ) -> Bool {
        guard graphInputSlots.count == 1,
              graphInputSlots.allSatisfy({ slot in
                guard let sampler = samplers[slot] else { return false }
                return sampler.mode == .regular && sampler.defaultTexture == nil
              }) else { return false }
        let auxiliaries = samplers.filter { !graphInputSlots.contains($0.key) }
        guard auxiliaries.count == 1,
              let auxiliary = auxiliaries.values.first else { return false }
        return auxiliary.mode == .opacityMask && auxiliary.defaultTexture != nil
    }

    nonisolated static func hasOnlyTypedOpacityMaskAuxiliary(
        _ samplers: [Int: Sampler],
        graphInputSlots: Set<Int>
    ) -> Bool {
        guard graphInputSlots.count == 1,
              graphInputSlots.allSatisfy({ slot in
                guard let sampler = samplers[slot] else { return false }
                return sampler.mode == .regular && sampler.defaultTexture == nil
              }) else { return false }
        let auxiliaries = samplers.filter { !graphInputSlots.contains($0.key) }
        guard auxiliaries.count == 1,
              let auxiliary = auxiliaries.values.first else { return false }
        return auxiliary.mode == .opacityMask
    }

    /// A structural compatibility normalization for historical authored
    /// materials that omitted a material role. An authored material key must
    /// retain its explicit alias or proven dormant-input admission path.
    nonisolated static func implicitFramebufferSlots(
        template: Template,
        samplers: [Int: Sampler]
    ) -> Set<Int> {
        guard template.textureSlots.count == 8,
              template.graphRole.bindings.isEmpty,
              template.textureSlots[0] == nil,
              let sampler = samplers[0],
              sampler.name == "g_Texture0",
              sampler.materialKey == nil,
              sampler.mode == .regular,
              sampler.defaultTexture == nil,
              samplers.allSatisfy({ slot, auxiliary in
                  slot == 0 || hasAuthoredAuxiliarySource(
                      sampler: auxiliary,
                      slot: template.textureSlots[slot]
                  )
              }),
              template.textureSlots.enumerated().allSatisfy({ index, slot in
                  guard index != 0, let slot else { return true }
                  return slot.candidates.allSatisfy { candidate in
                      if case .graph = candidate.reference { return false }
                      return true
                  }
              }) else { return [] }
        return [0]
    }

    /// An explicit non-graph authored candidate proves only that this sampler
    /// is an auxiliary rather than a competing implicit graph input. Its load
    /// purpose remains a separate Program admission contract and may still
    /// fail closed without erasing the valid slot-zero previous/current role.
    private nonisolated static func hasAuthoredAuxiliarySource(
        sampler: Sampler,
        slot: Template.TextureSlot?
    ) -> Bool {
        if explicitPurpose(for: sampler.mode) != nil || hasTypedAuxiliaryDefault(sampler) {
            return true
        }
        guard let slot, !slot.candidates.isEmpty else { return false }
        return slot.candidates.allSatisfy { candidate in
            if case .graph = candidate.reference { return false }
            return true
        }
    }
}

extension SceneResolvedMaterialShaderSchema {
    nonisolated static func usesGraphInputMaterialAlias(_ sampler: Sampler) -> Bool {
        switch sampler.materialKey?.lowercased() {
        case "framebuffer", "previous":
            return true
        case "ui_editor_properties_framebuffer", "上一个":
            return sampler.name == "g_Texture0" && sampler.slot == 0
                && sampler.mode == .regular && sampler.isHidden
        default:
            // An editor label grants the alias only for this hidden slot-zero
            // shape; arbitrary material/property keys retain their own owner.
            guard sampler.name == "g_Texture0", sampler.slot == 0,
                  sampler.mode == .regular, sampler.isHidden,
                  let key = sampler.materialKey?.lowercased(),
                  ["mask", "texture"].contains(key) else { return false }
            return sampler.labelKey?.lowercased() == "ui_editor_properties_framebuffer"
        }
    }

    nonisolated static func purpose(
        for reference: Template.TextureReference,
        sampler: Sampler
    ) -> SceneTextureLoadPurpose? {
        if case .graph = reference {
            return explicitPurpose(for: sampler.mode) ?? .premultipliedColor
        }
        if case let .provider(provider) = reference {
            switch provider {
            case .namedLayerTarget:
                // The actual named publication may later select its data ABI.
                return .premultipliedColor
            case .sceneBackground:
                return explicitPurpose(for: sampler.mode) ?? .premultipliedColor
            case .sceneEnvironment:
                return sampler.mode == .regular ? .premultipliedColor : nil
            case .system:
                break
            }
        }
        let declared = declaredPurpose(for: sampler)
        if let sourceProvenPurpose = sampler.sourceProvenPurpose {
            if let declared,
               !sourceReadPurpose(sourceProvenPurpose, accepts: declared) { return nil }
            var selectedPurpose = declared ?? sourceProvenPurpose
            if case let .asset(defaultPath)? = sampler.defaultTexture,
               let registeredDefault = SceneStockTextureSemanticRegistry.purpose(
                   for: defaultPath
               ) {
                guard sourceReadPurpose(sourceProvenPurpose, accepts: registeredDefault)
                else { return nil }
                if declared == nil { selectedPurpose = registeredDefault }
            }
            if case let .asset(path) = reference,
               let registered = SceneStockTextureSemanticRegistry.purpose(for: path) {
                guard sourceReadPurpose(sourceProvenPurpose, accepts: registered)
                else { return nil }
                selectedPurpose = registered
            }
            return selectedPurpose
        }
        guard case let .asset(path) = reference else { return declared }
        let registeredPurpose = SceneStockTextureSemanticRegistry.purpose(for: path)
        if let declared, let registeredPurpose, declared != registeredPurpose {
            // A direct scalar mask preserves a registered 2D data resource's
            // storage role without admitting conflicting source/color/volume use.
            guard sampler.channelUse == .redOnly,
                  registeredPurpose == .noise
                    || (sampler.mode == .opacityMask && registeredPurpose.isDataPurpose
                        && !registeredPurpose.requiresVolumeTexture)
            else { return nil }
            return registeredPurpose
        }
        let candidatePurpose = registeredPurpose ?? declared
        // A typed asset default can supply the slot role, but never override
        // the selected asset's own conflicting registered purpose.
        guard sampler.mode == .regular,
              declared == nil,
              case let .asset(defaultPath)? = sampler.defaultTexture,
              let defaultPurpose = SceneStockTextureSemanticRegistry.purpose(for: defaultPath)
        else { return candidatePurpose }
        guard candidatePurpose == nil || candidatePurpose == defaultPurpose else { return nil }
        return candidatePurpose ?? defaultPurpose
    }

    nonisolated static func sourceReadPurpose(
        _ source: SceneTextureLoadPurpose,
        accepts resource: SceneTextureLoadPurpose
    ) -> Bool {
        resource == source
            || (source == .phase && resource.isDataPurpose && !resource.requiresVolumeTexture)
    }

    private nonisolated static func declaredPurpose(
        for sampler: Sampler
    ) -> SceneTextureLoadPurpose? {
        if let purpose = explicitPurpose(for: sampler.mode) { return purpose }
        if sampler.formatKey?.caseInsensitiveCompare("normalmap") == .orderedSame { return .normal }
        return switch sampler.materialKey?.lowercased() {
        case "albedo": .straightAlbedo
        case "framebuffer": .premultipliedColor
        case "noise": .noise
        case "normal": .normal
        default: nil
        }
    }

    nonisolated static func hasTypedAuxiliaryDefault(_ sampler: Sampler) -> Bool {
        guard case let .asset(path)? = sampler.defaultTexture else { return false }
        return Self.purpose(for: .asset(path), sampler: sampler) != nil
    }

    nonisolated static func hasExplicitNonColorPurpose(_ sampler: Sampler) -> Bool {
        if explicitPurpose(for: sampler.mode) != nil { return true }
        return switch sampler.materialKey?.lowercased() {
        case "noise", "normal": true
        default: false
        }
    }

    nonisolated static func permitsSourceChannelProjection(_ sampler: Sampler) -> Bool {
        guard sampler.mode == .regular,
              !sampler.isHidden,
              sampler.sourceProvenPurpose == nil,
              declaredPurpose(for: sampler) == nil,
              !usesGraphInputMaterialAlias(sampler) else { return false }
        switch sampler.defaultTexture {
        case nil, .internalTarget: return true
        case let .asset(path):
            return SceneStockTextureSemanticRegistry.purpose(for: path) == nil
        }
    }

    nonisolated static func permitsSourceStraightColorProjection(_ sampler: Sampler) -> Bool {
        guard sampler.mode == .regular,
              !sampler.isHidden,
              sampler.sourceProvenPurpose == nil,
              declaredPurpose(for: sampler) == nil,
              !usesGraphInputMaterialAlias(sampler) else { return false }
        switch sampler.defaultTexture {
        case nil: return true
        case .internalTarget: return false
        case let .asset(path):
            guard let registered = SceneStockTextureSemanticRegistry.purpose(for: path)
            else { return true }
            return registered == .straightAlbedo
        }
    }
}

extension SceneResolvedMaterialShaderSchema {
    typealias GraphInputFact = SceneResolvedMaterialGraphInputSourceSlotFact

    /// Canonical classification for explicit aliases, the historical missing
    /// alias, and a strictly bounded dormant authored alias. The dormant case
    /// is source-led: arbitrary editor key/label text never grants execution.
    nonisolated static func graphInputSourceSlotFacts(
        template: Template,
        samplers: [Int: Sampler],
        inputIdentity: Graph.TextureIdentity?,
        sourceColorTransfer: SceneShaderColorTransfer? = nil,
        frontendBindings: [SceneAuthoredShaderProgram.TextureBinding]? = nil
    ) -> [Int: GraphInputFact] {
        guard let inputIdentity,
              exactEffectInput(inputIdentity, template: template) else {
            return [:]
        }
        var facts: [Int: GraphInputFact] = [:]
        let implicit = implicitFramebufferSlots(
            template: template,
            samplers: samplers
        )
        let selfCompositeIngress = exactEffectInput(
            inputIdentity, template: template, requiresEffectContext: true
        )
        for (slot, sampler) in samplers {
            let provenance: GraphInputFact.Provenance?
            if selfCompositeIngress,
               template.textureSlots.indices.contains(slot), template.textureSlots[slot] == nil,
               sameLayerCompositeDefault(sampler.defaultTexture, inputIdentity: inputIdentity) {
                provenance = .sameLayerCompositeDefault
            } else if usesGraphInputMaterialAlias(sampler) {
                provenance = .explicitMaterialAlias
            } else if implicit.contains(slot) {
                provenance = .implicitMissingAlias
            } else if (selfCompositeIngress
                && template.textureSlots.indices.contains(slot)
                && sameLayerCompositeCandidate(
                    template.textureSlots[slot],
                    inputIdentity: inputIdentity
                )) {
                // These effective candidates consume the exact ingress,
                // including a previous effect's output, ahead of idle defaults.
                provenance = .sameLayerCompositeDefault
            } else {
                provenance = nil
            }
            if let provenance {
                let selectionProvenance:
                    SceneResolvedMaterialProgram.TextureSelectionProvenance
                switch provenance {
                case .explicitMaterialAlias:
                    selectionProvenance = sampler.materialKey?.lowercased()
                        == "previous"
                        ? .materialGraphInputAlias : .implicitFramebuffer
                case .implicitMissingAlias:
                    selectionProvenance = .implicitFramebuffer
                case .dormantUnresolvedMaterialAlias:
                    selectionProvenance =
                        .dormantUnresolvedMaterialGraphInput
                case .sameLayerCompositeDefault:
                    // The typed default lowers to this exact graph ingress;
                    // its original RT spelling and variant remain in schema.
                    selectionProvenance = .shaderDefault
                }
                facts[slot] = .init(
                    slot: slot,
                    inputIdentity: inputIdentity,
                    provenance: provenance,
                    selectionProvenance: selectionProvenance
                )
            }
        }
        guard facts.isEmpty,
              template.effectContext != nil,
              let transferSlot = graphInputColorCarrierSlot(sourceColorTransfer),
              samplers.count == 1,
              let sampler = samplers[transferSlot],
              sampler.slot == transferSlot,
              sampler.mode == .regular,
              sampler.isHidden,
              sampler.materialKey?.contains(where: { !$0.isWhitespace }) == true,
              !usesGraphInputMaterialAlias(sampler),
              !hasExplicitNonColorPurpose(sampler),
              sampler.defaultTexture == nil,
              sampler.readinessCombo == nil,
              template.graphRole.bindings.isEmpty,
              template.textureSlots.allSatisfy({ $0 == nil }) else {
            return facts
        }
        if let frontendBindings {
            guard frontendBindings.count == 1,
                  let binding = frontendBindings.first,
                  binding.slot == transferSlot,
                  binding.name == sampler.name else {
                return [:]
            }
        }
        facts[transferSlot] = GraphInputFact(
            slot: transferSlot,
            inputIdentity: inputIdentity,
            provenance: GraphInputFact.Provenance
                .dormantUnresolvedMaterialAlias,
            selectionProvenance:
                SceneResolvedMaterialProgram.TextureSelectionProvenance
                    .dormantUnresolvedMaterialGraphInput
        )
        return facts
    }

    private nonisolated static func graphInputColorCarrierSlot(
        _ transfer: SceneShaderColorTransfer?
    ) -> Int? {
        switch transfer {
        case let .passthrough(slot),
             let .straightAlphaPreserving(slot),
             let .opaqueFromStraightColor(slot):
            slot
        case let .defaultStraightColorBoundary(slots):
            // The default boundary can replace a single proven straight
            // carrier when compiler lowering declines. Preserve the dormant
            // graph-input identity for that carrier so the fallback keeps
            // the same ingress contract as the source classification.
            slots.count == 1 ? slots.first : nil
        case .interpolatedColor, .straightAlpha, .straightAlphaUNorm,
             .independentAlphaSignal, .independentAlphaSignalPreserving,
             .independentAlphaSignalCompositing,
             .independentAlphaSignalUnderlayCompositing,
             .generatedStraightAlpha,
             .premultipliedAlpha,
             .opaque, .sourcedAlpha, .unresolved, nil:
            nil
        }
    }

    nonisolated static func exactEffectInput(
        _ input: Graph.TextureIdentity,
        template: Template,
        requiresEffectContext: Bool = false
    ) -> Bool {
        guard input.name == nil,
              input.kind == .layerSource || input.kind == .effectOutput else {
            return false
        }
        guard let context = template.effectContext else {
            // Existing explicit aliases can name an unscoped graph input.
            // Self references need prepared ownership for an effect output.
            return !requiresEffectContext
                || (input.kind == .layerSource && input.effect == nil)
        }
        guard input == context.input,
              SceneResolvedMaterialEffectIngress.accepts(
                  input,
                  layerID: context.key.layerID,
                  owner: context.key
              ) else { return false }
        return true
    }

    /// True when a sampler's default texture names the consuming layer's own
    /// composite target. The reference must stay same-layer: a cross-layer
    /// composite default has no graph-internal owner and is not a source
    /// fact.
    nonisolated static func sameLayerCompositeDefault(
        _ defaultTexture: DefaultTexture?,
        inputIdentity: Graph.TextureIdentity
    ) -> Bool {
        guard case let .internalTarget(name)? = defaultTexture,
              inputIdentity.name == nil,
              inputIdentity.kind == .layerSource || inputIdentity.kind == .effectOutput,
              case let .namedLayerTarget(reference) = name.admission,
              reference.providerLayerID == inputIdentity.layerID else {
            return false
        }
        return true
    }

    /// True when every authored candidate of the template slot is the
    /// consuming layer's own composite named target (the authored pass
    /// `textures: ["_rt_imageLayerComposite_<self>_{a,b}"]` form). Any other
    /// candidate keeps the slot out of this classification.
    nonisolated static func sameLayerCompositeCandidate(
        _ slot: Template.TextureSlot?,
        inputIdentity: Graph.TextureIdentity
    ) -> Bool {
        guard inputIdentity.name == nil,
              inputIdentity.kind == .layerSource || inputIdentity.kind == .effectOutput,
              let slot, !slot.candidates.isEmpty else {
            return false
        }
        return slot.candidates.allSatisfy { candidate in
            guard case let .provider(.namedLayerTarget(reference)) =
                candidate.reference else {
                return false
            }
            return reference.providerLayerID == inputIdentity.layerID
        }
    }

    /// Projects an already-typed self candidate onto its consuming effect's
    /// exact ingress. Candidate-chain admission remains with the caller.
    nonisolated static func sameLayerCompositeInput(
        _ reference: Template.TextureReference,
        template: Template,
        inputIdentity: Graph.TextureIdentity?,
        consumerLayerID: Int
    ) -> Graph.TextureIdentity? {
        guard let inputIdentity,
              inputIdentity.layerID == consumerLayerID,
              case let .provider(.namedLayerTarget(named)) = reference,
              named.providerLayerID == consumerLayerID,
              exactEffectInput(
                  inputIdentity, template: template, requiresEffectContext: true
              ) else { return nil }
        return inputIdentity
    }

    static func sceneBackgroundDefault(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int
    ) -> Template.TextureReference? {
        guard sampler.slot == slot,
              sampler.readinessCombo == nil,
              template.textureSlots.indices.contains(slot),
              case let .internalTarget(name)? = sampler.defaultTexture,
              case .typedFrameInput = name.admission,
              let layerID = template.effectContext?.key.layerID else { return nil }
        let reference = Template.TextureReference.provider(
            .sceneBackground(consumerLayerID: layerID)
        )
        if let authored = template.textureSlots[slot]?.candidates.last?.reference,
           authored != reference { return nil }
        return Self.purpose(for: reference, sampler: sampler) == nil ? nil : reference
    }

    /// Input representation belongs to the resolved resource, independently
    /// of the author's output color-flow proof. Overrides and data samplers
    /// cannot acquire the scene-background publication's color ABI.
    static func sceneBackgroundColorSlots(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> Set<Int> {
        Set(samplers.compactMap { slot, sampler in
            guard let reference = sceneBackgroundDefault(
                template: template, sampler: sampler, slot: slot
            ), Self.purpose(for: reference, sampler: sampler) == .premultipliedColor
            else { return nil }
            return slot
        })
    }

    static func sceneEnvironmentReference(
        template: Template, sampler: SceneResolvedMaterialShaderSchema.Sampler, slot: Int
    ) -> Template.TextureReference? {
        guard template.textureSlots.indices.contains(slot), sampler.slot == slot,
              Self.purpose(for: .provider(.sceneEnvironment), sampler: sampler) == .premultipliedColor
        else { return nil }
        if let selected = template.textureSlots[slot]?.candidates.last?.reference {
            return selected == .provider(.sceneEnvironment) ? selected : nil
        }
        return sceneEnvironmentDefault(template: template, sampler: sampler, slot: slot)
    }

    static func sceneEnvironmentDefault(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int
    ) -> Template.TextureReference? {
        guard sampler.slot == slot, sampler.readinessCombo == nil,
              template.textureSlots.indices.contains(slot),
              case let .internalTarget(name)? = sampler.defaultTexture,
              case .sceneEnvironment = name.admission else { return nil }
        let reference = Template.TextureReference.provider(.sceneEnvironment)
        if let authored = template.textureSlots[slot]?.candidates.last?.reference,
           authored != reference { return nil }
        return Self.purpose(for: reference, sampler: sampler) == .premultipliedColor ? reference : nil
    }

    /// The schema has already admitted the RT name. Only this projection
    /// binds it to a concrete consuming graph; no frame reparses authored text.
    static func renderTargetDefault(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int,
        inputIdentity: Graph.TextureIdentity?
    ) -> Template.TextureReference? {
        guard sampler.slot == slot, sampler.readinessCombo == nil else { return nil }
        if let environment = sceneEnvironmentDefault(template: template, sampler: sampler, slot: slot) {
            return environment
        }
        if let background = sceneBackgroundDefault(template: template, sampler: sampler, slot: slot) {
            return background
        }
        guard let inputIdentity,
              SceneResolvedMaterialShaderSchema.exactEffectInput(inputIdentity, template: template, requiresEffectContext: true),
              SceneResolvedMaterialShaderSchema.sameLayerCompositeDefault(
                  sampler.defaultTexture, inputIdentity: inputIdentity
              ) else { return nil }
        return .graph(inputIdentity)
    }

    /// Presence combos describe an authored binding, not the resource finally
    /// supplied to an active sampler. A prepared combo-off variant without an
    /// authored candidate or graph-input alias may consume its typed asset
    /// default. Launch admission separately keeps format-combo slots closed.
    static func presenceIndependentDefault(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int
    ) -> Template.TextureReference? {
        guard sampler.slot == slot,
              sampler.readinessCombo != nil,
              !usesGraphInputMaterialAlias(sampler),
              template.textureSlots.indices.contains(slot),
              template.textureSlots[slot] == nil,
              case let .asset(path)? = sampler.defaultTexture
        else {
            return nil
        }
        let reference = Template.TextureReference.asset(path)
        guard Self.purpose(for: reference, sampler: sampler) != nil else { return nil }
        return reference
    }

}
