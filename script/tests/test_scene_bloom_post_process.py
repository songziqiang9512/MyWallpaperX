#!/usr/bin/env python3
"""Real scene Bloom GPU output: zero contribution, reuse and positive halos."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_binding_program import SWIFT_SOURCES

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition'
FAULT_HEADER = r'''
#import <Metal/Metal.h>
void MWXArmEncoderFault(id<MTLCommandBuffer> buffer, NSUInteger index);
NSUInteger MWXEncoderAttempts(void);
void MWXArmPipelineFault(id<MTLDevice> device, NSUInteger index);
NSUInteger MWXPipelineAttempts(void);
'''
FAULT_SOURCE = r'''
#import "Fault.h"
#import <objc/runtime.h>
static id faultBuffer;
static NSUInteger faultIndex, attempts;
static IMP original;
static id faultEncoder(id receiver, SEL selector, id descriptor) {
    if (receiver == faultBuffer && ++attempts == faultIndex) return nil;
    return ((id (*)(id, SEL, id))original)(receiver, selector, descriptor);
}
void MWXArmEncoderFault(id<MTLCommandBuffer> buffer, NSUInteger index) {
    if (!original) {
        Method method = class_getInstanceMethod(object_getClass(buffer),
            @selector(renderCommandEncoderWithDescriptor:));
        original = method_setImplementation(method, (IMP)faultEncoder);
    }
    faultBuffer = buffer;
    faultIndex = index;
    attempts = 0;
}
NSUInteger MWXEncoderAttempts(void) { return attempts; }
static id faultDevice;
static NSUInteger pipelineIndex, pipelineAttempts;
static IMP pipelineOriginal;
static id faultPipeline(id receiver, SEL selector, id descriptor, NSError **error) {
    if (receiver == faultDevice && ++pipelineAttempts == pipelineIndex) {
        if (error) *error = [NSError errorWithDomain:@"BloomFixture" code:1 userInfo:nil];
        return nil;
    }
    return ((id (*)(id, SEL, id, NSError **))pipelineOriginal)(receiver, selector, descriptor, error);
}
void MWXArmPipelineFault(id<MTLDevice> device, NSUInteger index) {
    if (!pipelineOriginal) {
        Method method = class_getInstanceMethod(object_getClass(device),
            @selector(newRenderPipelineStateWithDescriptor:error:));
        pipelineOriginal = method_setImplementation(method, (IMP)faultPipeline);
    }
    faultDevice = device;
    pipelineIndex = index;
    pipelineAttempts = 0;
}
NSUInteger MWXPipelineAttempts(void) { return pipelineAttempts; }

'''
HARNESS = r'''
import Foundation
import Metal

@main enum Harness {
  static func main() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      fatalError("Metal unavailable")
    }
    MWXArmPipelineFault(device, 0)
    let bloom = SceneBloomPostProcess(device: device)!
    let preparedCount = MWXPipelineAttempts()
    func render(
      _ w: Int, _ h: Int, strength: Float, threshold: Float, enabled: Bool = true, phase: Int = 0, failEncoder: Int = 0,
      configuration: SceneBloomConfiguration? = nil
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
      MWXArmEncoderFault(cb, UInt(failEncoder))
      let encoded = bloom.encode(
        configuration: configuration ?? .init(
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
        "encoderAttempts": MWXEncoderAttempts(),
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
    for index in 1...4 {
      _ = render(400, 240, strength: 1, threshold: 0.3, phase: index)
      results["fault\(index)"] = render(400, 240, strength: 1, threshold: 0.3,
        phase: index + 37, failEncoder: index)
      results["recovery\(index)"] = render(400, 240, strength: 1, threshold: 0.3,
        phase: index + 37)
    }
    func property(_ key: String, _ kind: SceneUserPropertyKind,
                  _ value: SceneUserPropertyValue) -> SceneUserPropertyDefinition {
      .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
        order: 0, index: nil, minimumValue: nil, maximumValue: nil,
        stepValue: nil, allowsFractionalValues: true, fractionalPrecision: nil,
        displayCondition: nil, defaultValue: value, options: [])
    }
    let report = SceneUserPropertyBindingParser().parse(root: ["general": [
      "bloom": ["user": "enabled", "value": false],
      "bloomstrength": ["user": "strength", "value": 0.5],
      "bloomthreshold": ["user": "threshold", "value": 0.3],
      "bloomtint": ["user": "tint", "value": "1 1 1"],
    ]])
    let compilation = ScenePropertyBindingCompiler().compile(report: report,
      catalog: .init(definitions: [property("enabled", .bool, .bool(false)),
        property("strength", .slider, .number(0.5)),
        property("threshold", .slider, .number(0.3)),
        property("tint", .color, .string("1 1 1"))]))
    results["bindingAdmitted"] = report.diagnostics.isEmpty
      && compilation.program.instructions.count == 4
      && compilation.program.rebuildRequiredPropertyKeys.isEmpty
    func resolved(_ values: [String: SceneUserPropertyValue]) -> SceneBloomConfiguration {
      let evaluation = compilation.program.evaluate(effectiveValues: values)
      let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 1,
        definitions: compilation.program.definitions, userValues: evaluation.userValues).snapshot
      return SceneBloomConfiguration.disabled.resolving(snapshot)
    }
    let on: [String: SceneUserPropertyValue] = ["enabled": .bool(true),
      "strength": .number(0.5), "threshold": .number(0.3), "tint": .string("1 1 1")]
    var off = on; off["enabled"] = .bool(false)
    var zero = on; zero["strength"] = .number(0)
    var threshold = on; threshold["threshold"] = .number(1)
    var tint = on; tint["tint"] = .string("0 0 0")
    for (name, values) in [("On", on), ("Off", off), ("Zero", zero),
                            ("Threshold", threshold), ("Tint", tint), ("OnAgain", on)] {
      results["dynamic" + name] = render(400, 240, strength: 0, threshold: 1,
        enabled: false, configuration: resolved(values))
    }
    var invalid = on; invalid["strength"] = .number(.infinity)
    invalid["tint"] = .string("1 NaN 0")
    results["invalidFallsBack"] = resolved(invalid).strength == 0.5
      && resolved(invalid).tint == SIMD3<Float>(1, 1, 1)
    var overflow = on; overflow["strength"] = .number(Double.greatestFiniteMagnitude)
    results["floatOverflowFallsBack"] = resolved(overflow).strength == 1
    let comboRoot: [String: Any] = ["general": [
      "bloom": ["user": ["name": "mode", "condition": "glow"], "value": false]]]
    let comboCatalog = SceneUserPropertyDefinitionParser().parse(projectRoot: ["general": ["properties": [
      "mode": ["type": "combo", "value": "plain", "options": [
        ["label": "plain", "value": "plain"], ["label": "glow", "value": "glow"]]]]]])
    let combo = ScenePropertyBindingCompiler().compile(
      report: SceneUserPropertyBindingParser().parse(root: comboRoot), catalog: comboCatalog)
    results["comboAdmitted"] = combo.diagnostics.isEmpty && combo.program.instructions.count == 1
    for mode in ["plain", "glow", "plain"] {
      let evaluation = combo.program.evaluate(effectiveValues: ["mode": .string(mode)])
      let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 3, generation: 1,
        definitions: combo.program.definitions, userValues: evaluation.userValues).snapshot
      let config = SceneBloomConfiguration(enabled: false, strength: 1, threshold: 0.3,
        tint: SIMD3(1, 1, 1)).resolving(snapshot)
      results["combo" + mode] = render(400, 240, strength: 0, threshold: 1, configuration: config)
    }
    results["prepareOnce"] = preparedCount == 3 && MWXPipelineAttempts() == 3
    for index in 1...3 {
      MWXArmPipelineFault(device, UInt(index))
      let rejected = SceneBloomPostProcess(device: device)
      results["pipelineFailure\(index)"] = rejected == nil && MWXPipelineAttempts() == index
      MWXArmPipelineFault(device, 0)
      results["pipelineRecovery\(index)"] = SceneBloomPostProcess(device: device) != nil
        && MWXPipelineAttempts() == 3
    }
    let floatBloom = SceneBloomPostProcess(device: device, pixelFormat: .rgba16Float)!
    let fd = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: 32, height: 16, mipmapped: false)
    fd.usage = [.shaderRead, .renderTarget]
    fd.storageMode = .shared
    let ft = device.makeTexture(descriptor: fd)!
    var fp = [Float16](repeating: 0.5001, count: 32 * 16 * 4)
    for i in stride(from: 3, to: fp.count, by: 4) { fp[i] = 1 }
    fp.withUnsafeBytes { ft.replace(region: MTLRegionMake2D(0, 0, 32, 16),
      mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 32 * 8) }
    let fc = queue.makeCommandBuffer()!
    let encoded = floatBloom.encode(configuration: .init(enabled: true,
      strength: 1, threshold: 0.3, tint: SIMD3(1, 1, 1)), source: ft, commandBuffer: fc)
    fc.commit(); fc.waitUntilCompleted()
    var fr = [Float16](repeating: 0, count: fp.count)
    fr.withUnsafeMutableBytes { ft.getBytes($0.baseAddress!, bytesPerRow: 32 * 8,
      from: MTLRegionMake2D(0, 0, 32, 16), mipmapLevel: 0) }
    results["floatBloom"] = encoded && fc.status == .completed
      && fr[0] > fp[0] && fr[3] == 1 && fr.allSatisfy { $0.isFinite }
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
            (folder / "Fault.h").write_text(FAULT_HEADER)
            (folder / "Fault.m").write_text(FAULT_SOURCE)
            commands = [
                ["xcrun", "clang", "-fobjc-arc", "-c", str(folder / "Fault.m"),
                 "-o", str(folder / "fault.o")],
                ["xcrun", "-sdk", "macosx", "metal", "-c",
                 str(SCENE / "SceneBloomPostProcess.metal"), "-o", str(folder / "bloom.air")],
                ["xcrun", "-sdk", "macosx", "metallib", str(folder / "bloom.air"),
                 "-o", str(folder / "default.metallib")],
                ["swiftc", "-import-objc-header", str(folder / "Fault.h"),
                 str(folder / "fault.o"), *map(str, SWIFT_SOURCES),
                 str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyDefinitionParser.swift"),
                 str(SCENE / "SceneBloomPostProcess.swift"),
                 str(folder / "Main.swift"), "-o", str(folder / "run")],
            ]
            for command in commands:
                subprocess.run(command, capture_output=True, text=True, check=True, timeout=120)
            result = subprocess.run([str(folder / "run")], capture_output=True,
                                    text=True, check=True, timeout=30)
            cls.result = json.loads(result.stdout)

    def test_authored_bindings_reach_gpu_and_change_on_the_next_frame(self):
        self.assertTrue(self.result["bindingAdmitted"])
        self.assertTrue(self.result["invalidFallsBack"])
        self.assertTrue(self.result["floatOverflowFallsBack"])
        for suffix in ("On", "OnAgain"):
            self.assertGreater(self.result["dynamic" + suffix]["changedRGB"], 0)
        for suffix in ("Off", "Zero", "Threshold", "Tint"):
            self.assertEqual(self.result["dynamic" + suffix]["changedRGB"], 0)
        for suffix in ("On", "Off", "Zero", "Threshold", "Tint", "OnAgain"):
            self.assertEqual(self.result["dynamic" + suffix]["changedAlpha"], 0)

    def test_pipeline_preparation_is_complete_or_unavailable_and_never_repeated_per_frame(self):
        self.assertTrue(self.result["prepareOnce"])
        for index in range(1, 4):
            self.assertTrue(self.result[f"pipelineFailure{index}"])
            self.assertTrue(self.result[f"pipelineRecovery{index}"])

    def test_each_failed_pass_preserves_source_and_stops_the_chain(self):
        for index in range(1, 5):
            with self.subTest(pass_index=index):
                failed = self.result[f"fault{index}"]
                self.assertFalse(failed["encoded"])
                self.assertEqual(failed["encoderAttempts"], index)
                self.assertEqual(failed["changedRGB"], 0)
                self.assertEqual(failed["changedAlpha"], 0)
                recovered = self.result[f"recovery{index}"]
                self.assertTrue(recovered["encoded"])
                self.assertGreater(recovered["changedRGB"], 0)
                self.assertEqual(recovered["changedAlpha"], 0)

    def test_combo_condition_controls_gpu_bloom(self):
        self.assertTrue(self.result["comboAdmitted"])
        self.assertGreater(self.result["comboglow"]["changedRGB"], 0)
        self.assertEqual(self.result["comboplain"]["changedRGB"], 0)
        self.assertEqual(self.result["comboplain"]["encoderAttempts"], 0)

    def test_zero_contribution_and_disabled_are_pixel_identical(self):
        for name, values in self.result.items():
            if name.endswith(("Zero", "Threshold", "Disabled")):
                with self.subTest(case=name):
                    self.assertEqual(values["encoded"], name.endswith("Threshold"))
                    if name.endswith(("Zero", "Disabled")):
                        self.assertEqual(values["encoderAttempts"], 0)
                    self.assertEqual(values["changedRGB"], 0)
                    self.assertEqual(values["changedAlpha"], 0)

    def test_positive_bloom_and_reuse_add_light_without_changing_alpha(self):
        self.assertTrue(self.result["floatBloom"])
        for name in ["positive", "reusePositive"]:
            self.assertTrue(self.result[name]["encoded"])
            self.assertGreater(self.result[name]["changedRGB"], 0)
            self.assertEqual(self.result[name]["darkened"], 0)
            self.assertEqual(self.result[name]["changedAlpha"], 0)


if __name__ == "__main__":
    unittest.main()
