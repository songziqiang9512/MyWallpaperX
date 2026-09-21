from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"

HARNESS = r'''
import Foundation
import simd

struct SceneResolvedMaterialTemplate {
    struct ExactValue {
        let componentBitPatterns: [UInt64]
    }

    enum UniformValue {
        case staticExact(ExactValue)
        case dynamic
    }

    struct UniformDeclaration {
        let name: String
        let value: UniformValue
    }

    let uniformDeclarations: [UniformDeclaration]
}

struct SceneResolvedMaterialCompiledVariant {
    struct ActiveUniform {
        let name: String
        let materialKeys: [String]
    }

    struct Stage {
        let source: String
    }

    struct PreparedShader {
        let vertex: Stage
    }

    let resolvedIntegerCombos: [String: Int]
    let activeUniforms: [String: ActiveUniform]
    let preparedShader: PreparedShader
}

struct SceneResolvedMaterialLaunchEnvelopeCapabilitySnapshot {
    let allEntriesReady: Bool
    let variants: [SceneResolvedMaterialCompiledVariant]
}

struct SceneResolvedMaterialVariants {
    let snapshot: SceneResolvedMaterialLaunchEnvelopeCapabilitySnapshot

    func launchEnvelopeCapabilitySnapshot()
        -> SceneResolvedMaterialLaunchEnvelopeCapabilitySnapshot {
        snapshot
    }
}

struct SceneResolvedMaterialExecutionCapabilityCatalog {
    struct MaterialKey: Hashable {
        let rawValue: String
    }

    struct MaterialCapability {
        let variants: SceneResolvedMaterialVariants
        let template: SceneResolvedMaterialTemplate
    }
}

enum SceneAuthoredShaderLexer {
    enum Stage {
        case vertex
    }

    struct Token {
        let text: String
    }

    struct Result {
        let diagnostics: [String]
        let tokens: [Token]
    }

    static func lex(source: String, stage: Stage) -> Result {
        _ = stage
        var tokens: [Token] = []
        var current = ""
        func flush() {
            if !current.isEmpty {
                tokens.append(Token(text: current))
                current.removeAll(keepingCapacity: true)
            }
        }
        for character in source {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                flush()
                if !character.isWhitespace {
                    tokens.append(Token(text: String(character)))
                }
            }
        }
        flush()
        return Result(diagnostics: [], tokens: tokens)
    }
}

@main
enum Harness {
    static let pointKeys = ["point0", "point1", "point2", "point3"]
    static let points = [
        SIMD2<Float>(0.10, 0.20),
        SIMD2<Float>(0.80, 0.20),
        SIMD2<Float>(0.90, 0.90),
        SIMD2<Float>(0.05, 0.80),
    ]

    static func material(
        rayMode: Int?,
        directDraw: Int = 1,
        source: String = "inverse(squareToQuad(u0, u1, u2, u3))",
        points: [SIMD2<Float>] = Harness.points,
        ready: Bool = true,
        variants: [[String: Int]]? = nil
    ) -> SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability {
        let declarations = zip(pointKeys, points).map { key, point in
            SceneResolvedMaterialTemplate.UniformDeclaration(
                name: key,
                value: .staticExact(.init(componentBitPatterns: [
                    Double(point.x).bitPattern,
                    Double(point.y).bitPattern,
                ]))
            )
        }
        let activeUniforms = Dictionary(uniqueKeysWithValues: zip(pointKeys, ["u0", "u1", "u2", "u3"]).map {
            key, name in
            (name, SceneResolvedMaterialCompiledVariant.ActiveUniform(
                name: name,
                materialKeys: [key]
            ))
        })
        var defaultCombos = ["DIRECTDRAW": directDraw]
        if let rayMode {
            defaultCombos["RAYMODE"] = rayMode
        }
        let comboMaps = variants ?? [defaultCombos]
        let compiledVariants = comboMaps.map { combos in
            SceneResolvedMaterialCompiledVariant(
                resolvedIntegerCombos: combos,
                activeUniforms: activeUniforms,
                preparedShader: .init(vertex: .init(source: source))
            )
        }
        return .init(
            variants: .init(snapshot: .init(
                allEntriesReady: ready,
                variants: compiledVariants
            )),
            template: .init(uniformDeclarations: declarations)
        )
    }

    static func result(_ contract: ScenePreparedDirectDrawOutputGeometry) -> [String: Any] {
        [
            "extent": contract.canvasExtentScale,
            "top": contract.normalizedContentTopInset,
        ]
    }

    static func main() throws {
        let cases: [(String, SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability)] = [
            ("ray0", material(rayMode: 0)),
            ("ray1", material(rayMode: 1)),
            ("ray2", material(rayMode: 2)),
            ("unsupportedRay", material(rayMode: 3)),
            ("missingRay", material(rayMode: nil)),
            ("mixedUnsupported", material(rayMode: nil, variants: [
                ["DIRECTDRAW": 1, "RAYMODE": 1],
                ["DIRECTDRAW": 1, "RAYMODE": 3],
            ])),
            ("wrongDirectDraw", material(rayMode: 1, directDraw: 0)),
            ("sourceUnproven", material(rayMode: 1, source: "v_TexCoord = u0;")),
            ("overscanRejected", material(
                rayMode: 1,
                points: [
                    SIMD2<Float>(-0.02, 0.20),
                    SIMD2<Float>(0.80, 0.20),
                    SIMD2<Float>(0.90, 0.90),
                    SIMD2<Float>(0.05, 0.80),
                ]
            )),
        ]
        var output: [String: Any] = [:]
        for (name, capability) in cases {
            let contract = SceneResolvedMaterialDirectDrawGeometryCompiler.compile(
                materials: [.init(rawValue: name): capability]
            )
            output[name] = result(contract)
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneResolvedMaterialDirectDrawGeometryCompilerTests(unittest.TestCase):
    def test_ray_modes_share_prepared_geometry_and_reject_unproven_routes(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-direct-draw-compiler-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "Harness"
            harness.write_text(HARNESS, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    str(SCENE / "Compilation/Material/ScenePreparedDirectDrawOutputGeometry.swift"),
                    str(SCENE / "Compilation/Material/SceneResolvedMaterialDirectDrawGeometryCompiler.swift"),
                    str(harness),
                    "-o", str(binary),
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)

        self.assertEqual(result["ray0"]["extent"], 0.5)
        self.assertEqual(result["ray1"]["extent"], 0.5)
        self.assertEqual(result["ray2"]["extent"], 0.5)
        self.assertAlmostEqual(result["ray0"]["top"], 0.2, places=6)
        self.assertAlmostEqual(result["ray1"]["top"], 0.2, places=6)
        self.assertAlmostEqual(result["ray2"]["top"], 0.2, places=6)
        for rejected in (
            "unsupportedRay",
            "missingRay",
            "mixedUnsupported",
            "wrongDirectDraw",
            "sourceUnproven",
            "overscanRejected",
        ):
            self.assertEqual(result[rejected]["extent"], 0.5)
            self.assertEqual(result[rejected]["top"], 0.0)


if __name__ == "__main__":
    unittest.main()
