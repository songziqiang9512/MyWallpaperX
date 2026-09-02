#!/usr/bin/env python3
"""Shared authored scalar/vector built-in compiler canonicalization gate."""

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
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneAuthoredShaderBackendCanonicalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderBooleanScalarArithmeticNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderFloatingModuloNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderScalarArithmeticNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderScalarBuiltInLiteralNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderScalarVectorBroadcastNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderInactiveBuiltinOverloadCanonicalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderMutableFragmentVaryingNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderTextureSamplingNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderVaryingNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderDirectFunctionVectorArgumentNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderSourceNormalizer.swift",
]
GLSLANG = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
)


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let checks: [String: Bool]
    let normalizedVertex: String?
    let normalizedFragment: String?
}

@main
private struct ScalarVectorBuiltInHarness {
    private static let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() {
        gl_Position = vec4(a_Position, 1.0);
        v_TexCoord = a_TexCoord;
    }
    """

    private static func fragment(
        _ statement: String,
        declarations: [String] = [],
        helpers: [String] = []
    ) -> String {
        ([
            "varying vec2 v_TexCoord;",
            "uniform sampler2D g_Texture0;",
        ] + declarations + helpers + [
            "void main() {",
            "    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);",
            "    \(statement)",
            "}",
        ]).joined(separator: "\n")
    }

    private static func canonical(
        _ statement: String,
        declarations: [String] = [],
        helpers: [String] = []
    ) -> String {
        SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: vertex,
            fragment: fragment(
                statement,
                declarations: declarations,
                helpers: helpers
            )
        ).fragment
    }

    static func main() throws {
        let literalFirst = canonical(
            "gl_FragColor = vec4(max(0, albedo.rgb), albedo.a);"
        )
        let vec2 = canonical(
            "albedo.rg = max(0, albedo.rg); gl_FragColor = albedo;"
        )
        let vec4 = canonical(
            "gl_FragColor = max(0, albedo);"
        )
        let vertexZero = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: vertex.replacingOccurrences(
                of: "v_TexCoord = a_TexCoord;",
                with: "v_TexCoord = max(0, a_TexCoord);"
            ),
            fragment: fragment("gl_FragColor = albedo;")
        ).vertex
        let literalSecond = canonical(
            "gl_FragColor = vec4(max(albedo.rgb, 0), albedo.a);"
        )
        let minZero = canonical(
            "gl_FragColor = vec4(min(0, albedo.rgb), albedo.a);"
        )
        let floatZero = canonical(
            "gl_FragColor = vec4(max(0.0, albedo.rgb), albedo.a);"
        )
        let otherInteger = canonical(
            "gl_FragColor = vec4(max(1, albedo.rgb), albedo.a);"
        )
        let scalarFloatFirst = canonical(
            "float value = max(1, g_Ratio.x / g_Ratio.y); gl_FragColor = vec4(value);",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let scalarFloatSecond = canonical(
            "float value = max(g_Ratio.x / g_Ratio.y, 1); gl_FragColor = vec4(value);",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let scalarFloatMin = canonical(
            "float value = min(2, g_Ratio.x / g_Ratio.y); gl_FragColor = vec4(value);",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let scalarInteger = canonical(
            "int value = max(1, lower); gl_FragColor = vec4(float(value));",
            declarations: ["uniform int lower;"]
        )
        let scalarFloatLiteral = canonical(
            "float value = max(1.0, g_Ratio.x); gl_FragColor = vec4(value);",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let scalarUnknownCall = canonical(
            "float value = max(1, abs(g_Ratio.x)); gl_FragColor = vec4(value);",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let scalarStepMin = canonical(
            "float value = min(1, smoothstep(0, g_Ratio.x, g_Ratio.y) + step(g_Ratio.x, g_Ratio.y)); gl_FragColor = vec4(value);",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let discreteMask = canonical(
            "int value = max(lower, step(g_Ratio.x, g_Ratio.y) * step(-g_Ratio.x, g_Ratio.y)); gl_FragColor = vec4(float(value));",
            declarations: ["uniform int lower;", "uniform vec2 g_Ratio;"]
        )
        let directDiscreteMask = canonical(
            "int value = step(g_Ratio.x, g_Ratio.y); gl_FragColor = vec4(float(value));",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let directDiscreteArithmeticMask = canonical(
            "int value = step(1 - g_Ratio.x, g_Ratio.y); gl_FragColor = vec4(float(value));",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let directVectorStepMask = canonical(
            "int value = step(g_Ratio, g_Ratio.y); gl_FragColor = vec4(float(value));",
            declarations: ["uniform vec2 g_Ratio;"]
        )
        let nonDiscreteMask = canonical(
            "int value = max(lower, g_Ratio.x); gl_FragColor = vec4(float(value));",
            declarations: ["uniform int lower;", "uniform vec2 g_Ratio;"]
        )
        let userDefinedStepMask = canonical(
            "int value = max(lower, step(g_Ratio.x, g_Ratio.y)); gl_FragColor = vec4(float(value));",
            declarations: ["uniform int lower;", "uniform vec2 g_Ratio;"],
            helpers: ["float step(float edge, float value) { return value; }"]
        )
        let userDefinedDirectStepMask = canonical(
            "int value = step(g_Ratio.x, g_Ratio.y); gl_FragColor = vec4(float(value));",
            declarations: ["uniform vec2 g_Ratio;"],
            helpers: ["float step(float edge, float value) { return value; }"]
        )
        let compound = canonical(
            "gl_FragColor = vec4(max(0 + 0, albedo.rgb), albedo.a);"
        )
        let integerVariable = canonical(
            "gl_FragColor = vec4(max(lower, albedo.rgb), albedo.a);",
            declarations: ["uniform int lower;"]
        )
        let vectorVector = canonical(
            "gl_FragColor = vec4(max(albedo.rgb, vec3(0.0)), albedo.a);"
        )
        let scalarScalar = canonical(
            "float value = max(0.0, 1.0); gl_FragColor = vec4(value);"
        )
        let integerVector = canonical(
            "ivec3 value = max(0, ivec3(1)); gl_FragColor = vec4(value);"
        )
        let vectorConstructor = canonical(
            "gl_FragColor = vec4(max(0, vec3(albedo.r)), albedo.a);"
        )
        let userDefined = canonical(
            "gl_FragColor = vec4(max(0, albedo.rgb), albedo.a);",
            helpers: [
                "vec3 max(int lower, vec3 value) { return value; }",
            ]
        )
        let powScalarExponent = canonical(
            "albedo.rgb = pow(albedo.rgb, 2.2 / 2.2); gl_FragColor = albedo;"
        )
        let powUniformExponent = canonical(
            "albedo.rgb = pow(albedo.rgb, 1.0 / g_Exponent); gl_FragColor = albedo;",
            declarations: ["uniform float g_Exponent;"]
        )
        let powVectorExponent = canonical(
            "albedo.rgb = pow(albedo.rgb, g_Exponent); gl_FragColor = albedo;",
            declarations: ["uniform vec3 g_Exponent;"]
        )
        let scalarPow = canonical(
            "float value = pow(albedo.r, 2.2); gl_FragColor = vec4(value);"
        )
        let userDefinedPow = canonical(
            "albedo.rgb = pow(albedo.rgb, 2.2); gl_FragColor = albedo;",
            helpers: [
                "vec3 pow(vec3 value, float exponent) { return value; }",
            ]
        )

        let compileVertex = vertex
            .replacingOccurrences(
                of: "varying vec2 v_TexCoord;",
                with: "varying vec2 v_TexCoord;\nuniform vec4 g_Texture0Resolution;"
            )
            .replacingOccurrences(
                of: "void main() {",
                with: "vec2 fixtureCoordinates(vec2 value, float amount) { return value * amount; }\nvoid main() {"
            )
            .replacingOccurrences(
                of: "gl_Position = vec4(a_Position, 1.0);",
                with: "float xScale = max(1, g_Texture0Resolution.x / g_Texture0Resolution.y);\n"
                    + "        gl_Position = vec4(a_Position * xScale, 1.0);"
            )
            .replacingOccurrences(
                of: "v_TexCoord = a_TexCoord;",
                with: "vec2 limited = max(0, a_TexCoord);\n"
                    + "        v_TexCoord = fixtureCoordinates(g_Texture0Resolution, 0.5) + limited * 0.0;"
            )
        let compileFragment = fragment(
            "int mask = max(lower, step(g_Ratio.x, g_Ratio.y) * step(-g_Ratio.x, g_Ratio.y));\n"
                + "    int directMask = step(1 - g_Ratio.x, g_Ratio.y);\n"
                + "    float weight = min(1, smoothstep(0, g_Ratio.x, g_Ratio.y) + step(g_Ratio.x, g_Ratio.y));\n"
                + "    vec2 broadcast = g_Ratio.x * g_Ratio.y;\n"
                + "    broadcast *= 1.0 / g_Ratio4;\n"
                + "    albedo.rgb = pow(albedo.rgb, 2.2 / 2.2);\n"
                + "    gl_FragColor = vec4(max(0, albedo.rgb) + vec3(broadcast, weight) * float(mask), albedo.a);",
            declarations: [
                "uniform int lower;",
                "uniform vec2 g_Ratio;",
                "uniform vec4 g_Ratio4;",
            ]
        )
        let firstPair = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: compileVertex,
            fragment: compileFragment
        )
        let secondPair = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: firstPair.vertex,
            fragment: firstPair.fragment
        )
        let normalized: SceneGenericShaderSourceNormalizer.Pair?
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: firstPair.vertex,
            fragmentSource: firstPair.fragment,
            maximumStageSourceBytes: 64 * 1_024
        ) {
        case let .success(pair): normalized = pair
        case .failure: normalized = nil
        }
        let output = Output(
            checks: [
                "literalFirst": literalFirst.contains(
                    "max(vec3(0.0), albedo.rgb)"
                ),
                "vec2": vec2.contains(
                    "max(vec2(0.0), albedo.rg)"
                ),
                "vec4": vec4.contains("max(vec4(0.0), albedo)"),
                "vertex": vertexZero.contains(
                    "max(vec2(0.0), a_TexCoord)"
                ),
                "literalSecondPreserved": literalSecond.contains(
                    "max(albedo.rgb, 0)"
                ) && !literalSecond.contains("vec3(0.0)"),
                "minPreserved": minZero.contains(
                    "min(0, albedo.rgb)"
                ),
                "floatZeroPreserved": floatZero.contains(
                    "max(0.0, albedo.rgb)"
                ) && !floatZero.contains("vec3(0.0)"),
                "otherIntegerPreserved": otherInteger.contains(
                    "max(1, albedo.rgb)"
                ),
                "scalarFloatFirst": scalarFloatFirst.contains(
                    "max(1.0, g_Ratio.x / g_Ratio.y)"
                ),
                "scalarFloatSecond": scalarFloatSecond.contains(
                    "max(g_Ratio.x / g_Ratio.y, 1.0)"
                ),
                "scalarFloatMin": scalarFloatMin.contains(
                    "min(2.0, g_Ratio.x / g_Ratio.y)"
                ),
                "scalarIntegerPreserved": scalarInteger.contains(
                    "max(1, lower)"
                ) && !scalarInteger.contains("max(1.0, lower)"),
                "scalarFloatLiteralPreserved": scalarFloatLiteral.contains(
                    "max(1.0, g_Ratio.x)"
                ) && !scalarFloatLiteral.contains("max(1.0.0, g_Ratio.x)"),
                "scalarUnknownCallPreserved": scalarUnknownCall.contains(
                    "max(1, abs(g_Ratio.x))"
                ) && !scalarUnknownCall.contains("max(1.0, abs(g_Ratio.x))"),
                "scalarStepMin": scalarStepMin.contains(
                    "min(1.0, smoothstep(0, g_Ratio.x, g_Ratio.y) + step(g_Ratio.x, g_Ratio.y))"
                ),
                "discreteMask": discreteMask.contains(
                    "max(lower, int(step(g_Ratio.x, g_Ratio.y) * step(-g_Ratio.x, g_Ratio.y)))"
                ),
                "directDiscreteMask": directDiscreteMask.contains(
                    "int value = int(step(g_Ratio.x, g_Ratio.y))"
                ),
                "directDiscreteArithmeticMask": directDiscreteArithmeticMask.contains(
                    "int value = int(step(1 - g_Ratio.x, g_Ratio.y))"
                ),
                "directVectorStepMaskPreserved": directVectorStepMask.contains(
                    "int value = step(g_Ratio, g_Ratio.y)"
                ) && !directVectorStepMask.contains("int(step("),
                "nonDiscreteMaskPreserved": nonDiscreteMask.contains(
                    "max(lower, g_Ratio.x)"
                ) && !nonDiscreteMask.contains("int(g_Ratio.x)"),
                "userDefinedStepMaskPreserved": userDefinedStepMask.contains(
                    "max(lower, step(g_Ratio.x, g_Ratio.y))"
                ) && !userDefinedStepMask.contains("int(step("),
                "userDefinedDirectStepMaskPreserved": userDefinedDirectStepMask.contains(
                    "int value = step(g_Ratio.x, g_Ratio.y)"
                ) && !userDefinedDirectStepMask.contains("int(step("),
                "compoundPreserved": compound.contains(
                    "max(0 + 0, albedo.rgb)"
                ) && !compound.contains("vec3(0.0)"),
                "integerVariablePreserved": integerVariable.contains(
                    "max(lower, albedo.rgb)"
                ) && !integerVariable.contains("vec3(lower)"),
                "vectorVectorPreserved": vectorVector.contains(
                    "max(albedo.rgb, vec3(0.0))"
                ),
                "scalarScalarPreserved": scalarScalar.contains(
                    "max(0.0, 1.0)"
                ),
                "integerVectorPreserved": integerVector.contains(
                    "max(0, ivec3(1))"
                ),
                "vectorConstructorPreserved": vectorConstructor.contains(
                    "max(0, vec3(albedo.r))"
                ),
                "userDefinedPreserved": userDefined.contains(
                    "max(0, albedo.rgb)"
                ) && !userDefined.contains("max(vec3(0.0), albedo.rgb)"),
                "powScalarExponent": powScalarExponent.contains(
                    "pow(albedo.rgb, vec3(2.2 / 2.2))"
                ),
                "powUniformExponent": powUniformExponent.contains(
                    "pow(albedo.rgb, vec3(1.0 / g_Exponent))"
                ),
                "powVectorExponentPreserved": powVectorExponent.contains(
                    "pow(albedo.rgb, g_Exponent)"
                ) && !powVectorExponent.contains("vec3(g_Exponent)"),
                "scalarPowPreserved": scalarPow.contains(
                    "pow(albedo.r, 2.2)"
                ) && !scalarPow.contains("pow(albedo.r, vec"),
                "userDefinedPowPreserved": userDefinedPow.contains(
                    "pow(albedo.rgb, 2.2)"
                ) && !userDefinedPow.contains("pow(albedo.rgb, vec3(2.2))"),
                "idempotent": firstPair == secondPair,
                "normalized": normalized != nil,
                "normalizedScalarFloatMax": normalized?.vertex.contains(
                    "max(1.0, g_Texture0Resolution.x / g_Texture0Resolution.y)"
                ) == true,
                "normalizedUserFunctionArgument": normalized?.vertex.contains(
                    "fixtureCoordinates(g_Texture0Resolution.xy, 0.5)"
                ) == true,
                "normalizedDiscreteMask": normalized?.fragment.contains(
                    "max(lower, int(step(g_Ratio.x, g_Ratio.y) * step(-g_Ratio.x, g_Ratio.y)))"
                ) == true,
                "normalizedDirectDiscreteMask": normalized?.fragment.contains(
                    "int directMask = int(step(1 - g_Ratio.x, g_Ratio.y))"
                ) == true,
                "normalizedScalarStepMin": normalized?.fragment.contains(
                    "min(1.0, smoothstep(0, g_Ratio.x, g_Ratio.y) + step(g_Ratio.x, g_Ratio.y))"
                ) == true,
                "normalizedScalarVectorBroadcast": normalized?.fragment.contains(
                    "vec2 broadcast = vec2(g_Ratio.x * g_Ratio.y);"
                ) == true,
                "normalizedCompoundVectorNarrowing": normalized?.fragment.contains(
                    "broadcast *= (1.0 / g_Ratio4).xy;"
                ) == true,
                "normalizedPowScalarExponent": normalized?.fragment.contains(
                    "pow(albedo.rgb, vec3(2.2 / 2.2))"
                ) == true,
            ],
            normalizedVertex: normalized?.vertex,
            normalizedFragment: normalized?.fragment
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneShaderScalarVectorBuiltInCanonicalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "ScalarVectorBuiltInHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "scalar-vector-built-in-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(
            build_root / "clang-module-cache"
        )
        environment["SWIFT_MODULECACHE_PATH"] = str(
            build_root / "swift-module-cache"
        )
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
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def test_canonicalizes_only_source_proven_max_zero_vector_form(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertEqual(
            {name for name, passed in output["checks"].items() if not passed},
            set(),
        )

    def test_literal_zero_request_links_with_bundled_glslang(self) -> None:
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertIsNotNone(output["normalizedVertex"])
        self.assertIsNotNone(output["normalizedFragment"])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            vertex = root / "author.vert"
            fragment = root / "author.frag"
            vertex.write_text(output["normalizedVertex"], encoding="utf-8")
            fragment.write_text(output["normalizedFragment"], encoding="utf-8")
            linked = subprocess.run(
                [
                    str(GLSLANG),
                    "-V",
                    "--auto-map-bindings",
                    "--auto-map-locations",
                    "-l",
                    str(vertex),
                    str(fragment),
                ],
                cwd=root,
                capture_output=True,
                text=True,
            )
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)


if __name__ == "__main__":
    unittest.main()
