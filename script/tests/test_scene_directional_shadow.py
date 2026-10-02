#!/usr/bin/env python3
"""Behavioral Swift/Metal tests for model directional-shadow resources and pixels."""
import json
import hashlib
import math
import copy
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_offscreen_texture_pool as pool_fixture
from script.tests import test_scene_static_model_pipeline as model_fixture
from script.tests.fixtures.scene_directional_shadow_oracle import freeze_vectors, expected_visibility

REPO = Path(__file__).resolve().parents[2]
SCENE = REPO / 'MyWallpaperX/Core/SteamWorkshopScene'

POOL_MAIN = r'''
@main enum ShadowPoolProbe {
    static func clear(_ texture: MTLTexture, _ depth: Double, _ cb: MTLCommandBuffer) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.depthAttachment.texture = texture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = depth
        let encoder = cb.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.endEncoding()
    }
    static func readback(_ texture: MTLTexture, _ cb: MTLCommandBuffer, _ device: MTLDevice) -> MTLBuffer {
        let buffer = device.makeBuffer(length: 256 * texture.height, options: .storageModeShared)!
        let blit = cb.makeBlitCommandEncoder()!
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: 256,
                  destinationBytesPerImage: 256 * texture.height)
        blit.endEncoding()
        return buffer
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        var checks: [String: Bool] = [:]
        let short = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 255)
        var factories = 0
        let denied = short.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!, textureFactory: {
            factories += 1; return device.makeTexture(descriptor: $0)
        })
        checks["budget-refuses-before-factory"] = denied == nil && factories == 0 && short.residentByteCost == 0
        let failed = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 256)
        let nilTexture = failed.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!, textureFactory: { _ in
            factories += 1; return nil
        })
        checks["actual-factory-nil-no-residency"] = nilTexture == nil && factories == 1 && failed.residentByteCost == 0
        let retry = failed.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!)
        checks["same-pool-recovers-after-factory-failure"] = retry != nil && failed.residentByteCost == 256
        failed.reset(); retry?.pin.release()
        let physicalDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 8, height: 8, mipmapped: false)
        physicalDescriptor.storageMode = .private; physicalDescriptor.usage = [.renderTarget, .shaderRead]
        let physicalBytes = device.heapTextureSizeAndAlign(descriptor: physicalDescriptor).size
        let global = SceneResourceBudget(maximumBytes: physicalBytes)
        precondition(global.reserve(1, kind: .gpu))
        let physicalPool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 1024)
        let deniedPhysical = physicalPool.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!, textureFactory: { device.makeSceneTexture(descriptor: $0, budget: global) })
        checks["global-physical-quota-rejection"] = deniedPhysical == nil && global.snapshot.rejectionCount == 1 && global.snapshot.residentBytes == 1 && physicalPool.residentByteCost == 0
        global.release(1, kind: .gpu)
        autoreleasepool {
            let physical = physicalPool.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!, textureFactory: { device.makeSceneTexture(descriptor: $0, budget: global) })!
            physicalPool.reset()
            checks["global-physical-lease-retained-by-pin"] = global.snapshot.residentBytes == physicalBytes && physicalPool.residentByteCost == 256
            physical.pin.release()
        }
        checks["global-physical-retry-cancel-releases"] = global.snapshot.residentBytes == 0 && physicalPool.residentByteCost == 0
        let exact = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 256)
        let exactCB = queue.makeCommandBuffer()!
        let a = exact.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: exactCB)!
        let same = exact.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: exactCB)!
        checks["depth32-exact-cost-and-usage"] = a.texture.pixelFormat == .depth32Float && a.texture.mipmapLevelCount == 1
            && a.texture.usage.contains(.shaderRead) && a.texture.usage.contains(.renderTarget) && exact.residentByteCost == 256
        checks["same-cb-storage-and-generation"] = a.texture === same.texture && a.pin.generation == same.pin.generation
        checks["other-cb-cannot-overwrite-pending"] = exact.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!) == nil
        exact.reset(); a.pin.release()
        checks["reset-retains-other-pin"] = exact.residentByteCost == 256
        same.pin.release()
        checks["last-cancel-releases"] = exact.residentByteCost == 0

        let lifecycle = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 396)
        let cb = queue.makeCommandBuffer()!
        let first = lifecycle.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: cb)!
        clear(first.texture, 0.25, cb)
        let pixels = readback(first.texture, cb, device)
        lifecycle.reset()
        let nextCB = queue.makeCommandBuffer()!
        let resized = lifecycle.reserveModelShadow(slot: 0, width: 7, height: 5, commandBuffer: nextCB)!
        checks["resize-retains-old-pinned-generation"] = resized.texture !== first.texture
            && resized.pin.generation != first.pin.generation && lifecycle.residentByteCost == 396
        let semaphore = DispatchSemaphore(value: 0)
        cb.addCompletedHandler { _ in first.pin.release(); semaphore.signal() }
        cb.commit(); cb.waitUntilCompleted(); semaphore.wait()
        checks["actual-depth-store-readback"] = cb.status == .completed && cb.error == nil
            && pixels.contents().bindMemory(to: Float.self, capacity: 1).pointee == 0.25
        checks["completion-releases-only-old"] = lifecycle.residentByteCost == 140
        lifecycle.reset(); resized.pin.release()
        checks["cancel-new-generation-releases"] = lifecycle.residentByteCost == 0

        let pending = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 512)
        let heldCB = queue.makeCommandBuffer()!
        let event = device.makeSharedEvent()!
        heldCB.encodeWaitForEvent(event, value: 1)
        let held = pending.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: heldCB)!
        clear(held.texture, 0.375, heldCB)
        let heldPixels = readback(held.texture, heldCB, device)
        let heldDone = DispatchSemaphore(value: 0)
        heldCB.addCompletedHandler { _ in held.pin.release(); heldDone.signal() }
        heldCB.commit()
        pending.reset()
        let newer = pending.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!)!
        checks["submitted-blocked-cb-retains-old-generation"] = heldCB.status != .completed && newer.texture !== held.texture
            && newer.pin.generation != held.pin.generation && pending.residentByteCost == 512
        checks["third-cb-refused-while-gpu-blocked"] = pending.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: queue.makeCommandBuffer()!) == nil
        event.signaledValue = 1
        heldCB.waitUntilCompleted(); heldDone.wait()
        checks["signal-completion-preserves-old-content"] = heldCB.status == .completed && heldCB.error == nil
            && heldPixels.contents().bindMemory(to: Float.self, capacity: 1).pointee == 0.375 && pending.residentByteCost == 256
        pending.reset(); newer.pin.release()
        checks["pending-new-cancel-zero"] = pending.residentByteCost == 0

        let mandatory = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 512)
        let mandatoryCB = queue.makeCommandBuffer()!
        let required = mandatory.reserveCompositionTargets(dimensions: [(width: 8, height: 8)], commandBuffer: mandatoryCB)!
        checks["mandatory-real-target-priority"] = required.count == 1 && mandatory.residentByteCost == 512
            && mandatory.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: mandatoryCB) == nil
            && mandatory.residentByteCost == 512
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = required[0].texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0.5, 0, 1)
        let encoder = mandatoryCB.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.endEncoding()
        let control = readback(required[0].texture, mandatoryCB, device)
        mandatoryCB.commit(); mandatoryCB.waitUntilCompleted()
        let rgba = control.contents().bindMemory(to: UInt16.self, capacity: 4)
        checks["mandatory-output-survives-optional-refusal"] = mandatoryCB.status == .completed
            && mandatoryCB.error == nil && rgba[0] == 0 && rgba[1] == 0x3800 && rgba[2] == 0 && rgba[3] == 0x3c00
        mandatory.reset(); required.forEach { $0.pin.release() }
        checks["mandatory-cleanup"] = mandatory.residentByteCost == 0
        let bloomDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 8, height: 8, mipmapped: false)
        bloomDescriptor.storageMode = .private; bloomDescriptor.usage = [.renderTarget, .shaderRead]
        let bloomSource = device.makeSceneTexture(descriptor: bloomDescriptor)!
        let bloom = SceneBloomPostProcess(device: device, pixelFormat: .rgba16Float)!
        let configuration = SceneBloomConfiguration(enabled: true, strength: 0.5, threshold: 0.1, tint: SIMD3(repeating: 1))
        let modelDepthPool = SceneParticleDepthTargetPool()
        let particleDepthPool = SceneParticleDepthTargetPool()
        let modelDepth = modelDepthPool.acquire(device: device, width: 8, height: 8)!
        let particleDepth = particleDepthPool.acquire(device: device, width: 8, height: 8)!
        checks["mandatory-original-bloom-capacity"] = bloom.prepareCapacity(configuration: configuration, source: bloomSource)
        let available = SceneResourceBudget.shared.maximumBytes - SceneResourceBudget.shared.snapshot.residentBytes
        precondition(SceneResourceBudget.shared.reserve(available, kind: .gpu))
        do {
            defer { SceneResourceBudget.shared.release(available, kind: .gpu) }
            let quotaCB = queue.makeCommandBuffer()!
            let optional = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 1024)
            checks["mandatory-bloom-model-particle-before-optional-physical-refusal"] = optional.reserveModelShadow(slot: 0, width: 8, height: 8, commandBuffer: quotaCB) == nil && optional.residentByteCost == 0
            clear(modelDepth.texture, 0.25, quotaCB); clear(particleDepth.texture, 0.5, quotaCB)
            let modelPixel = readback(modelDepth.texture, quotaCB, device)
            let particlePixel = readback(particleDepth.texture, quotaCB, device)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = bloomSource; pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store; pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0.5, 0, 0.75)
            quotaCB.makeRenderCommandEncoder(descriptor: pass)!.endEncoding()
            checks["mandatory-original-bloom-encode-after-refusal"] = bloom.encode(configuration: configuration, source: bloomSource, commandBuffer: quotaCB)
            let finalPixel = readback(bloomSource, quotaCB, device)
            modelDepth.arm(on: quotaCB); particleDepth.arm(on: quotaCB)
            quotaCB.commit(); quotaCB.waitUntilCompleted()
            let pixel = finalPixel.contents().bindMemory(to: UInt16.self, capacity: 4)
            checks["mandatory-original-outputs-healthy"] = quotaCB.status == .completed && quotaCB.error == nil && Float(Float16(bitPattern: pixel[1])) > 0.5 && pixel[0] == 0 && pixel[2] == 0 && pixel[3] == 0x3a00 && modelPixel.contents().bindMemory(to: Float.self, capacity: 1).pointee == 0.25 && particlePixel.contents().bindMemory(to: Float.self, capacity: 1).pointee == 0.5
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def run_swift(sources, support, *, label, metal_sources=(), input_value=None):
    snapshot = os.environ.get('MWX_DIRECTIONAL_SHADOW_PRODUCT_SNAPSHOT')
    if snapshot:
        def frozen(path):
            candidate = Path(snapshot)/path.relative_to(REPO)
            return candidate if candidate.is_file() else path
        sources = [frozen(p) for p in sources]
        metal_sources = [frozen(p) for p in metal_sources]
    parent = os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE')
    if parent:
        Path(parent).mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=f'directional-shadow-{label}-', dir=parent))
    source = work / 'Harness.swift'
    source.write_text(support)
    binary = work / 'probe'
    identity_paths = [Path(__file__), REPO/'script/tests/fixtures/scene_directional_shadow_oracle.py', *sources, *metal_sources]
    source_identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identity_paths}
    (work/'source-identity.json').write_text(json.dumps(source_identity, indent=2))
    airs = []
    for index, metal in enumerate(metal_sources):
        air = work/f'{index}.air'
        built = subprocess.run(['xcrun', '--sdk', 'macosx', 'metal', '-std=macos-metal2.4', '-c', str(metal), '-o', str(air)], capture_output=True, text=True)
        (work/f'metal-{index}.log').write_text(built.stdout+built.stderr)
        if built.returncode: raise AssertionError(f'Metal compile: {work}\n{built.stderr}')
        airs.append(air)
    if airs:
        subprocess.run(['xcrun', '--sdk', 'macosx', 'metallib', *map(str, airs), '-o', str(work/'default.metallib')], check=True, capture_output=True)
    arguments = []
    if input_value is not None:
        (work/'input.json').write_text(json.dumps(input_value, indent=2))
        arguments.append(str(work/'input.json'))
    compiled = subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', *map(str, sources), str(source),
                               '-module-cache-path', str(work/'cache'), '-framework', 'Metal', '-o', str(binary)],
                              capture_output=True, text=True)
    (work/'compile.log').write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        raise AssertionError(f'{label} compile failed; {work}\n{compiled.stderr}')
    if any(hashlib.sha256(Path(p).read_bytes()).hexdigest() != sha for p, sha in source_identity.items()):
        raise AssertionError(f'source changed during compilation: {work}')
    result = subprocess.run([str(binary), *arguments], cwd=work, capture_output=True, text=True, timeout=90)
    (work/'run.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise AssertionError(f'{label} execution failed; {work}\n{result.stderr}')
    if any(hashlib.sha256(Path(p).read_bytes()).hexdigest() != sha for p, sha in source_identity.items()):
        raise AssertionError(f'source changed during execution: {work}')
    report = json.loads(result.stdout)
    (work/'result.json').write_text(json.dumps(report, indent=2))
    if report.get('metalUnavailable'):
        raise unittest.SkipTest('Metal unavailable')
    return report


class SceneDirectionalShadowResourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = run_swift([*pool_fixture.SWIFT_SOURCES, model_fixture.DYNAMIC_SNAPSHOT_SOURCE, SCENE/'Rendering/Composition/SceneBloomPostProcess.swift', SCENE/'Rendering/Particles/SceneParticleDepthTargetPool.swift'],
                              pool_fixture.HARNESS.split('@main', 1)[0] + POOL_MAIN, label='pool', metal_sources=[SCENE/'Rendering/Composition/SceneBloomPostProcess.metal'])

    def test_format_budget_and_real_factory_failure(self):
        for key in ['budget-refuses-before-factory', 'actual-factory-nil-no-residency', 'same-pool-recovers-after-factory-failure', 'depth32-exact-cost-and-usage', 'global-physical-quota-rejection', 'global-physical-lease-retained-by-pin', 'global-physical-retry-cancel-releases']:
            self.assertTrue(self.report[key], self.report)

    def test_submission_lifecycle_and_actual_depth_readback(self):
        for key in ['same-cb-storage-and-generation', 'other-cb-cannot-overwrite-pending', 'reset-retains-other-pin',
                    'last-cancel-releases', 'resize-retains-old-pinned-generation', 'actual-depth-store-readback',
                    'completion-releases-only-old', 'cancel-new-generation-releases', 'submitted-blocked-cb-retains-old-generation',
                    'third-cb-refused-while-gpu-blocked', 'signal-completion-preserves-old-content', 'pending-new-cancel-zero']:
            self.assertTrue(self.report[key], self.report)

    def test_mandatory_real_color_target_survives_optional_refusal(self):
        for key in ['mandatory-real-target-priority', 'mandatory-output-survives-optional-refusal', 'mandatory-cleanup', 'mandatory-original-bloom-capacity', 'mandatory-bloom-model-particle-before-optional-physical-refusal', 'mandatory-original-bloom-encode-after-refusal', 'mandatory-original-outputs-healthy']:
            self.assertTrue(self.report[key], self.report)


PIXEL_MAIN = r'''
@main enum ShadowPixelProbe {
 static func material(_ opacity: Float = 1, _ coverage: Bool = false, _ tint: Bool = false, _ lit: Bool = true, _ emission: Float = 0.8) -> SceneStaticModelMaterial {
  .init(color: SIMD3(repeating: 1), opacity: opacity, receivesLighting: lit, textureAlphaIsOpacity: coverage,
   textureAlphaIsTintMask: tint, emissiveColor: SIMD3(repeating: emission), emissiveBrightness: 1,
   brightness: 1, usesHDRBrightness: false, viewTint: nil)
 }
 static func main() throws {
  guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { print("{\"metalUnavailable\":true}"); return }
  guard let pipeline = SceneStaticModelPipeline(device: device, colorPixelFormat: .rgba16Float) else { fatalError("actual pipeline unavailable") }
  let vectors = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String:Any]]
  func texture(_ alpha: Float) -> MTLTexture {
   let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false)
   d.storageMode = .shared; d.usage = .shaderRead
   let t = device.makeTexture(descriptor:d)!
   var rgba:[Float] = [0.6,0.4,0.2,alpha]
   rgba.withUnsafeMutableBytes { t.replace(region: MTLRegionMake2D(0,0,1,1), mipmapLevel:0, withBytes:$0.baseAddress!, bytesPerRow:16) }
   return t
  }
  func coverageTexture(_ c: [String:Any]) -> MTLTexture {
   guard c["sample_u"] != nil else { return texture(Float(c["texture_alpha"] as? Double ?? 1)) }
   let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:2,height:1,mipmapped:false)
   d.storageMode = .shared; d.usage = .shaderRead
   let t = device.makeTexture(descriptor:d)!
   var values:[Float] = [1,1,1,0, 1,1,1,0.75]
   values.withUnsafeMutableBytes { t.replace(region:MTLRegionMake2D(0,0,2,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:32) }
   return t
  }
  func mesh(_ triangles: [[[Double]]]) -> SceneStaticModelMesh {
   let vertices = triangles.flatMap { $0 }.map { p in SceneMdlStaticModel.Vertex(position: SIMD3(Float(p[0]),Float(p[1]),Float(p[2])), normal: SIMD3(0,0,1), tangent: SIMD4(1,0,0,1), uv: SIMD2(0.5,0.5)) }
   return pipeline.makeMesh(vertices:vertices,indices:Array(0..<UInt32(vertices.count)))!
  }
  let albedo = texture(1)
  let emissionMask = texture(0.25)
  var rows:[[String:Any]] = []
  for v in vectors {
   let position = v["receiver"] as! [Double]
   let direction = v["toward_light"] as! [Double]
   let halfExtent = v["receiver_half_extent"] as? Double
   let x0 = halfExtent.map { position[0]-$0 } ?? (position[1] < -100 ? position[0]-5 : 10.0)
   let x1 = halfExtent.map { position[0]+$0 } ?? (position[1] < -100 ? position[0]+5 : 150.0)
   let y0 = halfExtent.map { position[1]-$0 } ?? (position[1] < -100 ? position[1]-5 : 10.0)
   let y1 = halfExtent.map { position[1]+$0 } ?? (position[1] < -100 ? position[1]+5 : 86.0)
   let receiverZ = position[2]
   let receiver = mesh([[[x0,y0,receiverZ],[x1,y1,receiverZ],[x1,y0,receiverZ]],[[x0,y0,receiverZ],[x0,y1,receiverZ],[x1,y1,receiverZ]]])
   let toward = simd_normalize(SIMD3<Float>(Float(direction[0]),Float(direction[1]),Float(direction[2])))
   let casters = v["casters"] as! [[String:Any]]
   let translated = v["name"] as? String == "caster-parent-translation"
   var casterWorld = matrix_identity_float4x4
   if translated { casterWorld.columns.3.x = 5 }
   var receiverWorld = matrix_identity_float4x4
   let perspective = v["camera"] as? String == "perspective"
   if perspective { receiverWorld.columns.3.z = 20; casterWorld.columns.3.z = 20 }
   let meshes = casters.map { c -> SceneStaticModelMesh in
    var triangles = c["triangles"] as! [[[Double]]]
    if translated { for i in triangles.indices { for j in triangles[i].indices { triangles[i][j][0] -= 5 } } }
    return mesh(triangles)
   }
   let projection = SceneDirectionalShadowProjection.make(bounds: [(minimum:receiver.boundsMinimum,maximum:receiver.boundsMaximum,world:receiverWorld)] + meshes.map { (minimum:$0.boundsMinimum,maximum:$0.boundsMaximum,world:casterWorld) }, directionTowardLight:toward,resolution:1024)!
   let cb = queue.makeCommandBuffer()!
   let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1024,height:1024,mipmapped:false)
   depthDesc.storageMode = .private; depthDesc.usage = [.renderTarget,.shaderRead]
   let map = device.makeTexture(descriptor:depthDesc)!
   let pass = MTLRenderPassDescriptor(); pass.depthAttachment.texture = map
   pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .store; pass.depthAttachment.clearDepth = 1
   let encoder = cb.makeRenderCommandEncoder(descriptor:pass)!
   for (index,c) in casters.enumerated() where (c["cast"] as? Bool ?? true) && (c["visible"] as? Bool ?? true) {
    let tint = c["tint_mask"] as? Bool ?? false
    let covered = (c["uses_coverage_alpha"] as? Bool ?? true) && !tint
    let uvFrame = SceneTextureUVTransform(origin:SIMD2(Float(c["sample_u"] as? Double ?? 0.5)-0.5,0),xAxis:SIMD2(1,0),yAxis:SIMD2(0,1))
    let sampleFlags = UInt32(c["sample_flags"] as? Int ?? 2)
    precondition(pipeline.drawShadow(mesh:meshes[index],texture:coverageTexture(c),textureFrame:uvFrame,sampling:SceneTextureSampling(texFlags:sampleFlags),modelMatrix:casterWorld,projection:.directional(projection),targetExtent:(width:map.width,height:map.height),layerAlpha:Float(c["layer_alpha"] as? Double ?? 1),material:material(Float(c["material_opacity"] as? Double ?? 1),covered,tint,c["receives_lighting"] as? Bool ?? true),encoder:encoder))
   }
   encoder.endEncoding()
   let shadow = SceneStaticModelShadow(texture:map,frameEpoch:7,generation:1,lightLayerID:10,projection:.directional(projection),commandBuffer:cb)
   // Authored camera sample at the chosen world point, independent of product light projection.
   let scale = Float(v["camera_scale"] as? Double ?? 0.05)
   var view = simd_float4x4(rows:[SIMD4(scale,0,0,-Float(position[0])*scale),SIMD4(0,-scale,0,Float(position[1])*scale),SIMD4(0,0,-0.001,0.5),SIMD4(0,0,0,1)])
   if v["camera"] as? String == "perspective" { view.columns.2.w = -0.01 }
   var buffers:[MTLBuffer] = []
   for mode in 0..<9 {
    let colorDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1,height:1,mipmapped:false)
    colorDesc.storageMode = .private; colorDesc.usage = [.renderTarget]
    let output = device.makeTexture(descriptor:colorDesc)!
    let zDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1,height:1,mipmapped:false)
    zDesc.storageMode = .private; zDesc.usage = .renderTarget
    let z = device.makeTexture(descriptor:zDesc)!
    let render = MTLRenderPassDescriptor(); render.colorAttachments[0].texture = output
    render.colorAttachments[0].loadAction = .clear; render.colorAttachments[0].storeAction = .store; render.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
    render.depthAttachment.texture = z; render.depthAttachment.loadAction = .clear; render.depthAttachment.storeAction = .dontCare; render.depthAttachment.clearDepth = 0
    let e = cb.makeRenderCommandEncoder(descriptor:render)!
    let selected:Float = mode == 0 || (4...6).contains(mode) ? 0 : Float(v["light_intensity"] as? Double ?? 0.6)
    let lights = SceneLightSnapshot(ambient: SIMD3(repeating: mode == 4 ? 0 : 0.08),directional:[
     .init(layerID:10,castsShadow:true,directionTowardLight:toward,color:SIMD3(repeating:1),intensity:selected),
     .init(layerID:11,directionTowardLight:SIMD3(0,0,1),color:SIMD3(0.5,0.7,1),intensity:mode == 5 ? 0 : 0.2)],point:[],spot:[],overflowCount:0)
    let enabled = v["shadow_enabled"] as? Bool ?? true
    let wrongLight = SceneStaticModelShadow(texture:map,frameEpoch:7,generation:1,lightLayerID:999,projection:.directional(projection),commandBuffer:cb)
    let testedShadow = mode == 7 ? wrongLight : shadow
    precondition(pipeline.draw(mesh:receiver,texture:albedo,colorTextureIsPremultiplied:false,emissiveMask:emissionMask,emissiveMaskTextureFrame:.identity,emissiveMaskSampling:.linearClamp,modelMatrix:receiverWorld,viewProjection:view,cameraPosition:SIMD3(Float(position[0]),Float(position[1]),100),textureFrame:.identity,sampling:.linearClamp,layerAlpha:0.75,material:material(1,false,false,true,mode == 6 ? 0 : 0.8),lighting:lights,writesDepth:true,shadows:(mode == 2 || mode == 3 || mode >= 7) && enabled ? [testedShadow] : [],frameEpoch:mode == 3 ? 8 : 7,commandBuffer:mode == 8 ? queue.makeCommandBuffer()! : cb,encoder:e))
    e.endEncoding()
    let b = device.makeBuffer(length:256,options:.storageModeShared)!
    let blit = cb.makeBlitCommandEncoder()!
    blit.copy(from:output,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:1,height:1,depth:1),to:b,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256); blit.endEncoding(); buffers.append(b)
   }
   cb.commit(); cb.waitUntilCompleted(); precondition(cb.status == .completed && cb.error == nil)
   let pixels = buffers.map { b -> [Float] in let p = b.contents().bindMemory(to:UInt16.self,capacity:4); return (0..<4).map { Float(Float16(bitPattern:p[$0])) } }
   rows.append(["name":v["name"]!,"pixels":pixels,"completed":true])
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows],options:[.sortedKeys]),as:UTF8.self))
 }
}
'''

class SceneDirectionalShadowPixelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sources = [getattr(model_fixture, name) for name in ['MODEL_SOURCE', 'SAMPLING_SOURCE', 'UV_TRANSFORM_SOURCE', 'DIRECTIONAL_LIGHT_SOURCE', 'POINT_LIGHT_SOURCE', 'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'DYNAMIC_SNAPSHOT_SOURCE', 'DYNAMIC_LAYER_VALUES_SOURCE', 'PERFORMANCE_COUNTER_SOURCE', 'PIPELINE_SOURCE', 'SHADOW_SOURCE']]
        sources.append(SCENE/'Resources/Textures/SceneResourceBudget.swift')
        cls.vectors = freeze_vectors()
        for name, u, flags, alpha in [('frame-left', .25, 3, 0), ('frame-right', .75, 3, .75),
                                     ('nearest-coverage', .55, 3, .75), ('linear-coverage', .55, 2, .45),
                                     ('repeat-outside', 1.25, 1, 0), ('clamp-outside', 1.25, 3, .75)]:
            vector = copy.deepcopy(cls.vectors[0]); vector['name'] = name
            vector['casters'][0].update(sample_u=u, sample_flags=flags, texture_alpha=alpha)
            vector['expected_visibility'] = expected_visibility(vector)
            cls.vectors.append(vector)
        for name, point, direction, intensity in [('axis-positive-z', [80,48,0], [0,0,1], .6),
                                                   ('near-positive-y', [80,-1952,0], [0,100,1], 60),
                                                   ('self-plane-no-positive-hit', [80,48,20], [1,0,1], .6),
                                                   ('contact-gap-one', [79,48,19], [1,0,1], .6),
                                                   ('contact-gap-tenth', [79.9,48,19.9], [1,0,1], .6),
                                                   ('above-plane-tenth', [80.1,48,20.1], [1,0,1], .6),
                                                   ('near-y-self-plane', [80,48,20], [0,100,1], 60),
                                                   ('self-plane-fractional-positive', [80.27,48.13,20], [.2,.4,1], .6),
                                                   ('self-plane-fractional-negative', [83.2,43.7,20], [-1,.35,1], .6)]:
            vector = copy.deepcopy(cls.vectors[0]); vector.update(name=name, receiver=point, toward_light=direction, light_intensity=intensity)
            vector['expected_visibility'] = expected_visibility(vector)
            cls.vectors.append(vector)
        vector = copy.deepcopy(cls.vectors[0]); vector.update(name='near-y-self-clear-edge', receiver=[80,57.99,20], toward_light=[0,1000,1], light_intensity=600, receiver_half_extent=.005, camera_scale=100)
        vector['expected_visibility'] = expected_visibility(vector); cls.vectors.append(vector)
        vector = copy.deepcopy(cls.vectors[0]); vector.update(name='finite-near-parallel-self', receiver=[80,48,20], toward_light=[0,1000000,1], light_intensity=600000)
        vector['expected_visibility'] = expected_visibility(vector); cls.vectors.append(vector)
        for name, point in [('near-tangent-real-gap', [80,47.9,19.9999]), ('near-tangent-negative-gap', [80,48.1,20.0001])]:
            vector = copy.deepcopy(cls.vectors[0]); vector.update(name=name, receiver=point, toward_light=[0,1000,1], light_intensity=600, receiver_half_extent=.005, camera_scale=100)
            vector['expected_visibility'] = expected_visibility(vector); cls.vectors.append(vector)
        selected = os.environ.get('MWX_DIRECTIONAL_SHADOW_VECTOR')
        if selected: cls.vectors = [v for v in cls.vectors if v['name'] == selected]
        cls.report = run_swift(sources, 'import Foundation\nimport Metal\nimport simd\n'+model_fixture.LIGHTING_STUB+PIXEL_MAIN, label='pixels', metal_sources=[model_fixture.METAL_SOURCE], input_value=cls.vectors)

    def test_independent_geometry_visibility_and_selected_light_contribution(self):
        self.assertEqual(len(self.vectors), len(self.report['rows']))
        for vector, row in zip(self.vectors, self.report['rows']):
            with self.subTest(vector=vector['name']):
                a, full, actual, stale, no_ambient, no_second, no_emission, wrong_light, wrong_cb = row['pixels']
                self.assertEqual(row['name'], vector['name'])
                self.assertTrue(row['completed'])
                for c in range(3):
                    self.assertGreater(full[c]-a[c], 0.02)
                    expected = a[c] + vector['expected_visibility']*(full[c]-a[c])
                    # Half attachment: two representable half steps, fixed before GPU execution.
                    tolerance = 2 * max(2**-24, 2**(math.floor(math.log2(abs(expected))) - 10)) if expected else 2**-23
                    self.assertLessEqual(abs(actual[c]-expected), tolerance)
                self.assertEqual([p[3] for p in row['pixels']], [0.75]*9)
                self.assertEqual(stale, full)
                self.assertEqual(wrong_light, full)
                self.assertEqual(wrong_cb, full)
                if vector['expected_visibility'] == 1: self.assertEqual(actual, full)

    def test_ambient_emission_and_other_directional_light_are_preserved(self):
        for row in self.report['rows']:
            with self.subTest(vector=row['name']):
                a, _, _, _, no_ambient, no_second, no_emission, _, _ = row['pixels']
                for c in range(3):
                    self.assertGreater(a[c]-no_ambient[c], 0.005)
                    self.assertGreater(a[c]-no_second[c], 0.005)
                    self.assertGreater(a[c]-no_emission[c], 0.005)

PARSER_MAIN = r'''
@main enum ShadowAuthoredProbe {
 static func main() throws {
  let root = try JSONDecoder().decode(String.self, from: Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
  let model = try SceneRuntimeModelBuilder().build(rootURL:URL(fileURLWithPath:root))
  var checks:[String:Bool] = [:]
  let expected = ["omitted","enabled","disabled","invalid","invalid","invalid","enabled","disabled","invalid"]
  for (index,intent) in expected.enumerated() {
   let object = model.sceneDocument.objects.first { $0.id == 100+index }!
   let layer = model.renderDescriptor.layers.first { $0.id == 100+index }!
   checks["model-\(index)-document"] = object.modelShadowCastIntent.rawValue == intent
   checks["model-\(index)-descriptor"] = layer.modelShadowCastIntent?.rawValue == intent
   let light = model.renderDescriptor.layers.first { $0.id == 200+index }!.directionalLight!
   checks["light-\(index)-descriptor"] = light.shadowCastIntent?.rawValue == intent
  }
  var oldLayer = try JSONSerialization.jsonObject(with:JSONEncoder().encode(model.renderDescriptor.layers[0])) as! [String:Any]
  oldLayer.removeValue(forKey:"modelShadowCastIntent")
  let decodedLayer = try JSONDecoder().decode(SceneRenderDescriptor.Layer.self,from:JSONSerialization.data(withJSONObject:oldLayer))
  checks["old-layer-decode-missing-shadow-key"] = decodedLayer.modelShadowCastIntent == nil
  let oldLight = try JSONDecoder().decode(SceneDirectionalLightDefinition.self,from:Data("{\"colorRGB\":[1,1,1],\"intensity\":1}".utf8))
  checks["old-light-decode-missing-shadow-key"] = oldLight.shadowCastIntent == nil
  let lights = SceneLightSnapshot.make(descriptor:model.renderDescriptor,worldFramesByLayerID:Dictionary(uniqueKeysWithValues:model.renderDescriptor.layers.map { ($0.id,matrix_identity_float4x4) }))
  checks["snapshot-budget-four"] = lights.directional.count == 4
  checks["snapshot-intent-not-default-true"] = lights.directional.map(\.castsShadow) == [false,true,false,false]
  checks["snapshot-preserves-layer-identity"] = lights.directional.compactMap(\.layerID) == [200,201,202,203]
  print(String(decoding:try JSONSerialization.data(withJSONObject:checks,options:[.sortedKeys]),as:UTF8.self))
 }
}
'''

class SceneDirectionalShadowAuthoredTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from script.tests import test_scene_alpha_display_builder_fixture as builder
        from script.tests.test_scene_directional_shadow_integration import fixture_entries
        scene, entries = fixture_entries()
        values = ['omitted', True, False, 1, 'true', None, {'value': True}, {'value': False}, {'value': None}]
        scene['objects'] = []
        for index, value in enumerate(values):
            model = {'id': 100+index, 'model':'models/caster.mdl', 'origin':'0 96 0'}
            light = {'id': 200+index, 'light':'ldirectional', 'intensity':1, 'color':'1 1 1'}
            if value != 'omitted':
                model['castshadow'] = value
                light['castshadow'] = value
            scene['objects'].append(model)
            scene['objects'].append(light)
        entries['scene.json'] = json.dumps(scene).encode()
        root = Path(tempfile.mkdtemp(prefix='directional-shadow-authored-'))
        (root/'project.json').write_text(json.dumps({'type':'scene','file':'scene.json'}))
        for name, content in entries.items():
            path = root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(content)
        sources = list(builder.SWIFT_SOURCES)
        for path in [model_fixture.LIGHT_SOURCE, model_fixture.DYNAMIC_LAYER_VALUES_SOURCE]:
            if path not in sources: sources.append(path)
        cls.report = run_swift(sources, 'import simd\n'+builder.HARNESS_SOURCE.split('@main',1)[0]+PARSER_MAIN, label='authored', input_value=str(root))

    def test_actual_parser_descriptor_and_light_budget(self):
        for key, value in self.report.items():
            if not key.startswith('old-'): self.assertTrue(value, key)

    def test_old_codable_missing_shadow_keys(self):
        self.assertTrue(self.report['old-layer-decode-missing-shadow-key'])
        self.assertTrue(self.report['old-light-decode-missing-shadow-key'])

if __name__ == '__main__':
    unittest.main()
