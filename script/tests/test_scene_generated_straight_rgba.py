#!/usr/bin/env python3

"""Source-independent generated straight RGBA crosses one premultiplied boundary."""

from __future__ import annotations

import json
import os
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
]


HARNESS = r'''
import Foundation

private let vertex = """
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord.xy = a_TexCoord;
}
"""

private let authored = """
uniform sampler2D g_Texture0;
uniform vec4 g_Texture0Resolution;
uniform float u_ypos;
uniform float u_grot;
uniform float u_opacity;
uniform vec3 u_col1;
uniform vec3 u_col2;
varying vec4 v_TexCoord;
vec2 rotateVec2(vec2 value, float angle) { return value + vec2(angle); }
void main() {
    vec2 uv = ((v_TexCoord.xy - 0.5) * g_Texture0Resolution.xy) / g_Texture0Resolution.y;
    vec2 cuv = rotateVec2(uv, 3.1415926 * u_grot);
    vec3 col = mix(u_col1, u_col2, cuv.y + u_ypos + 0.5);
    gl_FragColor = vec4(col, u_opacity);
}
"""

private let msl = """
#include <metal_stdlib>
using namespace metal;
struct FragmentOut { float4 mwxFragColor [[color(0)]]; };
fragment FragmentOut mwxGenericFragment() {
    FragmentOut out = {};
    float3 col = mix(float3(1.0), float3(0.0), 0.5);
    out.mwxFragColor = float4(col, 0.75);
    return out;
}
"""

private struct Output: Codable {
    let transfer: String
    let factRGB: String?
    let factAlpha: String?
    let renamedAccepted: Bool
    let alphaDrivesRGBRejected: Bool
    let sampledHelperRejected: Bool
    let lodSampledHelperRejected: Bool
    let directGenericSampleRejected: Bool
    let helperAlphaConsumptionRejected: Bool
    let rgbMutationRejected: Bool
    let alphaAliasRejected: Bool
    let secondOutputRejected: Bool
    let boundedAccepted: Bool
    let boundedPremultiplies: Bool
    let artifactAccepted: Bool
    let artifactKind: String?
    let artifactPremultiplies: Bool
    let artifactBindingAccepted: Bool
    let resolutionDependencyAccepted: Bool
    let missingResolutionSamplerRejected: Bool
    let compilerSampleDriftRejected: Bool
    let compilerMemberOutputRejected: Bool
    let compilerDuplicateOutputRejected: Bool
    let compilerHelperConflictRejected: Bool
    let routeProfile: String
    let routeState: String
    let rollbackOwner: String
    let externalProviderRejected: Bool
    let graphInputRejected: Bool
}

private func fact(_ source: String) ->
    SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.Fact? {
    SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.analyze(
        fragmentSource: source
    )
}

private func profile(
    source: String,
    provider: Bool = false,
    graphInputs: Set<Int> = [0]
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        fragmentSource: source,
        colorTransfer: SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: source
        ),
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        conditionalStraightUnionSourceSlot: nil,
        singleSamplerAlphaMutationSourceSlot: nil,
        sameSlotChannelReconstructionSourceSlot: nil,
        auxiliaryRGBMixSourceSlot: nil,
        normalizedSampleSumSourceSlot: nil,
        alphaWeightedSampleAverageSourceSlot: nil,
        preservedAlphaRGBFilterSourceSlot: nil,
        preservedAlphaRGBFilterTextureSlots: [],
        unitCompositeBlurredSlot: nil,
        unitCompositePreviousSlot: nil,
        hasExternalProviderTexture: provider,
        producesScalarRedOutput: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: [0],
        graphInputTextureSlots: graphInputs,
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyGraphInputSampler: true,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false
    )
}

@main
private enum GeneratedStraightRGBAHarness {
    static func main() throws {
        let proven = fact(authored)
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: authored
        ).program
        let artifact = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: msl,
            authoredSource: authored
        )
        let expected = SceneGenericShaderCapabilityProfile.ordinaryShader
        let route = profile(source: authored)
        let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authored
        )
        let transferName = switch transfer {
        case .generatedStraightAlpha: "generated-straight-alpha"
        default: "unexpected"
        }
        let renamed = authored
            .replacingOccurrences(of: "vec3 col", with: "vec3 gradient")
            .replacingOccurrences(of: "vec4(col,", with: "vec4(gradient,")
            .replacingOccurrences(of: "u_opacity", with: "surfaceAlpha")
        let sampled = authored.replacingOccurrences(
            of: "vec2 rotateVec2(vec2 value, float angle) { return value + vec2(angle); }",
            with: [
                "vec2 rotateVec2(vec2 value, float angle) {",
                "    return value + texSample2D(g_Texture0, value).rg + vec2(angle);",
                "}",
            ].joined(separator: "\n")
        )
        let lodSampled = authored.replacingOccurrences(
            of: "return value + vec2(angle);",
            with: "return value + texSample2DLod(g_Texture0, value, 0.0).rg + vec2(angle);"
        )
        let directGenericSample = authored.replacingOccurrences(
            of: "mix(u_col1, u_col2, cuv.y + u_ypos + 0.5)",
            with: "mix(u_col1, u_col2, cuv.y + u_ypos + 0.5) + texture(g_Texture0, cuv).rgb"
        )
        let helperAlphaConsumption = authored.replacingOccurrences(
            of: "return value + vec2(angle);",
            with: "return value * u_opacity + vec2(angle);"
        )
        let resolutionLayout = SceneGenericShaderArtifactBuilder.ReflectedLayout(
            fields: [.init(
                name: "g_Texture0Resolution",
                authoredName: "g_Texture0Resolution",
                type: "float4",
                offset: 0
            )],
            byteSize: 16
        )
        let resolutionDependencies = SceneGenericShaderArtifactBuilder
            .resolutionTextureDependencySlots(
                layout: resolutionLayout,
                authoredSources: [authored]
            )
        let augmentedResolutionLayout = SceneGenericShaderArtifactBuilder
            .addingTextureTransformFields(
                to: resolutionLayout,
                activeSlots: resolutionDependencies
            )
        let output = Output(
            transfer: transferName,
            factRGB: proven?.rgbName,
            factAlpha: proven?.alphaName,
            renamedAccepted: fact(renamed) != nil,
            alphaDrivesRGBRejected: fact(authored.replacingOccurrences(
                of: "mix(u_col1, u_col2, cuv.y + u_ypos + 0.5)",
                with: "mix(u_col1, u_col2, cuv.y + u_ypos + 0.5) * u_opacity"
            )) == nil,
            sampledHelperRejected: fact(sampled) == nil,
            lodSampledHelperRejected: fact(lodSampled) == nil,
            directGenericSampleRejected: fact(directGenericSample) == nil,
            helperAlphaConsumptionRejected: fact(helperAlphaConsumption) == nil,
            rgbMutationRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = vec4(col, u_opacity);",
                with: "    col *= 0.5;\n    gl_FragColor = vec4(col, u_opacity);"
            )) == nil,
            alphaAliasRejected: fact(authored.replacingOccurrences(
                of: "gl_FragColor = vec4(col, u_opacity);",
                with: "float alpha = u_opacity;\n    gl_FragColor = vec4(col, alpha);"
            )) == nil,
            secondOutputRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = vec4(col, u_opacity);",
                with: "    gl_FragColor = vec4(col, u_opacity);\n    gl_FragColor = vec4(col, u_opacity);"
            )) == nil,
            boundedAccepted: bounded != nil,
            boundedPremultiplies: bounded?.metalSource.contains(
                "return mwxPremultiply(mwxFragColor);"
            ) == true,
            artifactAccepted: artifact != nil,
            artifactKind: artifact?.transfer.kind,
            artifactPremultiplies: artifact?.msl.contains(
                "out.mwxFragColor = mwxGenericPremultiply(float4(col, 0.75));"
            ) == true,
            artifactBindingAccepted: SceneGenericShaderArtifactBuilder.colorTransfer(
                .init(kind: "generated-straight-alpha", slot: nil, slots: nil),
                isBoundBy: []
            ),
            resolutionDependencyAccepted:
                resolutionDependencies == [0]
                && augmentedResolutionLayout.map {
                    SceneGenericShaderArtifactBuilder.validTextureTransformLayout(
                        $0,
                        activeSlots: [0]
                    )
                } == true,
            missingResolutionSamplerRejected: SceneGenericShaderArtifactBuilder
                .resolutionTextureDependencySlots(
                    layout: resolutionLayout,
                    authoredSources: [authored.replacingOccurrences(
                        of: "uniform sampler2D g_Texture0;",
                        with: ""
                    )]
                ).isEmpty,
            compilerSampleDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "float3 col =",
                        with: "float4 hidden = g_Texture0.sample(sampler(), float2(0.5));\n    float3 col ="
                    ),
                    authoredSource: authored
                )) == nil,
            compilerMemberOutputRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "out.mwxFragColor = float4(col, 0.75);",
                        with: "out.mwxFragColor.xyz = col;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerDuplicateOutputRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "    return out;",
                        with: "    out.mwxFragColor = float4(col, 1.0);\n    return out;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerHelperConflictRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "using namespace metal;",
                        with: "using namespace metal;\nfloat4 mwxGenericPremultiply(float4 value);"
                    ),
                    authoredSource: authored
                )) == nil,
            routeProfile: route.rawValue,
            routeState: route.defaultRouteState.rawValue,
            rollbackOwner: route.validatedRollbackOwner.rawValue,
            externalProviderRejected:
                profile(source: authored, provider: true) == expected,
            graphInputRejected:
                profile(source: authored, graphInputs: [0]) == expected
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneGeneratedStraightRGBATests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-generated-straight-rgba-"
        )
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "generated-straight-rgba-test"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                "swiftc",
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Security",
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)
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

    def test_source_and_both_backends_conserve_generated_straight_rgba(self) -> None:
        self.assertEqual(self.result["transfer"], "generated-straight-alpha")
        self.assertEqual(self.result["factRGB"], "col")
        self.assertEqual(self.result["factAlpha"], "u_opacity")
        for key in (
            "renamedAccepted",
            "boundedAccepted",
            "boundedPremultiplies",
            "artifactAccepted",
            "artifactPremultiplies",
            "artifactBindingAccepted",
            "resolutionDependencyAccepted",
            "missingResolutionSamplerRejected",
        ):
            self.assertTrue(self.result[key], key)
        self.assertEqual(self.result["artifactKind"], "generated-straight-alpha")
        self.assertEqual(
            self.result["routeProfile"],
            "ordinary-shader",
        )
        self.assertEqual(self.result["routeState"], "generic-only")
        self.assertEqual(self.result["rollbackOwner"], "bounded-frontend")

    def test_source_compiler_and_route_drift_fail_closed(self) -> None:
        for key in (
            "alphaDrivesRGBRejected",
            "sampledHelperRejected",
            "lodSampledHelperRejected",
            "directGenericSampleRejected",
            "helperAlphaConsumptionRejected",
            "rgbMutationRejected",
            "alphaAliasRejected",
            "secondOutputRejected",
            "compilerSampleDriftRejected",
            "compilerMemberOutputRejected",
            "compilerDuplicateOutputRejected",
            "compilerHelperConflictRejected",
            "externalProviderRejected",
            "graphInputRejected",
        ):
            self.assertTrue(self.result[key], key)


if __name__ == "__main__":
    unittest.main()
