#!/usr/bin/env python3
"""CPU contract gate for authored quad domains and public gizmo roles.

The production affine geometry is checked against fixed, self-authored numeric
oracles. Real polygon raster coverage and end-to-end Scene pixels are separate
GPU/App gates; this test does not claim either.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [SCENE / p for p in (
    "Format/SceneJSONValue.swift",
    "Compilation/Material/SceneEffectDefinition.swift",
    "Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
    "Rendering/Lighting/SceneAuthoredShaderLightingInputs.swift",
    "Rendering/Geometry/SceneMatrix.swift",
    "Rendering/Geometry/SceneDirectDrawOutputGeometry.swift",
)]

HARNESS = r'''
import Foundation
import simd

@main enum Harness {
    static func main() throws {
        var result: [String: Bool] = [:]
        func close(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool {
            simd_distance(a, b) < 0.001
        }
        let basis = SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: SceneMatrix.translation(SIMD3(400,700,0))
                * SceneMatrix.scale(SIMD3(0.14,0.14,1)),
            parallaxOffset: .zero, canvasSize: SIMD2(1800,1200))!
        func resolve(_ points: SceneShaderQuadCoordinates, _ frame: UInt64 = 31,
                     _ generation: UInt64 = 9) -> SceneDirectDrawOutputGeometry.Resolved? {
            SceneDirectDrawOutputGeometry.resolve(coordinates: points,
                canvasSize: SIMD2(1800,1200), squareUnitModelMatrix: basis,
                viewProjection: matrix_identity_float4x4,
                frameIndex: frame, generation: generation)
        }
        let unit = resolve(.unit)!
        result["unitPlacementPreserved"] = close(unit.outputModelViewProjection * SIMD4(0.25,-0.125,0,1),
                                                    basis * SIMD4(0.25,-0.125,0,1))
        result["unitCapturePreserved"] = close(unit.captureModelViewProjection * SIMD4(300,-150,0,1),
                                                  SIMD4(0.5,-0.25,0,1))
        let expanded = SceneShaderQuadCoordinates(p0: SIMD2(-0.25,-0.35),p1: SIMD2(1.25,-0.35),
                                                   p2: SIMD2(1.25,1.15),p3: SIMD2(-0.25,1.15))
        let e = resolve(expanded)!
        result["outsideUnitCapture"] = close(e.captureModelViewProjection * SIMD4(-900,1020,0,1),
                                                 SIMD4(-1,1,0,1))
            && close(e.captureModelViewProjection * SIMD4(900,-780,0,1),SIMD4(1,-1,0,1))
        result["expandedPlacement"] = close(e.outputModelViewProjection * SIMD4(0,0,0,1),
                                                SIMD4(400,683.2,0,1))
            && close(e.outputModelViewProjection * SIMD4(0.5,0.5,0,1),SIMD4(526,557.2,0,1))
        let nonrect = SceneShaderQuadCoordinates(p0: SIMD2(-0.25,-0.20),p1: SIMD2(1.30,-0.35),
                                                  p2: SIMD2(1.15,1.20),p3: SIMD2(0.05,0.95))
        let n = resolve(nonrect,32,10)!
        result["nonrectPlacement"] = close(n.outputModelViewProjection * SIMD4(0,0,0,1),
                                               SIMD4(404.2,687.4,0,1))
            && close(n.outputModelViewProjection * SIMD4(0.5,0.5,0,1),SIMD4(534.4,557.2,0,1))
        result["rawUVUnchanged"] = n.coordinates == nonrect
        result["logicalHeightAndEpoch"] = n.vertexInputSize == CGSize(width:1200,height:1200)
            && n.frameIndex == 32 && n.generation == 10
        result["effectSquareBasisUnchanged"] = close(n.squareUnitModelMatrix * SIMD4(0,0,0,1),
                                                        SIMD4(400,700,0,1))
        let mirrored = SceneShaderQuadCoordinates(p0: SIMD2(0,0),p1: SIMD2(-1,0),
                                                   p2: SIMD2(-1,1),p3: SIMD2(0,1))
        result["oppositeWindingAccepted"] = resolve(mirrored) != nil
        result["invalidRejected"] = resolve(.init(p0:.zero,p1:SIMD2(1,1),p2:SIMD2(1,0),p3:SIMD2(0,1))) == nil
            && resolve(.init(p0:.zero,p1:.zero,p2:SIMD2(1,1),p3:SIMD2(0,1))) == nil
            && resolve(.init(p0:SIMD2(.nan,0),p1:SIMD2(1,0),p2:SIMD2(1,1),p3:SIMD2(0,1))) == nil
            && resolve(.init(p0:SIMD2(-Float.greatestFiniteMagnitude,0),p1:SIMD2(Float.greatestFiniteMagnitude,0),
                             p2:SIMD2(1,1),p3:SIMD2(0,1))) == nil
        let parent = SceneMatrix.translation(SIMD3<Float>(51,72,3)) * SceneMatrix.rotationZ(0.3)
        let local = SceneMatrix.translation(SIMD3<Float>(-11,13,0)) * SceneMatrix.rotationZ(-0.5)
            * SceneMatrix.scale(SIMD3<Float>(-2,3,1))
        let world = parent * local
        let square = SceneDirectDrawOutputGeometry.modelMatrix(worldFrame:world,
            parallaxOffset:SIMD2(7,-9),canvasSize:SIMD2(1800,1200))!
        let transformed = SceneDirectDrawOutputGeometry.resolve(coordinates:nonrect,
            canvasSize:SIMD2(1800,1200),squareUnitModelMatrix:square,
            viewProjection:matrix_identity_float4x4,frameIndex:1,generation:1)!
        // N's raw AABB center=(30,90); existing square applies one Y reflection.
        let expected = world * SIMD4<Float>(30,-90,0,1) + SIMD4<Float>(7,-9,0,0)
        result["hierarchyMirrorParallaxOnce"] = close(transformed.outputModelViewProjection * SIMD4(0,0,0,1),expected)
        let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        func role(_ name:String) throws -> SceneEffectDefinition.PerspectiveUVRole {
            try SceneEffectDefinitionLoader().load(data:Data(contentsOf:root.appendingPathComponent(name+".json")),
                relativePath:name+".json").perspectiveUVRole
        }
        result["renamedPublicRole"] = try role("renamed") == .quad(materialKeys:["nw","ne","se","sw"])
        result["noRoleStaysUnit"] = try role("absent") == .absent
        result["competingRoleRejected"] = try role("duplicate") == .invalid
        result["incompleteRoleRejected"] = try role("incomplete") == .invalid
        print(String(data:try JSONSerialization.data(withJSONObject:result),encoding:.utf8)!)
    }
}
'''


class AuthoredDirectDrawDomainTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-authored-quad-cpu-") as directory:
            p = Path(directory)
            role = {"type": "EffectPerspectiveUV", "vars": dict(zip(
                ("p0", "p1", "p2", "p3"), ("nw", "ne", "se", "sw")))}
            fixtures = {"renamed": [role], "absent": [{"type": "OtherGizmo"}],
                        "duplicate": [role, role],
                        "incomplete": [{"type": "EffectPerspectiveUV", "vars": {"p0": "nw"}}]}
            for name, gizmos in fixtures.items():
                (p / (name + ".json")).write_text(json.dumps({"passes": [], "gizmos": gizmos}))
            (p / "Main.swift").write_text(HARNESS)
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(p / "clang-cache")
            env["SWIFT_MODULECACHE_PATH"] = str(p / "swift-cache")
            run = subprocess.run(["xcrun", "swiftc", *map(str, SOURCES), str(p / "Main.swift"),
                                  "-o", str(p / "run")], capture_output=True, text=True, env=env, timeout=120)
            if run.returncode:
                raise RuntimeError(run.stderr)
            run = subprocess.run([str(p / "run"), str(p)], capture_output=True, text=True,
                                 env=env, check=True, timeout=20)
            cls.result = json.loads(run.stdout)

    def test_production_geometry_and_role_contract(self):
        self.assertTrue(self.result)
        for name, passed in self.result.items():
            with self.subTest(contract=name):
                self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
