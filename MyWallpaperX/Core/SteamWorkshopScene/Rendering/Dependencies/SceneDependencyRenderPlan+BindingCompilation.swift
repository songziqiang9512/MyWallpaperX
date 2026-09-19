import Foundation

extension SceneDependencyRenderPlan {
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
        let staticModelCompilation = Self.staticModelNamedTextureBindings(
            descriptor: descriptor,
            layersByID: layersByID,
            order: order,
            routeDisabled: namedProviderRouteDisabled
        )
        var bindings: [Int: Binding] = [:]

        // A hidden provider with authored effects is itself an executable
        // dependency consumer. Walk only the provider closure reachable from
        // visible roots; unrelated hidden effect graphs do not gain a route.
        // Conditional-content consumers (hidden layers that DECLARE
        // dependency references) are also reachable roots: the author
        // declared the dependency, so the provider chain must be ready when
        // the layer is shown.
        var reachableConsumerLayerIDs = visibleLayerIDs
        for reference in references where layersByID[reference.providerLayerID] != nil {
            reachableConsumerLayerIDs.insert(reference.consumerLayerID)
        }
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
        let multiProviderCandidateLayerIDs = Set<Int>(
            descriptor.layers.compactMap { layer in
                guard reachableConsumerLayerIDs.contains(layer.id) else {
                    return nil
                }
                let layerReferences = references.filter {
                    $0.consumerLayerID == layer.id
                }
                return Self.isMultiProviderAggregateCandidate(
                    layer: layer,
                    references: layerReferences
                ) ? layer.id : nil
            }
        )
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
                   Self.activeDependencyProviderLayerIDs(
                       layer: consumer,
                       references: references.filter {
                           $0.consumerLayerID == consumer.id
                       }
                   ) != [binding.providerLayerID] {
                    consumerLayerIDsToRemove.insert(consumerLayerID)
                    continue
                }
                guard let provider = layersByID[binding.providerLayerID],
                      provider.effects.contains(where: { $0.visible != false }),
                      let activeProviderDependencies =
                        Self.activeDependencyProviderLayerIDs(
                            layer: provider,
                            references: references.filter {
                                $0.consumerLayerID == provider.id
                            }
                        ),
                      !activeProviderDependencies.isEmpty else { continue }
                guard activeProviderDependencies.count == 1,
                      let providerBinding = bindings[provider.id],
                      activeProviderDependencies
                        == [providerBinding.providerLayerID] else {
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

        // Build aggregate owners only after the legacy one-provider closure
        // has been pruned. A nested provider is admitted when every one of its
        // active dependencies is represented by either that final legacy
        // binding or an aggregate admitted in an earlier pass. The passes are
        // deterministic and fail closed for unknown providers, cycles, or an
        // unresolved sibling; no aggregate projects a partial provider set.
        var multiProviderAggregates: [Int: MultiProviderAggregate] = [:]
        var pendingAggregateLayerIDs = multiProviderCandidateLayerIDs
        var admittedAggregate = true
        while admittedAggregate && !pendingAggregateLayerIDs.isEmpty {
            admittedAggregate = false
            for layer in descriptor.layers
            where pendingAggregateLayerIDs.contains(layer.id) {
                let layerReferences = references.filter {
                    $0.consumerLayerID == layer.id
                }
                guard let aggregate = Self.multiProviderAggregate(
                    layer: layer,
                    references: layerReferences,
                    allReferences: references,
                    layersByID: layersByID,
                    order: order,
                    visibleLayerIDs: visibleLayerIDs,
                    cyclicLayerIDs: cyclicLayerIDs,
                    legacyBindings: bindings,
                    admittedAggregates: multiProviderAggregates
                ) else { continue }
                multiProviderAggregates[layer.id] = aggregate
                pendingAggregateLayerIDs.remove(layer.id)
                admittedAggregate = true
            }
        }
        // Preserve a diagnostic for a reachable aggregate-shaped consumer
        // that could not acquire a complete nested closure, while keeping
        // successfully admitted aggregates free of a misleading legacy
        // `unsupportedConsumer` issue.
        for layerID in pendingAggregateLayerIDs {
            issues.append(Issue(
                kind: .unsupportedConsumer,
                layerID: layerID,
                providerLayerID: nil
            ))
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

        let staticModelResolution = Self.staticModelBindingsPreservingEffectProviders(
            staticModelCompilation,
            effectBindings: bindings
        )
        issues.append(contentsOf: staticModelResolution.issues)

        self.references = references
        self.namedReferenceConsumerLayerIDs = Set(references.compactMap { reference in
            reachableConsumerLayerIDs.contains(reference.consumerLayerID)
                ? reference.consumerLayerID : nil
        })
        self.executableUtilityConsumerLayerIDs = executableUtilityConsumerLayerIDs
        self.multiProviderCandidateLayerIDs = multiProviderCandidateLayerIDs
        self.multiProviderAggregatesByConsumerLayerID = multiProviderAggregates
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
        }).union(multiProviderAggregates.keys)
        self.bindingsByConsumerLayerID = bindings
        self.staticModelBindingsByConsumerLayerID = staticModelResolution.bindings
        self.requiredProviderLayerIDs = Set(bindings.values.map(\.providerLayerID))
            .union(multiProviderAggregates.values.flatMap { $0.providerLayerIDs })
            .union(staticModelResolution.bindings.values.map(\.providerLayerID))
        self.requiredGraphOutputProviderLayerIDs = Set(bindings.values.compactMap { binding in
            guard let provider = layersByID[binding.providerLayerID],
                  provider.effects.contains(where: { $0.visible != false }) else {
                return nil
            }
            return provider.id
        }).union(multiProviderAggregates.values.flatMap { aggregate in
            aggregate.providerLayerIDs.filter { providerID in
                layersByID[providerID]?.effects.contains(where: { $0.visible != false }) == true
            }
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
        // The current Binding contract has one provider owner. Keep a mixed
        // provider composition out of every legacy recognizer; otherwise a
        // first-provider projection would silently drop authored references.
        guard !Self.isMultiProviderAggregateCandidate(
            layer: layer,
            references: references
        ) else {
            return nil
        }
        let contract: (
            reference: Reference,
            blendMode: Int,
            kind: Binding.Kind,
            requiresResolvedMaterialProgram: Bool
        )?
        if let reference = materialProgramSolidLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID
        ) {
            contract = (reference, 0, .solidLayer, true)
        } else if let reference = singleSlot3SolidLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references
        ) {
            contract = (reference, 0, .solidLayer, false)
        } else if let declaration = supportedImageLayerBlendDeclaration(
            in: visibleEffects
        ), let declaredProvider = layersByID[declaration.providerLayerID],
           declaredProvider.contentKind == "image",
           declaredProvider.puppetMeshPath == nil,
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
        } else if let materialProgramReferences = materialProgramImageLayerReferences(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID
        ), let reference = materialProgramReferences.first {
            // Resource ownership only: the admitted MaterialProgram still
            // proves shader semantics, scalar inputs and output authority.
            contract = (reference, 0, .imageLayerBlend, true)
        } else if let reference = materialProgramGeometryLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID,
            visibleLayerIDs: visibleLayerIDs
        ) {
            contract = (reference, 0, .geometryLayer, true)
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
        guard let providerActiveDependencies =
                activeDependencyProviderLayerIDs(
                    layer: provider,
                    references: SceneDependencyGraphAnalysis.references(
                        in: [provider]
                    )
                ) else {
            issues.append(Issue(
                kind: .dependencyMismatch,
                layerID: layer.id,
                providerLayerID: provider.id
            ))
            return nil
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
                && (
                    provider.visible == false
                    || (
                        contract.requiresResolvedMaterialProgram
                            && provider.visible != false
                            && provider.effects.contains(where: {
                                $0.visible != false
                            })
                            && provider.dependencyLayerIDs.isEmpty
                            && provider.authoredDependencies.isEmpty
                    )
                )
        case .imageLayerBlend:
            provider.contentKind == "image"
                && provider.puppetMeshPath == nil
                && hasNoUtilityLayer(provider)
                && provider.visible == false
                || provider.contentKind == "text"
                    && hasNoUtilityLayer(provider)
                    && provider.childLayerIDs.isEmpty
                    && !provider.effects.contains(where: { $0.visible != false })
                    && provider.dependencyLayerIDs.isEmpty
                    && provider.authoredDependencies.isEmpty
        case .geometryLayer:
            provider.contentKind == "image"
                && provider.puppetMeshPath != nil
                && hasNoUtilityLayer(provider)
                && provider.visible != false
                && visibleLayerIDs.contains(provider.id)
                && provider.childLayerIDs.isEmpty
                && provider.dependencyLayerIDs.isEmpty
                && provider.authoredDependencies.isEmpty
        case .visibleImageGraphOutput:
            provider.contentKind == "image"
                && provider.puppetMeshPath == nil
                && hasNoUtilityLayer(provider)
                && provider.visible != false
                && providerHasVisibleEffects
                && provider.dependencyLayerIDs.isEmpty
        }
        guard providerKindIsSupported,
              (!providerHasVisibleEffects || (
                  (contract.kind == .imageLayerBlend
                      && provider.visible == false)
                    || contract.kind == .geometryLayer
                    || contract.kind == .visibleImageGraphOutput
                    || (contract.kind == .solidLayer
                        && contract.requiresResolvedMaterialProgram)
              )),
              provider.childLayerIDs.isEmpty,
              (providerActiveDependencies.isEmpty || providerHasVisibleEffects),
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
        let programImageReferenceSlots = materialProgramImageLayerReferences(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID
        )?.map(\.slot)
        let referenceSlots: [SceneEffectPassSlot]
        if contract.kind == .resolvedMaterial {
            referenceSlots = references.map(\.slot)
        } else if contract.kind == .imageLayerBlend,
                  contract.requiresResolvedMaterialProgram,
                  let programImageReferenceSlots {
            referenceSlots = programImageReferenceSlots
        } else {
            referenceSlots = [reference.slot]
        }
        if contract.requiresResolvedMaterialProgram {
            let admitted = Set(admittedResolvedMaterialReferences)
            guard referenceSlots.allSatisfy({ slot in
                admitted.contains(.init(
                    consumerLayerID: layer.id,
                    providerLayerID: provider.id,
                    slot: slot,
                    variant: .primary
                ))
            }) else {
                issues.append(Issue(
                    kind: .unsupportedConsumer,
                    layerID: layer.id,
                    providerLayerID: provider.id
                ))
                return nil
            }
        }
        return Binding(
            consumerLayerID: layer.id,
            providerLayerID: provider.id,
            slot: reference.slot,
            referenceSlots: referenceSlots,
            blendMode: contract.blendMode,
            kind: contract.kind,
            requiresForwardCapture: requiresForwardCapture,
            requiresResolvedMaterialProgram:
                contract.requiresResolvedMaterialProgram
        )
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
            && !layer.dependencyLayerIDs.isEmpty
    }

    nonisolated static func supportsStructuralUtilityConsumer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        layer.utilityLayer?.kind == .composition
            && layer.contentKind == "composition"
            && layer.childLayerIDs.isEmpty
            && !layer.dependencyLayerIDs.isEmpty
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
        if materialProgramImageLayerReferences(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID
        ) != nil {
            return true
        }
        if materialProgramGeometryLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID,
            visibleLayerIDs: visibleLayerIDs
        ) != nil {
            return true
        }
        if materialProgramSolidLayerReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            layersByID: layersByID
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

    /// Compiles the candidate into a lossless aggregate admission record.
    /// Every provider and authored slot must be independently safe; any
    /// ambiguity remains rejected instead of silently selecting one provider.
    private nonisolated static func multiProviderAggregate(
        layer: SceneRenderDescriptor.Layer,
        references: [Reference],
        allReferences: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer],
        order: [Int: Int],
        visibleLayerIDs: Set<Int>,
        cyclicLayerIDs: Set<Int>,
        legacyBindings: [Int: Binding],
        admittedAggregates: [Int: MultiProviderAggregate]
    ) -> MultiProviderAggregate? {
        guard isMultiProviderAggregateCandidate(
            layer: layer,
            references: references
        ) else { return nil }
        let activeReferences = references.filter { reference in
            layer.effects.first(where: { $0.id == reference.slot.effectID })?
                .visible != false
        }
        guard let authoredActiveReferences = authoredReferenceOrder(
            for: layer,
            references: activeReferences
        ) else { return nil }
        guard let activeDependencyProviderIDs =
                activeDependencyProviderLayerIDs(
                    layer: layer,
                    references: authoredActiveReferences
                ) else { return nil }
        guard Set(authoredActiveReferences.map(\.slot)).count
                == authoredActiveReferences.count,
              authoredActiveReferences.allSatisfy({ reference in
                  reference.consumerLayerID == layer.id
                      && reference.variant == .primary
                      && layer.dependencyLayerIDs.contains(
                          reference.providerLayerID
                      )
              }),
              authoredActiveReferences.allSatisfy({
                  aggregateReferenceShapeIsStrict(
                      layer: layer,
                      reference: $0
                  )
              }) else { return nil }
        let providerIDs = Set(authoredActiveReferences.map(\.providerLayerID))
        let declaredProviderIDs = Set(
            layer.dependencyLayerIDs.filter { $0 != layer.id }
        )
        // `dependencyLayerIDs` is the authored superset. Inactive effect
        // alternatives may name providers that are not part of this frame's
        // graph; the aggregate itself must carry exactly the active provider
        // vector while the helper above still proves the full declaration.
        guard layer.dependencyLayerIDs.count == declaredProviderIDs.count,
              declaredProviderIDs.allSatisfy({ layersByID[$0] != nil }),
              providerIDs == activeDependencyProviderIDs,
              providerIDs.count > 1,
              !cyclicLayerIDs.contains(layer.id) else { return nil }
        let bindings = authoredActiveReferences.compactMap { reference -> Binding? in
            guard let provider = layersByID[reference.providerLayerID],
                  provider.contentKind == "image",
                  hasNoUtilityLayer(provider),
                  provider.childLayerIDs.isEmpty,
                  !cyclicLayerIDs.contains(provider.id),
                  let providerOrder = order[provider.id],
                  let consumerOrder = order[layer.id],
                  providerOrder != consumerOrder else { return nil }
            let providerIsVisibleGraphOutput = Self
                .isVisibleGraphOutputProvider(
                    provider,
                    visibleLayerIDs: visibleLayerIDs
                )
            let providerIsVisibleGeometryOutput = provider.puppetMeshPath != nil
                && provider.visible != false
                && visibleLayerIDs.contains(provider.id)
                && provider.authoredDependencies.isEmpty
                && provider.dependencyLayerIDs.isEmpty
            guard provider.visible == false
                    || providerIsVisibleGraphOutput
                    || providerIsVisibleGeometryOutput else {
                return nil
            }
            let providerHasVisibleEffects = provider.effects.contains {
                $0.visible != false
            }
            let bindingKind: Binding.Kind = provider.puppetMeshPath == nil
                ? .imageLayerBlend : .geometryLayer
            let requiresForwardCapture = providerOrder > consumerOrder
            // Pre-executing a visible effect graph would consume its one
            // frame ticket before authored order reaches the provider.  The
            // named publication is not a substitute for its main-compositor
            // output, so keep this shape fail-closed until one ticket can own
            // both outputs without double execution.
            guard !(requiresForwardCapture
                && providerHasVisibleEffects
                && provider.visible != false
                && visibleLayerIDs.contains(provider.id)) else { return nil }
            let supportsForwardSourceCapture = requiresForwardCapture
                && provider.effects.isEmpty
                && provider.dependencyLayerIDs.isEmpty
            let supportsForwardGraphExecution = requiresForwardCapture
                && providerHasVisibleEffects
                && providerGraphIsAuthoredOrderIndependent(provider)
            guard !requiresForwardCapture
                    || supportsForwardSourceCapture
                    || supportsForwardGraphExecution,
                  let providerDependencies =
                    activeDependencyProviderLayerIDs(
                        layer: provider,
                        references: allReferences.filter {
                            $0.consumerLayerID == provider.id
                        }
                    ),
                  providerDependenciesAreAdmitted(
                      provider: provider,
                      activeDependencies: providerDependencies,
                      layersByID: layersByID,
                      cyclicLayerIDs: cyclicLayerIDs,
                      legacyBindings: legacyBindings,
                      admittedAggregates: admittedAggregates
                  ) else { return nil }
            return Binding(
                consumerLayerID: layer.id,
                providerLayerID: provider.id,
                slot: reference.slot,
                blendMode: 0,
                kind: bindingKind,
                requiresForwardCapture: requiresForwardCapture,
                requiresResolvedMaterialProgram: true
            )
        }
        guard bindings.count == authoredActiveReferences.count else { return nil }
        return MultiProviderAggregate(
            consumerLayerID: layer.id,
            bindings: bindings,
            authoredSlotOrder: authoredActiveReferences.map(\.slot)
        )
    }

}
