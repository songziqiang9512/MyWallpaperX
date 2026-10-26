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
  // Owned symmetric geometry. Both entries share the exact mesh;
  // there is no corpus geometry, cull experiment, property VM or App admission.
  let vertices = [SIMD3<Float>(-0.15, -0.15, 0), SIMD3(0.15, -0.15, 0),
                  SIMD3(0.15, 0.15, 0), SIMD3(-0.15, 0.15, 0)].map {
   SceneMdlStaticModel.Vertex(position: $0, normal: SIMD3(0, 0, 1),
    tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(repeating: 0.5))
  }
  let mesh = pipeline.makeMesh(model: SceneStaticModelFixture.model(vertices: vertices, indices: [0, 1, 2, 0, 2, 3]))!
  func entry(_ color: SIMD3<Float>) -> ScenePreparedStaticModelResources.Entry {
   var material = SceneStaticModelMaterial(color: color, opacity: 1,
    receivesLighting: false, textureAlphaIsOpacity: false, textureAlphaIsTintMask: false,
    emissiveColor: .zero, emissiveBrightness: 0, brightness: 1,
    usesHDRBrightness: false, viewTint: nil)
   material.cullMode = .none
   return .init(materialPath: "owned-pending-depth", dynamicMaterialPath: "",
    mesh: mesh,
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
   let state = SceneMetalRenderer.StaticModelFrame(commandBuffer: command)
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
  let held = (0..<3).map { _ in encode(true) }
  let firstDone = DispatchSemaphore(value: 0)
  for frame in held {
   frame.command.addCompletedHandler { _ in firstDone.signal() }
   frame.command.commit()
  }
  let first = held[0], second = encode(false)
  let firstStillPending = held.allSatisfy { $0.command.status != .completed } && gate.signaledValue == 0
  // The frame owner has classified busy. Cancel the unsubmitted candidate;
  // the production propagation to FrameOutcome is separately exercised by App.
  second.state.cancel(); second.leases.forEach { $0.cancel() }
  let pendingBytes = renderer.staticModelDepthTargetPool.residentByteCost
  gate.signaledValue = 1
  held.forEach { $0.command.waitUntilCompleted() }
  let completionsObserved = (0..<3).allSatisfy { _ in firstDone.wait(timeout: .now() + 10) == .success }
  let recovered = encode(false)
  let recoveredDone = DispatchSemaphore(value: 0)
  recovered.command.addCompletedHandler { _ in recoveredDone.signal() }
  recovered.command.commit(); recovered.command.waitUntilCompleted()
  let recoveredCompletion = recoveredDone.wait(timeout: .now() + 10) == .success
  let rows = [observation("three-submissions-held", first), observation("candidate-while-three-pending", second),
              observation("after-completion", recovered)]
  let firstRGB = rgb(first), secondRGB = rgb(second), recoveredRGB = rgb(recovered)
  var checks: [String: Bool] = [
   "actual-three-submissions-held": firstStillPending,
   "pending-frames-each-use-one-domain": held.allSatisfy {
    $0.leases.count == 1 && $0.encoded[1] == true && $0.encoded[2] == true },
   "second-busy-is-owned-frame-decision": second.leases.isEmpty
    && second.deferral == "static-model-depth-in-flight",
   "second-remains-unsubmitted": second.command.status == .notEnqueued,
   "cancelled-pixels-untouched": secondRGB == [17, 17, 17, 17],
   "completion-restores-both-draws": recovered.leases.count == 1
    && recovered.deferral == nil && recovered.encoded[1] == true && recovered.encoded[2] == true,
   "pixel-recovers-without-partial-presentation": firstRGB == [0, 255, 0, 255]
    && recoveredRGB == firstRGB,
   "actual-completion-callbacks-observed": completionsObserved && recoveredCompletion,
   "submitted-gpu-completed": (held + [recovered]).allSatisfy {
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
  let intrinsicState = SceneMetalRenderer.StaticModelFrame(commandBuffer: intrinsicCB)
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
  checks["four-same-pass-models-use-one-domain"] = intrinsicLeases.count == 1
   && intrinsicState.depthDeferralReason == nil
   && (1...4).allSatisfy { intrinsic.dependencyRuntime.encoded[$0] == true }
   && intrinsicCB.status == .completed && intrinsicCB.error == nil
   && rgb(first) == [255, 255, 0, 255]
  // Read actual depth attachment bytes. A color encoder interruption must
  // preserve a prior successful depth clear; each pass has its own first clear.
  func snapshotDepth(_ texture: MTLTexture, _ pass: SceneMainPassEncoder,
                     _ cb: MTLCommandBuffer) -> MTLBuffer {
   pass.closeForOffscreen()
   let buffer = device.makeBuffer(length: 256, options: .storageModeShared)!
   let blit = cb.makeBlitCommandEncoder()!
   blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0,y: 0,z: 0),
    sourceSize: .init(width: 1,height: 1,depth: 1), to: buffer, destinationOffset: 0,
    destinationBytesPerRow: 256, destinationBytesPerImage: 256)
   blit.endEncoding(); return buffer
  }
  func depthValue(_ buffer: MTLBuffer) -> Float {
   buffer.contents().bindMemory(to: Float.self, capacity: 1).pointee
  }
  let terminalPool = SceneParticleDepthTargetPool()
  let terminalCB = queue.makeCommandBuffer()!
  let terminalPass = SceneMainPassEncoder(commandBuffer: terminalCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let terminalState = SceneMetalRenderer.StaticModelFrame(commandBuffer: terminalCB)
  var terminalLeases: [SceneParticleDepthTargetLease] = []
  let a = terminalState.sharedDepth(pass: terminalPass, pool: terminalPool, device: device,
   commandBuffer: terminalCB, leases: &terminalLeases)
  let b = terminalState.sharedDepth(pass: terminalPass, pool: terminalPool, device: device,
   commandBuffer: terminalCB, leases: &terminalLeases)
  checks["terminal-reserve-is-one-lease"] = terminalLeases.count == 1
   && a.lease?.texture === b.lease?.texture
  let binding = terminalState.terminalDepthBinding(pass: terminalPass, commandBuffer: terminalCB)!
  checks["terminal-first-real-encoder-exists"] = binding.encoder(terminalPass) != nil
  let initialDepth = snapshotDepth(a.lease!.texture, terminalPass, terminalCB)
  precondition(terminalPass.encoder(depthTexture: a.lease!.texture, clearsDepth: true, clearDepth: 0.625) != nil)
  terminalPass.closeForOffscreen()
  checks["terminal-color-pass-preserves-owner"] = terminalPass.withReadableTarget { _, _ in true } == true
   && binding.encoder(terminalPass) != nil && terminalLeases.count == 1
  let resumedDepth = snapshotDepth(a.lease!.texture, terminalPass, terminalCB)
  let groupDescriptor = MTLTextureDescriptor.texture2DDescriptor(
   pixelFormat: .rgba16Float, width: 32, height: 32, mipmapped: false)
  groupDescriptor.storageMode = .private; groupDescriptor.usage = .renderTarget
  let groupTarget = device.makeTexture(descriptor: groupDescriptor)!
  let groupPass = SceneMainPassEncoder(commandBuffer: terminalCB, target: groupTarget,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
  let groupDepth = terminalState.sharedDepth(pass: groupPass, pool: terminalPool, device: device,
   commandBuffer: terminalCB, leases: &terminalLeases)
  checks["terminal-distinct-hdr-pass-has-independent-domain"] = terminalLeases.count == 2
   && groupDepth.lease!.texture !== a.lease!.texture
   && groupDepth.lease!.texture.width == 32 && groupDepth.lease!.texture.height == 32
  precondition(terminalState.sceneDepthEncoder(pass: groupPass, commandBuffer: terminalCB) != nil)
  let groupInitialDepth = snapshotDepth(groupDepth.lease!.texture, groupPass, terminalCB)
  let pinPool = SceneOffscreenTexturePool(device: device, pixelFormat: .bgra8Unorm,
   residentByteBudget: 1024 * 1024)
  let pinned = pinPool.reserveModelShadow(slot: 0, width: 16, height: 16, commandBuffer: terminalCB)!
  terminalState.pins.append(pinned.pin); pinPool.reset()
  let pinBytes = pinPool.residentByteCost, wrongArmCB = queue.makeCommandBuffer()!
  terminalState.arm(on: wrongArmCB); wrongArmCB.commit(); wrongArmCB.waitUntilCompleted()
  checks["terminal-wrong-arm-keeps-binding-and-shadow-pin"] = pinBytes > 0
   && pinPool.residentByteCost == pinBytes && terminalState.pins.count == 1
   && binding.encoder(terminalPass) != nil
   && terminalState.sceneDepthFailureReason == "scene-depth-command-buffer-mismatch"
  terminalPass.closeForOffscreen()
  terminalLeases.forEach { $0.arm(on: terminalCB) }; terminalState.arm(on: terminalCB)
  checks["terminal-binding-expires-at-submission"] = binding.encoder(terminalPass) == nil
  let terminalDone = DispatchSemaphore(value: 0)
  terminalCB.addCompletedHandler { _ in terminalDone.signal() }
  terminalCB.commit(); terminalCB.waitUntilCompleted()
  checks["terminal-correct-arm-releases-shadow-pin-on-completion"] =
   terminalDone.wait(timeout: .now() + 10) == .success && pinPool.residentByteCost == 0
  checks["terminal-first-real-encoder-clears-zero"] = depthValue(initialDepth) == 0
  checks["terminal-reopen-loads-existing-depth"] = depthValue(resumedDepth) == 0.625
  checks["terminal-hdr-pass-first-clear-is-independent"] = depthValue(groupInitialDepth) == 0
  checks["terminal-empty-writer-frame-completes"] = terminalCB.status == .completed && terminalCB.error == nil
  // Invalid consumers are isolated from the healthy encoder/readback above.
  let negativeCB = queue.makeCommandBuffer()!, wrongCB = queue.makeCommandBuffer()!
  let negativePass = SceneMainPassEncoder(commandBuffer: negativeCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let wrongPass = SceneMainPassEncoder(commandBuffer: negativeCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let negativeState = SceneMetalRenderer.StaticModelFrame(commandBuffer: negativeCB)
  var negativeLeases: [SceneParticleDepthTargetLease] = []
  _ = negativeState.sharedDepth(pass: negativePass, pool: terminalPool, device: device,
   commandBuffer: negativeCB, leases: &negativeLeases)
  let negativeBinding = negativeState.terminalDepthBinding(pass: negativePass, commandBuffer: negativeCB)!
  checks["terminal-binding-rechecks-consumer"] = negativeBinding.encoder(wrongPass) == nil
   && negativeState.sceneDepthFailureReason == "scene-depth-terminal-pass-mismatch"
  checks["terminal-binding-rejects-other-pass-and-cb"] =
   negativeState.terminalDepthBinding(pass: wrongPass, commandBuffer: negativeCB) == nil
   && negativeState.terminalDepthBinding(pass: negativePass, commandBuffer: wrongCB) == nil
   && negativeState.sceneDepthFailureReason == "scene-depth-command-buffer-mismatch"
  negativeState.cancel(); negativeLeases.forEach { $0.cancel() }
  let canceledCB = queue.makeCommandBuffer()!
  let canceledPass = SceneMainPassEncoder(commandBuffer: canceledCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let canceledState = SceneMetalRenderer.StaticModelFrame(commandBuffer: canceledCB)
  var canceledLeases: [SceneParticleDepthTargetLease] = []
  _ = canceledState.sharedDepth(pass: canceledPass, pool: terminalPool, device: device,
   commandBuffer: canceledCB, leases: &canceledLeases)
  let canceledBinding = canceledState.terminalDepthBinding(pass: canceledPass, commandBuffer: canceledCB)!
  let cancelPin = pinPool.reserveModelShadow(slot: 0, width: 16, height: 16, commandBuffer: canceledCB)!
  canceledState.pins.append(cancelPin.pin); pinPool.reset()
  precondition(canceledPass.finishEnsuringClear())
  checks["terminal-finished-pass-rejects-encoder"] = canceledBinding.encoder(canceledPass) == nil
  canceledState.cancel(); canceledLeases.forEach { $0.cancel() }
  checks["terminal-binding-expires-on-cancel"] = canceledBinding.encoder(canceledPass) == nil
   && pinPool.residentByteCost == 0
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
  let busyPass = SceneMainPassEncoder(commandBuffer: other, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let busyState = SceneMetalRenderer.StaticModelFrame(commandBuffer: other)
  var busyLeases: [SceneParticleDepthTargetLease] = []
  _ = busyState.sharedDepth(pass: busyPass, pool: pool, device: device,
   commandBuffer: other, leases: &busyLeases)
  _ = busyState.sharedDepth(pass: busyPass, pool: pool, device: device,
   commandBuffer: other, leases: &busyLeases)
  checks["terminal-busy-is-sticky-and-defers"] = busyState.depthDeferralReason == "static-model-depth-in-flight"
   && busyLeases.isEmpty && busyState.terminalDepthBinding(pass: busyPass, commandBuffer: other) == nil
  own[0].arm(on: other); other.commit(); other.waitUntilCompleted()
  if case .busyOtherFrame = pool.acquire(device: device, width: 8, height: 8,
                                        on: queue.makeCommandBuffer()!) {
   checks["wrong-cb-cannot-release-reservation"] = true
  } else { checks["wrong-cb-cannot-release-reservation"] = false }
  let capacityPass = SceneMainPassEncoder(commandBuffer: owner, target: first.output,
   clearColor: MTLClearColorMake(0, 1, 0, 1), clearEnabled: true)
  let capacityState = SceneMetalRenderer.StaticModelFrame(commandBuffer: owner)
  var capacityLeases: [SceneParticleDepthTargetLease] = []
  let refused = capacityState.sharedDepth(pass: capacityPass, pool: pool, device: device,
   commandBuffer: owner, leases: &capacityLeases)
  own[0].cancel()
  let stillRefused = capacityState.sharedDepth(pass: capacityPass, pool: pool, device: device,
   commandBuffer: owner, leases: &capacityLeases)
  if case .currentFrameCapacityExceeded = refused.acquisition,
     case .currentFrameCapacityExceeded = stillRefused.acquisition {
   checks["terminal-current-frame-capacity-is-sticky"] = capacityLeases.isEmpty
    && capacityState.depthDeferralReason == nil
    && capacityState.sceneDepthEncoder(pass: capacityPass, commandBuffer: owner) == nil
  } else { checks["terminal-current-frame-capacity-is-sticky"] = false }
  own.forEach { $0.cancel() }; busyState.cancel()
  precondition(capacityPass.finishEnsuringClear())
  capacityState.arm(on: owner); owner.commit(); owner.waitUntilCompleted()
  checks["terminal-capacity-failure-keeps-healthy-color"] = owner.status == .completed
   && owner.error == nil && rgb(first) == [0, 255, 0, 255]
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
  let sourceRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: nil, entries: [:]))
  let sourceCB = queue.makeCommandBuffer()!
  let sourcePass = SceneMainPassEncoder(commandBuffer: sourceCB, target: first.output,
   clearColor: MTLClearColorMake(0, 1, 0, 1), clearEnabled: true)
  let sourceState = SceneMetalRenderer.StaticModelFrame(commandBuffer: sourceCB)
  var sourceLeases: [SceneParticleDepthTargetLease] = []
  precondition(SceneResourceBudget.shared.reserve(quota, kind: .gpu))
  let emptyPool = SceneParticleDepthTargetPool()
  if case .allocationFailed = emptyPool.acquire(device: device, width: 128, height: 128, on: owner) {
   checks["physical-refusal-is-not-busy"] = true
  } else { checks["physical-refusal-is-not-busy"] = false }
  let excluded = sourceRenderer.unavailableSharedTerminalDepthLayers([20], state: sourceState,
   orderedLayers: [], ordinaryLayerIDs: [21], visible: [20, 21], worldFrames: [:], snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: sourcePass, groups: nil,
   commandBuffer: sourceCB, leases: &sourceLeases)
  checks["source-physical-miss-excludes-before-candidate"] = excluded == [20, 21]
   && sourceState.depthDeferralReason == nil && sourceLeases.isEmpty
   && sourceState.terminalDepthBinding(pass: sourcePass, commandBuffer: sourceCB) == nil
  SceneResourceBudget.shared.release(quota, kind: .gpu)
  // The caller omits only these IDs from preparationLayers before admission.
  // This nearest owner gate proves that a healthy color suffix still submits;
  // graph candidate/ledger absence is covered by the renderer's preflight order.
  precondition(sourcePass.finishEnsuringClear())
  sourceState.arm(on: sourceCB); sourceCB.commit(); sourceCB.waitUntilCompleted()
  checks["source-physical-miss-keeps-healthy-color-submit"] = sourceCB.status == .completed
   && sourceCB.error == nil && rgb(first) == [0, 255, 0, 255]
  let sourceRecoveryCB = queue.makeCommandBuffer()!
  let sourceRecoveryPass = SceneMainPassEncoder(commandBuffer: sourceRecoveryCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let sourceRecoveryState = SceneMetalRenderer.StaticModelFrame(commandBuffer: sourceRecoveryCB)
  var sourceRecoveryLeases: [SceneParticleDepthTargetLease] = []
  let recoveredExclusion = sourceRenderer.unavailableSharedTerminalDepthLayers([20], state: sourceRecoveryState,
   orderedLayers: [], ordinaryLayerIDs: [21], visible: [20, 21], worldFrames: [:], snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: sourceRecoveryPass, groups: nil,
   commandBuffer: sourceRecoveryCB, leases: &sourceRecoveryLeases)
  let recoveredBinding = sourceRecoveryState.terminalDepthBinding(pass: sourceRecoveryPass, commandBuffer: sourceRecoveryCB)
  checks["ordinary-and-source-share-single-qualified-lease"] = recoveredExclusion.isEmpty
   && sourceRecoveryLeases.count == 1
  checks["source-next-frame-recovers-without-writer"] = recoveredExclusion.isEmpty
   && sourceRecoveryLeases.count == 1 && recoveredBinding != nil

  checks["source-recovery-has-real-terminal-encoder"] = recoveredBinding?.encoder(sourceRecoveryPass) != nil
  let sourceDepth = sourceRecoveryState.sharedDepth(pass: sourceRecoveryPass,
   pool: sourceRenderer.staticModelDepthTargetPool, device: device,
   commandBuffer: sourceRecoveryCB, leases: &sourceRecoveryLeases)
  let sourceDepthReadback = snapshotDepth(sourceDepth.lease!.texture, sourceRecoveryPass, sourceRecoveryCB)
  sourceRecoveryPass.closeForOffscreen()
  sourceRecoveryLeases.forEach { $0.arm(on: sourceRecoveryCB) }; sourceRecoveryState.arm(on: sourceRecoveryCB)
  sourceRecoveryCB.commit(); sourceRecoveryCB.waitUntilCompleted()
  checks["source-recovery-completes"] = sourceRecoveryCB.status == .completed && sourceRecoveryCB.error == nil
  checks["source-recovery-clears-at-terminal-encoder"] = depthValue(sourceDepthReadback) == 0
  let sourceBusyOwner = queue.makeCommandBuffer()!
  var heldSourceLeases: [SceneParticleDepthTargetLease] = []
  for _ in 0..<3 {
   guard case let .acquired(lease) = sourceRenderer.staticModelDepthTargetPool.acquire(
    device: device, width: 64, height: 64, on: sourceBusyOwner) else { preconditionFailure("source slots") }
   heldSourceLeases.append(lease)
  }
  let sourceBusyCB = queue.makeCommandBuffer()!
  let sourceBusyPass = SceneMainPassEncoder(commandBuffer: sourceBusyCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let sourceBusyState = SceneMetalRenderer.StaticModelFrame(commandBuffer: sourceBusyCB)
  var sourceBusyLeases: [SceneParticleDepthTargetLease] = []
  _ = sourceRenderer.unavailableSharedTerminalDepthLayers([20], state: sourceBusyState,
   orderedLayers: [], ordinaryLayerIDs: [21], visible: [20, 21], worldFrames: [:], snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: sourceBusyPass, groups: nil,
   commandBuffer: sourceBusyCB, leases: &sourceBusyLeases)
  checks["source-busy-defers-before-admission"] = sourceBusyState.depthDeferralReason == "static-model-depth-in-flight"
   && sourceBusyLeases.isEmpty && sourceBusyCB.status == .notEnqueued
  sourceBusyState.cancel(); sourceBusyPass.closeForOffscreen(); heldSourceLeases.forEach { $0.cancel() }
  // Source and all model parts reserve the same scene pass domain, regardless
  // of authored order. One physical depth allocation is enough for every part.
  let priorityRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline,
   entries: [1: [entry(SIMD3(1, 0, 0)), entry(SIMD3(0, 1, 0)), entry(SIMD3(0, 0, 1))]]))
  let priorityCB = queue.makeCommandBuffer()!
  let priorityPass = SceneMainPassEncoder(commandBuffer: priorityCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let priorityState = SceneMetalRenderer.StaticModelFrame(commandBuffer: priorityCB)
  var priorityLeases: [SceneParticleDepthTargetLease] = []
  let priorityExclusion = priorityRenderer.unavailableSharedTerminalDepthLayers([20], state: priorityState,
   orderedLayers: [.init(id: 20, contentKind: "composition"), .init(id: 1)], visible: [1, 20],
   worldFrames: world, snapshot: dynamic, batches: [:], particlePipeline: nil,
   mainPass: priorityPass, groups: nil, commandBuffer: priorityCB, leases: &priorityLeases)
  let priorityDraws = priorityState.prepared?[1] ?? []
  let priorityDepth = priorityState.sharedDepth(pass: priorityPass,
   pool: priorityRenderer.staticModelDepthTargetPool, device: device,
   commandBuffer: priorityCB, leases: &priorityLeases)
  checks["source-and-all-model-parts-share-pass-domain"] = priorityExclusion.isEmpty
   && priorityLeases.count == 1 && priorityDraws.count == 3
   && priorityDepth.lease?.texture === priorityLeases.first?.texture
   && priorityState.terminalDepthBinding(pass: priorityPass, commandBuffer: priorityCB) != nil
  priorityState.cancel(); priorityPass.closeForOffscreen(); priorityLeases.forEach { $0.cancel() }
  let partialRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline,
   entries: [1: [entry(SIMD3(1, 0, 0)), entry(SIMD3(0, 1, 0))]]))
  let partialCB = queue.makeCommandBuffer()!
  let partialPass = SceneMainPassEncoder(commandBuffer: partialCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let partialState = SceneMetalRenderer.StaticModelFrame(commandBuffer: partialCB)
  var partialLeases: [SceneParticleDepthTargetLease] = []
  let partialDepthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
   pixelFormat: .depth32Float, width: 64, height: 64, mipmapped: false)
  partialDepthDescriptor.storageMode = .private; partialDepthDescriptor.usage = .renderTarget
  let partialDepthBytes = device.heapTextureSizeAndAlign(descriptor: partialDepthDescriptor).size
  let partialQuota = SceneResourceBudget.shared.maximumBytes - SceneResourceBudget.shared.snapshot.residentBytes - partialDepthBytes
  precondition(SceneResourceBudget.shared.reserve(partialQuota, kind: .gpu))
  let partialExclusion = partialRenderer.unavailableSharedTerminalDepthLayers([20], state: partialState,
   orderedLayers: [.init(id: 1)], visible: [1, 20], worldFrames: world, snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: partialPass, groups: nil,
   commandBuffer: partialCB, leases: &partialLeases)
  SceneResourceBudget.shared.release(partialQuota, kind: .gpu)
  let partialDraws = partialState.prepared?[1] ?? []
  checks["source-one-depth-budget-admits-every-model-part"] = partialExclusion.isEmpty
   && partialLeases.count == 1 && partialDraws.count == 2
   && partialState.terminalDepthBinding(pass: partialPass, commandBuffer: partialCB) != nil
   && partialState.depthDeferralReason == nil
  partialState.cancel(); partialPass.closeForOffscreen(); partialLeases.forEach { $0.cancel() }
  var namedEntry = entry(SIMD3(1, 0, 0))
  namedEntry = .init(materialPath: namedEntry.materialPath, dynamicMaterialPath: "",
   mesh: namedEntry.mesh,
   albedo: nil, namedAlbedo: "owned-late-provider", material: namedEntry.material)
  let lateRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline, entries: [1: [namedEntry]]))
  let lateCB = queue.makeCommandBuffer()!
  let latePass = SceneMainPassEncoder(commandBuffer: lateCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let lateState = SceneMetalRenderer.StaticModelFrame(commandBuffer: lateCB)
  var lateLeases: [SceneParticleDepthTargetLease] = []
  let lateExclusion = lateRenderer.unavailableSharedTerminalDepthLayers([20], state: lateState,
   orderedLayers: [.init(id: 1)], visible: [1, 20], worldFrames: world, snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: latePass, groups: nil,
   commandBuffer: lateCB, leases: &lateLeases)
  checks["source-unknown-late-input-keeps-original-chain"] = lateExclusion == [20]
   && lateState.prepared == nil && lateLeases.isEmpty && lateState.depthDeferralReason == nil
   && lateRenderer.staticModelDepthTargetPool.residentByteCost == 0
  lateState.cancel(); latePass.closeForOffscreen()
  // Refresh late draw payloads through their original owner without changing
  // the already reserved pass domain or acquiring a second model texture.
  let freshCB = queue.makeCommandBuffer()!
  let freshPass = SceneMainPassEncoder(commandBuffer: freshCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
  let freshState = SceneMetalRenderer.StaticModelFrame(commandBuffer: freshCB)
  var freshLeases: [SceneParticleDepthTargetLease] = []
  let freshExclusion = intrinsic.unavailableSharedTerminalDepthLayers([20], state: freshState,
   orderedLayers: (1...4).map { .init(id: $0) }, visible: [1, 2, 3, 4, 20], worldFrames: intrinsicWorld,
   snapshot: dynamic, batches: [:], particlePipeline: nil, mainPass: freshPass, groups: nil,
   commandBuffer: freshCB, leases: &freshLeases)
  let reserved = freshState.sharedDepth(pass: freshPass, pool: intrinsic.staticModelDepthTargetPool,
   device: device, commandBuffer: freshCB, leases: &freshLeases)
  freshState.prepared = nil
  _ = intrinsic.drawStaticModel(layer: .init(id: 4), state: freshState, worldFrames: intrinsicWorld,
   frameContext: .init(dynamicValues: dynamic), cameraFrame: camera, lighting: lighting,
   pass: freshPass, commandBuffer: freshCB, leases: &freshLeases)
  let refreshed = freshState.sharedDepth(pass: freshPass, pool: intrinsic.staticModelDepthTargetPool,
   device: device, commandBuffer: freshCB, leases: &freshLeases)
  precondition(freshPass.finishEnsuringClear())
  freshLeases.forEach { $0.arm(on: freshCB) }; freshState.arm(on: freshCB)
  freshCB.commit(); freshCB.waitUntilCompleted()
  checks["source-fresh-payload-keeps-original-scene-domain"] = freshExclusion.isEmpty
   && freshLeases.count == 1 && reserved.lease?.texture === refreshed.lease?.texture
   && intrinsic.dependencyRuntime.encoded[4] == true
   && freshCB.status == .completed && freshCB.error == nil && rgb(first) == [255, 255, 0, 255]
  let result: [String: Any] = ["checks": checks, "rows": rows,
   "passed": checks.values.allSatisfy { $0 }, "prepared": usePreparation,
   "boundary": "Actual StaticModelFrame depth qualifier/shared reserve/binding, pool, model draw, main encoder and Metal; prepared-input shell only. Healthy suffix here is a real color-pass clear, not a claimed graph layer. Explicit local cancellation after the real frame-owner busy decision; no source Program/App/corpus/VM/full admission/graph-ledger/flicker-cause claim."]
  return result
 }
}
