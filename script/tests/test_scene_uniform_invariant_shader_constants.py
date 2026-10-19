#!/usr/bin/env python3
"""Direct-uniform readonly globals through the real generic compiler route.

CPU methods never create a Metal device. The optional exact-pixel method reuses
their generated MSL and the same fixture/PSO for an A/B/A uniform sequence.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT))

from script.tests.test_scene_varying_value_parameter_prefix import (
    FIXTURE, GLSLANG, SWIFT_SOURCES as PREFIX_SOURCES, vertex_source,
)
from script.scene_swift_source_sets import scene_swift_sources

RUNTIME_SOURCES = [
    path for path in scene_swift_sources("generic_shader_compiler_preparation_implementation")
    if path.name == "SceneGenericShaderRuntimeConstantNormalizer.swift"
]
SWIFT_SOURCES = list(dict.fromkeys([*PREFIX_SOURCES, *RUNTIME_SOURCES]))
GPU_ENABLED = os.environ.get("MWX_SCENE_UNIFORM_CONSTANTS_GPU") == "1"


def shader_cases() -> list[dict]:
    result = []
    for name, drive, gain, vector, scalar, coordinate, parenthesized in (
        ("direct-uniform", "u_drive", "u_gain", "derivedUV", "derivedLevel", "coordinate", False),
        ("renamed-parenthesized", "u_control", "u_multiplier", "shifted", "brightness", "renamedUV", True),
    ):
        vector_rhs = f"{drive}.xy * vec2({gain}, 0.5) + vec2(0.125)"
        scalar_rhs = f"{drive}.z * {gain} + 0.0625"
        if parenthesized:
            vector_rhs = f"(({drive}.xy) * (vec2(({gain}), 0.5))) + (vec2(0.125))"
            scalar_rhs = f"(({drive}.z) * ({gain})) + (0.0625)"
        declarations = f"const vec2 {vector} = {vector_rhs};\nconst float {scalar} = {scalar_rhs};"
        helpers = (f"vec2 readCurrentUV(){{return (({vector}));}}\n"
                   f"float readCurrentLevel(){{return (({scalar}));}}\n") if parenthesized else ""
        vector_use, scalar_use = ("readCurrentUV()", "readCurrentLevel()") if parenthesized else (vector, scalar)
        fragment = f"""uniform vec4 {drive};
uniform float {gain};
varying vec2 {coordinate};
{declarations}
{helpers}
void main() {{
    gl_FragColor = vec4({vector_use} + {coordinate} * 0.25, {scalar_use}, {drive}.w);
}}
"""
        result.append({
            "name": name,
            "pair": {"vertex": vertex_source(coordinate, width=2), "fragment": fragment},
            "drive": drive, "gain": gain, "vector": vector, "scalar": scalar,
            "initializers": [vector_rhs, scalar_rhs],
        })
    return result


def expected_pixels(drive: list[float], gain: float) -> list[float]:
    # Independent arithmetic for this self-owned shader, not a product lowering.
    base_x, base_y = drive[0] * gain + 0.125, drive[1] * 0.5 + 0.125
    level = drive[2] * gain + 0.0625
    return [component for y in (0.25, 0.75) for x in (0.25, 0.75)
            for component in (base_x + x * 0.25, base_y + y * 0.25, level, drive[3])]


def packed_uniform_buffer(reflection: dict, msl: str, values: dict[str, list[float]]) -> dict | None:
    blocks = [item for item in reflection.get("ubos", []) if item.get("name") == "MWXUniforms"]
    if len(blocks) != 1:
        raise AssertionError(f"expected one reflected MWXUniforms block: {blocks}")
    block = blocks[0]
    definition = reflection["types"][block["type"]]
    storage = bytearray((block["block_size"] + 3) // 4 * 4)
    names = set()
    for member in definition["members"]:
        name = member["name"]
        if name not in values:
            raise AssertionError(f"unbound reflected member: {name}")
        names.add(name)
        components = values[name]
        width = {"float": 1, "vec2": 2, "vec3": 3, "vec4": 4}.get(member["type"])
        if width != len(components):
            raise AssertionError(f"unexpected uniform type/width: {member}")
        struct.pack_into("<" + "f" * width, storage, member["offset"], *components)
    if names != set(values):
        raise AssertionError(f"unused packet values: {set(values) - names}")
    indices = re.findall(r"constant\s+MWXUniforms\s*&\s*\w+\s*\[\[buffer\((\d+)\)\]\]", msl)
    # SPIRV-Cross can retain the SPIR-V block in reflection yet omit an unused
    # block from the actual vertex entry. Bind only the emitted MSL parameter.
    if not indices and "[[buffer(" not in msl and "constant MWXUniforms&" not in msl:
        return None
    if len(indices) != 1:
        raise AssertionError(f"expected exact MSL UBO parameter: {indices}")
    return {"index": int(indices[0]), "values": list(struct.unpack("<" + "f" * (len(storage) // 4), storage))}


class SceneUniformInvariantShaderConstantsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = None
        if directory := os.environ.get("MWX_SCENE_UNIFORM_CONSTANTS_WORK"):
            cls.work = Path(directory).resolve()
            cls.work.mkdir(parents=True, exist_ok=True)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-uniform-constants-")
            cls.work = Path(cls.temporary.name)
        if binary := os.environ.get("MWX_SCENE_UNIFORM_CONSTANTS_HARNESS"):
            cls.binary = Path(binary).resolve()
            if not cls.binary.is_file():
                raise RuntimeError("requested compiled fixture is missing")
            return
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        if len(RUNTIME_SOURCES) != 1:
            raise RuntimeError("runtime constant normalizer must be registered in its production source set")
        cls.binary = cls.work / "uniform-constants-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(cls.work / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(cls.work / "swift-cache")
        command = ["swiftc", "-parse-as-library", *(str(p) for p in SWIFT_SOURCES),
                   str(FIXTURE), "-o", str(cls.binary)]
        completed = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
                                   capture_output=True, text=True, timeout=120)
        (cls.work / "compile.stdout").write_text(completed.stdout)
        (cls.work / "compile.stderr").write_text(completed.stderr)
        if completed.returncode:
            raise RuntimeError(completed.stdout + completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.temporary is not None:
            cls.temporary.cleanup()

    def analyze(self, name: str, pair: dict[str, str]) -> tuple[Path, dict]:
        root = self.work / "cases" / name
        root.mkdir(parents=True, exist_ok=True)
        path = root / "input.json"
        path.write_text(json.dumps(pair, indent=2))
        result = subprocess.run([str(self.binary), "--analyze", str(path)],
                                capture_output=True, text=True, timeout=30)
        (root / "analysis.stdout").write_text(result.stdout)
        (root / "analysis.stderr").write_text(result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = json.loads(result.stdout)
        (root / "analysis.json").write_text(json.dumps(output, indent=2))
        self.assertTrue(output["idempotent"], name)
        self.assertTrue(output["runtimeConstantIdempotent"], name)
        return root, output

    def compile_generic(self, root: Path, output: dict) -> dict[str, str]:
        self.assertNotIn("normalizerFailure", output)
        for suffix, field in (("vert", "normalizedVertex"), ("frag", "normalizedFragment")):
            (root / ("source." + suffix)).write_text(output[field])
        commands = [("link", [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                               "-l", "source.vert", "source.frag"])]
        for suffix, entry in (("vert", "constantVertex"), ("frag", "constantFragment")):
            commands += [
                (suffix + "-spv", [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                                    "source." + suffix, "-o", suffix + ".spv"]),
                (suffix + "-msl", [str(GLSLANG.with_name("spirv-cross")), suffix + ".spv", "--msl",
                                    "--rename-entry-point", "main", entry, suffix,
                                    "--output", suffix + ".metal"]),
                (suffix + "-reflect", [str(GLSLANG.with_name("spirv-cross")), suffix + ".spv", "--reflect"]),
            ]
        for phase, command in commands:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=30)
            (root / (phase + ".stdout")).write_text(result.stdout)
            (root / (phase + ".stderr")).write_text(result.stderr)
            self.assertEqual(result.returncode, 0, phase + result.stdout + result.stderr)
        return {"vertexMSL": (root / "vert.metal").read_text(),
                "fragmentMSL": (root / "frag.metal").read_text(),
                "vertexFunction": "constantVertex", "fragmentFunction": "constantFragment"}

    def prepare_case(self, case: dict) -> Path:
        root, output = self.analyze(case["name"], case["pair"])
        original = case["pair"]["fragment"]
        rewritten = output["runtimeConstantFragment"]
        self.assertEqual(re.sub(r"\s+", "", rewritten),
                         re.sub(r"\s+", "", re.sub(r"\bconst\b", "", original)))
        for initializer in case["initializers"]:
            self.assertIn(initializer, rewritten)
        self.assertEqual(output["runtimeConstantVertex"], case["pair"]["vertex"])
        packet = self.compile_generic(root, output)
        fragment = packet["fragmentMSL"]
        entry = fragment.index("fragment constantFragment_out constantFragment(")
        for kind, name in (("float2", case["vector"]), ("float", case["scalar"])):
            declarations = list(re.finditer(r"\b" + kind + r"\s+" + name + r"\s*=", fragment))
            self.assertEqual(len(declarations), 1, name + " must initialize once per entry")
            self.assertGreater(declarations[0].start(), entry, name + " must be entry-private")
        variants = [([0.25, 0.5, 0.75, 0.5], 0.5), ([0.75, 0.25, 0.5, 0.75], 0.25)]
        draws, expected = [], []
        for drive, gain in (variants[0], variants[1], variants[0]):
            values = {case["drive"]: drive, case["gain"]: [gain], "mwxRenderSize": [2.0, 2.0]}
            buffers = {}
            for suffix, msl in (("vert", packet["vertexMSL"]), ("frag", fragment)):
                reflection = json.loads((root / (suffix + "-reflect.stdout")).read_text())
                buffers[suffix] = packed_uniform_buffer(reflection, msl, values)
            self.assertIsNotNone(buffers["frag"], "derived values must read the emitted fragment UBO")
            draws.append({"vertexBuffers": [buffers["vert"]] if buffers["vert"] else [],
                          "fragmentBuffers": [buffers["frag"]]})
            expected.append(expected_pixels(drive, gain))
        sequence = {"program": packet, "draws": draws}
        (root / "generic-uniform-sequence.json").write_text(json.dumps(sequence, indent=2))
        (root / "expected.json").write_text(json.dumps(expected, indent=2))
        (root / "packet-identity.json").write_text(json.dumps({
            "inputSHA256": hashlib.sha256((root / "input.json").read_bytes()).hexdigest(),
            "sequenceSHA256": hashlib.sha256((root / "generic-uniform-sequence.json").read_bytes()).hexdigest(),
            "uniformOrder": "A/B/A; same compiled program, different reflected buffer values",
            "readback": "pending separate explicit GPU method",
        }, indent=2))
        return root

    def test_direct_uniform_readonly_globals_compile_and_prepare_value_packets(self) -> None:
        for case in shader_cases():
            with self.subTest(name=case["name"]):
                self.prepare_case(case)

    def test_unproved_bindings_consumers_and_constant_uses_are_unchanged(self) -> None:
        cases = {
            "whole-write": "const float k=u_gain;\nvoid main(){k=0.5;gl_FragColor=vec4(k);}",
            "compound-write": "const float k=u_gain;\nvoid main(){k+=0.5;gl_FragColor=vec4(k);}",
            "component-write": "const vec2 k=u_drive.xy;\nvoid main(){k.x=0.5;gl_FragColor=vec4(k,0.0,1.0);}",
            "post-increment": "const float k=u_gain;\nvoid main(){k++;gl_FragColor=vec4(k);}",
            "inout": "const float k=u_gain;\nfloat touch(inout float x){x+=0.5;return x;}\nvoid main(){gl_FragColor=vec4(touch(k));}",
            "out": "const float k=u_gain;\nfloat touch(out float x){x=0.5;return x;}\nvoid main(){gl_FragColor=vec4(touch(k));}",
            "unknown-consumer": "const float k=u_gain;\nvoid main(){gl_FragColor=vec4(unknown(k));}",
            "unknown-rhs": "const float k=unknown(u_gain);\nvoid main(){gl_FragColor=vec4(k);}",
            "source-helper-rhs": "float derive(float x){return x*0.5;}\nconst float k=derive(u_gain);\nvoid main(){gl_FragColor=vec4(k);}",
            "local-shadow": "const float k=u_gain;\nvoid main(){float k=0.5;gl_FragColor=vec4(k);}",
            "formal-shadow": "const float k=u_gain;\nfloat consume(float k){return k;}\nvoid main(){gl_FragColor=vec4(consume(k));}",
            "uniform-shadow": "const float k=u_gain;\nfloat consume(float u_gain){return u_gain;}\nvoid main(){gl_FragColor=vec4(k);}",
            "constructor-shadow": "vec2 vec2(float x){return u_drive.xy;}\nconst vec2 k=vec2(u_gain);\nvoid main(){gl_FragColor=vec4(k,0.0,1.0);}",
            "array-global": "const vec2 k[2]=vec2[2](u_drive.xy,u_drive.zw);\nvoid main(){gl_FragColor=vec4(k[0],0.0,1.0);}",
            "uniform-array": "uniform float u_values[2];\nconst float k=u_values[0];\nvoid main(){gl_FragColor=vec4(k);}",
            "compiletime-array-size": "const float k=u_gain;\nvoid main(){float values[int(k)];gl_FragColor=vec4(k);}",
            "derived-global-chain": "const float k=u_gain;\nconst float next=k*0.5;\nvoid main(){gl_FragColor=vec4(next);}",
            "varying-rhs": "const vec2 k=coordinate;\nvoid main(){gl_FragColor=vec4(k,0.0,1.0);}",
            "sample-rhs": "uniform sampler2D g_Texture0;\nconst vec2 k=texSample2D(g_Texture0,vec2(0.5)).xy;\nvoid main(){gl_FragColor=vec4(k,0.0,1.0);}",
            "invocation-rhs": "const vec2 k=gl_FragCoord.xy;\nvoid main(){gl_FragColor=vec4(k,0.0,1.0);}",
            "int-global": "const int k=int(u_gain);\nvoid main(){gl_FragColor=vec4(float(k));}",
            "bool-global": "const bool k=u_gain>0.0;\nvoid main(){gl_FragColor=vec4(float(k));}",
            "matrix-global": "const mat2 k=mat2(u_gain);\nvoid main(){gl_FragColor=vec4(k[0],0.0,1.0);}",
            "mutable-global": "float k=u_gain;\nvoid main(){gl_FragColor=vec4(k);}",
            "compiletime-constant": "const vec2 k=vec2(0.25,0.5);\nvoid main(){gl_FragColor=vec4(k,0.0,1.0);}",
        }
        for name, body in cases.items():
            fragment = "uniform vec4 u_drive;\nuniform float u_gain;\nvarying vec2 coordinate;\n" + body
            with self.subTest(name=name):
                root, output = self.analyze(name, {"vertex": vertex_source("coordinate", width=2),
                                                 "fragment": fragment})
                self.assertEqual(output["runtimeConstantFragment"], output["canonicalFragment"])
                if name in ("mutable-global", "compiletime-constant"):
                    self.compile_generic(root, output)

    def test_dynamic_loop_keeps_type_preparation_without_bounded_execution(self) -> None:
        fragment = """uniform float u_count;
varying vec2 coordinate;
const float distanceStep = u_count * 0.125;
vec2 offsetCopy(vec2 point, float amount) {
    vec2 delta = 0.0, midpoint = vec2(0.5);
    delta = point * amount + midpoint;
    return delta;
}
void main() {
    vec2 total = 0.0;
    for (int i=0; i<int(u_count); ++i) { total += offsetCopy(coordinate, distanceStep); }
    gl_FragColor = vec4(total, 0.0, 1.0);
}
"""
        root, output = self.analyze("uniform-loop-broadcast", {
            "vertex": vertex_source("coordinate", width=2), "fragment": fragment,
        })
        self.assertIn("dynamicLoop", output["boundedDiagnosticCodes"])
        self.assertNotIn("boundedMSL", output)
        self.assertNotIn("const float distanceStep", output["runtimeConstantFragment"])
        for pattern in (r"vec2\s+delta\s*=\s*vec2\(0\.0\)", r"vec2\s+total\s*=\s*vec2\(0\.0\)"):
            self.assertRegex(output["normalizedFragment"], pattern)
        self.compile_generic(root, output)

    @unittest.skipUnless(GPU_ENABLED, "Metal readback is an explicit separately authorized gate")
    def test_uniform_inputs_reinitialize_same_program_for_each_draw(self) -> None:
        for case in shader_cases():
            root = self.work / "cases" / case["name"]
            packet = root / "generic-uniform-sequence.json"
            self.assertTrue(packet.is_file(), "prepare the CPU packet using this exact compiled fixture first")
            result = subprocess.run([str(self.binary), "--render-uniform-sequence", str(packet)],
                                    capture_output=True, text=True, timeout=30)
            (root / "gpu.stdout").write_text(result.stdout)
            (root / "gpu.stderr").write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            observed = json.loads(result.stdout)
            expected = json.loads((root / "expected.json").read_text())
            self.assertEqual(len(observed), 3)
            for index, (actual, target) in enumerate(zip(observed, expected)):
                with self.subTest(name=case["name"], draw=index):
                    self.assertEqual(len(actual), len(target))
                    for left, right in zip(actual, target):
                        self.assertAlmostEqual(left, right, places=6)
            self.assertEqual(observed[0], observed[2], "A/B/A must return to A without retained state")
            self.assertNotEqual(observed[0], observed[1], "the changed uniforms must affect this draw")


if __name__ == "__main__":
    unittest.main()
