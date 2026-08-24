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
    let activeUniforms: [String: Uniform]
    let neutralTextureResolution:
        SceneAuthoredShaderNeutralTextureResolutionFact?

    fileprivate init(
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
        let sourceActiveSamplers: [
            Int: SceneResolvedMaterialShaderSchema.Sampler
        ]
        do {
            sourceActiveSamplers = try SceneResolvedMaterialShaderSchema.activeSamplers(
                prepared,
                activeNames: Set(activeSamplerNames)
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
        let sourceColorTransfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: compilerSources.fragment,
            provenRuntimeLoopBounds: runtimeLoopBounds.fragment
        )
        let preservedAlphaRGBColorSlots =
            SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(
                fragmentSource: compilerSources.fragment
            ).map { Set($0.colorSampleCallCounts.keys) } ?? []
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
            outputSemantics: outputSemantics
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
                    genericOwnerFailure: .productOwnerRevoked,
                    details: [
                        "generic-artifact", code, requestKey,
                        "bounded-frontend-owner-revoked",
                    ]
                )
            }
            onBoundedFrontendCompilation()
            let output = SceneAuthoredShaderFrontend.compile(
                vertexSource: compilerSources.vertex,
                fragmentSource: compilerSources.fragment,
                runtimeLoopBounds: runtimeLoopBounds
            )
            guard output.diagnostics.isEmpty,
                  let bounded = output.program else {
                throw failure(
                    .shaderFrontendFailed,
                    phase: .frontend,
                    genericOwnerFailure:
                        sharedRollbackOwnerFailure(routeDecision),
                    details: SceneResolvedMaterialExecutionCapabilityDiagnostics
                        .frontendFailure(template: template, output: output)
                        + ["generic-artifact", code, requestKey]
                )
            }
            frontend = bounded
            boundedOutput = output
            artifactFailure = ["generic-artifact", code, requestKey]
        }
        let genericOwnerFailure = sharedRollbackOwnerFailure(routeDecision)
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

    static func hasExternalProviderTexture(
        in template: Template,
        activeTextureSlots: Set<Int>? = nil
    ) -> Bool {
        template.textureSlots.enumerated().contains { index, slot in
            guard activeTextureSlots?.contains(index) != false,
                  let slot else { return false }
            // Candidate order is low to high precedence. A terminal graph
            // reference is the immutable selected override; earlier provider
            // entries are provenance and cannot become runtime fallbacks.
            if case .graph? = slot.candidates.last?.reference {
                return false
            }
            return slot.candidates.contains { candidate in
                if case .provider = candidate.reference { return true }
                return false
            }
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

    /// Only a migrated generic-only profile may select the bounded frontend as
    /// its explicit disable-generic rollback. If that shared rollback fails,
    /// the generic product owner is exhausted and the Program-first chain must
    /// not fall through to a retained dedicated implementation.
    private static func sharedRollbackOwnerFailure(
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
              profile.defaultRouteState == .genericOnly,
              state == .disableGeneric,
              fallbackOwner == .boundedFrontend else { return nil }
        return .sharedRollbackExhausted
    }
}
