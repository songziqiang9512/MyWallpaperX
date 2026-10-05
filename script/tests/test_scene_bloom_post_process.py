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
import CoreGraphics

// This fixture never reserves composition groups; history tests use real pins.
final class SceneGraphRenderTargetResidencyPin {
  func release() { fatalError("unexpected composition pin in Bloom fixture") }
}

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
    let hdrKeys = ["bloomhdrstrength", "bloomhdrthreshold", "bloomhdrscatter",
                   "bloomhdrfeather", "bloomhdriterations"]
    let hdrGeneral = Dictionary(uniqueKeysWithValues: hdrKeys.map {
      ($0, ["user": $0, "value": $0 == "bloomhdriterations" ? 3.0 : 0.5] as [String: Any])
    })
    let hdrCatalog = SceneUserPropertyDefinitionParser().parse(projectRoot: ["general": [
      "properties": Dictionary(uniqueKeysWithValues: hdrKeys.map {
        ($0, ["type": "slider", "value": $0 == "bloomhdriterations" ? 3.0 : 0.5,
              "min": 0.0, "max": 8.0] as [String: Any])
      })]])
    let hdrBindings = ScenePropertyBindingCompiler().compile(
      report: SceneUserPropertyBindingParser().parse(root: ["general": hdrGeneral]),
      catalog: hdrCatalog)
    results["hdrFieldsAdmitted"] = hdrBindings.diagnostics.isEmpty
      && hdrBindings.program.instructions.count == hdrKeys.count
    let authoredHDR = SceneBloomConfiguration(enabled: true, strength: 7, threshold: 0.1,
      tint: SIMD3(1, 1, 1), hdr: .init(strength: 0.25, threshold: 0.75,
        scatter: 1, feather: 0.5, iterations: 3))
    let hdrEvaluation = hdrBindings.program.evaluate(effectiveValues: [
      "bloomhdrstrength": .number(2), "bloomhdrthreshold": .number(1.5),
      "bloomhdrscatter": .number(2), "bloomhdrfeather": .number(0.25),
      "bloomhdriterations": .number(8)])
    let hdrSnapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 4, generation: 2,
      definitions: hdrBindings.program.definitions, userValues: hdrEvaluation.userValues).snapshot
    let resolvedHDR = authoredHDR.resolving(hdrSnapshot)
    results["hdrTypedConfiguration"] = resolvedHDR.strength == 7 && resolvedHDR.threshold == 0.1
      && resolvedHDR.hdr == .init(strength: 2, threshold: 1.5, scatter: 2,
        feather: 0.25, iterations: 8)
    let standardOnly = SceneBloomConfiguration(enabled: true, strength: 7, threshold: 0.1,
      tint: SIMD3(1, 1, 1)).resolving(hdrSnapshot)
    results["hdrDoesNotActivateStandardProfile"] = standardOnly.hdr == nil
      && standardOnly.strength == 7 && standardOnly.threshold == 0.1
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

    // Public ColorSync conversion is an independent transfer oracle. Read
    // actual half-float Metal output; the source/alpha must stay untouched.
    let authored: [Float16] = [0, 0.01, 0.25, 0.5, 1, 1.25, 2, 4]
    let encodedSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)!
    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    var edrValid = true
    for requested: Float in [1, 1.2, 4, 16, 0, .nan, .infinity] {
      let source = float16Texture(8, 1, authored.map { [$0, $0, $0, 0.5] })
      let target = float16Texture(8, 1, Array(repeating: [0, 0, 0, 0], count: 8))
      let buffer = queue.makeCommandBuffer()!
      MWXArmEncoderFault(buffer, 0)
      let output = SceneDisplayMappingPostProcess.Output.extendedLinearSRGB(headroom: requested)
      edrValid = edrValid && mapping.encode(source: source.texture, target: target.texture,
        commandBuffer: buffer, output: output)
      buffer.commit(); buffer.waitUntilCompleted()
      edrValid = edrValid && buffer.status == .completed
      let pixels = readFloat16(target.texture, 8, 1)
      for (index, value) in authored.enumerated() {
        let color = CGColor(colorSpace: encodedSpace,
          components: [CGFloat(value), CGFloat(value), CGFloat(value), 1])!
        let expected = min(output.uniform, Float(color.converted(to: linearSpace,
          intent: .relativeColorimetric, options: nil)!.components![0]))
        edrValid = edrValid && abs(Float(pixels[index * 4]) - expected) < 0.002 * max(1, expected)
          && pixels[index * 4 + 3] == 0.5
      }
      edrValid = edrValid && readFloat16(source.texture, 8, 1) == source.bytes
    }
    results["edrColorSyncTransferAndHeadroom"] = edrValid

    // Overbright source contributes a halo BEFORE terminal SDR saturation.
    // A premature clamp would leave the threshold=1 input without a glow.
    var glowTexels = [[Float16]](repeating: [0.125, 0.125, 0.125, 1], count: 32 * 16)
    for y in 4..<12 { for x in 8..<24 { glowTexels[y * 32 + x] = [3, 3, 3, 1] } }
    let glow = float16Texture(32, 16, glowTexels)
    let glowBuffer = queue.makeCommandBuffer()!
    MWXArmEncoderFault(glowBuffer, 0)
    let glowEncoded = floatBloom.encode(configuration: .init(enabled: true,
      strength: 0.1, threshold: 1, tint: SIMD3(1, 1, 1)), source: glow.texture,
      commandBuffer: glowBuffer)
    glowBuffer.commit(); glowBuffer.waitUntilCompleted()
    let beforeDisplay = readFloat16(glow.texture, 32, 16)
    let glowTarget = float16Texture(32, 16,
      [[Float16]](repeating: [0, 0, 0, 1], count: 32 * 16))
    let displayBuffer = queue.makeCommandBuffer()!
    MWXArmEncoderFault(displayBuffer, 0)
    let glowDisplayed = mapping.encode(source: glow.texture, target: glowTarget.texture,
      commandBuffer: displayBuffer)
    displayBuffer.commit(); displayBuffer.waitUntilCompleted()
    let afterDisplay = readFloat16(glowTarget.texture, 32, 16)
    let haloIndices = stride(from: 0, to: glow.bytes.count, by: 4).filter {
      glow.bytes[$0] == 0.125 && beforeDisplay[$0] > 0.125 && beforeDisplay[$0] < 1
    }
    results["dmSuperwhiteBloom"] = [
      "completed": glowEncoded && glowDisplayed && glowBuffer.status == .completed
        && displayBuffer.status == .completed,
      "haloSurvived": !haloIndices.isEmpty
        && haloIndices.allSatisfy { beforeDisplay[$0] == afterDisplay[$0] },
      "superwhiteClippedOnlyAtDisplay": beforeDisplay[(8 * 32 + 16) * 4] > 1
        && afterDisplay[(8 * 32 + 16) * 4] == 1,
      "sourceUnchanged": readFloat16(glow.texture, 32, 16) == beforeDisplay,
    ]


    // Five neutral blocks match the official black-box input. Read actual 16F
    // GPU output before display clipping; this is behavior, not a CPU oracle.
    let hdrBloom = SceneBloomPostProcess(device: device, pixelFormat: .rgba16Float, hdrEnabled: true)!
    func renderHDR(_ config: SceneBloomConfiguration.HDR, tint: SIMD3<Float> = SIMD3(1, 1, 1),
                   failEncoder: Int = 0) -> [String: Any] {
      let w = 640, h = 256
      let brightness: [Float16] = [0.25, 0.5, 1, 2, 4]
      var input = [[Float16]](repeating: [0, 0, 0, 0.375], count: w * h)
      for block in 0..<5 {
        for y in 116..<140 { for x in (64 + block * 128 - 12)..<(64 + block * 128 + 12) {
          input[y * w + x] = [brightness[block], brightness[block], brightness[block], 0.75]
        } }
      }
      let source = float16Texture(w, h, input)
      let configuration = SceneBloomConfiguration(enabled: true, strength: 0, threshold: 9, tint: tint, hdr: config)
      let prepared = hdrBloom.prepareCapacity(configuration: configuration, source: source.texture)
      let buffer = queue.makeCommandBuffer()!
      MWXArmEncoderFault(buffer, UInt(failEncoder))
      let encoded = hdrBloom.encode(configuration: configuration, source: source.texture, commandBuffer: buffer)
      buffer.commit(); buffer.waitUntilCompleted()
      let output = readFloat16(source.texture, w, h)
      func roi(_ block: Int, _ rows: Range<Int>, _ channel: Int = 0) -> Double {
        var sum = 0.0, count = 0
        for y in rows { for x in (64 + block * 128 - 8)..<(64 + block * 128 + 8) {
          sum += Double(output[(y * w + x) * 4 + channel]); count += 1
        } }
        return sum / Double(count)
      }
      return ["prepared": prepared, "encoded": encoded, "completed": buffer.status == .completed,
        "unchanged": output == source.bytes, "attempts": MWXEncoderAttempts(),
        "alpha": stride(from: 3, to: output.count, by: 4).allSatisfy { output[$0] == source.bytes[$0] },
        "finite": output.allSatisfy { $0.isFinite },
        "near": (0..<5).map { roi($0, 104..<112) },
        "far": (0..<5).map { roi($0, 64..<80) },
        "green": (0..<5).map { roi($0, 104..<112, 1) }]
    }
    func hdrConfig(_ strength: Float = 1, _ threshold: Float = 1, _ scatter: Float = 1,
                   _ feather: Float = 0, _ iterations: Float = 3) -> SceneBloomConfiguration.HDR {
      .init(strength: strength, threshold: threshold, scatter: scatter, feather: feather, iterations: iterations)
    }
    for (key, config) in [("base", hdrConfig()), ("zero", hdrConfig(0)),
                          ("strong", hdrConfig(2)), ("threshold", hdrConfig(1, 0)),
                          ("feather", hdrConfig(1, 1, 1, 1)), ("scatter", hdrConfig(1, 1, 2)),
                          ("wide", hdrConfig(1, 1, 1, 0, 8)),
                          ("hugeIterations", hdrConfig(1, 1, 1, 0, .greatestFiniteMagnitude)),
                          ("unsupportedZeroLevels", hdrConfig(1, 1, 1, 0, 0)),
                          ("unsupportedOneLevel", hdrConfig(1, 1, 1, 0, 1)),
                          ("invalid", hdrConfig(1, 1, .nan)), ("baseAgain", hdrConfig())] {
      results["hdrGPU" + key] = renderHDR(config)
    }
    results["hdrGPUtint"] = renderHDR(hdrConfig(), tint: SIMD3(1, 0, 0))
    // Three down levels + two reconstruction levels + the sole combine.
    for index in 1...6 {
      results["hdrGPUfault\(index)"] = renderHDR(hdrConfig(), failEncoder: index)
      results["hdrGPUrecover\(index)"] = renderHDR(hdrConfig())
    }




    func uniformHDR(_ value: Float16, _ scatter: Float, _ levels: Float,
                    _ strength: Float = 1, _ threshold: Float = 0) -> Int {
      let source = float16Texture(640, 256,
        [[Float16]](repeating: [value, value, value, 1], count: 640 * 256))
      let buffer = queue.makeCommandBuffer()!
      MWXArmEncoderFault(buffer, 0)
      _ = hdrBloom.encode(configuration: .init(enabled: true, strength: 0, threshold: 9,
        tint: SIMD3(1, 1, 1), hdr: hdrConfig(strength, threshold, scatter, 0, levels)),
        source: source.texture, commandBuffer: buffer)
      buffer.commit(); buffer.waitUntilCompleted()
      precondition(buffer.status == .completed)
      let output = readFloat16(source.texture, 640, 256)
      return Int((min(1, max(0, Float(output[(128 * 640 + 320) * 4]))) * 255).rounded())
    }
    // Fixed-client black-box observations, frozen from independent uniform
    // fields: no halo ROI or CPU copy of the shader serves as the oracle.
    results["hdrUniformOfficial"] = [
      uniformHDR(0.1, 1, 3, 0), uniformHDR(0.1, 1, 2), uniformHDR(0.1, 1, 3),
      uniformHDR(0.1, 1, 8), uniformHDR(0.1, 2, 3), uniformHDR(0.01, 2, 2),
      uniformHDR(0.01, 2, 8), uniformHDR(0.01, 0, 3), uniformHDR(0.01, 1.619, 8),
      uniformHDR(0.25, 1, 3), uniformHDR(0.25, 1, 3, 1, 0.1),
      uniformHDR(0.05, 2, 4), uniformHDR(0.05, 0.5, 3)]

    results["hdrLargeScatterSmallStrength"] = uniformHDR(0.01, 100000000, 2, 0.000001)

    func largeParameter(_ strength: Float, _ tint: Float, _ scatter: Float = 0) -> [Float16] {
      let source = float16Texture(16, 16,
        [[Float16]](repeating: [0.0009765625, 0.0009765625, 0.0009765625, 0.5], count: 256))
      let buffer = queue.makeCommandBuffer()!
      MWXArmEncoderFault(buffer, 0)
      precondition(hdrBloom.encode(configuration: .init(enabled: true, strength: 0, threshold: 1,
        tint: SIMD3(repeating: tint), hdr: hdrConfig(strength, 0, scatter, 0, 2)), source: source.texture,
        commandBuffer: buffer))
      buffer.commit(); buffer.waitUntilCompleted()
      precondition(buffer.status == .completed)
      return readFloat16(source.texture, 16, 16)
    }
    let largeStrength = largeParameter(100000, 0.01)
    let equivalentScale = largeParameter(1000, 1)
    results["hdrLargeFiniteParameters"] = zip(largeStrength, equivalentScale).allSatisfy {
      abs(Float($0) - Float($1)) <= 0.0005
    } && largeStrength[0] > 0.45 && largeStrength[0] < 1
      && largeParameter(100000, 0)[0] == 0.0009765625
      && largeParameter(.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude)[0] == 0.0009765625

    let intense = float16Texture(16, 16, [[Float16]](repeating: [40000, 40000, 40000, 0.5], count: 256))
    let intenseBuffer = queue.makeCommandBuffer()!
    MWXArmEncoderFault(intenseBuffer, 0)
    let intenseEncoded = hdrBloom.encode(configuration: .init(enabled: true, strength: 0, threshold: 1,
      tint: SIMD3(1, 1, 1), hdr: hdrConfig(2, 1, 1, 0, 2)), source: intense.texture,
      commandBuffer: intenseBuffer)
    intenseBuffer.commit(); intenseBuffer.waitUntilCompleted()
    let intenseOutput = readFloat16(intense.texture, 16, 16)
    results["hdrFiniteSuperwhite"] = intenseEncoded && intenseBuffer.status == .completed
      && stride(from: 0, to: intenseOutput.count, by: 4).allSatisfy {
        intenseOutput[$0].isFinite && intenseOutput[$0] >= 40000 && intenseOutput[$0 + 3] == 0.5
      }
    _ = autoreleasepool { renderHDR(hdrConfig(1, 1, 1, 0, 8)) }
    let budget = SceneResourceBudget.shared
    let held = budget.maximumBytes - budget.snapshot.residentBytes
    precondition(budget.reserve(held, kind: .gpu))
    // Old 8-level chain alone can pay for the smaller replacement. With the
    // retired cache still pinned, neither its prepare nor next-frame retry fits.
    results["hdrBudgetReplacement"] = autoreleasepool { renderHDR(hdrConfig()) }
    budget.release(held, kind: .gpu)

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

    // HDR composition exported to SDR: all ordinary colors retain their
    // exact values; only superwhite channels saturate at the terminal.
    let ladderTexels: [[Float16]] = [
      [0, 0.5, 1, 1], [0.125, 0.75, 0.875, 1], [1, 0, 0.625, 1],
      [0.375, 1, 0.25, 1], [1.5, 3, 4, 1], [5, 8, 12, 1],
      [3, 3, 3, 1], [10000, 100, 16, 1],
      [0.5, 0.5, 0.5, 1], [3, 0.5, 0.2, 1], [0.75, 0.25, 0.0625, 1], [1, 1, 1, 1],
    ]
    let ladder = float16Texture(6, 2, ladderTexels)
    let ladderEncoded = runMapping(mapping, ladder.texture)
    let mapped = readFloat16(ladder.texture, 6, 2)
    var sdrBitExact = true
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
          if original <= 1 && output != original { sdrBitExact = false }
        }
      }
    }
    let whiteProbeIndices = [2, 16, 17, 20, 22]
    let grayIndex = 6 * 4
    results["dmWhiteProbes"] = whiteProbeIndices.map { Float(mapped[$0]) }
    results["dmLadderGPU"] = [
      "encoded": ladderEncoded, "sdrBitExact": sdrBitExact,
      "alphaBitExact": alphaBitExact, "sdrBounded": sdrBounded,
      "grayPreserved": mapped[grayIndex] == mapped[grayIndex + 1]
        && mapped[grayIndex + 1] == mapped[grayIndex + 2],
    ]
    let colorIndex = 9 * 4
    results["dmColorHighlight"] = [
      "greenBlueBitExact": mapped[colorIndex + 1] == ladder.bytes[colorIndex + 1]
        && mapped[colorIndex + 2] == ladder.bytes[colorIndex + 2],
      "redSaturated": mapped[colorIndex] == 1,
    ]
    let nonfiniteFixture = float16Texture(2, 1, [
      [.nan, .infinity, -.infinity, 1], [-1, .greatestFiniteMagnitude, 0.25, 1],
    ])
    _ = runMapping(mapping, nonfiniteFixture.texture)
    let invalidMapped = readFloat16(nonfiniteFixture.texture, 2, 1)
    results["dmNonFiniteGPU"] = invalidMapped.enumerated().allSatisfy { index, value in
      let expected: Float = [0, 0, 0, 1, 0, 1, 0.25, 1][index]
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
      && abs(Float(readFloat16(display.texture, 1, 1)[0]) - 0.75) <= 1.0 / 1024.0

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
      "mapped": afterRecovery[0] < faultCase.bytes[0] && afterRecovery[0] == 1,
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
      && recoveryReadback[0] == 1

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

    def test_hdr_authored_fields_compile_to_typed_scene_targets(self):
        self.assertTrue(self.result["hdrFieldsAdmitted"])

    def test_hdr_typed_values_remain_separate_from_standard_bloom(self):
        self.assertTrue(self.result["hdrTypedConfiguration"])
        self.assertTrue(self.result["hdrDoesNotActivateStandardProfile"])

    def test_hdr_gpu_parameters_change_energy_spread_threshold_and_tint(self):
        base = self.result["hdrGPUbase"]
        for name in ("base", "strong", "threshold", "feather", "scatter", "wide", "hugeIterations", "baseAgain", "tint"):
            value = self.result["hdrGPU" + name]
            for key in ("prepared", "encoded", "completed", "alpha", "finite"):
                self.assertTrue(value[key], (name, key))
        self.assertEqual(base["near"][:3], [0, 0, 0])
        self.assertGreater(base["near"][3], 0)
        self.assertGreater(base["near"][4], base["near"][3])
        self.assertGreater(self.result["hdrGPUstrong"]["near"][3], base["near"][3])
        self.assertGreater(self.result["hdrGPUthreshold"]["near"][1], 0)
        self.assertGreater(self.result["hdrGPUfeather"]["near"][2], 0)
        self.assertGreater(self.result["hdrGPUscatter"]["near"][3], base["near"][3])
        self.assertGreater(self.result["hdrGPUwide"]["far"][3], base["far"][3])
        self.assertEqual(self.result["hdrGPUtint"]["green"], [0] * 5)
        self.assertEqual(self.result["hdrGPUtint"]["near"], base["near"])
        self.assertEqual(self.result["hdrGPUbaseAgain"]["near"], base["near"])

    def test_hdr_gpu_failure_is_local_and_next_frame_recovers(self):
        for key in ("zero", "invalid", "unsupportedZeroLevels", "unsupportedOneLevel"):
            value = self.result["hdrGPU" + key]
            self.assertTrue(value["unchanged"])
            self.assertEqual(value["attempts"], 0)
        for index in range(1, 7):
            value = self.result[f"hdrGPUfault{index}"]
            self.assertFalse(value["encoded"])
            self.assertTrue(value["unchanged"])
            self.assertEqual(value["attempts"], index)
            self.assertTrue(self.result[f"hdrGPUrecover{index}"]["encoded"])

    def test_edr_output_matches_public_colorsync_transfer_and_current_headroom(self):
        self.assertTrue(self.result["edrColorSyncTransferAndHeadroom"])

    def test_hdr_uniform_field_matches_fixed_official_behavior(self):
        expected = [25, 51, 64, 127, 85, 6, 13, 5, 13, 159, 121, 51, 28]
        for index, (actual, target) in enumerate(zip(self.result["hdrUniformOfficial"], expected, strict=True)):
            self.assertLessEqual(abs(actual - target), 1, (index, actual, target))

    def test_hdr_superwhite_stays_finite_and_retired_capacity_can_be_replaced(self):
        self.assertTrue(self.result["hdrFiniteSuperwhite"])
        self.assertTrue(self.result["hdrLargeFiniteParameters"])
        self.assertLessEqual(abs(self.result["hdrLargeScatterSmallStrength"] - 130), 1)
        replacement = self.result["hdrBudgetReplacement"]
        self.assertTrue(replacement["prepared"])
        self.assertTrue(replacement["encoded"])
        self.assertTrue(replacement["alpha"])

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

    def test_display_mapping_refuses_mismatched_source_and_bypasses_non_hdr_route(self):
        gated = self.result["dmGatedZeroWork"]
        self.assertFalse(gated["encoded"])
        self.assertTrue(gated["bytesEqual"])
        self.assertEqual(gated["encoderAttempts"], 0)
        self.assertTrue(self.result["dmNilRouteZeroWork"])

    def test_hdr_sdr_export_preserves_ordinary_colors_and_clips_only_superwhite(self):
        ladder = self.result["dmLadderGPU"]
        for field in ("encoded", "sdrBitExact", "alphaBitExact", "sdrBounded", "grayPreserved"):
            self.assertTrue(ladder[field], field)
        self.assertEqual(self.result["dmWhiteProbes"], [1, 1, 1, 1, 1])
        color = self.result["dmColorHighlight"]
        self.assertTrue(color["greenBlueBitExact"])
        self.assertTrue(color["redSaturated"])

    def test_superwhite_contributes_bloom_before_sdr_export_without_source_writeback(self):
        for field, passed in self.result["dmSuperwhiteBloom"].items():
            self.assertTrue(passed, field)

    def test_display_mapping_gpu_sanitizes_only_nonfinite_or_out_of_range_channels(self):
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
