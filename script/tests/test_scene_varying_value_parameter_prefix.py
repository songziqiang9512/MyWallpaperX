#!/usr/bin/env python3
"""Value-only helper arguments across the shared floating-varying prefix proof.

CPU methods never create a Metal device. The separate pixel method consumes
both real backend outputs using the same compiled fixture.
"""
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
sys.path.insert(0, str(REPOSITORY_ROOT))

from script.tests.test_scene_shader_scalar_vector_builtin_canonicalization import (
    GLSLANG, SWIFT_SOURCES as CANONICALIZER_SOURCES,
)
from script.tests.test_scene_shader_preprocessor import SWIFT_SOURCES as PREPROCESSOR_SOURCES

FIXTURE = Path(__file__).with_name("fixtures") / "SceneVaryingValueParameterPrefixHarness.swift"
SWIFT_SOURCES = list(dict.fromkeys([
    *CANONICALIZER_SOURCES,
    *PREPROCESSOR_SOURCES,
]))
EXPECTED_COPY_PIXELS = [
    0.25, 0.25, 0.25, 1.0, 0.5, 0.25, 0.75, 1.0,
    0.25, 0.5, 0.25, 1.0, 0.5, 0.5, 0.75, 1.0,
]


def vertex_source(name: str = "carried", width: int = 4, assignment: str | None = None) -> str:
    if assignment is None:
        assignment = f"{name}.xy = a_TexCoord;" if width == 4 else f"{name} = a_TexCoord;"
    return f"""
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec{width} {name};
void main() {{ gl_Position = vec4(a_Position, 1.0); {assignment} }}
"""


def copy_cases() -> list[tuple[str, dict[str, str]]]:
    result = []
    for name, helper, carrier, qualifier, reordered, argument in (
        ("default-value", "shiftLocal", "carried", "", False, "carried"),
        ("renamed-explicit-in", "bendLocal", "renamedCoordinate", "in ", False, "((renamedCoordinate))"),
        ("second-value-argument", "offsetCopy", "alternateLink", "", True, "(alternateLink.xy)"),
    ):
        parameters = f"{qualifier}vec2 copied, float offset"
        arguments = f"{argument}, 0.125"
        if reordered:
            parameters, arguments = "float offset, vec2 copied", f"0.125, {argument}"
        local = "sampleCoordinate" if name == "renamed-explicit-in" else "copied"
        parameters = parameters.replace("copied", local)
        fragment = f"""
varying vec2 {carrier};
vec2 {helper}({parameters}) {{
    {local}.x = {local}.x * 0.5 + offset;
    {local}.y = {local}.y * 0.5 + 0.125;
    return {local};
}}
void main() {{
    vec2 changed = {helper}({arguments});
    gl_FragColor = vec4(changed, {carrier}.x, 1.0);
}}
"""
        result.append((name, {"vertex": vertex_source(carrier), "fragment": fragment}))
    return result


class SceneVaryingValueParameterPrefixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-varying-value-prefix-")
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / "prefix-harness"
        env = os.environ.copy()
        env["CLANG_MODULE_CACHE_PATH"] = str(cls.work / "clang-cache")
        env["SWIFT_MODULECACHE_PATH"] = str(cls.work / "swift-cache")
        command = ["swiftc", "-parse-as-library", *(str(p) for p in SWIFT_SOURCES),
                   str(FIXTURE), "-o", str(cls.binary)]
        completed = subprocess.run(command, cwd=REPOSITORY_ROOT, env=env,
                                   capture_output=True, text=True, timeout=120)
        (cls.work / "compile.stdout").write_text(completed.stdout)
        (cls.work / "compile.stderr").write_text(completed.stderr)
        if completed.returncode:
            raise RuntimeError(completed.stdout + completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def analyze(self, name: str, pair: dict[str, str]) -> tuple[Path, dict]:
        root = self.work / "cases" / name
        root.mkdir(parents=True, exist_ok=True)
        path = root / "input.json"
        path.write_text(json.dumps(pair, indent=2))
        output = json.loads(subprocess.check_output(
            [str(self.binary), "--analyze", str(path)], text=True, timeout=30,
        ))
        (root / "analysis.json").write_text(json.dumps(output, indent=2))
        return root, output

    def prepare(self, name: str, pair: dict[str, str], expected: list[float] | None = None) -> Path:
        root, output = self.analyze(name, pair)
        self.assertTrue(output["idempotent"])
        self.assertEqual(output["boundedDiagnosticCodes"], [], name)
        self.assertNotIn("normalizerFailure", output, name)
        self.assertIn("boundedMSL", output, name)
        for suffix, field in (("vert", "normalizedVertex"), ("frag", "normalizedFragment")):
            (root / ("source." + suffix)).write_text(output[field])
        commands = [[str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     "-l", "source.vert", "source.frag"]]
        for suffix, entry, stage in (("vert", "probeVertex", "vert"), ("frag", "probeFragment", "frag")):
            commands += [
                [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                 "source." + suffix, "-o", suffix + ".spv"],
                [str(GLSLANG.with_name("spirv-cross")), suffix + ".spv", "--msl",
                 "--rename-entry-point", "main", entry, stage, "--output", suffix + ".metal"],
            ]
        for command in commands:
            completed = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=30)
            self.assertEqual(completed.returncode, 0, name + completed.stdout + completed.stderr)
        packets = {
            "generic": {"vertexMSL": (root / "vert.metal").read_text(),
                        "fragmentMSL": (root / "frag.metal").read_text(),
                        "vertexFunction": "probeVertex", "fragmentFunction": "probeFragment"},
            "bounded": {"vertexMSL": output["boundedMSL"], "fragmentMSL": output["boundedMSL"],
                        "vertexFunction": output["boundedVertexFunction"],
                        "fragmentFunction": output["boundedFragmentFunction"]},
        }
        for backend, packet in packets.items():
            (root / (backend + "-pixels.json")).write_text(json.dumps(packet, indent=2))
        if expected is not None:
            (root / "expected.json").write_text(json.dumps(expected))
        return root

    def test_coordinate_value_copy_reaches_both_backend_routes(self) -> None:
        for name, pair in copy_cases():
            with self.subTest(name=name):
                self.prepare(name, pair, EXPECTED_COPY_PIXELS)

    def test_aliases_escapes_and_unproven_parameters_stay_rejected(self) -> None:
        cases = {
            "inout": ("vec2 move(inout vec2 p,float n){p.x+=n;return p;}", "move(carried,0.125)"),
            "out": ("vec2 move(out vec2 p,float n){p=vec2(n);return p;}", "move(carried,0.125)"),
            "array": ("vec2 move(vec2 p[2],float n){return p[0];}", "move(carried,0.125)"),
            "unknown-formal": ("vec2 move(Unknown p,float n){return vec2(n);}", "move(carried,0.125)"),
            "prototype": ("vec2 move(vec2 p,float n);", "move(carried,0.125)"),
            "unknown-call": ("", "unknown(carried)"),
            "overload": ("vec2 move(vec2 p,float n){return p;} vec2 move(vec3 p,float n){return p.xy;}", "move(carried,0.125)"),
            "wrong-width": ("vec2 move(vec3 p,float n){return p.xy;}", "move(carried,0.125)"),
            "unsafe-outer": ("vec2 move(vec2 p,float n){p.x+=n;return p;}", "unknown(move(carried,0.125))"),
            "global-varying-write": ("vec2 move(vec2 p,float n){carried.xy=vec2(n);return p;}", "move(carried,0.125)"),
            "shadowed-varying-formal": ("vec2 move(vec2 carried,float n){carried.x+=n;return carried;}", "move(carried,0.125)"),
            "callable-shadow": ("vec2 move(vec2 p,float n){return p;}", "move(carried,0.125)"),
            "unwritten-suffix-to-helper": ("vec2 move(vec2 p,float n){return p;}", "move(carried.zw,0.125)"),
            "mutating-actual": ("vec2 move(vec2 p,float n){return p;}", "move((carried.xy+=vec2(0.125)),0.125)"),
        }
        for name, (helper, call) in cases.items():
            main = "float move=1.0;" if name == "callable-shadow" else ""
            fragment = ("varying vec2 carried;\n" + helper + "\nvoid main(){" + main
                        + "vec2 original=carried.xy;gl_FragColor=vec4(" + call + ",original.x,1.0);}")
            with self.subTest(name=name):
                _, output = self.analyze(name, {"vertex": vertex_source(), "fragment": fragment})
                self.assertNotIn("boundedMSL", output, name)
                self.assertIn("normalizerFailure", output, name)
        safe_fragment = copy_cases()[0][1]["fragment"]
        for name, assignment in (
            ("unwritten", ""),
            ("partially-unwritten-helper-prefix", "carried.x=a_TexCoord.x;"),
            ("conditional-write", "if(a_TexCoord.x>0.0){carried.xy=a_TexCoord;}"),
            ("repeated-write", "carried.xy=a_TexCoord;carried.xy=vec2(0.0);"),
        ):
            with self.subTest(name=name):
                _, output = self.analyze(name, {"vertex": vertex_source(assignment=assignment),
                                               "fragment": safe_fragment})
                self.assertNotIn("boundedMSL", output, name)
                self.assertIn("normalizerFailure", output, name)
        reverse_fragment = ("varying vec4 carried;\nvec2 move(vec2 p){return p;}\n"
                            "void main(){gl_FragColor=vec4(move(carried.xy),0.0,1.0);}")
        _, output = self.analyze("fragment-wider-helper", {
            "vertex": vertex_source(width=2), "fragment": reverse_fragment,
        })
        self.assertNotIn("boundedMSL", output)
        self.assertIn("normalizerFailure", output)

    def test_existing_direct_reverse_and_zero_fill_paths_stay_healthy(self) -> None:
        for name, vertex, fragment in (
            ("direct-prefix", vertex_source(), "varying vec2 carried;\nvoid main(){gl_FragColor=vec4(carried.xy,0.0,1.0);}"),
            ("reverse-direct-prefix", vertex_source(width=2), "varying vec4 carried;\nvoid main(){gl_FragColor=vec4(carried.xy,0.0,1.0);}"),
            ("existing-partial-prefix-zero-fill", vertex_source(assignment="carried.x=a_TexCoord.x;"), "varying vec2 carried;\nvoid main(){gl_FragColor=vec4(carried.xy,0.0,1.0);}"),
            ("existing-zero-fill", vertex_source(), "varying vec2 carried;\nvoid main(){gl_FragColor=vec4(carried.xy,carried.z,1.0);}"),
        ):
            with self.subTest(name=name):
                self.prepare(name, {"vertex": vertex, "fragment": fragment})

    def test_coordinate_value_copy_exact_pixels(self) -> None:
        for name, pair in copy_cases():
            root = self.prepare(name, pair, EXPECTED_COPY_PIXELS)
            for backend in ("generic", "bounded"):
                with self.subTest(name=name, backend=backend):
                    pixels = json.loads(subprocess.check_output(
                        [str(self.binary), "--render", str(root / (backend + "-pixels.json"))],
                        text=True, timeout=30,
                    ))
                    self.assertEqual(len(pixels), len(EXPECTED_COPY_PIXELS))
                    for actual, expected in zip(pixels, EXPECTED_COPY_PIXELS):
                        self.assertAlmostEqual(actual, expected, places=6)


if __name__ == "__main__":
    unittest.main()
