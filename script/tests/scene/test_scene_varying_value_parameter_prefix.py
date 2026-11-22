#!/usr/bin/env python3
"""Value-only arguments, varying prefixes, and omitted fragment inputs.

CPU methods never create a Metal device. The separate pixel method consumes
both real backend outputs using the same compiled fixture. Explicit WORK and
HARNESS paths retain CPU packets for a separate GPU invocation; GPU=0 disables
readback while the default still runs the existing pixel checks.
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

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT))

from script.tests.scene.test_scene_shader_scalar_vector_builtin_canonicalization import (
    GLSLANG, SWIFT_SOURCES as CANONICALIZER_SOURCES,
)
from script.tests.scene.test_scene_shader_preprocessor import SWIFT_SOURCES as PREPROCESSOR_SOURCES

FIXTURE = (Path(__file__).resolve().parents[1] / "fixtures") / "SceneVaryingValueParameterPrefixHarness.swift"
SWIFT_SOURCES = list(dict.fromkeys([
    *CANONICALIZER_SOURCES,
    *PREPROCESSOR_SOURCES,
    *(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract" / name
      for name in ("SceneBuiltinShaderIdentity.swift", "SceneShaderContractLoader.swift",
                   "SceneShaderContractLoader+SourceGraph.swift")),
]))
GPU_ENABLED = os.environ.get("MWX_SCENE_VARYING_PREFIX_GPU", "1") == "1"
EXPECTED_COPY_PIXELS = [
    0.25, 0.25, 0.25, 1.0, 0.5, 0.25, 0.75, 1.0,
    0.25, 0.5, 0.25, 1.0, 0.5, 0.5, 0.75, 1.0,
]
PHASE_TEXTURE = [
    1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0,
    0.0, 0.0, 1.0, 1.0, 0.25, 0.5, 0.75, 1.0,
]
# A half-width phase swaps the two texels in each row; copy/zero UV cannot pass.
EXPECTED_PHASE_PIXELS = [
    0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0,
    0.25, 0.5, 0.75, 1.0, 0.0, 0.0, 1.0, 1.0,
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


def reverse_grouped_cases() -> list[dict]:
    result = []
    for name, carrier, expression, operation in (
        ("reverse-grouped-base", "carried", "(carried).xy", "xy"),
        ("reverse-nested-base-renamed", "renamedCoordinate", "((renamedCoordinate)).yx", "yx"),
        ("reverse-grouped-complete-suffix", "prefixValue", "(((prefixValue).xy))", "xy"),
        ("reverse-grouped-arithmetic", "surfaceLink", "(((surfaceLink)).xy)*vec2(0.5)+vec2(0.125)", "scaled"),
    ):
        result.append({"name": name, "pair": {
            "vertex": vertex_source(carrier, width=2),
            "fragment": (f"varying vec4 {carrier};\nvoid main(){{vec2 uv={expression};"
                         f"gl_FragColor=vec4(uv,({carrier}).x,1.0);}}"),
        }, "operation": operation, "uniforms": {}})
    for name, carrier, extent, scale, expression in (
        ("reverse-common-width-resource", "textureCoordinate", "g_Texture0Resolution", "u_Scale",
         "(textureCoordinate*g_Texture0Resolution.xy)/g_Texture0Resolution.y/u_Scale"),
        ("reverse-common-width-resource-renamed", "orbitCoordinate", "u_surfaceExtent", "u_divisor",
         "(((orbitCoordinate))*(u_surfaceExtent.xy))/(u_surfaceExtent.y)/(u_divisor*1.0)"),
    ):
        result.append({"name": name, "pair": {
            "vertex": vertex_source(carrier, width=2),
            "fragment": (f"uniform vec4 {extent};\nuniform float {scale};\nvarying vec4 {carrier};\n"
                         f"void main(){{vec2 uv={expression};gl_FragColor=vec4(uv,{carrier}.x,1.0);}}"),
        }, "operation": "aspect", "uniforms": {extent: [4.0, 2.0, 1.0, 1.0], scale: [2.0]},
            "carrier": carrier})
    return result


def reverse_pixels(operation: str) -> list[float]:
    # Independent interpolation/arithmetic oracle, without prefix-link logic.
    result = []
    for y in (0.25, 0.75):
        for x in (0.25, 0.75):
            u, v = {"xy": (x, y), "yx": (y, x),
                    "scaled": (x * 0.5 + 0.125, y * 0.5 + 0.125),
                    "aspect": (x, y * 0.5)}[operation]
            result.extend((u, v, x, 1.0))
    return result


def implicit_phase_cases() -> list[dict]:
    cases = []
    for name, carrier, sampler, phase, helper, expression in (
        ("implicit-phase", "v_TexCoord", 0, "u_Phase", "",
         "fract(v_TexCoord + u_Phase)"),
        ("implicit-phase-equivalent-renamed", "orbitCoordinate", 3, "u_OrbitOffset", "",
         "fract((orbitCoordinate * vec2(1.0)) + u_OrbitOffset / vec2(2.0))"),
        ("implicit-phase-helper-mixed-scope", "surfaceCoordinate", 0, "u_Phase", """
vec2 localCoordinate() { vec2 surfaceCoordinate=vec2(0.0); return surfaceCoordinate; }
vec2 formalCoordinate(vec2 surfaceCoordinate) { return surfaceCoordinate; }
vec2 shiftedCoordinate() {
    return fract(surfaceCoordinate + u_Phase + localCoordinate() + formalCoordinate(vec2(0.0)));
}
""", "shiftedCoordinate()"),
        ("implicit-phase-local-structure-type", "carried", 0, "u_Phase", """
vec2 localType() { struct carried { vec2 uv; }; return vec2(0.0); }
""", "fract(carried + u_Phase + localType())"),
    ):
        cases.append({"name": name, "pair": {
            "vertex": vertex_source(carrier, width=2),
            "fragment": (f"uniform sampler2D g_Texture{sampler};\nuniform vec2 {phase};\n"
                         + helper + f"\nvoid main(){{gl_FragColor=texSample2D(g_Texture{sampler},{expression});}}"),
        }, "uniforms": {phase: [1.0 if name.endswith("renamed") else 0.5, 0.0]},
            "textures": [{"index": sampler, "pixels": PHASE_TEXTURE}], "carrier": carrier})
    cases.append({"name": "implicit-phase-fixed-array", "pair": {
        "vertex": """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 phaseCoordinates[2];
void main() {
    gl_Position=vec4(a_Position,1.0);
    phaseCoordinates[0]=a_TexCoord;
    phaseCoordinates[1]=a_TexCoord+vec2(0.5,0.0);
}
""",
        "fragment": ("uniform sampler2D g_Texture0;\n"
                     "vec2 shiftedCoordinate(){return fract(phaseCoordinates[1]);}\n"
                     "void main(){gl_FragColor=texSample2D(g_Texture0,shiftedCoordinate());}"),
    }, "uniforms": {}, "textures": [{"index": 0, "pixels": PHASE_TEXTURE}],
        "carrier": "phaseCoordinates"})
    return cases


def implicit_shadow_cases() -> list[dict]:
    cases = []
    for name, declarations, expression, uniforms, color in (
        ("implicit-local-only", "", "carried", {}, [0.125, 0.875, 0.25, 1.0]),
        ("implicit-formal-only", "vec2 readLocal(vec2 carried){return carried*0.5;}",
         "readLocal(vec2(0.25,0.75))", {}, [0.125, 0.375, 0.25, 1.0]),
    ):
        local = "vec2 carried=vec2(0.125,0.875);" if name == "implicit-local-only" else ""
        cases.append({"name": name, "pair": {
            "vertex": vertex_source(width=2),
            "fragment": (declarations + "\nvoid main(){" + local
                         + f"gl_FragColor=vec4({expression},0.25,1.0);}}"),
        }, "uniforms": uniforms, "expected": color * 4})
    return cases


def pack_uniforms(fields: list[dict], size: int, index: int,
                  values: dict[str, list[float]]) -> dict:
    storage = bytearray((size + 3) // 4 * 4)
    for field in fields:
        width = {"float": 1, "vec2": 2, "float2": 2, "vec4": 4, "float4": 4}[field["type"]]
        components = values[field["name"]]
        if len(components) != width:
            raise AssertionError(f"wrong fixture uniform width: {field}")
        struct.pack_into("<" + "f" * width, storage, field["offset"], *components)
    return {"index": index, "values": list(struct.unpack("<" + "f" * (len(storage) // 4), storage))}


class SceneVaryingValueParameterPrefixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = None
        if directory := os.environ.get("MWX_SCENE_VARYING_PREFIX_WORK"):
            cls.work = Path(directory).resolve()
            cls.work.mkdir(parents=True, exist_ok=True)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-varying-value-prefix-")
            cls.work = Path(cls.temporary.name)
        cls.reused_harness = bool(os.environ.get("MWX_SCENE_VARYING_PREFIX_HARNESS"))
        if binary := os.environ.get("MWX_SCENE_VARYING_PREFIX_HARNESS"):
            cls.binary = Path(binary).resolve()
            if not cls.binary.is_file():
                raise RuntimeError("requested compiled fixture is missing")
            return
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
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
        self.assertEqual(result.returncode, 0, name + result.stdout + result.stderr)
        output = json.loads(result.stdout)
        (root / "analysis.json").write_text(json.dumps(output, indent=2))
        return root, output

    def prepare(self, name: str, pair: dict[str, str], expected: list[float] | None = None,
                uniforms: dict[str, list[float]] | None = None,
                textures: list[dict] | None = None) -> Path:
        root, output = self.analyze(name, pair)
        self.assertTrue(output["idempotent"])
        self.assertEqual(output["boundedDiagnosticCodes"], [], name)
        self.assertNotIn("normalizerFailure", output, name)
        self.assertIn("boundedMSL", output, name)
        # Alternate source resource names travel through the actual linker.
        stem = "renamed-surface" if name.endswith("renamed") else "source"
        for suffix, field in (("vert", "normalizedVertex"), ("frag", "normalizedFragment")):
            (root / (stem + "." + suffix)).write_text(output[field])
        commands = [[str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     "-l", stem + ".vert", stem + ".frag"]]
        for suffix, entry, stage in (("vert", "probeVertex", "vert"), ("frag", "probeFragment", "frag")):
            commands += [
                [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                 stem + "." + suffix, "-o", suffix + ".spv"],
                [str(GLSLANG.with_name("spirv-cross")), suffix + ".spv", "--msl", "--msl-decoration-binding",
                 "--rename-entry-point", "main", entry, stage, "--output", suffix + ".metal"],
            ]
        if uniforms:
            for suffix in ("vert", "frag"):
                commands.append([str(GLSLANG.with_name("spirv-cross")), suffix + ".spv", "--reflect"])
        for phase, command in enumerate(commands):
            completed = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=30)
            (root / f"tool-{phase}.stdout").write_text(completed.stdout)
            (root / f"tool-{phase}.stderr").write_text(completed.stderr)
            self.assertEqual(completed.returncode, 0, name + completed.stdout + completed.stderr)
            if command[-1] == "--reflect":
                (root / (command[1].split(".")[0] + "-reflect.json")).write_text(completed.stdout)
        packets = {
            "generic": {"vertexMSL": (root / "vert.metal").read_text(),
                        "fragmentMSL": (root / "frag.metal").read_text(),
                        "vertexFunction": "probeVertex", "fragmentFunction": "probeFragment"},
            "bounded": {"vertexMSL": output["boundedMSL"], "fragmentMSL": output["boundedMSL"],
                        "vertexFunction": output["boundedVertexFunction"],
                        "fragmentFunction": output["boundedFragmentFunction"]},
        }
        for backend, packet in packets.items():
            if textures:
                packet["fragmentTextures"] = textures
            (root / (backend + "-pixels.json")).write_text(json.dumps(packet, indent=2))
            if uniforms:
                values = {**uniforms, "mwxRenderSize": [2.0, 2.0],
                          "mwxVertexCoordinates01": [0.0, 1.0, 1.0, 1.0],
                          "mwxVertexCoordinates23": [0.0, 0.0, 1.0, 0.0]}
                if backend == "bounded":
                    buffer = pack_uniforms(output["boundedUniformFields"], output["boundedUniformByteSize"],
                                           output["boundedUniformBufferIndex"], values)
                    buffers = {"vertexBuffers": [buffer], "fragmentBuffers": [buffer]}
                else:
                    buffers = {}
                    for suffix, stage in (("vert", "vertexBuffers"), ("frag", "fragmentBuffers")):
                        msl = packet["vertexMSL" if suffix == "vert" else "fragmentMSL"]
                        indices = re.findall(r"constant\s+MWXUniforms\s*&\s*\w+\s*\[\[buffer\((\d+)\)\]\]", msl)
                        if not indices:
                            self.assertNotIn("constant MWXUniforms&", msl)
                            buffers[stage] = []
                            continue
                        self.assertEqual(len(indices), 1)
                        reflection = json.loads((root / (suffix + "-reflect.json")).read_text())
                        blocks = [b for b in reflection["ubos"] if b["name"] == "MWXUniforms"]
                        self.assertEqual(len(blocks), 1)
                        block = blocks[0]
                        buffers[stage] = [pack_uniforms(reflection["types"][block["type"]]["members"],
                                                       block["block_size"], int(indices[0]), values)]
                (root / (backend + "-uniform-sequence.json")).write_text(json.dumps(
                    {"program": packet, "draws": [buffers]}, indent=2))
        if expected is not None:
            (root / "expected.json").write_text(json.dumps(expected))
        (root / "packet-identity.json").write_text(json.dumps({
            "harnessSHA256": hashlib.sha256(self.binary.read_bytes()).hexdigest(),
            "pair": pair, "uniforms": uniforms or {},
            **({"fragmentTextures": textures} if textures else {}),
        }, indent=2))
        return root

    def strict_link(self, root: Path, output: dict, normalized: bool) -> subprocess.CompletedProcess:
        stem = "normalized" if normalized else "canonical"
        fields = ("normalizedVertex", "normalizedFragment") if normalized else (
            "canonicalVertex", "canonicalFragment")
        for suffix, field in zip(("vert", "frag"), fields):
            (root / (stem + "." + suffix)).write_text(output[field])
        flags = ["-V", "--auto-map-bindings", "--auto-map-locations"] if normalized else ["-d"]
        completed = subprocess.run([str(GLSLANG), *flags, "-l", stem + ".vert", stem + ".frag"],
                                   cwd=root, capture_output=True, text=True, timeout=30)
        (root / (stem + "-link.stdout")).write_text(completed.stdout)
        (root / (stem + "-link.stderr")).write_text(completed.stderr)
        return completed

    def test_implicit_phase_inputs_reach_both_backend_routes(self) -> None:
        for case in implicit_phase_cases():
            with self.subTest(name=case["name"]):
                root = self.prepare(case["name"], case["pair"], EXPECTED_PHASE_PIXELS,
                                    case["uniforms"], case["textures"])
                output = json.loads((root / "analysis.json").read_text())
                extent = r"\s*\[\s*2\s*\]" if case["name"].endswith("fixed-array") else ""
                self.assertRegex(output["canonicalFragment"],
                                 r"\bvarying\s+vec2\s+" + case["carrier"] + extent + r"\s*;")

    def test_implicit_inputs_preserve_local_and_formal_owners(self) -> None:
        for case in implicit_shadow_cases():
            with self.subTest(name=case["name"]):
                root = self.prepare(case["name"], case["pair"], case["expected"], case["uniforms"])
                output = json.loads((root / "analysis.json").read_text())
                self.assertNotRegex(output["canonicalFragment"], r"\bvarying\s+\w+\s+carried\b")

    def test_implicit_inputs_do_not_replace_other_names_or_invent_producers(self) -> None:
        normal_vertex = vertex_source(width=2)
        free_fragment = "void main(){gl_FragColor=vec4(carried,0.0,1.0);}"
        cases = [
            ("member-only", normal_vertex,
             "struct Payload{vec2 carried;};void main(){Payload value;value.carried=vec2(0.5);"
             "gl_FragColor=vec4(value.carried,0.0,1.0);}", False),
            ("local-structure-instance-member-only", normal_vertex,
             "vec2 readLocal(){struct Payload{vec2 carried;};Payload value;"
             "value.carried=vec2(0.5);return value.carried;}"
             "void main(){gl_FragColor=vec4(readLocal(),0.0,1.0);}", False),
            ("builtin-callee", vertex_source("sin", width=2),
             "void main(){gl_FragColor=vec4(sin(0.5));}", False),
            ("function-owner", normal_vertex,
             "vec2 carried(){return vec2(0.5);}void main(){gl_FragColor=vec4(carried(),0.0,1.0);}", False),
            ("uniform-stage-namespace-gap", normal_vertex,
             "uniform vec2 carried;\nvoid main(){gl_FragColor=vec4(carried,0.25,1.0);}", False),
            ("structure-type-owner", normal_vertex,
             "struct carried{vec2 uv;};void main(){carried value;value.uv=vec2(0.5);"
             "gl_FragColor=vec4(value.uv,0.0,1.0);}", False),
            ("custom-global-owner", normal_vertex,
             "struct Payload{vec2 uv;};Payload carried;void main(){carried.uv=vec2(0.5);"
             "gl_FragColor=vec4(carried.uv,0.0,1.0);}", False),
            ("global-initializer-only", normal_vertex,
             "vec2 stored=carried;void main(){gl_FragColor=vec4(stored,0.0,1.0);}", True),
            ("explicit-conflict", normal_vertex,
             "varying vec3 carried;void main(){gl_FragColor=vec4(carried,1.0);}", True),
            ("qualified-producer", normal_vertex.replace("varying vec2 carried;",
             "centroid varying vec2 carried;"), free_fragment, True),
            ("explicit-array-length-conflict", normal_vertex.replace("varying vec2 carried;",
             "varying vec2 carried[2];").replace("carried = a_TexCoord;",
             "carried[0]=a_TexCoord;carried[1]=a_TexCoord;"),
             "varying vec2 carried[3];void main(){gl_FragColor=vec4(carried[2],0.0,1.0);}", True),
            ("no-producer", "attribute vec3 a_Position;void main(){gl_Position=vec4(a_Position,1.0);}",
             free_fragment, True),
            ("duplicate-producer", normal_vertex.replace("varying vec2 carried;",
             "varying vec2 carried;varying vec2 carried;"), free_fragment, True),
            ("conflicting-producer", normal_vertex.replace("varying vec2 carried;",
             "varying vec2 carried;varying vec3 carried;"), free_fragment, True),
        ]
        for name, vertex, fragment, rejected in cases:
            with self.subTest(name=name):
                root, output = self.analyze("implicit-rejected-" + name, {"vertex": vertex, "fragment": fragment})
                self.assertTrue(output["idempotent"], name)
                carrier = "sin" if name == "builtin-callee" else "carried"
                if name == "explicit-array-length-conflict":
                    self.assertRegex(output["canonicalFragment"], r"\bvarying\s+vec2\s+carried\s*\[\s*3\s*\]\s*;")
                else:
                    self.assertNotRegex(output["canonicalFragment"],
                                        r"\bvarying\s+vec2\s+" + carrier + r"\b", name)
                if name == "explicit-conflict":
                    self.assertRegex(output["canonicalFragment"], r"\bvarying\s+vec3\s+carried\s*;")
                boundary = {"normalizerFailure": output.get("normalizerFailure"),
                            "boundedDiagnosticCodes": output["boundedDiagnosticCodes"]}
                if name == "uniform-stage-namespace-gap":
                    self.assertNotIn("normalizerFailure", output)
                    self.assertEqual(output["canonicalFragment"], fragment)
                    canonical = self.strict_link(root, output, normalized=False)
                    self.assertEqual(canonical.returncode, 0, canonical.stdout + canonical.stderr)
                    normalized = self.strict_link(root, output, normalized=True)
                    self.assertNotEqual(normalized.returncode, 0, "existing generic stage namespace gap changed")
                    self.assertEqual(output["boundedDiagnosticCodes"], [])
                    self.assertIn("boundedMSL", output)
                    (root / "strict-boundary.json").write_text(json.dumps({**boundary,
                        "canonicalAuthoredStrictReturncode": canonical.returncode,
                        "normalizedStrictReturncode": normalized.returncode,
                        "genericGap": "cross-stage-uniform-varying-namespace",
                        "boundedQualification": "diagnostics-and-MSL-only-no-Metal-pixels"}, indent=2))
                    continue
                if "normalizerFailure" in output and rejected:
                    (root / "strict-boundary.json").write_text(json.dumps(
                        {**boundary, "stage": "rejected-by-existing-generic-normalizer"}, indent=2))
                    continue
                normalized = "normalizerFailure" not in output
                # Unsupported generic struct admission stays visible while the
                # actual authored GLSL linker still proves the healthy source.
                completed = self.strict_link(root, output, normalized)
                (root / "strict-boundary.json").write_text(json.dumps({**boundary,
                    "stage": "normalized-strict-link" if normalized else "canonical-authored-strict-link",
                    "command": completed.args, "returncode": completed.returncode}, indent=2))
                if rejected:
                    self.assertNotEqual(completed.returncode, 0,
                                        name + " must retain its actual compiler failure: " + completed.stdout)
                else:
                    self.assertEqual(completed.returncode, 0, name + completed.stdout + completed.stderr)

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

    def test_reverse_grouped_reads_reach_both_backend_routes(self) -> None:
        for case in reverse_grouped_cases():
            with self.subTest(name=case["name"]):
                root = self.prepare(case["name"], case["pair"], reverse_pixels(case["operation"]),
                                    case["uniforms"])
                if "carrier" in case:
                    output = json.loads((root / "analysis.json").read_text())
                    self.assertRegex(output["canonicalFragment"],
                                     r"\(+\s*" + re.escape(case["carrier"]) + r"\s*\)+\s*\.xy")

    def test_reverse_grouping_does_not_grant_whole_values_or_escapes(self) -> None:
        cases = {
            "whole-reduction": ("", "vec2 uv=vec2(length(carried));"),
            "whole-copy": ("", "vec4 copied=carried;vec2 uv=copied.xy;"),
            "unpublished-suffix": ("", "vec2 uv=((carried)).zw;"),
            "mixed-high-component": ("", "vec2 uv=((carried)).xz;"),
            "direct-write": ("", "(carried).xy=vec2(0.5);vec2 uv=(carried).xy;"),
            "grouped-compound-write": ("", "((carried).xy)+=vec2(0.125);vec2 uv=(carried).xy;"),
            "grouped-prefix-mutation": ("", "++((carried).xy);vec2 uv=(carried).xy;"),
            "grouped-index-write": ("", "((carried).xy)[0]=0.5;vec2 uv=(carried).xy;"),
            "source-value-helper": ("vec2 move(vec2 p){return p;}", "vec2 uv=move((carried).xy);"),
            "out": ("void change(out vec2 p){p=vec2(0.5);}", "change((carried).xy);vec2 uv=(carried).xy;"),
            "inout": ("void change(inout vec2 p){p+=vec2(0.125);}", "change(((carried)).xy);vec2 uv=(carried).xy;"),
            "source-builtin-shadow": ("vec2 abs(vec2 p){return p;}", "vec2 uv=abs((carried).xy);"),
            "local-shadow": ("vec2 globalPrefix(){vec2 value=(carried).xy;return value;}",
                             "vec4 carried=vec4(0.5);vec2 uv=(carried).xy+globalPrefix();"),
            "formal-shadow": ("vec2 readLocal(vec4 carried){return carried.xy;}", "vec2 uv=(carried).xy;"),
            "grouped-return-escape": ("vec2 escaped(){return ((carried).xy);}", "vec2 uv=escaped();"),
            "expression-base": ("", "vec2 uv=(carried+vec4(0.0)).xy;"),
        }
        for name, (helper, statements) in cases.items():
            fragment = ("varying vec4 carried;\n" + helper + "\nvoid main(){" + statements
                        + "gl_FragColor=vec4(uv,0.0,1.0);}")
            with self.subTest(name=name):
                _, output = self.analyze("reverse-rejected-" + name, {
                    "vertex": vertex_source(width=2), "fragment": fragment,
                })
                self.assertTrue(output["idempotent"], name)
                self.assertEqual(output.get("normalizerFailure"), "varyingUnsupported", name)
                self.assertIn("stageLinkMismatch", output["boundedDiagnosticCodes"], name)
                self.assertNotIn("boundedMSL", output, name)
                if name == "whole-reduction":
                    self.assertIn("length(carried)", output["canonicalFragment"])
        # A local-only reference leaves the global interface dead: pruning it
        # is legal and does not exercise the reverse prefix proof.
        _, output = self.analyze("reverse-only-local-shadow-dead-interface", {
            "vertex": vertex_source(width=2),
            "fragment": ("varying vec4 carried;\nvoid main(){vec4 carried=vec4(0.5);"
                         "vec2 uv=(carried).xy;gl_FragColor=vec4(uv,0.0,1.0);}"),
        })
        self.assertTrue(output["idempotent"])
        self.assertEqual(output["boundedDiagnosticCodes"], [])
        self.assertIn("boundedMSL", output)
        self.assertNotIn("normalizerFailure", output)
        self.assertNotRegex(output["normalizedFragment"], r"\bin\s+vec4\s+carried\b")

    def prepared_pixels(self, name: str, pair: dict[str, str], expected: list[float],
                        uniforms: dict[str, list[float]] | None = None,
                        textures: list[dict] | None = None) -> Path:
        root = self.work / "cases" / name
        if not (root / "packet-identity.json").is_file():
            self.assertFalse(self.reused_harness,
                             "prepare CPU packets using this exact compiled fixture before separate GPU readback")
            root = self.prepare(name, pair, expected, uniforms, textures)
        identity = json.loads((root / "packet-identity.json").read_text())
        self.assertEqual(identity, {
            "harnessSHA256": hashlib.sha256(self.binary.read_bytes()).hexdigest(),
            "pair": pair, "uniforms": uniforms or {},
            **({"fragmentTextures": textures} if textures else {}),
        }, "GPU packets must match this shader input and compiled fixture")
        self.assertEqual(json.loads((root / "expected.json").read_text()), expected)
        return root

    def assert_exact_pixels(self, root: Path, expected: list[float], uniforms: bool = False) -> None:
        for backend in ("generic", "bounded"):
            mode, suffix = (("--render-uniform-sequence", "-uniform-sequence.json") if uniforms
                            else ("--render", "-pixels.json"))
            with self.subTest(backend=backend):
                completed = subprocess.run([str(self.binary), mode, str(root / (backend + suffix))],
                                           capture_output=True, text=True, timeout=30)
                (root / (backend + "-gpu.stdout")).write_text(completed.stdout)
                (root / (backend + "-gpu.stderr")).write_text(completed.stderr)
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
                observed = json.loads(completed.stdout)
                if uniforms:
                    self.assertEqual(len(observed), 1)
                    observed = observed[0]
                self.assertEqual(len(observed), len(expected))
                for actual, target in zip(observed, expected):
                    self.assertAlmostEqual(actual, target, places=6)

    @unittest.skipUnless(GPU_ENABLED, "Metal readback is disabled for the separate CPU gate")
    def test_implicit_phase_exact_pixels(self) -> None:
        for case in implicit_phase_cases():
            with self.subTest(name=case["name"]):
                root = self.prepared_pixels(case["name"], case["pair"], EXPECTED_PHASE_PIXELS,
                                            case["uniforms"], case["textures"])
                self.assert_exact_pixels(root, EXPECTED_PHASE_PIXELS, bool(case["uniforms"]))

    @unittest.skipUnless(GPU_ENABLED, "Metal readback is disabled for the separate CPU gate")
    def test_implicit_shadow_exact_pixels(self) -> None:
        for case in implicit_shadow_cases():
            with self.subTest(name=case["name"]):
                root = self.prepared_pixels(case["name"], case["pair"], case["expected"], case["uniforms"])
                self.assert_exact_pixels(root, case["expected"], bool(case["uniforms"]))

    @unittest.skipUnless(GPU_ENABLED, "Metal readback is disabled for the separate CPU gate")
    def test_coordinate_value_copy_exact_pixels(self) -> None:
        for name, pair in copy_cases():
            with self.subTest(name=name):
                root = self.prepared_pixels(name, pair, EXPECTED_COPY_PIXELS)
                self.assert_exact_pixels(root, EXPECTED_COPY_PIXELS)

    @unittest.skipUnless(GPU_ENABLED, "Metal readback is disabled for the separate CPU gate")
    def test_reverse_grouped_prefix_exact_pixels(self) -> None:
        for case in reverse_grouped_cases():
            with self.subTest(name=case["name"]):
                expected = reverse_pixels(case["operation"])
                root = self.prepared_pixels(case["name"], case["pair"], expected, case["uniforms"])
                self.assert_exact_pixels(root, expected, bool(case["uniforms"]))


if __name__ == "__main__":
    unittest.main()
