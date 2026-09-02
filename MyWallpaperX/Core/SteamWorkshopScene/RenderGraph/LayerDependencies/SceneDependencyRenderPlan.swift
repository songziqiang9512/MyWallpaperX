import Foundation

nonisolated struct SceneDependencyRenderPlan {
    nonisolated struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }

    nonisolated struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial
            case solidLayer
            case imageLayerBlend
            /// A visible image layer publishes its unified graph-final color
            /// into the same-frame named target consumed by a later
            /// MaterialProgram stage. It remains a normal compositor layer.
            case visibleImageGraphOutput
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind
        /// The exact image provider appears after its consumer in authored
        /// compositor order and must publish in the offscreen prepass. A
        /// static provider captures its source; an effectful provider executes
        /// its already-admitted graph. Neither changes final composition order.
        let requiresForwardCapture: Bool
        /// The binding is resource ownership only. UV transform or additional
        /// graph-internal provenance must be consumed by an admitted
        /// MaterialProgram, never by the legacy direct dependency composite.
        let requiresResolvedMaterialProgram: Bool

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind,
            requiresForwardCapture: Bool = false,
            requiresResolvedMaterialProgram: Bool = false
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
            self.requiresForwardCapture = requiresForwardCapture
            self.requiresResolvedMaterialProgram = requiresResolvedMaterialProgram
        }
    }

    nonisolated enum IssueKind: String {
        case dependencyMismatch
        case missingProvider
        case cyclicDependency
        case unsupportedConsumer
        case unsupportedVariant
        case forwardUtilityProvider
        case namedProviderRouteDisabled
    }

    nonisolated struct Issue: Hashable {
        let kind: IssueKind
        let layerID: Int
        let providerLayerID: Int?
    }

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>
    let executableUtilityConsumerLayerIDs: Set<Int>
    let requiredEffectConsumerLayerIDs: Set<Int>
    let bindingsByConsumerLayerID: [Int: Binding]
    let requiredProviderLayerIDs: Set<Int>
    let requiredGraphOutputProviderLayerIDs: Set<Int>
    let staticLayerSourcePassthroughBlockedLayerIDs: Set<Int>
    let cyclicLayerIDs: Set<Int>
    let issues: [Issue]

    nonisolated func blocksStaticLayerSourcePassthrough(for layerID: Int) -> Bool {
        staticLayerSourcePassthroughBlockedLayerIDs.contains(layerID)
    }

    /// Restricts prepared graph work to roots that are visible in the current
    /// committed frame plus the effectful provider closure they actually use.
    /// Static image providers are captured through this plan's named target
    /// path and therefore never acquire a graph execution identity here.
    nonisolated func resolvedMaterialExecutionLayerIDs(
        visibleRootLayerIDs: Set<Int>,
        availableExecutionLayerIDs: Set<Int>
    ) -> Set<Int> {
        var reachable = visibleRootLayerIDs.intersection(
            availableExecutionLayerIDs
        )
        var changed = true
        while changed {
            changed = false
            for binding in bindingsByConsumerLayerID.values
            where reachable.contains(binding.consumerLayerID)
                && requiredGraphOutputProviderLayerIDs.contains(
                    binding.providerLayerID
                )
                && availableExecutionLayerIDs.contains(
                    binding.providerLayerID
                )
            {
                changed = reachable.insert(binding.providerLayerID).inserted
                    || changed
            }
        }
        return reachable
    }

    nonisolated init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = [],
        verifiedXRayStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey> = [],
        admittedResolvedMaterialReferences: Set<Reference> = []
    ) {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let order = Dictionary(uniqueKeysWithValues: descriptor.renderOrderLayerIDs.enumerated().map {
            ($0.element, $0.offset)
        })
        let productReferences = SceneDependencyGraphAnalysis.references(
            in: descriptor.layers
        )
        let potentialReferences = Set(
            SceneDependencyGraphAnalysis
                .potentialOptionalNamedFallbackReferences(in: descriptor.layers)
        )
        let admittedPotentialReferences = potentialReferences.intersection(
            admittedResolvedMaterialReferences
        )
        let references = productReferences + admittedPotentialReferences.filter {
            !productReferences.contains($0)
        }
        let dependencyEdges = Self.productDependencyEdges(
            layers: descriptor.layers,
            references: references,
            productReferences: productReferences,
            potentialReferences: potentialReferences,
            admittedPotentialReferences: admittedPotentialReferences
        )
        let availableLayerIDs = Set(layersByID.keys)
        let xRayExemptConsumerLayerIDs = Set(visibleLayerIDs.filter { layerID in
            guard let layer = layersByID[layerID] else { return false }
            return SceneDependencyGraphAnalysis.xRayEffectLocalProviderContract(
                for: layer,
                verifiedStageKeys: verifiedXRayStageKeys,
                availableLayerIDs: availableLayerIDs
            ) != nil
        })
        var passthroughBlockedLayerIDs: Set<Int> = []
        let cyclicLayerIDs = SceneDependencyGraphAnalysis.cyclicLayerIDs(
            edges: dependencyEdges
        )
        let namedProviderRouteDisabled = ProcessInfo.processInfo.environment[
            "MWX_SCENE_NAMED_PROVIDER_ROUTE"
        ] == "disable-generic"
        var issues = SceneDependencyGraphAnalysis.referenceIssues(
            references: references,
            layersByID: layersByID
        )
        var bindings: [Int: Binding] = [:]

        // A hidden provider with authored effects is itself an executable
        // dependency consumer. Walk only the provider closure reachable from
        // visible roots; unrelated hidden effect graphs do not gain a route.
        var reachableConsumerLayerIDs = visibleLayerIDs
        var changed = true
        while changed {
            changed = false
            for reference in references
            where reachableConsumerLayerIDs.contains(reference.consumerLayerID) {
                guard let provider = layersByID[reference.providerLayerID],
                      provider.effects.contains(where: { $0.visible != false }),
                      reachableConsumerLayerIDs.insert(provider.id).inserted else {
                    continue
                }
                changed = true
            }
        }
        let visibleGraphOutputReferences: Set<Reference> = Set(
            descriptor.layers.compactMap { layer in
                guard reachableConsumerLayerIDs.contains(layer.id) else {
                    return nil
                }
                return Self.visibleImageGraphOutputReference(
                    layer: layer,
                    visibleEffects: layer.effects.filter { $0.visible != false },
                    references: references.filter {
                        $0.consumerLayerID == layer.id
                    },
                    layersByID: layersByID,
                    visibleLayerIDs: visibleLayerIDs
                )
            }
        )
        let passthroughSafeGraphOutputProviderLayerIDs = Set(
            visibleGraphOutputReferences.map(\.providerLayerID)
        ).filter { providerLayerID in
            let incoming = references.filter {
                reachableConsumerLayerIDs.contains($0.consumerLayerID)
                    && $0.providerLayerID == providerLayerID
            }
            return !incoming.isEmpty && incoming.allSatisfy {
                visibleGraphOutputReferences.contains($0)
            }
        }
        for consumerLayerID in reachableConsumerLayerIDs {
            for providerLayerID in dependencyEdges[consumerLayerID] ?? [] {
                if layersByID[providerLayerID] != nil,
                   !passthroughSafeGraphOutputProviderLayerIDs.contains(
                       providerLayerID
                   ) {
                    passthroughBlockedLayerIDs.insert(providerLayerID)
                }
            }
        }

        for layer in descriptor.layers where reachableConsumerLayerIDs.contains(layer.id) {
            let layerReferences = references.filter { $0.consumerLayerID == layer.id }
            guard !layerReferences.isEmpty else { continue }
            guard let binding = Self.executableBinding(
                for: layer,
                references: layerReferences,
                layersByID: layersByID,
                order: order,
                visibleLayerIDs: visibleLayerIDs,
                cyclicLayerIDs: cyclicLayerIDs,
                executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
                admittedResolvedMaterialReferences:
                    admittedResolvedMaterialReferences,
                namedProviderRouteDisabled: namedProviderRouteDisabled,
                issues: &issues
            ) else {
                continue
            }
            bindings[layer.id] = binding
            if !layer.dependencyLayerIDs.contains(binding.providerLayerID) {
                issues.append(Issue(
                    kind: .dependencyMismatch,
                    layerID: layer.id,
                    providerLayerID: binding.providerLayerID
                ))
            }
        }

        // An effectful provider may itself depend on one earlier provider, but
        // that edge must have survived the exact same binding compiler. Remove
        // any downstream binding whose provider graph is not closed by the
        // shared dependency plan; never fall back to publishing its base image.
        var removedBinding = true
        while removedBinding {
            removedBinding = false
            var consumerLayerIDsToRemove: Set<Int> = []
            for (consumerLayerID, binding) in bindings {
                if let consumer = layersByID[consumerLayerID],
                   consumer.effects.contains(where: { $0.visible != false }),
                   consumer.visible == false,
                   consumer.dependencyLayerIDs != [binding.providerLayerID] {
                    consumerLayerIDsToRemove.insert(consumerLayerID)
                    continue
                }
                guard let provider = layersByID[binding.providerLayerID],
                      provider.effects.contains(where: { $0.visible != false }),
                      !provider.dependencyLayerIDs.isEmpty else { continue }
                guard provider.dependencyLayerIDs.count == 1,
                      let providerBinding = bindings[provider.id],
                      providerBinding.providerLayerID
                        == provider.dependencyLayerIDs.first else {
                    consumerLayerIDsToRemove.insert(consumerLayerID)
                    issues.append(Issue(
                        kind: .dependencyMismatch,
                        layerID: consumerLayerID,
                        providerLayerID: binding.providerLayerID
                    ))
                    continue
                }
            }
            for consumerLayerID in consumerLayerIDsToRemove {
                bindings.removeValue(forKey: consumerLayerID)
            }
            removedBinding = !consumerLayerIDsToRemove.isEmpty
        }

        // An unbound named-input consumer owns no product dependency result.
        // If its unsupported effect chain is omitted, drawing the already
        // validated base source is the smallest previous-current fallback.
        // Executable consumers remain blocked until their binding is consumed,
        // and every unsafe provider remains blocked above so a base image can
        // never masquerade as a named graph publication downstream.
        passthroughBlockedLayerIDs.formUnion(
            bindings.keys.filter {
                !xRayExemptConsumerLayerIDs.contains($0)
            }
        )

        self.references = references
        self.namedReferenceConsumerLayerIDs = Set(references.compactMap { reference in
            reachableConsumerLayerIDs.contains(reference.consumerLayerID)
                ? reference.consumerLayerID : nil
        })
        self.executableUtilityConsumerLayerIDs = executableUtilityConsumerLayerIDs
        self.requiredEffectConsumerLayerIDs = Set(descriptor.layers.compactMap { layer in
            let layerReferences = references.filter { $0.consumerLayerID == layer.id }
            let routeDisabledStructuralUtility = namedProviderRouteDisabled
                && Self.supportsStructuralUtilityConsumer(layer)
                && (
                    Self.resolvedMaterialReference(
                        in: layer.effects.filter { $0.visible != false },
                        references: layerReferences
                    ) != nil
                    || Self.singleSlot3SolidLayerReference(
                        layer: layer,
                        visibleEffects: layer.effects.filter { $0.visible != false },
                        references: layerReferences
                    ) != nil
                )
            guard reachableConsumerLayerIDs.contains(layer.id),
                  Self.supportsEffectConsumer(
                      layer,
                      executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
                  ) || routeDisabledStructuralUtility,
                  !layerReferences.isEmpty,
                  Self.requiresNamedEffect(
                      layer,
                      references: layerReferences,
                      layersByID: layersByID,
                      visibleLayerIDs: visibleLayerIDs
                  ) else {
                return nil
            }
            return layer.id
        })
        self.bindingsByConsumerLayerID = bindings
        self.requiredProviderLayerIDs = Set(bindings.values.map(\.providerLayerID))
        self.requiredGraphOutputProviderLayerIDs = Set(bindings.values.compactMap { binding in
            guard let provider = layersByID[binding.providerLayerID],
                  provider.effects.contains(where: { $0.visible != false }) else {
                return nil
            }
            return provider.id
        })
        self.staticLayerSourcePassthroughBlockedLayerIDs = passthroughBlockedLayerIDs
        self.cyclicLayerIDs = cyclicLayerIDs
        self.issues = Array(Set(issues)).sorted {
            ($0.layerID, $0.kind.rawValue, $0.providerLayerID ?? -1)
                < ($1.layerID, $1.kind.rawValue, $1.providerLayerID ?? -1)
        }
    }

    nonisolated static func executableBinding(
        for layer: SceneRenderDescriptor.Layer,
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer],
        order: [Int: Int],
        visibleLayerIDs: Set<Int>,
        cyclicLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int>,
        admittedResolvedMaterialReferences: Set<Reference>,
        namedProviderRouteDisabled: Bool,
        issues: inout [Issue]
    ) -> Binding? {
        let visibleEffects = layer.effects.filter { $0.visible != false }
        let contract: (
            reference: Reference,
            blendMode: Int,
            kind: Binding.Kind,
            requiresResolvedMaterialProgram: Bool
        )?
        if let reference = singleSlot3SolidLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references
        ) {
            contract = (reference, 0, .solidLayer, false)
        } else if let declaration = supportedImageLayerBlendDeclaration(
            in: visibleEffects
        ), let declaredProvider = layersByID[declaration.providerLayerID],
           declaredProvider.contentKind == "image",
           hasNoUtilityLayer(declaredProvider) {
            let matchingReferences = references.filter { reference in
                reference.slot.effectID == declaration.effectID
                    && reference.slot.passIndex == declaration.passIndex
                    && reference.slot.slotIndex == declaration.slotIndex
                    && reference.providerLayerID == declaration.providerLayerID
            }
            let graphInternalReferences = references.filter {
                !matchingReferences.contains($0)
            }
            guard matchingReferences.count == 1,
                  let reference = matchingReferences.first,
                  graphInternalReferences.allSatisfy({ candidate in
                      candidate.consumerLayerID == layer.id
                          && candidate.providerLayerID == layer.id
                  }) else {
                issues.append(Issue(
                    kind: .unsupportedConsumer,
                    layerID: layer.id,
                    providerLayerID: nil
                ))
                return nil
            }
            contract = (
                reference,
                declaration.blendMode,
                .imageLayerBlend,
                declaration.requiresResolvedMaterialProgram
                    || !graphInternalReferences.isEmpty
            )
        } else if let reference = materialProgramImageLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID
        ) {
            // Resource ownership only: the admitted MaterialProgram still
            // proves shader semantics, scalar inputs and output authority.
            contract = (reference, 0, .imageLayerBlend, true)
        } else if let reference = visibleImageGraphOutputReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID,
            visibleLayerIDs: visibleLayerIDs
        ) {
            contract = (reference, 0, .visibleImageGraphOutput, false)
        } else if let reference = resolvedMaterialReference(
            in: visibleEffects,
            references: references
        ) {
            contract = (reference, 0, .resolvedMaterial, false)
        } else {
            contract = nil
        }
        guard let contract else {
            issues.append(Issue(kind: .unsupportedConsumer, layerID: layer.id, providerLayerID: nil))
            return nil
        }
        if contract.requiresResolvedMaterialProgram,
           !admittedResolvedMaterialReferences.contains(contract.reference) {
            issues.append(Issue(
                kind: .unsupportedConsumer,
                layerID: layer.id,
                providerLayerID: contract.reference.providerLayerID
            ))
            return nil
        }
        let supportsConsumer = supportsEffectConsumer(
            layer,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
        ) || (
            namedProviderRouteDisabled
                && (contract.kind == .resolvedMaterial || contract.kind == .solidLayer)
                && supportsStructuralUtilityConsumer(layer)
        )
        guard supportsConsumer else {
            issues.append(Issue(kind: .unsupportedConsumer, layerID: layer.id, providerLayerID: nil))
            return nil
        }
        let reference = contract.reference
        if case .some = layer.utilityLayer,
           layer.dependencyLayerIDs != [reference.providerLayerID] {
            issues.append(Issue(
                kind: .dependencyMismatch,
                layerID: layer.id,
                providerLayerID: reference.providerLayerID
            ))
            return nil
        }
        guard reference.variant == .primary else {
            issues.append(Issue(
                kind: .unsupportedVariant,
                layerID: layer.id,
                providerLayerID: reference.providerLayerID
            ))
            return nil
        }
        guard let provider = layersByID[reference.providerLayerID] else { return nil }
        guard !cyclicLayerIDs.contains(layer.id), !cyclicLayerIDs.contains(provider.id) else {
            issues.append(Issue(
                kind: .cyclicDependency,
                layerID: layer.id,
                providerLayerID: provider.id
            ))
            return nil
        }
        let providerHasVisibleEffects = provider.effects.contains {
            $0.visible != false
        }
        guard let providerOrder = order[provider.id],
              let consumerOrder = order[layer.id],
              providerOrder != consumerOrder else {
            issues.append(Issue(
                kind: .forwardUtilityProvider,
                layerID: layer.id,
                providerLayerID: provider.id
            ))
            return nil
        }
        let requiresForwardCapture = providerOrder > consumerOrder
        let supportsForwardSourceCapture = requiresForwardCapture
            && contract.kind == .imageLayerBlend
            && provider.effects.isEmpty
            && provider.dependencyLayerIDs.isEmpty
        let supportsForwardGraphExecution = requiresForwardCapture
            && contract.kind == .imageLayerBlend
            && providerHasVisibleEffects
            && providerGraphIsAuthoredOrderIndependent(provider)
        let supportsForwardCapture = supportsForwardSourceCapture
            || supportsForwardGraphExecution
        let providerKindIsSupported = switch contract.kind {
        case .resolvedMaterial:
            provider.utilityLayer?.kind == .composition
        case .solidLayer:
            provider.contentKind == "solid"
                && hasNoUtilityLayer(provider)
                && provider.visible == false
        case .imageLayerBlend:
            provider.contentKind == "image"
                && hasNoUtilityLayer(provider)
                && provider.visible == false
        case .visibleImageGraphOutput:
            provider.contentKind == "image"
                && hasNoUtilityLayer(provider)
                && provider.visible != false
                && providerHasVisibleEffects
                && provider.dependencyLayerIDs.isEmpty
        }
        guard providerKindIsSupported,
              (!providerHasVisibleEffects || (
                  (contract.kind == .imageLayerBlend
                      && provider.visible == false)
                    || contract.kind == .visibleImageGraphOutput
              )),
              provider.childLayerIDs.isEmpty,
              (provider.dependencyLayerIDs.isEmpty || providerHasVisibleEffects),
              providerOrder < consumerOrder || supportsForwardCapture else {
            issues.append(Issue(
                kind: .forwardUtilityProvider,
                layerID: layer.id,
                providerLayerID: provider.id
            ))
            return nil
        }
        // The legacy switch owns only the older named-provider route. A
        // visible graph-output binding is part of the exact generic-only
        // shader profile and must not silently restore the X-Ray incumbent.
        if namedProviderRouteDisabled,
           contract.kind != .visibleImageGraphOutput {
            issues.append(Issue(
                kind: .namedProviderRouteDisabled,
                layerID: layer.id,
                providerLayerID: provider.id
            ))
            return nil
        }
        return Binding(
            consumerLayerID: layer.id,
            providerLayerID: provider.id,
            slot: reference.slot,
            referenceSlots: contract.kind == .resolvedMaterial
                ? references.map(\.slot) : [reference.slot],
            blendMode: contract.blendMode,
            kind: contract.kind,
            requiresForwardCapture: requiresForwardCapture,
            requiresResolvedMaterialProgram:
                contract.requiresResolvedMaterialProgram
        )
    }

    /// A forward graph runs before any authored compositor layer. It may use
    /// its own layer source, static assets, frame inputs and one exact primary
    /// named input that the same dependency plan validates and schedules
    /// first. The main target, secondary targets and undeclared named inputs
    /// remain authored-order-dependent and are rejected.
    private nonisolated static func providerGraphIsAuthoredOrderIndependent(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        let references = SceneDependencyGraphAnalysis.references(in: [layer])
        if layer.dependencyLayerIDs.isEmpty {
            guard references.isEmpty else { return false }
        } else {
            guard layer.dependencyLayerIDs.count == 1,
                  let dependencyLayerID = layer.dependencyLayerIDs.first,
                  references.count == 1,
                  let reference = references.first,
                  reference.consumerLayerID == layer.id,
                  reference.providerLayerID == dependencyLayerID,
                  reference.variant == .primary else { return false }
        }
        return layer.effects.filter { $0.visible != false }.allSatisfy { effect in
            effect.passes.allSatisfy { pass in
                let authoredPaths = pass.texturePaths
                    + pass.textureSlots.compactMap { $0 }
                return authoredPaths.allSatisfy { path in
                    guard path.caseInsensitiveCompare("_rt_FullFrameBuffer")
                        != .orderedSame else { return false }
                    guard let named = SceneNamedTextureReference.parse(path)
                    else { return true }
                    return layer.dependencyLayerIDs == [named.providerLayerID]
                        && named.variant == .primary
                }
            }
        }
    }

    private nonisolated static func supportsEffectConsumer(
        _ layer: SceneRenderDescriptor.Layer,
        executableUtilityConsumerLayerIDs: Set<Int>
    ) -> Bool {
        guard let utility = layer.utilityLayer else { return true }
        return executableUtilityConsumerLayerIDs.contains(layer.id)
            && utility.kind == .composition
            && layer.contentKind == "composition"
            && layer.childLayerIDs.isEmpty
            && layer.dependencyLayerIDs.count == 1
    }

    private nonisolated static func supportsStructuralUtilityConsumer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        layer.utilityLayer?.kind == .composition
            && layer.contentKind == "composition"
            && layer.childLayerIDs.isEmpty
            && layer.dependencyLayerIDs.count == 1
    }

    private nonisolated static func requiresNamedEffect(
        _ layer: SceneRenderDescriptor.Layer,
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer],
        visibleLayerIDs: Set<Int>
    ) -> Bool {
        let visibleEffects = layer.effects.filter { $0.visible != false }
        if resolvedMaterialReference(
            in: visibleEffects,
            references: references
        ) != nil {
            return true
        }
        if visibleImageGraphOutputReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID,
            visibleLayerIDs: visibleLayerIDs
        ) != nil {
            return true
        }
        if supportedImageLayerBlendDeclaration(in: visibleEffects) != nil {
            return true
        }
        return singleSlot3SolidLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references
        ) != nil
    }

    private nonisolated static func resolvedMaterialReference(
        in visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference]
    ) -> Reference? {
        guard let reference = references.first,
              reference.slot.slotIndex == 1,
              references.allSatisfy({ candidate in
                  candidate.consumerLayerID == reference.consumerLayerID
                      && candidate.providerLayerID == reference.providerLayerID
                      && candidate.variant == reference.variant
                      && candidate.slot.slotIndex == 1
              }) else { return nil }

        for candidate in references {
            let effects = visibleEffects.filter { $0.id == candidate.slot.effectID }
            guard effects.count == 1, let effect = effects.first else { return nil }
            let passes = effect.passes.filter {
                $0.passIndex == candidate.slot.passIndex
            }
            guard passes.count == 1, let pass = passes.first else { return nil }
            let userTextureAllowsNamedFallback =
                SceneNamedTextureDependencyReferenceAnalysis
                    .userTextureAllowsNamedFallback(
                        slotIndex: candidate.slot.slotIndex,
                        pass: pass
                    )
            let hasOnlyNeutralAuthoredConstants = pass.constantShaderValues.values
                .allSatisfy { value in
                    guard let components = value.components,
                          !components.isEmpty else { return false }
                    return components.allSatisfy { $0 == 1 }
                }
            guard pass.textureSlots.indices.contains(candidate.slot.slotIndex),
                  let path = pass.textureSlots[candidate.slot.slotIndex],
                  SceneNamedTextureReference.parse(path) == .init(
                      providerLayerID: candidate.providerLayerID,
                      variant: candidate.variant
                  ),
                  userTextureAllowsNamedFallback,
                  hasOnlyNeutralAuthoredConstants else {
                return nil
            }
        }
        return reference
    }

    /// Bounded structural carrier for one hidden static solid publication.
    /// Effect path, combo values and authored constants belong to shader and
    /// MaterialProgram admission; they never select this dependency owner.
    private nonisolated static func singleSlot3SolidLayerReference(
        layer: SceneRenderDescriptor.Layer,
        visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference]
    ) -> Reference? {
        guard supportsStructuralUtilityConsumer(layer),
              visibleEffects.count == 1,
              let effect = visibleEffects.first,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.textureSlots.count == 4,
              pass.textureSlots[0...2].allSatisfy({ $0 == nil }),
              let path = pass.textureSlots[3],
              pass.texturePaths == [path],
              (!pass.userTextureInputs.indices.contains(3)
                  || pass.userTextureInputs[3] == nil),
              references.count == 1,
              let reference = references.first,
              reference.slot.effectID == effect.id,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 3,
              layer.dependencyLayerIDs == [reference.providerLayerID] else {
            return nil
        }
        return reference
    }

}
