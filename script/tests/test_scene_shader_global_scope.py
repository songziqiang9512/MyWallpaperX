#!/usr/bin/env python3
"""Real global-reference facts, linked backends, and two-frame Metal pixels."""
from __future__ import annotations

import hashlib
import json
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
'''
HARNESS = backend.HARNESS.replace(
    "        switch SceneGenericShaderSourceNormalizer.normalize(",
    SCOPE_FACTS + "        switch SceneGenericShaderSourceNormalizer.normalize(",
).replace(
    "var uniforms = [Float(width), Float(height), Float(0), Float(0)]",
    "var uniforms = [Float(0.125), Float(0.375), Float(width), Float(height)]",
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
