#!/usr/bin/env python3

import json
from pathlib import Path
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
]

FINALIZER_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialProgramFinalizer.swift"
)


HARNESS = r'''
import Foundation

private struct AlphaOutput: Codable {
    let memberwiseAccepted: Bool
    let repeatedLocalsAccepted: Bool
    let renamedThreeSampleAccepted: Bool
    let crossBlockRejected: Bool
    let mutationRejected: Bool
    let nonuniformDeclarationRejected: Bool
    let artifactKind: String?
    let sampleBoundaryCount: Int
    let outputBoundaryPresent: Bool
    let missingComponentRejected: Bool
    let wrongCarrierRejected: Bool
    let wrongSlotRejected: Bool
    let postTailRejected: Bool
    let extraSampleRejected: Bool
    let carrierEscapeRejected: Bool
    let normalizedInlineAccepted: Bool
    let normalizedOverlapPrefersPassthrough: Bool
    let normalizedWrongTotalRejected: Bool
    let normalizedNegativeWeightRejected: Bool
    let normalizedWrongSlotRejected: Bool
    let normalizedExtraReadRejected: Bool
    let normalizedMutationRejected: Bool
    let normalizedBranchRejected: Bool
    let normalizedExtraSampleRejected: Bool
    let independentTransferPreserved: Bool
    let routeProfile: String
    let routeState: String
    let disableState: String?
    let rollbackOwner: String
}

private struct CompositeOutput: Codable {
    let transfer: String
    let blurredSlot: Int?
    let previousSlot: Int?
    let unitColorUniform: String?
    let artifactKind: String?
    let boundedFrontendAccepted: Bool
    let coordinateAliasAccepted: Bool
    let coordinateIdentityHelperAccepted: Bool
    let renamedSlotHelperAccepted: Bool
    let coordinateHelperMutationRejected: Bool
    let coordinateHelperEscapeRejected: Bool
    let coordinateHelperWrongSampleRejected: Bool
    let duplicateCompositeReturnAccepted: Bool
    let duplicateReturnWrongCarrierRejected: Bool
    let duplicateReturnIntermediateMutationRejected: Bool
    let thirdCompositeReturnRejected: Bool
    let coordinateMutationRejected: Bool
    let coordinatePreviousReuseRejected: Bool
    let coordinateUniformProvenanceRejected: Bool
    let coordinateInlineMutationRejected: Bool
    let nonunitMaskRejected: Bool
    let postTailRejected: Bool
    let auxiliarySampleRejected: Bool
    let routeProfile: String
    let routeState: String
    let disableState: String?
    let rollbackOwner: String
}

private func transferName(_ transfer: SceneShaderColorTransfer) -> String {
    switch transfer {
    case .straightAlpha: return "straightAlpha"
    case .premultipliedAlpha: return "premultipliedAlpha"
    default: return "other"
    }
}

private func profile(
    transfer: SceneShaderColorTransfer,
    alphaSlot: Int? = nil,
    compositeSlots: (Int, Int)? = nil
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        colorTransfer: transfer,
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        conditionalStraightUnionSourceSlot: nil,
        singleSamplerAlphaMutationSourceSlot: nil,
        sameSlotChannelReconstructionSourceSlot: nil,
        auxiliaryRGBMixSourceSlot: nil,
        normalizedSampleSumSourceSlot: nil,
        alphaWeightedSampleAverageSourceSlot: alphaSlot,
        unitCompositeBlurredSlot: compositeSlots?.0,
        unitCompositePreviousSlot: compositeSlots?.1,
        hasExternalProviderTexture: false,
        producesScalarRedOutput: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: compositeSlots.map { Set([$0.0]) } ?? [],
        graphInputTextureSlots: compositeSlots.map { Set([$0.0, $0.1]) }
            ?? alphaSlot.map { Set([$0]) } ?? [],
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyGraphInputSampler: alphaSlot != nil,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false,
        hasLocalizedMutableFragmentVarying: false
    )
}

private func artifact(
    authored: String,
    msl: String,
    reflection: Data,
    uniformStruct: String
) -> SceneGenericShaderProgramArtifact? {
    let built = SceneGenericShaderArtifactBuilder.build(
        requestKey: String(repeating: "c", count: 64),
        backendID: "glslang-spirv-cross-msl-v2",
        stages: [
            .init(
                name: "vertex", source: "void main() {}",
                authoredSource: "void main() {}",
                msl: uniformStruct, reflection: reflection
            ),
            .init(
                name: "fragment", source: authored,
                authoredSource: authored, msl: msl, reflection: reflection
            ),
        ],
        maximumArtifactBytes: 1_024_000
    )
    guard case let .success(value) = built else { return nil }
    return value
}

private func alphaSource(
    count: Int = 4,
    accumulator: String = "result",
    sample: String = "sample",
    weight: String = "weight",
    repeatedLocals: Bool = false
) -> String {
    let samples = (0..<count).map { index in
        let declaration = repeatedLocals ? "vec4 " : ""
        return [
            "    {",
            "        \(declaration)\(sample) = texSample2D(g_Texture0, vec2(\(index).0));",
            "        \(accumulator) += \(sample) * \(sample).a;",
            "        \(weight) += \(sample).a;",
            "    }",
        ].joined(separator: "\n")
    }.joined(separator: "\n")
    let declaration = repeatedLocals
        ? "    vec4 \(accumulator) = CAST4(0.0);"
        : "    vec4 \(accumulator) = CAST4(0.0), \(sample);"
    return [
        "uniform sampler2D g_Texture0;",
        "void main() {",
        "    float \(weight) = 0.0;",
        declaration,
        samples,
        "    gl_FragColor.rgb = \(accumulator).rgb / max(0.001, \(weight));",
        "    gl_FragColor.a = \(accumulator).a / \(count).0;",
        "}",
    ].joined(separator: "\n")
}

private func immutableAlphaMSL(count: Int = 4) -> String {
    let samples = (0..<count).map { index in
        let name = index == 0 ? "mwx_sample" : "mwx_sample_\(index)"
        return [
            "    float4 \(name) = g_Texture0.sample(s, float2(\(index).0));",
            "    result += (\(name) * \(name).w);",
            "    weight += \(name).w;",
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
        "    float3 normalized = result.xyz / float3(fast::max(0.001000000047497451305389404296875, weight));",
        "    out.mwxFragColor.x = normalized.x;",
        "    out.mwxFragColor.y = normalized.y;",
        "    out.mwxFragColor.z = normalized.z;",
        "    out.mwxFragColor.w = result.w / \(count).0;",
        "    return out;",
        "}",
    ].joined(separator: "\n")
}

private let normalizedWeights = [
    "0.006299", "0.017298", "0.039533", "0.075189", "0.119007",
    "0.156756", "0.171834", "0.156756", "0.119007", "0.075189",
    "0.039533", "0.017298", "0.006299",
]
private let normalizedInline = [
    "uniform sampler2D g_Texture0;", "uniform sampler2D g_Texture1;",
    "varying vec2 v_TexCoord[13];", "void main() {",
    "    vec4 albedo = " + normalizedWeights.enumerated().map {
        "texSample2D(g_Texture0, v_TexCoord[\($0.offset)]) * \($0.element)"
    }.joined(separator: "\n        + ") + ";",
    "    gl_FragColor = albedo;", "}",
].joined(separator: "\n")

private let independentSignal = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform vec2 m_Position;
uniform float m_Size;
varying vec2 v_TexCoord;
vec4 injectSignal(vec4 current, float amount) {
    return min(current + vec4(amount), vec4(1.0));
}
vec4 shapeSignal(vec4 current, vec2 position, float size) {
    float amount = smoothstep(size, 0.0, length(position - v_TexCoord));
    return injectSignal(current, amount);
}
void main() {
    vec2 drift = texSample2D(g_Texture0, v_TexCoord).xy;
    vec4 signal = texSample2D(g_Texture1, v_TexCoord);
    signal *= step(0.0, drift.x);
    gl_FragColor = signal / (1.0 + length(drift));
    gl_FragColor = shapeSignal(gl_FragColor, m_Position, m_Size);
}
"""

private func independentTransfer(_ source: String) -> SceneShaderColorTransfer? {
    let analyzed = SceneAuthoredShaderSyntaxAnalyzer.analyze(
        lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: .fragment),
        stage: .fragment
    )
    guard analyzed.diagnostics.isEmpty, let fragment = analyzed.unit,
          let main = fragment.functions.first(where: { $0.name == "main" })
    else { return nil }
    let uses = fragment.tokens.indices.filter {
        fragment.tokens[$0].text == "gl_FragColor"
    }
    return SceneAuthoredShaderIndependentAlphaAnalyzer.analyze(
        outputUses: uses, fragment: fragment, main: main
    )
}

private func normalizedSlot(_ source: String) -> Int? {
    SceneAuthoredShaderNormalizedSampleSumAnalyzer.sourceSlot(
        fragmentSource: source
    )
}

private func compositeSource(
    mask: String = "1.0",
    tail: String = "",
    auxiliary: String = "",
    coordinateAlias: Bool = false,
    coordinateHelper: Bool = false,
    blurredSlot: Int = 0,
    previousSlot: Int = 2,
    coordinateName: String = "blurredCoords",
    coordinateHelperName: String = "coordinateIdentity",
    directCompositeReturnCount: Int = 0
) -> String {
    let hasAlias = coordinateAlias || coordinateHelper
    let blurredCoordinate = coordinateHelper
        ? "\(coordinateHelperName)(\(coordinateName), g_TextureResolution.xy)"
        : (hasAlias ? coordinateName : "v_TexCoord")
    return [
        "uniform sampler2D g_Texture\(blurredSlot);",
        "uniform sampler2D g_Texture\(previousSlot);",
        "uniform vec3 g_CompositeColor;",
        coordinateHelper ? "uniform vec4 g_TextureResolution;" : "",
        coordinateHelper ? "varying vec4 v_TexCoord;" : "varying vec2 v_TexCoord;",
        coordinateHelper
            ? "vec2 \(coordinateHelperName)(vec2 source, vec2 ignored) {"
            : "",
        coordinateHelper ? "    return source;" : "",
        coordinateHelper ? "}" : "",
        "vec4 identityComposite(vec4 oldColor, vec4 effectColor) {",
        "    return effectColor;",
        "}",
        "vec4 compositeCarrier(vec4 oldColor, vec4 effectColor) {",
        "    effectColor.rgb *= g_CompositeColor;",
        directCompositeReturnCount == 0
            ? "    return identityComposite(oldColor, effectColor);"
            : Array(
                repeating: "    return effectColor;",
                count: directCompositeReturnCount
            ).joined(separator: "\n"),
        "}",
        "void main() {",
        hasAlias ? "    vec2 \(coordinateName) = v_TexCoord.xy;" : "",
        "    vec4 blurred = texSample2D(g_Texture\(blurredSlot), \(blurredCoordinate));",
        "    vec4 previous = texSample2D(g_Texture\(previousSlot), v_TexCoord.xy);",
        "    float mask = \(mask);",
        "    float divisor = mix(blurred.a, 1, step(blurred.a, 0));",
        "    blurred = compositeCarrier(previous, vec4(blurred.rgb / divisor, blurred.a));",
        "    blurred = mix(previous, blurred, mask);",
        auxiliary,
        "    gl_FragColor = blurred;",
        tail,
        "}",
    ].filter { !$0.isEmpty }.joined(separator: "\n")
}

@main
private struct Harness {
    static func main() throws {
        if CommandLine.arguments[1] == "alpha" {
            let memberwise = alphaSource()
            let repeated = alphaSource(repeatedLocals: true)
            let canonical = immutableAlphaMSL()
            let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16}]}},"ubos":[{"type":"_1","block_size":32,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
            let built = artifact(
                authored: repeated,
                msl: canonical,
                reflection: reflection,
                uniformStruct: "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };"
            )
            let lowered = SceneGenericShaderStraightAlphaPreservingLowering
                .lowerAlphaWeightedSampleAverage(
                    canonical, expectedSlot: 0, sampleCount: 4
                ) ?? ""
            let crossBlock = repeated.replacingOccurrences(
                of: "        weight += sample.a;\n    }",
                with: "    }\n    weight += sample.a;",
                options: [], range: repeated.range(of: "        weight += sample.a;\n    }")
            )
            let mutation = repeated.replacingOccurrences(
                of: "        result += sample * sample.a;",
                with: "        sample.a = 0.5;\n        result += sample * sample.a;",
                options: [], range: repeated.range(of: "        result += sample * sample.a;")
            )
            let nonuniform = repeated.replacingOccurrences(
                of: "        vec4 sample =", with: "        sample =",
                options: [], range: repeated.range(of: "        vec4 sample =")
            )
            let capability = profile(transfer: .straightAlpha(textureSlot: 0), alphaSlot: 0)
            let aggregate = SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: normalizedInline
            )
            let overlapping = independentTransfer(normalizedInline)
            let output = AlphaOutput(
                memberwiseAccepted:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: memberwise
                    ) == .init(textureSlot: 0, sampleCount: 4),
                repeatedLocalsAccepted:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: repeated
                    ) == .init(textureSlot: 0, sampleCount: 4),
                renamedThreeSampleAccepted:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: alphaSource(
                            count: 3, accumulator: "unseenColor",
                            sample: "unseenTap", weight: "unseenWeight"
                        )
                    ) == .init(textureSlot: 0, sampleCount: 3),
                crossBlockRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: crossBlock
                    ) == nil,
                mutationRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: mutation
                    ) == nil,
                nonuniformDeclarationRejected:
                    SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
                        fragmentSource: nonuniform
                    ) == nil,
                artifactKind: built?.program.colorTransfer.kind,
                sampleBoundaryCount: lowered.components(
                    separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
                ).count - 1,
                outputBoundaryPresent: lowered.contains(
                    "out.mwxFragColor = mwxGenericPremultiply(float4(result.xyz, result.w / 4.0));"
                ),
                missingComponentRejected:
                    SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.analyze(
                        canonical.replacingOccurrences(
                            of: "    out.mwxFragColor.y = normalized.y;\n", with: ""
                        ), expectedSlot: 0, sampleCount: 4
                    ) == nil,
                wrongCarrierRejected:
                    SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.analyze(
                        canonical.replacingOccurrences(
                            of: "result += (mwx_sample_1 * mwx_sample_1.w);",
                            with: "result += (mwx_sample_1 * mwx_sample_2.w);"
                        ), expectedSlot: 0, sampleCount: 4
                    ) == nil,
                wrongSlotRejected:
                    SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.analyze(
                        canonical.replacingOccurrences(
                            of: "g_Texture0.sample", with: "g_Texture1.sample",
                            options: [], range: canonical.range(of: "g_Texture0.sample")
                        ), expectedSlot: 0, sampleCount: 4
                    ) == nil,
                postTailRejected:
                    SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.analyze(
                        canonical.replacingOccurrences(
                            of: "    return out;",
                            with: "    out.mwxFragColor.x *= 0.5;\n    return out;"
                        ), expectedSlot: 0, sampleCount: 4
                    ) == nil,
                extraSampleRejected:
                    SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.analyze(
                        canonical.replacingOccurrences(
                            of: "    float3 normalized =",
                            with: "    float4 hidden = g_Texture0.sample(s, uv);\n    float3 normalized ="
                        ), expectedSlot: 0, sampleCount: 4
                    ) == nil,
                carrierEscapeRejected:
                    SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.analyze(
                        canonical.replacingOccurrences(
                            of: "    float3 normalized =",
                            with: "    float4 escaped = mwx_sample_1;\n    float3 normalized ="
                        ), expectedSlot: 0, sampleCount: 4
                    ) == nil,
                normalizedInlineAccepted:
                    SceneAuthoredShaderNormalizedSampleSumAnalyzer.sourceSlot(
                        fragmentSource: normalizedInline
                    ) == 0,
                normalizedOverlapPrefersPassthrough:
                    aggregate == .passthrough(textureSlot: 0)
                        && overlapping
                            == .independentAlphaSignalPreserving(textureSlot: 0),
                normalizedWrongTotalRejected:
                    normalizedSlot(normalizedInline.replacingOccurrences(
                        of: "v_TexCoord[12]) * 0.006299;",
                        with: "v_TexCoord[12]) * 0.005299;"
                    )) == nil,
                normalizedNegativeWeightRejected:
                    normalizedSlot(normalizedInline.replacingOccurrences(
                        of: "v_TexCoord[12]) * 0.006299;",
                        with: "v_TexCoord[12]) * -0.006299;"
                    )) == nil,
                normalizedWrongSlotRejected:
                    normalizedSlot(normalizedInline.replacingOccurrences(
                        of: "g_Texture0, v_TexCoord[12]",
                        with: "g_Texture1, v_TexCoord[12]"
                    )) == nil,
                normalizedExtraReadRejected:
                    normalizedSlot(normalizedInline.replacingOccurrences(
                        of: "    gl_FragColor = albedo;",
                        with: "    vec4 escaped = albedo;\n    gl_FragColor = albedo;"
                    )) == nil,
                normalizedMutationRejected:
                    normalizedSlot(normalizedInline.replacingOccurrences(
                        of: "    gl_FragColor = albedo;",
                        with: "    albedo *= 1.0;\n    gl_FragColor = albedo;"
                    )) == nil,
                normalizedBranchRejected:
                    normalizedSlot(normalizedInline.replacingOccurrences(
                        of: "    gl_FragColor = albedo;",
                        with: "    if (true) { gl_FragColor = albedo; }"
                    )) == nil,
                normalizedExtraSampleRejected:
                    normalizedSlot(normalizedInline.replacingOccurrences(
                        of: "    gl_FragColor = albedo;",
                        with: "    vec4 hidden = texSample2D(g_Texture0, v_TexCoord[0]);\n    gl_FragColor = albedo;"
                    )) == nil,
                independentTransferPreserved:
                    SceneAuthoredShaderColorTransferAnalyzer.analyze(
                        fragmentSource: independentSignal
                    ) == .independentAlphaSignalPreserving(textureSlot: 1),
                routeProfile: capability.rawValue,
                routeState: capability.defaultRouteState.rawValue,
                disableState: SceneGenericShaderRouteState.resolve(
                    "disable-generic", defaultState: capability.defaultRouteState
                )?.rawValue,
                rollbackOwner: capability.validatedRollbackOwner.rawValue
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }

        let authored = compositeSource()
        let fact = SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer
            .analyze(fragmentSource: authored)
        let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16},{"name":"mwxTexture2Transform0","type":"vec4","offset":32},{"name":"mwxTexture2Transform1","type":"vec4","offset":48},{"name":"g_CompositeColor","type":"vec3","offset":64}]}},"ubos":[{"type":"_1","block_size":80,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture2","binding":2}]}"#.utf8)
        let msl = [
            "#include <metal_stdlib>", "using namespace metal;",
            "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture2Transform0; float4 mwxTexture2Transform1; float3 g_CompositeColor; };",
            "fragment void f() {",
            "    float4 blurred = g_Texture0.sample(s, uv);",
            "    float4 previous = g_Texture2.sample(s, uv);",
            "    blurred.xyz *= g_CompositeColor;",
            "    out.mwxFragColor = blurred;", "}",
        ].joined(separator: "\n")
        let capability = profile(
            transfer: .premultipliedAlpha, compositeSlots: (0, 2)
        )
        let coordinateAliasSource = compositeSource(coordinateAlias: true)
        let coordinatePreviousReuse = coordinateAliasSource.replacingOccurrences(
            of: "texSample2D(g_Texture2, v_TexCoord.xy)",
            with: "texSample2D(g_Texture2, blurredCoords)"
        )
        let output = CompositeOutput(
            transfer: transferName(
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: authored
                )
            ),
            blurredSlot: fact?.blurredSlot,
            previousSlot: fact?.previousSlot,
            unitColorUniform: fact?.unitColorUniform,
            artifactKind: artifact(
                authored: authored,
                msl: msl,
                reflection: reflection,
                uniformStruct: "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture2Transform0; float4 mwxTexture2Transform1; float3 g_CompositeColor; };"
            )?.program.colorTransfer.kind,
            boundedFrontendAccepted: SceneAuthoredShaderFrontend.compile(
                vertexSource: [
                    "attribute vec3 a_Position;", "attribute vec2 a_TexCoord;",
                    "varying vec2 v_TexCoord;", "void main() {",
                    "    gl_Position = vec4(a_Position, 1.0);",
                    "    v_TexCoord = a_TexCoord;", "}",
                ].joined(separator: "\n"),
                fragmentSource: authored
            ).program != nil,
            coordinateAliasAccepted:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(coordinateAlias: true)
                ) != nil,
            coordinateIdentityHelperAccepted:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(coordinateHelper: true)
                ) != nil,
            renamedSlotHelperAccepted:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        coordinateHelper: true,
                        blurredSlot: 3,
                        previousSlot: 5,
                        coordinateName: "unseenCoordinates",
                        coordinateHelperName: "unseenCoordinateIdentity"
                    )
                ) == .init(
                    blurredSlot: 3,
                    previousSlot: 5,
                    unitColorUniform: "g_CompositeColor"
                ),
            coordinateHelperMutationRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(coordinateHelper: true)
                        .replacingOccurrences(
                            of: "    return source;",
                            with: "    return source + ignored;"
                        )
                ) == nil,
            coordinateHelperEscapeRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(coordinateHelper: true)
                        .replacingOccurrences(
                            of: "    vec4 blurred =",
                            with: "    vec2 escapedCoordinates = blurredCoords;\n    vec4 blurred ="
                        )
                ) == nil,
            coordinateHelperWrongSampleRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(coordinateHelper: true)
                        .replacingOccurrences(
                            of: "texSample2D(g_Texture2, v_TexCoord.xy)",
                            with: "texSample2D(g_Texture2, blurredCoords)"
                        )
                ) == nil,
            duplicateCompositeReturnAccepted:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        directCompositeReturnCount: 2
                    )
                ) != nil,
            duplicateReturnWrongCarrierRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        directCompositeReturnCount: 2
                    ).replacingOccurrences(
                        of: "    return effectColor;\n    return effectColor;",
                        with: "    return effectColor;\n    return oldColor;"
                    )
                ) == nil,
            duplicateReturnIntermediateMutationRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        directCompositeReturnCount: 2
                    ).replacingOccurrences(
                        of: "    return effectColor;\n    return effectColor;",
                        with: "    return effectColor;\n    effectColor.a = 0.5;\n    return effectColor;"
                    )
                ) == nil,
            thirdCompositeReturnRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        directCompositeReturnCount: 3
                    )
                ) == nil,
            coordinateMutationRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        auxiliary: "    blurredCoords += vec2(0.1);",
                        coordinateAlias: true
                    )
                ) == nil,
            coordinatePreviousReuseRejected:
                coordinatePreviousReuse != coordinateAliasSource
                    && SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer
                        .analyze(fragmentSource: coordinatePreviousReuse) == nil,
            coordinateUniformProvenanceRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(coordinateAlias: true)
                        .replacingOccurrences(
                            of: "varying vec2 v_TexCoord;",
                            with: "uniform vec2 v_TexCoord;"
                        )
                ) == nil,
            coordinateInlineMutationRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(coordinateAlias: true)
                        .replacingOccurrences(
                            of: "texSample2D(g_Texture0, blurredCoords)",
                            with: "texSample2D(g_Texture0, (blurredCoords += vec2(0.1)))"
                        )
                ) == nil,
            nonunitMaskRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(mask: "0.5")
                ) == nil,
            postTailRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        tail: "    gl_FragColor.a *= 0.5;"
                    )
                ) == nil,
            auxiliarySampleRejected:
                SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compositeSource(
                        auxiliary: "    vec4 hidden = texSample2D(g_Texture0, vec2(0.5));"
                    )
                ) == nil,
            routeProfile: capability.rawValue,
            routeState: capability.defaultRouteState.rawValue,
            disableState: SceneGenericShaderRouteState.resolve(
                "disable-generic", defaultState: capability.defaultRouteState
            )?.rawValue,
            rollbackOwner: capability.validatedRollbackOwner.rawValue
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class StandardAlphaCompositeGenericContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.directory = tempfile.TemporaryDirectory(
            prefix="mwx-standard-alpha-composite-contract-"
        )
        root = Path(cls.directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "contract-harness"
        subprocess.run(
            [
                "xcrun", "swiftc", "-O", "-o", str(cls.binary),
                *[str(path) for path in SWIFT_SOURCES], str(harness),
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.directory.cleanup()

    def run_harness(self, mode: str) -> dict:
        completed = subprocess.run(
            [str(self.binary), mode],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_alpha_weighted_source_artifact_and_route_contract(self) -> None:
        output = self.run_harness("alpha")
        self.assertTrue(all(output[key] for key in (
            "memberwiseAccepted", "repeatedLocalsAccepted",
            "renamedThreeSampleAccepted", "crossBlockRejected",
            "mutationRejected", "nonuniformDeclarationRejected",
            "outputBoundaryPresent", "missingComponentRejected",
            "wrongCarrierRejected", "wrongSlotRejected", "postTailRejected",
            "extraSampleRejected", "carrierEscapeRejected",
            "normalizedInlineAccepted", "normalizedOverlapPrefersPassthrough",
            "normalizedWrongTotalRejected", "normalizedNegativeWeightRejected",
            "normalizedWrongSlotRejected", "normalizedExtraReadRejected",
            "normalizedMutationRejected", "normalizedBranchRejected",
            "normalizedExtraSampleRejected", "independentTransferPreserved",
        )), output)
        self.assertEqual(output["artifactKind"], "straight-alpha")
        self.assertEqual(output["sampleBoundaryCount"], 4)
        self.assertEqual(
            output["routeProfile"],
            "source-proven-graph-input-alpha-weighted-sample-average",
        )
        self.assertEqual(output["routeState"], "observe-only")
        self.assertEqual(output["disableState"], "disable-generic")
        self.assertEqual(output["rollbackOwner"], "program-first-incumbent")

    def test_unit_composite_source_artifact_and_route_contract(self) -> None:
        output = self.run_harness("composite")
        self.assertEqual(output["transfer"], "premultipliedAlpha")
        self.assertEqual(output["blurredSlot"], 0)
        self.assertEqual(output["previousSlot"], 2)
        self.assertEqual(output["unitColorUniform"], "g_CompositeColor")
        self.assertEqual(output["artifactKind"], "premultiplied")
        self.assertTrue(all(output[key] for key in (
            "boundedFrontendAccepted", "coordinateAliasAccepted",
            "coordinateIdentityHelperAccepted", "renamedSlotHelperAccepted",
            "coordinateHelperMutationRejected",
            "coordinateHelperEscapeRejected",
            "coordinateHelperWrongSampleRejected",
            "duplicateCompositeReturnAccepted",
            "duplicateReturnWrongCarrierRejected",
            "duplicateReturnIntermediateMutationRejected",
            "thirdCompositeReturnRejected",
            "coordinateMutationRejected", "coordinatePreviousReuseRejected",
            "coordinateUniformProvenanceRejected",
            "coordinateInlineMutationRejected", "nonunitMaskRejected",
            "postTailRejected", "auxiliarySampleRejected",
        )), output)
        self.assertEqual(
            output["routeProfile"],
            "source-proven-unit-previous-blurred-composite",
        )
        self.assertEqual(output["routeState"], "observe-only")
        self.assertEqual(output["disableState"], "disable-generic")
        self.assertEqual(output["rollbackOwner"], "program-first-incumbent")

        finalizer = FINALIZER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("details: colorContractFailureDetails(", finalizer)


if __name__ == "__main__":
    unittest.main()
