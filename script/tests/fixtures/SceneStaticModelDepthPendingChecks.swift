import Dispatch

// This prepared-input fixture has no descriptor framebuffer-source role.
extension SceneRenderDescriptor.Layer { var hasFramebufferMaterialSource: Bool { false } }

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
  // Actual shared owner, with no model writer: reservation is idempotent and
  // first clear belongs to a successful final encoder, not source capture.
  let terminalPool = SceneParticleDepthTargetPool()
  let terminalCB = queue.makeCommandBuffer()!
  let terminalPass = SceneMainPassEncoder(commandBuffer: terminalCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let terminalState = SceneMetalRenderer.StaticModelFrame()
  var terminalLeases: [SceneParticleDepthTargetLease] = []
  let a = terminalState.sharedDepth(pass: terminalPass, pool: terminalPool, device: device,
   commandBuffer: terminalCB, leases: &terminalLeases)
  let b = terminalState.sharedDepth(pass: terminalPass, pool: terminalPool, device: device,
   commandBuffer: terminalCB, leases: &terminalLeases)
  checks["terminal-reserve-is-one-lease"] = terminalLeases.count == 1
   && a.lease?.texture === b.lease?.texture && !terminalState.sharedWasCleared
  let wrongCB = queue.makeCommandBuffer()!
  let wrongPass = SceneMainPassEncoder(commandBuffer: terminalCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  checks["terminal-binding-rejects-other-pass-and-cb"] =
   terminalState.terminalDepthBinding(pass: wrongPass, commandBuffer: terminalCB) == nil
   && terminalState.terminalDepthBinding(pass: terminalPass, commandBuffer: wrongCB) == nil
  let binding = terminalState.terminalDepthBinding(pass: terminalPass, commandBuffer: terminalCB)!
  checks["terminal-binding-rechecks-consumer"] = binding.encoder(wrongPass) == nil
   && !terminalState.sharedWasCleared
  checks["terminal-first-real-encoder-clears"] = binding.encoder(terminalPass) != nil
   && terminalState.sharedWasCleared
  checks["terminal-color-pass-preserves-owner"] = terminalPass.withReadableTarget { _, _ in true } == true
   && binding.encoder(terminalPass) != nil && terminalLeases.count == 1
  terminalPass.closeForOffscreen()
  terminalLeases.forEach { $0.arm(on: terminalCB) }; terminalState.arm(on: terminalCB)
  checks["terminal-binding-expires-at-submission"] = binding.encoder(terminalPass) == nil
  terminalCB.commit(); terminalCB.waitUntilCompleted()
  checks["terminal-empty-writer-frame-completes"] = terminalCB.status == .completed && terminalCB.error == nil
  // A finished pass cannot consume the binding or advance first-clear state.
  let canceledCB = queue.makeCommandBuffer()!
  let canceledPass = SceneMainPassEncoder(commandBuffer: canceledCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let canceledState = SceneMetalRenderer.StaticModelFrame()
  var canceledLeases: [SceneParticleDepthTargetLease] = []
  _ = canceledState.sharedDepth(pass: canceledPass, pool: terminalPool, device: device,
   commandBuffer: canceledCB, leases: &canceledLeases)
  let canceledBinding = canceledState.terminalDepthBinding(pass: canceledPass, commandBuffer: canceledCB)!
  precondition(canceledPass.finishEnsuringClear())
  checks["terminal-failed-encoder-does-not-clear"] = canceledBinding.encoder(canceledPass) == nil
   && !canceledState.sharedWasCleared
  canceledState.cancel(); canceledLeases.forEach { $0.cancel() }
  checks["terminal-binding-expires-on-cancel"] = canceledBinding.encoder(canceledPass) == nil
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
  let busyState = SceneMetalRenderer.StaticModelFrame()
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
  let sourceRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: nil, entries: [:]))
  let sourceCB = queue.makeCommandBuffer()!
  let sourcePass = SceneMainPassEncoder(commandBuffer: sourceCB, target: first.output,
   clearColor: MTLClearColorMake(0, 1, 0, 1), clearEnabled: true)
  let sourceState = SceneMetalRenderer.StaticModelFrame()
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
  let sourceRecoveryState = SceneMetalRenderer.StaticModelFrame()
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
   && !sourceRecoveryState.sharedWasCleared
  checks["source-recovery-clears-at-terminal-encoder"] = recoveredBinding?.encoder(sourceRecoveryPass) != nil
   && sourceRecoveryState.sharedWasCleared
  sourceRecoveryPass.closeForOffscreen()
  sourceRecoveryLeases.forEach { $0.arm(on: sourceRecoveryCB) }; sourceRecoveryState.arm(on: sourceRecoveryCB)
  sourceRecoveryCB.commit(); sourceRecoveryCB.waitUntilCompleted()
  checks["source-recovery-completes"] = sourceRecoveryCB.status == .completed && sourceRecoveryCB.error == nil
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
  let sourceBusyState = SceneMetalRenderer.StaticModelFrame()
  var sourceBusyLeases: [SceneParticleDepthTargetLease] = []
  _ = sourceRenderer.unavailableSharedTerminalDepthLayers([20], state: sourceBusyState,
   orderedLayers: [], ordinaryLayerIDs: [21], visible: [20, 21], worldFrames: [:], snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: sourceBusyPass, groups: nil,
   commandBuffer: sourceBusyCB, leases: &sourceBusyLeases)
  checks["source-busy-defers-before-admission"] = sourceBusyState.depthDeferralReason == "static-model-depth-in-flight"
   && sourceBusyLeases.isEmpty && sourceBusyCB.status == .notEnqueued
  sourceBusyState.cancel(); sourceBusyPass.closeForOffscreen(); heldSourceLeases.forEach { $0.cancel() }
  // A source authored before near-coincident models must not change their
  // original shared/isolated classification or consume a fourth pool slot.
  let priorityRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline,
   entries: [1: [entry(SIMD3(1, 0, 0)), entry(SIMD3(0, 1, 0)), entry(SIMD3(0, 0, 1))]]))
  let priorityCB = queue.makeCommandBuffer()!
  let priorityPass = SceneMainPassEncoder(commandBuffer: priorityCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let priorityState = SceneMetalRenderer.StaticModelFrame()
  var priorityLeases: [SceneParticleDepthTargetLease] = []
  let priorityExclusion = priorityRenderer.unavailableSharedTerminalDepthLayers([20], state: priorityState,
   orderedLayers: [.init(id: 20, contentKind: "composition"), .init(id: 1)], visible: [1, 20],
   worldFrames: world, snapshot: dynamic, batches: [:], particlePipeline: nil,
   mainPass: priorityPass, groups: nil, commandBuffer: priorityCB, leases: &priorityLeases)
  let priorityDraws = priorityState.prepared?[1] ?? []
  checks["source-model-priority-and-isolation-preserved"] = priorityExclusion.isEmpty
   && priorityLeases.count == 3 && priorityDraws.map(\.partIndex) == [0, 1, 2]
   && priorityDraws.map { $0.depth?.shared } == [true, false, false]
   && priorityState.sharedLease?.texture === priorityDraws.first?.depth?.lease?.texture
  priorityState.cancel(); priorityPass.closeForOffscreen(); priorityLeases.forEach { $0.cancel() }
  let partialRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline,
   entries: [1: [entry(SIMD3(1, 0, 0)), entry(SIMD3(0, 1, 0))]]))
  let partialCB = queue.makeCommandBuffer()!
  let partialPass = SceneMainPassEncoder(commandBuffer: partialCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let partialState = SceneMetalRenderer.StaticModelFrame()
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
  checks["source-isolated-refusal-keeps-valid-shared-depth"] = partialExclusion.isEmpty
   && partialLeases.count == 1 && partialDraws.count == 2
   && partialDraws[0].depth?.lease != nil && partialDraws[1].depth?.lease == nil
   && partialState.terminalDepthBinding(pass: partialPass, commandBuffer: partialCB) != nil
   && partialState.depthDeferralReason == nil
  partialState.cancel(); partialPass.closeForOffscreen(); partialLeases.forEach { $0.cancel() }
  var namedEntry = entry(SIMD3(1, 0, 0))
  namedEntry = .init(materialPath: namedEntry.materialPath, dynamicMaterialPath: "",
   geometryIdentity: namedEntry.geometryIdentity, mesh: namedEntry.mesh,
   albedo: nil, namedAlbedo: "owned-late-provider", material: namedEntry.material)
  let lateRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline, entries: [1: [namedEntry]]))
  let lateCB = queue.makeCommandBuffer()!
  let latePass = SceneMainPassEncoder(commandBuffer: lateCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: false)
  let lateState = SceneMetalRenderer.StaticModelFrame()
  var lateLeases: [SceneParticleDepthTargetLease] = []
  let lateExclusion = lateRenderer.unavailableSharedTerminalDepthLayers([20], state: lateState,
   orderedLayers: [.init(id: 1)], visible: [1, 20], worldFrames: world, snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: latePass, groups: nil,
   commandBuffer: lateCB, leases: &lateLeases)
  checks["source-unknown-late-input-keeps-original-chain"] = lateExclusion == [20]
   && lateState.prepared == nil && lateLeases.isEmpty && lateState.depthDeferralReason == nil
   && lateRenderer.staticModelDepthTargetPool.residentByteCost == 0
  lateState.cancel(); latePass.closeForOffscreen()
  // Early qualification owns a complete depth schedule, but the ordered
  // shadow walk exits at the fourth near-coincident part. A later independent
  // shared-depth draw must refresh its payload and retain its original slot.
  let suffixEntry = ScenePreparedStaticModelResources.Entry(materialPath: "owned-independent-suffix",
   dynamicMaterialPath: "", geometryIdentity: "owned-independent-suffix-geometry", mesh: mesh,
   albedo: PreparedTexture(texture: white), material: entry(SIMD3(1, 0, 1)).material,
   writesDepth: true, materialBlending: .normal)
  let exitRenderer = SceneMetalRenderer(device: device, resources: .init(pipeline: pipeline,
   entries: [1: [entry(SIMD3(1, 0, 0))], 2: [entry(SIMD3(0, 1, 0))],
    3: [entry(SIMD3(0, 0, 1))], 4: [entry(SIMD3(1, 1, 0))], 5: [suffixEntry]]))
  let exitLayers = (1...5).map { SceneRenderDescriptor.Layer(id: $0) }
  let exitWorld = Dictionary(uniqueKeysWithValues: (1...5).map { id in (id, world[1]!) })
  let exitCB = queue.makeCommandBuffer()!
  let exitPass = SceneMainPassEncoder(commandBuffer: exitCB, target: first.output,
   clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
  let exitState = SceneMetalRenderer.StaticModelFrame()
  var exitLeases: [SceneParticleDepthTargetLease] = []
  let exitExclusion = exitRenderer.unavailableSharedTerminalDepthLayers([20], state: exitState,
   orderedLayers: exitLayers, visible: [1, 2, 3, 4, 5, 20], worldFrames: exitWorld, snapshot: dynamic,
   batches: [:], particlePipeline: nil, mainPass: exitPass, groups: nil,
   commandBuffer: exitCB, leases: &exitLeases)
  let earlySuffixDepth = exitState.prepared?[5]?.first?.depth?.lease?.texture
  let exitPool = SceneOffscreenTexturePool(device: device, pixelFormat: .bgra8Unorm,
   residentByteBudget: 8 * 1024 * 1024)
  let exitReason = exitRenderer.prepareOrderedModelShadow(state: exitState, lights: [], lighting: lighting,
   orderedLayers: exitLayers, visible: [1, 2, 3, 4, 5], activeNamedModels: [], forwardGraphProviders: [],
   framePlans: [:], imageTextures: .init(), imagePipeline: .init(),
   frameContext: .init(dynamicValues: dynamic), worldFrames: exitWorld, cameraFrame: camera,
   parallax: .init(), viewportSize: CGSize(width: 64, height: 64), batches: [:], particlePipeline: nil,
   mainPass: exitPass, groups: nil, utilityExecution: exitRenderer.utilityExecution, pool: exitPool,
   commandBuffer: exitCB, leases: &exitLeases, terminalCapacity: { true }, recordsEvidence: false)
  let freshSuffix = exitRenderer.staticModelDraws(layer: exitLayers[4], worldFrames: exitWorld, snapshot: dynamic)![0]
  let lateSuffixDepth = exitState.depth(for: freshSuffix, layerID: 5, pass: exitPass,
   pool: exitRenderer.staticModelDepthTargetPool, device: device, commandBuffer: exitCB, leases: &exitLeases)
  checks["source-ordered-exit-keeps-suffix-reservation"] = exitExclusion.isEmpty && exitReason == nil
   && exitState.prepared?[5] == nil && freshSuffix.texture === white
   && earlySuffixDepth != nil && lateSuffixDepth.lease?.texture === earlySuffixDepth
   && lateSuffixDepth.shared && exitLeases.count == 3
  // Releasing a slot after the original refusal must not make the same failed
  // part retry. The original result is immutable for this frame identity.
  exitLeases[2].cancel()
  let failedDraw = exitRenderer.staticModelDraws(layer: exitLayers[3], worldFrames: exitWorld, snapshot: dynamic)![0]
  let stillFailed = exitState.depth(for: failedDraw, layerID: 4, pass: exitPass,
   pool: exitRenderer.staticModelDepthTargetPool, device: device, commandBuffer: exitCB, leases: &exitLeases)
  if case .currentFrameCapacityExceeded = stillFailed.acquisition {
   checks["source-ordered-exit-does-not-retry-failed-part"] = exitLeases.count == 3
  } else { checks["source-ordered-exit-does-not-retry-failed-part"] = false }
  _ = exitRenderer.drawStaticModel(layer: exitLayers[4], state: exitState, worldFrames: exitWorld,
   frameContext: .init(dynamicValues: dynamic), cameraFrame: camera, lighting: lighting,
   pass: exitPass, commandBuffer: exitCB, leases: &exitLeases)
  precondition(exitPass.finishEnsuringClear())
  exitLeases.forEach { $0.arm(on: exitCB) }; exitState.arm(on: exitCB)
  exitCB.commit(); exitCB.waitUntilCompleted()
  checks["source-ordered-exit-suffix-draws-with-fresh-payload"] = exitLeases.count == 3
   && exitRenderer.dependencyRuntime.encoded[5] == true
   && exitCB.status == .completed && exitCB.error == nil && rgb(first) == [255, 0, 255, 255]
  let result: [String: Any] = ["checks": checks, "rows": rows,
   "passed": checks.values.allSatisfy { $0 }, "prepared": usePreparation,
   "boundary": "Actual StaticModelFrame depth qualifier/shared reserve/binding, pool, model draw, main encoder and Metal; prepared-input shell only. Healthy suffix here is a real color-pass clear, not a claimed graph layer. Explicit local cancellation after the real frame-owner busy decision; no source Program/App/corpus/VM/full admission/graph-ledger/flicker-cause claim."]
  return result
 }
}
