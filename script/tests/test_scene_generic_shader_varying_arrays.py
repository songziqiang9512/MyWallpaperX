#!/usr/bin/env python3
"""Fixed scalar varying arrays through maintained preparation and strict tools.

CPU methods reuse the existing frontend/preprocessor fixture without creating a
Metal device. The opt-in pixel method consumes their exact generated packet.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT))

from script.tests.test_scene_varying_value_parameter_prefix import (
    FIXTURE, GLSLANG, SWIFT_SOURCES,
)


def array_pair(count: int = 32, name: str = "carried", coordinate: str = "coordinate",
               parenthesized: bool = False, element: str = "float") -> dict[str, str]:
    value = "a_TexCoord.x * 0.5 + float(i) / 128.0"
    if parenthesized:
        value = "((float(i)) * (1.0 / 128.0)) + ((a_TexCoord.x) * 0.5)"
    if element != "float":
        value = f"{element}({value})"
    read = f"{name}[selected]"
    if element.startswith("vec"):
        read += ".x"
    elif element != "float":
        read = f"float({read})"
    return {
        "vertex": f"""attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 {coordinate};
varying {element} {name}[{count}];
void main() {{
    gl_Position = vec4(a_Position, 1.0);
    {coordinate} = a_TexCoord;
    for (int i = 0; i < {count}; i++) {{ {name}[i] = {value}; }}
}}
""",
        "fragment": f"""varying vec2 {coordinate};
varying {element} {name}[{count}];
void main() {{
    int selected = clamp(int(floor({coordinate}.y * {count}.0)), 0, {count - 1});
    gl_FragColor = vec4({read}, {coordinate}.x * 0.5,
                        {coordinate}.y, 1.0);
}}
""",
    }


def pixel_cases() -> list[tuple[str, dict[str, str]]]:
    return [
        ("scalar32", array_pair()),
        ("renamed-parenthesized", array_pair(
            name="frequencyCarrier", coordinate="rasterCoordinate", parenthesized=True
        )),
    ]


def expected_pixels() -> list[float]:
    # Independent arithmetic for the self-owned carrier at four pixel centers.
    return [component for y in (0.25, 0.75) for x in (0.25, 0.75)
            for component in (x * 0.5 + int(y * 32) / 128.0, x * 0.5, y, 1.0)]


def with_extra_interface(pair: dict[str, str], fields: list[tuple[str, str, int | None]],
                         stages: tuple[str, ...] = ("vertex", "fragment"),
                         read_fragment: bool = True) -> dict[str, str]:
    result = pair.copy()
    declarations, writes, reads = [], [], []
    for kind, name, count in fields:
        suffix = f"[{count}]" if count is not None else ""
        declarations.append(f"varying {kind} {name}{suffix};")
        target = f"{name}[0]" if count is not None else name
        writes.append(f"{target} = {kind}(0.125);")
        scalar = target + ("[0][0]" if kind.startswith("mat") else
                           ".x" if kind.startswith("vec") else "")
        reads.append(scalar)
    for stage in stages:
        result[stage] = "\n".join(declarations) + "\n" + result[stage]
        if stage == "vertex":
            result[stage] = result[stage].replace(
                "void main() {", "void main() {\n" + "\n".join(writes), 1
            )
        elif read_fragment:
            result[stage] = result[stage].replace(
                "1.0);", "1.0 + " + " + ".join(reads) + ");", 1
            )
    return result


class SceneGenericShaderVaryingArrayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = None
        if directory := os.environ.get("MWX_SCENE_VARYING_ARRAY_WORK"):
            cls.work = Path(directory).resolve()
            cls.work.mkdir(parents=True, exist_ok=True)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-varying-array-")
            cls.work = Path(cls.temporary.name)
        if binary := os.environ.get("MWX_SCENE_VARYING_ARRAY_HARNESS"):
            cls.binary = Path(binary).resolve()
            if not cls.binary.is_file():
                raise RuntimeError("requested maintained fixture binary is missing")
            return
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.binary = cls.work / "varying-array-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(cls.work / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(cls.work / "swift-cache")
        command = ["swiftc", "-parse-as-library", *(str(p) for p in SWIFT_SOURCES),
                   str(FIXTURE), "-o", str(cls.binary)]
        result = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
                                capture_output=True, text=True, timeout=120)
        (cls.work / "compile.stdout").write_text(result.stdout)
        (cls.work / "compile.stderr").write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

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
        return root, output

    def compile_generic(self, root: Path, output: dict) -> dict:
        self.assertNotIn("normalizerFailure", output)
        for suffix, field in (("vert", "normalizedVertex"), ("frag", "normalizedFragment")):
            (root / ("source." + suffix)).write_text(output[field])
        # Consume the exact two SPIR-V outputs produced by mandatory stage link.
        commands = [("link", [str(GLSLANG), "-V", "--auto-map-bindings",
                               "--auto-map-locations", "-l", "source.vert", "source.frag"])]
        for suffix, entry in (("vert", "arrayVertex"), ("frag", "arrayFragment")):
            commands.append((suffix + "-msl", [
                str(GLSLANG.with_name("spirv-cross")), suffix + ".spv", "--msl",
                "--msl-version", "20000", "--msl-decoration-binding",
                "--rename-entry-point", "main", entry, suffix,
                "--output", suffix + ".metal",
            ]))
        for phase, command in commands:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=30)
            (root / (phase + ".stdout")).write_text(result.stdout)
            (root / (phase + ".stderr")).write_text(result.stderr)
            self.assertEqual(result.returncode, 0, phase + result.stdout + result.stderr)
        return {"vertexMSL": (root / "vert.metal").read_text(),
                "fragmentMSL": (root / "frag.metal").read_text(),
                "vertexFunction": "arrayVertex", "fragmentFunction": "arrayFragment"}

    def test_fixed_scalar_arrays_reach_strict_generic_backend(self) -> None:
        for name, pair in [*pixel_cases(), ("scalar17", array_pair(17))]:
            with self.subTest(name=name):
                root, output = self.analyze(name, pair)
                self.assertIn("unsupportedType", output["boundedDiagnosticCodes"], name)
                packet = self.compile_generic(root, output)
                (root / "generic-pixels.json").write_text(json.dumps(packet, indent=2))
                if name != "scalar17":
                    (root / "expected.json").write_text(json.dumps(expected_pixels()))
        legacy = array_pair(4)
        legacy["fragment"] = """varying vec2 coordinate;
varying float carried[4];
void main() { gl_FragColor = vec4(carried[0], carried[3], coordinate.y, 1.0); }
"""
        root, output = self.analyze("legacy-literal-four", legacy)
        self.assertEqual(output["boundedDiagnosticCodes"], [])
        self.assertIn("boundedMSL", output)
        self.compile_generic(root, output)

    def test_interface_shape_and_component_budget_boundaries(self) -> None:
        exact = [("vec4", "padding", 16), ("vec3", "detail", 8), ("vec2", "edge", None)]
        # 32 scalar + 2 coordinate + 64 vector + 24 vector + 2 vector = 124.
        root, output = self.analyze("exact-124", with_extra_interface(array_pair(), exact))
        self.compile_generic(root, output)
        _, overflow = self.analyze("over-124", with_extra_interface(
            array_pair(), [*exact, ("float", "excess", None)]
        ))
        self.assertEqual(overflow.get("normalizerFailure"), "varyingUnsupported")
        _, vertex_overflow = self.analyze("vertex-budget-independent", with_extra_interface(
            array_pair(), [("vec4", "padding", 16), ("mat3", "basis", 3)],
            stages=("vertex",)
        ))
        self.assertEqual(vertex_overflow.get("normalizerFailure"), "varyingUnsupported")
        _, matrix_overflow = self.analyze("matrix-components", with_extra_interface(
            array_pair(), [("mat3", "basis", 11)]
        ))
        self.assertEqual(matrix_overflow.get("normalizerFailure"), "varyingUnsupported")
        root, dead = self.analyze("dead-fragment-not-retained", with_extra_interface(
            array_pair(), [("mat4", "unusedMatrices", 16)],
            stages=("fragment",), read_fragment=False
        ))
        self.assertNotIn("normalizerFailure", dead)
        self.compile_generic(root, dead)
        # The new component budget must not revoke the older <=16-array cohort.
        _, legacy = self.analyze("legacy-budget-unchanged", with_extra_interface(
            array_pair(16), [("vec4", "oldA", 16), ("vec4", "oldB", 16)]
        ))
        self.assertNotIn("normalizerFailure", legacy)

        mismatch = array_pair()
        mismatch["fragment"] = array_pair(31)["fragment"]
        type_mismatch = array_pair()
        type_mismatch["fragment"] = array_pair(16, element="vec4")["fragment"]
        absent_fragment = array_pair()
        absent_fragment["fragment"] = (
            "varying vec2 coordinate;\n"
            "void main(){gl_FragColor=vec4(coordinate,0.0,1.0);}\n"
        )
        absent_vertex = array_pair()
        absent_vertex["vertex"] = """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 coordinate;
void main(){gl_Position=vec4(a_Position,1.0);coordinate=a_TexCoord;}
"""
        cases = {
            "different-count": mismatch,
            "different-element-type": type_mismatch,
            "no-retained-fragment-pair": absent_fragment,
            "missing-vertex-pair": absent_vertex,
            "scalar33": array_pair(33),
            "vector17": array_pair(17, element="vec2"),
            "integer32": array_pair(32, element="int"),
            "boolean32": array_pair(32, element="bool"),
            "unknown32": array_pair(32, element="Unknown"),
            "zero-count": array_pair(0),
        }
        huge = array_pair()
        huge = {stage: text.replace("carried[32];", "carried[9223372036854775807];")
                for stage, text in huge.items()}
        cases["huge-count"] = huge
        nested = array_pair()
        nested["fragment"] = nested["fragment"].replace("carried[32];", "carried[32][2];")
        cases["two-dimensional"] = nested
        other_failures = {
            "missing-vertex-pair": "stageLinkMismatch",
            "huge-count": "arrayUnsupported",
            "zero-count": "arrayUnsupported",
            "two-dimensional": "declarationUnsupported",
        }
        for name, pair in cases.items():
            with self.subTest(name=name):
                _, output = self.analyze(name, pair)
                self.assertEqual(output.get("normalizerFailure"),
                                 other_failures.get(name, "varyingUnsupported"), name)

    def test_original_contract_uses_maintained_preparation_and_strict_tools(self) -> None:
        if not (path := os.environ.get("MWX_SCENE_VARYING_ARRAY_ACTUAL_CONTRACT")):
            self.skipTest("actual contract qualification requires an explicit frozen input")
        source = Path(path).resolve()
        data = json.loads(source.read_text())
        for stage in data["contract"]["stages"]:
            self.assertEqual(hashlib.sha256(stage["source"].encode()).hexdigest(),
                             stage["rawSHA256"])
        root = self.work / "actual-contract"
        root.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(self.binary), "--actual-contract", str(source)],
                                capture_output=True, text=True, timeout=30)
        (root / "analysis.stdout").write_text(result.stdout)
        (root / "analysis.stderr").write_text(result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = json.loads(result.stdout)
        (root / "analysis.json").write_text(json.dumps(output, indent=2))
        self.assertEqual(output["stage"], "actual-contract-variant-preprocessor-before-shared-proof")
        self.assertIn("unsupportedType", output["boundedDiagnosticCodes"])
        self.compile_generic(root, output)
        manifest = {"input": str(source), "inputSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
                    "identity": data["contract"]["identity"],
                    "materialCombos": data["materialCombos"],
                    "textureReadiness": data.get("textureReadiness"),
                    "phase": output["stage"], "MetalOrAppExecuted": False}
        (root / "result.json").write_text(json.dumps(manifest, indent=2))

    @unittest.skipUnless(os.environ.get("MWX_SCENE_VARYING_ARRAY_GPU") == "1",
                         "exact Metal readback is explicitly enabled by its GPU owner")
    def test_metal_dynamic_index_and_interpolation(self) -> None:
        for name, _ in pixel_cases():
            root = self.work / "cases" / name
            packet = root / "generic-pixels.json"
            self.assertTrue(packet.is_file(), "run the CPU preparation on this work directory first")
            result = subprocess.run([str(self.binary), "--render", str(packet)],
                                    capture_output=True, text=True, timeout=30)
            (root / "pixels.stdout").write_text(result.stdout)
            (root / "pixels.stderr").write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            observed = json.loads(result.stdout)
            expected = json.loads((root / "expected.json").read_text())
            self.assertEqual(len(observed), len(expected))
            for actual, reference in zip(observed, expected):
                self.assertAlmostEqual(actual, reference, delta=1e-6, msg=name)


if __name__ == "__main__":
    unittest.main()
