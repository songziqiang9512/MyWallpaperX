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
    # Fixed model/image shaders share this canonical response with dynamic
    # ColorBlend. Freeze the include as part of the executed shader identity.
    metal_headers = {metal.parent/header for metal in metal_sources
                     for header in ['SceneDistanceFog.metalh', 'SceneSurfaceResponse.metalh']
                     if (metal.parent/header).is_file()}
    identity_paths = [Path(__file__), REPO/'script/tests/fixtures/scene_directional_shadow_oracle.py',
                      *sources, *metal_sources, *sorted(metal_headers)]
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
   let projection = SceneDirectionalShadowProjection.make(
    bounds: meshes.map { (minimum:$0.boundsMinimum,maximum:$0.boundsMaximum,world:casterWorld) },
    receiverBounds: [(minimum:receiver.boundsMinimum,maximum:receiver.boundsMaximum,world:receiverWorld)],
    directionTowardLight:toward,resolution:1024)
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
    precondition(pipeline.drawShadow(mesh:meshes[index],texture:coverageTexture(c),textureFrame:uvFrame,sampling:SceneTextureSampling(texFlags:sampleFlags),modelMatrix:casterWorld,projection:.directional(projection!),face:0,viewport:MTLViewport(originX:0,originY:0,width:Double(map.width),height:Double(map.height),znear:0,zfar:1),layerAlpha:Float(c["layer_alpha"] as? Double ?? 1),material:material(Float(c["material_opacity"] as? Double ?? 1),covered,tint,c["receives_lighting"] as? Bool ?? true),encoder:encoder))
   }
   encoder.endEncoding()
   let shadow = projection.map { SceneStaticModelShadow(texture:map,frameEpoch:7,generation:1,lightLayerID:10,projection:.directional($0),commandBuffer:cb) }
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
    let lights = SceneLightSnapshot(ambient: SIMD3(repeating: mode == 4 ? 0 : 0.08),skylight: .zero,directional:[
     .init(layerID:10,castsShadow:true,directionTowardLight:toward,color:SIMD3(repeating:1),intensity:selected),
     .init(layerID:11,directionTowardLight:SIMD3(0,0,1),color:SIMD3(0.5,0.7,1),intensity:mode == 5 ? 0 : 0.2)],point:[],spot:[],overflowCount:0)
    let enabled = v["shadow_enabled"] as? Bool ?? true
    let wrongLight = projection.map { SceneStaticModelShadow(texture:map,frameEpoch:7,generation:1,lightLayerID:999,projection:.directional($0),commandBuffer:cb) }
    let testedShadow = mode == 7 ? wrongLight : shadow
    precondition(pipeline.draw(mesh:receiver,texture:albedo,colorTextureIsPremultiplied:false,emissiveMask:emissionMask,emissiveMaskTextureFrame:.identity,emissiveMaskSampling:.linearClamp,modelMatrix:receiverWorld,viewProjection:view,cameraPosition:SIMD3(Float(position[0]),Float(position[1]),100),textureFrame:.identity,sampling:.linearClamp,layerAlpha:0.75,material:material(1,false,false,true,mode == 6 ? 0 : 0.8),lighting:lights,writesDepth:true,shadows:(mode == 2 || mode == 3 || mode >= 7) && enabled ? testedShadow.map { [$0] } ?? [] : [],frameEpoch:mode == 3 ? 8 : 7,commandBuffer:mode == 8 ? queue.makeCommandBuffer()! : cb,encoder:e))
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
        sources = [getattr(model_fixture, name) for name in ['MODEL_SOURCE', 'SAMPLING_SOURCE', 'UV_TRANSFORM_SOURCE', 'DIRECTIONAL_LIGHT_SOURCE', 'POINT_LIGHT_SOURCE', 'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'VISIBILITY_SOURCE', 'DYNAMIC_SNAPSHOT_SOURCE', 'DYNAMIC_LAYER_VALUES_SOURCE', 'PERFORMANCE_COUNTER_SOURCE', 'MATERIAL_SOURCE', 'PIPELINE_SOURCE', 'SHADOW_SOURCE']] + [SCENE/'Runtime/Frame/SceneStaticModelMaterialBindings.swift']
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
                    # Direct-light positivity margin: official energy factor
                    # k=0.30 scales the direct term; the margin tracks that
                    # magnitude (observed 0.014-0.019 across vectors).
                    self.assertGreater(full[c]-a[c], 0.01)
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
                    # Ambient energy is ramp-halved by the official
                    # ambient-only hemisphere weight (1+n.y)/2 (2026-10-09);
                    # the positivity threshold tracks the halved magnitude.
                    self.assertGreater(a[c]-no_ambient[c], 0.004)
                    self.assertGreater(a[c]-no_second[c], 0.004)
                    self.assertGreater(a[c]-no_emission[c], 0.004)

FILTER_KERNEL = r'''
kernel void shadowFilterProbe(constant float4 *points [[buffer(0)]],
    constant SceneModelShadowUniforms *uniforms [[buffer(1)]],
    device float4 *results [[buffer(2)]], depth2d<float> map [[texture(0)]],
    depth2d<float> atlas [[texture(1)]], uint index [[thread_position_in_grid]]) {
    float2 uv = points[index].xy;
    float3 flat(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y, 0.5);
    results[index] = float4(
        sceneDirectionalVisibility(flat, float3(1,0,0), float3(0,1,0), map, uniforms[0]),
        sceneSpotVisibility(float3(flat.xy * 0.5, 0.5), float3(1,0,0), float3(0,1,0), map, uniforms[1]),
        scenePointVisibility(float3(flat.xy * 0.5, 0.5), float3(1,0,0), float3(0,1,0), atlas, uniforms[2]),
        sceneDirectionalVisibility(float3(flat.xy, 0.9), float3(1,0,2), float3(0,1,0), map, uniforms[0]));
}
'''

FILTER_MAIN = r'''
struct FilterUniforms {
    var transform:simd_float4x4 = matrix_identity_float4x4
    var positionRadius=SIMD4<Float>(0,0,0,2)
    var parameters=SIMD4<Float>(1,0,0,0)
    var identity=SIMD4<UInt32>(0,0,1,0)
}
@main enum FilterProbe {
 static func main() throws {
    let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
    let d=MTLCreateSystemDefaultDevice()!,q=d.makeCommandQueue()!
    let lib=try d.makeLibrary(URL:URL(fileURLWithPath:"default.metallib"))
    let p=try d.makeComputePipelineState(function:lib.makeFunction(name:"shadowFilterProbe")!)
    let points=input.map { row -> SIMD4<Float> in let uv=row["uv"] as! [Double];return SIMD4(Float(uv[0]),Float(uv[1]),0,0) }
    let pointBuffer=d.makeBuffer(bytes:points,length:MemoryLayout<SIMD4<Float>>.stride*points.count)!
    let uniforms=[FilterUniforms(),FilterUniforms(),FilterUniforms()]
    let uniformBuffer=d.makeBuffer(bytes:uniforms,length:MemoryLayout<FilterUniforms>.stride*3)!
    var rows:[[String:Any]]=[]
    for pattern in ["step","checker","blocked"] {
        let cb=q.makeCommandBuffer()!
        func map(_ width:Int,_ height:Int)->MTLTexture {
            let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:width,height:height,mipmapped:false)
            td.storageMode = .private;td.usage = .shaderRead
            let t=d.makeTexture(descriptor:td)!,stride=256
            let b=d.makeBuffer(length:stride*height,options:.storageModeShared)!
            for y in 0..<height { for x in 0..<width {
                let xx=x%4,yy=y%4
                let value:Float=pattern=="blocked" ? 0 : (pattern=="step" ? (xx>=2 ? 1:0) : ((xx+yy)%2==1 ? 1:0))
                b.contents().advanced(by:y*stride+x*4).storeBytes(of:value,as:Float.self)
            }}
            let e=cb.makeBlitCommandEncoder()!
            e.copy(from:b,sourceOffset:0,sourceBytesPerRow:stride,sourceBytesPerImage:stride*height,sourceSize:.init(width:width,height:height,depth:1),to:t,destinationSlice:0,destinationLevel:0,destinationOrigin:.init(x:0,y:0,z:0));e.endEncoding()
            return t
        }
        let depth=map(4,4),atlas=map(12,8),out=d.makeBuffer(length:16*points.count,options:.storageModeShared)!
        let e=cb.makeComputeCommandEncoder()!;e.setComputePipelineState(p)
        e.setBuffer(pointBuffer,offset:0,index:0);e.setBuffer(uniformBuffer,offset:0,index:1);e.setBuffer(out,offset:0,index:2)
        e.setTexture(depth,index:0);e.setTexture(atlas,index:1)
        e.dispatchThreads(.init(width:points.count,height:1,depth:1),threadsPerThreadgroup:.init(width:1,height:1,depth:1));e.endEncoding()
        cb.commit();cb.waitUntilCompleted()
        let ptr=out.contents().bindMemory(to:SIMD4<Float>.self,capacity:points.count)
        rows.append(["pattern":pattern,"completed":cb.status == .completed && cb.error == nil,
            "values":(0..<points.count).map{[ptr[$0].x,ptr[$0].y,ptr[$0].z,ptr[$0].w]}])
    }
    print(String(data:try JSONSerialization.data(withJSONObject:["rows":rows]),encoding:.utf8)!)
 }
}
'''

class SceneShadowFilterFootprintTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Frozen 4x4 depth maps: central checker cells [0,1;1,0] and a vertical
        # step. These exact dyadic phase expectations precede GPU execution.
        cls.vectors = [
            {'name':'first-center','uv':[.375,.375],'step':0,'checker':0},
            {'name':'quarter','uv':[.4375,.4375],'step':.25,'checker':.375},
            {'name':'half','uv':[.5,.5],'step':.5,'checker':.5},
            {'name':'three-quarters','uv':[.5625,.5625],'step':.75,'checker':.375},
            {'name':'second-center','uv':[.625,.375],'step':1,'checker':1}]
        parent=REPO/'.artifacts/tmp'
        parent.mkdir(parents=True,exist_ok=True)
        root=Path(tempfile.mkdtemp(prefix='shadow-filter-source-',dir=parent))
        product=model_fixture.METAL_SOURCE
        snapshot=os.environ.get('MWX_DIRECTIONAL_SHADOW_PRODUCT_SNAPSHOT')
        if snapshot: product=Path(snapshot)/product.relative_to(REPO)
        before=hashlib.sha256(product.read_bytes()).hexdigest()
        source=root/'SceneStaticModel.metal';source.write_text(product.read_text()+FILTER_KERNEL)
        for name in ['SceneDistanceFog.metalh','SceneSurfaceResponse.metalh']:
            (root/name).write_bytes((product.parent/name).read_bytes())
        (root/'product-identity.json').write_text(json.dumps({str(product):before},indent=2))
        layout,main=FILTER_MAIN.split('@main',1)
        layout_source=root/'FilterUniforms.swift';layout_source.write_text('import simd\n'+layout)
        cls.report=run_swift([layout_source], 'import Foundation\nimport Metal\nimport simd\n@main'+main,
            label='shared-filter',metal_sources=[source],input_value=cls.vectors)
        if hashlib.sha256(product.read_bytes()).hexdigest()!=before: raise AssertionError('product drift')

    def test_exact_centers_quarter_and_half_phase_for_all_three_lights(self):
        self.assertEqual({row['pattern'] for row in self.report['rows']},{'step','checker','blocked'})
        for row in self.report['rows']:
            self.assertTrue(row['completed'])
            self.assertEqual(len(row['values']),len(self.vectors))
            for vector,values in zip(self.vectors,row['values']):
                want=0 if row['pattern']=='blocked' else vector[row['pattern']]
                with self.subTest(pattern=row['pattern'],phase=vector['name']):
                    for value in values[:3]: self.assertAlmostEqual(value,want,delta=2**-20)

    def test_invalid_directional_taps_keep_only_their_own_weight(self):
        row=next(r for r in self.report['rows'] if r['pattern']=='blocked')
        # The plane is z=.9+2*dx: right taps at the three interior phases leave
        # [0,1], left taps remain behind a zero-depth occluder. No renormalizing.
        for index,want in [(1,.25),(2,.5),(3,.75)]:
            self.assertAlmostEqual(row['values'][index][3],want,delta=2**-20)



# Numeric public geometry only; no media dependency or runtime sample dispatch.
SKINNY_PLANE_INPUT = {'receiver': [-1.1132866558811105, -0.8784986201299999, -0.9979555472746794],
 'receiver_normal': [-0.3180197775363922, 0.893155574798584, 0.3180197775363922],
 'receiver_triangles': [[[-7.788613796234131, -5.160461902618408, 6.679943084716797],
                         [-6.612985134124756, -4.388819217681885, 5.688652992248535],
                         [-7.048151016235352, -4.60972785949707, 5.873840808868408]]],
 'caster_triangles': [[[-8.274378776550293, -5.582437992095947, 7.379165172576904],
                       [-7.161378860473633, -4.9107890129089355, 6.606048107147217],
                       [-6.863584041595459, -4.618021011352539, 6.081696033477783]],
                      [[-7.788613796234131, -5.160461902618408, 6.679943084716797],
                       [-6.612985134124756, -4.388819217681885, 5.688652992248535],
                       [-7.048151016235352, -4.60972785949707, 5.873840808868408]],
                      [[-6.656628131866455, -4.208202838897705, 5.1378068923950195],
                       [-7.463845252990723, -4.6116251945495605, 5.463473796844482],
                       [-8.230224609375, -5.16533088684082, 6.252005100250244]],
                      [[-7.463845252990723, -4.6116251945495605, 5.463473796844482],
                       [-8.468241691589355, -5.141155242919922, 5.946095943450928],
                       [-8.71441650390625, -5.376636981964111, 6.361202239990234]]],
 'model_matrix': [0.22153723239898682,
                  0.03255791589617729,
                  -0.054652415215969086,
                  0,
                  -0.04609108343720436,
                  0.21862949430942535,
                  -0.056589774787425995,
                  0,
                  0.04384651407599449,
                  0.06532054394483566,
                  0.21664799749851227,
                  0,
                  0,
                  0,
                  -3,
                  1],
 'camera_matrix': [1685.5826568603516,
                   0.0,
                   0.0,
                   0.0,
                   0.0,
                   1685.5826354026794,
                   0.0,
                   0.0,
                   -569.0,
                   -449.0,
                   9.5367431640625e-07,
                   -1.0,
                   1308.6999728679657,
                   1032.6999785900116,
                   0.009997844696044922,
                   2.299999952316284],
 'shadow_matrix': [-0.0008051993208937347,
                   0,
                   0.0048917848616838455,
                   0,
                   0,
                   0.020798927173018456,
                   0,
                   0,
                   -0.03488016501069069,
                   0,
                   -0.00011292555427644402,
                   0,
                   0.4087190628051758,
                   0.776597261428833,
                   0.9127105474472046,
                   1],
 'depth_bias': 9.5367431640625e-07,
 'toward_light': [-0.9997336864471436, 0.0, 0.023078586906194687],
 'light_intensity': 1,
 'local_gap_axis': [-4.192692865758798, 0.8427716423078392, -0.7310012040704149],
 'native_shadow': True}

def skinny_plane_vectors():
    from script.tests.fixtures.scene_directional_shadow_oracle import ray_triangle, cross, sub, dot
    # Oblique coplanar strip and declared fixed frustum: tiny projected
    # triangles expose raster-depth error without changing the receiver bias.
    base=SKINNY_PLANE_INPUT
    cases=[('self',[(0,False,False)],1),('positive-gap',[(.001,False,False)],0),
           ('negative-gap',[(-.001,False,False)],1),('backface-gap',[(.001,True,False)],1),
           ('thin-normal',[(0,False,False),(.001,True,False)],1),
           ('thin-nocull',[(0,False,False),(.001,True,True)],0)]
    result=[]
    for name,planes,wanted in cases:
        row=copy.deepcopy(base);row['name']='skinny-'+name;row['casters']=[]
        for gap,reverse,nocull in planes:
            triangles=[[[p[i]+gap*base['local_gap_axis'][i] for i in range(3)] for p in tri] for tri in base['caster_triangles']]
            if reverse: triangles=[[tri[0],tri[2],tri[1]] for tri in triangles]
            row['casters'].append({'triangles':triangles,'nocull':nocull})
        # Independent physical ray plus declared normal/nocull admission.
        blocked=False;m=base['model_matrix']
        for caster in row['casters']:
            for tri in caster['triangles']:
                world=[[sum(m[c*4+r]*p[c] for c in range(3))+m[12+r] for r in range(3)] for p in tri]
                normal=cross(sub(world[1],world[0]),sub(world[2],world[0]))
                if not caster['nocull'] and dot(normal,base['toward_light'])<=0: continue
                blocked |= ray_triangle(base['receiver'],base['toward_light'],world) is not None
        assert (0 if blocked else 1)==wanted,(name,blocked)
        row['expected_visibility']=wanted;result.append(row)
    return result


def skinny_plane_main():
    # Reuse the established real Pipeline harness; only fixture geometry,
    # frustum/camera and declared native winding are parameterized here.
    code=PIXEL_MAIN.replace('func mesh(_ triangles: [[[Double]]])', 'func mesh(_ triangles: [[[Double]]], normal:SIMD3<Float> = SIMD3(0,0,1))')
    code=code.replace('normal: SIMD3(0,0,1)', 'normal: normal')
    code=code.replace('let albedo = texture(1)', 'func matrix(_ a:[Double])->simd_float4x4 {let f=a.map(Float.init);return simd_float4x4(columns:(SIMD4(f[0],f[1],f[2],f[3]),SIMD4(f[4],f[5],f[6],f[7]),SIMD4(f[8],f[9],f[10],f[11]),SIMD4(f[12],f[13],f[14],f[15])))}\n  let albedo = texture(1)')
    old='let receiver = mesh([[[x0,y0,receiverZ],[x1,y1,receiverZ],[x1,y0,receiverZ]],[[x0,y0,receiverZ],[x0,y1,receiverZ],[x1,y1,receiverZ]]])'
    code=code.replace(old, 'let normal=v["receiver_normal"] as! [Double]\n   let receiver=mesh(v["receiver_triangles"] as! [[[Double]]],normal:SIMD3(Float(normal[0]),Float(normal[1]),Float(normal[2])))')
    code=code.replace('var casterWorld = matrix_identity_float4x4','var casterWorld = matrix(v["model_matrix"] as! [Double])')
    code=code.replace('var receiverWorld = matrix_identity_float4x4','var receiverWorld = matrix(v["model_matrix"] as! [Double])')
    start=code.index('   let projection = SceneDirectionalShadowProjection.make(')
    end=code.index('   let cb = queue.makeCommandBuffer()!',start)
    code=code[:start]+'   let projection:SceneDirectionalShadowProjection? = .init(worldToClip:matrix(v["shadow_matrix"] as! [Double]),depthBias:Float(v["depth_bias"] as! Double))\n'+code[end:]
    code=code.replace('    precondition(pipeline.drawShadow(', '    var casterMaterial=material(Float(c["material_opacity"] as? Double ?? 1),covered,tint,c["receives_lighting"] as? Bool ?? true)\n    if c["nocull"] as? Bool == true {casterMaterial.cullMode = .none}\n    precondition(pipeline.drawShadow(')
    code=code.replace('material:material(Float(c["material_opacity"] as? Double ?? 1),covered,tint,c["receives_lighting"] as? Bool ?? true)', 'material:casterMaterial')
    code=code.replace('encoder:encoder))','encoder:encoder,frontFacing:.clockwise))')
    start=code.index('   let scale = Float(v[');end=code.index('   var buffers:',start)
    return code[:start]+'   let view=matrix(v["camera_matrix"] as! [Double])\n'+code[end:]


class SceneDirectionalShadowCasterPlaneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors=skinny_plane_vectors()
        sources=[getattr(model_fixture,name) for name in ['MODEL_SOURCE','SAMPLING_SOURCE','UV_TRANSFORM_SOURCE','DIRECTIONAL_LIGHT_SOURCE','POINT_LIGHT_SOURCE','SPOT_LIGHT_SOURCE','LIGHT_SOURCE','VISIBILITY_SOURCE','DYNAMIC_SNAPSHOT_SOURCE','DYNAMIC_LAYER_VALUES_SOURCE','PERFORMANCE_COUNTER_SOURCE','MATERIAL_SOURCE','PIPELINE_SOURCE','SHADOW_SOURCE']]
        sources += [SCENE/'Runtime/Frame/SceneStaticModelMaterialBindings.swift',SCENE/'Resources/Textures/SceneResourceBudget.swift']
        cls.report=run_swift(sources,'import Foundation\nimport Metal\nimport simd\n'+model_fixture.LIGHTING_STUB+skinny_plane_main(),label='skinny-caster-plane',metal_sources=[model_fixture.METAL_SOURCE],input_value=cls.vectors)

    def test_coplanar_self_signed_gap_and_culled_or_covered_thin_sheet(self):
        self.assertEqual(len(self.report['rows']),len(self.vectors))
        for vector,row in zip(self.vectors,self.report['rows']):
            with self.subTest(case=vector['name']):
                self.assertTrue(row['completed'])
                a,full,actual,stale,_,_,_,wrong,other=row['pixels']
                for channel in range(3):
                    self.assertGreater(full[channel]-a[channel],.01)
                    want=a[channel]+vector['expected_visibility']*(full[channel]-a[channel])
                    tolerance=2*max(2**-24,2**(math.floor(math.log2(abs(want)))-10)) if want else 2**-23
                    self.assertLessEqual(abs(actual[channel]-want),tolerance)
                self.assertEqual([p[3] for p in row['pixels']],[.75]*9)
                self.assertEqual(stale,full);self.assertEqual(wrong,full);self.assertEqual(other,full)


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
        # Official gating: absent general.lightconfig leaves directional lights
        # inert for static models (own-fixture N-series, 2026-10-06); this
        # budget probe needs the class admitted to exercise the 4-slot cap.
        scene['general']['lightconfig'] = {'directional': 1}
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
