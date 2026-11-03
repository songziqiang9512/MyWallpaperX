extension Harness {
    private static func renderSmokeTest() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return false }

        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        guard let input = device.makeTexture(descriptor: inputDescriptor) else { return false }
        var white = [UInt8](repeating: 255, count: 4)
        input.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        guard let output = device.makeTexture(descriptor: outputDescriptor) else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }

        let values = [
            SceneParticleGPUInstance(
                position: SIMD3(-0.25, 0, 0), size: 0.5, rotation: .zero,
                color: SIMD3(repeating: 1), alpha: 1
            ),
            SceneParticleGPUInstance(
                position: SIMD3(0.25, 0, 0), size: 0.5, rotation: SIMD3(0, 0, 0.2),
                color: SIMD3(1, 0, 0), alpha: 0.5
            ),
        ]
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: values) else { return false }
        let emptyInstances = SceneParticleMetalInstanceBuffer()
        let basis = SceneParticleOrientation.screen.basis(
            cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        let emptyDraw = pipeline.draw(
            texture: input, instances: emptyInstances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        let translucentDraw = pipeline.draw(
            texture: input, instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        let additiveDraw = pipeline.draw(
            texture: input, instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            renderState: particleState(.additive),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        let submitted = instances.markSubmitted(on: command)
        let completed = SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        return !emptyDraw && translucentDraw && additiveDraw
            && submitted && completed
            && command.status == .completed && instances.count == 2
    }

    private static func additiveFractionalAlphaPixel() -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        var white: [UInt8] = [255, 255, 255, 255]
        input.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: .zero,
                size: 2,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 0.25
            ),
        ]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return []
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.additive),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), SceneParticleOffscreenReadbackHarness.commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }




    private static func instanceBufferSlotTest() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let firstCommand = queue.makeCommandBuffer(),
              let secondCommand = queue.makeCommandBuffer(),
              let thirdCommand = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 1)]),
              let firstBuffer = instances.buffer else {
            return ["available": false]
        }
        let firstValue = firstBuffer.contents()
            .assumingMemoryBound(to: SceneParticleGPUInstance.self)
            .pointee.positionAndSize.x
        let firstSubmitted = instances.markSubmitted(on: firstCommand)

        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 2)]),
              let secondBuffer = instances.buffer else {
            return ["available": false]
        }
        let firstPreserved = firstBuffer.contents()
            .assumingMemoryBound(to: SceneParticleGPUInstance.self)
            .pointee.positionAndSize.x == firstValue
        let secondSubmitted = instances.markSubmitted(on: secondCommand)

        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 3)]),
              let thirdBuffer = instances.buffer else {
            return ["available": false]
        }
        let thirdSubmitted = instances.markSubmitted(on: thirdCommand)
        let firstCompleted = SceneParticleOffscreenReadbackHarness.commitAndWait(firstCommand)

        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 4)]),
              let reusedBuffer = instances.buffer else {
            return ["available": false]
        }
        let secondCompleted = SceneParticleOffscreenReadbackHarness.commitAndWait(secondCommand)
        let thirdCompleted = SceneParticleOffscreenReadbackHarness.commitAndWait(thirdCommand)
        return [
            "available": true,
            "firstSubmitted": firstSubmitted,
            "secondSubmitted": secondSubmitted,
            "thirdSubmitted": thirdSubmitted,
            "firstPreserved": firstPreserved,
            "grewForSecond": firstBuffer !== secondBuffer,
            "grewForThird": firstBuffer !== thirdBuffer && secondBuffer !== thirdBuffer,
            "firstCompleted": firstCompleted,
            "reusedFirst": reusedBuffer === firstBuffer,
            "cleanupCompleted": secondCompleted && thirdCompleted,
        ]
    }

    private static func instanceBufferPendingCancellationTest() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pendingCommand = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 1)]),
              let firstBuffer = instances.buffer else {
            return ["available": false]
        }
        let pendingCancelled = instances.cancelPending()
        let pendingCleared = instances.currentDrawState() == nil && instances.count == 0
        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 2)]),
              let secondBuffer = instances.buffer else {
            return ["available": false]
        }
        let reusedAfterPending = secondBuffer === firstBuffer
        let marked = instances.markSubmitted(on: pendingCommand)
        let uncommittedCancelled = instances.cancelUncommittedSubmission(on: pendingCommand)
        let uncommittedCleared = instances.currentDrawState() == nil && instances.count == 0
        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 3)]),
              let thirdBuffer = instances.buffer else {
            return ["available": false]
        }
        let reusedAfterSubmissionCancel = thirdBuffer === firstBuffer
        let idempotentCancel = !instances.cancelUncommittedSubmission(on: pendingCommand)
        _ = instances.cancelPending()

        guard let committedCommand = queue.makeCommandBuffer(),
              instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 4)]),
              let committedBuffer = instances.buffer,
              instances.markSubmitted(on: committedCommand) else {
            return ["available": false]
        }
        let cancelInFlightRejected = !instances.cancelPending()
        let inFlightCountPreserved = instances.count == 1
        guard SceneParticleOffscreenReadbackHarness.commitAndWait(committedCommand) else {
            return ["available": false]
        }
        let cancelAfterCompletionRejected =
            !instances.cancelUncommittedSubmission(on: committedCommand)
        guard instances.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 5)]),
              let afterCompletionBuffer = instances.buffer else {
            return ["available": false]
        }
        let reusedAfterCompletion = afterCompletionBuffer === committedBuffer
        _ = instances.cancelPending()
        return [
            "available": true,
            "pendingCancelled": pendingCancelled,
            "pendingCleared": pendingCleared,
            "reusedAfterPending": reusedAfterPending,
            "marked": marked,
            "uncommittedCancelled": uncommittedCancelled,
            "uncommittedCleared": uncommittedCleared,
            "reusedAfterSubmissionCancel": reusedAfterSubmissionCancel,
            "idempotentCancel": idempotentCancel,
            "cancelInFlightRejected": cancelInFlightRejected,
            "inFlightCountPreserved": inFlightCountPreserved,
            "cancelAfterCompletionRejected": cancelAfterCompletionRejected,
            "reusedAfterCompletion": reusedAfterCompletion,
        ]
    }

    private static func topologyRetirementTest() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let event = device.makeSharedEvent(),
              let texture = device.makeTexture(descriptor: .texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
              )) else { return ["available": false] }
        func batch(_ layerID: Int, child: Int? = nil, x: Float = 0) -> SceneParticleDrawBatch {
            .init(layerID: layerID, particlePath: "particles/shared.json", texture: texture,
                colorUVScale: SIMD2(repeating: 1), colorSampling: .directImageFallback,
                refraction: nil, renderState: particleState(.additive), childTemplateIndex: child,
                instances: [SceneParticleOffscreenReadbackHarness.instance(x: x)],
                orientation: .screen, orientationAxis: nil, usesPerspective: false)
        }
        var facts: [String: Any] = ["available": true]
        weak var retiredRoot: SceneParticleMetalInstanceBuffer?
        weak var retiredChild: SceneParticleMetalInstanceBuffer?
        var peerOwner: SceneParticleMetalInstanceBuffer?
        autoreleasepool {
            guard let command = queue.makeCommandBuffer(),
                  let peerCommand = queue.makeCommandBuffer() else { return }
            defer { event.signaledValue = 1 }
            var prepared = pipeline.prepare([batch(42), batch(42, child: 0), batch(43)])
            guard prepared.count == 3 else { return }
            retiredRoot = prepared[0].instanceBuffer
            retiredChild = prepared[1].instanceBuffer
            peerOwner = prepared[2].instanceBuffer
            facts["rootAndChildHaveDistinctOwners"] = retiredRoot !== retiredChild
                && retiredRoot !== peerOwner && retiredChild !== peerOwner
            facts["rootAndChildSubmitted"] = prepared[0].instanceBuffer.markSubmitted(on: command)
                && prepared[1].instanceBuffer.markSubmitted(on: command)
            command.encodeWaitForEvent(event, value: 1)
            command.commit()
            pipeline.retire(layerIDs: [42])
            pipeline.retire(layerIDs: [42])
            prepared.removeAll()
            facts["pendingGPUKeepsRetiredOwners"] = retiredRoot != nil && retiredChild != nil
                && command.status != .completed && command.status != .error
            let peer = pipeline.prepare([batch(43, x: 2)])
            facts["healthyPeerReusesOwner"] = peer.count == 1 && peer[0].instanceBuffer === peerOwner
            pipeline.cancel(peer, on: peerCommand)
            facts["healthyPeerPendingCancelled"] = peer.first?.instanceBuffer.count == 0
                && peer.first?.instanceBuffer.currentDrawState() == nil
            event.signaledValue = 1
            command.waitUntilCompleted()
            facts["retiredSubmissionCompleted"] = command.status == .completed
        }
        facts["completedGPUReleasesRootKey"] = retiredRoot == nil
        facts["completedGPUReleasesChildKey"] = retiredChild == nil
        weak var cancelledRoot: SceneParticleMetalInstanceBuffer?
        weak var cancelledChild: SceneParticleMetalInstanceBuffer?
        autoreleasepool {
            guard let command = queue.makeCommandBuffer() else { return }
            var prepared = pipeline.prepare([batch(44), batch(44, child: 0)])
            guard prepared.count == 2 else { return }
            cancelledRoot = prepared[0].instanceBuffer
            cancelledChild = prepared[1].instanceBuffer
            facts["unsubmittedRootAndChildArmed"] = prepared.allSatisfy {
                $0.instanceBuffer.markSubmitted(on: command)
            }
            pipeline.retire(layerIDs: [44])
            pipeline.cancel(prepared, on: command)
            facts["unsubmittedReservationsCancelled"] = prepared.allSatisfy {
                $0.instanceBuffer.count == 0 && $0.instanceBuffer.currentDrawState() == nil
                    && !$0.instanceBuffer.cancelUncommittedSubmission(on: command)
            }
            prepared.removeAll()
        }
        facts["cancelledCommandReleasesRootKey"] = cancelledRoot == nil
        facts["cancelledCommandReleasesChildKey"] = cancelledChild == nil
        let peer = pipeline.prepare([batch(43, x: 3)])
        facts["peerSurvivesBothRetirements"] = peer.count == 1 && peer[0].instanceBuffer === peerOwner
        return facts
    }

    private static func uprightGeometryContract() -> [String: Any] {
        func camera(_ roll: Float, canvas: Bool = false, eye: [Float] = [0, 0, 3], authoredUp: [Float]? = nil) -> SceneParticleCameraFrame {
            let angle = roll * .pi / 180
            return SceneParticleCameraFrame(camera: .init(
                eye: eye, center: [0, 0, 0], up: authoredUp ?? [-sin(angle), cos(angle), 0],
                orthoWidth: canvas ? 2 : nil, orthoHeight: canvas ? 2 : nil,
                fovDegrees: 50, perspectiveOverrideFOVDegrees: 50,
                nearZ: 0.01, farZ: 100), viewportSize: CGSize(width: 256, height: 256))
        }
        let model = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.identity(), parallaxOffset: .zero)
        let rotated = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.rotationZ(.pi / 2), parallaxOffset: .zero)
        let scaled = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.rotationZ(.pi / 2) * SceneMatrix.scale(SIMD3(2, 3, 1)),
            parallaxOffset: .zero)
        let mirrored = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.scale(SIMD3(1, -2, 1)), parallaxOffset: .zero)
        let zero = SceneMatrix.scale(SIMD3<Float>(1, 0, 1))
        var rows: [String: Any] = [:]
        func row(_ frame: SceneParticleCameraFrame, _ orientation: SceneParticleOrientation,
                 _ model: simd_float4x4, projection: simd_float4x4 = SceneMatrix.identity(),
                 expectedBasis: SceneParticleOrientationBasis = .init(right: SIMD3(1, 0, 0), up: SIMD3(0, -1, 0))) -> [String: Any] {
            let basis = frame.basis(for: orientation, layerModel: model)
            return ["right": vector(basis.right), "up": vector(basis.up),
                "pixels": spriteBounds(currentAspect: 0.5, nextAspect: 0.5, frameMix: 0,
                    marked: true, viewProjection: projection, basis: basis),
                "expectedPixels": spriteBounds(currentAspect: 0.5, nextAspect: 0.5, frameMix: 0,
                    marked: true, viewProjection: projection, basis: expectedBasis)]
        }
        for roll: Float in [0, 89, 90, 91, 180] {
            let frame = camera(roll)
            rows["roll\(Int(roll))"] = row(frame, .worldUpright, model)
            rows["localRoll\(Int(roll))"] = row(frame, .upright, model)
            rows["projectedRoll\(Int(roll))"] = row(frame, .worldUpright, model,
                projection: frame.perspectiveViewProjection)
        }
        let frame = camera(0)
        let rotatedExpected = SceneParticleOrientationBasis(right: SIMD3(0, 1, 0), up: SIMD3(1, 0, 0))
        rows["localRotated"] = row(frame, .upright, rotated, expectedBasis: rotatedExpected)
        rows["localScaled"] = row(frame, .upright, scaled, expectedBasis: rotatedExpected)
        rows["worldRotated"] = row(frame, .worldUpright, rotated)
        rows["screenRotated"] = row(frame, .screen, rotated, expectedBasis: rotatedExpected)
        rows["screenWorldRotated"] = row(frame, .worldScreen, rotated)
        rows["screenScaled"] = row(frame, .screen, scaled,
            expectedBasis: .init(right: SIMD3(0, 1, 0), up: SIMD3(1, 0, 0),
                localGeometry: simd_float3x3(SIMD3(0, 2, 0), SIMD3(3, 0, 0), SIMD3(0, 0, -1))))
        let tilt = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.rotationX(.pi / 3), parallaxOffset: .zero)
        rows["screenTilted"] = row(frame, .screen, tilt,
            expectedBasis: .init(right: SIMD3(1, 0, 0), up: SIMD3(0, -0.5, -sqrt(0.75)),
                localGeometry: simd_float3x3(SIMD3(1, 0, 0), SIMD3(0, -0.5, -sqrt(0.75)),
                    SIMD3(0, sqrt(0.75), -0.5))))
        rows["localMirrored"] = row(frame, .upright, mirrored,
            expectedBasis: .init(right: SIMD3(-1, 0, 0), up: SIMD3(0, 1, 0)))
        rows["zeroAxis"] = row(frame, .upright, zero)
        let tilted = camera(0, eye: [0, 2, 3])
        rows["tilted"] = row(tilted, .worldUpright, model,
            projection: tilted.perspectiveViewProjection)
        let canvas = camera(0, canvas: true)
        rows["canvas"] = row(canvas, .upright, model, projection: canvas.perspectiveViewProjection * SceneMatrix.translation(SIMD3(1, 1, 0)))
        let pole = SceneParticleOrientation.upright.basis(cameraRight: SIMD3(1, 1, 0),
            cameraUp: SIMD3(0, 0, 1), cameraForward: SIMD3(0, -1, 0))
        let degenerate = SceneParticleOrientation.upright.basis(cameraRight: SIMD3(0, 1, 0),
            cameraUp: SIMD3(0, 0, 1), cameraForward: SIMD3(0, -1, 0))
        let fixedAxis = SIMD3<Float>(0, 1, 0)
        var fixedSame = true
        for orientation: SceneParticleOrientation in [.fixed, .worldFixed] {
            let vectors = orientation.fixedBasisVectors(axis: fixedAxis, layerModel: rotated)
            let legacy = frame.basis(for: orientation, fixedRight: vectors.right, fixedUp: vectors.up)
            let current = frame.basis(for: orientation, layerModel: rotated, orientationAxis: fixedAxis)
            fixedSame = fixedSame && legacy.right == current.right && legacy.up == current.up
        }
        var trails: [String: [String: Int]] = [:]
        for roll: Float in [0, 89, 90, 91, 180] {
            let rolled = camera(roll)
            trails["roll\(Int(roll))"] = trailBounds(velocity: SIMD3(1, 0, 0),
                viewProjection: rolled.perspectiveViewProjection,
                basis: rolled.basis(for: .upright, layerModel: model))
        }
        trails["tilted"] = trailBounds(velocity: SIMD3(1, 0, 0),
            viewProjection: tilted.perspectiveViewProjection,
            basis: tilted.basis(for: .upright, layerModel: model))
        let poleFrame = camera(0, eye: [0, 3, 0], authoredUp: [0, 0, 1])
        trails["pole"] = trailBounds(velocity: SIMD3(1, 0, 0),
            viewProjection: poleFrame.perspectiveViewProjection,
            basis: poleFrame.basis(for: .upright, layerModel: model))
        return ["rows": rows, "trails": trails, "poleRight": vector(pole.right), "poleUp": vector(pole.up),
            "degenerateRight": vector(degenerate.right), "degenerateUp": vector(degenerate.up),
            "fixedDirectionsUnchanged": fixedSame,
            "screenRolledUp": vector(camera(90).basis(for: .screen).up)]
    }

    private static func spriteBounds(
        currentAspect: Float,
        nextAspect: Float,
        frameMix: Float,
        rotation: SIMD3<Float> = .zero,
        layerModel: simd_float4x4 = SceneMatrix.identity(),
        marked: Bool = false,
        viewProjection: simd_float4x4 = SceneMatrix.identity(),
        basis: SceneParticleOrientationBasis = .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0))
    ) -> [String: Int] {
        let size = 256
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [:] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [:] }
        var white: [UInt8] = marked ? [255, 0, 0, 255, 0, 255, 0, 255] : [UInt8](repeating: 255, count: 8)
        input.replace(
            region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 8
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: SIMD3(0.125, -0.25, 0.5),
                size: 0.5,
                rotation: rotation,
                color: SIMD3(repeating: 1),
                alpha: 1,
                currentFrameAspect: currentAspect,
                nextFrameAspect: nextAspect,
                frameMix: frameMix
            ),
        ]) else { return [:] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [:] }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: viewProjection,
                layerModel: layerModel,
                basis: basis
            ),
            renderState: particleState(.translucent),
            colorSampling: marked ? SceneParticleTextureSampling(texFlags: 3) : .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), SceneParticleOffscreenReadbackHarness.commitAndWait(command) else { return [:] }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        let visible = (0..<(size * size)).filter { pixels[$0 * 4 + 3] > 0 }
        let xs = visible.map { $0 % size }
        let ys = visible.map { $0 / size }
        let red = visible.filter { pixels[$0 * 4 + 2] > 200 && pixels[$0 * 4 + 1] < 30 }
        let green = visible.filter { pixels[$0 * 4 + 1] > 200 && pixels[$0 * 4 + 2] < 30 }
        func center(_ points: [Int], x: Bool) -> Int {
            guard !points.isEmpty else { return -1 }
            return Int((Double(points.reduce(0) { $0 + (x ? $1 % size : $1 / size) }) / Double(points.count) * 1000).rounded())
        }
        return [
            "redX1000": center(red, x: true), "redY1000": center(red, x: false),
            "greenX1000": center(green, x: true), "greenY1000": center(green, x: false),
            "width": (xs.max() ?? -1) - (xs.min() ?? 0) + 1,
            "height": (ys.max() ?? -1) - (ys.min() ?? 0) + 1,
            "centerX2": (xs.max() ?? -1) + (xs.min() ?? 0),
            "centerY2": (ys.max() ?? -1) + (ys.min() ?? 0),
        ]
    }

    private static func sequenceEndPixels() -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [] }
        var pixels: [UInt8] = [255,0,0,255, 0,0,255,255]
        texture.replace(region: MTLRegionMake2D(0,0,2,1), mipmapLevel: 0,
                        withBytes: &pixels, bytesPerRow: 8)
        func frame(_ index: Int) -> SceneParticleFrameTransform {
            .init(origin: SIMD2(index == 0 ? 0.25 : 0.75,0.5), xAxis: .zero, yAxis: .zero)
        }
        var rows: [[String: Any]] = []
        for prepared in [false, true] {
            for blend in [false, true] {
                for age: Float in [0.25, 0.5, 0.75, 0.999, 1, 1.25] {
                    let selected = SceneParticleSpriteFrameSelector.select(
                        mode: .sequence, frameDurations: [1,1],
                        frameEndTimes: prepared ? [1,2] : nil,
                        totalDuration: prepared ? 2 : nil,
                        age: age, lifetime: 1, particleID: 1, blendsFrames: blend)!
                    let observed = SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture,
                        currentFrame: frame(selected.currentIndex),
                        nextFrame: frame(selected.nextIndex), frameMix: selected.mix)
                    rows.append(["prepared":prepared,"blend":blend,"age":age,"bgra":observed])
                }
            }
        }
        return rows
    }

    private static func straightInterpolationTest() -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [] }
        var pixels: [UInt8] = [255,0,0,0, 0,0,255,255]
        texture.replace(region: MTLRegionMake2D(0,0,2,1), mipmapLevel: 0,
                        withBytes: &pixels, bytesPerRow: 8)
        func frame(_ u: Float) -> SceneParticleFrameTransform {
            .init(origin: SIMD2(u,0.5), xAxis: .zero, yAxis: .zero)
        }
        var rows: [[String: Any]] = []
        for additive in [false, true] {
            for alpha: Float in [0.4, 1] {
                for background: Float in [0, 0.125] {
                    for overbright: Float in [0.5, 1] {
                        for mix: Float in [0, 0.25, 0.5, 0.75, 1] {
                            for spatial in [false, true] {
                                let observed = SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture,
                                    currentFrame: frame(spatial ? 0.25 + mix * 0.5 : 0.25),
                                    nextFrame: spatial ? nil : frame(0.75),
                                    frameMix: spatial ? 0 : mix, particleAlpha: alpha,
                                    blendMode: additive ? .additive : .translucent,
                                    background: background, overbright: overbright)
                                rows.append(["additive": additive, "alpha": alpha,
                                    "background": background, "overbright": overbright,
                                    "mix": mix, "spatial": spatial, "bgra": observed])
                            }
                        }
                    }
                }
            }
        }
        return rows
    }

    private static func colorContractTest() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [:] }
        let r8Descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 2, height: 2, mipmapped: false
        )
        r8Descriptor.usage = .shaderRead
        r8Descriptor.storageMode = .shared
        guard let r8 = device.makeTexture(descriptor: r8Descriptor) else { return [:] }
        var gray = [UInt8](repeating: 200, count: 4)
        r8.replace(
            region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
            withBytes: &gray, bytesPerRow: 2
        )
        let rawR8 = SceneParticleOffscreenReadbackHarness.centerPixel(texture: r8)
        guard let adaptedR8Texture = SceneParticleColorTextureAdapter.adapt(r8) else {
            return [:]
        }
        let adaptedR8 = SceneParticleOffscreenReadbackHarness.centerPixel(texture: adaptedR8Texture)

        let rgDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm, width: 2, height: 2, mipmapped: true
        )
        rgDescriptor.usage = .shaderRead
        rgDescriptor.storageMode = .shared
        guard let rg = device.makeTexture(descriptor: rgDescriptor) else { return [:] }
        var luminanceAlpha = [UInt8](repeating: 0, count: 8)
        for index in 0..<4 {
            luminanceAlpha[index * 2] = 255
            luminanceAlpha[index * 2 + 1] = 128
        }
        rg.replace(
            region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
            withBytes: &luminanceAlpha, bytesPerRow: 4
        )
        var secondMip: [UInt8] = [64, 64]
        rg.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 1,
            withBytes: &secondMip, bytesPerRow: 2
        )
        guard let adaptedRG = SceneParticleColorTextureAdapter.adapt(rg) else {
            return [:]
        }
        guard let secondMipView = adaptedRG.makeTextureView(
            pixelFormat: adaptedRG.pixelFormat, textureType: .type2D,
            levels: 1..<2, slices: 0..<1, swizzle: adaptedRG.swizzle) else { return [:] }
        return [
            "rawR8": rawR8, "adaptedR8": adaptedR8,
            "rgMipCount": adaptedRG.mipmapLevelCount,
            "rgPixel": SceneParticleOffscreenReadbackHarness.centerPixel(texture: adaptedRG),
            "rgSecondMip": SceneParticleOffscreenReadbackHarness.centerPixel(texture: secondMipView),
        ]
    }
}
