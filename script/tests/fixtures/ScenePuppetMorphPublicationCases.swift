import Metal
import simd

private func makeMorphPublicationPlayback(device: MTLDevice, pipeline: SceneImageLayerPipeline,
                                          atlas: MTLTexture, boneAlpha: [Float]? = nil,
                                          primaryTargets: [SceneMdlPuppetAnimation.MorphTarget]? = nil) throws -> Playback {
    let base = fixture(poses: [pose(), pose()], weight: 1)
    let vertices = base.0.vertices + [.init(x: 0.75, y: 0.75, z: 0, u: 0.25, v: 0.75)]
    let mesh = SceneMdlPuppetMesh(version: base.0.version, vertexStride: base.0.vertexStride,
        meshBlockOffset: base.0.meshBlockOffset, vertices: vertices, indices: base.0.indices)
    let rig = SceneMdlPuppetRig(bones: base.1.bones,
        vertexWeights: Array(repeating: base.1.vertexWeights[0], count: vertices.count))

    func clip(_ id: Int, shift: Float, alpha: [Float]?,
              targets: [SceneMdlPuppetAnimation.MorphTarget], additive: Bool) -> ScenePuppetAnimationSelection.Clip {
        let name = "publication-\(id)"
        let bone = pose(translationX: shift)
        let animation = SceneMdlPuppetAnimation(id: id, name: name, mode: "single", framesPerSecond: 1,
            frameCount: 1, transformsByBone: [[bone, bone]], alphaByBone: alpha.map { [$0] },
            hasAuxiliaryScalarTrack: true, morphTargets: targets)
        let layer = ScenePuppetAnimationLayer(id: id, animationID: id, name: name, additive: additive,
            blend: 1, blendIn: false, blendOut: false, blendTime: 0, rate: 1, visible: true,
            visibilityBinding: nil)
        return .init(layer: layer, animation: animation)
    }

    let primary = clip(17, shift: 0, alpha: boneAlpha, targets: primaryTargets ?? [
        .init(weights: [0, 1], positions: [SIMD3(0.25, 0, 0.25)], coverages: [0.5]),
        .init(weights: [0, 1], positions: [SIMD3(-0.0625, 0, 0)], coverages: [0.5]),
    ], additive: false)
    let peer = clip(31, shift: 0.125, alpha: nil, targets: [
        .init(weights: [0, 1], positions: [SIMD3(0, 0.5, 0)], coverages: nil),
    ], additive: true)
    let selection = ScenePuppetAnimationSelection(clips: [primary, peer], composition: .layered)
    return try makePlayback((mesh, rig, selection), device: device, pipeline: pipeline, atlas: atlas,
        morphVertexAddresses: [1, 1, 1, 0])
}

func morphPublicationChecks(device: MTLDevice, queue: MTLCommandQueue,
                            pipeline: SceneImageLayerPipeline, atlas: MTLTexture) throws -> [String: Any] {
    typealias LayerFrame = ScenePuppetAnimationPlaybackRuntime.LayerFrame
    let output = try makeMorphPublicationPlayback(device: device, pipeline: pipeline, atlas: atlas)
    let zero = ScenePuppetAnimationEvaluator.FrameSample(frameA: 0, frameB: 1, fraction: 0)
    let half = ScenePuppetAnimationEvaluator.FrameSample(frameA: 0, frameB: 1, fraction: 0.5)
    let full = ScenePuppetAnimationEvaluator.FrameSample(frameA: 0, frameB: 1, fraction: 1)

    func vertices(_ frame: ScenePuppetPlaybackState.RenderFrame) -> [[Float]] {
        guard case let .image(vertices, _) = frame.geometry else { fatalError("expected image pose") }
        return vertices.map { [$0.position.x, $0.position.y, $0.vertexCoverage, $0.texcoord.x, $0.texcoord.y] }
    }

    func capture(_ frame: LayerFrame, playback: Playback? = nil) -> [String: Any] {
        let playback = playback ?? output
        let gpu = render(playback, sceneTime: 0, device: device, queue: queue, atlas: atlas, animationFrame: frame)
        let pose = playback.state.renderFrame!
        return ["revision": pose.revision, "vertices": vertices(pose), "gpu": [
            "drew": gpu.drew, "ready": gpu.readyAfter,
            "centerAlpha": gpu.pixels[(16 * 32 + 16) * 4 + 3], "imageSHA256": gpu.report["imageSHA256"]!
        ]]
    }

    let start = capture(.init(samples: [zero, nil]))
    let halfway = capture(.init(samples: [half, nil]))
    let halfwayBuffers = bufferBytes(Observation.buffers)
    let repeated = capture(.init(samples: [half, nil]))
    let repeatedBuffersUnchanged = halfwayBuffers == bufferBytes(Observation.buffers)
    let peak = capture(.init(samples: [full, nil]))
    let hidden = capture(.init(samples: [nil, nil]))
    let blended = capture(.init(samples: [full, nil], blends: [0.5, 1]))
    let zeroPeer = capture(.init(samples: [full, zero]))
    let conflict = capture(.init(samples: [full, full]))
    let resumed = capture(.init(samples: [full, nil]))

    let rotated = try makeMorphPublicationPlayback(device: device, pipeline: pipeline, atlas: atlas,
        boneAlpha: [0.5, 0.5])
    // A quarter turn around Y maps bind Z directly to image X.
    let quarterTurn: [Double] = [0, 0, -1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1]
    rotated.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 0, operation: .matrix(quarterTurn))])
    rotated.state.prepareFrame(animationFrame: .init(samples: [zero, nil]))
    let rotatedBefore = vertices(rotated.state.renderFrame!)[0]
    rotated.state.prepareFrame(animationFrame: .init(samples: [full, nil]))
    let rotatedAfter = vertices(rotated.state.renderFrame!)[0]

    let overflow = try makeMorphPublicationPlayback(device: device, pipeline: pipeline, atlas: atlas,
        boneAlpha: [0.75, 0.75], primaryTargets: [
            .init(weights: [0, 1], positions: [SIMD3(.greatestFiniteMagnitude, 0, 0)], coverages: [0.75])
        ])
    let beforeOverflow = capture(.init(samples: [zero, nil]), playback: overflow)
    // Blend 2 overflows the shape's X while the peer's bone shift remains finite.
    let afterOverflow = capture(.init(samples: [full, zero], blends: [2, 1]), playback: overflow)

    return ["start": start, "half": halfway, "repeated": repeated, "full": peak,
        "hidden": hidden, "blended": blended, "zeroPeer": zeroPeer, "conflict": conflict, "resumed": resumed,
        "repeatedBuffersUnchanged": repeatedBuffersUnchanged,
        "rotatedBefore": rotatedBefore, "rotatedAfter": rotatedAfter,
        "beforeOverflow": beforeOverflow, "afterOverflow": afterOverflow]
}
