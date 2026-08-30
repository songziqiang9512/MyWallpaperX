import Foundation

/// Immutable shader/frontend/schema facts for one texture-readiness variant.
/// Concrete resources and uniform values are bound by each frame snapshot.
nonisolated struct SceneResolvedMaterialCompiledVariant {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    let readinessMask: UInt8
    let textureFormats: [SceneShaderTextureFormat?]
    let preparedShader: SceneShaderPreparedProgram
    let frontendProgram: SceneAuthoredShaderProgram
    let routeDecision: SceneGenericShaderRouteDecision
    let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
    let activeSamplers: [Int: Sampler]
    let graphInputSourceSlotFacts: [
        Int: SceneResolvedMaterialGraphInputSourceSlotFact
    ]
    let preservedAlphaRGBColorSlots: Set<Int>
    let sourceProvenOpaqueColorSlots: Set<Int>
    let conditionalGeneratedRGBInputContract:
        SceneResolvedMaterialProgramDerivation
            .ConditionalGeneratedRGBInputContract?
    let sameAlphaReconstructedRGBInputContract:
        SceneResolvedMaterialProgramDerivation
            .SameAlphaReconstructedRGBInputContract?
    let activeUniforms: [String: Uniform]
    let neutralTextureResolution:
        SceneAuthoredShaderNeutralTextureResolutionFact?

    init(
        readinessMask: UInt8,
        textureFormats: [SceneShaderTextureFormat?],
        preparedShader: SceneShaderPreparedProgram,
        frontendProgram: SceneAuthoredShaderProgram,
        routeDecision: SceneGenericShaderRouteDecision,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds,
        activeSamplers: [Int: Sampler],
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ],
        preservedAlphaRGBColorSlots: Set<Int>,
        sourceProvenOpaqueColorSlots: Set<Int>,
        conditionalGeneratedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .ConditionalGeneratedRGBInputContract?,
        sameAlphaReconstructedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .SameAlphaReconstructedRGBInputContract?,
        activeUniforms: [String: Uniform],
        neutralTextureResolution:
            SceneAuthoredShaderNeutralTextureResolutionFact?
    ) {
        self.readinessMask = readinessMask
        self.textureFormats = textureFormats
        self.preparedShader = preparedShader
        self.frontendProgram = frontendProgram
        self.routeDecision = routeDecision
        self.runtimeLoopBounds = runtimeLoopBounds
        self.activeSamplers = activeSamplers
        self.graphInputSourceSlotFacts = graphInputSourceSlotFacts
        self.preservedAlphaRGBColorSlots = preservedAlphaRGBColorSlots
        self.sourceProvenOpaqueColorSlots = sourceProvenOpaqueColorSlots
        self.conditionalGeneratedRGBInputContract =
            conditionalGeneratedRGBInputContract
        self.sameAlphaReconstructedRGBInputContract =
            sameAlphaReconstructedRGBInputContract
        self.activeUniforms = activeUniforms
        self.neutralTextureResolution = neutralTextureResolution
    }
}

nonisolated extension SceneResolvedMaterialVariantCache {
    static func compile(
        template: Template,
        variantKey: SceneResolvedMaterialVariantKey,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage,
        outputIsRGBA8Unorm: Bool,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphTextureFormatFacts: [Graph.TextureIdentity: SceneShaderTextureFormat],
        onBoundedFrontendCompilation: () -> Void
    ) throws -> Variant {
        let readinessMask = variantKey.readinessMask
        let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, readinessMask & (1 << UInt8($0)) != 0)
        })
        let prepared: SceneShaderPreparedProgram
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: template.shaderContract,
            compatibilityTarget: template.compatibilityTarget,
            combos: template.comboValues,
            inactiveComboProviders: Set(template.inheritedInactiveCombos),
            textureReadiness: readiness,
            textureFormats: variantKey.resolvedTextureFormats
        ) {
        case let .accepted(value): prepared = value
        case let .rejected(rejection):
            throw failure(
                .shaderPreparationFailed,
                phase: .preparation,
                details: [rejection.phase.rawValue, rejection.code.rawValue]
                    + rejection.details
            )
        case .notApplicable:
            throw failure(.identityInvariant, phase: .invariant)
        }
        let compatibilityTargetAdmissionPending = prepared.all.allSatisfy {
            $0.compatibilityTarget == .windowsDX11ShaderModel4
        } && prepared.all.contains {
            !$0.compatibilityMacroDependencies.isEmpty
        }
        let compilerSources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: prepared.vertex.source,
            fragment: prepared.fragment.source
        )
        let runtimeLoopBounds = SceneResolvedMaterialRuntimeLoopBoundResolver.resolve(
            template: template,
            prepared: prepared
        )
        let activeSamplerNames = SceneAuthoredShaderDeadBindingAnalyzer
            .activeSamplerNames(
                vertexSource: compilerSources.vertex,
                fragmentSource: compilerSources.fragment,
                runtimeLoopBounds: runtimeLoopBounds
            ) ?? []
        guard let resolvedIntegerCombos =
                SceneAuthoredShaderPreparation.resolvedIntegerCombos(
                    contract: template.shaderContract,
                    prepared: prepared,
                    combos: template.comboValues,
                    inactiveComboProviders: Set(
                        template.inheritedInactiveCombos
                    ),
                    textureReadiness: readiness,
                    textureFormats: variantKey.resolvedTextureFormats
                ) else {
            throw failure(.shaderPreparationFailed, phase: .preparation)
        }
        let normalBlendModeIdentifiers = Set(
            resolvedIntegerCombos.compactMap { name, value in
                value == 0 ? name : nil
            }
        )
        let sourceActiveSamplers: [
            Int: SceneResolvedMaterialShaderSchema.Sampler
        ]
        do {
            sourceActiveSamplers = try SceneResolvedMaterialShaderSchema.activeSamplers(
                prepared,
                activeNames: Set(activeSamplerNames),
                analysisVertexSource: compilerSources.vertex,
                analysisFragmentSource: compilerSources.fragment,
                normalBlendModeIdentifiers: normalBlendModeIdentifiers
            )
        } catch {
            throw failure(.authoredSamplerSchemaInvalid)
        }
        let activeGraphTextureIdentities = Dictionary(uniqueKeysWithValues:
            activeSamplerNames.compactMap { name -> (Int, Graph.TextureIdentity)? in
                guard name.hasPrefix("g_Texture"),
                      let slot = Int(name.dropFirst("g_Texture".count)),
                      template.textureSlots.indices.contains(slot),
                      let candidate = template.textureSlots[slot]?.candidates.last,
                      case let .graph(identity) = candidate.reference
                else { return nil }
                return (slot, identity)
            })
        let graphTextureSlots = Set(activeGraphTextureIdentities.compactMap {
            $0.value.kind == .framebuffer ? $0.key : nil
        })
        let spatialWeightedColorBlendFact =
            SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer.analyze(
                fragmentSource: compilerSources.fragment,
                normalBlendModeIdentifiers: normalBlendModeIdentifiers
            )
        let analyzedSourceColorTransfer =
            SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: compilerSources.fragment,
                provenRuntimeLoopBounds: runtimeLoopBounds.fragment
            )
        let conditionalGeneratedRGBFact =
            SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.analyze(
                fragmentSource: compilerSources.fragment
            )
        let sameAlphaReconstructedRGBFact =
            SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze(
                fragmentSource: compilerSources.fragment
            )
        let rgbBlendScalarAlphaFact =
            SceneAuthoredShaderColorTransferAnalyzer.rgbBlendScalarAlphaFact(
                fragmentSource: compilerSources.fragment
            )
        let sourceColorTransfer: SceneShaderColorTransfer =
            spatialWeightedColorBlendFact.map {
                .straightAlphaPreserving(textureSlot: $0.sourceSlot)
            } ?? analyzedSourceColorTransfer
        let spatialWeightedColorBlendTypedAuxiliarySlots = Set(
            sourceActiveSamplers.compactMap { slot, sampler in
                sampler.sourceProvenPurpose == nil ? nil : slot
            }
        )
        let activeExternalProviderTextureSlots = externalProviderTextureSlots(
            in: template,
            activeTextureSlots: Set(sourceActiveSamplers.keys)
        )
        let activeTerminalNamedLayerProviderTextureSlots =
            terminalNamedLayerProviderTextureSlots(
            in: template,
            activeTextureSlots: Set(sourceActiveSamplers.keys)
        )
        let spatialWeightedColorBlendExternalColorSlot: Int?
        if let fact = spatialWeightedColorBlendFact,
           activeExternalProviderTextureSlots == [fact.straightColorSlot],
           activeTerminalNamedLayerProviderTextureSlots == [fact.straightColorSlot] {
            spatialWeightedColorBlendExternalColorSlot = fact.straightColorSlot
        } else {
            spatialWeightedColorBlendExternalColorSlot = nil
        }
        let preservedAlphaRGBColorSlots: Set<Int>
        if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(
            fragmentSource: compilerSources.fragment
        ) {
            preservedAlphaRGBColorSlots = Set(fact.colorSampleCallCounts.keys)
        } else if let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(
            fragmentSource: compilerSources.fragment
        ) {
            preservedAlphaRGBColorSlots = [fact.sourceSlot]
        } else if let fact = sameAlphaReconstructedRGBFact {
            preservedAlphaRGBColorSlots = [fact.sourceSlot]
        } else if let fact = rgbBlendScalarAlphaFact {
            preservedAlphaRGBColorSlots = [fact.sourceSlot]
        } else {
            preservedAlphaRGBColorSlots = []
        }
        let conditionalGeneratedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .ConditionalGeneratedRGBInputContract?
        if let fact = conditionalGeneratedRGBFact,
           sourceColorTransfer == .straightAlphaPreserving(
            textureSlot: fact.alphaCarrierSlot
           ) {
            conditionalGeneratedRGBInputContract = .init(
                alphaCarrierSlot: fact.alphaCarrierSlot,
                generatedOpaqueColorSlots: fact.generatedOpaqueColorSlots,
                scalarRedSlots: fact.scalarRedSlots,
                scalarGreenSlots: fact.scalarGreenSlots,
                scalarBlueSlots: fact.scalarBlueSlots,
                scalarAlphaSlots: fact.scalarAlphaSlots
            )
        } else {
            conditionalGeneratedRGBInputContract = nil
        }
        let sameAlphaReconstructedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .SameAlphaReconstructedRGBInputContract?
        if let fact = sameAlphaReconstructedRGBFact,
           sourceColorTransfer == .straightAlphaPreserving(
            textureSlot: fact.sourceSlot
           ) {
            sameAlphaReconstructedRGBInputContract = .init(
                sourceSlot: fact.sourceSlot,
                dataSlots: fact.auxiliarySlots
            )
        } else {
            sameAlphaReconstructedRGBInputContract = nil
        }
        let sourceGraphInputFacts = SceneResolvedMaterialShaderSchema
            .graphInputSourceSlotFacts(
                template: template,
                samplers: sourceActiveSamplers,
                inputIdentity: implicitFramebufferIdentity,
                sourceColorTransfer: sourceColorTransfer
            )
        var graphInputTextureSlots = Set(activeGraphTextureIdentities.keys)
        graphInputTextureSlots.formUnion(template.graphRole.bindings.compactMap {
            sourceActiveSamplers[$0.slot] == nil ? nil : $0.slot
        })
        graphInputTextureSlots.formUnion(sourceGraphInputFacts.keys)
        let typedStaticDataAuxiliarySlots = typedStaticDataAuxiliarySlots(
            template: template,
            samplers: sourceActiveSamplers,
            graphInputSlots: graphInputTextureSlots
        )
        let graphR8TextureSlots = Set(activeGraphTextureIdentities.compactMap {
            graphTextureFormatFacts[$0.value] == .r8 ? $0.key : nil
        })
        let activeTextureSlots: Set<Int> = Set(activeSamplerNames.compactMap { name -> Int? in
            guard name.hasPrefix("g_Texture"),
                  let slot = Int(name.dropFirst("g_Texture".count)) else {
                return nil
            }
            return slot
        })
        let activeOpacityMaskSlots = Set(sourceActiveSamplers.compactMap {
            slot, sampler in sampler.mode == .opacityMask ? slot : nil
        })
        let neutralTextureResolution =
            SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
                vertexSource: compilerSources.vertex,
                fragmentSource: compilerSources.fragment,
                activeSamplerSlots: activeTextureSlots
            )
        let outputSemantics: SceneGenericShaderOutputSemantics = switch outputStorage {
        case .redGreenUnorm: .redGreenUnorm
        case .preservedRGBAUnorm: .preservedRGBAUnorm
        default: .color
        }
        let alphaAttenuationSourceSlot =
            SceneResolvedMaterialAlphaAttenuationEligibility.sourceSlot(
                    fragmentSource: prepared.fragment.source,
                    samplers: sourceActiveSamplers,
                    template: template,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    graphInputSourceSlotFacts: sourceGraphInputFacts
                )
        let colorBlendSourceSlot =
            SceneResolvedMaterialColorBlendEligibility.sourceSlot(
                fragmentSource: prepared.fragment.source,
                colorTransfer: sourceColorTransfer,
                samplers: sourceActiveSamplers,
                template: template,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                graphInputSourceSlotFacts: sourceGraphInputFacts
            )
        let unitCompositeSlots =
            SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.slots(
                fragmentSource: compilerSources.fragment,
                prepared: prepared,
                samplers: sourceActiveSamplers,
                template: template,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                activeGraphTextureIdentities: activeGraphTextureIdentities
            )
        let artifactResolution = SceneResolvedMaterialGenericShaderArtifactCache.resolve(
            vertexSource: compilerSources.vertex,
            fragmentSource: compilerSources.fragment,
            alphaAttenuationSourceSlot: alphaAttenuationSourceSlot,
            colorBlendSourceSlot: colorBlendSourceSlot,
            unitCompositeBlurredSlot: unitCompositeSlots?.blurred,
            unitCompositePreviousSlot: unitCompositeSlots?.previous,
            unitCompositeMaskSlot: unitCompositeSlots?.mask,
            hasExternalProviderTexture:
                SceneResolvedMaterialVariantCache.hasExternalProviderTexture(
                    in: template,
                    activeTextureSlots: activeTextureSlots
                ),
            producesScalarRedOutput: outputStorage == .scalarRedUnorm
                || outputStorage == .scalarRedFloat16,
            producesRedGreenUnormOutput: outputStorage == .redGreenUnorm,
            hasOnlyScalarDataInputs:
                SceneResolvedMaterialShaderSchema.hasOnlyScalarDataInputs(
                    sourceActiveSamplers,
                    activeSlots: activeTextureSlots,
                    resolvedFormats: variantKey.resolvedTextureFormats
                ),
            isSourceIndependentPremultipliedOutput:
                outputStorage == .color
                    && sourceActiveSamplers[0] == nil
                    && graphTextureSlots.isEmpty
                    && graphInputTextureSlots.isEmpty,
            graphTextureSlots: graphTextureSlots,
            graphInputTextureSlots: graphInputTextureSlots,
            activeTextureSlots: activeTextureSlots,
            activeOpacityMaskSlots: activeOpacityMaskSlots,
            typedStaticDataAuxiliarySlots: typedStaticDataAuxiliarySlots,
            spatialWeightedColorBlendSourceSlot:
                spatialWeightedColorBlendFact?.sourceSlot,
            spatialWeightedColorBlendActiveSlots:
                spatialWeightedColorBlendFact?.activeSlots ?? [],
            spatialWeightedColorBlendTypedAuxiliarySlots:
                spatialWeightedColorBlendTypedAuxiliarySlots,
            spatialWeightedColorBlendExternalColorSlot:
                spatialWeightedColorBlendExternalColorSlot,
            r8TextureSlots: graphR8TextureSlots,
            hasDefaultedOpacityMaskSampler:
                SceneResolvedMaterialShaderSchema.hasOnlyDefaultedOpacityMaskAuxiliary(
                    sourceActiveSamplers,
                    graphInputSlots: graphInputTextureSlots
                ),
            hasOnlyTypedOpacityMaskAuxiliary:
                SceneResolvedMaterialShaderSchema.hasOnlyTypedOpacityMaskAuxiliary(
                    sourceActiveSamplers,
                    graphInputSlots: graphInputTextureSlots
                ),
            hasOnlyGraphInputSampler:
                !sourceActiveSamplers.isEmpty
                    && Set(sourceActiveSamplers.keys) == graphInputTextureSlots,
            outputIsRGBA8Unorm: outputIsRGBA8Unorm,
            sourceColorTransfer: sourceColorTransfer,
            outputSemantics: outputSemantics,
            runtimeLoopBounds: runtimeLoopBounds
        )
        let frontend: SceneAuthoredShaderProgram
        let routeDecision:
            SceneGenericShaderRouteDecision
        let boundedOutput: SceneAuthoredShaderFrontendOutput?
        let artifactFailure: [String]
        switch artifactResolution {
        case let .accepted(program, requestKey, decision):
            frontend = program
            routeDecision = decision
            boundedOutput = nil
            artifactFailure = ["generic-artifact-accepted", requestKey]
        case let .ownerDeferred(code, requestKey, decision):
            if compatibilityTargetAdmissionPending {
                throw failure(
                    .shaderFrontendFailed,
                    phase: .frontend,
                    details: [
                        "compatibility-target-unadmitted",
                        "generic-artifact", code, requestKey, decision.profile,
                    ]
                )
            }
            throw failure(
                .genericProductOwnerDeferred,
                phase: .frontend,
                details: ["generic-artifact", code, requestKey, decision.profile]
            )
        case let .unavailable(
            code,
            requestKey,
            permitsBoundedFrontend,
            decision
        ):
            routeDecision = decision
            guard permitsBoundedFrontend else {
                throw failure(
                    .shaderFrontendFailed,
                    phase: .frontend,
                    genericOwnerFailure: compatibilityTargetAdmissionPending
                        ? nil : .productOwnerRevoked,
                    details: [
                        "generic-artifact", code, requestKey,
                        "bounded-frontend-owner-revoked",
                        compatibilityTargetAdmissionPending
                            ? "compatibility-target-unadmitted"
                            : "compatibility-target-not-applicable",
                    ]
                )
            }
            onBoundedFrontendCompilation()
            let output = SceneAuthoredShaderFrontend.compile(
                vertexSource: compilerSources.vertex,
                fragmentSource: compilerSources.fragment,
                runtimeLoopBounds: runtimeLoopBounds,
                provenColorTransfer: sourceColorTransfer,
                premultipliedColorInputSlots:
                    decision.profile == SceneGenericShaderCapabilityProfile
                        .providerBackedGraphInputSpatialWeightedColorBlend.rawValue
                        ? spatialWeightedColorBlendExternalColorSlot.map {
                            Set([$0])
                        } ?? []
                        : []
            )
            guard output.diagnostics.isEmpty,
                  let bounded = output.program else {
                throw failure(
                    .shaderFrontendFailed,
                    phase: .frontend,
                    genericOwnerFailure:
                        compatibilityTargetAdmissionPending
                            ? nil : genericOwnerFailure(routeDecision),
                    details: SceneResolvedMaterialExecutionCapabilityDiagnostics
                        .frontendFailure(template: template, output: output)
                        + ["generic-artifact", code, requestKey]
                )
            }
            frontend = bounded
            boundedOutput = output
            artifactFailure = ["generic-artifact", code, requestKey]
        }
        let sourceProvenOpaqueColorSlots: Set<Int>
        if routeDecision.profile
            == SceneGenericShaderCapabilityProfile
                .sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage.rawValue {
            guard let fact =
                    SceneAuthoredShaderOpaqueAlphaWeightedLoopAverageAnalyzer
                        .analyze(fragmentSource: compilerSources.fragment) else {
                throw failure(
                    .identityInvariant,
                    phase: .invariant,
                    details: ["opaque-color-source-contract-missing"]
                )
            }
            sourceProvenOpaqueColorSlots = [fact.sourceSlot]
        } else {
            sourceProvenOpaqueColorSlots = []
        }
        // Compatibility-target branch selection is only a Program candidate.
        // The route decision becomes product ownership when every admission
        // check below succeeds and the compiled Variant is returned.
        let genericOwnerFailure = compatibilityTargetAdmissionPending
            ? nil : genericOwnerFailure(routeDecision)
        guard
              SceneResolvedMaterialProgramDerivation.validPreparedStages(prepared),
              SceneResolvedMaterialProgramDerivation.uniqueAndValid(
                  frontend.uniformLayout
              ) else {
            throw failure(
                .shaderFrontendFailed,
                phase: .frontend,
                genericOwnerFailure: genericOwnerFailure,
                details: (boundedOutput.map {
                    SceneResolvedMaterialExecutionCapabilityDiagnostics
                        .frontendFailure(template: template, output: $0)
                } ?? []) + artifactFailure
            )
        }
        let samplers = sourceActiveSamplers
        let bindings = frontend.textureBindings
        if let internalTarget = internalTarget(in: samplers) {
            throw failure(
                .samplerInternalTargetUnsupported,
                phase: .preparation,
                slot: internalTarget.slot,
                genericOwnerFailure: genericOwnerFailure,
                details: [internalTarget.name]
            )
        }
        do {
            try validateSamplerBindings(samplers, bindings: bindings)
        } catch let failure as Failure {
            throw failure.withGenericOwnerFailure(genericOwnerFailure)
        }
        let graphInputFacts = SceneResolvedMaterialShaderSchema
            .graphInputSourceSlotFacts(
                template: template,
                samplers: samplers,
                inputIdentity: implicitFramebufferIdentity,
                sourceColorTransfer: frontend.colorTransfer,
                frontendBindings: bindings
            )
        let bindingFactTokens = bindings.map {
            "\($0.slot):\($0.name):\($0.channelUse.rawValue)"
        }.sorted()
        guard graphInputFacts == sourceGraphInputFacts else {
            throw failure(
                .samplerBindingIdentityMismatch,
                phase: .invariant,
                genericOwnerFailure: genericOwnerFailure,
                details: [
                    "graph-input-source-fact-divergence",
                    "source-transfer-\(sourceColorTransfer)",
                    "frontend-transfer-\(frontend.colorTransfer)",
                    "source-slots-\(sourceGraphInputFacts.keys.sorted())",
                    "frontend-slots-\(graphInputFacts.keys.sorted())",
                    "bindings-\(bindingFactTokens)",
                ]
            )
        }
        if declaresActivePass(prepared) {
            throw failure(
                .activePassUnsupported,
                phase: .preparation,
                genericOwnerFailure: genericOwnerFailure,
                details: ["active-pass"]
            )
        }
        let activeSlots = Set(bindings.map(\.slot))
        let nonHost = frontend.uniformLayout.fields.filter {
            SceneResolvedMaterialUniformEncoder.hostUniform(
                $0,
                activeTextureSlots: activeSlots
            ) == nil
        }
        let uniforms: [String: SceneResolvedMaterialShaderSchema.Uniform]
        do {
            uniforms = try SceneResolvedMaterialShaderSchema.activeUniforms(
                nonHost,
                prepared: prepared
            )
        } catch {
            throw failure(
                .uniformBindingInvalid,
                phase: .uniform,
                genericOwnerFailure: genericOwnerFailure,
                details: [String(describing: error)]
            )
        }
        return .init(
            readinessMask: readinessMask,
            textureFormats: variantKey.textureFormats,
            preparedShader: prepared,
            frontendProgram: frontend,
            routeDecision: routeDecision,
            runtimeLoopBounds: runtimeLoopBounds,
            activeSamplers: samplers,
            graphInputSourceSlotFacts: graphInputFacts,
            preservedAlphaRGBColorSlots: preservedAlphaRGBColorSlots,
            sourceProvenOpaqueColorSlots: sourceProvenOpaqueColorSlots,
            conditionalGeneratedRGBInputContract:
                conditionalGeneratedRGBInputContract,
            sameAlphaReconstructedRGBInputContract:
                sameAlphaReconstructedRGBInputContract,
            activeUniforms: uniforms,
            neutralTextureResolution: neutralTextureResolution
        )
    }

    private static func internalTarget(
        in samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> (slot: Int, name: String)? {
        for (slot, sampler) in samplers.sorted(by: { $0.key < $1.key }) {
            if case let .internalTarget(name)? = sampler.defaultTexture {
                return (slot, name)
            }
        }
        return nil
    }

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

    private static func declaresActivePass(
        _ prepared: SceneShaderPreparedProgram
    ) -> Bool {
        prepared.all.contains { source in
            source.activeAnnotations.contains { annotation in
                annotation.annotation.marker?.caseInsensitiveCompare("[PASS]")
                    == .orderedSame
            }
        }
    }

    static func failure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil,
        genericOwnerFailure: Failure.GenericOwnerFailure? = nil,
        details: [String] = []
    ) -> Failure {
        .init(
            phase: phase,
            code: code,
            slot: slot,
            genericOwnerFailure: genericOwnerFailure,
            details: details
        )
    }

    /// A migrated generic-only profile may select the bounded frontend as its
    /// source-proven runtime-loop primary or explicit disable-generic rollback.
    /// If that shared compiler fails, the generic product owner is exhausted
    /// and Program-first must not revive a retained dedicated implementation.
    static func genericOwnerFailure(
        _ decision: SceneGenericShaderRouteDecision
    ) -> Failure.GenericOwnerFailure? {
        guard let profile = SceneGenericShaderCapabilityProfile(
                  rawValue: decision.profile
              ),
              let state = SceneGenericShaderRouteState(
                  rawValue: decision.state
              ),
              let fallbackOwner = SceneGenericShaderFallbackOwner(
                  rawValue: decision.fallbackOwner
              ),
              profile.defaultRouteState == .genericOnly else { return nil }
        if state == .disableGeneric, fallbackOwner == .boundedFrontend {
            return .sharedRollbackExhausted
        }
        return .productOwnerRevoked
    }
}
