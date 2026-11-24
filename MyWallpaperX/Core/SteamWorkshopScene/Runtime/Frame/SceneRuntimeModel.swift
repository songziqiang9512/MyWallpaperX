import Foundation

struct SceneRuntimeModel {
    let project: SceneProject
    let sceneDocument: SceneDocument
    let assetCatalog: SceneAssetCatalog
    let resourceView: SceneResourceView
    let authoredRenderDescriptor: SceneRenderDescriptor
    let renderDescriptor: SceneRenderDescriptor
    let propertyVectorProjection: SceneScriptVectorCandidateCatalog
    let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
    let runtimeInput: SceneRuntimeInput
#if DEBUG
    var resourceReferences: SceneResourceReferenceIndex? = nil
    var resourceIndex: SceneResourceIndex? = nil
    var capabilityProfile: SceneCapabilityProfile? = nil
#endif

    /// Compatibility inputs remain two independent provenance-bearing facts.
    /// No unverified rule is applied merely by exposing this context.
    nonisolated var compatibilityContext: SceneCompatibilityContext {
        SceneCompatibilityContext(
            projectVersion: .init(
                value: project.declaredVersion,
                sourceKind: .projectJSON,
                sourceRelativePath: "project.json",
                fieldName: "version"
            ),
            sceneVersion: .init(
                value: sceneDocument.declaredVersion,
                sourceKind: .sceneEntry,
                sourceRelativePath: project.entryPath,
                fieldName: "version"
            )
        )
    }
}

struct SceneRuntimeModelBuilder {
    enum BuildError: LocalizedError {
        case missingProject
        case missingSceneDocument(String?)
        case missingAssetCatalog
#if DEBUG
        case missingResourceReferences
#endif
        case missingRenderDescriptor

        var errorDescription: String? {
            switch self {
            case .missingProject:
                return String(localized: "Couldn’t build the Scene runtime: the project wasn’t parsed.")
            case let .missingSceneDocument(detail):
                if let detail, !detail.isEmpty {
                    return String(localized: "Couldn’t build the Scene runtime: \(detail)")
                }
                return String(localized: "Couldn’t build the Scene runtime: scene.json wasn’t parsed.")
            case .missingAssetCatalog:
                return String(localized: "Couldn’t build the Scene runtime: the asset catalog wasn’t parsed.")
#if DEBUG
            case .missingResourceReferences:
                return String(localized: "Couldn’t build the Scene runtime: the resource reference index wasn’t created.")
#endif
            case .missingRenderDescriptor:
                return String(localized: "Couldn’t build the Scene runtime: the renderer input descriptor wasn’t created.")
            }
        }
    }

    func build(
        rootURL: URL,
        source: ScenePlaybackSource? = nil,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        usesHDRWorkingDomain: Bool = true,
        appliesBloom: Bool = true,
        checkCancellation: (() throws -> Void)? = nil,
        preparedStaticModel: (String, SceneMdlStaticModel.PreparedSource) -> Void = { _, _ in },
        preparedParticleDefinition: (String, SceneParticleAssetGraphLoader.PreparedDefinition) -> Void = { _, _ in }
    ) throws -> SceneRuntimeModel {
        let sourceFacts = try SceneRuntimeSourceFactsBuilder().build(
            rootURL: rootURL,
            source: source,
            propertyOverrides: propertyOverrides,
            usesHDRWorkingDomain: usesHDRWorkingDomain,
            appliesBloom: appliesBloom,
            checkCancellation: checkCancellation,
            preparedStaticModel: preparedStaticModel,
            preparedParticleDefinition: preparedParticleDefinition
        )
        try checkCancellation?()
        guard let project = sourceFacts.project else {
            throw BuildError.missingProject
        }
        guard let sceneDocument = sourceFacts.sceneDocument else {
            throw BuildError.missingSceneDocument(
                sourceFacts.sceneDocumentLoadErrorDescription
            )
        }
        guard let assetCatalog = sourceFacts.assetCatalog else {
            throw BuildError.missingAssetCatalog
        }
#if DEBUG
        guard let resourceReferences = sourceFacts.resourceReferences else {
            throw BuildError.missingResourceReferences
        }
        let capabilityProfile = sourceFacts.capabilityProfile
#endif
        guard let renderDescriptor = sourceFacts.renderDescriptor else {
            throw BuildError.missingRenderDescriptor
        }
        let timelineTargets = Set(
            SceneTimelineTargetCompiler.compile(descriptor: renderDescriptor)
                .bindings.map(\.target)
        )
        let structuralPropertyVectorProjection = SceneScriptVectorProgram.project(
            descriptor: renderDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            timelineTargets: timelineTargets
        )
        let displayProjectedDescriptor = SceneIdentityDisplayScriptProjection.apply(
            to: renderDescriptor,
            sourceEvidence: sceneDocument.scriptSourceEvidence
        )
        let mediaProjectedDescriptor = SceneInitialMediaEffectVisibilityProjection.apply(
            to: displayProjectedDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            sourceEvidence: sceneDocument.scriptSourceEvidence
        )
        let projectedScalarTargets = SceneScriptScalarProgram.projectedTargets(
            descriptor: renderDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            timelineTargets: timelineTargets
        )
        let scalarProjectedDescriptor = SceneScriptScalarDisplayProjection.apply(
            admittedTargets: projectedScalarTargets,
            to: mediaProjectedDescriptor
        )
        let alphaClaimedTargets = projectedScalarTargets.union(timelineTargets)
        let fallbackProjectedDescriptor = SceneScriptScalarDisplayProjection
            .applyUnclaimedFallback(
                claimedTargets: alphaClaimedTargets,
                to: scalarProjectedDescriptor
            )
        let particleProjectedDescriptor = SceneScriptParticleProjection.apply(
            admittedTargets: projectedScalarTargets.union(structuralPropertyVectorProjection.targets),
            to: fallbackProjectedDescriptor
        )
        // A failed optional scale producer keeps the resolved authored current.
        // Hiding the whole layer turns a local script/property failure into a
        // composition regression and violates the shared fail-soft boundary.
        let runtimeDescriptor = particleProjectedDescriptor
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: runtimeDescriptor
        )
        let typedVisibilityOwnerLayerIDs = Set(
            structuralPropertyVectorProjection.uniqueCandidates.compactMap {
                candidate -> Int? in
                guard case let .layer(layerID, .visibility) =
                        candidate.definition.target else { return nil }
                return layerID
            }
        )
        let propertyDefinitionsByKey = Dictionary(
            grouping: project.userProperties.definitions, by: \.key
        )
        let propertyVisibilityTargets = Set(
            sceneDocument.userPropertyResolution.bindingReport.bindings.compactMap {
                binding -> SceneDynamicTarget? in
                guard case .layerVisibility = binding.target else { return nil }
                let definitions = propertyDefinitionsByKey[binding.reference.key] ?? []
                let kind = definitions.count == 1 ? definitions[0].kind : nil
                guard let mapped = ScenePropertyBindingCompiler.map(binding, propertyKind: kind),
                      mapped.propertyKind == kind else { return nil }
                return mapped.target
            }
        )
        let visibilityPreparationTargets = SceneDynamicLayerVisibilityRouteAdmission.targets(
            in: runtimeDescriptor,
            candidates: propertyVisibilityTargets.union(structuralPropertyVectorProjection.targets),
            hasScriptLayerAccess: !sceneDocument.scriptBindings.isEmpty
        )
        var colorConsumerLayerIDs = visibleLayerIDs.union(typedVisibilityOwnerLayerIDs)
        if !visibilityPreparationTargets.isEmpty {
            // Preparation demand is not a current publication. Child false and
            // alpha display authority still resolve through the shared snapshot.
            let visibilityPreparationSnapshot = SceneDynamicSnapshotResolver().resolve(
                frameIndex: 0, generation: 0,
                definitions: visibilityPreparationTargets.map {
                    .init(target: $0, valueType: .bool, authoredValue: .bool(true))
                }
            ).snapshot
            colorConsumerLayerIDs.formUnion(SceneLayerVisibility.visibleLayerIDs(
                in: runtimeDescriptor, snapshot: visibilityPreparationSnapshot
            ))
        }
        let hasStaticModelColorConsumer = runtimeDescriptor.layers.contains {
            $0.staticModelPath != nil && colorConsumerLayerIDs.contains($0.id)
        }
        let sceneScriptColorConsumerLayerIDs: Set<Int> = Set(
            runtimeDescriptor.layers.compactMap { layer in
                let hasVolumetricConeConsumer = layer.spotLight?.castsVolumetrics == true
                    && layer.spotLight?.isSolid == true
                let hasConsumer = layer.supportsDirectLayerColorConsumer
                    || layer.staticModelPath != nil
                    || hasVolumetricConeConsumer
                    || (layer.contentKind == "text"
                        && layer.text != nil
                        && layer.textStyle != nil)
                    || (hasStaticModelColorConsumer
                        && (layer.spotLight != nil
                            || layer.directionalLight != nil
                            || layer.tubeLight != nil))
                guard hasConsumer,
                      colorConsumerLayerIDs.contains(layer.id)
                        || hasVolumetricConeConsumer
                else { return nil }
                return layer.id
            }
        )
        let rawPropertyVectorProjection = SceneScriptVectorProgram.project(
            descriptor: renderDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            timelineTargets: timelineTargets,
            admittedLayerColorConsumerIDs: sceneScriptColorConsumerLayerIDs,
            shaderContracts: assetCatalog.shaderContracts,
            // D1 seed authority: the projection guard reads the authored
            // descriptor, while each effect-visibility definition's seed
            // reads the load-prepared state so the frame snapshot starts at
            // the matcher-prepared visibility (hidden), not the binding
            // seed.
            preparedDescriptor: runtimeDescriptor
        )
        // Validate the small proposed material producer set before replacing any builtin
        // writers. Rejected source lowering must retain the complete old route.
        let proposedMaterialProperties = SceneMaterialPropertyBindingCompiler.provenPropertyBindings(
            rawPropertyVectorProjection.materialBindings, descriptor: renderDescriptor,
            materialInstancesByLayerID: sceneDocument.materialInstancesByLayerID
        )
        let proposedMaterialPropertyCompilation = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: proposedMaterialProperties, diagnostics: []),
            catalog: project.userProperties
        )
        let namedMaterialLayerIDs = Set((SceneNamedTextureDependencyReferenceAnalysis.references(
            in: runtimeDescriptor.layers, includingInactiveEffects: true
        ) + SceneNamedTextureDependencyReferenceAnalysis.potentialNamedReferences(
            in: runtimeDescriptor.layers
        )).flatMap { [$0.consumerLayerID, $0.providerLayerID] })
        let admittedMaterials = SceneBaseMaterialProviderBindingCompiler.admittedSourceMaterials(
            rawPropertyVectorProjection.materialBindings, descriptor: runtimeDescriptor,
            materialInstancesByLayerID: sceneDocument.materialInstancesByLayerID,
            propertyCompilation: proposedMaterialPropertyCompilation, namedLayerIDs: namedMaterialLayerIDs
        )
        let propertyVectorProjection = SceneScriptVectorCandidateCatalog(
            candidates: rawPropertyVectorProjection.candidates,
            materialBindings: admittedMaterials
        )
        let sceneBindings = sceneDocument.userPropertyResolution.bindingReport
        let activeSceneBindings = usesHDRWorkingDomain && appliesBloom ? sceneBindings.bindings
            : sceneBindings.bindings.filter { binding in
                switch binding.target {
                case .layerBrightness, .particle(_, .brightness):
                    return !sceneDocument.general.hdrEnabled || renderDescriptor.hdrEnabled
                case .scene:
                    guard case let .scene(field)? = ScenePropertyBindingCompiler.map(binding.target)?.target
                    else { return true }
                    return renderDescriptor.camera.bloom.consumes(field)
                default:
                    return true
                }
            }
        let materialBindings = SceneMaterialPropertyBindingCompiler.compile(
            descriptor: renderDescriptor,
            materialInstancesByLayerID: sceneDocument.materialInstancesByLayerID,
            provenBindings: propertyVectorProjection.materialBindings,
            modelScriptInputs: propertyVectorProjection.uniqueCandidates.map {
                (target: $0.definition.target, inputs: $0.properties)
            }
        )
        let compilation = ScenePropertyBindingCompiler().compile(
            report: .init(
                bindings: activeSceneBindings + materialBindings,
                diagnostics: sceneBindings.diagnostics
            ),
            catalog: project.userProperties,
            cameraInputLayerID: renderDescriptor.camera.default2DInputLayerID
        )
        // Script-owned effect-visibility targets (the batch-B producer
        // channel): these effects are activation-gated executable stages.
        let scriptOwnedEffectVisibilityTargets = Set(
            propertyVectorProjection.targets.compactMap { target -> SceneDynamicTarget? in
                guard case .effectVisibility = target else { return nil }
                return target
            }
        )
        let runtimeInput = SceneRuntimeInput(
            renderDescriptor: ScenePuppetAnimationPropertyPreparation.applyingBindings(
                compilation.program, report: sceneBindings, to: runtimeDescriptor),
            propertyBindingProgram: compilation.program,
            effectivePropertyValues: project.userProperties.effectiveValues(
                overrides: propertyOverrides
            ),
            shaderContracts: assetCatalog.shaderContracts,
            scriptOwnedEffectVisibilityTargets: scriptOwnedEffectVisibilityTargets,
            hasScriptLayerAccess: !sceneDocument.scriptBindings.isEmpty
        )

        var model = SceneRuntimeModel(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceView: sourceFacts.resourceView,
            authoredRenderDescriptor: renderDescriptor,
            renderDescriptor: runtimeInput.renderDescriptor,
            propertyVectorProjection: propertyVectorProjection,
            authoredEffectRenderPlans: runtimeInput.authoredEffectRenderPlans,
            runtimeInput: runtimeInput
        )
#if DEBUG
        model.resourceReferences = resourceReferences
        model.resourceIndex = sourceFacts.resourceIndex
        model.capabilityProfile = capabilityProfile
#endif
        return model
    }
}
