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
        sourceColorTransfer: SceneShaderColorTransfer,
        colorBoundary: SceneShaderColorBoundary?,
        usesSourceRasterProjection: Bool = false
    ) throws -> (
        frontend: SceneAuthoredShaderProgram,
        routeDecision: SceneGenericShaderRouteDecision,
        boundedOutput: SceneAuthoredShaderFrontendOutput?,
        artifactFailure: [String],
        premultipliedColorInputSlots: Set<Int>
    ) {
        let sceneBackgroundColorSlots = SceneResolvedMaterialShaderSchema.sceneBackgroundColorSlots(template: template, samplers: sourceActiveSamplers)
        let sceneEnvironmentSlots = Set(sourceActiveSamplers.compactMap { slot, sampler in
            SceneResolvedMaterialShaderSchema.sceneEnvironmentReference(
                template: template, sampler: sampler, slot: slot) == nil ? nil : slot
        })
        let profileInputSlots: (String) -> Set<Int> = { profile in
            switch profile {
            case SceneGenericShaderCapabilityProfile
                .providerBackedGraphInputSpatialWeightedColorBlend.rawValue:
                spatialWeightedColorBlendExternalColorSlot.map { [$0] } ?? []
            case SceneGenericShaderCapabilityProfile.ordinaryShader.rawValue:
                // Mixed-provider slots select their ABI through the frame-owned
                // mixed contract, so the ordinary aux widening must not claim
                // them: claiming them turned an unproved potential fallback
                // into exact mixed evidence and revoked system-only programs.
                outputSemantics == .color
                    ? premultipliedColorAuxiliarySlots
                        .subtracting(mixedProviderSlots)
                    : []
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
                []
            }
        }
        let premultipliedInputSlotsForProfile: (String) -> Set<Int> = {
            profileInputSlots($0).union(sceneBackgroundColorSlots)
                .union(sceneEnvironmentSlots)
        }
        let frontend: SceneAuthoredShaderProgram
        let routeDecision:
            SceneGenericShaderRouteDecision
        let boundedOutput: SceneAuthoredShaderFrontendOutput?
        let artifactFailure: [String]
        let premultipliedColorInputSlots: Set<Int>
#if DEBUG
        SceneResolvedMaterialVariantCompileProfile.add(
            artifact: (CACurrentMediaTime() - artifactStart) * 1000
        )
#endif
        switch artifactResolution {
        case let .accepted(program, inputSlots, requestKey, decision):
            // The accepted artifact already validated this exact compiler ABI.
            // Reclassifying it with bounded-frontend rules loses mixed inputs.
            premultipliedColorInputSlots = inputSlots
            if template.graphRole.effectInput == .effectOutput,
               sceneBackgroundColorSlots.count == 1, let slot = sceneBackgroundColorSlots.first {
                frontend = prepareProjectedBackground(
                    program: program, slot: slot, vertexSource: compilerSources.vertex,
                    fragmentSource: compilerSources.fragment
                )
            } else {
                frontend = program
            }
            routeDecision = decision
            boundedOutput = nil
            artifactFailure = ["generic-artifact-accepted", requestKey]
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
                premultipliedColorInputSlots: premultipliedColorInputSlots,
                colorBoundary: colorBoundary,
                boundTextureSlots: Set(sourceActiveSamplers.keys),
                usesSourceRasterProjection: usesSourceRasterProjection
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

    private static func prepareProjectedBackground(
        program: SceneAuthoredShaderProgram, slot: Int, vertexSource: String, fragmentSource: String
    ) -> SceneAuthoredShaderProgram {
        guard program.supportsPlacementSpaceTerminalReplay,
              let input = program.textureBindings.first(where: { $0.slot == slot }),
              let fact = SceneAuthoredShaderSamePixelSourceAnalyzer.analyze(
                vertexSource: vertexSource, fragmentSource: fragmentSource, sceneBackgroundSlot: slot
              ), fact.positionMatrixUniformName == "g_ModelViewProjectionMatrix",
              let source = SceneGenericShaderAttachmentReadLowering.lower(
                metalSource: program.metalSource, fragmentFunctionName: program.fragmentFunctionName,
                sourceTextureName: input.name, sourceSampleCallCount: fact.sampleCallCount, sourceSlot: slot
              )
        else { return program }
        var result = program
        result.attachmentReadVariant = .init(
            schemaVersion: 1, sourceSlot: slot, metalSource: source,
            metalSourceSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            physicalTextureSlots: program.textureBindings.map(\.slot).filter { $0 != slot }.sorted(),
            usesSceneProjection: true
        )
        return result
    }
}
