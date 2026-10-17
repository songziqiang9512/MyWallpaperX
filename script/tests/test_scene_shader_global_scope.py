#!/usr/bin/env python3
"""Real global-reference facts, linked backends, and two-frame Metal pixels."""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_shader_fragment_position as backend

ROOT = backend.REPOSITORY_ROOT
SCOPE_FACTS = r'''
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: fragment, stage: .fragment),
            stage: .fragment
        )
        var references: [String: [[Int]]] = [:]
        var referenced: [String: Bool] = [:]
        var referenceTokenSites: [String: [[Int]]] = [:]
        if let unit = syntax.unit {
            let globalTokens = SceneAuthoredShaderGlobalReferenceAnalyzer.referenceTokens(in: unit)
            for declaration in unit.declarations {
                references[declaration.name] = SceneAuthoredShaderGlobalReferenceAnalyzer
                    .referenceIndices(declaration.name, in: unit).map {
                        [unit.tokens[$0].line, unit.tokens[$0].column]
                    }
                referenced[declaration.name] = SceneAuthoredShaderGlobalReferenceAnalyzer
                    .isReferenced(declaration.name, in: unit)
                referenceTokenSites[declaration.name] = globalTokens
                    .filter { $0.text == declaration.name }
                    .sorted { ($0.line, $0.column) < ($1.line, $1.column) }
                    .map { [$0.line, $0.column] }
            }
        }
        result["syntaxDiagnostics"] = syntax.diagnostics.map { $0.code.rawValue }
        result["globalReferences"] = references
        result["globalIsReferenced"] = referenced
        result["globalReferenceTokenSites"] = referenceTokenSites
        result["canonicalFragment"] = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: vertex, fragment: fragment
        ).fragment
'''
HARNESS = backend.HARNESS.replace(
    "        switch SceneGenericShaderSourceNormalizer.normalize(",
    SCOPE_FACTS + "        switch SceneGenericShaderSourceNormalizer.normalize(",
).replace(
    "var uniforms = [Float(width), Float(height), Float(0), Float(0)]",
    "var uniforms = [Float(0.125), Float(0.375), Float(width), Float(height)]",
)
# Reuse the existing submission/readback carrier. The authored arithmetic cases
# sample an asymmetric UV ramp, so dropped/swapped components change pixels.
HARNESS = HARNESS.replace(
    "        let queue = device.makeCommandQueue()!",
    r'''
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 8, height: 8, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = [.shaderRead]
        let input = device.makeTexture(descriptor: inputDescriptor)!
        var inputPixels: [Float] = []
        for y in 0..<8 {
            for x in 0..<8 {
                inputPixels += [Float(x)/7, Float(y)/7, Float(x+2*y)/21, 1]
            }
        }
        inputPixels.withUnsafeBytes {
            input.replace(region: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 8*16)
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        let sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
        let queue = device.makeCommandQueue()!
''',
).replace(
    "            encoder.setRenderPipelineState(pipeline)",
    "            encoder.setRenderPipelineState(pipeline)\n"
    "            encoder.setFragmentTexture(input, index: 0)\n"
    "            encoder.setFragmentSamplerState(sampler, index: 0)",
)


class ShaderProbe(unittest.TestCase):
    generic_metal = backend.SceneShaderFragmentPositionTests.generic_metal
    render = backend.SceneShaderFragmentPositionTests.render

    def __init__(self, directory: Path, binary: Path):
        super().__init__()
        self.root = directory
        self.binary = binary
        self.results: list[dict] = []
        self._compiled: dict[tuple[str, str], tuple[dict, Path]] = {}
        self._generic: dict[Path, list[Path]] = {}

    def compile(self, fragment: str, vertex: str = backend.VERTEX,
                resource: str = "self-owned") -> tuple[dict, Path]:
        key = (vertex, fragment)
        if key in self._compiled:
            return self._compiled[key]
        directory = Path(tempfile.mkdtemp(prefix=resource + "-", dir=self.root))
        vertex_path, fragment_path = directory / f"{resource}.vert", directory / f"{resource}.frag"
        vertex_path.write_text(vertex)
        fragment_path.write_text(fragment)
        completed = subprocess.run([str(self.binary), str(vertex_path), str(fragment_path),
            str(directory / "output.vert"), str(directory / "output.frag")],
            capture_output=True, text=True, timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self._compiled[key] = (result, directory)
        return result, directory

    def generic(self, directory: Path) -> list[Path]:
        if directory not in self._generic:
            self._generic[directory] = self.generic_metal(directory)
        return self._generic[directory]

    def pixels(self, result: dict, directory: Path, *, width: int = 48,
               height: int = 32) -> dict:
        locations = [(8, 6), (24, 16), (40, 26)]
        bounded = directory / "bounded.metal"
        bounded.write_text(result["boundedMetal"])
        outputs = {}
        for name, stages, functions, uniform_index in (
            ("bounded", [bounded, bounded], ["sceneAuthoredVertex", "sceneAuthoredFragment"], 0),
            ("generic", self.generic(directory), ["position_vert", "position_frag"], 0),
        ):
            outputs[name] = self.render(directory, stages, functions, uniform_index,
                (width, height), (0, 0, width, height), locations)
        return {"locations": locations, "width": width, "height": height, "backends": outputs}


def compile_probe(directory: Path, *, frozen: dict | None = None) -> tuple[ShaderProbe, dict]:
    directory.mkdir(parents=True, exist_ok=True)
    if frozen is None:
        source_directory = directory / "sources"
        source_directory.mkdir()
        records = []
        for index, path in enumerate(backend.SWIFT_SOURCES):
            data = path.read_bytes()
            target = source_directory / f"{index:03d}-{path.name}"
            target.write_bytes(data)
            records.append({"source": str(path), "frozen": str(target.resolve()),
                "sha256": hashlib.sha256(data).hexdigest()})
    else:
        records = frozen["sources"]
    facts = {record["source"]: record["sha256"] for record in records}
    receipt = {"sourceCount": len(records), "sources": records,
        "sourceSHA256": hashlib.sha256(json.dumps(facts, sort_keys=True).encode()).hexdigest(),
        "harnessSHA256": hashlib.sha256(HARNESS.encode()).hexdigest(),
        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "compilerToolSHA256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (backend.GLSLANG, backend.GLSLANG.with_name("spirv-cross"))}}
    (directory / "inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    harness = directory / "Harness.swift"
    harness.write_text(HARNESS)
    binary = directory / "shader-global-scope"
    environment = dict(os.environ)
    environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
    environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-cache")
    compilation = subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
        *(record["frozen"] for record in records), str(harness),
        "-module-cache-path", str(directory / "module-cache"), "-o", str(binary)],
        cwd=ROOT, env=environment, capture_output=True, text=True, timeout=180)
    (directory / "compile.stdout.log").write_text(compilation.stdout)
    (directory / "compile.stderr.log").write_text(compilation.stderr)
    if compilation.returncode:
        raise AssertionError(compilation.stderr)
    return ShaderProbe(directory, binary), receipt


def marked_fragment(source: str, names: tuple[str, ...]) -> tuple[str, dict]:
    """Remove test-authored @ markers and retain the declared expected token sites."""
    expected: dict[str, list[list[int]]] = {name: [] for name in names}
    lines = []
    for line_number, line in enumerate(source.splitlines(), 1):
        while "@" in line:
            start = line.index("@")
            end = start + 1
            while end < len(line) and (line[end].isalnum() or line[end] == "_"):
                end += 1
            name = line[start + 1:end]
            expected[name].append([line_number, start + 1])
            line = line[:start] + name + line[end:]
        lines.append(line)
    return "\n".join(lines) + "\n", expected


def cases() -> list[dict]:
    result = []

    def add(label, body, names=("signal",), *, vertex=None, expected="uv", accepted=True):
        fragment, references = marked_fragment(body, names)
        result.append({"name": label, "fragment": fragment, "references": references,
            "vertex": vertex or backend.VERTEX.replace("v_TexCoord", names[0]),
            "expected": expected, "accepted": accepted})

    for name, resource, expression in (("signal", "source-material", "signal"),
                                       ("renamedCarrier", "another-resource", "(renamedCarrier + renamedCarrier) * 0.5")):
        add(resource + "-initializer", f"""varying vec2 {name};
void main() {{
    vec2 {name} = @{name};
    gl_FragColor = vec4({expression}, 0.25, 1.0);
}}""", (name,))
    for name, resource in (("authoredGain", "uniform-source"), ("renamedGain", "different-uniform-resource")):
        add(resource, f"""uniform vec2 {name};
void main() {{
    vec2 {name} = @{name};
    gl_FragColor = vec4({name}, 0.25, 1.0);
}}""", (name,), expected=(0.125, 0.375), vertex=backend.VERTEX)

    add("comma-first-declarator-visible", """varying vec2 signal;
void main() {
    vec2 signal = @signal, nextValue = signal + vec2(0.125);
    gl_FragColor = vec4(nextValue, 0.25, 1.0);
}""", expected="uv-offset")
    two_varyings = backend.VERTEX.replace("v_TexCoord", "signal").replace(
        "void main()", "varying vec2 nextValue;\nvoid main()"
    ).replace("signal = a_TexCoord;", "signal = a_TexCoord; nextValue = a_TexCoord;")
    add("comma-second-declarator-shadows-global", """varying vec2 signal;
varying vec2 nextValue;
void main() {
    vec2 signal = vec2(0.2, 0.3), nextValue = signal;
    gl_FragColor = vec4(nextValue, 0.25, 1.0);
}""", ("signal", "nextValue"), vertex=two_varyings, expected=(0.2, 0.3))
    add("helper-parameter-does-not-hide-main", """varying vec2 signal;
float helper(vec2 signal) { return signal.x; }
void main() {
    gl_FragColor = vec4(@signal + vec2(helper(vec2(0.2)) * 0.0), 0.25, 1.0);
}""")
    add("for-header-shadow-exits", """varying vec2 signal;
void main() {
    for (int signal = 0; signal < 1; ++signal) { }
    gl_FragColor = vec4(@signal, 0.25, 1.0);
}""")
    add("if-else-unbraced-shadow-exits", """varying vec2 signal;
void main() {
    if (true) vec2 signal = vec2(0.2); else vec2 signal = vec2(0.3);
    gl_FragColor = vec4(@signal, 0.25, 1.0);
}""")
    add("if-condition-before-declaration", """varying vec2 signal;
void main() {
    if (@signal.x > 0.5) vec2 signal = vec2(0.2);
    gl_FragColor = vec4(@signal, 0.25, 1.0);
}""")
    add("nested-shadow-exits", """varying vec2 signal;
void main() {
    vec2 previous = @signal;
    { vec2 signal = vec2(0.2); previous += signal * 0.0; }
    gl_FragColor = vec4((previous + @signal) * 0.5, 0.25, 1.0);
}""")
    add("read-before-and-local-after-declaration", """varying vec2 signal;
void main() {
    vec2 previous = @signal;
    vec2 signal = vec2(0.2);
    gl_FragColor = vec4(previous + signal * 0.0, 0.25, 1.0);
}""")
    add("truly-dead-global-mismatch", """varying vec4 signal;
void main() {
    vec4 signal = vec4(0.2, 0.3, 0.25, 1.0);
    gl_FragColor = signal;
}""", expected=(0.2, 0.3))
    add("member-and-comment-are-not-global", """varying vec4 x;
// x is mentioned in a comment; it is not a reference.
void main() {
    vec2 point = vec2(0.2, 0.3); /* x remains unused. */
    gl_FragColor = vec4(point.x, point.y, 0.25, 1.0);
}""", ("x",), expected=(0.2, 0.3))
    add("live-global-abi-mismatch-with-helper-shadow", """varying vec4 signal;
float helper(vec2 signal) { return signal.x; }
void main() {
    gl_FragColor = vec4(@signal.z, helper(vec2(0.2)), 0.25, 1.0);
}""", accepted=False)
    return result


def float2_arithmetic_cases() -> list[dict]:
    # HLSL Expr.conv / Conv.vtrunc use the shorter vector's prefix at an
    # arithmetic boundary. No semantic evidence comes from the failed official
    # four-card carrier; these controls follow the public working-draft rule.
    result = []

    def add(name, source, control, names=("wide", "v_TexCoord"), vertex=backend.VERTEX,
            expected_uv=(1.0, -0.1625, 1.0, -0.1125), normalize_uv=False):
        names = ("g_Texture0", *names)
        fragment, references = marked_fragment(source.replace("texture2D(g_Texture0,", "texture2D(@g_Texture0,"), names)
        reference, _ = marked_fragment(control.replace("texture2D(g_Texture0,", "texture2D(@g_Texture0,"), names)
        result.append({"name": name, "fragment": fragment, "control": reference,
            "references": references, "vertex": vertex, "expectedUV": expected_uv,
            "normalizeUV": normalize_uv})

    for name, expression, control in [
        ("subtract", "uv - (gain * wide + 0.0625)",
         "uv - (gain * wide.xy + 0.0625)"),
        ("reverse", "(gain * wide + 0.625) - uv * 0.25",
         "(gain * wide.xy + 0.625) - uv * 0.25"),
        ("grouped", "((uv) - (((gain) * (wide)) + (0.0625)))",
         "((uv) - (((gain) * (wide.xy)) + (0.0625)))"),
        ("divide", "uv / (wide * gain + 0.75)",
         "uv / (wide.xy * gain + 0.75)"),
        ("precedence", "uv - gain * wide + 0.125",
         "uv - gain * wide.xy + 0.125"),
    ]:
        variants = [("panel", "wide")]
        if name == "subtract":
            variants.append(("renamed-art", "shiftedCarrier"))
        for resource, binding in variants:
            def body(value):
                return f"""uniform sampler2D g_Texture0;
uniform vec3 {binding};
varying vec2 v_TexCoord;
void main() {{
    vec2 uv = @v_TexCoord;
    float gain = 0.125;
    vec4 {binding} = vec4(0.8, 0.4, 16.0, 32.0);
    vec2 coord = {value.replace('wide', binding)};
    gl_FragColor = texture2D(g_Texture0, coord);
}}"""
            expected_uv = {"reverse": (-0.25, 0.725, -0.25, 0.675),
                "divide": (1/0.85, 0.0, 1/0.8, 0.0),
                "precedence": (1.0, 0.025, 1.0, 0.075)}.get(name, (1.0, -0.1625, 1.0, -0.1125))
            add(resource + "-" + name, body(expression), body(control), (binding, "v_TexCoord"),
                expected_uv=expected_uv)

    parameter = """uniform sampler2D g_Texture0;
uniform vec3 wide;
varying vec2 v_TexCoord;
float peer(vec2 wide) { return wide.x; }
vec2 shifted(vec4 wide, vec2 uv) {
    vec2 coord = uv - (0.125 * WIDE + 0.0625);
    return coord;
}
void main() {
    gl_FragColor = texture2D(g_Texture0, shifted(vec4(0.8, 0.4, 16.0, 32.0), @v_TexCoord));
}"""
    add("parameter-and-peer-function", parameter.replace("WIDE", "wide"),
        parameter.replace("WIDE", "wide.xy"))
    for name, statements in [
        ("before-declaration", "vec2 uv = @wide;\n"
         "vec4 wide = vec4(0.8, 0.4, 16.0, 32.0);\n"
         "vec2 coord = uv - (0.125 * WIDE + 0.0625);"),
        ("declaration-initializer", "vec4 wide = vec4(@wide, 16.0, 32.0);\n"
         "vec2 coord = vec2(0.8, 0.7) - (0.125 * WIDE + 0.0625);"),
        ("nested-scope-exits", "vec2 coord = @wide;\n"
         "{ vec4 wide = vec4(0.8, 0.4, 16.0, 32.0);\n"
         "coord = coord - (0.125 * WIDE + 0.0625); }\n"
         "coord = coord + @wide * 0.125;"),
    ]:
        source = "uniform sampler2D g_Texture0;\nvarying vec2 wide;\nvoid main() {\n" \
            + statements + "\ngl_FragColor = texture2D(g_Texture0, coord);\n}"
        add(name, source.replace("WIDE", "wide"), source.replace("WIDE", "wide.xy"),
            ("wide",), backend.VERTEX.replace("v_TexCoord", "wide"),
            expected_uv={"declaration-initializer": (-0.125, 0.7375, -0.125, 0.6375),
                "nested-scope-exits": (1.125, -0.1625, 1.125, -0.1125)}
                .get(name, (1.0, -0.1625, 1.0, -0.1125)))
    direct = """uniform sampler2D g_Texture0;
uniform vec3 wide;
varying vec2 v_TexCoord;
void main() {
    vec4 wide = vec4(@v_TexCoord, 16.0, 32.0);
    gl_FragColor = texture2D(g_Texture0, COORD);
}"""
    add("legacy-direct-identifier", direct.replace("COORD", "wide"),
        direct.replace("COORD", "wide.xy"), expected_uv=(1, 0, 1, 0))
    direct_function = direct.replace("void main()", "vec2 echoCoord(vec2 value) { return value; }\nvoid main()")
    add("legacy-direct-function-argument", direct_function.replace("COORD", "echoCoord(wide)"),
        direct_function.replace("COORD", "echoCoord(wide.xy)"), expected_uv=(1, 0, 1, 0))
    direct_vec2 = "uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n" \
        "void main() { gl_FragColor = texture2D(g_Texture0, @v_TexCoordCOORD); }"
    add("legacy-vec2-coordinate", direct_vec2.replace("COORD", ""),
        direct_vec2.replace("COORD", ".xy"), ("v_TexCoord",), expected_uv=(1, 0, 1, 0))
    nested_call = """uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
vec2 echoCoord(vec2 value) { return value; }
void main() {
    vec2 uv = @v_TexCoord;
    vec4 wide = vec4(0.8, 0.4, 16.0, 32.0);
    vec2 coord = WRAPPER(uv - (0.125 * WIDE + 0.0625));
    gl_FragColor = texture2D(g_Texture0, coord);
}"""
    for function in ["normalize", "echoCoord"]:
        source = nested_call.replace("WRAPPER", function)
        add("legacy-inner-float2-" + function, source.replace("WIDE", "wide"),
            source.replace("WIDE", "wide.xy"), ("v_TexCoord",), normalize_uv=function == "normalize")

    opaque_constructor = """uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 wide = vec4(@v_TexCoord + vec2(0.4, 0.25), 16.0, 32.0);
    vec2 coord = normalize(WIDE - vec2(sin(0.1)));
    gl_FragColor = texture2D(g_Texture0, coord);
}"""
    add("constructor-around-builtin-call", opaque_constructor.replace("WIDE", "wide"),
        opaque_constructor.replace("WIDE", "wide.xy"), ("v_TexCoord",),
        expected_uv=(1, 0.4-math.sin(0.1), 1, 0.25-math.sin(0.1)), normalize_uv=True)
    opaque_user = nested_call.replace("vec2 echoCoord",
        "float scalarShade(float phase) { return phase * 0.5 + 0.0625; }\nvec2 echoCoord")
    opaque_user = opaque_user.replace("WRAPPER", "echoCoord").replace(
        "0.125 * WIDE + 0.0625", "0.125 * WIDE + CAST2(scalarShade(0.25))")
    add("renamed-resource-constructor-around-user-call", opaque_user.replace("WIDE", "wide"),
        opaque_user.replace("WIDE", "wide.xy"), ("v_TexCoord",),
        expected_uv=(1, -0.2875, 1, -0.2375))
    internal_width = nested_call.replace("vec2 coord = WRAPPER(uv - (0.125 * WIDE + 0.0625));",
        "vec3 value3 = vec3(0.125, 0.25, 0.5);\n    vec2 coord = uv - vec2(WIDE * value3);")
    add("constructor-keeps-inner-xyz-conversion", internal_width.replace("WIDE", "wide"),
        internal_width.replace("WIDE", "wide.xyz"), ("v_TexCoord",),
        expected_uv=(1, -0.1, 1, -0.1))
    return result


class SceneShaderGlobalScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = None
        if destination := os.environ.get("MWX_SHADER_GLOBAL_SCOPE_EVIDENCE"):
            cls.directory = Path(destination)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-shader-global-scope-")
            cls.directory = Path(cls.temporary.name)
        cls.probe, cls.receipt = compile_probe(cls.directory)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.receipt["results"] = cls.probe.results
        cls.receipt["frozenSourceHashesStable"] = all(
            hashlib.sha256(Path(item["frozen"]).read_bytes()).hexdigest() == item["sha256"]
            for item in cls.receipt["sources"]
        )
        cls.receipt["liveSourceHashesStable"] = all(
            hashlib.sha256(Path(item["source"]).read_bytes()).hexdigest() == item["sha256"]
            for item in cls.receipt["sources"]
        )
        (cls.directory / "result.json").write_text(json.dumps(cls.receipt, indent=2) + "\n")
        if cls.temporary is not None:
            cls.temporary.cleanup()

    def test_global_token_scopes_link_and_render_on_both_backends(self) -> None:
        gpu = os.environ.get("MWX_RUN_SHADER_GLOBAL_SCOPE_GPU") == "1"
        for case in cases():
            with self.subTest(case=case["name"]):
                result, directory = self.probe.compile(case["fragment"], case["vertex"], case["name"])
                self.assertEqual(result["syntaxDiagnostics"], [])
                self.assertEqual(result["globalReferences"], case["references"])
                self.assertEqual(result["globalReferenceTokenSites"], case["references"])
                self.assertEqual(result["globalIsReferenced"],
                    {name: bool(sites) for name, sites in case["references"].items()})
                record = {"case": case["name"], "references": result["globalReferences"],
                    "boundedHasProgram": result["boundedHasProgram"], "genericNormalized": result["ok"]}
                self.probe.results.append(record)
                if not case["accepted"]:
                    self.assertFalse(result["boundedHasProgram"], result)
                    self.assertFalse(result["ok"], result)
                    continue
                self.assertTrue(result["ok"], result)
                self.assertTrue(result["boundedHasProgram"], result["boundedDiagnostics"])
                self.probe.generic(directory)
                if not gpu:
                    continue
                pixels = self.probe.pixels(result, directory)
                record["pixels"] = pixels
                self.assert_pixels(case["name"], pixels, case["expected"])
        self.assertTrue(all(hashlib.sha256(Path(item["frozen"]).read_bytes()).hexdigest() == item["sha256"]
            for item in self.receipt["sources"]), "frozen source changed during gate")

    def assert_pixels(self, case: str, pixels: dict, expected_value) -> None:
        for name, output in pixels["backends"].items():
            self.assertEqual(len(output["frames"]), 2)
            for frame_index, frame in enumerate(output["frames"]):
                for pixel, (x, y) in zip(frame, pixels["locations"], strict=True):
                    expected = expected_value
                    if isinstance(expected, str):
                        offset = 0.125 if expected == "uv-offset" else 0
                        expected = ((x + 0.5) / pixels["width"] + offset,
                                    (y + 0.5) / pixels["height"] + offset)
                    for actual, wanted in zip(pixel, [*expected, 0.25, 1], strict=True):
                        self.assertAlmostEqual(actual, wanted, delta=2e-6,
                            msg=f"{case} {name} frame={frame_index} pixel={x},{y}")

    def test_float2_arithmetic_uses_lexical_types_and_matches_explicit_xy_pixels(self) -> None:
        if os.environ.get("MWX_RUN_SHADER_GLOBAL_SCOPE_GPU") != "1":
            self.skipTest("set MWX_RUN_SHADER_GLOBAL_SCOPE_GPU=1 for actual Metal readback")
        for case in float2_arithmetic_cases():
            with self.subTest(case=case["name"]):
                paired = []
                for label, fragment in [("implicit", case["fragment"]), ("explicit", case["control"])]:
                    result, directory = self.probe.compile(fragment, case["vertex"], case["name"] + "-" + label)
                    self.assertEqual(result["syntaxDiagnostics"], [])
                    self.assertEqual(result["globalReferences"], case["references"])
                    self.assertEqual(result["globalReferenceTokenSites"], case["references"])
                    self.assertTrue(result["ok"], result)
                    self.assertTrue(result["boundedHasProgram"], result["boundedDiagnostics"])
                    paired.append(self.probe.pixels(result, directory))
                differences = {}
                for backend_name, actual in paired[0]["backends"].items():
                    expected = paired[1]["backends"][backend_name]
                    self.assertEqual(actual["completion"], "completed")
                    self.assertEqual(actual["submissions"], 2)
                    self.assertEqual(actual["frames"], [actual["frames"][0]] * 2)
                    self.assertNotEqual(expected["frames"][0][0][:2], expected["frames"][0][-1][:2])
                    # Independent carrier oracle: normalized UVs address an
                    # 8x8 linear-filtered ramp whose texels are (x/7,y/7,(x+2y)/21,1).
                    # Both frames deliberately have identical inputs and must
                    # reproduce these known spatial colors before comparison.
                    ax, bx, ay, by = case["expectedUV"]
                    for frame in expected["frames"]:
                        for pixel, (x, y) in zip(frame, paired[1]["locations"], strict=True):
                            u = ax * (x+0.5)/paired[1]["width"] + bx
                            v = ay * (y+0.5)/paired[1]["height"] + by
                            if case["normalizeUV"]:
                                length = (u*u + v*v)**0.5
                                u, v = u/length, v/length
                            red = min(1.0, max(0.0, (8*u-0.5)/7))
                            green = min(1.0, max(0.0, (8*v-0.5)/7))
                            for component, wanted in zip(pixel, [red, green, (red+2*green)/3, 1], strict=True):
                                # Permit bounded sampling precision relative
                                # to the ideal continuous ramp, independently
                                # of the stricter implicit/explicit comparison.
                                self.assertAlmostEqual(component, wanted, delta=1/1024,
                                    msg=f"independent explicit-ramp oracle {case['name']} {backend_name} {x},{y}")
                    self.assertNotEqual(actual["frames"][0][0][:2], actual["frames"][0][-1][:2],
                        "UV-ramp control must distinguish sampled coordinates")
                    delta = max(abs(a-b) for frame, control in zip(actual["frames"], expected["frames"], strict=True)
                        for pixel, reference in zip(frame, control, strict=True)
                        for a, b in zip(pixel, reference, strict=True))
                    self.assertLessEqual(delta, 2e-6)
                    differences[backend_name] = delta
                self.probe.results.append({"case": case["name"], "implicit": paired[0],
                    "explicit": paired[1], "maxDifference": differences,
                    "globalReferences": case["references"], "expectedUV": case["expectedUV"],
                    "normalizeUV": case["normalizeUV"]})
                if case["name"] == "panel-subtract":
                    wrong, directory = self.probe.compile(case["control"].replace("wide.xy", "wide.xx"),
                        case["vertex"], "wrong-prefix-control")
                    wrong_pixels = self.probe.pixels(wrong, directory)
                    for name, output in wrong_pixels["backends"].items():
                        correct = paired[1]["backends"][name]
                        delta = max(abs(a-b) for frame, reference in zip(output["frames"], correct["frames"], strict=True)
                            for pixel, expected in zip(frame, reference, strict=True)
                            for a, b in zip(pixel, expected, strict=True))
                        self.assertGreater(delta, 0.025, "xx must be distinguishable from xy")
                    self.probe.results.append({"case": "wrong-prefix-control", "pixels": wrong_pixels,
                        "distinguishableFromXY": True})

    def test_float2_arithmetic_does_not_cross_unproven_expression_boundaries(self) -> None:
        for name, expression, declarations, sample in [
            ("wide-only", "wide + vec4(0.1)", "", "texture2D"),
            ("unknown", "uv - missing", "", "texture2D"),
            ("future-local", "uv - future", "", "texture2D"),
            ("side-effect", "uv - (wide++)", "", "texture2D"),
            ("user-call", "uv - coordinates(wide)",
             "vec4 coordinates(vec4 value) { return value; }", "texture2D"),
            ("wide-only-user-call", "coordinates(wide + wide)",
             "vec2 coordinates(vec2 value) { return value; }", "texture2D"),
            ("normalize", "uv - normalize(wide)", "", "texture2D"),
            ("wide-only-normalize", "normalize(wide)", "", "texture2D"),
            ("dot-scalar-coordinate", "dot(wide, wide)", "", "texture2D"),
            ("integer", "uv - ivec4(1)", "", "texture2D"),
            ("matrix", "uv - mat2(1.0)", "", "texture2D"),
            ("dynamic-array", "uv - values[int(uv.x * 2.0)]", "vec4 values[2];", "texture2D"),
            ("non-2d", "wide", "", "texture3D"),
        ]:
            with self.subTest(case=name):
                sampler = "sampler2D" if sample == "texture2D" else "sampler3D"
                tail = "vec4 future = vec4(0.25);" if name == "future-local" else ""
                fragment = f"""uniform {sampler} g_Texture0;
varying vec2 v_TexCoord;
{declarations}
void main() {{
    vec2 uv = v_TexCoord;
    vec4 wide = vec4(0.8, 0.4, 0.6, 0.2);
    gl_FragColor = {sample}(g_Texture0, {expression});
    {tail}
}}"""
                result, directory = self.probe.compile(fragment, resource="unproven-" + name)
                # None of these authored inputs has an explicit .xy. A sampler
                # consumer alone cannot authorize truncating an unknown tree.
                self.assertNotIn(".xy", result["canonicalFragment"])
                if result["ok"]:
                    self.probe.generic_metal(directory, accepted=False)
                self.probe.results.append({"case": name, "boundedHasProgram": result["boundedHasProgram"],
                    "genericNormalized": result["ok"], "unprovenCoordinateNotRewritten": True})

        # A constructor's nominal result type does not make invalid arguments
        # legal. The real compiler must still reject three scalar vec2 inputs.
        fragment = """uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 wide = vec4(v_TexCoord + vec2(0.4, 0.25), 16.0, 32.0);
    gl_FragColor = texture2D(g_Texture0,
        normalize(wide - vec2(sin(0.1), sin(0.2), sin(0.3))));
}"""
        result, directory = self.probe.compile(fragment, resource="invalid-constructor-arity")
        self.assertTrue(result["ok"], result)
        self.probe.generic_metal(directory, accepted=False)
        self.probe.results.append({"case": "invalid-constructor-arity", "genericNormalized": True,
            "realCompilerRejected": True})

    def test_deep_legal_scopes_retain_exact_global_tokens_and_lowering(self) -> None:
        for kind in ("block", "if"):
            opening = "{\n" if kind == "block" else "if (true) {\n"
            source = "varying vec2 deepSignal;\nvoid main() {\nvec2 carried = vec2(0.0);\n" \
                + opening * 320 + "carried = @deepSignal;\n" + "}\n" * 320 \
                + "gl_FragColor = vec4(carried, 0.25, 1.0);\n}\n"
            fragment, references = marked_fragment(source, ("deepSignal",))
            result, _ = self.probe.compile(fragment,
                backend.VERTEX.replace("v_TexCoord", "deepSignal"), "deep-" + kind)
            self.assertEqual(result["syntaxDiagnostics"], [])
            self.assertEqual(result["globalReferences"], references)
            self.assertEqual(result["globalReferenceTokenSites"], references)
            self.assertEqual(result["globalIsReferenced"], {"deepSignal": True})
            self.assertTrue(result["boundedHasProgram"], result["boundedDiagnostics"])
            # This is the token-lowering contract for the bounded stage input;
            # the deep facts do not claim an external compiler nesting budget.
            self.assertEqual(result["boundedMetal"].count("mwxInput.deepSignal"), 1)
            self.probe.results.append({"case": "deep-" + kind, "depth": 320,
                "references": references, "boundedHasProgram": result["boundedHasProgram"],
                "exactLoweredGlobalTokens": 1})

    def test_adjacent_metadata_controls_link_after_dead_interface_pruning(self) -> None:
        fragments = {
            "duplicate-dead-varying": """varying vec4 signal;
varying vec4 signal;
void main() {
    vec4 signal = vec4(0.2, 0.3, 0.25, 1.0);
    gl_FragColor = signal;
}
""",
            "struct-fields-are-not-global-references": """varying vec4 signal;
struct Outer { vec2 signal; };
void main() {
    struct Inner { vec2 signal; };
    Outer first = Outer(vec2(0.2, 0.3));
    Inner second = Inner(vec2(0.2, 0.3));
    gl_FragColor = vec4((first.signal + second.signal) * 0.5, 0.25, 1.0);
}
""",
            "constant-struct-member-is-not-global": """varying vec4 signal;
struct S { vec2 signal; };
const S fixedValue = S(vec2(0.2, 0.3));
const vec2 chosen = fixedValue.signal;
void main() { gl_FragColor = vec4(chosen, 0.25, 1.0); }
""",
        }
        vertex = backend.VERTEX.replace("v_TexCoord", "signal")
        for name, fragment in fragments.items():
            with self.subTest(case=name):
                result, directory = self.probe.compile(fragment, vertex, name)
                # The vertex intentionally exports vec2 while the dead fragment
                # declaration is vec4. A real link requires dead-interface pruning;
                # an unavailable bounded syntax DTO is not a scope-fact success.
                self.assertTrue(result["ok"], result)
                if name != "duplicate-dead-varying":
                    self.assertEqual(result["syntaxDiagnostics"], [])
                    self.assertEqual(result["globalReferences"], {"signal": []})
                    self.assertEqual(result["globalReferenceTokenSites"], {"signal": []})
                    self.assertEqual(result["globalIsReferenced"], {"signal": False})
                self.probe.generic(directory)
                self.probe.results.append({"case": name, "genericNormalized": True,
                    "genericLinked": True,
                    "syntaxDiagnostics": result["syntaxDiagnostics"]})

    def test_hinted_loop_and_real_global_mutation_keep_exact_live_tokens(self) -> None:
        sources = {
            "hinted-loop-global-read": """varying vec2 signal;
void main() {
    vec2 carried = vec2(0.0);
    [loop] for (int i = 0; i < 1; ++i) { carried += @signal; }
    gl_FragColor = vec4(carried, 0.25, 1.0);
}
""",
            "real-global-varying-mutation": """varying vec2 signal;
void main() {
    @signal += vec2(0.125);
    gl_FragColor = vec4(@signal, 0.25, 1.0);
}
""",
        }
        for name, source in sources.items():
            with self.subTest(case=name):
                fragment, references = marked_fragment(source, ("signal",))
                result, directory = self.probe.compile(fragment,
                    backend.VERTEX.replace("v_TexCoord", "signal"), name)
                self.assertEqual(result["syntaxDiagnostics"], [])
                self.assertEqual(result["globalReferences"], references)
                self.assertEqual(result["globalReferenceTokenSites"], references)
                self.assertEqual(result["globalIsReferenced"], {"signal": True})
                self.assertTrue(result["boundedHasProgram"], result["boundedDiagnostics"])
                self.assertEqual(result["boundedMetal"].count("mwxInput.signal"),
                    len(references["signal"]))
                self.assertTrue(result["ok"], result)
                self.probe.generic(directory)
                record = {"case": name, "references": references,
                    "boundedHasProgram": True, "genericNormalized": True,
                    "genericLinked": True, "exactLoweredGlobalTokens": len(references["signal"])}
                self.probe.results.append(record)
                if name == "real-global-varying-mutation" \
                        and os.environ.get("MWX_RUN_SHADER_GLOBAL_SCOPE_GPU") == "1":
                    pixels = self.probe.pixels(result, directory)
                    record["pixels"] = pixels
                    self.assert_pixels(name, pixels, "uv-offset")

    def test_struct_array_dimension_preserves_real_global_reference_fact(self) -> None:
        fragment, references = marked_fragment("""varying vec2 signal;
struct Local { float entries[int(@signal.x)]; };
void main() { gl_FragColor = vec4(0.2, 0.3, 0.25, 1.0); }
""", ("signal",))
        result, _ = self.probe.compile(fragment,
            backend.VERTEX.replace("v_TexCoord", "signal"), "struct-array-dimension-fact")
        self.assertEqual(result["syntaxDiagnostics"], [])
        self.assertEqual(result["globalReferences"], references)
        self.assertEqual(result["globalReferenceTokenSites"], references)
        self.assertEqual(result["globalIsReferenced"], {"signal": True})
        # A varying is not a legal constant GLSL array size. This input only
        # establishes token ownership, and makes no Program/compile claim.
        self.probe.results.append({"case": "struct-array-dimension-fact",
            "references": references, "globalIsReferenced": True,
            "validation": "token-facts-only"})


if __name__ == "__main__":
    unittest.main()
