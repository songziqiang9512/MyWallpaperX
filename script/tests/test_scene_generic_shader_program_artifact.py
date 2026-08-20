#!/usr/bin/env python3

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources
from scene_shader_compiler_artifact import build_program_artifact


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderCompilerBundle.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderCompilerProcess.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderSourceNormalizer.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderArtifactBuilder.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderArtifactBuilder+StageUniforms.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStraightAlphaPreservingLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderBoundedLoopWork.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderCompiler.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderArtifactCache.swift",
]

CACHE_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderArtifactCache.swift"
)

HARNESS = r"""
import Foundation

private struct Output: Codable {
    let status: String
    let code: String?
    let requestKey: String
    let permitsBoundedFrontend: Bool?
    let backend: String?
    let uniformBufferIndex: Int?
    let uniformNames: [String]?
    let textureSlots: [Int]?
    let colorTransfer: String?
    let fragmentOutputChannelUse: String?
    let routeProfile: String?
    let routeState: String?
    let fallbackOwner: String?
}

private struct CoordinatorOutput: Codable {
    let operationCount: Int
    let firstSource: String
    let repeatedSource: String
    let independentSource: String
    let firstFailed: Bool
    let repeatedFailed: Bool
    let independentSucceeded: Bool
}

private struct BuilderOutput: Codable {
    let positiveKind: String?
    let positiveSlots: [Int]?
    let unprovenOutputChannelUse: String?
    let positiveFailure: String?
    let vectorWeightRejected: Bool
    let mutatedColorRejected: Bool
}

private struct StraightPreservingBuilderOutput: Codable {
    let positiveKind: String?
    let positiveSlot: Int?
    let sampleUnpremultiplied: Bool
    let outputPremultiplied: Bool
    let helperPairPresent: Bool
    let wrongSlotRejected: Bool
    let helperConflictRejected: Bool
    let composedKind: String?
    let composedFailure: String?
    let composedSampleCount: Int
    let composedOutputPremultiplied: Bool
    let composedMetal: String?
    let unrelatedAlphaRejected: Bool
    let mixedSlotRejected: Bool
}

private struct StraightAttenuationBuilderOutput: Codable {
    let analyzedTransfer: String
    let positiveKind: String?
    let positiveSlot: Int?
    let wholeColorAttenuated: Bool
    let unrelatedAlphaReadRejected: Bool
    let wholeVectorUseRejected: Bool
    let rgbWriteRejected: Bool
}

private struct ConditionalStraightBuilderOutput: Codable {
    let positiveKind: String?
    let positiveSlot: Int?
    let unpremultipliedSamples: Int
    let terminalPremultiply: Bool
    let missingSampleRejected: Bool
    let wrongAlphaWriteRejected: Bool
    let outputReadRejected: Bool
    let helperConflictRejected: Bool
}

private struct PositionInputOutput: Codable {
    let directUsesClipSpace: Bool
    let directAvoidsTargetPixels: Bool
    let projectedUsesTargetPixels: Bool
}

private struct VaryingLinkOutput: Codable {
    let deadMismatchAccepted: Bool
    let deadFragmentInterfaceRemoved: Bool
    let liveMismatchRejected: Bool
}

private struct TypedMixNormalizationOutput: Codable {
    let firstWideArgumentNarrowed: Bool
    let secondWideArgumentNarrowed: Bool
    let vec2ArgumentNarrowed: Bool
    let explicitSwizzlePreserved: Bool
    let userDefinedMixPreserved: Bool
    let invalidWeightPreserved: Bool
}

private func colorTransferName(_ transfer: SceneShaderColorTransfer) -> String {
    switch transfer {
    case .passthrough: return "passthrough"
    case .interpolatedColor: return "interpolatedColor"
    case .straightAlpha: return "straightAlpha"
    case .straightAlphaPreserving: return "straightAlphaPreserving"
    case .premultipliedAlpha: return "premultipliedAlpha"
    case .opaque: return "opaque"
    default: return "other"
    }
}

@main
private struct GenericShaderArtifactHarness {
    static func main() throws {
        if CommandLine.arguments[1] == "--normalizer-typed-mix" {
            let vertex = [
                "attribute vec3 a_Position;",
                "attribute vec2 a_TexCoord;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    gl_Position = vec4(a_Position, 1.0);",
                "    v_TexCoord = a_TexCoord;",
                "}",
            ].joined(separator: "\n")
            func normalized(_ expression: String, prelude: [String] = []) -> String {
                let fragment = ([
                    "varying vec2 v_TexCoord;",
                    "uniform sampler2D g_Texture0;",
                ] + prelude + [
                    "void main() {",
                    "    vec4 source = texSample2D(g_Texture0, v_TexCoord);",
                    "    vec3 replacement = vec3(0.25);",
                    "    vec2 replacement2 = vec2(0.5);",
                    "    float weight = 0.5;",
                    "    vec2 invalidWeight = vec2(0.5);",
                    "    \(expression)",
                    "    gl_FragColor = source;",
                    "}",
                ]).joined(separator: "\n")
                switch SceneGenericShaderSourceNormalizer.normalize(
                    vertexSource: vertex,
                    fragmentSource: fragment,
                    maximumStageSourceBytes: 64 * 1_024
                ) {
                case let .success(pair): return pair.fragment
                case .failure: return ""
                }
            }
            let first = normalized(
                "source.rgb = mix(source, replacement, weight);"
            )
            let second = normalized(
                "source.rgb = mix(replacement, source, weight);"
            )
            let vec2 = normalized(
                "source.rg = mix(source, replacement2, weight);"
            )
            let explicit = normalized(
                "source.rgb = mix(source.rgb, replacement, weight);"
            )
            let userDefined = normalized(
                "source.rgb = mix(source, replacement, weight);",
                prelude: [
                    "vec3 mix(vec4 base, vec3 replacement, float weight) {",
                    "    return replacement;",
                    "}",
                ]
            )
            let invalidWeight = normalized(
                "source.rgb = mix(source, replacement, invalidWeight);"
            )
            let output = TypedMixNormalizationOutput(
                firstWideArgumentNarrowed: first.contains(
                    "source . rgb = mix ( source . xyz , replacement , weight )"
                ) || first.contains(
                    "source.rgb = mix(source.xyz, replacement, weight)"
                ),
                secondWideArgumentNarrowed: second.contains(
                    "mix ( replacement , source . xyz , weight )"
                ) || second.contains(
                    "mix(replacement, source.xyz, weight)"
                ),
                vec2ArgumentNarrowed: vec2.contains(
                    "mix ( source . xy , replacement2 , weight )"
                ) || vec2.contains(
                    "mix(source.xy, replacement2, weight)"
                ),
                explicitSwizzlePreserved:
                    explicit.contains(
                        "source.rgb = mix(source.rgb, replacement, weight)"
                    )
                    && !explicit.contains("source.rgb.xyz"),
                userDefinedMixPreserved:
                    userDefined.contains("mix(source, replacement, weight)")
                    && !userDefined.contains("mix(source.xyz, replacement, weight)"),
                invalidWeightPreserved:
                    invalidWeight.contains("mix(source, replacement, invalidWeight)")
                    && !invalidWeight.contains("mix(source.xyz, replacement, invalidWeight)")
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--normalizer-varying-link" {
            let vertex = [
                "attribute vec3 a_Position;",
                "attribute vec2 a_TexCoord;",
                "varying vec2 v_Live;",
                "varying vec2 v_Optional;",
                "void main() {",
                "    gl_Position = vec4(a_Position, 1.0);",
                "    v_Live = a_TexCoord;",
                "    v_Optional = a_TexCoord;",
                "}",
            ].joined(separator: "\n")
            let deadFragment = [
                "varying vec2 v_Live;",
                "varying vec4 v_Optional;",
                "void main() { gl_FragColor = vec4(v_Live, 0.0, 1.0); }",
            ].joined(separator: "\n")
            let liveFragment = deadFragment.replacingOccurrences(
                of: "vec4(v_Live, 0.0, 1.0)",
                with: "v_Optional"
            )
            let dead: SceneGenericShaderSourceNormalizer.Pair?
            switch SceneGenericShaderSourceNormalizer.normalize(
                vertexSource: vertex,
                fragmentSource: deadFragment,
                maximumStageSourceBytes: 64 * 1_024
            ) {
            case let .success(pair): dead = pair
            case .failure: dead = nil
            }
            let liveMismatchRejected: Bool
            switch SceneGenericShaderSourceNormalizer.normalize(
                vertexSource: vertex,
                fragmentSource: liveFragment,
                maximumStageSourceBytes: 64 * 1_024
            ) {
            case .success: liveMismatchRejected = false
            case .failure(.varyingUnsupported): liveMismatchRejected = true
            case .failure: liveMismatchRejected = false
            }
            let output = VaryingLinkOutput(
                deadMismatchAccepted: dead != nil,
                deadFragmentInterfaceRemoved:
                    dead?.fragment.contains("in vec4 v_Optional") == false,
                liveMismatchRejected: liveMismatchRejected
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--normalizer-position" {
            let fragment = [
                "varying vec2 v_TexCoord;",
                "uniform sampler2D g_Texture0;",
                "void main() {",
                "    gl_FragColor = texture(g_Texture0, v_TexCoord);",
                "}",
            ].joined(separator: "\n")
            func normalized(_ vertex: String) throws -> String {
                switch SceneGenericShaderSourceNormalizer.normalize(
                    vertexSource: vertex,
                    fragmentSource: fragment,
                    maximumStageSourceBytes: 64 * 1_024
                ) {
                case let .success(pair): return pair.vertex
                case let .failure(failure): throw failure
                }
            }
            let direct = try normalized([
                "attribute vec3 a_Position;",
                "attribute vec2 a_TexCoord;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    gl_Position = vec4(a_Position, 1.0);",
                "    v_TexCoord = a_TexCoord;",
                "}",
            ].joined(separator: "\n"))
            let projected = try normalized([
                "uniform mat4 g_ModelViewProjectionMatrix;",
                "attribute vec3 a_Position;",
                "attribute vec2 a_TexCoord;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    gl_Position = mul(",
                "        vec4(a_Position, 1.0),",
                "        g_ModelViewProjectionMatrix);",
                "    v_TexCoord = a_TexCoord;",
                "}",
            ].joined(separator: "\n"))
            let output = PositionInputOutput(
                directUsesClipSpace: direct.contains(
                    "mwxPosition * 2.0 - vec2(1.0)"
                ),
                directAvoidsTargetPixels: !direct.contains(
                    "(mwxPosition - vec2(0.5)) * mwxRenderSize"
                ),
                projectedUsesTargetPixels: projected.contains(
                    "(mwxPosition - vec2(0.5)) * mwxRenderSize"
                )
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-interpolation" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"rate","type":"float","offset":0},{"name":"mwxRenderSize","type":"vec2","offset":8}]}},"ubos":[{"type":"_1","block_size":16,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float rate; float2 mwxRenderSize; };"
            let fragmentMSL = [
                "struct MWXUniforms { float rate; float2 mwxRenderSize; };",
                "fragment void f() {",
                "    float4 current = g_Texture0.sample(sourceSampler, uv);",
                "    float4 history = g_Texture1.sample(historySampler, uv);",
                "    float rate = uniforms.rate;",
                // SPIRV-Cross may make the scalar overload explicit. The
                // material color contract must not depend on this spelling.
                "    out.mwxFragColor = mix(history, current, float4(rate));",
                "}",
            ].joined(separator: "\n")
            let authoredInterpolation = [
                "uniform sampler2D g_Texture0;",
                "uniform sampler2D g_Texture1;",
                "uniform float g_Amount;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    vec4 presentColor = texSample2D(g_Texture0, v_TexCoord);",
                "    vec4 retainedColor = texSample2D(g_Texture1, v_TexCoord);",
                "    float blendAmount = g_Amount;",
                "    gl_FragColor = mix(retainedColor, presentColor, blendAmount);",
                "}",
            ].joined(separator: "\n")
            func build(
                _ fragment: String,
                authoredFragment: String
            ) -> Result<
                SceneGenericShaderProgramArtifact,
                SceneGenericShaderArtifactBuilder.Failure
            > {
                SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "a", count: 64),
                    backendID: "glslang-spirv-cross-msl-v1",
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL, reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: authoredFragment,
                            authoredSource: authoredFragment,
                            msl: fragment, reflection: reflection
                        ),
                    ],
                    maximumArtifactBytes: 1_024_000
                )
            }
            let positiveKind: String?
            let positiveSlots: [Int]?
            let unprovenOutputChannelUse: String?
            let positiveFailure: String?
            switch build(fragmentMSL, authoredFragment: authoredInterpolation) {
            case let .success(artifact):
                positiveKind = artifact.program.colorTransfer.kind
                positiveSlots = artifact.program.colorTransfer.slots
                unprovenOutputChannelUse = artifact.program.fragmentOutputChannelUse
                positiveFailure = nil
            case let .failure(failure):
                positiveKind = nil
                positiveSlots = nil
                unprovenOutputChannelUse = nil
                positiveFailure = String(describing: failure)
            }
            let vectorWeightRejected = failedColorTransfer(build(
                fragmentMSL,
                authoredFragment: authoredInterpolation.replacingOccurrences(
                    of: "float blendAmount = g_Amount;",
                    with: "vec2 blendAmount = vec2(g_Amount);"
                )
            ))
            let mutatedColorRejected = failedColorTransfer(build(
                fragmentMSL,
                authoredFragment: authoredInterpolation.replacingOccurrences(
                    of: "vec4 retainedColor =",
                    with: "presentColor *= 0.5;\n    vec4 retainedColor ="
                )
            ))
            let output = BuilderOutput(
                positiveKind: positiveKind,
                positiveSlots: positiveSlots,
                unprovenOutputChannelUse: unprovenOutputChannelUse,
                positiveFailure: positiveFailure,
                vectorWeightRejected: vectorWeightRejected,
                mutatedColorRejected: mutatedColorRejected
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-straight-preserving" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0}]}},"ubos":[{"type":"_1","block_size":8,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float2 mwxRenderSize; };"
            let fragmentMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float2 mwxRenderSize; };",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 albedo = g_Texture0.sample(sourceSampler, uv);",
                "    float signal = g_Texture1.sample(signalSampler, uv).x;",
                "    albedo.xyz *= signal;",
                "    out.mwxFragColor = albedo;",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            let authored = [
                "uniform sampler2D g_Texture0;",
                "uniform sampler2D g_Texture1;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);",
                "    float signal = texSample2D(g_Texture1, v_TexCoord).r;",
                "    albedo.rgb *= signal;",
                "    gl_FragColor = albedo;",
                "}",
            ].joined(separator: "\n")
            let composedMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float2 mwxRenderSize; };",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 scene = g_Texture0.sample(sourceSampler, uv);",
                "    float4 rValue = g_Texture0.sample(sourceSampler, uv);",
                "    float4 gValue = g_Texture0.sample(sourceSampler, uv);",
                "    float4 bValue = g_Texture0.sample(sourceSampler, uv);",
                "    float signal = g_Texture1.sample(signalSampler, uv).x;",
                "    float3 finalColor = scene.rgb;",
                "    finalColor = mix(finalColor, rValue.rgb, 0.5);",
                "    finalColor += gValue.rgb * 0.1 + bValue.rgb * 0.1 + signal;",
                "    float alpha = scene.w;",
                "    out.mwxFragColor = float4(finalColor, alpha);",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            func build(_ msl: String) -> Result<
                SceneGenericShaderProgramArtifact,
                SceneGenericShaderArtifactBuilder.Failure
            > {
                SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "b", count: 64),
                    backendID: "glslang-spirv-cross-msl-v1",
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL, reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: authored,
                            authoredSource: authored,
                            msl: msl, reflection: reflection
                        ),
                    ],
                    maximumArtifactBytes: 1_024_000
                )
            }
            let positive: SceneGenericShaderProgramArtifact?
            switch build(fragmentMSL) {
            case let .success(artifact): positive = artifact
            case .failure: positive = nil
            }
            let metal = positive?.program.metalSource ?? ""
            let composed: SceneGenericShaderProgramArtifact?
            let composedFailure: String?
            switch build(composedMSL) {
            case let .success(artifact): composed = artifact; composedFailure = nil
            case let .failure(failure): composed = nil; composedFailure = String(describing: failure)
            }
            let composedMetal = composed?.program.metalSource ?? ""
            let unrelatedAlphaRejected = failedColorTransfer(build(
                composedMSL.replacingOccurrences(
                    of: "float alpha = scene.w;",
                    with: "float alpha = g_Texture1.sample(signalSampler, uv).w;"
                )
            ))
            let mixedSlotRejected = failedColorTransfer(build(
                composedMSL.replacingOccurrences(
                    of: "float4 scene = g_Texture0.sample",
                    with: "float4 scene = g_Texture1.sample"
                )
            ))
            let output = StraightPreservingBuilderOutput(
                positiveKind: positive?.program.colorTransfer.kind,
                positiveSlot: positive?.program.colorTransfer.slot,
                sampleUnpremultiplied: metal.contains(
                    "mwxGenericUnpremultiply(g_Texture0.sample(sourceSampler, uv))"
                ),
                outputPremultiplied: metal.contains(
                    "out.mwxFragColor = mwxGenericPremultiply(albedo);"
                ),
                helperPairPresent:
                    metal.contains("inline float4 mwxGenericUnpremultiply")
                    && metal.contains("inline float4 mwxGenericPremultiply"),
                wrongSlotRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "float4 albedo = g_Texture0.sample",
                        with: "float4 albedo = g_Texture1.sample"
                    )
                )),
                helperConflictRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "using namespace metal;",
                        with: "using namespace metal;\nfloat4 mwxGenericPremultiply(float4 value);"
                    )
                )),
                composedKind: composed?.program.colorTransfer.kind,
                composedFailure: composedFailure,
                composedSampleCount: composedMetal.components(separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample").count - 1,
                composedOutputPremultiplied: composedMetal.contains(
                    "out.mwxFragColor = mwxGenericPremultiply(float4(finalColor, alpha));"
                ),
                composedMetal: composed?.program.metalSource,
                unrelatedAlphaRejected: unrelatedAlphaRejected,
                mixedSlotRejected: mixedSlotRejected
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-straight-attenuation" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0}]},"_2":{"members":[]}},"ubos":[{"type":"_1","block_size":8,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float2 mwxRenderSize; };"
            let fragmentMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float2 mwxRenderSize; };",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 albedo = g_Texture0.sample(sourceSampler, uv);",
                "    float delta = dot(abs(keyColor - albedo.xyz), float3(1.0));",
                "    float blend = smoothstep(0.001, 0.002 + fuzz, delta - tolerance);",
                "    albedo.w *= mix(keyAlpha, 1.0, blend);",
                "    out.mwxFragColor = albedo;",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            let authored = [
                "uniform sampler2D g_Texture0;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);",
                "    float delta = dot(abs(keyColor - albedo.rgb), vec3(1.0));",
                "    float blend = smoothstep(0.001, 0.002 + fuzz, delta - tolerance);",
                "    albedo.a *= mix(keyAlpha, 1.0, blend);",
                "    gl_FragColor = albedo;",
                "}",
            ].joined(separator: "\n")
            func build(_ msl: String) -> Result<
                SceneGenericShaderProgramArtifact,
                SceneGenericShaderArtifactBuilder.Failure
            > {
                SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "c", count: 64),
                    backendID: "glslang-spirv-cross-msl-v1",
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL, reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: authored,
                            authoredSource: authored,
                            msl: msl, reflection: reflection
                        ),
                    ],
                    maximumArtifactBytes: 1_024_000
                )
            }
            let positive: SceneGenericShaderProgramArtifact?
            switch build(fragmentMSL) {
            case let .success(artifact): positive = artifact
            case .failure: positive = nil
            }
            let metal = positive?.program.metalSource ?? ""
            let output = StraightAttenuationBuilderOutput(
                analyzedTransfer: colorTransferName(
                    SceneAuthoredShaderColorTransferAnalyzer.analyze(
                        fragmentSource: authored
                    )
                ),
                positiveKind: positive?.program.colorTransfer.kind,
                positiveSlot: positive?.program.colorTransfer.slot,
                wholeColorAttenuated: metal.contains(
                    "albedo *= mix(keyAlpha, 1.0, blend);"
                ),
                unrelatedAlphaReadRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "float delta = dot(abs(keyColor - albedo.xyz), float3(1.0));",
                        with: "float delta = albedo.w + dot(abs(keyColor - albedo.xyz), float3(1.0));"
                    )
                )),
                wholeVectorUseRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "float delta = dot(abs(keyColor - albedo.xyz), float3(1.0));",
                        with: "float delta = length(albedo);"
                    )
                )),
                rgbWriteRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "    albedo.w *= mix(keyAlpha, 1.0, blend);",
                        with: "    albedo.xyz *= blend;\n    albedo.w *= mix(keyAlpha, 1.0, blend);"
                    )
                ))
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-conditional-straight" {
            let reflection = Data(#"{"types":{"_1":{"members":[]}},"ubos":[{"type":"_1","block_size":0,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms {};"
            let fragmentMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms {};",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 base = g_Texture0.sample(sourceSampler, uv);",
                "    float4 reflected = g_Texture0.sample(sourceSampler, reflectedUV);",
                "    if (base.w > border) {",
                "        out.mwxFragColor = base;",
                "    } else if (reflected.w > 0.0) {",
                "        float3 color = mix(base.xyz, shadowColor, weight);",
                "        out.mwxFragColor.x = color.x;",
                "        out.mwxFragColor.y = color.y;",
                "        out.mwxFragColor.z = color.z;",
                "        out.mwxFragColor.w = min(1.0, base.w + reflected.w * weight);",
                "    } else {",
                "        out.mwxFragColor = base;",
                "    }",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            let authored = [
                "uniform sampler2D g_Texture0;",
                "uniform float g_Border;",
                "uniform float g_ScalarWeight;",
                "uniform vec3 g_Shadow;",
                "varying vec2 v_TexCoord;",
                "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {",
                "    return mix(base, blend, opacity);",
                "}",
                "void main() {",
                "    vec4 base = texSample2D(g_Texture0, v_TexCoord);",
                "    vec4 reflected = texSample2D(g_Texture0, v_TexCoord + vec2(0.25, 0.0));",
                "    if (base.a > g_Border) {",
                "        gl_FragColor = base;",
                "    } else if (reflected.a > 0.0) {",
                "        gl_FragColor.rgb = ApplyBlending(0, base.rgb, g_Shadow, g_ScalarWeight);",
                "        gl_FragColor.a = min(1.0, base.a + reflected.a * g_ScalarWeight);",
                "    } else {",
                "        gl_FragColor = base;",
                "    }",
                "}",
            ].joined(separator: "\n")
            func build(_ msl: String) -> Result<
                SceneGenericShaderProgramArtifact,
                SceneGenericShaderArtifactBuilder.Failure
            > {
                SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "d", count: 64),
                    backendID: "glslang-spirv-cross-msl-v1",
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL, reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: authored,
                            authoredSource: authored,
                            msl: msl, reflection: reflection
                        ),
                    ],
                    maximumArtifactBytes: 1_024_000
                )
            }
            let positive: SceneGenericShaderProgramArtifact?
            switch build(fragmentMSL) {
            case let .success(artifact): positive = artifact
            case .failure: positive = nil
            }
            let metal = positive?.program.metalSource ?? ""
            let output = ConditionalStraightBuilderOutput(
                positiveKind: positive?.program.colorTransfer.kind,
                positiveSlot: positive?.program.colorTransfer.slot,
                unpremultipliedSamples: metal.components(
                    separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample"
                ).count - 1,
                terminalPremultiply: metal.contains(
                    "out.mwxFragColor = mwxGenericPremultiply(out.mwxFragColor);"
                ),
                missingSampleRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "float4 reflected = g_Texture0.sample(sourceSampler, reflectedUV);",
                        with: "float4 reflected = float4(0.0);"
                    )
                )),
                wrongAlphaWriteRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "out.mwxFragColor.w = min",
                        with: "out.mwxFragColor.x = min"
                    )
                )),
                outputReadRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "    return out;",
                        with: "    float4 leaked = out.mwxFragColor;\n    return out;"
                    )
                )),
                helperConflictRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "using namespace metal;",
                        with: "using namespace metal;\nfloat4 mwxGenericPremultiply(float4 value);"
                    )
                ))
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--coordinator" {
            let coordinator = SceneResolvedMaterialGenericShaderArtifactCache
                .CompilationCoordinator()
            var operationCount = 0
            let failed: () -> Result<URL, SceneGenericShaderCompiler.Failure> = {
                operationCount += 1
                return .failure(.workspace)
            }
            let first = coordinator.perform(key: "failed-key", operation: failed)
            let repeated = coordinator.perform(key: "failed-key", operation: failed)
            let independent = coordinator.perform(key: "independent-key") {
                operationCount += 1
                return .success(URL(fileURLWithPath: "/tmp/fixture-artifact"))
            }
            let output = CoordinatorOutput(
                operationCount: operationCount,
                firstSource: first.source.rawValue,
                repeatedSource: repeated.source.rawValue,
                independentSource: independent.source.rawValue,
                firstFailed: failedResult(first.result),
                repeatedFailed: failedResult(repeated.result),
                independentSucceeded: succeededResult(independent.result)
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        let vertex = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let fragment = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let result: Output
        switch SceneResolvedMaterialGenericShaderArtifactCache.resolve(
            vertexSource: vertex,
            fragmentSource: fragment,
            alphaAttenuationSourceSlot: ProcessInfo.processInfo.environment[
                "MWX_TEST_ALPHA_ATTENUATION_SOURCE_SLOT"
            ].flatMap(Int.init),
            colorBlendSourceSlot: ProcessInfo.processInfo.environment[
                "MWX_TEST_COLOR_BLEND_SOURCE_SLOT"
            ].flatMap(Int.init),
            hasExternalProviderTexture:
                ProcessInfo.processInfo.environment["MWX_TEST_EXTERNAL_PROVIDER"] == "1",
            producesScalarRedOutput:
                ProcessInfo.processInfo.environment["MWX_TEST_SCALAR_OUTPUT"] == "1",
            isSourceIndependentPremultipliedOutput:
                ProcessInfo.processInfo.environment[
                    "MWX_TEST_SOURCE_INDEPENDENT_PREMULTIPLIED_OUTPUT"
                ] == "1",
            graphTextureSlots: Set(
                (ProcessInfo.processInfo.environment["MWX_TEST_GRAPH_SLOTS"] ?? "")
                    .split(separator: ",").compactMap { Int($0) }
            ),
            graphInputTextureSlots: Set(
                (ProcessInfo.processInfo.environment["MWX_TEST_GRAPH_INPUT_SLOTS"] ?? "")
                    .split(separator: ",").compactMap { Int($0) }
            ),
            r8TextureSlots: Set(
                (ProcessInfo.processInfo.environment["MWX_TEST_R8_SLOTS"] ?? "")
                    .split(separator: ",").compactMap { Int($0) }
            ),
            hasDefaultedOpacityMaskSampler:
                ProcessInfo.processInfo.environment[
                    "MWX_TEST_DEFAULTED_OPACITY_MASK"
                ] == "1"
        ) {
        case let .accepted(program, requestKey, decision):
            result = .init(
                status: "accepted", code: nil, requestKey: requestKey,
                permitsBoundedFrontend: nil,
                backend: program.backend.rawValue,
                uniformBufferIndex: program.uniformBufferIndex,
                uniformNames: program.uniformLayout.fields.map(\.name),
                textureSlots: program.textureBindings.map(\.slot),
                colorTransfer: colorTransferName(program.colorTransfer),
                fragmentOutputChannelUse: program.fragmentOutputChannelUse.rawValue,
                routeProfile: decision.profile,
                routeState: decision.state,
                fallbackOwner: decision.fallbackOwner
            )
        case let .unavailable(code, requestKey, permitsBoundedFrontend, decision):
            result = .init(
                status: "unavailable", code: code, requestKey: requestKey,
                permitsBoundedFrontend: permitsBoundedFrontend,
                backend: nil, uniformBufferIndex: nil,
                uniformNames: nil, textureSlots: nil, colorTransfer: nil,
                fragmentOutputChannelUse: nil,
                routeProfile: decision.profile,
                routeState: decision.state,
                fallbackOwner: decision.fallbackOwner
            )
        }
        let data = try JSONEncoder().encode(result)
        FileHandle.standardOutput.write(data)
    }
}

private func failedResult<T, E>(_ result: Result<T, E>) -> Bool {
    if case .failure = result { return true }
    return false
}

private func succeededResult<T, E>(_ result: Result<T, E>) -> Bool {
    if case .success = result { return true }
    return false
}

private func failedColorTransfer(
    _ result: Result<
        SceneGenericShaderProgramArtifact,
        SceneGenericShaderArtifactBuilder.Failure
    >
) -> Bool {
    if case .failure(.colorTransfer) = result { return true }
    return false
}
"""

VERTEX = """
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
"""

FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
"""

UNPROVEN_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void WriteOutput() {
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
void main() {
    WriteOutput();
}
"""

GENERIC_ONLY_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    int counter = 0;
    while (counter < 1) {
        counter += 1;
    }
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
"""

OPAQUE_FRAGMENT = """
varying vec2 v_TexCoord;
void main() {
    vec3 total = vec3(v_TexCoord, 0.2);
    gl_FragColor = vec4(total, 1.0);
}
"""

STRAIGHT_ALPHA_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    float mask = 0.5;
    gl_FragColor = vec4(color.rgb, color.a * mask);
}
"""

ALPHA_ATTENUATION_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_UserAlpha;
varying vec2 v_TexCoord;
void main() {
    vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
    carrier.a *= 0.5 * g_UserAlpha;
    gl_FragColor = carrier;
}
"""

INTERPOLATED_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Blend;
varying vec2 v_TexCoord;
void main() {
    vec4 recent = texSample2D(g_Texture0, v_TexCoord);
    vec4 retained = texSample2D(g_Texture1, v_TexCoord);
    gl_FragColor = mix(retained, recent, g_Blend);
}
"""

STRAIGHT_PRESERVING_R8_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
varying vec2 v_TexCoord;
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
    float signal = texSample2D(g_Texture1, v_TexCoord).r;
    albedo.rgb *= signal;
    gl_FragColor = albedo;
}
"""

CHANNEL_RECONSTRUCTION_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_Opacity;
uniform vec3 g_Tint;
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
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    color.rgb = ApplyBlending(0, color.rgb, g_Tint, g_Opacity);
    gl_FragColor = color;
}
"""

STAGE_UNIFORM_STRAIGHT_PRESERVING_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Time;
uniform float u_Speed;
varying vec2 v_TexCoord;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    float mask = texSample2D(g_Texture1, v_TexCoord).r;
    vec3 transformed = color.rgb;
    transformed.x = frac(transformed.x + g_Time * u_Speed);
    color.rgb = mix(color, transformed, mask);
    gl_FragColor = color;
}
"""

FILM_GRAIN_STOCK_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1; // {"default":"util/noise"}
uniform sampler2D g_Texture2; // {"mode":"opacitymask","combo":"MASK"}
uniform float g_Time;
uniform float g_NoiseAlpha;
varying vec2 v_TexCoord;
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
    vec3 noise = texSample2D(g_Texture1, v_TexCoord + g_Time).rgb;
    albedo.rgb = mix(albedo.rgb, noise, g_NoiseAlpha);
    gl_FragColor = albedo;
}
"""

STAGE_UNIFORM_PASSTHROUGH_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_Speed;
varying vec2 v_TexCoord;
void main() {
    vec2 offset = vec2(g_Speed * 0.0);
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord + offset);
}
"""

GRAPH_INPUT_COLOR_BLEND_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_Opacity;
uniform vec3 g_Color;
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
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    float weight = g_Opacity;
    color.rgb = ApplyBlending(30, color.rgb, g_Color, weight);
    gl_FragColor = color;
}
"""

PREMULTIPLIED_FRAGMENT = """
uniform float g_Weight;
vec3 ApplyBlending(
    const int mode,
    in vec3 base,
    in vec3 blend,
    in float opacity
) {
    return base + blend * opacity;
}
void main() {
    float weight = g_Weight;
    vec3 tint = vec3(0.8);
    vec4 color = CAST4(0.0);
    color.rgb = ApplyBlending(31, color.rgb, tint, weight);
    color.a = max(color.a, weight);
    gl_FragColor = color;
}
"""

CONDITIONAL_STRAIGHT_UNION_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_Border;
uniform float g_ScalarWeight;
uniform vec3 g_Shadow;
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
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec4 reflected = texSample2D(
        g_Texture0,
        v_TexCoord + vec2(0.25, 0.0)
    );
    if (base.a > g_Border) {
        gl_FragColor = base;
    } else if (reflected.a > 0.0) {
        gl_FragColor.rgb = ApplyBlending(
            0,
            base.rgb,
            g_Shadow,
            g_ScalarWeight
        );
        gl_FragColor.a = min(
            1.0,
            base.a + reflected.a * g_ScalarWeight
        );
    } else {
        gl_FragColor = base;
    }
}
"""


class SceneGenericShaderProgramArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "GenericShaderArtifactHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "generic-shader-artifact-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(build_root / "clang-module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(build_root / "swift-module-cache")
        subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Security",
                "-o",
                str(cls.binary),
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

    def run_harness(
        self,
        root: Path,
        *,
        route: str | None,
        profile_routes: str | None = None,
        fragment: str = FRAGMENT,
        has_external_provider: bool = False,
        produces_scalar_output: bool = False,
        source_independent_premultiplied_output: bool = False,
        graph_slots: tuple[int, ...] = (),
        graph_input_slots: tuple[int, ...] = (),
        r8_slots: tuple[int, ...] = (),
        has_defaulted_opacity_mask: bool = False,
        alpha_attenuation_source_slot: int | None = None,
        color_blend_source_slot: int | None = None,
    ):
        vertex_path = root / "fixture.vert"
        fragment_path = root / "fixture.frag"
        vertex_path.write_text(textwrap.dedent(VERTEX), encoding="utf-8")
        fragment_path.write_text(textwrap.dedent(fragment), encoding="utf-8")
        requests = root / "requests"
        cache = root / "cache"
        requests.mkdir(exist_ok=True)
        cache.mkdir(exist_ok=True)
        environment = os.environ.copy()
        environment.update({
            "MWX_SCENE_GENERIC_SHADER_REQUESTS": str(requests),
            "MWX_SCENE_GENERIC_SHADER_CACHE": str(cache),
        })
        if route is None:
            environment.pop("MWX_SCENE_GENERIC_SHADER_ROUTE", None)
        else:
            environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = route
        if profile_routes is None:
            environment.pop("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", None)
        else:
            environment["MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES"] = profile_routes
        if has_external_provider:
            environment["MWX_TEST_EXTERNAL_PROVIDER"] = "1"
        else:
            environment.pop("MWX_TEST_EXTERNAL_PROVIDER", None)
        if produces_scalar_output:
            environment["MWX_TEST_SCALAR_OUTPUT"] = "1"
        else:
            environment.pop("MWX_TEST_SCALAR_OUTPUT", None)
        if source_independent_premultiplied_output:
            environment[
                "MWX_TEST_SOURCE_INDEPENDENT_PREMULTIPLIED_OUTPUT"
            ] = "1"
        else:
            environment.pop(
                "MWX_TEST_SOURCE_INDEPENDENT_PREMULTIPLIED_OUTPUT", None
            )
        if graph_slots:
            environment["MWX_TEST_GRAPH_SLOTS"] = ",".join(map(str, graph_slots))
        else:
            environment.pop("MWX_TEST_GRAPH_SLOTS", None)
        if graph_input_slots:
            environment["MWX_TEST_GRAPH_INPUT_SLOTS"] = ",".join(
                map(str, graph_input_slots)
            )
        else:
            environment.pop("MWX_TEST_GRAPH_INPUT_SLOTS", None)
        if r8_slots:
            environment["MWX_TEST_R8_SLOTS"] = ",".join(map(str, r8_slots))
        else:
            environment.pop("MWX_TEST_R8_SLOTS", None)
        if has_defaulted_opacity_mask:
            environment["MWX_TEST_DEFAULTED_OPACITY_MASK"] = "1"
        else:
            environment.pop("MWX_TEST_DEFAULTED_OPACITY_MASK", None)
        if alpha_attenuation_source_slot is not None:
            environment["MWX_TEST_ALPHA_ATTENUATION_SOURCE_SLOT"] = str(
                alpha_attenuation_source_slot
            )
        else:
            environment.pop("MWX_TEST_ALPHA_ATTENUATION_SOURCE_SLOT", None)
        if color_blend_source_slot is not None:
            environment["MWX_TEST_COLOR_BLEND_SOURCE_SLOT"] = str(
                color_blend_source_slot
            )
        else:
            environment.pop("MWX_TEST_COLOR_BLEND_SOURCE_SLOT", None)
        completed = subprocess.run(
            [str(self.binary), str(vertex_path), str(fragment_path)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout), requests, cache, completed.stderr

    def artifact(
        self, key: str, *, color_transfer: str = "passthrough"
    ) -> dict:
        metal = """
#include <metal_stdlib>
using namespace metal;
struct Uniforms { float2 mwxRenderSize; };
vertex float4 mwxGenericVertex(uint vertexID [[vertex_id]], constant Uniforms& u [[buffer(8)]]) { return float4(0.0); }
fragment float4 mwxGenericFragment(texture2d<float> g_Texture0 [[texture(0)]]) { return float4(1.0); }
""".strip() + "\n"
        return {
            "schemaVersion": 3,
            "kind": "scene-generic-shader-program-artifact",
            "backendID": "glslang-spirv-cross-msl-v1",
            "requestKey": key,
            "program": {
                "metalSource": metal,
                "metalSourceSHA256": hashlib.sha256(metal.encode()).hexdigest(),
                "vertexFunctionName": "mwxGenericVertex",
                "fragmentFunctionName": "mwxGenericFragment",
                "uniformBufferIndex": 8,
                "uniformLayout": {
                    "fields": [{
                        "name": "mwxRenderSize",
                        "authoredName": "mwxRenderSize",
                        "type": "float2",
                        "offset": 0,
                    }],
                    "byteSize": 16,
                },
                "textureBindings": [{
                    "name": "g_Texture0", "slot": 0, "channelUse": "unproven"
                }],
                "staticLoopWork": 0,
                "fragmentOutputChannelUse": "redDefined",
                "colorTransfer": (
                    {"kind": color_transfer, "slot": 0}
                    if color_transfer in (
                        "passthrough",
                        "straight-alpha",
                        "straight-alpha-preserving",
                    )
                    else (
                        {"kind": color_transfer, "slots": [0, 1]}
                        if color_transfer == "interpolated-color"
                        else {"kind": color_transfer}
                    )
                ),
            },
        }

    def python_artifact(
        self,
        key: str,
        *,
        vertex_source: str = VERTEX,
        fragment_source: str = FRAGMENT,
    ) -> dict:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0}
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 8, "set": 0, "binding": 8
            }],
            "textures": [{"name": "g_Texture0", "binding": 0}],
        }
        stages = [
            {"stage": "vertex", "reflection": reflection},
            {"stage": "fragment", "reflection": reflection},
        ]
        vertex_msl = """#include <metal_stdlib>
using namespace metal;
struct MWXUniforms { float2 mwxRenderSize; };
vertex float4 mwxGenericVertex(uint vertexID [[vertex_id]]) {
    return float4(0.0);
}
"""
        fragment_msl = """#include <metal_stdlib>
using namespace metal;
struct MWXUniforms { float2 mwxRenderSize; };
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment(texture2d<float> g_Texture0 [[texture(0)]]) {
    Output out;
    out.mwxFragColor = g_Texture0.sample(sampler(), float2(0.5));
    return out;
}
"""
        return build_program_artifact(
            request_key=key,
            backend_id="glslang-spirv-cross-msl-v1",
            compiled_stages=stages,
            stage_sources={
                "vertex": vertex_source,
                "fragment": fragment_source,
            },
            msl_sources={"vertex": vertex_msl, "fragment": fragment_msl},
            maximum_artifact_bytes=1_024_000,
        )

    @staticmethod
    def request_key(seed: str, vertex_source: str, fragment_source: str) -> str:
        digest = hashlib.sha256()
        for value in (
            seed,
            "wallpaper-engine-glsl-like-v0",
            vertex_source,
            fragment_source,
            "{}",
        ):
            encoded = value.encode("utf-8")
            digest.update(len(encoded).to_bytes(8, "big"))
            digest.update(encoded)
        return digest.hexdigest()

    def test_schema_two_request_and_default_cache_namespaces_are_isolated(self):
        source = CACHE_SOURCE.read_text(encoding="utf-8")
        self.assertIn('"mwx-generic-shader-request-v3"', source)
        self.assertIn('"SceneGenericShaderPrograms-v3"', source)
        self.assertNotIn('"mwx-generic-shader-request-v2"', source)
        self.assertNotIn('"SceneGenericShaderPrograms-v2"', source)

        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            observed, _, cache, _ = self.run_harness(root, route="observe-only")
            current_key = self.request_key(
                "mwx-generic-shader-request-v3", VERTEX, FRAGMENT
            )
            legacy_key = self.request_key(
                "mwx-generic-shader-request-v1", VERTEX, FRAGMENT
            )
            self.assertEqual(observed["requestKey"], current_key)
            self.assertNotEqual(current_key, legacy_key)

            stale = self.artifact(legacy_key)
            stale["schemaVersion"] = 1
            stale["program"].pop("fragmentOutputChannelUse")
            (cache / f"{legacy_key}.json").write_text(
                json.dumps(stale), encoding="utf-8"
            )
            unavailable, _, _, log = self.run_harness(
                root, route="prefer-generic"
            )
            self.assertEqual(unavailable["requestKey"], current_key)
            self.assertEqual(
                unavailable["code"],
                "compiler-configuration-licensebundleunavailable",
            )
            self.assertNotIn("artifact-invalid-json", log)

    def test_swift_normalizer_prunes_only_dead_fragment_varying_mismatch(self):
        completed = subprocess.run(
            [str(self.binary), "--normalizer-varying-link"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "deadMismatchAccepted": True,
            "deadFragmentInterfaceRemoved": True,
            "liveMismatchRejected": True,
        })

    def test_compilation_coordinator_restarts_for_independent_key(self):
        completed = subprocess.run(
            [str(self.binary), "--coordinator"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertIsNone(output.get("composedFailure"))
        self.assertEqual(output, {
            "operationCount": 2,
            "firstSource": "spawn",
            "repeatedSource": "launch-result-cache",
            "independentSource": "spawn",
            "firstFailed": True,
            "repeatedFailed": True,
            "independentSucceeded": True,
        })

    def test_straight_alpha_preserving_proves_composed_same_slot_output(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-straight-preserving"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertEqual(output["positiveKind"], "straight-alpha-preserving")
        self.assertEqual(output["positiveSlot"], 0)
        self.assertEqual(output["composedKind"], "straight-alpha-preserving")
        self.assertEqual(output["composedSampleCount"], 4)
        self.assertTrue(output["composedOutputPremultiplied"])
        self.assertTrue(output["unrelatedAlphaRejected"])
        self.assertTrue(output["mixedSlotRejected"])

    def test_audio_scalar_array_swizzle_is_removed_from_metal_abi(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-straight-preserving"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertNotIn("g_AudioSpectrum16Left[0].x", output.get("composedMetal", ""))

    def test_product_builder_proves_scalar_two_color_interpolation(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-interpolation"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "positiveKind": "interpolated-color",
            "positiveSlots": [0, 1],
            "unprovenOutputChannelUse": "redDefined",
            "vectorWeightRejected": True,
            "mutatedColorRejected": True,
        })

    def test_product_builder_preserves_straight_rgb_alpha_boundary(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-straight-preserving"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertEqual({key: output[key] for key in (
            "positiveKind", "positiveSlot", "sampleUnpremultiplied",
            "outputPremultiplied", "helperPairPresent", "wrongSlotRejected",
            "helperConflictRejected"
        )}, {
            "positiveKind": "straight-alpha-preserving",
            "positiveSlot": 0,
            "sampleUnpremultiplied": True,
            "outputPremultiplied": True,
            "helperPairPresent": True,
            "wrongSlotRejected": True,
            "helperConflictRejected": True,
        })

    def test_product_builder_accepts_rgb_reads_before_single_alpha_attenuation(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-straight-attenuation"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "analyzedTransfer": "straightAlpha",
            "positiveKind": "straight-alpha",
            "positiveSlot": 0,
            "wholeColorAttenuated": True,
            "unrelatedAlphaReadRejected": True,
            "wholeVectorUseRejected": True,
            "rgbWriteRejected": True,
        })

    def test_product_builder_lowers_source_proven_conditional_straight_union(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-conditional-straight"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "positiveKind": "straight-alpha",
            "positiveSlot": 0,
            "unpremultipliedSamples": 2,
            "terminalPremultiply": True,
            "missingSampleRejected": True,
            "wrongAlphaWriteRejected": True,
            "outputReadRejected": True,
            "helperConflictRejected": True,
        })

    def test_product_normalizer_reuses_typed_mix_vector_narrowing(self):
        completed = subprocess.run(
            [str(self.binary), "--normalizer-typed-mix"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "firstWideArgumentNarrowed": True,
            "secondWideArgumentNarrowed": True,
            "vec2ArgumentNarrowed": True,
            "explicitSwizzlePreserved": True,
            "userDefinedMixPreserved": True,
            "invalidWeightPreserved": True,
        })

    def test_product_normalizer_preserves_vertex_position_contract(self):
        completed = subprocess.run(
            [str(self.binary), "--normalizer-position"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "directUsesClipSpace": True,
            "directAvoidsTargetPixels": True,
            "projectedUsesTargetPixels": True,
        })

    def test_request_export_and_source_keyed_artifact_acceptance(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, requests, cache, first_log = self.run_harness(
                root, route="observe-only"
            )
            self.assertEqual(first["status"], "unavailable")
            self.assertEqual(first["code"], "route-observe-only")
            self.assertNotIn("outcome=fallback", first_log)
            request_files = list(requests.glob("*.json"))
            self.assertEqual([path.stem for path in request_files], [first["requestKey"]])
            request = json.loads(request_files[0].read_text(encoding="utf-8"))
            self.assertEqual(request["requestID"], first["requestKey"])
            self.assertEqual([stage["stage"] for stage in request["stages"]], [
                "vertex", "fragment"
            ])

            artifact = self.python_artifact(first["requestKey"])
            self.assertEqual(
                artifact["program"]["fragmentOutputChannelUse"], "unproven"
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, accepted_log = self.run_harness(
                root, route="prefer-generic"
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["backend"], "genericCompilerArtifact")
            self.assertEqual(accepted["uniformBufferIndex"], 8)
            self.assertEqual(accepted["uniformNames"], ["mwxRenderSize"])
            self.assertEqual(accepted["textureSlots"], [0])
            self.assertEqual(accepted["colorTransfer"], "passthrough")
            self.assertEqual(accepted["fragmentOutputChannelUse"], "redDefined")
            self.assertIn(
                "state=prefer-generic profile=ordinary-shader "
                "outcome=accepted reason=- ", accepted_log
            )
            self.assertIn("count=1", accepted_log)

            default_accepted, _, _, default_log = self.run_harness(
                root, route=None
            )
            self.assertEqual(default_accepted["status"], "accepted")
            self.assertEqual(
                default_accepted["backend"], "genericCompilerArtifact"
            )
            self.assertIn(
                "state=prefer-generic profile=ordinary-shader "
                "outcome=accepted reason=- ",
                default_log,
            )

            disabled, _, _, disabled_log = self.run_harness(
                root, route="disable-generic"
            )
            self.assertEqual(disabled["status"], "unavailable")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertIn(
                "state=disable-generic profile=ordinary-shader outcome=fallback "
                "reason=route-disabled ",
                disabled_log,
            )

            invalid, _, _, invalid_log = self.run_harness(
                root, route="unknown-route"
            )
            self.assertEqual(invalid["status"], "unavailable")
            self.assertEqual(invalid["code"], "route-invalid")
            self.assertTrue(invalid["permitsBoundedFrontend"])
            self.assertNotIn("outcome=accepted", invalid_log)

            changed, _, _, changed_log = self.run_harness(
                root,
                route="prefer-generic",
                fragment=FRAGMENT + "\n// distinct prepared source\n",
            )
            self.assertEqual(changed["status"], "unavailable")
            self.assertEqual(
                changed["code"],
                "compiler-configuration-licensebundleunavailable",
            )
            self.assertNotEqual(changed["requestKey"], accepted["requestKey"])
            self.assertIn(
                "profile=ordinary-shader outcome=fallback "
                "reason=compiler-configuration-licensebundleunavailable",
                changed_log,
            )

    def test_corrupt_metal_digest_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(root, route="observe-only")
            artifact = self.artifact(first["requestKey"])
            artifact["program"]["metalSourceSHA256"] = "0" * 64
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            rejected, _, _, rejected_log = self.run_harness(
                root, route="prefer-generic"
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertIn(
                "profile=ordinary-shader outcome=fallback "
                "reason=artifact-contract-rejected", rejected_log
            )
            self.assertIn(f"request={first['requestKey']}", rejected_log)

    def test_artifact_color_fact_cannot_contradict_prepared_source(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(root, route="observe-only")
            artifact = self.artifact(first["requestKey"], color_transfer="opaque")
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            rejected, _, _, rejected_log = self.run_harness(
                root, route="prefer-generic"
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertIn(
                "profile=ordinary-shader outcome=fallback "
                "reason=artifact-contract-rejected",
                rejected_log,
            )

    def test_unknown_fragment_output_fact_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(root, route="observe-only")
            artifact = self.artifact(first["requestKey"])
            artifact["program"]["fragmentOutputChannelUse"] = "forged"
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            rejected, _, _, _ = self.run_harness(root, route="prefer-generic")
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")

    def test_valid_but_forged_fragment_output_fact_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root,
                route="observe-only",
                fragment=UNPROVEN_FRAGMENT,
            )
            artifact = self.artifact(first["requestKey"])
            self.assertEqual(
                artifact["program"]["fragmentOutputChannelUse"],
                "redDefined",
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            rejected, _, _, _ = self.run_harness(
                root,
                route="prefer-generic",
                fragment=UNPROVEN_FRAGMENT,
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")

    def test_generic_only_syntax_preserves_unproven_output_fact(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root,
                route="observe-only",
                fragment=GENERIC_ONLY_FRAGMENT,
            )
            artifact = self.artifact(first["requestKey"])
            artifact["program"]["fragmentOutputChannelUse"] = "unproven"
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(
                root,
                route="prefer-generic",
                fragment=GENERIC_ONLY_FRAGMENT,
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["backend"], "genericCompilerArtifact")
            self.assertEqual(accepted["colorTransfer"], "passthrough")

    def test_python_unproven_artifact_round_trips_for_unproven_source(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root,
                route="observe-only",
                fragment=UNPROVEN_FRAGMENT,
            )
            artifact = self.python_artifact(
                first["requestKey"],
                fragment_source=UNPROVEN_FRAGMENT,
            )
            self.assertEqual(
                artifact["program"]["fragmentOutputChannelUse"], "unproven"
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(
                root,
                route="prefer-generic",
                fragment=UNPROVEN_FRAGMENT,
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["fragmentOutputChannelUse"], "unproven")

    def test_opaque_artifact_maps_to_opaque_program_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root, route="observe-only", fragment=OPAQUE_FRAGMENT
            )
            artifact = self.artifact(first["requestKey"], color_transfer="opaque")
            artifact["program"]["staticLoopWork"] = 4
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(
                root, route="prefer-generic", fragment=OPAQUE_FRAGMENT
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "opaque")

    def test_premultiplied_artifact_maps_to_program_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root, route="observe-only", fragment=PREMULTIPLIED_FRAGMENT
            )
            artifact = self.artifact(
                first["requestKey"], color_transfer="premultiplied"
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(
                root, route="prefer-generic", fragment=PREMULTIPLIED_FRAGMENT
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "premultipliedAlpha")

    def test_source_independent_premultiplied_output_has_profile_local_product_authority(self):
        profile = "source-proven-independent-premultiplied-output"
        with tempfile.TemporaryDirectory(
            prefix="mwx-generic-artifact-test-"
        ) as directory:
            root = Path(directory)
            rejected, _, cache, rejected_log = self.run_harness(
                root,
                route=None,
                fragment=PREMULTIPLIED_FRAGMENT,
                source_independent_premultiplied_output=True,
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertEqual(rejected["routeProfile"], profile)
            self.assertEqual(rejected["routeState"], "generic-only")
            self.assertIn(
                f"state=generic-only profile={profile} outcome=rejected",
                rejected_log,
            )

            artifact = self.artifact(
                rejected["requestKey"], color_transfer="premultiplied"
            )
            (cache / f"{rejected['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, accepted_log = self.run_harness(
                root,
                route=None,
                fragment=PREMULTIPLIED_FRAGMENT,
                source_independent_premultiplied_output=True,
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["routeProfile"], profile)
            self.assertEqual(accepted["routeState"], "generic-only")
            self.assertIn(
                f"state=generic-only profile={profile} outcome=accepted",
                accepted_log,
            )

            rolled_back, _, _, rollback_log = self.run_harness(
                root,
                route="disable-generic",
                fragment=PREMULTIPLIED_FRAGMENT,
                source_independent_premultiplied_output=True,
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertEqual(rolled_back["routeProfile"], profile)
            self.assertIn(
                f"state=disable-generic profile={profile} "
                "outcome=fallback reason=route-disabled",
                rollback_log,
            )

    def test_source_independent_premultiplied_output_profile_rejects_broader_ownership(self):
        cases = [
            {},
            {"has_external_provider": True},
            {"graph_slots": (0,)},
            {"graph_input_slots": (0,)},
            {"produces_scalar_output": True},
        ]
        profile = "source-proven-independent-premultiplied-output"
        for facts in cases:
            with self.subTest(facts=facts), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                result, _, _, log = self.run_harness(
                    Path(directory),
                    route=None,
                    fragment=PREMULTIPLIED_FRAGMENT,
                    source_independent_premultiplied_output=bool(facts),
                    **facts,
                )
                self.assertNotEqual(result["routeProfile"], profile)
                self.assertTrue(result["permitsBoundedFrontend"])
                self.assertIn("state=prefer-generic", log)

    def test_conditional_straight_union_has_profile_local_product_authority(self):
        profile = "source-proven-graph-input-conditional-straight-union"
        with tempfile.TemporaryDirectory(
            prefix="mwx-generic-artifact-test-"
        ) as directory:
            root = Path(directory)
            rejected, _, cache, rejected_log = self.run_harness(
                root,
                route=None,
                fragment=CONDITIONAL_STRAIGHT_UNION_FRAGMENT,
                graph_input_slots=(0,),
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertEqual(rejected["routeProfile"], profile)
            self.assertEqual(rejected["routeState"], "generic-only")
            self.assertIn(
                f"state=generic-only profile={profile} outcome=rejected",
                rejected_log,
            )

            artifact = self.artifact(
                rejected["requestKey"], color_transfer="straight-alpha"
            )
            artifact["program"]["fragmentOutputChannelUse"] = "unproven"
            (cache / f"{rejected['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, accepted_log = self.run_harness(
                root,
                route=None,
                fragment=CONDITIONAL_STRAIGHT_UNION_FRAGMENT,
                graph_input_slots=(0,),
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["routeProfile"], profile)
            self.assertEqual(accepted["routeState"], "generic-only")
            self.assertIn(
                f"state=generic-only profile={profile} outcome=accepted",
                accepted_log,
            )

            rolled_back, _, _, rollback_log = self.run_harness(
                root,
                route=None,
                profile_routes=f"{profile}=disable-generic",
                fragment=CONDITIONAL_STRAIGHT_UNION_FRAGMENT,
                graph_input_slots=(0,),
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertEqual(rolled_back["routeProfile"], profile)
            self.assertEqual(rolled_back["fallbackOwner"], "bounded-frontend")
            self.assertIn(
                f"state=disable-generic profile={profile} "
                "outcome=fallback reason=route-disabled",
                rollback_log,
            )

    def test_conditional_straight_union_profile_is_source_derived_and_narrow(self):
        profile = "source-proven-graph-input-conditional-straight-union"
        renamed = CONDITIONAL_STRAIGHT_UNION_FRAGMENT.replace(
            "g_Shadow", "g_UnseenTint"
        ).replace("g_ScalarWeight", "g_UnseenWeight")
        cases = [
            (renamed, {"graph_input_slots": (0,)}, profile, False),
            (STRAIGHT_ALPHA_FRAGMENT, {"graph_input_slots": (0,)}, None, True),
            (
                CONDITIONAL_STRAIGHT_UNION_FRAGMENT,
                {"graph_input_slots": ()},
                None,
                True,
            ),
            (
                CONDITIONAL_STRAIGHT_UNION_FRAGMENT,
                {"graph_input_slots": (0, 1)},
                None,
                True,
            ),
            (
                CONDITIONAL_STRAIGHT_UNION_FRAGMENT,
                {"graph_input_slots": (0,), "graph_slots": (1,)},
                None,
                True,
            ),
            (
                CONDITIONAL_STRAIGHT_UNION_FRAGMENT,
                {"graph_input_slots": (0,), "has_external_provider": True},
                None,
                True,
            ),
        ]
        for fragment, facts, expected_profile, permits_bounded in cases:
            with self.subTest(
                expected_profile=expected_profile, facts=facts
            ), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                result, _, _, log = self.run_harness(
                    Path(directory),
                    route=None,
                    fragment=fragment,
                    **facts,
                )
                if expected_profile is not None:
                    self.assertEqual(result["routeProfile"], expected_profile)
                    self.assertFalse(result["permitsBoundedFrontend"])
                    self.assertIn("state=generic-only", log)
                else:
                    self.assertNotEqual(result["routeProfile"], profile)
                    self.assertEqual(
                        result["permitsBoundedFrontend"], permits_bounded
                    )
                    self.assertIn("state=prefer-generic", log)

    def test_straight_alpha_artifact_maps_color_source_slot(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root, route="observe-only", fragment=STRAIGHT_ALPHA_FRAGMENT
            )
            artifact = self.artifact(
                first["requestKey"], color_transfer="straight-alpha"
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(
                root, route="prefer-generic", fragment=STRAIGHT_ALPHA_FRAGMENT
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "straightAlpha")

    def test_interpolated_color_artifact_requires_sorted_bound_slots(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root, route="observe-only", fragment=INTERPOLATED_FRAGMENT
            )
            artifact = self.artifact(
                first["requestKey"], color_transfer="interpolated-color"
            )
            artifact["program"]["textureBindings"].append({
                "name": "g_Texture1", "slot": 1, "channelUse": "unproven"
            })
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, accepted_log = self.run_harness(
                root, route="prefer-generic", fragment=INTERPOLATED_FRAGMENT
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "interpolatedColor")
            self.assertIn(
                "state=generic-only "
                "profile=source-proven-scalar-color-interpolation "
                "outcome=accepted",
                accepted_log,
            )

            artifact["program"]["colorTransfer"]["slots"] = [1, 0]
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            rejected, _, _, rejected_log = self.run_harness(
                root, route="prefer-generic", fragment=INTERPOLATED_FRAGMENT
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertIn(
                "state=generic-only "
                "profile=source-proven-scalar-color-interpolation "
                "outcome=rejected reason=artifact-contract-rejected",
                rejected_log,
            )

    def test_interpolated_profile_revokes_bounded_owner_until_explicit_rollback(
        self,
    ):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            rejected, _, _, rejected_log = self.run_harness(
                root, route=None, fragment=INTERPOLATED_FRAGMENT
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertIn("state=generic-only", rejected_log)
            self.assertIn(
                "profile=source-proven-scalar-color-interpolation",
                rejected_log,
            )
            self.assertIn("outcome=rejected", rejected_log)

            observed, _, _, _ = self.run_harness(
                root, route="observe-only", fragment=INTERPOLATED_FRAGMENT
            )
            self.assertEqual(observed["code"], "route-observe-only")
            self.assertFalse(observed["permitsBoundedFrontend"])

            invalid, _, _, _ = self.run_harness(
                root, route="unknown-route", fragment=INTERPOLATED_FRAGMENT
            )
            self.assertEqual(invalid["code"], "route-invalid")
            self.assertFalse(invalid["permitsBoundedFrontend"])

            rolled_back, _, _, rollback_log = self.run_harness(
                root, route="disable-generic", fragment=INTERPOLATED_FRAGMENT
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertIn(
                "state=disable-generic "
                "profile=source-proven-scalar-color-interpolation "
                "outcome=fallback reason=route-disabled",
                rollback_log,
            )

    def test_provider_backed_interpolation_keeps_typed_bounded_fallback(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            unavailable, _, _, log = self.run_harness(
                root,
                route=None,
                fragment=INTERPOLATED_FRAGMENT,
                has_external_provider=True,
            )
            self.assertEqual(unavailable["status"], "unavailable")
            self.assertTrue(unavailable["permitsBoundedFrontend"])
            self.assertIn("state=prefer-generic", log)
            self.assertIn(
                "profile=provider-backed-scalar-color-interpolation",
                log,
            )
            self.assertIn("outcome=fallback", log)

    def test_profile_local_route_rollback_does_not_disable_other_profiles(self):
        profile_routes = "source-proven-opaque-scalar-output=disable-generic"
        with tempfile.TemporaryDirectory(
            prefix="mwx-generic-artifact-test-"
        ) as directory:
            root = Path(directory)
            rolled_back, _, _, rollback_log = self.run_harness(
                root,
                route=None,
                profile_routes=profile_routes,
                fragment=OPAQUE_FRAGMENT,
                produces_scalar_output=True,
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertEqual(
                rolled_back["routeProfile"],
                "source-proven-opaque-scalar-output",
            )
            self.assertEqual(rolled_back["routeState"], "disable-generic")
            self.assertEqual(rolled_back["fallbackOwner"], "bounded-frontend")
            self.assertIn(
                "state=disable-generic "
                "profile=source-proven-opaque-scalar-output",
                rollback_log,
            )

            still_generic, _, _, generic_log = self.run_harness(
                root,
                route=None,
                profile_routes=profile_routes,
                fragment=STAGE_UNIFORM_PASSTHROUGH_FRAGMENT,
                graph_input_slots=(0,),
            )
            self.assertEqual(still_generic["status"], "unavailable")
            self.assertFalse(still_generic["permitsBoundedFrontend"])
            self.assertNotEqual(still_generic["code"], "route-disabled")
            self.assertEqual(
                still_generic["routeProfile"],
                "source-proven-graph-input-stage-uniform-passthrough",
            )
            self.assertEqual(still_generic["routeState"], "generic-only")
            self.assertIn(
                "state=generic-only "
                "profile=source-proven-graph-input-stage-uniform-passthrough",
                generic_log,
            )

    def test_profile_local_prefer_generic_cannot_downgrade_generic_only(self):
        with tempfile.TemporaryDirectory(
            prefix="mwx-generic-artifact-test-"
        ) as directory:
            result, _, _, log = self.run_harness(
                Path(directory),
                route=None,
                profile_routes=(
                    "source-proven-opaque-scalar-output=prefer-generic"
                ),
                fragment=OPAQUE_FRAGMENT,
                produces_scalar_output=True,
            )
            self.assertEqual(result["code"], "route-invalid")
            self.assertFalse(result["permitsBoundedFrontend"])
            self.assertIn(
                "route-invalid profile=source-proven-opaque-scalar-output",
                log,
            )

    def test_profile_local_route_rejects_invalid_or_unauthorized_mapping(self):
        cases = [
            (
                "source-proven-opaque-scalar-output=not-a-route",
                OPAQUE_FRAGMENT,
                {"produces_scalar_output": True},
                False,
            ),
            (
                "source-proven-opaque-scalar-output=disable-generic,"
                "source-proven-opaque-scalar-output=prefer-generic",
                OPAQUE_FRAGMENT,
                {"produces_scalar_output": True},
                False,
            ),
            (
                "ordinary-shader=generic-only",
                FRAGMENT,
                {},
                True,
            ),
        ]
        for profile_routes, fragment, facts, permits_bounded in cases:
            with self.subTest(profile_routes=profile_routes), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                result, _, _, invalid_log = self.run_harness(
                    Path(directory),
                    route=None,
                    profile_routes=profile_routes,
                    fragment=fragment,
                    **facts,
                )
                self.assertEqual(result["code"], "route-invalid")
                self.assertEqual(result["permitsBoundedFrontend"], permits_bounded)
                self.assertIn("route-invalid profile=", invalid_log)
                self.assertIn("reason=route-configuration-invalid", invalid_log)

    def test_profile_registry_isolated_from_legacy_global_route(self):
        with tempfile.TemporaryDirectory(
            prefix="mwx-generic-artifact-test-"
        ) as directory:
            result, _, _, log = self.run_harness(
                Path(directory),
                route="disable-generic",
                profile_routes=(
                    "source-proven-graph-input-stage-uniform-passthrough="
                    "disable-generic"
                ),
                fragment=FRAGMENT,
            )
            self.assertNotEqual(result["code"], "route-disabled")
            self.assertIn(
                "state=prefer-generic profile=ordinary-shader",
                log,
            )

    def test_profile_routes_preserve_only_evidenced_owner_authority(self):
        cases = [
            (
                PREMULTIPLIED_FRAGMENT,
                {"source_independent_premultiplied_output": True},
                "source-proven-independent-premultiplied-output",
            ),
            (
                GRAPH_INPUT_COLOR_BLEND_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "color_blend_source_slot": 0,
                },
                "source-proven-graph-input-color-blend",
            ),
            (
                ALPHA_ATTENUATION_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "alpha_attenuation_source_slot": 0,
                },
                "source-proven-graph-input-alpha-attenuation",
            ),
            (
                STAGE_UNIFORM_PASSTHROUGH_FRAGMENT,
                {"graph_input_slots": (0,)},
                "source-proven-graph-input-stage-uniform-passthrough",
            ),
            (
                STAGE_UNIFORM_STRAIGHT_PRESERVING_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_defaulted_opacity_mask": True,
                },
                "source-proven-graph-input-stage-uniform-straight-alpha-preserving",
            ),
            (
                FRAGMENT,
                {"graph_slots": (0,)},
                "source-proven-graph-target-passthrough",
            ),
            (
                OPAQUE_FRAGMENT,
                {"produces_scalar_output": True},
                "source-proven-opaque-scalar-output",
            ),
            (
                STRAIGHT_PRESERVING_R8_FRAGMENT,
                {"r8_slots": (1,)},
                "source-proven-straight-alpha-r8-signal",
            ),
        ]
        for fragment, facts, profile in cases:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                root = Path(directory)
                rejected, _, _, rejected_log = self.run_harness(
                    root, route="prefer-generic", fragment=fragment, **facts
                )
                self.assertEqual(rejected["status"], "unavailable")
                self.assertFalse(rejected["permitsBoundedFrontend"])
                self.assertIn(f"state=generic-only profile={profile}", rejected_log)
                self.assertIn("outcome=rejected", rejected_log)

                observed, _, _, _ = self.run_harness(
                    root, route="observe-only", fragment=fragment, **facts
                )
                self.assertEqual(observed["code"], "route-observe-only")
                self.assertFalse(observed["permitsBoundedFrontend"])

                invalid, _, _, _ = self.run_harness(
                    root, route="unknown-route", fragment=fragment, **facts
                )
                self.assertEqual(invalid["code"], "route-invalid")
                self.assertFalse(invalid["permitsBoundedFrontend"])

                rolled_back, _, _, rollback_log = self.run_harness(
                    root, route="disable-generic", fragment=fragment, **facts
                )
                self.assertEqual(rolled_back["code"], "route-disabled")
                self.assertTrue(rolled_back["permitsBoundedFrontend"])
                self.assertIn(
                    f"state=disable-generic profile={profile} "
                    "outcome=fallback reason=route-disabled",
                    rollback_log,
                )

        preferred_cases = [
            (
                STRAIGHT_ALPHA_FRAGMENT,
                {"graph_input_slots": (0,)},
                "source-proven-graph-input-straight-alpha",
            ),
            (
                CHANNEL_RECONSTRUCTION_FRAGMENT,
                {"graph_input_slots": (0,)},
                "source-proven-graph-input-straight-alpha-preserving",
            ),
            (
                STAGE_UNIFORM_STRAIGHT_PRESERVING_FRAGMENT,
                {"graph_input_slots": (0,)},
                "source-proven-graph-input-straight-alpha-preserving",
            ),
        ]
        for fragment, facts, profile in preferred_cases:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                root = Path(directory)
                unavailable, _, _, fallback_log = self.run_harness(
                    root, route=None, fragment=fragment, **facts
                )
                self.assertEqual(unavailable["status"], "unavailable")
                self.assertTrue(unavailable["permitsBoundedFrontend"])
                self.assertIn(
                    f"state=prefer-generic profile={profile} outcome=fallback",
                    fallback_log,
                )
                self.assertIn("reason=compiler-configuration-", fallback_log)
                self.assertIn("count=1", fallback_log)

                observed, _, _, _ = self.run_harness(
                    root, route="observe-only", fragment=fragment, **facts
                )
                self.assertEqual(observed["code"], "route-observe-only")
                self.assertTrue(observed["permitsBoundedFrontend"])

                invalid, _, _, _ = self.run_harness(
                    root, route="unknown-route", fragment=fragment, **facts
                )
                self.assertEqual(invalid["code"], "route-invalid")
                self.assertTrue(invalid["permitsBoundedFrontend"])

                forced, _, _, _ = self.run_harness(
                    root, route="generic-only", fragment=fragment, **facts
                )
                self.assertEqual(forced["code"], "route-invalid")
                self.assertTrue(forced["permitsBoundedFrontend"])

                rolled_back, _, _, rollback_log = self.run_harness(
                    root, route="disable-generic", fragment=fragment, **facts
                )
                self.assertEqual(rolled_back["code"], "route-disabled")
                self.assertTrue(rolled_back["permitsBoundedFrontend"])
                self.assertIn(
                    f"state=disable-generic profile={profile} "
                    "outcome=fallback reason=route-disabled",
                    rollback_log,
                )

        with tempfile.TemporaryDirectory(
            prefix="mwx-generic-artifact-test-"
        ) as directory:
            ordinary, _, _, ordinary_log = self.run_harness(
                Path(directory),
                route="prefer-generic",
                fragment=STRAIGHT_PRESERVING_R8_FRAGMENT,
            )
            self.assertTrue(ordinary["permitsBoundedFrontend"])
            self.assertIn(
                "state=prefer-generic profile=ordinary-shader outcome=fallback",
                ordinary_log,
            )

        for fragment, facts in (
            (FRAGMENT, {"graph_slots": (1,)}),
            (FRAGMENT, {"graph_slots": (0,), "has_external_provider": True}),
            (FRAGMENT, {"graph_input_slots": (0,)}),
            (
                STAGE_UNIFORM_PASSTHROUGH_FRAGMENT,
                {"graph_input_slots": (1,)},
            ),
            (
                STAGE_UNIFORM_PASSTHROUGH_FRAGMENT,
                {"graph_input_slots": (0,), "has_external_provider": True},
            ),
            (STRAIGHT_ALPHA_FRAGMENT, {"graph_input_slots": (1,)}),
            (
                STRAIGHT_ALPHA_FRAGMENT,
                {"graph_input_slots": (0,), "has_external_provider": True},
            ),
            (
                CHANNEL_RECONSTRUCTION_FRAGMENT,
                {"graph_input_slots": (1,)},
            ),
            (
                CHANNEL_RECONSTRUCTION_FRAGMENT,
                {"graph_input_slots": (0,), "has_external_provider": True},
            ),
            (
                GRAPH_INPUT_COLOR_BLEND_FRAGMENT,
                {
                    "graph_input_slots": (1,),
                    "color_blend_source_slot": 0,
                },
            ),
            (
                GRAPH_INPUT_COLOR_BLEND_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "color_blend_source_slot": 0,
                    "has_external_provider": True,
                },
            ),
        ):
            with self.subTest(facts=facts), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                ordinary, _, _, ordinary_log = self.run_harness(
                    Path(directory), route="prefer-generic", fragment=fragment,
                    **facts,
                )
                self.assertTrue(ordinary["permitsBoundedFrontend"])
                self.assertIn(
                    "state=prefer-generic profile=ordinary-shader outcome=fallback",
                    ordinary_log,
                )

    def test_migrated_profiles_accept_generic_artifacts_and_fail_closed(self):
        cases = [
            (
                GRAPH_INPUT_COLOR_BLEND_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "color_blend_source_slot": 0,
                },
                "straight-alpha-preserving",
                "source-proven-graph-input-color-blend",
                False,
            ),
            (
                ALPHA_ATTENUATION_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "alpha_attenuation_source_slot": 0,
                },
                "straight-alpha",
                "source-proven-graph-input-alpha-attenuation",
                False,
            ),
            (
                STAGE_UNIFORM_PASSTHROUGH_FRAGMENT,
                {"graph_input_slots": (0,)},
                "passthrough",
                "source-proven-graph-input-stage-uniform-passthrough",
                False,
            ),
            (
                STAGE_UNIFORM_STRAIGHT_PRESERVING_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_defaulted_opacity_mask": True,
                },
                "straight-alpha-preserving",
                "source-proven-graph-input-stage-uniform-straight-alpha-preserving",
                True,
            ),
            (
                FRAGMENT,
                {"graph_slots": (0,)},
                "passthrough",
                "source-proven-graph-target-passthrough",
                False,
            ),
            (
                OPAQUE_FRAGMENT,
                {"produces_scalar_output": True},
                "opaque",
                "source-proven-opaque-scalar-output",
                False,
            ),
            (
                STRAIGHT_PRESERVING_R8_FRAGMENT,
                {"r8_slots": (1,)},
                "straight-alpha-preserving",
                "source-proven-straight-alpha-r8-signal",
                True,
            ),
        ]
        for fragment, facts, transfer, profile, needs_aux in cases:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                root = Path(directory)
                observed, _, cache, _ = self.run_harness(
                    root, route="observe-only", fragment=fragment, **facts
                )
                artifact = self.artifact(
                    observed["requestKey"], color_transfer=transfer
                )
                if needs_aux:
                    artifact["program"]["textureBindings"].append({
                        "name": "g_Texture1",
                        "slot": 1,
                        "channelUse": "redOnly",
                    })
                artifact_path = cache / f"{observed['requestKey']}.json"
                artifact_path.write_text(json.dumps(artifact), encoding="utf-8")

                accepted, _, _, accepted_log = self.run_harness(
                    root, route="prefer-generic", fragment=fragment, **facts
                )
                self.assertEqual(accepted["status"], "accepted")
                self.assertEqual(accepted["backend"], "genericCompilerArtifact")
                self.assertIn(
                    f"state=generic-only profile={profile} outcome=accepted",
                    accepted_log,
                )

                artifact["program"]["metalSourceSHA256"] = "0" * 64
                artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
                rejected, _, _, rejected_log = self.run_harness(
                    root, route="prefer-generic", fragment=fragment, **facts
                )
                self.assertEqual(rejected["code"], "artifact-contract-rejected")
                self.assertFalse(rejected["permitsBoundedFrontend"])
                self.assertIn(
                    f"profile={profile} outcome=rejected "
                    "reason=artifact-contract-rejected",
                    rejected_log,
                )

    def test_preferred_graph_input_profiles_accept_generic_then_fallback_locally(
        self,
    ):
        cases = [
            (
                STRAIGHT_ALPHA_FRAGMENT,
                {"graph_input_slots": (0,)},
                "straight-alpha",
                "source-proven-graph-input-straight-alpha",
            ),
            (
                CHANNEL_RECONSTRUCTION_FRAGMENT,
                {"graph_input_slots": (0,)},
                "straight-alpha-preserving",
                "source-proven-graph-input-straight-alpha-preserving",
            ),
        ]
        for fragment, facts, transfer, profile in cases:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                root = Path(directory)
                observed, _, cache, _ = self.run_harness(
                    root, route="observe-only", fragment=fragment, **facts
                )
                artifact = self.artifact(
                    observed["requestKey"], color_transfer=transfer
                )
                artifact_path = cache / f"{observed['requestKey']}.json"
                artifact_path.write_text(json.dumps(artifact), encoding="utf-8")

                accepted, _, _, accepted_log = self.run_harness(
                    root, route=None, fragment=fragment, **facts
                )
                self.assertEqual(accepted["status"], "accepted")
                self.assertEqual(accepted["backend"], "genericCompilerArtifact")
                self.assertIn(
                    f"state=prefer-generic profile={profile} outcome=accepted",
                    accepted_log,
                )

                artifact["program"]["metalSourceSHA256"] = "0" * 64
                artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
                fallback, _, _, fallback_log = self.run_harness(
                    root, route=None, fragment=fragment, **facts
                )
                self.assertEqual(fallback["code"], "artifact-contract-rejected")
                self.assertTrue(fallback["permitsBoundedFrontend"])
                self.assertIn(
                    f"state=prefer-generic profile={profile} outcome=fallback "
                    "reason=artifact-contract-rejected",
                    fallback_log,
                )

    def test_film_grain_stock_shape_uses_shared_program_and_local_artifact_fallback(
        self,
    ):
        facts = {"graph_input_slots": (0,)}
        profile = "source-proven-graph-input-straight-alpha-preserving"
        with tempfile.TemporaryDirectory(
            prefix="mwx-film-grain-shared-artifact-test-"
        ) as directory:
            root = Path(directory)
            observed, _, cache, _ = self.run_harness(
                root,
                route="observe-only",
                fragment=FILM_GRAIN_STOCK_FRAGMENT,
                **facts,
            )
            artifact = self.artifact(
                observed["requestKey"],
                color_transfer="straight-alpha-preserving",
            )
            artifact_path = cache / f"{observed['requestKey']}.json"
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")

            accepted, _, _, accepted_log = self.run_harness(
                root,
                route=None,
                fragment=FILM_GRAIN_STOCK_FRAGMENT,
                **facts,
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["backend"], "genericCompilerArtifact")
            self.assertIn(
                f"state=prefer-generic profile={profile} outcome=accepted",
                accepted_log,
            )

            artifact["program"]["metalSourceSHA256"] = "0" * 64
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            fallback, _, _, fallback_log = self.run_harness(
                root,
                route=None,
                fragment=FILM_GRAIN_STOCK_FRAGMENT,
                **facts,
            )
            self.assertEqual(fallback["code"], "artifact-contract-rejected")
            self.assertTrue(fallback["permitsBoundedFrontend"])
            self.assertIn(
                f"state=prefer-generic profile={profile} outcome=fallback "
                "reason=artifact-contract-rejected",
                fallback_log,
            )


if __name__ == "__main__":
    unittest.main()
