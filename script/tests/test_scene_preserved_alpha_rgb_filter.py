#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderArtifactCache.swift",
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let analyzedTransfer: String
    let sourceSlot: Int?
    let fullColorSampleCounts: [Int: Int]?
    let rgbColorSampleCounts: [Int: Int]?
    let dataSampleCounts: [Int: Int]?
    let boundedSourceSamplesUnpremultiplied: Int
    let boundedBaseSamplesUnpremultiplied: Int
    let boundedDataSamplesUnpremultiplied: Int
    let boundedOutputPremultiplied: Bool
    let directLoweringAccepted: Bool
    let staticLoopWork: Int?
    let positiveKind: String?
    let positiveSlot: Int?
    let genericSourceSamplesUnpremultiplied: Int
    let genericBaseSamplesUnpremultiplied: Int
    let genericDataSamplesUnpremultiplied: Int
    let genericOutputPremultiplied: Bool
    let routeProfile: String
    let routeState: String
    let fallbackOwner: String
    let booleanArithmeticCasted: Bool
    let booleanConditionPreserved: Bool
    let compoundBooleanArithmeticPreserved: Bool
    let renamedLocalsAccepted: Bool
    let alphaWriteRejected: Bool
    let hiddenSampleRejected: Bool
    let unprojectedDataRejected: Bool
    let wrongColorSlotRejected: Bool
    let baseAlphaOutputRejected: Bool
    let postBlendWriteRejected: Bool
    let compilerSampleDriftRejected: Bool
    let compilerColorProjectionDriftRejected: Bool
    let compilerDataProjectionDriftRejected: Bool
    let helperConflictRejected: Bool
    let descendingLoopRejected: Bool
    let dynamicLoopRejected: Bool
    let oversizedLoopRejected: Bool
    let helperAnalyzed: Bool
    let helperSourceSlot: Int?
    let helperFullColorSampleCounts: [Int: Int]?
    let helperRGBColorSampleCounts: [Int: Int]?
    let helperDataSampleCounts: [Int: Int]?
    let helperArtifactAccepted: Bool
    let helperBoundedSourceSamplesUnpremultiplied: Int
    let helperBoundedDataSamplesUnpremultiplied: Int
    let helperGenericSourceSamplesUnpremultiplied: Int
    let helperGenericDataSamplesUnpremultiplied: Int
    let helperWrongAlphaRejected: Bool
    let helperWrongColorSlotRejected: Bool
    let helperHiddenSampleRejected: Bool
    let helperOutParameterRejected: Bool
    let helperGlobalWriteRejected: Bool
    let helperHiddenRecursionRejected: Bool
    let helperMutualRecursionRejected: Bool
    let helperDAGRejoinAccepted: Bool
    let helperAtomicRejected: Bool
    let helperUnconditionalReplacementRejected: Bool
    let helperUnprovenResourceCallRejected: Bool
}

@main
private struct PreservedAlphaRGBFilterHarness {
    static func main() throws {
        let vertex = [
            "attribute vec3 a_Position;",
            "attribute vec2 a_TexCoord;",
            "varying vec2 v_TexCoord;",
            "void main() {",
            "    gl_Position = vec4(a_Position, 1.0);",
            "    v_TexCoord = a_TexCoord;",
            "}",
        ].joined(separator: "\n")
        let authored = [
            "uniform sampler2D g_Texture0;",
            "uniform sampler2D g_Texture1;",
            "uniform sampler2D g_Texture2;",
            "uniform float u_Opacity;",
            "varying vec2 v_TexCoord;",
            "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 filtered, in float opacity) {",
            "    return mix(base, filtered, opacity);",
            "}",
            "#define kernel 1",
            "void main() {",
            "    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);",
            "    vec2 depthTex = texSample2D(g_Texture2, v_TexCoord).rg;",
            "    float depth = max(depthTex.x, depthTex.y);",
            "    if (depth > 0.01) {",
            "        vec4 original = albedo;",
            "        for (int i = -kernel; i <= kernel; i++) {",
            "            albedo.rgb += texSample2D(g_Texture0, v_TexCoord + vec2(float(i))).rgb;",
            "        }",
            "        albedo.rgb /= 4.0;",
            "    }",
            "    vec4 baseAlbedo = texSample2D(g_Texture1, v_TexCoord);",
            "    albedo = vec4(ApplyBlending(0, baseAlbedo.rgb, albedo.rgb, u_Opacity * depthTex.x), albedo.a);",
            "    gl_FragColor = albedo;",
            "}",
        ].joined(separator: "\n")
        let fragmentMSL = [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "struct MWXUniforms {};",
            "fragment void f() {",
            "    float4 albedo = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);",
            "    float2 depthTex = g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord).xy;",
            "    if (depth > 0.01) {",
            "        float3 filtered = albedo.xyz + g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord + offset).xyz;",
            "        albedo.x = filtered.x;",
            "        albedo.y = filtered.y;",
            "        albedo.z = filtered.z;",
            "    }",
            "    float4 baseAlbedo = g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord);",
            "    albedo = float4(ApplyBlending(0, baseAlbedo.xyz, albedo.xyz, opacity), albedo.w);",
            "    out.mwxFragColor = albedo;",
            "    return out;",
            "}",
        ].joined(separator: "\n")
        let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"mwxTexture0Transform0","type":"vec4","offset":16},{"name":"mwxTexture0Transform1","type":"vec4","offset":32},{"name":"mwxTexture1Transform0","type":"vec4","offset":48},{"name":"mwxTexture1Transform1","type":"vec4","offset":64},{"name":"mwxTexture2Transform0","type":"vec4","offset":80},{"name":"mwxTexture2Transform1","type":"vec4","offset":96}]}},"ubos":[{"type":"_1","block_size":112,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1},{"name":"g_Texture2","binding":2}]}"#.utf8)
        let helperReflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"mwxTexture3Transform0","type":"vec4","offset":16},{"name":"mwxTexture3Transform1","type":"vec4","offset":32},{"name":"mwxTexture5Transform0","type":"vec4","offset":48},{"name":"mwxTexture5Transform1","type":"vec4","offset":64}]}},"ubos":[{"type":"_1","block_size":80,"set":0,"binding":8}],"textures":[{"name":"g_Texture3","binding":3},{"name":"g_Texture5","binding":5}]}"#.utf8)

        let helperAuthored = [
            "uniform sampler2D g_Texture3;",
            "uniform sampler2D g_Texture5;",
            "varying vec2 v_TexCoord;",
            "vec3 toneCurve(vec3 value) { return value / (1.0 + value); }",
            "#define kernelSampleCount 3",
            "vec3 radialFilter(vec2 coord, vec2 spread) {",
            "    vec3 color = vec3(0.0);",
            "    for (int i = 0; i < kernelSampleCount; i++) {",
            "        color += toneCurve(texSample2D(g_Texture3, coord + spread * float(i)).rgb);",
            "    }",
            "    return color / float(kernelSampleCount);",
            "}",
            "void main() {",
            "    vec4 filtered = texSample2D(g_Texture3, v_TexCoord);",
            "    vec2 control = texSample2D(g_Texture5, v_TexCoord).rg;",
            "    if (control.x > 0.01) {",
            "        filtered = vec4(radialFilter(v_TexCoord, control), filtered.a);",
            "    }",
            "    gl_FragColor = filtered;",
            "}",
        ].joined(separator: "\n")
        let helperCompilerSource = helperAuthored.replacingOccurrences(
            of: "i < kernelSampleCount",
            with: "i < 3"
        )
        let helperMSL = [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "struct MWXUniforms {};",
            "float3 radialFilter(float2 coord, float2 spread) {",
            "    float3 color = g_Texture3.sample(g_Texture3Smplr, (coord + spread)).xyz;",
            "    return color;",
            "}",
            "fragment void f() {",
            "    float4 filtered = g_Texture3.sample(g_Texture3Smplr, in.v_TexCoord);",
            "    float2 control = g_Texture5.sample(g_Texture5Smplr, in.v_TexCoord).xy;",
            "    if (control.x > 0.01) { filtered.xyz = radialFilter(in.v_TexCoord, control); }",
            "    out.mwxFragColor = filtered;",
            "    return out;",
            "}",
        ].joined(separator: "\n")

        func artifact(
            authored source: String,
            compilerSource: String? = nil,
            msl: String,
            reflectionData: Data? = nil
        ) -> SceneGenericShaderProgramArtifact? {
            let built = SceneGenericShaderArtifactBuilder.build(
                requestKey: String(repeating: "b", count: 64),
                backendID: "glslang-spirv-cross-msl-v2",
                stages: [
                    .init(
                        name: "vertex", source: vertex,
                        authoredSource: vertex,
                        msl: "struct MWXUniforms {};",
                        reflection: reflectionData ?? reflection
                    ),
                    .init(
                        name: "fragment", source: compilerSource ?? source,
                        authoredSource: source,
                        msl: msl,
                        reflection: reflectionData ?? reflection
                    ),
                ],
                maximumArtifactBytes: 1_024_000
            )
            guard case let .success(value) = built else { return nil }
            return value
        }

        let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyze(
            fragmentSource: authored
        )
        let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authored
        )
        let analyzedTransfer: String
        if case .straightAlphaPreserving = transfer {
            analyzedTransfer = "straightAlphaPreserving"
        } else {
            analyzedTransfer = "unexpected"
        }
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: authored
        ).program
        let positive = artifact(authored: authored, msl: fragmentMSL)
        let directLowering = fact.flatMap {
            SceneGenericShaderStraightAlphaPreservingLowering
                .lowerPreservedAlphaRGBFilter(
                    fragmentMSL,
                    fullColorSampleCallCounts: $0.fullColorSampleCallCounts,
                    rgbColorSampleCallCounts: $0.rgbColorSampleCallCounts,
                    dataSampleCallCounts: $0.dataSampleCallCounts
                )
        }
        let boundedMetal = bounded?.metalSource ?? ""
        let genericMetal = positive?.program.metalSource ?? ""
        let helperFact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer
            .analyzeAny(fragmentSource: helperAuthored)
        let helperTransfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: helperAuthored
        )
        let helperBounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: helperAuthored
        ).program
        let helperArtifact = artifact(
            authored: helperAuthored,
            compilerSource: helperCompilerSource,
            msl: helperMSL,
            reflectionData: helperReflection
        )
        let helperBoundedMetal = helperBounded?.metalSource ?? ""
        let helperGenericMetal = helperArtifact?.program.metalSource ?? ""

        let profile = SceneGenericShaderCapabilityProfile(
            colorTransfer: .straightAlphaPreserving(textureSlot: 0),
            alphaAttenuationSourceSlot: nil,
            colorBlendSourceSlot: nil,
            conditionalStraightUnionSourceSlot: nil,
            singleSamplerAlphaMutationSourceSlot: nil,
            sameSlotChannelReconstructionSourceSlot: nil,
            auxiliaryRGBMixSourceSlot: nil,
            normalizedSampleSumSourceSlot: nil,
            hasExternalProviderTexture: false,
            producesScalarRedOutput: false,
            isSourceIndependentPremultipliedOutput: false,
            graphTextureSlots: [],
            graphInputTextureSlots: [0],
            r8TextureSlots: [],
            hasDefaultedOpacityMaskSampler: false,
            hasOnlyGraphInputSampler: false,
            hasStageScopedUniformBindings: false,
            hasStereoAudioSpectrumArrays: false,
            hasLocalizedMutableFragmentVarying: false
        )

        let booleanFragment = [
            "uniform float weight;",
            "varying vec2 v_TexCoord;",
            "void main() {",
            "    float value = 1.0;",
            "    value *= (weight < 0.6) * 6.0;",
            "    if (weight < 0.6) { value *= 2.0; }",
            "    value *= (weight + 0.1 < 0.6) * 6.0;",
            "    gl_FragColor = vec4(value);",
            "}",
        ].joined(separator: "\n")
        let normalizedBoolean: String
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertex,
            fragmentSource: booleanFragment,
            maximumStageSourceBytes: 32_768
        ) {
        case let .success(pair): normalizedBoolean = pair.fragment
        case .failure: normalizedBoolean = ""
        }

        func sourceAccepted(_ source: String) -> Bool {
            SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyze(
                fragmentSource: source
            ) != nil
        }
        func helperSourceAccepted(_ source: String) -> Bool {
            SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(
                fragmentSource: source
            ) != nil
        }
        let renamed = authored
            .replacingOccurrences(of: "albedo", with: "filteredColor")
            .replacingOccurrences(of: "baseAlbedo", with: "sceneColor")
            .replacingOccurrences(of: "depthTex", with: "controlPair")
        let compilerSampleDrift = fragmentMSL.replacingOccurrences(
            of: "    out.mwxFragColor = albedo;",
            with: "    float4 hidden = g_Texture0.sample(g_Texture0Smplr, float2(0.5));\n    out.mwxFragColor = albedo;"
        )
        let compilerColorProjectionDrift = fragmentMSL.replacingOccurrences(
            of: ").xyz;", with: ").xy;"
        )
        let compilerDataProjectionDrift = fragmentMSL.replacingOccurrences(
            of: ").xy;", with: ");"
        )
        let helperConflict = fragmentMSL.replacingOccurrences(
            of: "using namespace metal;",
            with: "using namespace metal;\nfloat4 mwxGenericUnpremultiply(float4 value) { return value; }"
        )

        let output = Output(
            analyzedTransfer: analyzedTransfer,
            sourceSlot: fact?.sourceSlot,
            fullColorSampleCounts: fact?.fullColorSampleCallCounts,
            rgbColorSampleCounts: fact?.rgbColorSampleCallCounts,
            dataSampleCounts: fact?.dataSampleCallCounts,
            boundedSourceSamplesUnpremultiplied: boundedMetal.components(
                separatedBy: "mwxUnpremultiply(mwxTexture0.sample("
            ).count - 1,
            boundedBaseSamplesUnpremultiplied: boundedMetal.components(
                separatedBy: "mwxUnpremultiply(mwxTexture1.sample("
            ).count - 1,
            boundedDataSamplesUnpremultiplied: boundedMetal.components(
                separatedBy: "mwxUnpremultiply(mwxTexture2.sample("
            ).count - 1,
            boundedOutputPremultiplied:
                boundedMetal.contains("return mwxPremultiply(mwxFragColor);"),
            directLoweringAccepted: directLowering != nil,
            staticLoopWork: positive?.program.staticLoopWork,
            positiveKind: positive?.program.colorTransfer.kind,
            positiveSlot: positive?.program.colorTransfer.slot,
            genericSourceSamplesUnpremultiplied: genericMetal.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count - 1,
            genericBaseSamplesUnpremultiplied: genericMetal.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture1.sample("
            ).count - 1,
            genericDataSamplesUnpremultiplied: genericMetal.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture2.sample("
            ).count - 1,
            genericOutputPremultiplied: genericMetal.contains(
                "out.mwxFragColor = mwxGenericPremultiply(albedo);"
            ),
            routeProfile: profile.rawValue,
            routeState: profile.defaultRouteState.rawValue,
            fallbackOwner: profile.validatedRollbackOwner.rawValue,
            booleanArithmeticCasted: normalizedBoolean.contains(
                "value *= float(weight < 0.6) * 6.0"
            ),
            booleanConditionPreserved:
                normalizedBoolean.contains("if (weight < 0.6)"),
            compoundBooleanArithmeticPreserved:
                normalizedBoolean.contains("(weight + 0.1 < 0.6) * 6.0")
                && !normalizedBoolean.contains(
                    "float(weight + 0.1 < 0.6)"
                ),
            renamedLocalsAccepted: sourceAccepted(renamed),
            alphaWriteRejected: !sourceAccepted(
                authored.replacingOccurrences(
                    of: "    vec4 baseAlbedo =",
                    with: "    albedo.a *= 0.5;\n    vec4 baseAlbedo ="
                )
            ),
            hiddenSampleRejected: !sourceAccepted(
                authored.replacingOccurrences(
                    of: "    vec4 baseAlbedo =",
                    with: "    vec4 hidden = texSample2D(g_Texture3, v_TexCoord);\n    vec4 baseAlbedo ="
                )
            ),
            unprojectedDataRejected: !sourceAccepted(
                authored.replacingOccurrences(
                    of: "vec2 depthTex = texSample2D(g_Texture2, v_TexCoord).rg;",
                    with: "vec4 depthTex = texSample2D(g_Texture2, v_TexCoord);"
                )
            ),
            wrongColorSlotRejected: !sourceAccepted(
                authored.replacingOccurrences(
                    of: "albedo.rgb += texSample2D(g_Texture0",
                    with: "albedo.rgb += texSample2D(g_Texture1"
                )
            ),
            baseAlphaOutputRejected: !sourceAccepted(
                authored.replacingOccurrences(
                    of: "), albedo.a);", with: "), baseAlbedo.a);"
                )
            ),
            postBlendWriteRejected: !sourceAccepted(
                authored.replacingOccurrences(
                    of: "    gl_FragColor = albedo;",
                    with: "    albedo.rgb *= 0.5;\n    gl_FragColor = albedo;"
                )
            ),
            compilerSampleDriftRejected:
                artifact(authored: authored, msl: compilerSampleDrift) == nil,
            compilerColorProjectionDriftRejected:
                artifact(
                    authored: authored,
                    msl: compilerColorProjectionDrift
                ) == nil,
            compilerDataProjectionDriftRejected:
                artifact(
                    authored: authored,
                    msl: compilerDataProjectionDrift
                ) == nil,
            helperConflictRejected:
                artifact(authored: authored, msl: helperConflict) == nil,
            descendingLoopRejected: artifact(
                authored: authored,
                compilerSource: authored.replacingOccurrences(
                    of: "for (int i = -kernel; i <= kernel; i++)",
                    with: "for (int i = 1; i <= -1; i++)"
                ),
                msl: fragmentMSL
            ) == nil,
            dynamicLoopRejected: artifact(
                authored: authored,
                compilerSource: authored.replacingOccurrences(
                    of: "for (int i = -kernel; i <= kernel; i++)",
                    with: "for (int i = -kernel; i <= g_Count; i++)"
                ),
                msl: fragmentMSL
            ) == nil,
            oversizedLoopRejected: artifact(
                authored: authored,
                compilerSource: authored.replacingOccurrences(
                    of: "for (int i = -kernel; i <= kernel; i++)",
                    with: "for (int i = -32; i <= 32; i++)"
                ),
                msl: fragmentMSL
            ) == nil,
            helperAnalyzed: {
                if case .straightAlphaPreserving = helperTransfer { return true }
                return false
            }(),
            helperSourceSlot: helperFact?.sourceSlot,
            helperFullColorSampleCounts: helperFact?.fullColorSampleCallCounts,
            helperRGBColorSampleCounts: helperFact?.rgbColorSampleCallCounts,
            helperDataSampleCounts: helperFact?.dataSampleCallCounts,
            helperArtifactAccepted: helperArtifact != nil,
            helperBoundedSourceSamplesUnpremultiplied: helperBoundedMetal
                .components(
                    separatedBy: "mwxUnpremultiply(mwxTexture3.sample("
                ).count - 1,
            helperBoundedDataSamplesUnpremultiplied: helperBoundedMetal
                .components(
                    separatedBy: "mwxUnpremultiply(mwxTexture5.sample("
                ).count - 1,
            helperGenericSourceSamplesUnpremultiplied: helperGenericMetal
                .components(
                    separatedBy: "mwxGenericUnpremultiply(g_Texture3.sample("
                ).count - 1,
            helperGenericDataSamplesUnpremultiplied: helperGenericMetal
                .components(
                    separatedBy: "mwxGenericUnpremultiply(g_Texture5.sample("
                ).count - 1,
            helperWrongAlphaRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "radialFilter(v_TexCoord, control), filtered.a",
                    with: "radialFilter(v_TexCoord, control), control.x"
                )
            ),
            helperWrongColorSlotRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "toneCurve(texSample2D(g_Texture3",
                    with: "toneCurve(texSample2D(g_Texture4"
                )
            ),
            helperHiddenSampleRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "vec3 toneCurve",
                    with: "vec3 hidden() { return texSample2D(g_Texture4, vec2(0.0)).rgb; }\nvec3 toneCurve"
                )
            ),
            helperOutParameterRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "vec3 radialFilter(vec2 coord, vec2 spread)",
                    with: "vec3 radialFilter(vec2 coord, out vec2 spread)"
                )
            ),
            helperGlobalWriteRejected: !helperSourceAccepted(
                helperAuthored
                    .replacingOccurrences(
                        of: "uniform sampler2D g_Texture3;",
                        with: "uniform sampler2D g_Texture3;\nvec3 leakedColor;"
                    )
                    .replacingOccurrences(
                        of: "    return color / float(kernelSampleCount);",
                        with: "    leakedColor = color;\n    return color / float(kernelSampleCount);"
                    )
            ),
            helperHiddenRecursionRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "vec3 toneCurve(vec3 value) { return value / (1.0 + value); }",
                    with: "vec3 toneCurve(vec3 value) { if (value.x < 0.0) { value += toneCurve(value); } return value / (1.0 + value); }"
                )
            ),
            helperMutualRecursionRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "vec3 toneCurve(vec3 value) { return value / (1.0 + value); }",
                    with: "vec3 cycleA(vec3 value); vec3 cycleB(vec3 value) { return cycleA(value); } vec3 cycleA(vec3 value) { return cycleB(value); } vec3 toneCurve(vec3 value) { return cycleA(value); }"
                )
            ),
            helperDAGRejoinAccepted: helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "vec3 toneCurve(vec3 value) { return value / (1.0 + value); }",
                    with: "vec3 sharedLeaf(vec3 value) { return value / (1.0 + value); } vec3 leftBranch(vec3 value) { return sharedLeaf(value); } vec3 rightBranch(vec3 value) { return sharedLeaf(value); } vec3 toneCurve(vec3 value) { return leftBranch(value) + rightBranch(value); }"
                )
            ),
            helperAtomicRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "    return color / float(kernelSampleCount);",
                    with: "    atomicAdd(counter, 1);\n    return color / float(kernelSampleCount);"
                )
            ),
            helperUnconditionalReplacementRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: [
                        "    if (control.x > 0.01) {",
                        "        filtered = vec4(radialFilter(v_TexCoord, control), filtered.a);",
                        "    }",
                    ].joined(separator: "\n"),
                    with: "    filtered = vec4(radialFilter(v_TexCoord, control), filtered.a);"
                )
            ),
            helperUnprovenResourceCallRejected: !helperSourceAccepted(
                helperAuthored.replacingOccurrences(
                    of: "    return color / float(kernelSampleCount);",
                    with: "    color += texture(g_Texture3, coord).rgb;\n    return color / float(kernelSampleCount);"
                )
            )
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class ScenePreservedAlphaRGBFilterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "PreservedAlphaRGBFilterHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "preserved-alpha-rgb-filter-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(
            build_root / "clang-module-cache"
        )
        environment["SWIFT_MODULECACHE_PATH"] = str(
            build_root / "swift-module-cache"
        )
        subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Security",
                "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def test_source_artifact_route_and_failure_boundaries(self):
        self.maxDiff = None
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "analyzedTransfer": "straightAlphaPreserving",
            "sourceSlot": 0,
            "fullColorSampleCounts": {"0": 1, "1": 1},
            "rgbColorSampleCounts": {"0": 1},
            "dataSampleCounts": {"2": 1},
            "boundedSourceSamplesUnpremultiplied": 2,
            "boundedBaseSamplesUnpremultiplied": 1,
            "boundedDataSamplesUnpremultiplied": 0,
            "boundedOutputPremultiplied": True,
            "directLoweringAccepted": True,
            "staticLoopWork": 3,
            "positiveKind": "straight-alpha-preserving",
            "positiveSlot": 0,
            "genericSourceSamplesUnpremultiplied": 2,
            "genericBaseSamplesUnpremultiplied": 1,
            "genericDataSamplesUnpremultiplied": 0,
            "genericOutputPremultiplied": True,
            "routeProfile":
                "source-proven-graph-input-straight-alpha-preserving",
            "routeState": "prefer-generic",
            "fallbackOwner": "bounded-frontend",
            "booleanArithmeticCasted": True,
            "booleanConditionPreserved": True,
            "compoundBooleanArithmeticPreserved": True,
            "renamedLocalsAccepted": True,
            "alphaWriteRejected": True,
            "hiddenSampleRejected": True,
            "unprojectedDataRejected": True,
            "wrongColorSlotRejected": True,
            "baseAlphaOutputRejected": True,
            "postBlendWriteRejected": True,
            "compilerSampleDriftRejected": True,
            "compilerColorProjectionDriftRejected": True,
            "compilerDataProjectionDriftRejected": True,
            "helperConflictRejected": True,
            "descendingLoopRejected": True,
            "dynamicLoopRejected": True,
            "oversizedLoopRejected": True,
            "helperAnalyzed": True,
            "helperSourceSlot": 3,
            "helperFullColorSampleCounts": {"3": 1},
            "helperRGBColorSampleCounts": {"3": 1},
            "helperDataSampleCounts": {"5": 1},
            "helperArtifactAccepted": True,
            "helperBoundedSourceSamplesUnpremultiplied": 2,
            "helperBoundedDataSamplesUnpremultiplied": 0,
            "helperGenericSourceSamplesUnpremultiplied": 2,
            "helperGenericDataSamplesUnpremultiplied": 0,
            "helperWrongAlphaRejected": True,
            "helperWrongColorSlotRejected": True,
            "helperHiddenSampleRejected": True,
            "helperOutParameterRejected": True,
            "helperGlobalWriteRejected": True,
            "helperHiddenRecursionRejected": True,
            "helperMutualRecursionRejected": True,
            "helperDAGRejoinAccepted": True,
            "helperAtomicRejected": True,
            "helperUnconditionalReplacementRejected": True,
            "helperUnprovenResourceCallRejected": True,
        })


if __name__ == "__main__":
    unittest.main()
