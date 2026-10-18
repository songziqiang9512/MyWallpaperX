import Dispatch

@main enum PendingDepthProbe {
 struct Frame {
  let command: MTLCommandBuffer
  let output: MTLTexture
  let state: SceneMetalRenderer.StaticModelFrame
  let leases: [SceneParticleDepthTargetLease]
  let encoded: [Int: Bool]
  let deferral: String?
 }

 static func main() throws {
  let late = try run(usePreparation: false)
  if late["metalUnavailable"] as? Bool == true {
   print("{\"metalUnavailable\":true}"); return
  }
  let prepared = try run(usePreparation: true)
  print(String(decoding: try JSONSerialization.data(withJSONObject: ["cases": [late, prepared]],
   options: [.sortedKeys]), as: UTF8.self))
 }

 static func run(usePreparation: Bool) throws -> [String: Any] {
  guard let device = MTLCreateSystemDefaultDevice(),
        let queue = device.makeCommandQueue(), let gate = device.makeSharedEvent() else {
   return ["metalUnavailable": true]
  }
  let pipeline = SceneStaticModelPipeline(device: device)!
  let whiteDescriptor = MTLTextureDescriptor.texture2DDescriptor(
   pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
  whiteDescriptor.storageMode = .shared; whiteDescriptor.usage = .shaderRead
  let white = device.makeTexture(descriptor: whiteDescriptor)!
  let whitePixel: [UInt8] = [255, 255, 255, 255]
  whitePixel.withUnsafeBytes {
   white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                 withBytes: $0.baseAddress!, bytesPerRow: 4)
  }
  // Owned symmetric geometry. Both entries share the exact mesh and identity;
  // there is no corpus geometry, cull experiment, property VM or App admission.
  let vertices = [SIMD3<Float>(-0.15, -0.15, 0), SIMD3(0.15, -0.15, 0),
                  SIMD3(0.15, 0.15, 0), SIMD3(-0.15, 0.15, 0)].map {
   SceneMdlStaticModel.Vertex(position: $0, normal: SIMD3(0, 0, 1),
    tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(repeating: 0.5))
  }
  let mesh = pipeline.makeMesh(vertices: vertices, indices: [0, 1, 2, 0, 2, 3])!
  func entry(_ color: SIMD3<Float>) -> ScenePreparedStaticModelResources.Entry {
   var material = SceneStaticModelMaterial(color: color, opacity: 1,
    receivesLighting: false, textureAlphaIsOpacity: false, textureAlphaIsTintMask: false,
    emissiveColor: .zero, emissiveBrightness: 0, brightness: 1,
    usesHDRBrightness: false, viewTint: nil)
   material.cullMode = .none
   return .init(materialPath: "owned-pending-depth", dynamicMaterialPath: "",
    geometryIdentity: "owned-same-unit-quad", mesh: mesh,
    albedo: PreparedTexture(texture: white), material: material,
    writesDepth: true, materialBlending: .normal)
  }
  let renderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline,
   entries: [1: [entry(SIMD3(1, 0, 0))], 2: [entry(SIMD3(0, 1, 0))]]))
  let layers = [SceneRenderDescriptor.Layer(id: 1), .init(id: 2)]
  let camera = SceneParticleCameraFrame(camera: renderer.renderDescriptor.camera,
   viewportSize: CGSize(width: 64, height: 64))
  let lighting = SceneLightSnapshot(ambient: SIMD3(repeating: 1), skylight: .zero,
   directional: [], point: [], spot: [], overflowCount: 0)
  let dynamic = SceneDynamicSnapshot.empty(frameIndex: 1, generation: 1)
  let world = Dictionary(uniqueKeysWithValues: zip([1, 2], [Float(65), 65.1]).map { id, scale in
   (id, SceneMatrix.translation(SIMD3(32, 32, 0)) * SceneMatrix.scale(SIMD3(repeating: scale)))
  })

  func encode(_ blocked: Bool) -> Frame {
   let command = queue.makeCommandBuffer()!
   if blocked { command.encodeWaitForEvent(gate, value: 1) }
   let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
   descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
   let output = device.makeTexture(descriptor: descriptor)!
   let sentinel = [UInt8](repeating: 17, count: 64 * 64 * 4)
   sentinel.withUnsafeBytes { output.replace(region: MTLRegionMake2D(0, 0, 64, 64),
    mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 64 * 4) }
   let pass = SceneMainPassEncoder(commandBuffer: command, target: output,
    clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
   let state = SceneMetalRenderer.StaticModelFrame()
   var leases: [SceneParticleDepthTargetLease] = []
   renderer.dependencyRuntime.encoded.removeAll()
   if usePreparation {
    let candidates = renderer.shadowDrawCandidates(orderedLayers: layers, visible: [1, 2],
     worldFrames: world, snapshot: dynamic, groups: nil)!
    _ = renderer.prepareMandatoryDepth(state: state, candidates: candidates, orderedLayers: layers,
     visible: [1, 2], batches: [:], particlePipeline: nil, mainPass: pass, groups: nil,
     commandBuffer: command, leases: &leases)
   }
   for layer in layers where state.depthDeferralReason == nil {
    _ = renderer.drawStaticModel(layer: layer, state: state, worldFrames: world,
     frameContext: .init(dynamicValues: dynamic), cameraFrame: camera,
     lighting: lighting, pass: pass, commandBuffer: command, leases: &leases)
   }
   if state.depthDeferralReason == nil { precondition(pass.finishEnsuringClear()) }
   else { pass.closeForOffscreen() }
   if state.depthDeferralReason == nil {
    leases.forEach { $0.arm(on: command) }; state.arm(on: command)
   }
   return Frame(command: command, output: output, state: state,
                leases: leases, encoded: renderer.dependencyRuntime.encoded,
                deferral: state.depthDeferralReason)
  }
  func rgb(_ frame: Frame) -> [Int] {
   var pixel = [UInt8](repeating: 0, count: 4)
   frame.output.getBytes(&pixel, bytesPerRow: 4,
    from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0)
   return [Int(pixel[2]), Int(pixel[1]), Int(pixel[0]), Int(pixel[3])]
  }
  func observation(_ name: String, _ frame: Frame) -> [String: Any] {
   ["phase": name, "leaseCount": frame.leases.count,
    "encodedLayerIDs": layers.filter { frame.encoded[$0.id] == true }.map(\.id),
    "centerRGBA": rgb(frame), "completed": frame.command.status == .completed,
    "gpuError": frame.command.error.map(String.init(describing:)) ?? "none",
    "deferral": frame.deferral ?? "none"]
  }
  // A submitted shared-event wait makes pending status deterministic. The
  // bounded watchdog only releases the gate; it cannot turn a late run into
  // a valid reproduction because firstStillPending is part of the result.
  defer { gate.signaledValue = 1 }
  DispatchQueue.global().asyncAfter(deadline: .now() + 5) { gate.signaledValue = 1 }
  let first = encode(true)
  let firstDone = DispatchSemaphore(value: 0)
  first.command.addCompletedHandler { _ in firstDone.signal() }
  first.command.commit()
  let second = encode(false)
  let firstStillPending = first.command.status != .completed && gate.signaledValue == 0
  // The frame owner has classified busy. Cancel the unsubmitted candidate;
  // the production propagation to FrameOutcome is separately exercised by App.
  second.state.cancel(); second.leases.forEach { $0.cancel() }
  let pendingBytes = renderer.staticModelDepthTargetPool.residentByteCost
  gate.signaledValue = 1
  first.command.waitUntilCompleted()
  let completionsObserved = firstDone.wait(timeout: .now() + 10) == .success
  let recovered = encode(false)
  let recoveredDone = DispatchSemaphore(value: 0)
  recovered.command.addCompletedHandler { _ in recoveredDone.signal() }
  recovered.command.commit(); recovered.command.waitUntilCompleted()
  let recoveredCompletion = recoveredDone.wait(timeout: .now() + 10) == .success
  let rows = [observation("first-held", first), observation("second-while-first-pending", second),
              observation("after-completion", recovered)]
  let firstRGB = rgb(first), secondRGB = rgb(second), recoveredRGB = rgb(recovered)
  var checks: [String: Bool] = [
   "actual-first-submission-held": firstStillPending,
   "first-two-leases-and-both-draws": first.leases.count == 2
    && first.encoded[1] == true && first.encoded[2] == true,
   "second-busy-is-owned-frame-decision": second.leases.count == 1
    && second.deferral == "static-model-depth-in-flight",
   "second-remains-unsubmitted": second.command.status == .notEnqueued,
   "cancelled-pixels-untouched": secondRGB == [17, 17, 17, 17],
   "completion-restores-both-draws": recovered.leases.count == 2
    && recovered.deferral == nil && recovered.encoded[1] == true && recovered.encoded[2] == true,
   "pixel-recovers-without-partial-presentation": firstRGB == [0, 255, 0, 255]
    && recoveredRGB == firstRGB,
   "actual-completion-callbacks-observed": completionsObserved && recoveredCompletion,
   "submitted-gpu-completed": [first, recovered].allSatisfy {
    $0.command.status == .completed && $0.command.error == nil },
   "no-resident-growth-after-completion": pendingBytes
    == renderer.staticModelDepthTargetPool.residentByteCost
  ]
  let intrinsic = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline,
   entries: [1: [entry(SIMD3(1, 0, 0))], 2: [entry(SIMD3(0, 1, 0))],
             3: [entry(SIMD3(0, 0, 1))], 4: [entry(SIMD3(1, 1, 0))]]))
  let intrinsicCB = queue.makeCommandBuffer()!
  let intrinsicPass = SceneMainPassEncoder(commandBuffer: intrinsicCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
  let intrinsicState = SceneMetalRenderer.StaticModelFrame()
  var intrinsicLeases: [SceneParticleDepthTargetLease] = []
  let intrinsicWorld = Dictionary(uniqueKeysWithValues: (1...4).map { id in
   (id, SceneMatrix.translation(SIMD3(32, 32, 0))
    * SceneMatrix.scale(SIMD3(repeating: 65 + Float(id - 1) * 0.1)))
  })
  for id in 1...4 {
   _ = intrinsic.drawStaticModel(layer: .init(id: id), state: intrinsicState,
    worldFrames: intrinsicWorld, frameContext: .init(dynamicValues: dynamic),
    cameraFrame: camera, lighting: lighting, pass: intrinsicPass,
    commandBuffer: intrinsicCB, leases: &intrinsicLeases)
  }
  precondition(intrinsicPass.finishEnsuringClear())
  intrinsicLeases.forEach { $0.arm(on: intrinsicCB) }
  intrinsicState.arm(on: intrinsicCB); intrinsicCB.commit(); intrinsicCB.waitUntilCompleted()
  checks["own-four-draws-do-not-defer"] = intrinsicLeases.count == 3
   && intrinsicState.depthDeferralReason == nil && intrinsic.dependencyRuntime.encoded[4] != true
   && (1...3).allSatisfy { intrinsic.dependencyRuntime.encoded[$0] == true }
   && intrinsicCB.status == .completed && intrinsicCB.error == nil
   && rgb(first) == [0, 0, 255, 255]
  // Direct pool facts exercise current-frame excess versus another owner,
  // owner-matched arm/cancel, invalid extent and physical-budget failure.
  let pool = SceneParticleDepthTargetPool()
  let owner = queue.makeCommandBuffer()!, other = queue.makeCommandBuffer()!
  var own: [SceneParticleDepthTargetLease] = []
  for _ in 0..<3 {
   guard case let .acquired(lease) = pool.acquire(device: device, width: 8, height: 8, on: owner)
   else { preconditionFailure("own depth slots") }
   own.append(lease)
  }
  if case .currentFrameCapacityExceeded = pool.acquire(device: device, width: 8, height: 8, on: owner) {
   checks["own-excess-is-not-busy"] = true
  } else { checks["own-excess-is-not-busy"] = false }
  if case .busyOtherFrame = pool.acquire(device: device, width: 8, height: 8, on: other) {
   checks["other-owner-is-busy"] = true
  } else { checks["other-owner-is-busy"] = false }
  own[0].arm(on: other); other.commit(); other.waitUntilCompleted()
  if case .busyOtherFrame = pool.acquire(device: device, width: 8, height: 8,
                                        on: queue.makeCommandBuffer()!) {
   checks["wrong-cb-cannot-release-reservation"] = true
  } else { checks["wrong-cb-cannot-release-reservation"] = false }
  own.forEach { $0.cancel() }
  let recoveredOwner = queue.makeCommandBuffer()!
  var restored: [SceneParticleDepthTargetLease] = []
  for _ in 0..<3 {
   if case let .acquired(lease) = pool.acquire(device: device, width: 8, height: 8, on: recoveredOwner) {
    restored.append(lease)
   }
  }
  checks["cancel-restores-three-slots"] = restored.count == 3
  restored.forEach { $0.cancel() }
  if case .invalidExtent = pool.acquire(device: device, width: Int.max, height: 8, on: owner) {
   checks["invalid-extent-is-not-busy"] = true
  } else { checks["invalid-extent-is-not-busy"] = false }
  let quota = SceneResourceBudget.shared.maximumBytes - SceneResourceBudget.shared.snapshot.residentBytes
  precondition(SceneResourceBudget.shared.reserve(quota, kind: .gpu))
  let emptyPool = SceneParticleDepthTargetPool()
  if case .allocationFailed = emptyPool.acquire(device: device, width: 128, height: 128, on: owner) {
   checks["physical-refusal-is-not-busy"] = true
  } else { checks["physical-refusal-is-not-busy"] = false }
  SceneResourceBudget.shared.release(quota, kind: .gpu)
  let result: [String: Any] = ["checks": checks, "rows": rows,
   "passed": checks.values.allSatisfy { $0 }, "prepared": usePreparation,
   "boundary": "Actual unchanged StaticModelFrame.depth, pool, draw, main encoder and Metal; prepared-input shell only. Explicit local cancellation after the real frame-owner busy decision; no App/corpus/VM/full admission/flicker-cause claim."]
  return result
 }
}
