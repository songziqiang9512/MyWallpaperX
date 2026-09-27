#!/usr/bin/env python3
"""Real scene Bloom GPU output: zero contribution, reuse and positive halos."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition'
HARNESS = r'''
import Foundation
import Metal

@main enum Harness {
  static func main() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      fatalError("Metal unavailable")
    }
    let bloom = SceneBloomPostProcess()
    func render(
      _ w: Int, _ h: Int, strength: Float, threshold: Float, enabled: Bool = true, phase: Int = 0
    ) -> [String: Any] {
      var bytes = [UInt8](repeating: 0, count: w * h * 4)
      for y in 0..<h {
        for x in 0..<w {
          let i = (y * w + x) * 4
          let high = abs(x - w / 2 - phase) < w / 12 && abs(y - h / 3) < h / 10
          bytes[i] = high ? 255 : UInt8((x * 37 + y * 13 + phase) % 100)
          bytes[i + 1] = high ? 230 : UInt8((x * 17 + y * 23 + phase) % 80)
          bytes[i + 2] = high ? 250 : UInt8((x * 7 + y * 43 + phase) % 120)
          bytes[i + 3] = UInt8(100 + (x + y) % 156)
        }
      }
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
      desc.storageMode = .shared
      desc.usage = [.shaderRead, .renderTarget]
      let source = device.makeTexture(descriptor: desc)!
      bytes.withUnsafeBytes {
        source.replace(
          region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!,
          bytesPerRow: w * 4)
      }
      let cb = queue.makeCommandBuffer()!
      let encoded = bloom.encode(
        configuration: .init(
          enabled: enabled, strength: strength, threshold: threshold, tint: SIMD3(1, 1, 1)),
        source: source, commandBuffer: cb)
      cb.commit()
      cb.waitUntilCompleted()
      precondition(cb.status == .completed && cb.error == nil)
      var output = [UInt8](repeating: 0, count: bytes.count)
      output.withUnsafeMutableBytes {
        source.getBytes(
          $0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
      }
      var changed = 0
      var alphaChanges = 0
      var darkened = 0
      var maxDelta = 0
      for i in bytes.indices {
        let delta = Int(output[i]) - Int(bytes[i])
        if delta != 0 {
          if i % 4 == 3 {
            alphaChanges += 1
          } else {
            changed += 1
            if delta < 0 { darkened += 1 }
            maxDelta = max(maxDelta, abs(delta))
          }
        }
      }
      return [
        "encoded": encoded, "changedRGB": changed, "changedAlpha": alphaChanges,
        "darkened": darkened, "maxDelta": maxDelta,
      ]
    }
    var results: [String: Any] = [:]
    for (name, w, h) in [("small", 237, 149), ("large", 3024, 1964), ("tiny", 3, 2)] {
      results[name + "Zero"] = render(w, h, strength: 0, threshold: 1)
      results[name + "Threshold"] = render(w, h, strength: 1, threshold: 1)
      results[name + "Disabled"] = render(w, h, strength: 1, threshold: 0.3, enabled: false)
    }
    results["positive"] = render(400, 240, strength: 1, threshold: 0.3)
    results["reuseZero"] = render(400, 240, strength: 0, threshold: 0, phase: 13)
    results["reusePositive"] = render(400, 240, strength: 1, threshold: 0.3, phase: 13)
    print(String(data: try JSONSerialization.data(withJSONObject: results), encoding: .utf8)!)
  }
}
'''

class SceneBloomPostProcessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="mwx-bloom-gpu-") as directory:
            folder = Path(directory)
            (folder / "Main.swift").write_text(HARNESS)
            commands = [
                ["xcrun", "-sdk", "macosx", "metal", "-c",
                 str(SCENE / "SceneBloomPostProcess.metal"), "-o", str(folder / "bloom.air")],
                ["xcrun", "-sdk", "macosx", "metallib", str(folder / "bloom.air"),
                 "-o", str(folder / "default.metallib")],
                ["swiftc", str(SCENE / "SceneBloomPostProcess.swift"),
                 str(folder / "Main.swift"), "-o", str(folder / "run")],
            ]
            for command in commands:
                subprocess.run(command, capture_output=True, text=True, check=True, timeout=120)
            result = subprocess.run([str(folder / "run")], capture_output=True,
                                    text=True, check=True, timeout=30)
            cls.result = json.loads(result.stdout)

    def test_zero_contribution_and_disabled_are_pixel_identical(self):
        for name, values in self.result.items():
            if name.endswith(("Zero", "Threshold", "Disabled")):
                with self.subTest(case=name):
                    self.assertEqual(values["encoded"], not name.endswith("Disabled"))
                    self.assertEqual(values["changedRGB"], 0)
                    self.assertEqual(values["changedAlpha"], 0)

    def test_positive_bloom_and_reuse_add_light_without_changing_alpha(self):
        for name in ["positive", "reusePositive"]:
            self.assertTrue(self.result[name]["encoded"])
            self.assertGreater(self.result[name]["changedRGB"], 0)
            self.assertEqual(self.result[name]["darkened"], 0)
            self.assertEqual(self.result[name]["changedAlpha"], 0)


if __name__ == "__main__":
    unittest.main()
