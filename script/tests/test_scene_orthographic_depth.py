"""Orthographic cards retain two-sided authored depth while typed tilt changes."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering"
HARNESS = r'''
import CoreGraphics
import Foundation
import simd
enum SceneRenderDescriptor {
    struct CameraDescriptor {
        var orthoWidth: Float? = 1920
        var orthoHeight: Float? = 1080
        var nearZ: Float = 0.01
        var farZ: Float = 10000
    }
}
@main enum Harness {
    static func main() throws {
        let camera = SceneRenderDescriptor.CameraDescriptor()
        let projection = SceneCameraProjection.viewProjection(
            camera: camera, viewportSize: CGSize(width: 1920, height: 1080)
        )
        let origin = SceneMatrix.translation(SIMD3<Float>(960, 540, 0))
        var depths: [Float] = []
        for angle: Float in [-0.3, 0, 0.3] {
            let model = origin * SceneMatrix.eulerXYZ(SIMD3(0, angle, 0))
            for x: Float in [-500, 500] {
                let clip = projection * model * SIMD4(x, 0, 0, 1)
                depths.append(clip.z / clip.w)
            }
        }
        let tooNear = projection * SIMD4<Float>(960, 540, 10001, 1)
        let tooFar = projection * SIMD4<Float>(960, 540, -10001, 1)
        let data = try JSONSerialization.data(withJSONObject: [
            "depths": depths, "outside": [tooNear.z, tooFar.z]
        ])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class OrthographicDepthTests(unittest.TestCase):
    def test_tilt_spans_both_sides_of_canvas_but_keeps_clip_limits(self):
        with tempfile.TemporaryDirectory(prefix="mwx-ortho-depth-") as directory:
            directory = Path(directory)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS)
            binary = directory / "test"
            compilation = subprocess.run([
                "xcrun", "swiftc", str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift"),
                str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Input/SceneCameraProjection.swift"), str(harness),
                "-o", str(binary)
            ], capture_output=True, text=True)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = json.loads(subprocess.check_output([str(binary)], text=True))
            self.assertEqual(len(result["depths"]), 6)
            self.assertTrue(all(0 < d < 1 for d in result["depths"]))
            self.assertAlmostEqual(result["depths"][2], 0.5, places=5)
            self.assertLess(result["outside"][0], 0)
            self.assertGreater(result["outside"][1], 1)


if __name__ == "__main__":
    unittest.main()
