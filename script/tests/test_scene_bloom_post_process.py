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

enum SceneGPUCensus {
  static func recordMainPassRender(usesDepth: Bool) {}
}

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

    // ===== D2 display mapping (stage B first slice) =====
    let curve = SceneDisplayMappingCurve.frozenDefault
    let darkLadder: [Float] = [0, 0.0625, 0.125, 0.25, 0.375, 0.5]
    results["dmCurveDarkIdentity"] = darkLadder.allSatisfy { curve.evaluate($0) == $0 }
    let hdrLadder: [Float] = [0.5, 0.75, 1, 1.5, 3, 5, 12, 100, 10000, .greatestFiniteMagnitude]
    let cpuOutputs = hdrLadder.map { curve.evaluate($0) }
    results["dmCurveSDRBounded"] = cpuOutputs.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
      && zip(cpuOutputs, cpuOutputs.dropFirst()).allSatisfy { $0 <= $1 }
    results["dmCurveNonFinite"] = [Float.nan, .infinity, -.infinity, -0.5].allSatisfy {
      curve.evaluate($0) == 0
    }
    // Independent, frozen behavior anchors rather than a second curve formula.
    results["dmCurveAnchors"] = [Float(1), 1.5, 3, 5, 12].map { curve.evaluate($0) }

    let mapping = SceneDisplayMappingPostProcess(device: device, pixelFormat: .rgba16Float, hdrEnabled: true)!
    func float16Texture(
      _ width: Int, _ height: Int, _ texels: [[Float16]]
    ) -> (texture: MTLTexture, bytes: [Float16]) {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
      descriptor.usage = [.shaderRead, .renderTarget]
      descriptor.storageMode = .shared
      let texture = device.makeTexture(descriptor: descriptor)!
      let flat = texels.flatMap { $0 }
      flat.withUnsafeBytes {
        texture.replace(
          region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
          withBytes: $0.baseAddress!, bytesPerRow: width * 8)
      }
      return (texture, flat)
    }
    func readFloat16(_ texture: MTLTexture, _ width: Int, _ height: Int) -> [Float16] {
      var output = [Float16](repeating: 0, count: width * height * 4)
      output.withUnsafeMutableBytes {
        texture.getBytes(
          $0.baseAddress!, bytesPerRow: width * 8,
          from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
      }
      return output
    }
    @discardableResult
    func runMapping(
      _ pass: SceneDisplayMappingPostProcess?, _ source: MTLTexture, failEncoder: Int = 0
    ) -> Bool {
      let buffer = queue.makeCommandBuffer()!
      MWXArmEncoderFault(buffer, UInt(failEncoder))
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: source.pixelFormat, width: source.width, height: source.height, mipmapped: false)
      descriptor.storageMode = .shared
      descriptor.usage = [.shaderRead, .renderTarget]
      let target = device.makeTexture(descriptor: descriptor)!
      let encoded = pass?.encode(source: source, target: target, commandBuffer: buffer) ?? false
      if encoded, let copy = buffer.makeBlitCommandEncoder() {
        copy.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
          sourceSize: .init(width: source.width, height: source.height, depth: 1),
          to: source, destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
        copy.endEncoding()
      }
      buffer.commit()
      buffer.waitUntilCompleted()
      precondition(buffer.status == .completed && buffer.error == nil)
      return encoded
    }

    // Non-HDR (bgra8Unorm) source must be refused with zero GPU work.
    var gatedBytes = [UInt8](repeating: 0, count: 8 * 2 * 4)
    for i in gatedBytes.indices { gatedBytes[i] = UInt8((i * 31) % 256) }
    let gatedDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 8, height: 2, mipmapped: false)
    gatedDescriptor.usage = [.shaderRead, .renderTarget]
    gatedDescriptor.storageMode = .shared
    let gatedSource = device.makeTexture(descriptor: gatedDescriptor)!
    gatedBytes.withUnsafeBytes {
      gatedSource.replace(
        region: MTLRegionMake2D(0, 0, 8, 2), mipmapLevel: 0,
        withBytes: $0.baseAddress!, bytesPerRow: 8 * 4)
    }
    let gatedEncoded = runMapping(mapping, gatedSource)
    var gatedReadback = [UInt8](repeating: 0, count: gatedBytes.count)
    gatedReadback.withUnsafeMutableBytes {
      gatedSource.getBytes(
        $0.baseAddress!, bytesPerRow: 8 * 4,
        from: MTLRegionMake2D(0, 0, 8, 2), mipmapLevel: 0)
    }
    results["dmGatedZeroWork"] = [
      "encoded": gatedEncoded, "bytesEqual": gatedReadback == gatedBytes,
      "encoderAttempts": MWXEncoderAttempts(),
    ]

    // HDR route: opaque terminal RGB. White is compressed to reserve SDR
    // highlight range; dark identity applies only below the frozen knee.
    let ladderTexels: [[Float16]] = [
      [0, 0.5, 1, 1], [0.125, 0.75, 0.875, 1], [1, 0, 0.625, 1],
      [0.375, 1, 0.25, 1], [1.5, 3, 4, 1], [5, 8, 12, 1],
      [3, 3, 3, 1], [10000, 100, 16, 1],
      [0.5, 0.5, 0.5, 1], [3, 0.5, 0.2, 1], [0.75, 0.25, 0.0625, 1], [1, 1, 1, 1],
    ]
    let ladder = float16Texture(6, 2, ladderTexels)
    let ladderEncoded = runMapping(mapping, ladder.texture)
    let mapped = readFloat16(ladder.texture, 6, 2)
    var darkBitExact = true
    var alphaBitExact = true
    var sdrBounded = true
    for texel in 0..<12 {
      for channel in 0..<4 {
        let index = texel * 4 + channel
        let original = ladder.bytes[index]
        let output = mapped[index]
        if channel == 3 {
          if output != original { alphaBitExact = false }
        } else {
          if !(output.isFinite && output >= 0 && output <= 1) { sdrBounded = false }
          if original <= 0.5 && output != original { darkBitExact = false }
        }
      }
    }
    let shoulderProbeIndices = [2, 16, 17, 20, 22]
    let grayIndex = 6 * 4
    results["dmShoulderProbes"] = shoulderProbeIndices.map { Float(mapped[$0]) }
    results["dmLadderGPU"] = [
      "encoded": ladderEncoded, "darkBitExact": darkBitExact,
      "alphaBitExact": alphaBitExact, "sdrBounded": sdrBounded,
      "grayPreserved": mapped[grayIndex] == mapped[grayIndex + 1]
        && mapped[grayIndex + 1] == mapped[grayIndex + 2],
    ]
    let colorIndex = 9 * 4
    results["dmColorHighlight"] = [
      "greenBlueBitExact": mapped[colorIndex + 1] == ladder.bytes[colorIndex + 1]
        && mapped[colorIndex + 2] == ladder.bytes[colorIndex + 2],
      "redCompressed": mapped[colorIndex] > mapped[colorIndex + 1]
        && mapped[colorIndex] < 1,
    ]
    let nonfiniteFixture = float16Texture(2, 1, [
      [.nan, .infinity, -.infinity, 1], [-1, .greatestFiniteMagnitude, 0.25, 1],
    ])
    _ = runMapping(mapping, nonfiniteFixture.texture)
    let invalidMapped = readFloat16(nonfiniteFixture.texture, 2, 1)
    results["dmNonFiniteGPU"] = invalidMapped.enumerated().allSatisfy { index, value in
      let expected = index % 4 == 3 ? Float(nonfiniteFixture.bytes[index])
        : curve.evaluate(Float(nonfiniteFixture.bytes[index]))
      return value.isFinite && abs(Float(value) - expected) <= 1.0 / 1024.0
    }
    // Non-HDR route is nil even if a target uses floating-point storage.
    let bypass = float16Texture(2, 1, [[0.75, 1, 3, 1], [0.25, 0.5, 0, 1]])
    let nonHDRMapping = SceneDisplayMappingPostProcess(
      device: device, pixelFormat: .rgba16Float, hdrEnabled: false)
    results["dmNilRouteZeroWork"] = nonHDRMapping == nil && !runMapping(nonHDRMapping, bypass.texture)
      && MWXEncoderAttempts() == 0 && readFloat16(bypass.texture, 2, 1) == bypass.bytes

    // An accumulating main pass must not repeatedly map retained display RGB.
    // The real main-pass owner keeps its attachment when clear is disabled.
    let accumulatingMapping = SceneDisplayMappingPostProcess(
      device: device, pixelFormat: .rgba16Float, hdrEnabled: true)
    let retained = float16Texture(1, 1, [[0.75, 0.75, 0.75, 1]])
    let display = float16Texture(1, 1, [[0, 0, 0, 1]])
    for _ in 0..<2 {
      let buffer = queue.makeCommandBuffer()!
      let mainPass = SceneMainPassEncoder(
        commandBuffer: buffer, target: retained.texture,
        clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
      mainPass.finishEnsuringClear()
      accumulatingMapping?.encode(source: retained.texture, target: display.texture, commandBuffer: buffer)
      buffer.commit()
      buffer.waitUntilCompleted()
      precondition(buffer.status == .completed && buffer.error == nil)
    }
    results["dmAccumulatingPassUnchanged"] =
      readFloat16(retained.texture, 1, 1) == retained.bytes
      && abs(Float(readFloat16(display.texture, 1, 1)[0]) - 2.0 / 3.0) <= 1.0 / 1024.0

    // Encoder failure mid-chain must preserve the source (blit is read-only).
    let faultTexels: [[Float16]] = [
      [3, 1, 0.5, 1], [0.75, 5, 0.125, 1], [2, 0.25, 8, 1], [0.5, 1, 12, 1],
    ]
    let faultCase = float16Texture(4, 1, faultTexels)
    let failedEncoded = runMapping(mapping, faultCase.texture, failEncoder: 1)
    let afterFault = readFloat16(faultCase.texture, 4, 1)
    let recoveredEncoded = runMapping(mapping, faultCase.texture)
    let afterRecovery = readFloat16(faultCase.texture, 4, 1)
    results["dmEncoderFault"] = [
      "encoded": failedEncoded, "bytesEqual": afterFault == faultCase.bytes,
    ]
    results["dmEncoderRecovery"] = [
      "encoded": recoveredEncoded,
      "mapped": afterRecovery[0] < faultCase.bytes[0] && afterRecovery[0] > 0.9 && afterRecovery[0] < 1,
    ]

    // Launch-time pipeline failure: nil instance, no-op encode, then recovery.
    MWXArmPipelineFault(device, 1)
    let broken = SceneDisplayMappingPostProcess(device: device, pixelFormat: .rgba16Float, hdrEnabled: true)
    results["dmPipelineFailure1"] = broken == nil && MWXPipelineAttempts() == 1
    let noopCase = float16Texture(1, 1, [[3, 3, 3, 1]])
    let noopBuffer = queue.makeCommandBuffer()!
    MWXArmEncoderFault(noopBuffer, 0)
    broken?.encode(source: noopCase.texture, target: float16Texture(4, 1, faultTexels).texture, commandBuffer: noopBuffer)
    noopBuffer.commit()
    noopBuffer.waitUntilCompleted()
    let noopReadback = readFloat16(noopCase.texture, 1, 1)
    results["dmPipelineNoOp"] = noopBuffer.status == .completed
      && noopReadback == noopCase.bytes && MWXEncoderAttempts() == 0
    MWXArmPipelineFault(device, 0)
    let recoveredMapping = SceneDisplayMappingPostProcess(
      device: device, pixelFormat: .rgba16Float, hdrEnabled: true)
    let recoveryEncoded = runMapping(recoveredMapping, noopCase.texture)
    let recoveryReadback = readFloat16(noopCase.texture, 1, 1)
    results["dmPipelineRecovery1"] = recoveredMapping != nil && recoveryEncoded
      && recoveryReadback[0] > 0.9 && recoveryReadback[0] < 1

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
                ["xcrun", "-sdk", "macosx", "metal", "-c",
                 str(SCENE / "SceneDisplayMappingPostProcess.metal"),
                 "-o", str(folder / "display-mapping.air")],
                ["xcrun", "-sdk", "macosx", "metallib", str(folder / "bloom.air"),
                 str(folder / "display-mapping.air"),
                 "-o", str(folder / "default.metallib")],
                ["swiftc","-import-objc-header",str(folder / "Fault.h"),str(folder / "fault.o"),*map(str, SWIFT_SOURCES),str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyDefinitionParser.swift"),str(SCENE / "SceneBloomPostProcess.swift"),str(SCENE / "SceneDisplayMappingPostProcess.swift"),str(SCENE / "SceneMainPassEncoder.swift"),str(folder / "Main.swift"),"-o",str(folder / "run"),Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift"],
            ]
            for command in commands:
                compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
                if compiled.returncode:
                    raise RuntimeError(compiled.stderr)
            result = subprocess.run([str(folder / "run")], capture_output=True,
                                    text=True, check=True, timeout=120)
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

    def test_display_mapping_curve_reserves_sdr_highlight_range(self):
        self.assertTrue(self.result["dmCurveDarkIdentity"])
        self.assertTrue(self.result["dmCurveSDRBounded"])
        self.assertTrue(self.result["dmCurveNonFinite"])
        for actual, expected in zip(self.result["dmCurveAnchors"], [0.75, 0.8333333, 0.9166667, 0.95, 0.9791667]):
            self.assertAlmostEqual(actual, expected, delta=1 / 1024)

    def test_display_mapping_refuses_mismatched_source_and_bypasses_non_hdr_route(self):
        gated = self.result["dmGatedZeroWork"]
        self.assertFalse(gated["encoded"])
        self.assertTrue(gated["bytesEqual"])
        self.assertEqual(gated["encoderAttempts"], 0)
        self.assertTrue(self.result["dmNilRouteZeroWork"])

    def test_display_mapping_gpu_preserves_distinct_highlights_inside_sdr_range(self):
        ladder = self.result["dmLadderGPU"]
        for field in ("encoded", "darkBitExact", "alphaBitExact", "sdrBounded", "grayPreserved"):
            self.assertTrue(ladder[field], field)
        probes = self.result["dmShoulderProbes"]
        for actual, expected in zip(probes, [0.75, 0.8333333, 0.9166667, 0.95, 0.9791667]):
            self.assertAlmostEqual(actual, expected, delta=1 / 1024)
        # All five remain distinct after SDR clamp and 8-bit quantization.
        sdr_codes = [round(min(1, max(0, x)) * 255) for x in probes]
        for lower, upper in zip(probes, probes[1:]):
            self.assertGreater(upper - lower, 1 / 64)
        self.assertEqual(len(set(sdr_codes)), 5, sdr_codes)

    def test_display_mapping_compresses_colorful_highlights_without_crosstalk(self):
        color = self.result["dmColorHighlight"]
        self.assertTrue(color["greenBlueBitExact"])
        self.assertTrue(color["redCompressed"])

    def test_display_mapping_gpu_and_cpu_agree_on_nonfinite_input(self):
        self.assertTrue(self.result["dmNonFiniteGPU"])

    def test_accumulating_main_pass_does_not_remap_retained_display_color(self):
        self.assertTrue(self.result["dmAccumulatingPassUnchanged"])

    def test_display_mapping_pipeline_failure_fails_soft_and_recovers(self):
        self.assertTrue(self.result["dmPipelineFailure1"])
        self.assertTrue(self.result["dmPipelineNoOp"])
        self.assertTrue(self.result["dmPipelineRecovery1"])

    def test_display_mapping_encoder_failure_preserves_source(self):
        fault = self.result["dmEncoderFault"]
        self.assertFalse(fault["encoded"])
        self.assertTrue(fault["bytesEqual"])
        recovery = self.result["dmEncoderRecovery"]
        self.assertTrue(recovery["encoded"])
        self.assertTrue(recovery["mapped"])


if __name__ == "__main__":
    unittest.main()
