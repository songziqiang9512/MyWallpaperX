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
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let sourceSlot: Int?
    let scalarSampleCounts: [Int: Int]?
    let analyzedTransfer: String
    let artifactKind: String?
    let sourceUnpremultiplied: Bool
    let maskUnpremultiplied: Bool
    let outputPremultiplied: Bool
    let renamedAccepted: Bool
    let replacedAlphaRejected: Bool
    let secondColorRejected: Bool
    let helperSampleRejected: Bool
    let compilerExtraSampleRejected: Bool
    let compilerMaskProjectionRejected: Bool
    let compilerAlphaDriftRejected: Bool
}

@main
private struct GeneratedRGBPreservedAlphaHarness {
    static func main() throws {
        let vertex = [
            "attribute vec3 a_Position;", "attribute vec2 a_TexCoord;",
            "varying vec2 v_TexCoord;", "void main() {",
            "    v_TexCoord = a_TexCoord;",
            "    gl_Position = vec4(a_Position, 1.0);", "}",
        ].joined(separator: "\n")
        let authored = [
            "uniform sampler2D g_Texture0; uniform sampler2D g_Texture1;",
            "varying vec2 v_TexCoord;",
            "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {",
            "    return base + blend * opacity;", "}", "void main() {",
            "    vec4 scene = texSample2D(g_Texture0, v_TexCoord);",
            "    float mask = texSample2D(g_Texture1, v_TexCoord).r;",
            "    vec3 generated = vec3(v_TexCoord.x, v_TexCoord.y, 0.5);",
            "    vec3 finalColor = generated.rgb;",
            "    finalColor = ApplyBlending(31, lerp(finalColor.rgb, scene.rgb, scene.a), finalColor.rgb, 0.75 * mask);",
            "    float alpha = scene.a;",
            "    gl_FragColor = vec4(finalColor, alpha);", "}",
        ].joined(separator: "\n")
        let fragmentMSL = [
            "#include <metal_stdlib>", "using namespace metal;",
            "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };",
            "fragment void f() {",
            "    float4 scene = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);",
            "    float mask = g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord).x;",
            "    float3 finalColor = float3(in.v_TexCoord, 0.5);",
            "    finalColor = finalColor + finalColor * (0.75 * mask);",
            "    float alpha = scene.w;",
            "    out.mwxFragColor = float4(finalColor, alpha);",
            "    return out;", "}",
        ].joined(separator: "\n")
        let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16},{"name":"mwxTexture1Transform0","type":"vec4","offset":32},{"name":"mwxTexture1Transform1","type":"vec4","offset":48}]}},"ubos":[{"type":"_1","block_size":64,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)

        func artifact(authored fragment: String, msl: String) ->
            SceneGenericShaderProgramArtifact? {
            let built = SceneGenericShaderArtifactBuilder.build(
                requestKey: String(repeating: "c", count: 64),
                backendID: "glslang-spirv-cross-msl-v2",
                stages: [
                    .init(
                        name: "vertex", source: vertex, authoredSource: vertex,
                        msl: "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };",
                        reflection: reflection
                    ),
                    .init(
                        name: "fragment", source: fragment,
                        authoredSource: fragment, msl: msl,
                        reflection: reflection
                    ),
                ],
                maximumArtifactBytes: 1_024_000
            )
            guard case let .success(value) = built else { return nil }
            return value
        }

        let fact = SceneAuthoredShaderStraightBlendOutputAnalyzer
            .analyzeAlphaPreservingGeneratedRGB(fragmentSource: authored)
        let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authored
        )
        let analyzedTransfer: String
        if case let .straightAlphaPreserving(slot) = transfer {
            analyzedTransfer = "straight-alpha-preserving:\(slot)"
        } else {
            analyzedTransfer = "unexpected"
        }
        let positive = artifact(authored: authored, msl: fragmentMSL)
        let metal = positive?.program.metalSource ?? ""
        let renamed = authored
            .replacingOccurrences(of: "scene", with: "unseenCarrier")
            .replacingOccurrences(of: "mask", with: "unseenSignal")
            .replacingOccurrences(of: "finalColor", with: "unseenResult")

        let output = Output(
            sourceSlot: fact?.sourceSlot,
            scalarSampleCounts: fact?.scalarSampleCallCounts,
            analyzedTransfer: analyzedTransfer,
            artifactKind: positive?.program.colorTransfer.kind,
            sourceUnpremultiplied: metal.contains(
                "mwxGenericUnpremultiply(g_Texture0.sample("
            ),
            maskUnpremultiplied: metal.contains(
                "mwxGenericUnpremultiply(g_Texture1.sample("
            ),
            outputPremultiplied: metal.contains(
                "mwxGenericPremultiply(float4(finalColor, alpha))"
            ),
            renamedAccepted: SceneAuthoredShaderStraightBlendOutputAnalyzer
                .analyzeAlphaPreservingGeneratedRGB(
                    fragmentSource: renamed
                )?.sourceSlot == 0,
            replacedAlphaRejected: SceneAuthoredShaderStraightBlendOutputAnalyzer
                .analyzeAlphaPreservingGeneratedRGB(
                    fragmentSource: authored.replacingOccurrences(
                        of: "float alpha = scene.a;", with: "float alpha = 1.0;"
                    )
                ) == nil,
            secondColorRejected: SceneAuthoredShaderStraightBlendOutputAnalyzer
                .analyzeAlphaPreservingGeneratedRGB(
                    fragmentSource: authored.replacingOccurrences(
                        of: "float mask = texSample2D(g_Texture1, v_TexCoord).r;",
                        with: "vec4 maskColor = texSample2D(g_Texture1, v_TexCoord); float mask = maskColor.r;"
                    )
                ) == nil,
            helperSampleRejected: SceneAuthoredShaderStraightBlendOutputAnalyzer
                .analyzeAlphaPreservingGeneratedRGB(
                    fragmentSource: authored.replacingOccurrences(
                        of: "return base + blend * opacity;",
                        with: "return base + texSample2D(g_Texture1, vec2(0.5)).rgb * opacity;"
                    )
                ) == nil,
            compilerExtraSampleRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "    float alpha = scene.w;",
                    with: "    float4 hidden = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);\n    float alpha = scene.w;"
                )
            ) == nil,
            compilerMaskProjectionRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord).x;",
                    with: "g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord);"
                )
            ) == nil,
            compilerAlphaDriftRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "float alpha = scene.w;", with: "float alpha = mask;"
                )
            ) == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneGeneratedRGBPreservedAlphaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "GeneratedRGBPreservedAlphaHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "generated-rgb-preserved-alpha-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(
            build_root / "clang-module-cache"
        )
        environment["SWIFT_MODULECACHE_PATH"] = str(
            build_root / "swift-module-cache"
        )
        subprocess.run(
            [
                swiftc, "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES), str(harness),
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

    def test_source_compiler_and_color_boundaries(self):
        completed = subprocess.run(
            [str(self.binary)], cwd=REPOSITORY_ROOT, check=True,
            capture_output=True, text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "sourceSlot": 0,
            "scalarSampleCounts": {"1": 1},
            "analyzedTransfer": "straight-alpha-preserving:0",
            "artifactKind": "straight-alpha-preserving",
            "sourceUnpremultiplied": True,
            "maskUnpremultiplied": False,
            "outputPremultiplied": True,
            "renamedAccepted": True,
            "replacedAlphaRejected": True,
            "secondColorRejected": True,
            "helperSampleRejected": True,
            "compilerExtraSampleRejected": True,
            "compilerMaskProjectionRejected": True,
            "compilerAlphaDriftRejected": True,
        })


if __name__ == "__main__":
    unittest.main()
