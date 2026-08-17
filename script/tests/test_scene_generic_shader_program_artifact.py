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
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderCompiler.swift",
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
    let backend: String?
    let uniformBufferIndex: Int?
    let uniformNames: [String]?
    let textureSlots: [Int]?
    let colorTransfer: String?
    let fragmentOutputChannelUse: String?
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
    let provenOutputChannelUse: String?
    let positiveFailure: String?
    let vectorWeightRejected: Bool
    let mutatedColorRejected: Bool
}

private struct PositionInputOutput: Codable {
    let directUsesClipSpace: Bool
    let directAvoidsTargetPixels: Bool
    let projectedUsesTargetPixels: Bool
}

private func colorTransferName(_ transfer: SceneShaderColorTransfer) -> String {
    switch transfer {
    case .passthrough: return "passthrough"
    case .interpolatedColor: return "interpolatedColor"
    case .straightAlpha: return "straightAlpha"
    case .premultipliedAlpha: return "premultipliedAlpha"
    case .opaque: return "opaque"
    default: return "other"
    }
}

@main
private struct GenericShaderArtifactHarness {
    static func main() throws {
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
                "    out.mwxFragColor = mix(history, current, rate);",
                "}",
            ].joined(separator: "\n")
            func build(
                _ fragment: String,
                authoredFragment: String = "void main() {}"
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
                            msl: vertexMSL, reflection: reflection
                        ),
                        .init(
                            name: "fragment", source: authoredFragment,
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
            switch build(fragmentMSL) {
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
            let provenOutputChannelUse: String?
            switch build(
                fragmentMSL,
                authoredFragment: "void main() { gl_FragColor = vec4(1.0); }"
            ) {
            case let .success(artifact):
                provenOutputChannelUse = artifact.program.fragmentOutputChannelUse
            case .failure:
                provenOutputChannelUse = nil
            }
            let vectorWeightRejected = failedColorTransfer(build(
                fragmentMSL.replacingOccurrences(of: "float rate =", with: "float2 rate =")
            ))
            let mutatedColorRejected = failedColorTransfer(build(
                fragmentMSL.replacingOccurrences(
                    of: "float4 history =",
                    with: "current *= 0.5;\n    float4 history ="
                )
            ))
            let output = BuilderOutput(
                positiveKind: positiveKind,
                positiveSlots: positiveSlots,
                unprovenOutputChannelUse: unprovenOutputChannelUse,
                provenOutputChannelUse: provenOutputChannelUse,
                positiveFailure: positiveFailure,
                vectorWeightRejected: vectorWeightRejected,
                mutatedColorRejected: mutatedColorRejected
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
            fragmentSource: fragment
        ) {
        case let .accepted(program, requestKey):
            result = .init(
                status: "accepted", code: nil, requestKey: requestKey,
                backend: program.backend.rawValue,
                uniformBufferIndex: program.uniformBufferIndex,
                uniformNames: program.uniformLayout.fields.map(\.name),
                textureSlots: program.textureBindings.map(\.slot),
                colorTransfer: colorTransferName(program.colorTransfer),
                fragmentOutputChannelUse: program.fragmentOutputChannelUse.rawValue
            )
        case let .unavailable(code, requestKey):
            result = .init(
                status: "unavailable", code: code, requestKey: requestKey,
                backend: nil, uniformBufferIndex: nil,
                uniformNames: nil, textureSlots: nil, colorTransfer: nil,
                fragmentOutputChannelUse: nil
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
        fragment: str = FRAGMENT,
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
            "schemaVersion": 2,
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
                "fragmentOutputChannelUse": "redDefined",
                "colorTransfer": (
                    {"kind": color_transfer, "slot": 0}
                    if color_transfer in ("passthrough", "straight-alpha")
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
        self.assertIn('"mwx-generic-shader-request-v2"', source)
        self.assertIn('"SceneGenericShaderPrograms-v2"', source)
        self.assertNotIn('"mwx-generic-shader-request-v1"', source)
        self.assertNotIn('"SceneGenericShaderPrograms-v1"', source)

        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            observed, _, cache, _ = self.run_harness(root, route="observe-only")
            current_key = self.request_key(
                "mwx-generic-shader-request-v2", VERTEX, FRAGMENT
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

    def test_compilation_coordinator_restarts_for_independent_key(self):
        completed = subprocess.run(
            [str(self.binary), "--coordinator"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertEqual(output, {
            "operationCount": 2,
            "firstSource": "spawn",
            "repeatedSource": "launch-result-cache",
            "independentSource": "spawn",
            "firstFailed": True,
            "repeatedFailed": True,
            "independentSucceeded": True,
        })

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
            "unprovenOutputChannelUse": "unproven",
            "provenOutputChannelUse": "redDefined",
            "vectorWeightRejected": True,
            "mutatedColorRejected": True,
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
                "state=prefer-generic outcome=accepted reason=- ", accepted_log
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
                "state=prefer-generic outcome=accepted reason=- ",
                default_log,
            )

            disabled, _, _, disabled_log = self.run_harness(
                root, route="disable-generic"
            )
            self.assertEqual(disabled["status"], "unavailable")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertIn(
                "state=disable-generic outcome=fallback "
                "reason=route-disabled ",
                disabled_log,
            )

            invalid, _, _, invalid_log = self.run_harness(
                root, route="unknown-route"
            )
            self.assertEqual(invalid["status"], "unavailable")
            self.assertEqual(invalid["code"], "route-invalid")
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
                "outcome=fallback "
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
                "outcome=fallback reason=artifact-contract-rejected", rejected_log
            )
            self.assertIn(f"request={first['requestKey']}", rejected_log)

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

    def test_straight_alpha_artifact_maps_color_source_slot(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(root, route="observe-only")
            artifact = self.artifact(
                first["requestKey"], color_transfer="straight-alpha"
            )
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(root, route="prefer-generic")
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "straightAlpha")

    def test_interpolated_color_artifact_requires_sorted_bound_slots(self):
        with tempfile.TemporaryDirectory(prefix="mwx-generic-artifact-test-") as directory:
            root = Path(directory)
            first, _, cache, _ = self.run_harness(root, route="observe-only")
            artifact = self.artifact(
                first["requestKey"], color_transfer="interpolated-color"
            )
            artifact["program"]["textureBindings"].append({
                "name": "g_Texture1", "slot": 1, "channelUse": "unproven"
            })
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            accepted, _, _, _ = self.run_harness(root, route="prefer-generic")
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["colorTransfer"], "interpolatedColor")

            artifact["program"]["colorTransfer"]["slots"] = [1, 0]
            (cache / f"{first['requestKey']}.json").write_text(
                json.dumps(artifact), encoding="utf-8"
            )
            rejected, _, _, _ = self.run_harness(root, route="prefer-generic")
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")


if __name__ == "__main__":
    unittest.main()
