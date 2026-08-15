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


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_support"),
    SCENE_ROOT / "RenderGraph/ShaderFrontend/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderArtifactCache.swift",
]

HARNESS = r"""
import Foundation

private struct Output: Codable {
    let status: String
    let code: String?
    let requestKey: String
    let backend: String?
    let uniformBufferIndex: Int?
    let uniformNames: [String]?
    let textureSlots: [Int]?
    let colorTransfer: String?
}

private func colorTransferName(_ transfer: SceneShaderColorTransfer) -> String {
    switch transfer {
    case .passthrough: return "passthrough"
    case .premultipliedAlpha: return "premultipliedAlpha"
    case .opaque: return "opaque"
    default: return "other"
    }
}

@main
private struct GenericShaderArtifactHarness {
    static func main() throws {
        let vertex = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let fragment = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let result: Output
        switch SceneResolvedMaterialGenericShaderArtifactCache.resolve(
            vertexSource: vertex,
            fragmentSource: fragment
        ) {
        case let .accepted(program, requestKey):
            result = .init(
                status: "accepted", code: nil, requestKey: requestKey,
                backend: program.backend.rawValue,
                uniformBufferIndex: program.uniformBufferIndex,
                uniformNames: program.uniformLayout.fields.map(\.name),
                textureSlots: program.textureBindings.map(\.slot),
                colorTransfer: colorTransferName(program.colorTransfer)
            )
        case let .unavailable(code, requestKey):
            result = .init(
                status: "unavailable", code: code, requestKey: requestKey,
                backend: nil, uniformBufferIndex: nil,
                uniformNames: nil, textureSlots: nil, colorTransfer: nil
            )
        }
        let data = try JSONEncoder().encode(result)
        FileHandle.standardOutput.write(data)
    }
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

    def run_harness(self, root: Path, *, route: str, fragment: str = FRAGMENT):
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
            "MWX_SCENE_GENERIC_SHADER_ROUTE": route,
            "MWX_SCENE_GENERIC_SHADER_REQUESTS": str(requests),
            "MWX_SCENE_GENERIC_SHADER_CACHE": str(cache),
        })
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
            "schemaVersion": 1,
            "kind": "scene-generic-shader-program-artifact",
            "backendID": "glslang-spirv-cross-msl-v1",
            "requestKey": key,
            "routeState": "prefer-generic",
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
                "colorTransfer": (
                    {"kind": "passthrough", "slot": 0}
                    if color_transfer == "passthrough"
                    else {"kind": color_transfer}
                ),
            },
        }

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

            artifact = self.artifact(first["requestKey"])
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
            self.assertIn(
                "state=prefer-generic outcome=accepted reason=- ", accepted_log
            )
            self.assertIn("count=1", accepted_log)

            changed, _, _, changed_log = self.run_harness(
                root,
                route="prefer-generic",
                fragment=FRAGMENT + "\n// distinct prepared source\n",
            )
            self.assertEqual(changed["status"], "unavailable")
            self.assertEqual(changed["code"], "artifact-missing")
            self.assertNotEqual(changed["requestKey"], accepted["requestKey"])
            self.assertIn(
                "outcome=fallback reason=artifact-missing", changed_log
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
                "outcome=fallback reason=artifact-contract-rejected", rejected_log
            )
            self.assertIn(f"request={first['requestKey']}", rejected_log)

    def test_opaque_artifact_maps_to_opaque_program_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(root, route="observe-only")
            artifact = self.artifact(first["requestKey"], color_transfer="opaque")
            artifact["program"]["staticLoopWork"] = 4
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(root, route="prefer-generic")
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "opaque")

    def test_premultiplied_artifact_maps_to_program_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(root, route="observe-only")
            artifact = self.artifact(
                first["requestKey"], color_transfer="premultiplied"
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(root, route="prefer-generic")
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "premultipliedAlpha")


if __name__ == "__main__":
    unittest.main()
