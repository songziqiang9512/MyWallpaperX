#!/usr/bin/env python3

"""Same-slot sampled-alpha RGBA reconstruction stays on one shared path."""

from __future__ import annotations

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
    let transfer: String
    let sourceSlot: Int?
    let auxiliarySlots: [Int]?
    let preservesSnapshotAlpha: Bool?
    let totalSamples: Int?
    let renamedAccepted: Bool
    let loweringAccepted: Bool
    let artifactTransfer: String?
    let sourceUnpremultipliedCount: Int
    let dataUnpremultipliedCount: Int
    let outputPremultiplied: Bool
    let routeProfile: String
    let routeState: String
    let rollbackOwner: String
    let defaultPermitsBoundedFrontend: Bool
    let defaultFallbackOutcome: String
    let disablePermitsBoundedFrontend: Bool
    let disableFallbackOutcome: String
    let wrongSlotRejected: Bool
    let wrongProjectionRejected: Bool
    let alphaOverwriteRejected: Bool
    let hiddenSourceRejected: Bool
    let endpointDriftRejected: Bool
    let compilerAlphaLaneDriftRejected: Bool
    let compilerProjectionDriftRejected: Bool
    let compilerTemporaryEscapeRejected: Bool
    let compilerHiddenSourceRejected: Bool
    let compilerEndpointDriftRejected: Bool
    let realCompilerLoweringAccepted: Bool
    let realCompilerSourceUnpremultipliedCount: Int
}

@main
private enum SampledAlphaRGBAReconstructionHarness {
    static func main() throws {
        let authored = [
            "uniform sampler2D g_Texture0;",
            "uniform sampler2D g_Texture1;",
            "uniform sampler2D g_Texture2;",
            "varying vec4 v_Coordinate;",
            "void main() {",
            "    vec4 reconstructed;",
            "    float mask = texSample2D(g_Texture2, v_Coordinate.zw).r;",
            "    vec4 snapshot = texSample2D(g_Texture0, v_Coordinate.xy);",
            "    reconstructed.ga = texSample2D(g_Texture0, v_Coordinate.zw).ga;",
            "    reconstructed.r = texSample2D(g_Texture0, v_Coordinate.xy + 0.01).r;",
            "    reconstructed.b = texSample2D(g_Texture0, v_Coordinate.xy - 0.01).b;",
            "    vec3 field = texSample2D(g_Texture1, v_Coordinate.xy).gbr;",
            "    reconstructed.rgb = mix(reconstructed.rgb, field, 0.1);",
            "    gl_FragColor = mix(snapshot, reconstructed, mask);",
            "}",
        ].joined(separator: "\n")
        let msl = [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "fragment void f() {",
            "    float mask = g_Texture2.sample(g_Texture2Smplr, in.v_Coordinate.zw).x;",
            "    float4 snapshot = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.xy);",
            "    float4 reconstructed;",
            "    float2 sampledGA = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.zw).yw;",
            "    reconstructed.y = sampledGA.x;",
            "    reconstructed.w = sampledGA.y;",
            "    reconstructed.x = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.xy + 0.01).x;",
            "    reconstructed.z = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.xy - 0.01).z;",
            "    float3 field = g_Texture1.sample(g_Texture1Smplr, in.v_Coordinate.xy).yzx;",
            "    float3 filtered = mix(reconstructed.xyz, field, float3(0.1));",
            "    reconstructed.x = filtered.x;",
            "    reconstructed.y = filtered.y;",
            "    reconstructed.z = filtered.z;",
            "    out.mwxFragColor = mix(snapshot, reconstructed, float4(mask));",
            "    return out;",
            "}",
        ].joined(separator: "\n")

        func fact(
            _ source: String
        ) -> SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact? {
            SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze(
                fragmentSource: source
            )
        }

        func routeProfile() -> SceneGenericShaderCapabilityProfile {
            SceneGenericShaderCapabilityProfile(
                colorTransfer: .straightAlpha(textureSlot: 0),
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
                sameAlphaReconstructedRGBFilterSourceSlot: 0,
                sameAlphaReconstructedRGBFilterAuxiliarySlots: [1, 2],
                typedStaticDataAuxiliarySlots: [1, 2],
                unitCompositeBlurredSlot: nil,
                unitCompositePreviousSlot: nil,
                hasExternalProviderTexture: false,
                producesScalarRedOutput: false,
                isSourceIndependentPremultipliedOutput: false,
                graphTextureSlots: [],
                graphInputTextureSlots: [0],
                r8TextureSlots: [],
                hasDefaultedOpacityMaskSampler: false,
                hasStageScopedUniformBindings: false,
                hasStereoAudioSpectrumArrays: false
            )
        }

        let analyzed = fact(authored)
        let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authored
        )
        let lowered = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: msl,
            authoredSource: authored
        )
        let loweredMSL = lowered?.msl ?? ""
        let realCompilerMSL = CommandLine.arguments.count == 2
            ? (try? String(
                contentsOfFile: CommandLine.arguments[1],
                encoding: .utf8
            )) ?? ""
            : ""
        let realCompilerLowered = try?
            SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: realCompilerMSL,
                authoredSource: authored
            )
        let realCompilerLoweredMSL = realCompilerLowered?.msl ?? ""
        let profile = routeProfile()
        let renamed = authored
            .replacingOccurrences(of: "reconstructed", with: "colorCarrier")
            .replacingOccurrences(of: "snapshot", with: "entryColor")
            .replacingOccurrences(of: "field", with: "proceduralValue")

        let output = Output(
            transfer: {
                if case .straightAlpha(textureSlot: 0) = transfer {
                    return "straight-alpha-0"
                }
                return "unexpected"
            }(),
            sourceSlot: analyzed?.sourceSlot,
            auxiliarySlots: analyzed?.auxiliarySlots.sorted(),
            preservesSnapshotAlpha: analyzed?.preservesSnapshotAlpha,
            totalSamples: analyzed?.totalSampleCallCount,
            renamedAccepted: fact(renamed) != nil,
            loweringAccepted: lowered != nil,
            artifactTransfer: lowered?.transfer.kind,
            sourceUnpremultipliedCount: loweredMSL.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count - 1,
            dataUnpremultipliedCount: [1, 2].reduce(0) { count, slot in
                count + loweredMSL.components(
                    separatedBy:
                        "mwxGenericUnpremultiply(g_Texture\(slot).sample("
                ).count - 1
            },
            outputPremultiplied: loweredMSL.contains(
                "out.mwxFragColor = mwxGenericPremultiply("
                    + "mix(snapshot, reconstructed, float4(mask)));"
            ),
            routeProfile: profile.rawValue,
            routeState: profile.defaultRouteState.rawValue,
            rollbackOwner: profile.validatedRollbackOwner.rawValue,
            defaultPermitsBoundedFrontend:
                profile.permitsBoundedFrontendAfterArtifactFailure(
                    routeState: profile.defaultRouteState
                ),
            defaultFallbackOutcome: profile.artifactFallbackOutcome(
                routeState: profile.defaultRouteState
            ),
            disablePermitsBoundedFrontend:
                profile.permitsBoundedFrontendAfterArtifactFailure(
                    routeState: .disableGeneric
                ),
            disableFallbackOutcome: profile.artifactFallbackOutcome(
                routeState: .disableGeneric
            ),
            wrongSlotRejected: fact(authored.replacingOccurrences(
                of: "texSample2D(g_Texture0, v_Coordinate.zw).ga",
                with: "texSample2D(g_Texture1, v_Coordinate.zw).ga"
            )) == nil,
            wrongProjectionRejected: fact(authored.replacingOccurrences(
                of: "v_Coordinate.zw).ga;",
                with: "v_Coordinate.zw).rg;"
            )) == nil,
            alphaOverwriteRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = mix(snapshot, reconstructed, mask);",
                with: "    reconstructed.a = mask;\n"
                    + "    gl_FragColor = mix(snapshot, reconstructed, mask);"
            )) == nil,
            hiddenSourceRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = mix(snapshot, reconstructed, mask);",
                with: "    float hidden = texSample2D(g_Texture0, v_Coordinate.xy).r;\n"
                    + "    gl_FragColor = mix(snapshot, reconstructed, mask);"
            )) == nil,
            endpointDriftRejected: fact(authored.replacingOccurrences(
                of: "mix(snapshot, reconstructed, mask)",
                with: "mix(reconstructed, snapshot, mask)"
            )) == nil,
            compilerAlphaLaneDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "reconstructed.w = sampledGA.y;",
                        with: "reconstructed.w = sampledGA.x;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerProjectionDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: ").yw;",
                        with: ").xy;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerTemporaryEscapeRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "    reconstructed.y = sampledGA.x;",
                        with: "    reconstructed.y = sampledGA.x;\n"
                            + "    float escapedGA = sampledGA.x;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerHiddenSourceRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "    out.mwxFragColor = mix(snapshot, reconstructed, float4(mask));",
                        with: "    float hidden = g_Texture0.sample("
                            + "g_Texture0Smplr, in.v_Coordinate.xy).x;\n"
                            + "    out.mwxFragColor = mix(snapshot, reconstructed, float4(mask));"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerEndpointDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "mix(snapshot, reconstructed, float4(mask))",
                        with: "mix(reconstructed, snapshot, float4(mask))"
                    ),
                    authoredSource: authored
                )) == nil,
            realCompilerLoweringAccepted: realCompilerLowered != nil,
            realCompilerSourceUnpremultipliedCount:
                realCompilerLoweredMSL.components(
                    separatedBy:
                        "mwxGenericUnpremultiply(g_Texture0.sample("
                ).count - 1
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneSampledAlphaRGBAReconstructionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory(
            prefix="mwx-sampled-alpha-rgba-"
        )
        root = Path(cls.build_directory.name)
        harness = root / "SampledAlphaRGBAReconstructionHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        compiler_source = root / "sampled-alpha.frag"
        compiler_source.write_text(
            """#version 450
layout(location=0) in vec4 v_Coordinate;
layout(location=0) out vec4 mwxFragColor;
layout(binding=0) uniform sampler2D g_Texture0;
layout(binding=1) uniform sampler2D g_Texture1;
layout(binding=2) uniform sampler2D g_Texture2;
void main() {
    vec4 reconstructed;
    float mask = texture(g_Texture2, v_Coordinate.zw).r;
    vec4 snapshot = texture(g_Texture0, v_Coordinate.xy);
    reconstructed.ga = texture(g_Texture0, v_Coordinate.zw).ga;
    reconstructed.r = texture(g_Texture0, v_Coordinate.xy + 0.01).r;
    reconstructed.b = texture(g_Texture0, v_Coordinate.xy - 0.01).b;
    vec3 field = texture(g_Texture1, v_Coordinate.xy).gbr;
    reconstructed.rgb = mix(reconstructed.rgb, field, 0.1);
    mwxFragColor = mix(snapshot, reconstructed, mask);
}
""",
            encoding="utf-8",
        )
        spirv = root / "sampled-alpha.spv"
        actual_msl = root / "sampled-alpha.metal"
        glslang = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
        )
        spirv_cross = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Resources/SceneShaderCompilerTools/spirv-cross"
        )
        compiler = subprocess.run(
            [
                str(glslang), "-V", "--auto-map-bindings",
                "--auto-map-locations", "-S", "frag", "-e", "main",
                "-o", str(spirv), str(compiler_source),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compiler.returncode != 0:
            raise RuntimeError(compiler.stderr or compiler.stdout)
        cross = subprocess.run(
            [
                str(spirv_cross), str(spirv), "--msl", "--msl-version",
                "20000", "--msl-decoration-binding", "--rename-entry-point",
                "main", "mwxGenericFragment", "frag", "--output",
                str(actual_msl),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if cross.returncode != 0:
            raise RuntimeError(cross.stderr or cross.stdout)
        cls.binary = root / "sampled-alpha-rgba"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
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
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        result = subprocess.run(
            [str(cls.binary), str(actual_msl)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr or result.stdout)
        cls.result = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def test_shared_color_boundary_and_route(self) -> None:
        self.assertEqual(self.result["transfer"], "straight-alpha-0")
        self.assertEqual(self.result["sourceSlot"], 0)
        self.assertEqual(self.result["auxiliarySlots"], [1, 2])
        self.assertFalse(self.result["preservesSnapshotAlpha"])
        self.assertEqual(self.result["totalSamples"], 6)
        self.assertTrue(self.result["renamedAccepted"])
        self.assertTrue(self.result["loweringAccepted"])
        self.assertEqual(self.result["artifactTransfer"], "straight-alpha")
        self.assertEqual(self.result["sourceUnpremultipliedCount"], 4)
        self.assertEqual(self.result["dataUnpremultipliedCount"], 0)
        self.assertTrue(self.result["outputPremultiplied"])
        self.assertEqual(
            self.result["routeProfile"],
            "source-proven-graph-input-sampled-alpha-reconstructed-rgba-data-filter",
        )
        self.assertEqual(self.result["routeState"], "generic-only")
        self.assertEqual(self.result["rollbackOwner"], "none")
        self.assertFalse(self.result["defaultPermitsBoundedFrontend"])
        self.assertEqual(
            self.result["defaultFallbackOutcome"], "rejected"
        )
        self.assertFalse(self.result["disablePermitsBoundedFrontend"])
        self.assertEqual(self.result["disableFallbackOutcome"], "fallback")
        self.assertTrue(self.result["realCompilerLoweringAccepted"])
        self.assertEqual(
            self.result["realCompilerSourceUnpremultipliedCount"], 4
        )

    def test_source_and_compiler_drift_fail_closed(self) -> None:
        for key in (
            "wrongSlotRejected",
            "wrongProjectionRejected",
            "alphaOverwriteRejected",
            "hiddenSourceRejected",
            "endpointDriftRejected",
            "compilerAlphaLaneDriftRejected",
            "compilerProjectionDriftRejected",
            "compilerTemporaryEscapeRejected",
            "compilerHiddenSourceRejected",
            "compilerEndpointDriftRejected",
        ):
            self.assertTrue(self.result[key], (key, self.result))


if __name__ == "__main__":
    unittest.main()
