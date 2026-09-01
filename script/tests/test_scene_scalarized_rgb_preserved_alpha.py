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
    let analyzedTransfer: String
    let artifactKind: String?
    let sourceUnpremultiplied: Bool
    let auxiliaryUnpremultiplied: Bool
    let outputPremultiplied: Bool
    let renamedAccepted: Bool
    let alphaDriftRejected: Bool
    let hiddenSourceSampleRejected: Bool
    let auxiliaryVectorRejected: Bool
    let missingComponentRejected: Bool
    let componentMismatchRejected: Bool
    let nonterminalOutputRejected: Bool
}

@main
private struct ScalarizedRGBPreservedAlphaHarness {
    static func main() throws {
        let vertex = [
            "attribute vec3 a_Position;", "attribute vec2 a_TexCoord;",
            "varying vec2 v_TexCoord;", "void main() {",
            "    v_TexCoord = a_TexCoord;",
            "    gl_Position = vec4(a_Position, 1.0);", "}",
        ].joined(separator: "\n")
        let authored = [
            "uniform sampler2D g_Texture0; uniform sampler2D g_Texture1;",
            "uniform float g_Amount; varying vec2 v_TexCoord;",
            "vec3 BlendSignal(vec3 base, vec3 signal, float amount) {",
            "    return mix(base, signal, amount);", "}", "void main() {",
            "    vec4 carrier = texSample2D(g_Texture0, v_TexCoord);",
            "    float signal0 = texSample2DLod(g_Texture1, v_TexCoord, 1.0).r;",
            "    float signal1 = texSample2D(g_Texture1, v_TexCoord).r;",
            "    float strength = smoothstep(signal0, signal1, g_Amount);",
            "    vec3 generated = vec3(signal0, signal1, strength);",
            "    carrier.rgb = BlendSignal(carrier.rgb, generated, strength);",
            "    gl_FragColor = vec4(max(vec3(0.0), carrier.rgb), carrier.a);", "}",
        ].joined(separator: "\n")
        let fragmentMSL = [
            "#include <metal_stdlib>", "using namespace metal;",
            "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; float g_Amount; };",
            "fragment void f() {", "    mwxGenericFragment_out out = {};",
            "    float4 carrier = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);",
            "    float signal0 = g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord, level(1.0)).x;",
            "    float signal1 = g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord).x;",
            "    float strength = smoothstep(signal0, signal1, _31.g_Amount);",
            "    float3 sourceRGB = carrier.xyz;",
            "    float3 generated = float3(signal0, signal1, strength);",
            "    float3 blended = mix(sourceRGB, generated, float3(strength));",
            "    carrier.x = blended.x;", "    carrier.y = blended.y;",
            "    carrier.z = blended.z;",
            "    out.mwxFragColor = float4(fast::max(float3(0.0), carrier.xyz), carrier.w);",
            "    return out;", "}",
        ].joined(separator: "\n")
        let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxTexture0Transform0","type":"vec4","offset":0},{"name":"mwxTexture0Transform1","type":"vec4","offset":16},{"name":"mwxTexture1Transform0","type":"vec4","offset":32},{"name":"mwxTexture1Transform1","type":"vec4","offset":48},{"name":"g_Amount","type":"float","offset":64}]}},"ubos":[{"type":"_1","block_size":80,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)

        func artifact(authored fragment: String, msl: String) ->
            SceneGenericShaderProgramArtifact? {
            let built = SceneGenericShaderArtifactBuilder.build(
                requestKey: String(repeating: "d", count: 64),
                backendID: "glslang-spirv-cross-msl-v2",
                stages: [
                    .init(
                        name: "vertex", source: vertex, authoredSource: vertex,
                        msl: "struct MWXUniforms { float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; float g_Amount; };",
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
        let renamedMSL = fragmentMSL
            .replacingOccurrences(of: "carrier", with: "unseenCarrier")
            .replacingOccurrences(of: "blended", with: "unseenRGB")
        let output = Output(
            analyzedTransfer: analyzedTransfer,
            artifactKind: positive?.program.colorTransfer.kind,
            sourceUnpremultiplied: metal.contains(
                "mwxGenericUnpremultiply(g_Texture0.sample("
            ),
            auxiliaryUnpremultiplied: metal.contains(
                "mwxGenericUnpremultiply(g_Texture1.sample("
            ),
            outputPremultiplied: metal.contains(
                "mwxGenericPremultiply(float4(fast::max(float3(0.0), carrier.xyz), carrier.w))"
            ),
            renamedAccepted: artifact(
                authored: authored, msl: renamedMSL
            ) != nil,
            alphaDriftRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "carrier.w);", with: "signal0);"
                )
            ) == nil,
            hiddenSourceSampleRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "    float strength =",
                    with: "    float hidden = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord).x;\n    float strength ="
                )
            ) == nil,
            auxiliaryVectorRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord).x;",
                    with: "g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord);"
                )
            ) == nil,
            missingComponentRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "    carrier.z = blended.z;\n", with: ""
                )
            ) == nil,
            componentMismatchRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "carrier.z = blended.z;", with: "carrier.z = blended.y;"
                )
            ) == nil,
            nonterminalOutputRejected: artifact(
                authored: authored,
                msl: fragmentMSL.replacingOccurrences(
                    of: "    return out;",
                    with: "    float late = signal0;\n    return out;"
                )
            ) == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneScalarizedRGBPreservedAlphaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "ScalarizedRGBPreservedAlphaHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "scalarized-rgb-preserved-alpha-harness"
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

    def test_scalarized_rgb_preserves_only_the_graph_input_boundary(self):
        self.maxDiff = None
        completed = subprocess.run(
            [str(self.binary)], cwd=REPOSITORY_ROOT, check=True,
            capture_output=True, text=True,
        )
        self.assertEqual(json.loads(completed.stdout), {
            "analyzedTransfer": "straight-alpha-preserving:0",
            "artifactKind": "straight-alpha-preserving",
            "sourceUnpremultiplied": True,
            "auxiliaryUnpremultiplied": False,
            "outputPremultiplied": True,
            "renamedAccepted": True,
            "alphaDriftRejected": True,
            "hiddenSourceSampleRejected": True,
            "auxiliaryVectorRejected": True,
            "missingComponentRejected": True,
            "componentMismatchRejected": True,
            "nonterminalOutputRejected": True,
        })


if __name__ == "__main__":
    unittest.main()
