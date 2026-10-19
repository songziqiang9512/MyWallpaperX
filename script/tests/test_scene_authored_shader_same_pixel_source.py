#!/usr/bin/env python3
"""CPU-only structural source-sampling proof; no Metal/compiler execution."""

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
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402
from test_scene_shader_preprocessor import SWIFT_SOURCES as PREPROCESSOR_SOURCES  # noqa: E402


SWIFT_SOURCES = list(dict.fromkeys([
    *scene_swift_sources("authored_shader_frontend_core"),
    *PREPROCESSOR_SOURCES,
    SCENE_ROOT / "Compilation/ShaderFrontend/SceneAuthoredShaderSamePixelSourceAnalyzer.swift",
]))

VERTEX = """
uniform mat4 g_ModelViewProjectionMatrix;
uniform vec4 auxResolution;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 bridgeUV;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    bridgeUV.xy = a_TexCoord;
    bridgeUV.zw = vec2(a_TexCoord.x * auxResolution.z / auxResolution.x,
                       a_TexCoord.y * auxResolution.w / auxResolution.y);
}
"""

FRAGMENT = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
varying vec4 bridgeUV;
void main() {
    vec4 source = texture2D(g_Texture0, bridgeUV.xy);
    vec4 auxiliary = texture2D(g_Texture1, bridgeUV.zw + vec2(0.125));
    gl_FragColor = source + auxiliary * 0.0;
}
"""

HARNESS = r'''
import Foundation

private struct Input: Decodable {
    let name: String
    let vertexSource: String
    let fragmentSource: String
}

private struct PreparedInput: Decodable {
    let name: String
    let projectRoot: String
    let packageRoot: String?
    let stockRoot: String?
    let vertexPath: String
    let fragmentPath: String
    let combos: [String: Int64]
}

private struct Request: Decodable {
    let cases: [Input]
    let prepared: [PreparedInput]
}

private struct ResultEntry: Encodable {
    let name: String
    let fact: SceneAuthoredShaderSamePixelSourceAnalyzer.Fact?
    let vertexSHA256: String
    let fragmentSHA256: String
}

private enum PreparationFailure: Error { case rejected(String) }

@main
private enum Harness {
    static func main() throws {
        let request = try JSONDecoder().decode(Request.self,
            from: FileHandle.standardInput.readDataToEndOfFile())
        var entries: [ResultEntry] = request.cases.map { evaluate($0) }
        for input in request.prepared {
            let view = SceneResourceView(
                projectRootURL: URL(fileURLWithPath: input.projectRoot),
                packageRootURL: input.packageRoot.map { URL(fileURLWithPath: $0) },
                stockAssetsRootURL: input.stockRoot.map { URL(fileURLWithPath: $0) })
            let graph = SceneShaderSourceGraphBuilder().build(roots: [
                .init(label: "vertex", virtualPath: input.vertexPath),
                .init(label: "fragment", virtualPath: input.fragmentPath)
            ], resourceView: view)
            func prepare(_ path: String, stage: SceneShaderContract.StageKind) throws -> String {
                let environment = try SceneShaderVariantEnvironment(stage: stage,
                    combos: input.combos.sorted(by: { $0.key < $1.key }).map {
                        .init(name: $0.key, definition: .defined(.integer($0.value)))
                    })
                switch SceneShaderPreprocessor().preprocess(rootRelativePath: path,
                    graph: graph, environment: environment) {
                case let .success(source): return source.source
                case let .failure(failure):
                    throw PreparationFailure.rejected(String(describing: failure))
                }
            }
            entries.append(evaluate(Input(name: input.name,
                vertexSource: try prepare(input.vertexPath, stage: .vertex),
                fragmentSource: try prepare(input.fragmentPath, stage: .fragment))))
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(entries))
    }

    private static func evaluate(_ input: Input) -> ResultEntry {
        ResultEntry(name: input.name,
            fact: SceneAuthoredShaderSamePixelSourceAnalyzer.analyze(
                vertexSource: input.vertexSource, fragmentSource: input.fragmentSource),
            vertexSHA256: SceneShaderStableDigest.hash(Data(input.vertexSource.utf8)),
            fragmentSHA256: SceneShaderStableDigest.hash(Data(input.fragmentSource.utf8)))
    }
}
'''


class SceneAuthoredShaderSamePixelSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-same-pixel-source-")
        cls.root = Path(cls.temporary.name)
        cls.binary = cls.root / "proof"
        cls.environment = os.environ.copy()
        cls.environment["CLANG_MODULE_CACHE_PATH"] = str(cls.root / "clang-cache")
        cls.environment["SWIFT_MODULECACHE_PATH"] = str(cls.root / "swift-cache")
        harness = cls.root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        try:
            subprocess.run([swiftc, "-parse-as-library", *map(str, SWIFT_SOURCES),
                            str(harness), "-o", str(cls.binary)],
                           cwd=REPOSITORY_ROOT, env=cls.environment, check=True,
                           capture_output=True, text=True)
        except subprocess.CalledProcessError as error:
            cls.temporary.cleanup()
            raise RuntimeError(error.stderr) from error

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def evaluate(self, cases: list[dict], prepared: list[dict] | None = None) -> dict:
        output = subprocess.run([str(self.binary)], input=json.dumps({
            "cases": cases, "prepared": prepared or [],
        }), cwd=REPOSITORY_ROOT, env=self.environment, check=True,
            capture_output=True, text=True).stdout
        return {item["name"]: item for item in json.loads(output)}

    def test_identity_variants_and_neighbor_rejections(self) -> None:
        cases = []
        expectations = {}

        def add(name, vertex=VERTEX, fragment=FRAGMENT, *, accepted=True, count=1,
                varying="bridgeUV", matrix="g_ModelViewProjectionMatrix"):
            cases.append({"name": name, "vertexSource": vertex, "fragmentSource": fragment})
            expectations[name] = (accepted, count, varying, matrix)

        add("split-xy-zw-independent-auxiliary")
        add("renamed-varying", VERTEX.replace("bridgeUV", "renamedCoordinates"),
            FRAGMENT.replace("bridgeUV", "renamedCoordinates"), varying="renamedCoordinates")
        add("renamed-matrix-fact", VERTEX.replace("g_ModelViewProjectionMatrix", "engineTransform"),
            matrix="engineTransform")
        add("grouped-identity-constructors", VERTEX.replace(
            "vec4(a_Position, 1.0)", "vec4(vec3((a_Position).xyz), (1.0))"
        ).replace("bridgeUV.xy = a_TexCoord;",
                  "bridgeUV.xy = vec2((a_TexCoord.x), (a_TexCoord.y));"),
            FRAGMENT.replace("bridgeUV.xy", "vec2((bridgeUV).x, (bridgeUV).y)"))
        add("matrix-times-vector", VERTEX.replace(
            "mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix)",
            "(g_ModelViewProjectionMatrix) * (vec4(a_Position, 1.0))"))
        add("vec4-full-identity", VERTEX.replace("bridgeUV.xy = a_TexCoord;",
                                               "bridgeUV = a_TexCoord.xyxy;"))
        add("vec2-varying", VERTEX.replace("varying vec4", "varying vec2").replace(
            "bridgeUV.xy = a_TexCoord;", "bridgeUV = a_TexCoord;"
        ).replace("bridgeUV.zw = vec2", "vec2 unused = vec2"),
            FRAGMENT.replace("varying vec4", "varying vec2").replace("bridgeUV.zw", "vec2(0.0)"))
        add("xy-interface-width-independent", fragment=FRAGMENT.replace("varying vec4", "varying vec2"))
        add("two-ordinary-source-reads", fragment=FRAGMENT.replace(
            "gl_FragColor = source", "source += texture2D(g_Texture0, vec2((bridgeUV.xy)));\n gl_FragColor = source"
        ), count=2)
        add("authored-sample-spelling", fragment=FRAGMENT.replace("texture2D", "texSample2D"))
        add("other-slot-offset-lod-unrestricted", fragment=FRAGMENT.replace(
            "texture2D(g_Texture1, bridgeUV.zw + vec2(0.125))",
            "texture2DLod(g_Texture1, bridgeUV.zw * vec2(2.0), 1.0)"))

        def reject(name, vertex=VERTEX, fragment=FRAGMENT):
            add(name, vertex, fragment, accepted=False)

        reject("vertex-warp", VERTEX.replace("vec4(a_Position, 1.0)",
                                              "vec4(a_Position + vec3(0.1), 1.0)"))
        reject("wrong-matrix-order", VERTEX.replace(
            "mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix)",
            "vec4(a_Position, 1.0) * g_ModelViewProjectionMatrix"))
        reject("no-engine-matrix", VERTEX.replace(
            "mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix)", "vec4(a_Position, 1.0)"))
        reject("position-written-again", VERTEX.replace("bridgeUV.xy =", "gl_Position.x += 0.1;\n bridgeUV.xy ="))
        reject("vertex-conditional-producer", VERTEX.replace(
            "bridgeUV.xy = a_TexCoord;", "if (auxResolution.x > 0.0) { bridgeUV.xy = a_TexCoord; }"))
        reject("vertex-conditional-unbraced", VERTEX.replace(
            "bridgeUV.xy = a_TexCoord;", "if (auxResolution.x > 0.0) bridgeUV.xy = a_TexCoord;"))
        reject("vertex-early-return", VERTEX.replace("gl_Position =", "if (auxResolution.x > 0.0) return;\n gl_Position ="))
        reject("duplicate-xy-write", VERTEX.replace("bridgeUV.xy = a_TexCoord;",
            "bridgeUV.xy = a_TexCoord; bridgeUV.xy = a_TexCoord;"))
        reject("vertex-uv-offset", VERTEX.replace("bridgeUV.xy = a_TexCoord;",
                                                 "bridgeUV.xy = a_TexCoord + vec2(0.1);"))
        reject("vertex-uv-swapped", VERTEX.replace("bridgeUV.xy = a_TexCoord;",
                                                  "bridgeUV.xy = a_TexCoord.yx;"))
        reject("vertex-input-mutated", VERTEX.replace("gl_Position =", "a_TexCoord.x += 0.1; gl_Position ="))
        reject("fragment-offset", fragment=FRAGMENT.replace("g_Texture0, bridgeUV.xy", "g_Texture0, bridgeUV.xy + vec2(0.1)"))
        reject("fragment-reordered", fragment=FRAGMENT.replace("g_Texture0, bridgeUV.xy", "g_Texture0, bridgeUV.yx"))
        reject("fragment-alias-coordinate", fragment=FRAGMENT.replace(
            "vec4 source =", "vec2 localUV = bridgeUV.xy; vec4 source ="
        ).replace("g_Texture0, bridgeUV.xy", "g_Texture0, localUV"))
        reject("fragment-xy-write", fragment=FRAGMENT.replace("vec4 source =", "bridgeUV.xy += vec2(0.1); vec4 source ="))
        reject("fragment-grouped-xy-write", fragment=FRAGMENT.replace("vec4 source =", "((bridgeUV).xy) += vec2(0.1); vec4 source ="))
        reject("fragment-out-helper", fragment=FRAGMENT.replace("void main()", "void move(inout vec2 uv) { uv.x += 0.1; }\nvoid main()").replace(
            "vec4 source =", "move(bridgeUV.xy); vec4 source ="))
        reject("local-varying-shadow", fragment=FRAGMENT.replace("vec4 source =", "vec4 bridgeUV = vec4(0.5); vec4 source ="))
        reject("multiple-coordinate-varyings", fragment=FRAGMENT.replace("void main()", "varying vec2 differentUV; void main()").replace(
            "gl_FragColor = source", "source += texture2D(g_Texture0, differentUV); gl_FragColor = source"))
        for function in ["texture2DLod", "texture2DOffset", "textureGather", "texture2DProj"]:
            reject(function, fragment=FRAGMENT.replace("texture2D(g_Texture0", f"{function}(g_Texture0"))
        reject("extra-sample-argument", fragment=FRAGMENT.replace("g_Texture0, bridgeUV.xy)", "g_Texture0, bridgeUV.xy, 0.0)"))
        reject("source-sampler-helper", fragment=FRAGMENT.replace("void main()", "vec4 readSource(sampler2D s, vec2 uv) { return texture2D(s, uv); }\nvoid main()").replace(
            "texture2D(g_Texture0,", "readSource(g_Texture0,"))
        reject("source-read-in-helper", fragment=FRAGMENT.replace("void main()", "vec4 unused() { return texture2D(g_Texture0, bridgeUV.xy); }\nvoid main()"))
        reject("source-sampler-alias", fragment=FRAGMENT.replace("vec4 source =", "sampler2D alias = g_Texture0; vec4 source ="))
        reject("vertex-source-read", VERTEX.replace("void main()", "uniform sampler2D g_Texture0; void main()").replace(
            "bridgeUV.xy =", "vec4 read = texture2D(g_Texture0, a_TexCoord); bridgeUV.xy ="))
        reject("missing-source-sample", fragment=FRAGMENT.replace("texture2D(g_Texture0, bridgeUV.xy)", "vec4(0.0)"))
        reject("malformed-source", fragment=FRAGMENT + "(")

        results = self.evaluate(cases)
        for name, (accepted, count, varying, matrix) in expectations.items():
            with self.subTest(name=name):
                fact = results[name].get("fact")
                if not accepted:
                    self.assertIsNone(fact)
                else:
                    self.assertEqual(fact, {"textureSlot": 0, "sampleCallCount": count,
                        "coordinateVaryingName": varying, "positionMatrixUniformName": matrix})

    def test_resource_renaming_uses_existing_preprocessor(self) -> None:
        root = self.root / "own-resources"
        prepared = []
        for index, stem in enumerate(["original-pass", "renamed-unrelated-resource"]):
            parent = root / "shaders" / stem
            parent.mkdir(parents=True)
            (parent / "quad.vert").write_text(VERTEX, encoding="utf-8")
            (parent / "color.frag").write_text(FRAGMENT, encoding="utf-8")
            prepared.append({"name": str(index), "projectRoot": str(root),
                "vertexPath": f"shaders/{stem}/quad.vert",
                "fragmentPath": f"shaders/{stem}/color.frag", "combos": {}})
        results = self.evaluate([], prepared)
        self.assertEqual(results["0"]["fact"], results["1"]["fact"])
        self.assertEqual(results["0"]["fact"]["sampleCallCount"], 1)

    @unittest.skipUnless(os.environ.get("MWX_SAME_PIXEL_REAL_INPUT"),
                         "optional authored source context was not supplied")
    def test_read_only_authored_input_through_existing_preprocessor(self) -> None:
        # The task supplies read-only corpus bytes; no author algorithm is copied
        # into this portable fixture or used as the product dispatch key.
        context = json.loads(Path(os.environ["MWX_SAME_PIXEL_REAL_INPUT"]).read_text())
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in Path(context["projectRoot"]).rglob("*") if path.is_file()}
        result = self.evaluate([], [context])[context["name"]]
        self.assertEqual(result["fact"]["textureSlot"], 0)
        self.assertGreaterEqual(result["fact"]["sampleCallCount"], 1)
        self.assertEqual(result["fact"]["positionMatrixUniformName"], "g_ModelViewProjectionMatrix")
        self.assertEqual(before, {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in Path(context["projectRoot"]).rglob("*") if path.is_file()})


if __name__ == "__main__":
    unittest.main()
