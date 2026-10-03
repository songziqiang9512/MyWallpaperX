import Foundation
import QuartzCore

nonisolated extension SceneResolvedMaterialVariantCache {
    static func finalizeVariantBindings(
        template: Template,
        variantKey: SceneResolvedMaterialVariantKey,
        prepared: SceneShaderPreparedProgram,
        compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair,
        routeDecision: SceneGenericShaderRouteDecision,
        compatibilityTargetAdmissionPending: Bool,
        frontend: SceneAuthoredShaderProgram,
        boundedOutput: SceneAuthoredShaderFrontendOutput?,
        artifactFailure: [String],
        sourceActiveSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        sourceGraphInputFacts: [Int: SceneResolvedMaterialGraphInputSourceSlotFact],
        sourceColorTransfer: SceneShaderColorTransfer,
        neutralTextureResolution: SceneAuthoredShaderNeutralTextureResolutionFact?
    ) throws -> (
        sourceProvenOpaqueColorSlots: Set<Int>,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        graphInputFacts: [Int: SceneResolvedMaterialGraphInputSourceSlotFact],
        uniforms: [String: SceneResolvedMaterialShaderSchema.Uniform],
        preparedUniformBindings: [SceneResolvedMaterialPreparedUniformBinding],
        associatedOverOverlaySlot: Int?
    ) {
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
        if let internalTarget = unsupportedInternalTarget(in: samplers, template: template, inputIdentity: implicitFramebufferIdentity, readinessMask: variantKey.readinessMask) {
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
        let preparedUniformBindings: [
            SceneResolvedMaterialPreparedUniformBinding
        ]
        do {
            preparedUniformBindings = try SceneResolvedMaterialProgramFinalizer
                .prepareUniformBindings(
                    template: template,
                    fields: frontend.uniformLayout.fields,
                    activeUniforms: uniforms,
                    activeTextureSlots: activeSlots,
                    neutralTextureResolution: neutralTextureResolution
                )
        } catch let failure as Failure {
            throw failure.withGenericOwnerFailure(genericOwnerFailure)
        } catch {
            throw failure(
                .uniformBindingInvalid,
                phase: .uniform,
                genericOwnerFailure: genericOwnerFailure,
                details: ["prepared-uniform-binding-unexpected-failure"]
            )
        }
        let associatedOverOverlaySlot =
            SceneResolvedMaterialProgramDerivation.associatedOverOverlaySlot(
                fragmentSource: prepared.fragment.source
            )
        return (
            sourceProvenOpaqueColorSlots,
            samplers,
            graphInputFacts,
            uniforms,
            preparedUniformBindings,
            associatedOverOverlaySlot
        )
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
