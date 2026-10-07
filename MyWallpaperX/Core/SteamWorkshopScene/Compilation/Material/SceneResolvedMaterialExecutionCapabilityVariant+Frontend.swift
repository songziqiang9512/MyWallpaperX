import Foundation
import QuartzCore

nonisolated extension SceneResolvedMaterialVariantCache {
    static func resolveVariantFrontend(
        template: Template,
        sourceActiveSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        spatialWeightedColorBlendExternalColorSlot: Int?,
        premultipliedColorAuxiliarySlots: Set<Int>,
        mixedProviderSlots: Set<Int> = [],
        outputSemantics: SceneGenericShaderOutputSemantics,
        artifactStart: Double,
        artifactResolution: SceneResolvedMaterialGenericShaderArtifactCache.Resolution,
        compatibilityTargetAdmissionPending: Bool,
        onBoundedFrontendCompilation: () -> Void,
        compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds,
        sourceColorTransfer: SceneShaderColorTransfer
    ) throws -> (
        frontend: SceneAuthoredShaderProgram,
        routeDecision: SceneGenericShaderRouteDecision,
        boundedOutput: SceneAuthoredShaderFrontendOutput?,
        artifactFailure: [String],
        premultipliedColorInputSlots: Set<Int>
    ) {
        // A sampler whose only source is the internal scene-background
        // default reads a publication the registry defines as premultiplied
        // color; that slot crosses the color boundary by contract, not by
        // authored color-flow analysis.
        let sceneBackgroundDefaultSlots: Set<Int> = Set(
            sourceActiveSamplers.compactMap { (
                slot: Int,
                sampler: SceneResolvedMaterialShaderSchema.Sampler
            ) -> Int? in
                guard case .internalTarget = sampler.defaultTexture,
                      SceneResolvedMaterialTextureResolver.sceneBackgroundDefault(
                          template: template,
                          sampler: sampler,
                          slot: slot
                      ) != nil else { return nil }
                return slot
            }
        )
        let sceneEnvironmentSlots = Set(sourceActiveSamplers.compactMap { slot, sampler in
            SceneResolvedMaterialTextureResolver.sceneEnvironmentReference(
                template: template, sampler: sampler, slot: slot) == nil ? nil : slot
        })
        let profileInputSlots: (String) -> Set<Int> = { profile in
            switch profile {
            case SceneGenericShaderCapabilityProfile
                .providerBackedGraphInputSpatialWeightedColorBlend.rawValue:
                spatialWeightedColorBlendExternalColorSlot.map { [$0] } ?? []
            case SceneGenericShaderCapabilityProfile.ordinaryShader.rawValue:
                // Resource representation is independent of the output
                // profile; keep the existing background boundary as well.
                // Mixed-provider slots select their ABI through the frame-owned
                // mixed contract, so the ordinary aux widening must not claim
                // them: claiming them turned an unproved potential fallback
                // into exact mixed evidence and revoked system-only programs.
                outputSemantics == .color
                    ? premultipliedColorAuxiliarySlots
                        .subtracting(mixedProviderSlots)
                        .union(sceneBackgroundDefaultSlots)
                    : sceneBackgroundDefaultSlots
            case SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputOverlayAlphaBlend.rawValue,
                 SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputOverlayColorBlendAlphaPreserving.rawValue,
                 SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputAssociatedOverBlend.rawValue,
                 SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha
                .rawValue:
                premultipliedColorAuxiliarySlots
            default:
                sceneBackgroundDefaultSlots
            }
        }
        let premultipliedInputSlotsForProfile: (String) -> Set<Int> = {
            profileInputSlots($0).union(sceneEnvironmentSlots)
        }
        let frontend: SceneAuthoredShaderProgram
        let routeDecision:
            SceneGenericShaderRouteDecision
        let boundedOutput: SceneAuthoredShaderFrontendOutput?
        let artifactFailure: [String]
        let premultipliedColorInputSlots: Set<Int>
        SceneResolvedMaterialVariantCompileProfile.add(
            artifact: (CACurrentMediaTime() - artifactStart) * 1000
        )
        switch artifactResolution {
        case let .accepted(program, inputSlots, requestKey, decision):
            // The accepted artifact already validated this exact compiler ABI.
            // Reclassifying it with bounded-frontend rules loses mixed inputs.
            premultipliedColorInputSlots = inputSlots
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
            premultipliedColorInputSlots =
                premultipliedInputSlotsForProfile(decision.profile)
            let output = SceneAuthoredShaderFrontend.compile(
                vertexSource: compilerSources.vertex,
                fragmentSource: compilerSources.fragment,
                runtimeLoopBounds: runtimeLoopBounds,
                provenColorTransfer: sourceColorTransfer,
                premultipliedColorInputSlots: premultipliedColorInputSlots
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
        return (
            frontend,
            routeDecision,
            boundedOutput,
            artifactFailure,
            premultipliedColorInputSlots
        )
    }
}
