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
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
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

private struct PreservedChannelUseOutput: Codable {
    let directRedGreen: String?
    let mixedProjection: String?
}

private struct PreservedRGBADataBuilderOutput: Codable {
    let outputSemantics: String?
    let colorTransfer: String?
    let wholeOutputAccepted: Bool
    let helperOutputRejected: Bool
}

private struct NormalizedSampleSumOutput: Codable {
    let analyzedTransfer: String
    let positiveKind: String?
    let positiveSlot: Int?
    let renamedHelperAccepted: Bool
    let immutableAliasAccepted: Bool
    let mutatedAliasRejected: Bool
    let reusedAliasRejected: Bool
    let conditionalAliasRejected: Bool
    let nonNormalizedRejected: Bool
    let negativeWeightRejected: Bool
    let zeroWeightRejected: Bool
    let mixedSlotRejected: Bool
    let hiddenSampleRejected: Bool
    let branchingHelperRejected: Bool
}

private struct AlphaWeightedSampleAverageOutput: Codable {
    let analyzedTransfer: String
    let sourceSlot: Int?
    let sampleCount: Int?
    let renamedLocalsAccepted: Bool
    let threeSampleCombinationAccepted: Bool
    let boundedFrontendAccepted: Bool
    let boundedSampleUnpremultipliedCount: Int
    let boundedOutputPremultiplied: Bool
    let positiveKind: String?
    let positiveSlot: Int?
    let genericSampleUnpremultipliedCount: Int
    let genericOutputPremultiplied: Bool
    let denominatorMismatchRejected: Bool
    let hiddenSampleRejected: Bool
    let wrongWeightRejected: Bool
    let wrongNormalizationRejected: Bool
    let earlyNormalizationRejected: Bool
    let compilerDriftRejected: Bool
    let helperConflictRejected: Bool
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
    let directKind: String?
    let directFailure: String?
    let directSampleCount: Int
    let directOutputPremultiplied: Bool
    let directAlphaWriteRejected: Bool
    let directHiddenSampleRejected: Bool
    let directWrongSlotRejected: Bool
    let nonAudioVectorArrayRejected: Bool
}

private struct StraightAttenuationBuilderOutput: Codable {
    let analyzedTransfer: String
    let positiveKind: String?
    let positiveSlot: Int?
    let sampleUnpremultiplied: Bool
    let alphaOnlyMutationPreserved: Bool
    let outputPremultiplied: Bool
    let unrelatedAlphaReadRejected: Bool
    let wholeVectorUseRejected: Bool
    let rgbWriteRejected: Bool
}

private struct StraightOutputBuilderOutput: Codable {
    let analyzedTransfer: String
    let positiveKind: String?
    let positiveSlot: Int?
    let sampleUnpremultiplied: Bool
    let outputPremultiplied: Bool
    let wrongSlotRejected: Bool
    let duplicateOutputRejected: Bool
    let helperConflictRejected: Bool
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

private struct MutableFragmentVaryingOutput: Codable {
    let mainMutationLowered: Bool
    let interfacePreserved: Bool
    let helperMutationRejected: Bool
    let arrayMutationRejected: Bool
    let readOnlyPreserved: Bool
}

private struct TypedMixNormalizationOutput: Codable {
    let firstWideArgumentNarrowed: Bool
    let secondWideArgumentNarrowed: Bool
    let vec2ArgumentNarrowed: Bool
    let explicitSwizzlePreserved: Bool
    let userDefinedMixPreserved: Bool
    let invalidWeightPreserved: Bool
}

private struct CanonicalizerOutput: Codable {
    let arraysCompacted: Bool
    let loopsUnrolled: Bool
    let boundedFrontendAccepted: Bool
    let genericNormalizerAccepted: Bool
    let assignmentNarrowed: Bool
    let smallArrayLoopUnrolled: Bool
    let smallArrayBoundedFrontendAccepted: Bool
    let smallArrayGenericNormalizerAccepted: Bool
    let smallArrayDynamicBoundPreserved: Bool
    let smallArrayOutOfBoundsPreserved: Bool
    let dynamicBoundPreserved: Bool
    let controlFlowPreserved: Bool
    let outOfPrefixPreserved: Bool
}

private func colorTransferName(_ transfer: SceneShaderColorTransfer) -> String {
    switch transfer {
    case .passthrough: return "passthrough"
    case .interpolatedColor: return "interpolatedColor"
    case .straightAlpha: return "straightAlpha"
    case .straightAlphaPreserving: return "straightAlphaPreserving"
    case .premultipliedAlpha: return "premultipliedAlpha"
    case .opaque: return "opaque"
    case .unresolved: return "unresolved"
    default: return "other"
    }
}

@main
private struct GenericShaderArtifactHarness {
    static func main() throws {
        if CommandLine.arguments[1] == "--backend-canonicalizer" {
            let vertex = [
                "attribute vec3 a_Position;",
                "attribute vec2 a_TexCoord;",
                "varying vec2 v_TexCoord;",
                "varying vec3 v_Mask;",
                "varying vec3 v_Colors[24];",
                "varying vec3 v_Settings[24];",
                "void main() {",
                "    gl_Position = vec4(a_Position, 1.0);",
                "    v_TexCoord = a_TexCoord;",
                "    v_Mask = vec3(a_TexCoord, 1.0);",
                "    for (int i = 0; i < int(float(24) * 0.25); ++i) v_Settings[i] = vec3(0.0);",
                "    v_Colors[0] = vec3(0.0); v_Colors[1] = vec3(0.1);",
                "    v_Colors[2] = vec3(0.2); v_Colors[3] = vec3(0.3);",
                "    v_Colors[4] = vec3(0.4); v_Colors[5] = vec3(0.5);",
                "}",
            ].joined(separator: "\n")
            let fragment = [
                "varying vec2 v_TexCoord;",
                "varying vec3 v_Mask;",
                "varying vec3 v_Colors[24];",
                "varying vec3 v_Settings[24];",
                "void main() {",
                "    float nColors = float(24) * 0.25;",
                "    vec3 color = vec3(0.0);",
                "    for (int i = 0; i < int(nColors); ++i) {",
                "        /* A comment brace } must not terminate the loop body. */",
                "        color += v_Colors[i] + v_Settings[i] * float(i);",
                "    }",
                "    vec2 norm = step(0.5, abs(v_Mask - 0.5));",
                "    gl_FragColor = vec4(color + vec3(norm, 0.0), 1.0);",
                "}",
            ].joined(separator: "\n")
            let canonical = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: vertex,
                fragment: fragment
            )
            let bounded = SceneAuthoredShaderFrontend.compile(
                vertexSource: canonical.vertex,
                fragmentSource: canonical.fragment
            )
            let normalized: SceneGenericShaderSourceNormalizer.Pair?
            switch SceneGenericShaderSourceNormalizer.normalize(
                vertexSource: canonical.vertex,
                fragmentSource: canonical.fragment,
                maximumStageSourceBytes: 64 * 1_024
            ) {
            case let .success(pair): normalized = pair
            case .failure: normalized = nil
            }
            let dynamicVertex = vertex.replacingOccurrences(
                of: "int(float(24) * 0.25)",
                with: "g_Count"
            ).replacingOccurrences(
                of: "attribute vec3 a_Position;",
                with: "uniform int g_Count;\nattribute vec3 a_Position;"
            )
            let dynamic = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: dynamicVertex,
                fragment: fragment
            )
            let controlVertex = vertex.replacingOccurrences(
                of: "v_Settings[i] = vec3(0.0);",
                with: "{ v_Settings[i] = vec3(0.0); break; }"
            )
            let controlled = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: controlVertex,
                fragment: fragment
            )
            let prefixVertex = vertex.replacingOccurrences(
                of: "v_Colors[5] = vec3(0.5);",
                with: "v_Colors[5] = vec3(0.5); v_Colors[20] = vec3(1.0);"
            )
            let prefix = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: prefixVertex,
                fragment: fragment
            )
            let smallVertex = [
                "attribute vec3 a_Position;",
                "attribute vec2 a_TexCoord;",
                "varying vec2 v_Samples[4];",
                "void main() {",
                "    gl_Position = vec4(a_Position, 1.0);",
                "    v_Samples[0] = a_TexCoord - vec2(0.1);",
                "    v_Samples[1] = a_TexCoord + vec2(0.1, -0.1);",
                "    v_Samples[2] = a_TexCoord + vec2(-0.1, 0.1);",
                "    v_Samples[3] = a_TexCoord + vec2(0.1);",
                "}",
            ].joined(separator: "\n")
            let smallFragment = [
                "uniform sampler2D g_Texture0;",
                "varying vec2 v_Samples[4];",
                "void main() {",
                "    vec4 total = vec4(0.0);",
                "    for (int i = 0; i < 4; ++i) {",
                "        total += texSample2D(g_Texture0, v_Samples[i]) * 0.25;",
                "    }",
                "    gl_FragColor = total;",
                "}",
            ].joined(separator: "\n")
            let small = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: smallVertex,
                fragment: smallFragment
            )
            let smallBounded = SceneAuthoredShaderFrontend.compile(
                vertexSource: small.vertex,
                fragmentSource: small.fragment
            )
            let smallNormalized: SceneGenericShaderSourceNormalizer.Pair?
            switch SceneGenericShaderSourceNormalizer.normalize(
                vertexSource: small.vertex,
                fragmentSource: small.fragment,
                maximumStageSourceBytes: 64 * 1_024
            ) {
            case let .success(pair): smallNormalized = pair
            case .failure: smallNormalized = nil
            }
            let smallDynamicSource = smallFragment.replacingOccurrences(
                of: "i < 4", with: "i < g_Count"
            ).replacingOccurrences(
                of: "uniform sampler2D g_Texture0;",
                with: "uniform int g_Count;\nuniform sampler2D g_Texture0;"
            )
            let smallDynamic = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: smallVertex,
                fragment: smallDynamicSource
            )
            let smallOutOfBoundsSource = smallFragment.replacingOccurrences(
                of: "i < 4", with: "i < 5"
            )
            let smallOutOfBounds = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: smallVertex,
                fragment: smallOutOfBoundsSource
            )
            let output = CanonicalizerOutput(
                arraysCompacted:
                    canonical.vertex.contains("v_Colors[6]")
                    && canonical.fragment.contains("v_Settings[6]"),
                loopsUnrolled:
                    !canonical.vertex.contains("for (")
                    && !canonical.fragment.contains("for ("),
                boundedFrontendAccepted:
                    bounded.diagnostics.isEmpty && bounded.program != nil,
                genericNormalizerAccepted: normalized != nil,
                assignmentNarrowed:
                    normalized?.fragment.contains(").xy") == true,
                smallArrayLoopUnrolled:
                    !small.fragment.contains("for (")
                    && (0 ..< 4).allSatisfy {
                        small.fragment.contains("v_Samples[\($0)]")
                    },
                smallArrayBoundedFrontendAccepted:
                    smallBounded.diagnostics.isEmpty && smallBounded.program != nil,
                smallArrayGenericNormalizerAccepted: smallNormalized != nil,
                smallArrayDynamicBoundPreserved:
                    smallDynamic.fragment.contains("v_Samples[i]")
                    && smallDynamic.fragment.contains("g_Count"),
                smallArrayOutOfBoundsPreserved:
                    smallOutOfBounds.fragment.contains("v_Samples[i]")
                    && smallOutOfBounds.fragment.contains("i < 5"),
                dynamicBoundPreserved:
                    dynamic.vertex.contains("v_Settings[24]")
                    && dynamic.vertex.contains("g_Count"),
                controlFlowPreserved:
                    controlled.vertex.contains("break")
                    && controlled.vertex.contains("v_Settings[24]"),
                outOfPrefixPreserved:
                    prefix.vertex.contains("v_Colors[24]")
                    && prefix.vertex.contains("v_Colors[20]")
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
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
        if CommandLine.arguments[1] == "--normalizer-mutable-fragment-varying" {
            let vertex = [
                "attribute vec3 a_Position;",
                "attribute vec2 a_TexCoord;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    gl_Position = vec4(a_Position, 1.0);",
                "    v_TexCoord = a_TexCoord;",
                "}",
            ].joined(separator: "\n")
            func normalized(_ fragment: String) -> Result<
                SceneGenericShaderSourceNormalizer.Pair,
                SceneGenericShaderSourceNormalizer.Failure
            > {
                SceneGenericShaderSourceNormalizer.normalize(
                    vertexSource: vertex,
                    fragmentSource: fragment,
                    maximumStageSourceBytes: 64 * 1_024
                )
            }
            let mutable = normalized([
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    v_TexCoord.y = 1.0 - v_TexCoord.y;",
                "    v_TexCoord += vec2(0.25);",
                "    gl_FragColor = vec4(v_TexCoord, 0.0, 1.0);",
                "}",
            ].joined(separator: "\n"))
            let helper = normalized([
                "varying vec2 v_TexCoord;",
                "vec2 helper() { return v_TexCoord; }",
                "void main() {",
                "    v_TexCoord.y = 1.0 - v_TexCoord.y;",
                "    gl_FragColor = vec4(helper(), 0.0, 1.0);",
                "}",
            ].joined(separator: "\n"))
            let arrayVertex = vertex.replacingOccurrences(
                of: "varying vec2 v_TexCoord;",
                with: "varying vec2 v_TexCoord[2];"
            ).replacingOccurrences(
                of: "v_TexCoord = a_TexCoord;",
                with: "v_TexCoord[0] = a_TexCoord;"
            )
            let array = SceneGenericShaderSourceNormalizer.normalize(
                vertexSource: arrayVertex,
                fragmentSource: [
                    "varying vec2 v_TexCoord[2];",
                    "void main() {",
                    "    v_TexCoord[0].y = 1.0 - v_TexCoord[0].y;",
                    "    gl_FragColor = vec4(v_TexCoord[0], 0.0, 1.0);",
                    "}",
                ].joined(separator: "\n"),
                maximumStageSourceBytes: 64 * 1_024
            )
            let readOnly = normalized([
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    gl_FragColor = vec4(v_TexCoord, 0.0, 1.0);",
                "}",
            ].joined(separator: "\n"))
            let mutableSource: String
            switch mutable {
            case let .success(pair): mutableSource = pair.fragment
            case .failure: mutableSource = ""
            }
            let output = MutableFragmentVaryingOutput(
                mainMutationLowered:
                    mutableSource.contains(
                        "vec2 mwxMutable_v_TexCoord = v_TexCoord;"
                    )
                    && mutableSource.contains(
                        "mwxMutable_v_TexCoord.y = 1.0 - mwxMutable_v_TexCoord.y"
                    )
                    && mutableSource.contains(
                        "mwxMutable_v_TexCoord += vec2(0.25)"
                    ),
                interfacePreserved: mutableSource.contains(
                    "in vec2 v_TexCoord;"
                ),
                helperMutationRejected: {
                    if case .failure(.varyingUnsupported) = helper { return true }
                    return false
                }(),
                arrayMutationRejected: {
                    if case .failure(.varyingUnsupported) = array { return true }
                    return false
                }(),
                readOnlyPreserved: {
                    guard case let .success(pair) = readOnly else { return false }
                    return !pair.fragment.contains("mwxMutable_v_TexCoord")
                }()
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
        if CommandLine.arguments[1] == "--builder-alpha-weighted-sample-average" {
            func authoredSource(
                count: Int,
                accumulator: String = "result",
                sample: String = "sample",
                weight: String = "weight"
            ) -> String {
                let samples = (0..<count).map { index in
                    [
                        "    {",
                        "        \(sample) = texSample2D(g_Texture0, v_TexCoord[\(index)]);",
                        "        \(accumulator) += \(sample) * \(sample).a;",
                        "        \(weight) += \(sample).a;",
                        "    }",
                    ].joined(separator: "\n")
                }.joined(separator: "\n")
                return [
                    "uniform sampler2D g_Texture0;",
                    "varying vec2 v_TexCoord[\(count)];",
                    "void main() {",
                    "    float \(weight) = 0.0;",
                    "    vec4 \(accumulator) = CAST4(0.0), \(sample);",
                    samples,
                    "    \(accumulator).rgb /= max(0.001, \(weight));",
                    "    gl_FragColor = vec4(\(accumulator).rgb, \(accumulator).a / \(count).0);",
                    "}",
                ].joined(separator: "\n")
            }
            func vertexSource(count: Int) -> String {
                let assignments = (0..<count).map {
                    "    v_TexCoord[\($0)] = a_TexCoord + vec2(\(Double($0) * 0.01));"
                }.joined(separator: "\n")
                return [
                    "attribute vec3 a_Position;",
                    "attribute vec2 a_TexCoord;",
                    "varying vec2 v_TexCoord[\(count)];",
                    "void main() {",
                    "    gl_Position = vec4(a_Position, 1.0);",
                    assignments,
                    "}",
                ].joined(separator: "\n")
            }
            func metalSource(count: Int) -> String {
                let samples = (0..<count).map { index in
                    let assignment = index == 0
                        ? "    float4 mwx_sample = g_Texture0.sample(g_Texture0Smplr, v_TexCoord[\(index)]);"
                        : "    mwx_sample = g_Texture0.sample(g_Texture0Smplr, v_TexCoord[\(index)]);"
                    return [
                        assignment,
                        "    result += (mwx_sample * mwx_sample.w);",
                        "    weight += mwx_sample.w;",
                    ].joined(separator: "\n")
                }.joined(separator: "\n")
                return [
                    "#include <metal_stdlib>",
                    "using namespace metal;",
                    "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
                    "fragment void f() {",
                    "    float weight = 0.0;",
                    "    float4 result = float4(0.0);",
                    samples,
                    "    float4 _92 = result;",
                    "    float3 _95 = _92.xyz / float3(fast::max(0.001, weight));",
                    "    result.x = _95.x;",
                    "    result.y = _95.y;",
                    "    result.z = _95.z;",
                    "    out.mwxFragColor = float4(result.xyz, result.w / \(count).0);",
                    "}",
                ].joined(separator: "\n")
            }
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16}]}},"ubos":[{"type":"_1","block_size":32,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            func artifact(authored: String, msl: String) -> SceneGenericShaderProgramArtifact? {
                let built = SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "a", count: 64),
                    backendID: "glslang-spirv-cross-msl-v2",
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL,
                            reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: authored,
                            authoredSource: authored,
                            msl: msl,
                            reflection: reflection
                        ),
                    ],
                    maximumArtifactBytes: 1_024_000
                )
                guard case let .success(value) = built else { return nil }
                return value
            }
            let authored = authoredSource(count: 4)
            let fact = SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                fragmentSource: authored
            )
            let bounded = SceneAuthoredShaderFrontend.compile(
                vertexSource: vertexSource(count: 4),
                fragmentSource: authored
            ).program
            let positive = artifact(authored: authored, msl: metalSource(count: 4))
            let genericMetal = positive?.program.metalSource ?? ""
            let boundedMetal = bounded?.metalSource ?? ""
            let renamed = authoredSource(
                count: 4,
                accumulator: "unseenColor",
                sample: "unseenTap",
                weight: "unseenWeight"
            )
            let compilerDrift = metalSource(count: 4).replacingOccurrences(
                of: "    out.mwxFragColor =",
                with: "    float4 hidden = g_Texture0.sample(g_Texture0Smplr, float2(0.5));\n    out.mwxFragColor ="
            )
            let helperConflict = metalSource(count: 4).replacingOccurrences(
                of: "using namespace metal;",
                with: "using namespace metal;\nfloat4 mwxGenericUnpremultiply(float4 value) { return value; }"
            )
            let output = AlphaWeightedSampleAverageOutput(
                analyzedTransfer: colorTransferName(
                    SceneAuthoredShaderColorTransferAnalyzer.analyze(
                        fragmentSource: authored
                    )
                ),
                sourceSlot: fact?.textureSlot,
                sampleCount: fact?.sampleCount,
                renamedLocalsAccepted:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: renamed
                    ) == .init(textureSlot: 0, sampleCount: 4),
                threeSampleCombinationAccepted:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: authoredSource(count: 3)
                    ) == .init(textureSlot: 0, sampleCount: 3),
                boundedFrontendAccepted: bounded != nil,
                boundedSampleUnpremultipliedCount:
                    boundedMetal.components(
                        separatedBy: "mwxUnpremultiply(mwxTexture0.sample("
                    ).count - 1,
                boundedOutputPremultiplied:
                    boundedMetal.contains("return mwxPremultiply(mwxFragColor);"),
                positiveKind: positive?.program.colorTransfer.kind,
                positiveSlot: positive?.program.colorTransfer.slot,
                genericSampleUnpremultipliedCount:
                    genericMetal.components(
                        separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
                    ).count - 1,
                genericOutputPremultiplied:
                    genericMetal.contains(
                        "out.mwxFragColor = mwxGenericPremultiply(float4(result.xyz, result.w / 4.0));"
                    ),
                denominatorMismatchRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: authored.replacingOccurrences(
                            of: "result.a / 4.0", with: "result.a / 3.0"
                        )
                    ) == nil,
                hiddenSampleRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: authored.replacingOccurrences(
                            of: "    result.rgb /=",
                            with: "    vec4 hidden = texSample2D(g_Texture0, vec2(0.5));\n    result.rgb /="
                        )
                    ) == nil,
                wrongWeightRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: authored.replacingOccurrences(
                            of: "result += sample * sample.a;",
                            with: "result += sample * 0.5;",
                            options: [],
                            range: authored.range(of: "result += sample * sample.a;")
                        )
                    ) == nil,
                wrongNormalizationRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: authored.replacingOccurrences(
                            of: "max(0.001, weight)", with: "max(0.001, weight + 1.0)"
                        )
                    ) == nil,
                earlyNormalizationRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: authored.replacingOccurrences(
                            of: "    result.rgb /= max(0.001, weight);",
                            with: ""
                        ).replacingOccurrences(
                            of: "    {\n        sample = texSample2D(g_Texture0, v_TexCoord[3]);",
                            with: "    result.rgb /= max(0.001, weight);\n    {\n        sample = texSample2D(g_Texture0, v_TexCoord[3]);"
                        )
                    ) == nil,
                compilerDriftRejected: artifact(
                    authored: authored, msl: compilerDrift
                ) == nil,
                helperConflictRejected: artifact(
                    authored: authored, msl: helperConflict
                ) == nil
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-preserved-channel-use" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16}]}},"ubos":[{"type":"_1","block_size":32,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            let authored = [
                "uniform sampler2D g_Texture0;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    vec2 pair = texSample2D(g_Texture0, v_TexCoord).rg;",
                "    gl_FragColor = vec4(pair, 0.0, 1.0);",
                "}",
            ].joined(separator: "\n")
            func channelUse(_ fragmentMSL: String) -> String? {
                let built = SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "e", count: 64),
                    backendID: "glslang-spirv-cross-msl-v2",
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL, reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: authored,
                            authoredSource: authored,
                            msl: fragmentMSL, reflection: reflection
                        ),
                    ],
                    maximumArtifactBytes: 1_024_000
                )
                guard case let .success(artifact) = built else { return nil }
                return artifact.program.textureBindings.first?.channelUse
            }
            let direct = [
                "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
                "fragment void f() {",
                "    float2 pair = g_Texture0.sample(s, uv).xy;",
                "    out.mwxFragColor = float4(pair, 0.0, 1.0);",
                "}",
            ].joined(separator: "\n")
            let mixed = direct.replacingOccurrences(
                of: "out.mwxFragColor = float4(pair, 0.0, 1.0);",
                with: [
                    "float red = g_Texture0.sample(s, uv).x;",
                    "    out.mwxFragColor = float4(pair.x + red, pair.y, 0.0, 1.0);",
                ].joined(separator: "\n")
            )
            let output = PreservedChannelUseOutput(
                directRedGreen: channelUse(direct),
                mixedProjection: channelUse(mixed)
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-preserved-rgba-data" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16}]}},"ubos":[{"type":"_1","block_size":32,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            let wholeOutput = [
                "uniform sampler2D g_Texture0;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    vec4 state = texSample2D(g_Texture0, v_TexCoord);",
                "    state.rg += state.ba * 0.25;",
                "    gl_FragColor = state;",
                "}",
            ].joined(separator: "\n")
            let helperOutput = wholeOutput.replacingOccurrences(
                of: "    gl_FragColor = state;",
                with: "    WriteOutput(state);"
            )
            let fragmentMSL = [
                "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
                "fragment void f() {",
                "    float4 state = g_Texture0.sample(s, uv);",
                "    state.xy += state.zw * 0.25;",
                "    out.mwxFragColor = state;",
                "}",
            ].joined(separator: "\n")
            func build(_ source: String) -> Result<
                SceneGenericShaderProgramArtifact,
                SceneGenericShaderArtifactBuilder.Failure
            > {
                SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "9", count: 64),
                    backendID: "glslang-spirv-cross-msl-v2",
                    outputSemantics: .preservedRGBAUnorm,
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL, reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: source,
                            authoredSource: source,
                            msl: fragmentMSL, reflection: reflection
                        ),
                    ],
                    maximumArtifactBytes: 1_024_000
                )
            }
            let accepted = build(wholeOutput)
            let artifact: SceneGenericShaderProgramArtifact?
            if case let .success(value) = accepted { artifact = value }
            else { artifact = nil }
            let output = PreservedRGBADataBuilderOutput(
                outputSemantics: artifact?.outputSemantics.rawValue,
                colorTransfer: artifact?.program.colorTransfer.kind,
                wholeOutputAccepted: artifact != nil,
                helperOutputRejected: failedColorTransfer(build(helperOutput))
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-normalized-sample-sum" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16}]}},"ubos":[{"type":"_1","block_size":32,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            let fragmentMSL = [
                "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
                "fragment void f() {",
                "    float4 color = g_Texture0.sample(s, uv - delta) * 0.25",
                "        + g_Texture0.sample(s, uv) * 0.5",
                "        + g_Texture0.sample(s, uv + delta) * 0.25;",
                "    out.mwxFragColor = color;",
                "}",
            ].joined(separator: "\n")
            let authored = [
                "uniform sampler2D g_Texture0;",
                "varying vec2 v_TexCoord;",
                "vec4 sharedKernel(vec2 uv, vec2 delta) {",
                "    vec2 offset = delta * 1.0;",
                "    return texSample2D(g_Texture0, uv - offset) * 0.25",
                "        + texSample2D(g_Texture0, uv) * 0.5",
                "        + texSample2D(g_Texture0, uv + offset) * 0.25;",
                "}",
                "void main() {",
                "    gl_FragColor = sharedKernel(v_TexCoord, vec2(0.01));",
                "}",
            ].joined(separator: "\n")
            func transfer(_ source: String) -> SceneShaderColorTransfer {
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: source
                )
            }
            func isPassthrough(_ source: String) -> Bool {
                transfer(source) == .passthrough(textureSlot: 0)
            }
            let aliased = authored.replacingOccurrences(
                of: "    gl_FragColor = sharedKernel(v_TexCoord, vec2(0.01));",
                with: [
                    "    vec4 filtered = sharedKernel(v_TexCoord, vec2(0.01));",
                    "    gl_FragColor = filtered;",
                ].joined(separator: "\n")
            )
            let built = SceneGenericShaderArtifactBuilder.build(
                requestKey: String(repeating: "f", count: 64),
                backendID: "glslang-spirv-cross-msl-v2",
                stages: [
                    .init(
                        name: "vertex", source: "void main() {}",
                        authoredSource: "void main() {}",
                        msl: vertexMSL, reflection: reflection
                    ),
                    .init(
                        name: "fragment", source: authored,
                        authoredSource: authored,
                        msl: fragmentMSL, reflection: reflection
                    ),
                ],
                maximumArtifactBytes: 1_024_000
            )
            let artifact: SceneGenericShaderProgramArtifact?
            switch built {
            case let .success(value): artifact = value
            case .failure: artifact = nil
            }
            let output = NormalizedSampleSumOutput(
                analyzedTransfer: colorTransferName(transfer(authored)),
                positiveKind: artifact?.program.colorTransfer.kind,
                positiveSlot: artifact?.program.colorTransfer.slot,
                renamedHelperAccepted: isPassthrough(
                    authored.replacingOccurrences(
                        of: "sharedKernel", with: "unseenFilter"
                    )
                ),
                immutableAliasAccepted: isPassthrough(aliased),
                mutatedAliasRejected: !isPassthrough(
                    aliased.replacingOccurrences(
                        of: "    gl_FragColor = filtered;",
                        with: "    filtered.a *= 0.5;\n    gl_FragColor = filtered;"
                    )
                ),
                reusedAliasRejected: !isPassthrough(
                    aliased.replacingOccurrences(
                        of: "    gl_FragColor = filtered;",
                        with: "    vec4 copy = filtered;\n    gl_FragColor = filtered;"
                    )
                ),
                conditionalAliasRejected: !isPassthrough(
                    aliased.replacingOccurrences(
                        of: "    vec4 filtered = sharedKernel(v_TexCoord, vec2(0.01));",
                        with: [
                            "    vec4 filtered;",
                            "    if (v_TexCoord.x > 0.5) {",
                            "        filtered = sharedKernel(v_TexCoord, vec2(0.01));",
                            "    }",
                        ].joined(separator: "\n")
                    )
                ),
                nonNormalizedRejected: !isPassthrough(
                    authored.replacingOccurrences(of: "* 0.5", with: "* 0.4")
                ),
                negativeWeightRejected: !isPassthrough(
                    authored.replacingOccurrences(
                        of: "+ texSample2D(g_Texture0, uv + offset) * 0.25",
                        with: "- texSample2D(g_Texture0, uv + offset) * 0.25"
                    )
                ),
                zeroWeightRejected: !isPassthrough(
                    authored.replacingOccurrences(of: "* 0.5", with: "* 0.0")
                ),
                mixedSlotRejected: !isPassthrough(
                    authored.replacingOccurrences(
                        of: "texSample2D(g_Texture0, uv + offset)",
                        with: "texSample2D(g_Texture1, uv + offset)"
                    )
                ),
                hiddenSampleRejected: !isPassthrough(
                    authored.replacingOccurrences(
                        of: "vec2 offset = delta * 1.0;",
                        with: "vec2 offset = texSample2D(g_Texture0, uv).xy * delta;"
                    )
                ),
                branchingHelperRejected: !isPassthrough(
                    authored.replacingOccurrences(
                        of: "vec2 offset = delta * 1.0;",
                        with: "vec2 offset = delta * 1.0; if (uv.x < 0.0) return vec4(0.0);"
                    )
                )
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-interpolation" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"rate","type":"float","offset":0},{"name":"mwxRenderSize","type":"vec2","offset":8},{"name":"mwxTexture0Transform0","type":"vec4","offset":16},{"name":"mwxTexture0Transform1","type":"vec4","offset":32},{"name":"mwxTexture1Transform0","type":"vec4","offset":48},{"name":"mwxTexture1Transform1","type":"vec4","offset":64}]}},"ubos":[{"type":"_1","block_size":80,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float rate; float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };"
            let fragmentMSL = [
                "struct MWXUniforms { float rate; float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };",
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
                    backendID: "glslang-spirv-cross-msl-v2",
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
            let vertexReflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"mwxTexture0Transform0","type":"vec4","offset":16},{"name":"mwxTexture0Transform1","type":"vec4","offset":32},{"name":"mwxTexture1Transform0","type":"vec4","offset":48},{"name":"mwxTexture1Transform1","type":"vec4","offset":64}]}},"ubos":[{"type":"_1","block_size":80,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)
            let fragmentReflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"g_AudioSpectrum16Left","type":"float","offset":16,"array":[16]},{"name":"mwxTexture0Transform0","type":"vec4","offset":80},{"name":"mwxTexture0Transform1","type":"vec4","offset":96},{"name":"mwxTexture1Transform0","type":"vec4","offset":112},{"name":"mwxTexture1Transform1","type":"vec4","offset":128}]}},"ubos":[{"type":"_1","block_size":144,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };"
            let fragmentMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float2 mwxRenderSize; float g_AudioSpectrum16Left[16]; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 albedo = g_Texture0.sample(sourceSampler, uv);",
                "    float signal = g_Texture1.sample(signalSampler, uv).x;",
                "    float audio = uniforms.g_AudioSpectrum16Left[int(signal)].x;",
                "    albedo.xyz *= signal;",
                "    out.mwxFragColor = albedo;",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            let authored = [
                "uniform sampler2D g_Texture0;",
                "uniform sampler2D g_Texture1;",
                "uniform float g_AudioSpectrum16Left[16];",
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
                "struct MWXUniforms { float2 mwxRenderSize; float g_AudioSpectrum16Left[16]; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 scene = g_Texture0.sample(sourceSampler, uv);",
                "    float4 rValue = g_Texture0.sample(sourceSampler, uv);",
                "    float4 gValue = g_Texture0.sample(sourceSampler, uv);",
                "    float4 bValue = g_Texture0.sample(sourceSampler, uv);",
                "    float signal = g_Texture1.sample(signalSampler, uv).x;",
                "    float audio = uniforms.g_AudioSpectrum16Left[int(signal)].x;",
                "    float3 finalColor = scene.rgb;",
                "    finalColor = mix(finalColor, rValue.rgb, 0.5);",
                "    finalColor += gValue.rgb * 0.1 + bValue.rgb * 0.1 + signal;",
                "    float alpha = scene.w;",
                "    out.mwxFragColor = float4(finalColor, alpha);",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            let directMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float2 mwxRenderSize; float g_AudioSpectrum16Left[16]; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 retained = g_Texture0.sample(sourceSampler, uv);",
                "    float4 shiftedRed = g_Texture0.sample(sourceSampler, uv + 0.01);",
                "    float4 shiftedBlue = g_Texture0.sample(sourceSampler, uv - 0.01);",
                "    float4 renamedCarrier = retained;",
                "    renamedCarrier.x = shiftedRed.x;",
                "    renamedCarrier.z = shiftedBlue.z;",
                "    out.mwxFragColor = renamedCarrier;",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            let directAuthored = [
                "uniform sampler2D g_Texture0;",
                "varying vec2 v_TexCoord;",
                "void main() {",
                "    vec4 retained = texSample2D(g_Texture0, v_TexCoord);",
                "    vec4 shiftedRed = texSample2D(g_Texture0, v_TexCoord + 0.01);",
                "    vec4 shiftedBlue = texSample2D(g_Texture0, v_TexCoord - 0.01);",
                "    vec4 renamedCarrier = retained;",
                "    renamedCarrier.r = shiftedRed.r;",
                "    renamedCarrier.b = shiftedBlue.b;",
                "    gl_FragColor = renamedCarrier;",
                "}",
            ].joined(separator: "\n")
            let directReflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"g_AudioSpectrum16Left","type":"float","offset":16,"array":[16]},{"name":"mwxTexture0Transform0","type":"vec4","offset":80},{"name":"mwxTexture0Transform1","type":"vec4","offset":96}]}},"ubos":[{"type":"_1","block_size":112,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let directVertexReflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0}]}},"ubos":[{"type":"_1","block_size":8,"set":0,"binding":8}],"textures":[]}"#.utf8)
            func build(
                _ msl: String,
                authoredSource: String? = nil,
                reflection: Data? = nil,
                vertexReflectionValue: Data? = nil
            ) -> Result<
                SceneGenericShaderProgramArtifact,
                SceneGenericShaderArtifactBuilder.Failure
            > {
                let authoredSource = authoredSource ?? authored
                return SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "b", count: 64),
                    backendID: "glslang-spirv-cross-msl-v2",
                    stages: [
                        .init(
                            name: "vertex", source: "void main() {}",
                            authoredSource: "void main() {}",
                            msl: vertexMSL,
                            reflection: vertexReflectionValue ?? vertexReflection
                        ),
                        .init(
                            name: "fragment", source: authoredSource,
                            authoredSource: authoredSource,
                            msl: msl, reflection: reflection ?? fragmentReflection
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
            let direct: SceneGenericShaderProgramArtifact?
            let directFailure: String?
            switch build(
                directMSL,
                authoredSource: directAuthored,
                reflection: directReflection,
                vertexReflectionValue: directVertexReflection
            ) {
            case let .success(artifact):
                direct = artifact
                directFailure = nil
            case let .failure(failure):
                direct = nil
                directFailure = String(describing: failure)
            }
            let directMetal = direct?.program.metalSource ?? ""
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
            let nonAudioVectorReflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"g_ColorArray","type":"vec4","offset":16,"array":[16]}]}},"ubos":[{"type":"_1","block_size":272,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)
            let nonAudioVectorMetal = composedMSL
                .replacingOccurrences(
                    of: "float g_AudioSpectrum16Left[16]",
                    with: "float4 g_ColorArray[16]"
                )
                .replacingOccurrences(
                    of: "g_AudioSpectrum16Left[int(signal)].x",
                    with: "g_ColorArray[int(signal)].x"
                )
            let nonAudioVectorAuthored = authored
                .replacingOccurrences(
                    of: "uniform float g_AudioSpectrum16Left[16];",
                    with: "uniform vec4 g_ColorArray[16];"
                )
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
                mixedSlotRejected: mixedSlotRejected,
                directKind: direct?.program.colorTransfer.kind,
                directFailure: directFailure,
                directSampleCount: directMetal.components(
                    separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample"
                ).count - 1,
                directOutputPremultiplied: directMetal.contains(
                    "out.mwxFragColor = mwxGenericPremultiply(renamedCarrier);"
                ),
                directAlphaWriteRejected: failedColorTransfer(build(
                    directMSL.replacingOccurrences(
                        of: "    out.mwxFragColor = renamedCarrier;",
                        with: "    renamedCarrier.w *= 0.5;\n"
                            + "    out.mwxFragColor = renamedCarrier;"
                    ),
                    authoredSource: directAuthored,
                    reflection: directReflection,
                    vertexReflectionValue: directVertexReflection
                )),
                directHiddenSampleRejected: failedColorTransfer(build(
                    directMSL.replacingOccurrences(
                        of: "    float4 renamedCarrier = retained;",
                        with: "    float4 hiddenSample = g_Texture0.sample(sourceSampler, uv * 0.5);\n"
                            + "    float4 renamedCarrier = retained;"
                    ),
                    authoredSource: directAuthored,
                    reflection: directReflection,
                    vertexReflectionValue: directVertexReflection
                )),
                directWrongSlotRejected: failedColorTransfer(build(
                    directMSL.replacingOccurrences(
                        of: "float4 shiftedBlue = g_Texture0.sample",
                        with: "float4 shiftedBlue = g_Texture1.sample"
                    ),
                    authoredSource: directAuthored,
                    vertexReflectionValue: directVertexReflection
                )),
                nonAudioVectorArrayRejected: failedUniformMember(build(
                    nonAudioVectorMetal,
                    authoredSource: nonAudioVectorAuthored,
                    reflection: nonAudioVectorReflection
                ))
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        if CommandLine.arguments[1] == "--builder-straight-attenuation" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"mwxTexture0Transform0","type":"vec4","offset":16},{"name":"mwxTexture0Transform1","type":"vec4","offset":32}]},"_2":{"members":[]}},"ubos":[{"type":"_1","block_size":48,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            let fragmentMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
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
                    backendID: "glslang-spirv-cross-msl-v2",
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
                sampleUnpremultiplied: metal.contains(
                    "float4 albedo = mwxGenericUnpremultiply("
                        + "g_Texture0.sample(sourceSampler, uv));"
                ),
                alphaOnlyMutationPreserved: metal.contains(
                    "albedo.w *= mix(keyAlpha, 1.0, blend);"
                ) && !metal.contains(
                    "albedo *= mix(keyAlpha, 1.0, blend);"
                ),
                outputPremultiplied: metal.contains(
                    "out.mwxFragColor = mwxGenericPremultiply(albedo);"
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
        if CommandLine.arguments[1] == "--builder-straight-output" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"mwxTexture0Transform0","type":"vec4","offset":16},{"name":"mwxTexture0Transform1","type":"vec4","offset":32}]}},"ubos":[{"type":"_1","block_size":48,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            let fragmentMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
                "struct Output { float4 mwxFragColor [[color(0)]]; };",
                "fragment Output f() {",
                "    Output out;",
                "    float4 scene = g_Texture0.sample(sourceSampler, uv);",
                "    float3 finalColor = mix(float3(1.0), scene.xyz, scene.w);",
                "    float alpha = bar;",
                "    out.mwxFragColor = float4(finalColor, alpha);",
                "    return out;",
                "}",
            ].joined(separator: "\n")
            let authored = [
                "uniform sampler2D g_Texture0;",
                "uniform vec3 u_BarColor;",
                "uniform float u_BarOpacity;",
                "varying vec2 v_TexCoord;",
                "vec3 ApplyBlending(const int mode, in vec3 A, in vec3 B, in float opacity) {",
                "    return mix(A, (B), opacity);",
                "}",
                "void main() {",
                "    float bar = v_TexCoord.x;",
                "    vec3 finalColor = u_BarColor;",
                "    vec4 scene = texSample2D(g_Texture0, v_TexCoord);",
                "    finalColor = ApplyBlending(0, mix(finalColor.rgb, scene.rgb, scene.a), finalColor.rgb, bar * u_BarOpacity);",
                "    float alpha = bar * u_BarOpacity;",
                "    gl_FragColor = vec4(finalColor, alpha);",
                "}",
            ].joined(separator: "\n")
            func build(_ msl: String) -> Result<
                SceneGenericShaderProgramArtifact,
                SceneGenericShaderArtifactBuilder.Failure
            > {
                SceneGenericShaderArtifactBuilder.build(
                    requestKey: String(repeating: "e", count: 64),
                    backendID: "glslang-spirv-cross-msl-v2",
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
            let output = StraightOutputBuilderOutput(
                analyzedTransfer: colorTransferName(
                    SceneAuthoredShaderColorTransferAnalyzer.analyze(
                        fragmentSource: authored
                    )
                ),
                positiveKind: positive?.program.colorTransfer.kind,
                positiveSlot: positive?.program.colorTransfer.slot,
                sampleUnpremultiplied: metal.contains(
                    "mwxGenericUnpremultiply(g_Texture0.sample(sourceSampler, uv))"
                ),
                outputPremultiplied: metal.contains(
                    "out.mwxFragColor = mwxGenericPremultiply(float4(finalColor, alpha));"
                ),
                wrongSlotRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "float4 scene = g_Texture0.sample",
                        with: "float4 scene = g_Texture1.sample"
                    )
                )),
                duplicateOutputRejected: failedColorTransfer(build(
                    fragmentMSL.replacingOccurrences(
                        of: "    return out;",
                        with: "    out.mwxFragColor = float4(finalColor, alpha);\n    return out;"
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
        if CommandLine.arguments[1] == "--builder-conditional-straight" {
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16}]}},"ubos":[{"type":"_1","block_size":32,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let vertexMSL = "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            let fragmentMSL = [
                "#include <metal_stdlib>",
                "using namespace metal;",
                "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
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
                    backendID: "glslang-spirv-cross-msl-v2",
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
                ] == "1",
            hasOnlyGraphInputSampler:
                ProcessInfo.processInfo.environment[
                    "MWX_TEST_ONLY_GRAPH_INPUT_SAMPLER"
                ] == "1",
            outputSemantics:
                ProcessInfo.processInfo.environment[
                    "MWX_TEST_PRESERVED_RGBA_OUTPUT"
                ] == "1" ? .preservedRGBAUnorm : .color
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

private func failedUniformMember(
    _ result: Result<
        SceneGenericShaderProgramArtifact,
        SceneGenericShaderArtifactBuilder.Failure
    >
) -> Bool {
    if case .failure(.uniformMember) = result { return true }
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

PRESERVED_RGBA_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 state = texSample2D(g_Texture0, v_TexCoord);
    state.rg += state.ba * 0.25;
    gl_FragColor = state;
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

SINGLE_SAMPLER_ALPHA_MUTATION_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_EdgeAlpha;
varying vec2 v_TexCoord;
void main() {
    vec4 renamedCarrier = texSample2D(g_Texture0, v_TexCoord);
    renamedCarrier.a *= g_EdgeAlpha;
    gl_FragColor = renamedCarrier;
}
"""

SAME_SLOT_CHANNEL_RECONSTRUCTION_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 retained = texSample2D(g_Texture0, v_TexCoord);
    vec4 shiftedRed = texSample2D(g_Texture0, v_TexCoord + vec2(0.01, 0.0));
    vec4 shiftedBlue = texSample2D(g_Texture0, v_TexCoord - vec2(0.01, 0.0));
    vec4 renamedCarrier = retained;
    renamedCarrier.r = shiftedRed.r;
    renamedCarrier.b = shiftedBlue.b;
    gl_FragColor = renamedCarrier;
}
"""

SAME_SLOT_CHANNEL_RECONSTRUCTION_WRONG_SLOT_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
varying vec2 v_TexCoord;
void main() {
    vec4 retained = texSample2D(g_Texture0, v_TexCoord);
    vec4 shiftedRed = texSample2D(g_Texture1, v_TexCoord + vec2(0.01, 0.0));
    vec4 renamedCarrier = retained;
    renamedCarrier.r = shiftedRed.r;
    gl_FragColor = renamedCarrier;
}
"""

SAME_SLOT_CHANNEL_RECONSTRUCTION_ALPHA_WRITE_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 retained = texSample2D(g_Texture0, v_TexCoord);
    vec4 shiftedRed = texSample2D(g_Texture0, v_TexCoord + vec2(0.01, 0.0));
    vec4 renamedCarrier = retained;
    renamedCarrier.r = shiftedRed.r;
    renamedCarrier.a *= 0.5;
    gl_FragColor = renamedCarrier;
}
"""

SAME_SLOT_CHANNEL_RECONSTRUCTION_EXTRA_SAMPLE_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 retained = texSample2D(g_Texture0, v_TexCoord);
    vec4 shiftedRed = texSample2D(g_Texture0, v_TexCoord + vec2(0.01, 0.0));
    vec4 hiddenSample = texSample2D(g_Texture0, v_TexCoord * 0.5);
    vec4 renamedCarrier = retained;
    renamedCarrier.r = shiftedRed.r;
    gl_FragColor = renamedCarrier;
}
"""

SAME_SLOT_CHANNEL_RECONSTRUCTION_CONTROL_FLOW_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_Choice;
varying vec2 v_TexCoord;
void main() {
    vec4 retained = texSample2D(g_Texture0, v_TexCoord);
    vec4 shiftedRed = texSample2D(g_Texture0, v_TexCoord + vec2(0.01, 0.0));
    vec4 renamedCarrier = retained;
    if (g_Choice > 0.5) {
        renamedCarrier.r = shiftedRed.r;
    }
    gl_FragColor = renamedCarrier;
}
"""

SINGLE_SAMPLER_ALPHA_MUTATION_CONTROL_FLOW_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_EdgeAlpha;
varying vec2 v_TexCoord;
void main() {
    vec4 renamedCarrier = texSample2D(g_Texture0, v_TexCoord);
    if (g_EdgeAlpha > 0.5) {
        renamedCarrier.a *= g_EdgeAlpha;
    }
    gl_FragColor = renamedCarrier;
}
"""

AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_AudioSpectrum64Left[64];
uniform float g_AudioSpectrum64Right[64];
varying vec2 v_TexCoord;
void main() {
    v_TexCoord.y = 1.0 - v_TexCoord.y;
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    int bin = int(clamp(v_TexCoord.x * 63.0, 0.0, 63.0));
    float mask = clamp(
        g_AudioSpectrum64Left[bin] + g_AudioSpectrum64Right[bin],
        0.0,
        1.0
    );
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

NORMALIZED_SAMPLE_SUM_FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
vec4 unseenFilter(vec2 uv, vec2 delta) {
    return texSample2D(g_Texture0, uv - delta) * 0.25
        + texSample2D(g_Texture0, uv) * 0.5
        + texSample2D(g_Texture0, uv + delta) * 0.25;
}
void main() {
    gl_FragColor = unseenFilter(v_TexCoord, vec2(0.01));
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

STAGE_UNIFORM_NO_AUX_STRAIGHT_PRESERVING_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float g_Time;
varying vec2 v_TexCoord;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    color.rgb = color.rgb + vec3(g_Time * 0.0);
    gl_FragColor = color;
}
"""

FILM_GRAIN_STOCK_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1; // {"default":"util/noise"}
uniform sampler2D g_Texture2; // {"mode":"opacitymask","combo":"MASK"}
uniform float g_Time;
uniform float g_NoiseAlpha;
uniform float g_NoisePower;
varying vec2 v_TexCoord;
varying vec4 v_TexCoordNoise;
vec3 ApplyBlending(
    const int mode,
    in vec3 base,
    in vec3 blend,
    in float opacity
) {
    return mix(base, blend, opacity);
}
void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
    vec3 noise = texSample2D(g_Texture1, v_TexCoordNoise.xy).rgb;
    vec3 noise2 = texSample2D(g_Texture1, v_TexCoordNoise.zw).gbr;
    noise = saturate(noise * noise2);
    noise = pow(noise, CAST3(g_NoisePower));
    float blend = g_NoiseAlpha;
    albedo.rgb = ApplyBlending(14, albedo.rgb, noise, blend);
    gl_FragColor = albedo;
}
"""

AUXILIARY_RGB_MIX_RENAMED_FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture3; // {"default":"util/noise"}
uniform float g_Weight;
varying vec2 v_UV;
void main() {
    vec4 carrier = texSample2D(g_Texture0, v_UV);
    vec3 detail = texSample2D(g_Texture3, v_UV).rgb;
    carrier.rgb = mix(carrier.rgb, detail, g_Weight);
    gl_FragColor = carrier;
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
        has_only_graph_input_sampler: bool = False,
        alpha_attenuation_source_slot: int | None = None,
        color_blend_source_slot: int | None = None,
        preserved_rgba_output: bool = False,
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
        if has_only_graph_input_sampler:
            environment["MWX_TEST_ONLY_GRAPH_INPUT_SAMPLER"] = "1"
        else:
            environment.pop("MWX_TEST_ONLY_GRAPH_INPUT_SAMPLER", None)
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
        if preserved_rgba_output:
            environment["MWX_TEST_PRESERVED_RGBA_OUTPUT"] = "1"
        else:
            environment.pop("MWX_TEST_PRESERVED_RGBA_OUTPUT", None)
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
        self,
        key: str,
        *,
        color_transfer: str = "passthrough",
        output_semantics: str = "color",
        output_channel_use: str = "redDefined",
        auxiliary_channel_use: str | None = None,
    ) -> dict:
        slots = [0] if auxiliary_channel_use is None else [0, 1]
        transforms = " ".join(
            f"float4 mwxTexture{slot}Transform{component};"
            for slot in slots for component in range(2)
        )
        metal = f"""
#include <metal_stdlib>
using namespace metal;
struct Uniforms {{ float2 mwxRenderSize; {transforms} }};
vertex float4 mwxGenericVertex(uint vertexID [[vertex_id]], constant Uniforms& u [[buffer(8)]]) {{ return float4(0.0); }}
fragment float4 mwxGenericFragment(texture2d<float> g_Texture0 [[texture(0)]], constant Uniforms& u [[buffer(8)]]) {{ return g_Texture0.sample(sampler(), u.mwxTexture0Transform0.xy + u.mwxTexture0Transform0.zw * 0.5 + u.mwxTexture0Transform1.xy * 0.5); }}
""".strip() + "\n"
        return {
            "schemaVersion": 4,
            "kind": "scene-generic-shader-program-artifact",
            "backendID": "glslang-spirv-cross-msl-v2",
            "requestKey": key,
            "outputSemantics": output_semantics,
            "program": {
                "metalSource": metal,
                "metalSourceSHA256": hashlib.sha256(metal.encode()).hexdigest(),
                "vertexFunctionName": "mwxGenericVertex",
                "fragmentFunctionName": "mwxGenericFragment",
                "uniformBufferIndex": 8,
                "uniformLayout": {
                    "fields": [{
                        "name": "mwxRenderSize", "authoredName": "mwxRenderSize",
                        "type": "float2", "offset": 0,
                    }] + [{
                        "name": f"mwxTexture{slot}Transform{component}",
                        "authoredName": f"mwxTexture{slot}Transform{component}",
                        "type": "float4", "offset": 16 + slot * 32 + component * 16,
                    } for slot in slots for component in range(2)],
                    "byteSize": 16 + len(slots) * 32,
                },
                "textureBindings": [
                    {"name": f"g_Texture{slot}", "slot": slot, "channelUse": (
                        "unproven" if slot == 0 else auxiliary_channel_use
                    )} for slot in slots
                ],
                "staticLoopWork": 0,
                "fragmentOutputChannelUse": output_channel_use,
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
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
                {"name": "mwxTexture0Transform0", "type": "vec4", "offset": 16},
                {"name": "mwxTexture0Transform1", "type": "vec4", "offset": 32},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 48, "set": 0, "binding": 8
            }],
            "textures": [{"name": "g_Texture0", "binding": 0}],
        }
        stages = [
            {"stage": "vertex", "reflection": reflection},
            {"stage": "fragment", "reflection": reflection},
        ]
        vertex_msl = """#include <metal_stdlib>
using namespace metal;
struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };
vertex float4 mwxGenericVertex(uint vertexID [[vertex_id]]) {
    return float4(0.0);
}
"""
        fragment_msl = """#include <metal_stdlib>
using namespace metal;
struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment(texture2d<float> g_Texture0 [[texture(0)]], constant MWXUniforms& uniforms [[buffer(8)]]) {
    Output out;
    float2 uv = uniforms.mwxTexture0Transform0.xy + uniforms.mwxTexture0Transform0.zw * 0.5 + uniforms.mwxTexture0Transform1.xy * 0.5;
    out.mwxFragColor = g_Texture0.sample(sampler(), uv);
    return out;
}
"""
        return build_program_artifact(
            request_key=key,
            backend_id="glslang-spirv-cross-msl-v2",
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
            "color",
            vertex_source,
            fragment_source,
            "{}",
        ):
            encoded = value.encode("utf-8")
            digest.update(len(encoded).to_bytes(8, "big"))
            digest.update(encoded)
        return digest.hexdigest()

    def test_transform_abi_request_and_default_cache_namespaces_are_isolated(self):
        source = CACHE_SOURCE.read_text(encoding="utf-8")
        self.assertIn('"mwx-generic-shader-request-v5"', source)
        self.assertIn('"SceneGenericShaderPrograms-v5"', source)
        self.assertNotIn('"mwx-generic-shader-request-v4"', source)
        self.assertNotIn('"SceneGenericShaderPrograms-v4"', source)

        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            observed, _, cache, _ = self.run_harness(root, route="observe-only")
            current_key = self.request_key(
                "mwx-generic-shader-request-v5", VERTEX, FRAGMENT
            )
            legacy_key = self.request_key(
                "mwx-generic-shader-request-v4", VERTEX, FRAGMENT
            )
            self.assertEqual(observed["requestKey"], current_key)
            self.assertNotEqual(current_key, legacy_key)

            stale = self.artifact(legacy_key)
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

    def test_swift_normalizer_localizes_only_main_scoped_mutable_varying(self):
        completed = subprocess.run(
            [str(self.binary), "--normalizer-mutable-fragment-varying"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "mainMutationLowered": True,
            "interfacePreserved": True,
            "helperMutationRejected": True,
            "arrayMutationRejected": True,
            "readOnlyPreserved": True,
        })

    def test_backend_canonicalizer_unrolls_only_proven_varying_prefix(self):
        completed = subprocess.run(
            [str(self.binary), "--backend-canonicalizer"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "arraysCompacted": True,
            "loopsUnrolled": True,
            "boundedFrontendAccepted": True,
            "genericNormalizerAccepted": True,
            "assignmentNarrowed": True,
            "smallArrayLoopUnrolled": True,
            "smallArrayBoundedFrontendAccepted": True,
            "smallArrayGenericNormalizerAccepted": True,
            "smallArrayDynamicBoundPreserved": True,
            "smallArrayOutOfBoundsPreserved": True,
            "dynamicBoundPreserved": True,
            "controlFlowPreserved": True,
            "outOfPrefixPreserved": True,
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
        self.assertEqual(output["directKind"], "straight-alpha-preserving")
        self.assertEqual(output["directSampleCount"], 3)
        self.assertTrue(output["directOutputPremultiplied"])
        self.assertTrue(output["directAlphaWriteRejected"])
        self.assertTrue(output["directHiddenSampleRejected"])
        self.assertTrue(output["directWrongSlotRejected"])

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
        self.assertNotIn(
            "g_AudioSpectrum16Left[int(signal)].x",
            output.get("composedMetal", ""),
        )
        self.assertTrue(output["nonAudioVectorArrayRejected"])

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

    def test_product_builder_proves_exact_red_green_projection(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-preserved-channel-use"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "directRedGreen": "redGreenOnly",
            "mixedProjection": "unproven",
        })

    def test_product_builder_proves_normalized_same_slot_sample_sum(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-normalized-sample-sum"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "analyzedTransfer": "passthrough",
            "positiveKind": "passthrough",
            "positiveSlot": 0,
            "renamedHelperAccepted": True,
            "immutableAliasAccepted": True,
            "mutatedAliasRejected": True,
            "reusedAliasRejected": True,
            "conditionalAliasRejected": True,
            "nonNormalizedRejected": True,
            "negativeWeightRejected": True,
            "zeroWeightRejected": True,
            "mixedSlotRejected": True,
            "hiddenSampleRejected": True,
            "branchingHelperRejected": True,
        })

    def test_product_builder_preserves_alpha_weighted_sample_average(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-alpha-weighted-sample-average"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "analyzedTransfer": "straightAlpha",
            "sourceSlot": 0,
            "sampleCount": 4,
            "renamedLocalsAccepted": True,
            "threeSampleCombinationAccepted": True,
            "boundedFrontendAccepted": True,
            "boundedSampleUnpremultipliedCount": 4,
            "boundedOutputPremultiplied": True,
            "positiveKind": "straight-alpha",
            "positiveSlot": 0,
            "genericSampleUnpremultipliedCount": 4,
            "genericOutputPremultiplied": True,
            "denominatorMismatchRejected": True,
            "hiddenSampleRejected": True,
            "wrongWeightRejected": True,
            "wrongNormalizationRejected": True,
            "earlyNormalizationRejected": True,
            "compilerDriftRejected": True,
            "helperConflictRejected": True,
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
            "sampleUnpremultiplied": True,
            "alphaOnlyMutationPreserved": True,
            "outputPremultiplied": True,
            "unrelatedAlphaReadRejected": True,
            "wholeVectorUseRejected": True,
            "rgbWriteRejected": True,
        })

    def test_product_builder_conserves_source_proven_independent_straight_output(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-straight-output"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "analyzedTransfer": "straightAlpha",
            "positiveKind": "straight-alpha",
            "positiveSlot": 0,
            "sampleUnpremultiplied": True,
            "outputPremultiplied": True,
            "wrongSlotRejected": True,
            "duplicateOutputRejected": True,
            "helperConflictRejected": True,
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
            self.assertEqual(accepted["uniformNames"], [
                "mwxRenderSize",
                "mwxTexture0Transform0",
                "mwxTexture0Transform1",
            ])
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

    def test_preserved_rgba_output_has_distinct_raw_data_artifact_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-rgba-data-") as directory:
            root = Path(directory)
            color, _, _, _ = self.run_harness(
                root,
                route="observe-only",
                fragment=PRESERVED_RGBA_FRAGMENT,
            )
            data, requests, cache, _ = self.run_harness(
                root,
                route="observe-only",
                fragment=PRESERVED_RGBA_FRAGMENT,
                preserved_rgba_output=True,
            )
            self.assertNotEqual(color["requestKey"], data["requestKey"])
            request = json.loads(
                (requests / f"{data['requestKey']}.json").read_text(encoding="utf-8")
            )
            self.assertEqual(request["schemaVersion"], 2)
            self.assertEqual(request["outputSemantics"], "preserved-rgba-unorm")

            artifact = self.artifact(
                data["requestKey"],
                color_transfer="preserved-rgba-data",
                output_semantics="preserved-rgba-unorm",
            )
            (cache / f"{data['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(
                root,
                route="prefer-generic",
                fragment=PRESERVED_RGBA_FRAGMENT,
                preserved_rgba_output=True,
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "unresolved")
            self.assertEqual(accepted["fragmentOutputChannelUse"], "redDefined")

            artifact["program"]["fragmentOutputChannelUse"] = "unproven"
            (cache / f"{data['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            rejected, _, _, _ = self.run_harness(
                root,
                route="prefer-generic",
                fragment=PRESERVED_RGBA_FRAGMENT,
                preserved_rgba_output=True,
            )
            self.assertEqual(rejected["code"], "artifact-contract-rejected")

    def test_preserved_rgba_builder_requires_definite_whole_output(self):
        completed = subprocess.run(
            [str(self.binary), "--builder-preserved-rgba-data"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        observed = json.loads(completed.stdout)
        self.assertEqual(observed, {
            "outputSemantics": "preserved-rgba-unorm",
            "colorTransfer": "preserved-rgba-data",
            "wholeOutputAccepted": True,
            "helperOutputRejected": True,
        })

    def test_normalized_sample_sum_profile_is_generic_only_and_reversible(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-sum-route-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root,
                route=None,
                fragment=NORMALIZED_SAMPLE_SUM_FRAGMENT,
            )
            self.assertEqual(
                first["routeProfile"],
                "source-proven-normalized-sample-sum",
            )
            self.assertEqual(first["routeState"], "generic-only")
            self.assertFalse(first["permitsBoundedFrontend"])

            artifact = self.python_artifact(
                first["requestKey"],
                fragment_source=NORMALIZED_SAMPLE_SUM_FRAGMENT,
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, accepted_log = self.run_harness(
                root,
                route=None,
                fragment=NORMALIZED_SAMPLE_SUM_FRAGMENT,
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["routeState"], "generic-only")
            self.assertIn(
                "state=generic-only "
                "profile=source-proven-normalized-sample-sum outcome=accepted",
                accepted_log,
            )

            disabled, _, _, disabled_log = self.run_harness(
                root,
                route=None,
                profile_routes=(
                    "source-proven-normalized-sample-sum=disable-generic"
                ),
                fragment=NORMALIZED_SAMPLE_SUM_FRAGMENT,
            )
            self.assertEqual(disabled["status"], "unavailable")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertTrue(disabled["permitsBoundedFrontend"])
            self.assertIn(
                "state=disable-generic "
                "profile=source-proven-normalized-sample-sum outcome=fallback",
                disabled_log,
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

    def test_audio_stage_uniform_mutable_straight_alpha_has_narrow_product_authority(
        self,
    ):
        profile = (
            "source-proven-graph-input-audio-stage-uniform-straight-alpha-"
            "no-auxiliary"
        )
        facts = {
            "graph_input_slots": (0,),
            "has_only_graph_input_sampler": True,
        }
        with tempfile.TemporaryDirectory(
            prefix="mwx-generic-artifact-test-"
        ) as directory:
            root = Path(directory)
            rejected, _, cache, rejected_log = self.run_harness(
                root,
                route=None,
                fragment=AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT,
                **facts,
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
            (cache / f"{rejected['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, accepted_log = self.run_harness(
                root,
                route=None,
                fragment=AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT,
                **facts,
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
                fragment=AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT,
                **facts,
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertEqual(rolled_back["fallbackOwner"], "bounded-frontend")
            self.assertIn(
                f"state=disable-generic profile={profile} "
                "outcome=fallback reason=route-disabled",
                rollback_log,
            )

    def test_audio_stage_uniform_mutable_straight_alpha_profile_is_structurally_narrow(
        self,
    ):
        profile = (
            "source-proven-graph-input-audio-stage-uniform-straight-alpha-"
            "no-auxiliary"
        )
        without_right = AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT.replace(
            "uniform float g_AudioSpectrum64Right[64];\n", ""
        ).replace(" + g_AudioSpectrum64Right[bin]", "")
        without_mutation = AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT.replace(
            "    v_TexCoord.y = 1.0 - v_TexCoord.y;\n", ""
        )
        cases = [
            (without_right, {"graph_input_slots": (0,), "has_only_graph_input_sampler": True}),
            (without_mutation, {"graph_input_slots": (0,), "has_only_graph_input_sampler": True}),
            (
                AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT,
                {"graph_input_slots": (0,)},
            ),
            (
                AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                    "has_external_provider": True,
                },
            ),
            (
                AUDIO_STAGE_UNIFORM_MUTABLE_STRAIGHT_ALPHA_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "graph_slots": (1,),
                    "has_only_graph_input_sampler": True,
                },
            ),
        ]
        for fragment, facts in cases:
            with self.subTest(facts=facts), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                result, _, _, log = self.run_harness(
                    Path(directory), route=None, fragment=fragment, **facts
                )
                self.assertNotEqual(result["routeProfile"], profile)
                self.assertTrue(result["permitsBoundedFrontend"])
                self.assertIn("state=prefer-generic", log)

    def test_interpolated_color_artifact_requires_sorted_bound_slots(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(
                root, route="observe-only", fragment=INTERPOLATED_FRAGMENT
            )
            artifact = self.artifact(
                first["requestKey"],
                color_transfer="interpolated-color",
                auxiliary_channel_use="unproven",
            )
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
                SINGLE_SAMPLER_ALPHA_MUTATION_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-single-sampler-alpha-mutation",
            ),
            (
                SAME_SLOT_CHANNEL_RECONSTRUCTION_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-same-slot-channel-reconstruction",
            ),
            (
                FILM_GRAIN_STOCK_FRAGMENT,
                {"graph_input_slots": (0,)},
                "source-proven-graph-input-auxiliary-rgb-blend-alpha-preserving",
            ),
            (
                AUXILIARY_RGB_MIX_RENAMED_FRAGMENT,
                {"graph_input_slots": (0,)},
                "source-proven-graph-input-auxiliary-rgb-blend-alpha-preserving",
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
                STAGE_UNIFORM_NO_AUX_STRAIGHT_PRESERVING_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-stage-uniform-straight-alpha-preserving-no-auxiliary",
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

    def test_narrow_alpha_and_channel_profiles_reject_unproven_shapes(self):
        cases = [
            (
                SINGLE_SAMPLER_ALPHA_MUTATION_FRAGMENT,
                {"graph_input_slots": (0,)},
                "source-proven-graph-input-single-sampler-alpha-mutation",
            ),
            (
                SINGLE_SAMPLER_ALPHA_MUTATION_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                    "has_external_provider": True,
                },
                "source-proven-graph-input-single-sampler-alpha-mutation",
            ),
            (
                SINGLE_SAMPLER_ALPHA_MUTATION_FRAGMENT,
                {
                    "graph_input_slots": (1,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-single-sampler-alpha-mutation",
            ),
            (
                SINGLE_SAMPLER_ALPHA_MUTATION_CONTROL_FLOW_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-single-sampler-alpha-mutation",
            ),
            (
                SAME_SLOT_CHANNEL_RECONSTRUCTION_WRONG_SLOT_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-same-slot-channel-reconstruction",
            ),
            (
                SAME_SLOT_CHANNEL_RECONSTRUCTION_ALPHA_WRITE_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-same-slot-channel-reconstruction",
            ),
            (
                SAME_SLOT_CHANNEL_RECONSTRUCTION_EXTRA_SAMPLE_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-same-slot-channel-reconstruction",
            ),
            (
                SAME_SLOT_CHANNEL_RECONSTRUCTION_CONTROL_FLOW_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "source-proven-graph-input-same-slot-channel-reconstruction",
            ),
        ]
        for fragment, facts, rejected_profile in cases:
            with self.subTest(fragment=fragment[:80]), tempfile.TemporaryDirectory(
                prefix="mwx-generic-artifact-test-"
            ) as directory:
                result, _, _, log = self.run_harness(
                    Path(directory),
                    route="prefer-generic",
                    fragment=fragment,
                    **facts,
                )
                self.assertTrue(result["permitsBoundedFrontend"])
                self.assertNotIn(f"profile={rejected_profile}", log)

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
                SINGLE_SAMPLER_ALPHA_MUTATION_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "straight-alpha",
                "source-proven-graph-input-single-sampler-alpha-mutation",
                False,
            ),
            (
                SAME_SLOT_CHANNEL_RECONSTRUCTION_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "straight-alpha-preserving",
                "source-proven-graph-input-same-slot-channel-reconstruction",
                False,
            ),
            (
                FILM_GRAIN_STOCK_FRAGMENT,
                {"graph_input_slots": (0,)},
                "straight-alpha-preserving",
                "source-proven-graph-input-auxiliary-rgb-blend-alpha-preserving",
                True,
            ),
            (
                AUXILIARY_RGB_MIX_RENAMED_FRAGMENT,
                {"graph_input_slots": (0,)},
                "straight-alpha-preserving",
                "source-proven-graph-input-auxiliary-rgb-blend-alpha-preserving",
                True,
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
                STAGE_UNIFORM_NO_AUX_STRAIGHT_PRESERVING_FRAGMENT,
                {
                    "graph_input_slots": (0,),
                    "has_only_graph_input_sampler": True,
                },
                "straight-alpha-preserving",
                "source-proven-graph-input-stage-uniform-straight-alpha-preserving-no-auxiliary",
                False,
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
                    observed["requestKey"],
                    color_transfer=transfer,
                    auxiliary_channel_use="redOnly" if needs_aux else None,
                )
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

    def test_auxiliary_rgb_mix_shape_uses_narrow_generic_only_route(
        self,
    ):
        facts = {"graph_input_slots": (0,)}
        profile = (
            "source-proven-graph-input-auxiliary-rgb-blend-alpha-preserving"
        )
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
                f"state=generic-only profile={profile} outcome=accepted",
                accepted_log,
            )

            artifact["program"]["metalSourceSHA256"] = "0" * 64
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            rejected, _, _, rejected_log = self.run_harness(
                root,
                route=None,
                fragment=FILM_GRAIN_STOCK_FRAGMENT,
                **facts,
            )
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertIn(
                f"state=generic-only profile={profile} outcome=rejected "
                "reason=artifact-contract-rejected",
                rejected_log,
            )

            rolled_back, _, _, rollback_log = self.run_harness(
                root,
                route=None,
                profile_routes=f"{profile}=disable-generic",
                fragment=FILM_GRAIN_STOCK_FRAGMENT,
                **facts,
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertIn(
                f"state=disable-generic profile={profile} outcome=fallback "
                "reason=route-disabled",
                rollback_log,
            )

    def test_auxiliary_rgb_mix_profile_rejects_broader_alpha_preserving_shapes(
        self,
    ):
        profile = (
            "source-proven-graph-input-auxiliary-rgb-blend-alpha-preserving"
        )
        cases = [
            FILM_GRAIN_STOCK_FRAGMENT.replace(
                "g_Texture1", "g_Texture0"
            ),
            FILM_GRAIN_STOCK_FRAGMENT.replace(
                "albedo.rgb = ApplyBlending",
                "albedo.a *= 0.5;\n    albedo.rgb = ApplyBlending",
            ),
            FILM_GRAIN_STOCK_FRAGMENT.replace(
                "float blend = g_NoiseAlpha;", "float blend = noise.r;"
            ),
            FILM_GRAIN_STOCK_FRAGMENT.replace(
                "gl_FragColor = albedo;",
                "vec4 hidden = texSample2D(g_Texture1, v_TexCoord);\n"
                "    gl_FragColor = albedo;",
            ),
            AUXILIARY_RGB_MIX_RENAMED_FRAGMENT.replace(
                "void main() {",
                "vec4 hiddenSample() {\n"
                "    return texSample2D(g_Texture3, v_UV);\n"
                "}\n"
                "void main() {",
            ),
        ]
        for fragment in cases:
            with self.subTest(fragment=fragment[-160:]), tempfile.TemporaryDirectory(
                prefix="mwx-auxiliary-rgb-mix-route-test-"
            ) as directory:
                result, _, _, log = self.run_harness(
                    Path(directory),
                    route=None,
                    fragment=fragment,
                    graph_input_slots=(0,),
                )
                self.assertTrue(result["permitsBoundedFrontend"])
                self.assertNotIn(f"profile={profile}", log)


if __name__ == "__main__":
    unittest.main()
