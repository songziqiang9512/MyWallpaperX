#!/usr/bin/env python3
"""Exact effect-light arrays through both frontends and real compiler artifacts."""
from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_generic_shader_float_array_index import SWIFT_SOURCES, REPOSITORY_ROOT

TOOLS = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools"
HARNESS = r'''
import Foundation

@main enum LightArrayChecks {
    static func decoded(_ artifact: SceneGenericShaderProgramArtifact) -> Bool {
        artifact.makeProgram(expectedKey: "light-arrays",
            expectedOutputSemantics: .preservedRGBAUnorm, expectedColorTransfer: .unresolved,
            expectedFragmentOutputChannelUse: .redDefined) != nil
    }
    static func main() throws {
        let mode = CommandLine.arguments[1]
        var output: [String: Any] = [:]
        if mode == "frontends" {
            let vertex = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
            let fragment = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
            let bounded = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: fragment)
            output["bounded"] = bounded.program != nil
            output["boundedDiagnostics"] = bounded.diagnostics.map { $0.code.rawValue }
            output["boundedMetal"] = bounded.program?.metalSource ?? ""
            output["boundedFields"] = bounded.program?.uniformLayout.fields.map {
                ["name": $0.name, "authoredName": $0.authoredName, "type": $0.type.rawValue,
                 "count": $0.arrayCount ?? 0, "bytes": $0.storageByteSize,
                 "stage": $0.stage?.rawValue ?? ""] as [String: Any]
            } ?? []
            switch SceneGenericShaderSourceNormalizer.normalize(vertexSource: vertex,
                fragmentSource: fragment, maximumStageSourceBytes: 100_000) {
            case let .success(pair):
                output["generic"] = true; output["vertex"] = pair.vertex; output["fragment"] = pair.fragment
            case let .failure(failure):
                output["generic"] = false; output["failure"] = String(describing: failure)
            }
        } else if mode == "build" {
            let rows = try JSONSerialization.jsonObject(with: Data(contentsOf:
                URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String: String]]
            let stages = rows.map { row in SceneGenericShaderArtifactBuilder.Stage(
                name: row["name"]!, source: row["source"]!, authoredSource: row["authoredSource"]!,
                msl: row["msl"]!, reflection: Data(row["reflection"]!.utf8)) }
            switch SceneGenericShaderArtifactBuilder.build(requestKey: "light-arrays",
                backendID: "glslang-spirv-cross-msl-v2", outputSemantics: .preservedRGBAUnorm,
                stages: stages, maximumArtifactBytes: 1_048_576) {
            case let .success(artifact):
                output["built"] = true; output["decoded"] = decoded(artifact)
                output["artifact"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(artifact))
            case let .failure(failure): output["built"] = false; output["failure"] = String(describing: failure)
            }
        } else {
            let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self,
                from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
            output["decoded"] = decoded(artifact)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneLightHostArrayFrontendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-light-array-frontends-")
        cls.root = Path(os.environ.get("MWX_LIGHT_ARRAY_EVIDENCE", cls.temporary.name))
        cls.root.mkdir(parents=True, exist_ok=True)
        cls.binary = cls.root / "light-array-frontends"
        harness = cls.root / "Harness.swift"
        harness.write_text(HARNESS)
        cls.identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SWIFT_SOURCES}
        result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-whole-module-optimization",
            *map(str, SWIFT_SOURCES), str(harness), "-module-cache-path", str(cls.root / "module-cache"),
            "-o", str(cls.binary)], capture_output=True, text=True)
        (cls.root / "compile.log").write_text(result.stdout + result.stderr)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SWIFT_SOURCES}
        (cls.root / "inputs.json").write_text(json.dumps({"before": cls.identities, "after": after,
            "unchanged": cls.identities == after}, indent=2) + "\n")
        cls.temporary.cleanup()
        if cls.identities != after:
            raise AssertionError("compiler input changed during light-array gate")

    def run_gate(self, *args: str) -> dict:
        result = subprocess.run([str(self.binary), *map(str, args)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def sources(self, name: str, component: str = "x", alpha: str = "w") -> tuple[str, str]:
        declarations = "uniform vec3 g_LightsPosition[4];\nuniform vec4 g_LightsColorPremultiplied[3];\n"
        vertex = declarations + """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_Light;
        void main() {
            float LOCAL = g_LightsPosition[0].COMPONENT;
            v_Light = vec2(LOCAL + g_LightsColorPremultiplied[0].ALPHA, a_TexCoord.y);
            gl_Position = vec4(a_Position, 1.0);
        }
        """.replace("LOCAL", name).replace("COMPONENT", component).replace("ALPHA", alpha)
        fragment = declarations + """
        varying vec2 v_Light;
        void main() {
            float LOCAL = g_LightsPosition[2].COMPONENT;
            gl_FragColor = vec4(LOCAL + g_LightsColorPremultiplied[1].ALPHA, v_Light.x, 0.0, 1.0);
        }
        """.replace("LOCAL", name).replace("COMPONENT", component).replace("ALPHA", alpha)
        return vertex, fragment

    def frontends(self, vertex: str, fragment: str, directory: Path) -> dict:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "authored.vert").write_text(vertex)
        (directory / "authored.frag").write_text(fragment)
        result = self.run_gate("frontends", directory / "authored.vert", directory / "authored.frag")
        (directory / "frontends.json").write_text(json.dumps(result, indent=2) + "\n")
        return result

    def compile_artifact(self, authored: tuple[str, str], normalized: dict, directory: Path) -> dict:
        self.assertTrue(normalized.get("generic"), normalized.get("failure"))
        stages = []
        for name, suffix, source in zip(("vertex", "fragment"), ("vert", "frag"), authored):
            path = directory / f"compiled.{suffix}"
            path.write_text(normalized[name])
            spirv = directory / f"{name}.spv"
            msl = directory / f"{name}.metal"
            reflection = directory / f"{name}.reflection.json"
            commands = [
                [str(TOOLS / "glslang"), "-V", "--auto-map-bindings", "--auto-map-locations",
                 "-S", suffix, "-e", "main", "-o", str(spirv), str(path)],
                [str(TOOLS / "spirv-cross"), str(spirv), "--msl", "--msl-version", "20000",
                 "--msl-decoration-binding", "--rename-entry-point", "main",
                 "mwxGenericVertex" if name == "vertex" else "mwxGenericFragment", suffix,
                 "--output", str(msl)],
                [str(TOOLS / "spirv-cross"), str(spirv), "--reflect", "--output", str(reflection)],
            ]
            for command in commands:
                run = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            stages.append({"name": name, "source": normalized[name], "authoredSource": source,
                           "msl": msl.read_text(), "reflection": reflection.read_text()})
        inputs = directory / "stages.json"
        inputs.write_text(json.dumps(stages))
        output = self.run_gate("build", inputs)
        (directory / "builder.json").write_text(json.dumps(output, indent=2) + "\n")
        self.assertTrue(output.get("built"), output)
        self.assertTrue(output["decoded"])
        return output["artifact"]

    def compile_metal(self, source: str, directory: Path, name: str) -> None:
        path = directory / f"{name}.metal"
        path.write_text(source)
        result = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-std=macos-metal2.3", "-c",
            str(path), "-o", str(directory / f"{name}.air")], capture_output=True, text=True)
        (directory / f"{name}-metal.log").write_text(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_frontends_reflection_stage_local_arrays_and_component_types(self) -> None:
        for name, component, alpha in [("distance", "x", "w"), ("renamedDistance", "r", "a")]:
            with self.subTest(name=name):
                directory = self.root / name
                source = self.sources(name, component, alpha)
                result = self.frontends(*source, directory)
                self.assertTrue(result["bounded"], result["boundedDiagnostics"])
                self.assertTrue(result["generic"], result.get("failure"))
                self.compile_metal(result["boundedMetal"], directory, "bounded")
                artifact = self.compile_artifact(source, result, directory)
                self.compile_metal(artifact["program"]["metalSource"], directory, "generic")
                arrays = [f for f in artifact["program"]["uniformLayout"]["fields"] if "arrayCount" in f]
                self.assertEqual(len(arrays), 4)
                for host, value_type, count, storage in [("g_LightsPosition", "float3", 4, 64),
                        ("g_LightsColorPremultiplied", "float4", 3, 48)]:
                    selected = [f for f in arrays if f["authoredName"] == host]
                    self.assertEqual({f["stage"] for f in selected}, {"vertex", "fragment"})
                    self.assertEqual({(f["type"], f["arrayCount"]) for f in selected}, {(value_type, count)})
                    self.assertEqual({f["name"] for f in selected}, {"mwxV_" + host, "mwxF_" + host})
                    for stage in ("vertex", "fragment"):
                        reflection = json.loads((directory / f"{stage}.reflection.json").read_text())
                        members = next(v["members"] for v in reflection["types"].values()
                            if any(m.get("name") == host for m in v.get("members", [])))
                        member = next(m for m in members if m["name"] == host)
                        self.assertEqual(member["array_stride"] * count, storage)

    def test_unknown_and_wrong_host_vector_array_shapes_fail_both_frontends(self) -> None:
        vertex, fragment = self.sources("distance")
        for name, find, replacement in [("renamed-host", "g_LightsPosition", "userLights"),
                ("wrong-type", "vec3 g_LightsPosition", "vec4 g_LightsPosition"),
                ("wrong-count", "g_LightsPosition[4]", "g_LightsPosition[3]"),
                ("wrong-color-count", "g_LightsColorPremultiplied[3]", "g_LightsColorPremultiplied[4]")]:
            with self.subTest(name=name):
                result = self.frontends(vertex.replace(find, replacement), fragment.replace(find, replacement),
                    self.root / name)
                self.assertFalse(result["bounded"])
                self.assertFalse(result["generic"])

    def test_actual_artifact_tampered_reserved_shape_and_count_fail_without_trap(self) -> None:
        source = self.sources("distance")
        directory = self.root / "tamper"
        artifact = self.compile_artifact(source, self.frontends(*source, directory), directory)
        fields = artifact["program"]["uniformLayout"]["fields"]
        index = next(i for i, f in enumerate(fields) if f.get("authoredName") == "g_LightsPosition")
        for name, changes in [("same-byte-wrong-type", {"type": "float4"}),
                ("scalar-type-bypass", {"type": "float"}), ("short-count", {"arrayCount": 3}),
                ("zero-count", {"arrayCount": 0}), ("negative-count", {"arrayCount": -1}),
                ("overflow-count", {"arrayCount": 9223372036854775807}),
                ("other-negative-count", {"authoredName": "legacyArray", "arrayCount": -1}),
                ("other-overflow-count", {"authoredName": "legacyArray", "arrayCount": 9223372036854775807}),
                ("offset-overflow", {"offset": 9223372036854775807})]:
            with self.subTest(name=name):
                modified = copy.deepcopy(artifact)
                modified["program"]["uniformLayout"]["fields"][index].update(changes)
                path = directory / f"{name}.json"
                path.write_text(json.dumps(modified))
                self.assertFalse(self.run_gate("decode", path)["decoded"])

    def test_existing_real_audio_float_array_artifact_roundtrips_and_compiles(self) -> None:
        declarations = "uniform vec3 g_LightsPosition[4];\nuniform vec4 g_LightsColorPremultiplied[3];\n"
        source = tuple(s.replace(declarations, "uniform float g_AudioSpectrum16Left[16];\n")
            .replace("g_LightsPosition[0].x", "g_AudioSpectrum16Left[0]")
            .replace("g_LightsPosition[2].x", "g_AudioSpectrum16Left[2]")
            .replace("g_LightsColorPremultiplied[0].w", "g_AudioSpectrum16Left[1]")
            .replace("g_LightsColorPremultiplied[1].w", "g_AudioSpectrum16Left[3]")
            for s in self.sources("legacyValue"))
        directory = self.root / "legacy-audio"
        normalized = self.frontends(*source, directory)
        self.assertTrue(normalized["bounded"], normalized["boundedDiagnostics"])
        artifact = self.compile_artifact(source, normalized, directory)
        self.compile_metal(artifact["program"]["metalSource"], directory, "legacy-audio")
        arrays = [f for f in artifact["program"]["uniformLayout"]["fields"] if "arrayCount" in f]
        self.assertEqual(len(arrays), 2)
        self.assertEqual({(f["authoredName"], f["type"], f["arrayCount"]) for f in arrays},
            {("g_AudioSpectrum16Left", "float", 16)})


if __name__ == "__main__":
    unittest.main()
