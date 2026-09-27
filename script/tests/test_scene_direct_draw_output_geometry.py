#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/ScenePreparedDirectDrawOutputGeometry.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneDirectDrawOutputGeometry.swift",
]


HARNESS = r'''
import Foundation
import simd

@main
enum Harness {
    static func close(_ lhs: SIMD4<Float>, _ rhs: SIMD4<Float>) -> Bool {
        simd_distance(lhs, rhs) < 0.001
    }

    static func main() throws {
        let centered = ScenePreparedDirectDrawOutputGeometry.centeredHalfCanvas
        let aligned = ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(0.57282, 0.19584),
                SIMD2<Float>(0.38640, 0.19475),
                SIMD2<Float>(0.21953, 0.83065),
                SIMD2<Float>(0.76299, 0.83838),
            ])!
        let extent = SceneDirectDrawOutputGeometry.baseExtent(
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: aligned
        )
        let world = SceneMatrix.translation(SIMD3<Float>(100, 200, 0))
            * SceneMatrix.rotationZ(.pi / 2)
            * SceneMatrix.scale(SIMD3<Float>(2, 3, 1))
        let centeredModel = SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: world,
            parallaxOffset: SIMD2<Float>(5, -7),
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: centered
        )
        let alignedModel = SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: world,
            parallaxOffset: SIMD2<Float>(5, -7),
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: aligned
        )
        let preservesExtent = centeredModel.flatMap { centeredMatrix in
            alignedModel.map { alignedMatrix in
            let centeredWidth = centeredMatrix * SIMD4<Float>(0.5, 0, 0, 1)
                - centeredMatrix * SIMD4<Float>(-0.5, 0, 0, 1)
            let alignedWidth = alignedMatrix * SIMD4<Float>(0.5, 0, 0, 1)
                - alignedMatrix * SIMD4<Float>(-0.5, 0, 0, 1)
            let centeredHeight = centeredMatrix * SIMD4<Float>(0, 0.5, 0, 1)
                - centeredMatrix * SIMD4<Float>(0, -0.5, 0, 1)
            let alignedHeight = alignedMatrix * SIMD4<Float>(0, 0.5, 0, 1)
                - alignedMatrix * SIMD4<Float>(0, -0.5, 0, 1)
            return close(centeredWidth, alignedWidth)
                && close(centeredHeight, alignedHeight)
            }
        } ?? false
        let alignsActiveTop = centeredModel.flatMap { centeredMatrix in
            alignedModel.map { alignedMatrix in
            let originalCarrierTop = centeredMatrix
                * SIMD4<Float>(0, 0.5, 0, 1)
            let authoredActiveTop = alignedMatrix
                * SIMD4<Float>(0, 0.5 - aligned.normalizedContentTopInset, 0, 1)
            return close(originalCarrierTop, authoredActiveTop)
            }
        } ?? false
        let invalid = SceneDirectDrawOutputGeometry.baseExtent(
            canvasSize: SIMD2<Float>(.nan, 2160),
            contract: aligned
        ) == nil && SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: SceneMatrix.identity(),
            parallaxOffset: .zero,
            canvasSize: SIMD2<Float>(0, 2160),
            contract: aligned
        ) == nil && SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: SceneMatrix.identity(),
            parallaxOffset: .zero,
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: .init(
                canvasExtentScale: 0.5,
                normalizedContentTopInset: 0.75
            )
        ) == nil && ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
                SIMD2<Float>(1, 1), SIMD2<Float>(1.2, 1),
            ]) == nil
        let borderOverscan = ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(-0.00204, 0.22119),
                SIMD2<Float>(0.60427, 0.21922),
                SIMD2<Float>(0.80427, 0.76922),
                SIMD2<Float>(0.20427, 0.76922),
            ]) != nil
        let excessiveOverscan = ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(-0.02, 0.22119),
                SIMD2<Float>(0.60427, 0.21922),
                SIMD2<Float>(0.80427, 0.76922),
                SIMD2<Float>(0.20427, 0.76922),
            ]) == nil
        let result: [String: Bool] = [
            "halfCanvasExtent": extent == SIMD2<Float>(1920, 1080),
            "topAlignmentPreservesExtent": preservesExtent,
            "authoredActiveTopMatchesOriginalCarrierTop": alignsActiveTop,
            "invalidRejected": invalid,
            "borderOverscanAccepted": borderOverscan,
            "excessiveOverscanRejected": excessiveOverscan,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


COMPILER_HARNESS = r'''
import Foundation
import simd

// Standalone catalog input shims; lexer, geometry compiler and matrix execution
// below are production code. Full catalog preparation is exercised by App runs.
struct SceneResolvedMaterialTemplate {
    struct Scalar { let componentBitPatterns: [UInt64] }
    enum Value { case staticExact(Scalar), dynamic }
    struct Declaration { let name: String; let value: Value }
    let uniformDeclarations: [Declaration]
}
struct SceneResolvedMaterialCompiledVariant {
    struct Uniform { let name: String; let materialKeys: [String] }
    struct Source { let source: String }
    struct Prepared { let vertex: Source }
    let resolvedIntegerCombos: [String: Int]
    let activeUniforms: [String: Uniform]
    let preparedShader: Prepared
}
enum SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias MaterialKey = Int
    struct Variants {
        let allEntriesReady: Bool
        let variants: [SceneResolvedMaterialCompiledVariant]
        func launchEnvelopeCapabilitySnapshot() -> Self { self }
    }
    struct MaterialCapability {
        let template: SceneResolvedMaterialTemplate
        let variants: Variants
    }
}
@main enum Harness {
    static func main() throws {
        typealias Catalog = SceneResolvedMaterialExecutionCapabilityCatalog
        func prepared(_ modes: [Int], dynamic: Bool = false, ready: Bool = true,
                      source: String = "inverse(squareToQuad(p0,p1,p2,p3))", direct: Int = 1
        ) -> Catalog.MaterialCapability {
            let points: [[Double]] = [[0.75,0.25],[0.75,0.75],[0.25,0.75],[0.25,0.25]]
            let declarations = points.enumerated().map { index, point in
                SceneResolvedMaterialTemplate.Declaration(name:"point\(index)",
                    value: dynamic ? .dynamic : .staticExact(.init(componentBitPatterns:point.map(\.bitPattern))))
            }
            let uniforms = Dictionary(uniqueKeysWithValues:(0..<4).map { index in
                ("p\(index)",SceneResolvedMaterialCompiledVariant.Uniform(name:"p\(index)",materialKeys:["point\(index)"]))
            })
            return .init(template:.init(uniformDeclarations:declarations), variants:.init(allEntriesReady:ready,
                variants:modes.map { mode in .init(resolvedIntegerCombos:["DIRECTDRAW":direct,"RAYMODE":mode],
                    activeUniforms:uniforms,preparedShader:.init(vertex:.init(source:source))) }))
        }
        func compile(_ material: Catalog.MaterialCapability) -> ScenePreparedDirectDrawOutputGeometry {
            SceneResolvedMaterialDirectDrawGeometryCompiler.compile(materials:[0:material])
        }
        let world=SceneMatrix.translation(SIMD3<Float>(231,417,9))
            * SceneMatrix.rotationZ(0.37) * SceneMatrix.scale(SIMD3<Float>(3,2,1))
        let offset=SIMD2<Float>(11,-7)
        func center(_ geometry: ScenePreparedDirectDrawOutputGeometry) -> [Float] {
            let matrix=SceneDirectDrawOutputGeometry.modelMatrix(worldFrame:world,parallaxOffset:offset,
                canvasSize:SIMD2<Float>(3840,2160),contract:geometry)!
            let value=matrix * SIMD4<Float>(0,0,0,1);return [value.x,value.y,value.z]
        }
        let centered=ScenePreparedDirectDrawOutputGeometry.centeredHalfCanvas
        let result:[String:Any] = [
            "radialCenter":center(compile(prepared([1]))),
            "cornerCenter":center(compile(prepared([2]))),
            "mixedCenter":center(compile(prepared([0,1]))),
            "linearInset":compile(prepared([0])).normalizedContentTopInset,
            "dynamicCentered":compile(prepared([0],dynamic:true)) == centered,
            "notReadyCentered":compile(prepared([0],ready:false)) == centered,
            "unprovenCentered":compile(prepared([0],source:"unrelated(p0,p1,p2,p3)")) == centered,
            "nonDirectCentered":compile(prepared([0],direct:0)) == centered,
            "unknownCentered":compile(prepared([9])) == centered,
            "linearRadialMaterialsCentered":SceneResolvedMaterialDirectDrawGeometryCompiler.compile(materials:[0:prepared([0]),1:prepared([1])]) == centered,
            "linearCornerMaterialsCentered":SceneResolvedMaterialDirectDrawGeometryCompiler.compile(materials:[0:prepared([0]),1:prepared([2])]) == centered,
            "linearMixedMaterialsCentered":SceneResolvedMaterialDirectDrawGeometryCompiler.compile(materials:[0:prepared([0]),1:prepared([0,1])]) == centered,
            "linearWithNonDirectInset":SceneResolvedMaterialDirectDrawGeometryCompiler.compile(materials:[0:prepared([0]),1:prepared([0],direct:0)]).normalizedContentTopInset,
            "multipleMaterialsCentered":SceneResolvedMaterialDirectDrawGeometryCompiler.compile(materials:[0:prepared([0]),1:prepared([0])]) == centered
        ]
        print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''


class SceneDirectDrawOutputGeometryTests(unittest.TestCase):
    def test_radial_and_corner_keep_authored_center_while_linear_retains_alignment(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        extra = [SCENE_ROOT / "Compilation/ShaderContract/SceneShaderSourceGraph.swift",
                 SCENE_ROOT / "Compilation/ShaderContract/SceneShaderContract.swift",
                 SCENE_ROOT / "Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
                 SCENE_ROOT / "Format/SceneJSONValue.swift",
                 SCENE_ROOT / "Compilation/ShaderFrontend/SceneAuthoredShaderFrontendModel.swift",
                 SCENE_ROOT / "Compilation/ShaderFrontend/SceneAuthoredShaderLexer.swift",
                 SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialDirectDrawGeometryCompiler.swift"]
        with tempfile.TemporaryDirectory(prefix="scene-direct-draw-compiler-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            harness.write_text(COMPILER_HARNESS, encoding="utf-8")
            binary = temporary / "probe"
            built = subprocess.run(["swiftc", "-parse-as-library", *(str(p) for p in SOURCES + extra),
                                    str(harness), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            output = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        result = json.loads(output.stdout)
        for name in ("radialCenter", "cornerCenter", "mixedCenter"):
            with self.subTest(profile=name):
                for actual, expected in zip(result[name], [242, 410, 9]):
                    self.assertAlmostEqual(actual, expected, places=3)
        self.assertAlmostEqual(result["linearInset"], 0.25)
        self.assertAlmostEqual(result["linearWithNonDirectInset"], 0.25)
        for name, value in result.items():
            if name.endswith("Centered"):
                with self.subTest(boundary=name):
                    self.assertTrue(value, name)

    def test_prepared_top_alignment_preserves_half_canvas_scale(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="scene-direct-draw-output-geometry-"
        ) as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-direct-draw-output-geometry"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
