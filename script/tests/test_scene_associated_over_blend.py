#!/usr/bin/env python3

"""Associated-over WRITEALPHA blend is source-proven and identity-free."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteAuthority.swift",
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let sourceSlot: Int?
    let overlaySlot: Int?
    let renamedAccepted: Bool
    let transferAccepted: Bool
    let renamedTransferAccepted: Bool
    let boundedUnpremultipliesSource: Bool
    let boundedLeavesOverlayData: Bool
    let boundedPremultipliesOutput: Bool
    let loweringAccepted: Bool
    let loweringLeavesOverlayData: Bool
    let loweringPremultipliesOutput: Bool
    let extraSampleRejected: Bool
    let writeAlphaOffRejected: Bool
    let overlayAlphaNotAssociatedOver: Bool
    let overlayAlphaKeepsStraightTransfer: Bool
    let extraBlendCallRejected: Bool
    let controlFlowRejected: Bool
    let helperDriftRejected: Bool
    let sameSlotRejected: Bool
    let uvHelperDriftRejected: Bool
    let extraOutputRejected: Bool
    let extraCompilerSampleRejected: Bool
    let indirectHelperSideEffectRejected: Bool
    let compilerDroppedOverlayRejected: Bool
    let compilerDroppedSourceContributionRejected: Bool
    let compilerInertOverlayUseRejected: Bool
    let compilerZeroOverlayContributionRejected: Bool
    let compilerWrongBlendFunctionRejected: Bool
    let compilerLiteralZeroWeightRejected: Bool
    let compilerWeightMutationRejected: Bool
    let compilerWeightIncrementRejected: Bool
    let compilerOverlayMutationRejected: Bool
    let compilerPostBlendOverwriteRejected: Bool
    let compilerZeroWeightInitializerRejected: Bool
    let compilerZeroProductInitializerRejected: Bool
    let compilerWrongCarrierRejected: Bool
    let routeProfile: String
    let graphOverlayRouteProfile: String
    let routeState: String
    let namedProviderOverlayRouteProfile: String
    let namedProviderOverlayPremultipliedRouteProfile: String
    let extraProviderRejected: Bool
    let providerRejected: Bool
    let wrongPremultipliedSlotRejected: Bool
    let missingGraphInputRejected: Bool
    let overlayAlpha957Accepted: Bool
    let overlayAlphaNamedProviderRouteProfile: String
    let overlayAlpha957NamedProviderRouteProfile: String
    let overlayAlphaNamedProviderLoweringUnpremultipliesOverlay: Bool
    let overlayAlphaTypedStaticRouteProfile: String
    let overlayAlphaLoweringAccepted: Bool
    let overlayAlphaLoweringLeavesOverlayData: Bool
    let overlayAlphaLoweringPremultipliesOutput: Bool
    let overlayAlphaMissingAlphaWriteRejected: Bool
    let overlayAlphaZeroContributionRejected: Bool
    let overlayAlpha957LoweringAccepted: Bool
    let overlayAlphaPreservingAccepted: Bool
    let overlayAlphaPreservingTransferAccepted: Bool
    let overlayAlphaPreservingDataRouteProfile: String
    let overlayAlphaPreservingPremultipliedRouteProfile: String
    let overlayAlphaPreservingDataLoweringAccepted: Bool
    let overlayAlphaPreservingDataLoweringLeavesOverlayData: Bool
    let overlayAlphaPreservingPremultipliedLoweringUnpremultipliesOverlay: Bool
    let overlayAlphaPreservingAlphaMutationRejected: Bool
}

private let associatedOverHelper = """
vec4 Composite(vec4 albedo, vec4 blendColors, float blendAlpha) {
    float newAlpha = (albedo.a * (1.0 - blendAlpha) + blendColors.a * blendAlpha);
    vec4 input = albedo;
    albedo.rgb = albedo.rgb * albedo.a * (1.0 - blendAlpha) + blendColors.rgb * blendColors.a * blendAlpha;
    vec3 srcRgb = mix(blendColors.rgb, input.rgb, step(0.01, input.a) * (1.0 - blendColors.a * blendAlpha));
    vec3 dstRgb = mix(input.rgb, blendColors.rgb, step(0.01, blendColors.a * (1.0 - input.a * (1.0 - blendAlpha))));
    albedo.rgb += mix(srcRgb, dstRgb, blendAlpha) * (1.0 - newAlpha);
    albedo.a = newAlpha;
    return albedo;
}
float GetUVBlend(vec2 uv) {
    return 1.0;
}
"""

private let authored = """
varying vec4 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_ScalarWeight;
\(associatedOverHelper)
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
    vec2 blendUV = v_TexCoord.zw;
    vec4 blendColors = texSample2D(g_Texture1, blendUV);
    float blend = 1.0;
    blend = GetUVBlend(blendUV) * blend;
    float blendAlpha = blend * g_ScalarWeight;
    albedo = Composite(albedo, blendColors, blendAlpha);
    gl_FragColor = albedo;
}
"""

private let renamedAuthored = """
varying vec4 v_Packed;
uniform sampler2D g_Texture3;
uniform sampler2D g_Texture2;
uniform float g_Amount;
float4 Combine(float4 base, float4 overlay, float amount) {
    float outAlpha = (base.w * (1.0 - amount) + overlay.w * amount);
    float4 saved = base;
    base.xyz = base.xyz * base.w * (1.0 - amount) + overlay.xyz * overlay.w * amount;
    float3 src = lerp(overlay.xyz, saved.xyz, step(0.01, saved.w) * (1.0 - overlay.w * amount));
    float3 dst = lerp(saved.xyz, overlay.xyz, step(0.01, overlay.w * (1.0 - saved.w * (1.0 - amount))));
    base.xyz += lerp(src, dst, amount) * (1.0 - outAlpha);
    base.w = outAlpha;
    return base;
}
void main() {
    float4 surface = texture2D(g_Texture3, v_Packed.xy);
    float2 overlayUV = v_Packed.zw;
    float4 layer = texture2D(g_Texture2, overlayUV);
    float weight = g_Amount;
    surface = Combine(surface, layer, weight);
    gl_FragColor = surface;
}
"""

private let overlayAlphaAuthored = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Opacity;
uniform float g_AlphaMultiply;
varying vec2 v_TexCoord;
vec3 ApplyBlending(
    const int mode,
    in vec3 base,
    in vec3 blend,
    in float opacity
) {
    return mix(base, blend, opacity);
}
void main() {
    vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
    vec4 overlay = texSample2D(g_Texture1, v_TexCoord);
    float weight = g_Opacity * overlay.a;
    carrier.rgb = ApplyBlending(0, carrier.rgb, overlay.rgb, weight);
    carrier.a = overlay.a * g_AlphaMultiply;
    gl_FragColor = carrier;
}
"""

private let writeAlphaApplyBlendingAuthored = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Multiply;
uniform float g_AlphaMultiply;
varying vec4 v_TexCoord;
float GetUVBlend(vec2 uv) {
    return 1.0;
}
vec3 ApplyBlending(const int blendMode, in vec3 A, in vec3 B, in float opacity) {
    return mix(A, (B), opacity);
}
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
    vec2 blendUV = v_TexCoord.zw;
    vec4 blendColors = texSample2D(g_Texture1, blendUV);
    float blend = 1.0;
    float blendAlpha = GetUVBlend(blendUV) * blend * g_Multiply * blendColors.a;
    albedo.rgb = ApplyBlending(0, albedo.rgb, blendColors.rgb, blendAlpha);
    albedo.a = blendColors.a * g_AlphaMultiply;
    gl_FragColor = albedo;
}
"""

private let overlayAlphaPreservingAuthored =
    writeAlphaApplyBlendingAuthored.replacingOccurrences(
        of: "    albedo.a = blendColors.a * g_AlphaMultiply;\n",
        with: ""
    )

private let compilerMSL = """
#include <metal_stdlib>
using namespace metal;
fragment void f() {
    float4 albedo = g_Texture0.sample(sourceSampler, uv);
    float4 blendColors = g_Texture1.sample(overlaySampler, overlayUV);
    float blendAlpha = g_ScalarWeight;
    albedo = Composite(albedo, blendColors, blendAlpha);
    out.mwxFragColor = albedo;
    return out;
}
"""

private func fact(_ source: String) -> SceneAuthoredShaderAssociatedOverBlendAnalyzer.Fact? {
    SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze(fragmentSource: source)
}

private func transfer(_ source: String) -> SceneShaderColorTransfer {
    SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source)
}

private func overlayAlpha(
    _ source: String
) -> (source: Int, overlay: Int)? {
    SceneAuthoredShaderColorTransferAnalyzer.blendSourceSlots(
        fragmentSource: source
    ).overlayAlpha
}

private func overlayAlphaPreserving(
    _ source: String
) -> (source: Int, overlay: Int)? {
    SceneAuthoredShaderColorTransferAnalyzer.blendSourceSlots(
        fragmentSource: source
    ).overlayAlphaPreserving
}

private func lowered(
    _ msl: String,
    authored: String,
    premultipliedColorInputSlots: Set<Int> = []
) -> String? {
    guard let prepared = try? SceneGenericShaderArtifactBuilder
        .prepareColorTransfer(msl: msl, authoredSource: authored) else {
        return nil
    }
    guard !premultipliedColorInputSlots.isEmpty else { return prepared.msl }
    return SceneGenericShaderArtifactBuilder.lowerPremultipliedColorInputs(
        prepared.msl,
        slots: premultipliedColorInputSlots
    )
}

private func profile(
    authored: String,
    active: Set<Int>,
    graphInputs: Set<Int>,
    graphTargets: Set<Int> = [],
    typedStatic: Set<Int> = [],
    preservedChannels: Set<Int> = [],
    premultipliedColor: Set<Int> = [],
    provider: Bool = false
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        fragmentSource: authored,
        colorTransfer: transfer(authored),
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        overlayAlphaBlendSourceSlot: overlayAlpha(authored)?.source,
        overlayAlphaBlendAuxiliarySlot: overlayAlpha(authored)?.overlay,
        overlayAlphaPreservingBlendSourceSlot:
            overlayAlphaPreserving(authored)?.source,
        overlayAlphaPreservingBlendAuxiliarySlot:
            overlayAlphaPreserving(authored)?.overlay,
        associatedOverBlendSourceSlot: fact(authored)?.sourceSlot,
        associatedOverBlendOverlaySlot: fact(authored)?.overlaySlot,
        conditionalStraightUnionSourceSlot: nil,
        singleSamplerAlphaMutationSourceSlot: nil,
        sameSlotChannelReconstructionSourceSlot: nil,
        auxiliaryRGBMixSourceSlot: nil,
        normalizedSampleSumSourceSlot: nil,
        alphaWeightedSampleAverageSourceSlot: nil,
        preservedAlphaRGBFilterSourceSlot: nil,
        preservedAlphaRGBFilterTextureSlots: [],
        activeTextureSlots: active,
        typedStaticDataAuxiliarySlots: typedStatic,
        preservedChannelsExternalProviderTextureSlots: preservedChannels,
        premultipliedColorAuxiliarySlots: premultipliedColor,
        unitCompositeBlurredSlot: nil,
        unitCompositePreviousSlot: nil,
        hasExternalProviderTexture: provider,
        producesScalarRedOutput: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: graphTargets,
        graphInputTextureSlots: graphInputs,
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false
    )
}

private func compileMetal(_ fragment: String) -> String {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec4 v_TexCoord;
    void main() {
        v_TexCoord = vec4(a_TexCoord, a_TexCoord);
        gl_Position = vec4(a_Position, 1.0);
    }
    """
    return SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex,
        fragmentSource: fragment
    ).program?.metalSource ?? ""
}

@main
private enum Harness {
    static func main() throws {
        let positive = fact(authored)
        let renamed = fact(renamedAuthored)
        let metal = compileMetal(authored)
        let loweredMSL = lowered(compilerMSL, authored: authored)
        let writeAlphaOff = authored.replacingOccurrences(
            of: associatedOverHelper,
            with: """
            vec4 Composite(vec4 albedo, vec4 blendColors, float blendAlpha) {
                blendAlpha *= blendColors.a;
                albedo.rgb = mix(albedo.rgb, blendColors.rgb, blendAlpha);
                return albedo;
            }
            float GetUVBlend(vec2 uv) {
                return 1.0;
            }
            """
        )
        let extraBlend = authored.replacingOccurrences(
            of: "albedo = Composite(albedo, blendColors, blendAlpha);",
            with: """
            albedo = Composite(albedo, blendColors, blendAlpha);
                blendColors = texSample2D(g_Texture1, blendUV);
                albedo = Composite(albedo, blendColors, blendAlpha);
            """
        )
        let overlayAlphaLowered = lowered(
            compilerMSL.replacingOccurrences(
                of: "float4 albedo = g_Texture0.sample(sourceSampler, uv);",
                with: "float4 carrier = g_Texture0.sample(sourceSampler, uv);"
            ).replacingOccurrences(
                of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                with: """
                carrier.xyz = mix(carrier.xyz, blendColors.xyz, blendAlpha);
                    carrier.w = blendColors.w * g_AlphaMultiply;
                """
            ).replacingOccurrences(
                of: "out.mwxFragColor = albedo;",
                with: "out.mwxFragColor = carrier;"
            ),
            authored: overlayAlphaAuthored
        )
        let overlayAlphaPreservingCompilerMSL = compilerMSL
            .replacingOccurrences(
                of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                with: "albedo.xyz = mix(albedo.xyz, blendColors.xyz, blendAlpha);"
            )
        let overlayAlphaPreservingDataLowered = lowered(
            overlayAlphaPreservingCompilerMSL,
            authored: overlayAlphaPreservingAuthored
        )
        let overlayAlphaPreservingPremultipliedLowered = lowered(
            overlayAlphaPreservingCompilerMSL,
            authored: overlayAlphaPreservingAuthored,
            premultipliedColorInputSlots: [1]
        )
        let expected = SceneGenericShaderCapabilityProfile
            .sourceProvenGraphInputAssociatedOverBlend
        let accepted = profile(
            authored: authored,
            active: [0, 1],
            graphInputs: [0],
            typedStatic: [1]
        )
        let graphOverlay = profile(
            authored: authored,
            active: [0, 1],
            graphInputs: [0],
            graphTargets: [1]
        )
        let output = Output(
            sourceSlot: positive?.sourceSlot,
            overlaySlot: positive?.overlaySlot,
            renamedAccepted: renamed?.sourceSlot == 3
                && renamed?.overlaySlot == 2,
            transferAccepted: transfer(authored)
                == .straightAlpha(textureSlot: 0),
            renamedTransferAccepted: transfer(renamedAuthored)
                == .straightAlpha(textureSlot: 3),
            boundedUnpremultipliesSource: metal.contains(
                "mwxUnpremultiply(mwxTexture0.sample"
            ),
            boundedLeavesOverlayData: !metal.contains(
                "mwxUnpremultiply(mwxTexture1.sample"
            ),
            boundedPremultipliesOutput: metal.contains(
                "return mwxPremultiply(mwxFragColor);"
            ),
            loweringAccepted: loweredMSL != nil,
            loweringLeavesOverlayData: loweredMSL?.contains(
                "mwxGenericUnpremultiply(g_Texture1.sample"
            ) == false,
            loweringPremultipliesOutput: loweredMSL?.contains(
                "out.mwxFragColor = mwxGenericPremultiply(albedo);"
            ) == true,
            extraSampleRejected: fact(
                authored.replacingOccurrences(
                    of: "vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);",
                    with: """
                    vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
                        float extra = texSample2D(g_Texture0, v_TexCoord.xy * 0.5).r;
                    """
                )
            ) == nil,
            writeAlphaOffRejected: fact(writeAlphaOff) == nil,
            overlayAlphaNotAssociatedOver: fact(overlayAlphaAuthored) == nil,
            overlayAlphaKeepsStraightTransfer: transfer(overlayAlphaAuthored)
                == .straightAlpha(textureSlot: 0),
            extraBlendCallRejected: fact(extraBlend) == nil,
            controlFlowRejected: fact(
                authored.replacingOccurrences(
                    of: "gl_FragColor = albedo;",
                    with: "if (blendAlpha > 0.0) { gl_FragColor = albedo; }"
                )
            ) == nil,
            helperDriftRejected: fact(
                authored.replacingOccurrences(of: "0.01", with: "0.02")
            ) == nil,
            sameSlotRejected: fact(
                authored.replacingOccurrences(
                    of: "texSample2D(g_Texture1, blendUV)",
                    with: "texSample2D(g_Texture0, blendUV)"
                )
            ) == nil,
            uvHelperDriftRejected: fact(
                authored.replacingOccurrences(
                    of: "return 1.0;",
                    with: "return step(0.99, uv.x);"
                )
            ) == nil,
            extraOutputRejected: fact(
                authored.replacingOccurrences(
                    of: "gl_FragColor = albedo;",
                    with: "gl_FragColor = albedo; gl_FragColor.a = 1.0;"
                )
            ) == nil,
            extraCompilerSampleRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "float blendAlpha = g_ScalarWeight;",
                    with: """
                    float extra = g_Texture0.sample(sourceSampler, uv * 0.5).x;
                        float blendAlpha = g_ScalarWeight + extra;
                    """
                ),
                authored: authored
            ) == nil,
            indirectHelperSideEffectRejected: fact(
                authored.replacingOccurrences(
                    of: "void main() {",
                    with: "void Kill() { discard; }\nvoid main() {"
                ).replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "Kill(); albedo = Composite(albedo, blendColors, blendAlpha);"
                )
            ) == nil,
            compilerDroppedOverlayRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "albedo = albedo;"
                ),
                authored: authored
            ) == nil,
            compilerDroppedSourceContributionRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "albedo = blendColors;"
                ),
                authored: authored
            ) == nil,
            compilerInertOverlayUseRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "albedo = albedo; blendColors = blendColors;"
                ),
                authored: authored
            ) == nil,
            compilerZeroOverlayContributionRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "albedo = albedo + blendColors * 0.0;"
                ),
                authored: authored
            ) == nil,
            compilerWrongBlendFunctionRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "albedo = Passthrough(albedo, blendColors, blendAlpha);"
                ),
                authored: authored
            ) == nil,
            compilerLiteralZeroWeightRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "albedo = Composite(albedo, blendColors, 0.0);"
                ),
                authored: authored
            ) == nil,
            compilerWeightMutationRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "blendAlpha = 0.0;\n    albedo = Composite(albedo, blendColors, blendAlpha);"
                ),
                authored: authored
            ) == nil,
            compilerWeightIncrementRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "++blendAlpha;\n    albedo = Composite(albedo, blendColors, blendAlpha);"
                ),
                authored: authored
            ) == nil,
            compilerOverlayMutationRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "blendColors = float4(0.0);\n    albedo = Composite(albedo, blendColors, blendAlpha);"
                ),
                authored: authored
            ) == nil,
            compilerPostBlendOverwriteRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "albedo = Composite(albedo, blendColors, blendAlpha);\n    albedo = float4(0.0);"
                ),
                authored: authored
            ) == nil,
            compilerZeroWeightInitializerRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "float blendAlpha = g_ScalarWeight;",
                    with: "float blendAlpha = 0.0;"
                ),
                authored: authored
            ) == nil,
            compilerZeroProductInitializerRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "float blendAlpha = g_ScalarWeight;",
                    with: "float blendAlpha = g_ScalarWeight * 0.0;"
                ),
                authored: authored
            ) == nil,
            compilerWrongCarrierRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "out.mwxFragColor = albedo;",
                    with: "out.mwxFragColor = blendColors;"
                ),
                authored: authored
            ) == nil,
            routeProfile: accepted.rawValue,
            graphOverlayRouteProfile: graphOverlay.rawValue,
            routeState: accepted.defaultRouteState.rawValue,
            namedProviderOverlayRouteProfile: profile(
                authored: authored,
                active: [0, 1],
                graphInputs: [0],
                provider: true
            ).rawValue,
            namedProviderOverlayPremultipliedRouteProfile: profile(
                authored: authored,
                active: [0, 1],
                graphInputs: [0],
                premultipliedColor: [1],
                provider: true
            ).rawValue,
            extraProviderRejected: profile(
                authored: authored,
                active: [0, 1],
                graphInputs: [0],
                provider: true
            ).rawValue != expected.rawValue,
            providerRejected: profile(
                authored: authored,
                active: [0, 1],
                graphInputs: [0],
                provider: true
            ).rawValue != expected.rawValue,
            wrongPremultipliedSlotRejected: profile(
                authored: authored,
                active: [0, 1],
                graphInputs: [0],
                premultipliedColor: [2],
                provider: true
            ).rawValue != expected.rawValue,
            missingGraphInputRejected: profile(
                authored: authored,
                active: [0, 1],
                graphInputs: []
            ).rawValue != expected.rawValue,
            overlayAlpha957Accepted: overlayAlpha(
                writeAlphaApplyBlendingAuthored
            )?.source == 0
                && overlayAlpha(writeAlphaApplyBlendingAuthored)?.overlay == 1,
            overlayAlphaNamedProviderRouteProfile: profile(
                authored: overlayAlphaAuthored,
                active: [0, 1],
                graphInputs: [0],
                premultipliedColor: [1],
                provider: true
            ).rawValue,
            overlayAlpha957NamedProviderRouteProfile: profile(
                authored: writeAlphaApplyBlendingAuthored,
                active: [0, 1],
                graphInputs: [0],
                premultipliedColor: [1],
                provider: true
            ).rawValue,
            overlayAlphaNamedProviderLoweringUnpremultipliesOverlay: lowered(
                compilerMSL.replacingOccurrences(
                    of: "float4 albedo = g_Texture0.sample(sourceSampler, uv);",
                    with: "float4 carrier = g_Texture0.sample(sourceSampler, uv);"
                ).replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: """
                    carrier.xyz = mix(carrier.xyz, blendColors.xyz, blendAlpha);
                        carrier.w = blendColors.w * g_AlphaMultiply;
                    """
                ).replacingOccurrences(
                    of: "out.mwxFragColor = albedo;",
                    with: "out.mwxFragColor = carrier;"
                ),
                authored: overlayAlphaAuthored,
                premultipliedColorInputSlots: [1]
            )?.contains(
                "mwxGenericUnpremultiply(g_Texture1.sample"
            ) == true,
            overlayAlphaTypedStaticRouteProfile: profile(
                authored: overlayAlphaAuthored,
                active: [0, 1],
                graphInputs: [0],
                typedStatic: [1]
            ).rawValue,
            overlayAlphaLoweringAccepted: overlayAlphaLowered != nil,
            overlayAlphaLoweringLeavesOverlayData: overlayAlphaLowered?.contains(
                "mwxGenericUnpremultiply(g_Texture1.sample"
            ) == false,
            overlayAlphaLoweringPremultipliesOutput: overlayAlphaLowered?.contains(
                "out.mwxFragColor = mwxGenericPremultiply(carrier);"
            ) == true,
            overlayAlphaMissingAlphaWriteRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "float4 albedo = g_Texture0.sample(sourceSampler, uv);",
                    with: "float4 carrier = g_Texture0.sample(sourceSampler, uv);"
                ).replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: "carrier.xyz = mix(carrier.xyz, blendColors.xyz, blendAlpha);"
                ).replacingOccurrences(
                    of: "out.mwxFragColor = albedo;",
                    with: "out.mwxFragColor = carrier;"
                ),
                authored: overlayAlphaAuthored
            ) == nil,
            overlayAlphaZeroContributionRejected: lowered(
                compilerMSL.replacingOccurrences(
                    of: "float4 albedo = g_Texture0.sample(sourceSampler, uv);",
                    with: "float4 carrier = g_Texture0.sample(sourceSampler, uv);"
                ).replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: """
                    carrier.xyz = mix(carrier.xyz, blendColors.xyz, blendAlpha);
                        carrier.w = blendColors.w * 0.0;
                    """
                ).replacingOccurrences(
                    of: "out.mwxFragColor = albedo;",
                    with: "out.mwxFragColor = carrier;"
                ),
                authored: overlayAlphaAuthored
            ) == nil,
            overlayAlpha957LoweringAccepted: lowered(
                compilerMSL.replacingOccurrences(
                    of: "float blendAlpha = g_ScalarWeight;",
                    with: """
                    float blendAlpha = g_Multiply * blendColors.w;
                    """
                ).replacingOccurrences(
                    of: "albedo = Composite(albedo, blendColors, blendAlpha);",
                    with: """
                    albedo.rgb = mix(albedo.rgb, blendColors.rgb, blendAlpha);
                        albedo.a = blendColors.a * g_AlphaMultiply;
                    """
                ),
                authored: writeAlphaApplyBlendingAuthored
            ) != nil,
            overlayAlphaPreservingAccepted:
                overlayAlphaPreserving(overlayAlphaPreservingAuthored)?.source == 0
                && overlayAlphaPreserving(
                    overlayAlphaPreservingAuthored
                )?.overlay == 1,
            overlayAlphaPreservingTransferAccepted:
                transfer(overlayAlphaPreservingAuthored)
                    == .straightAlphaPreserving(textureSlot: 0),
            overlayAlphaPreservingDataRouteProfile: profile(
                authored: overlayAlphaPreservingAuthored,
                active: [0, 1],
                graphInputs: [0],
                preservedChannels: [1],
                provider: true
            ).rawValue,
            overlayAlphaPreservingPremultipliedRouteProfile: profile(
                authored: overlayAlphaPreservingAuthored,
                active: [0, 1],
                graphInputs: [0],
                premultipliedColor: [1],
                provider: true
            ).rawValue,
            overlayAlphaPreservingDataLoweringAccepted:
                overlayAlphaPreservingDataLowered != nil,
            overlayAlphaPreservingDataLoweringLeavesOverlayData:
                overlayAlphaPreservingDataLowered?.contains(
                    "mwxGenericUnpremultiply(g_Texture1.sample"
                ) == false,
            overlayAlphaPreservingPremultipliedLoweringUnpremultipliesOverlay:
                overlayAlphaPreservingPremultipliedLowered?.contains(
                    "mwxGenericUnpremultiply(g_Texture1.sample"
                ) == true,
            overlayAlphaPreservingAlphaMutationRejected:
                overlayAlphaPreserving(
                    overlayAlphaPreservingAuthored.replacingOccurrences(
                        of: "    gl_FragColor = albedo;",
                        with: "    albedo.a = 1.0;\n    gl_FragColor = albedo;"
                    )
                ) == nil
        )
        print(String(
            data: try JSONEncoder().encode(output),
            encoding: .utf8
        )!)
    }
}
'''


class SceneAssociatedOverBlendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-associated-over-"
        )
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        cls.binary = root / "harness"
        harness.write_text(HARNESS, encoding="utf-8")
        compiled = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-O",
                "-o",
                str(cls.binary),
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compiled.returncode != 0:
            raise AssertionError(compiled.stderr)
        executed = subprocess.run(
            [str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if executed.returncode != 0:
            raise AssertionError(executed.stderr)
        cls.result = json.loads(executed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_stock_writealpha_shape_is_straight_alpha_on_the_shared_chain(
        self,
    ) -> None:
        self.assertEqual(self.result["sourceSlot"], 0)
        self.assertEqual(self.result["overlaySlot"], 1)
        self.assertTrue(self.result["renamedAccepted"])
        self.assertTrue(self.result["transferAccepted"])
        self.assertTrue(self.result["renamedTransferAccepted"])
        self.assertTrue(self.result["boundedUnpremultipliesSource"])
        self.assertTrue(self.result["boundedLeavesOverlayData"])
        self.assertTrue(self.result["boundedPremultipliesOutput"])
        self.assertTrue(self.result["loweringAccepted"])
        self.assertTrue(self.result["loweringLeavesOverlayData"])
        self.assertTrue(self.result["loweringPremultipliesOutput"])
        self.assertEqual(
            self.result["routeProfile"],
            "source-proven-graph-input-associated-over-blend",
        )
        self.assertNotEqual(
            self.result["graphOverlayRouteProfile"],
            "source-proven-graph-input-associated-over-blend",
        )
        self.assertNotEqual(
            self.result["namedProviderOverlayRouteProfile"],
            "source-proven-graph-input-associated-over-blend",
        )
        self.assertEqual(
            self.result["namedProviderOverlayPremultipliedRouteProfile"],
            "source-proven-graph-input-associated-over-blend",
        )
        self.assertEqual(self.result["routeState"], "prefer-generic")
        self.assertTrue(self.result["overlayAlpha957Accepted"])
        self.assertEqual(
            self.result["overlayAlphaNamedProviderRouteProfile"],
            "source-proven-graph-input-overlay-alpha-blend",
        )
        self.assertEqual(
            self.result["overlayAlpha957NamedProviderRouteProfile"],
            "source-proven-graph-input-overlay-alpha-blend",
        )
        self.assertTrue(
            self.result["overlayAlphaNamedProviderLoweringUnpremultipliesOverlay"]
        )
        self.assertEqual(
            self.result["overlayAlphaTypedStaticRouteProfile"],
            "source-proven-graph-input-overlay-alpha-blend",
        )
        self.assertTrue(self.result["overlayAlphaLoweringAccepted"])
        self.assertTrue(self.result["overlayAlphaLoweringLeavesOverlayData"])
        self.assertTrue(self.result["overlayAlphaLoweringPremultipliesOutput"])
        self.assertTrue(self.result["overlayAlphaMissingAlphaWriteRejected"])
        self.assertTrue(self.result["overlayAlphaZeroContributionRejected"])
        self.assertTrue(self.result["overlayAlpha957LoweringAccepted"])
        self.assertTrue(self.result["overlayAlphaPreservingAccepted"])
        self.assertTrue(self.result["overlayAlphaPreservingTransferAccepted"])
        preserving_profile = (
            "source-proven-graph-input-overlay-color-blend-alpha-preserving"
        )
        self.assertEqual(
            self.result["overlayAlphaPreservingDataRouteProfile"],
            preserving_profile,
        )
        self.assertEqual(
            self.result["overlayAlphaPreservingPremultipliedRouteProfile"],
            preserving_profile,
        )
        self.assertTrue(
            self.result["overlayAlphaPreservingDataLoweringAccepted"]
        )
        self.assertTrue(
            self.result["overlayAlphaPreservingDataLoweringLeavesOverlayData"]
        )
        self.assertTrue(
            self.result[
                "overlayAlphaPreservingPremultipliedLoweringUnpremultipliesOverlay"
            ]
        )
        self.assertTrue(
            self.result["overlayAlphaPreservingAlphaMutationRejected"]
        )

    def test_unproven_dataflow_and_foreign_blend_forms_fail_closed(self) -> None:
        for key in (
            "extraSampleRejected",
            "writeAlphaOffRejected",
            "overlayAlphaNotAssociatedOver",
            "overlayAlphaKeepsStraightTransfer",
            "extraBlendCallRejected",
            "controlFlowRejected",
            "helperDriftRejected",
            "sameSlotRejected",
            "uvHelperDriftRejected",
            "extraOutputRejected",
            "extraCompilerSampleRejected",
            "indirectHelperSideEffectRejected",
            "compilerDroppedOverlayRejected",
            "compilerDroppedSourceContributionRejected",
            "compilerInertOverlayUseRejected",
            "compilerZeroOverlayContributionRejected",
            "compilerWrongBlendFunctionRejected",
            "compilerLiteralZeroWeightRejected",
            "compilerWeightMutationRejected",
            "compilerWeightIncrementRejected",
            "compilerOverlayMutationRejected",
            "compilerPostBlendOverwriteRejected",
            "compilerZeroWeightInitializerRejected",
            "compilerZeroProductInitializerRejected",
            "compilerWrongCarrierRejected",
            "providerRejected",
            "wrongPremultipliedSlotRejected",
            "extraProviderRejected",
            "missingGraphInputRejected",
        ):
            self.assertTrue(self.result[key], key)


if __name__ == "__main__":
    unittest.main()
