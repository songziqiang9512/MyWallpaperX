import Foundation
import Metal
import simd

// Produces projection, depth, winding, and texture-axis evidence through the
// production camera uniform producer and the real offscreen Metal pipeline.
enum SceneParticleCameraRenderingHarness {
    static func run() -> [String: Any] {
        let width: Float = 1280
        let height: Float = 832
        let distance: Float = 1000
        let eye = SIMD3(width / 2, height / 2, distance)
        let view = SceneMatrix.lookAt(
            eye: eye, center: SIMD3(width / 2, height / 2, 0), up: SIMD3(0, 1, 0)
        )
        let fov = 2 * atan(height / (2 * distance))
        let projection = SceneMatrix.perspectiveRHMetal(
            fovYRadians: fov, aspect: width / height, near: 0.1, far: 5000
        )
        let viewProjection = projection * view

        return [
            "nearNDC": ndc(projection, SIMD4(0, 0, -0.1, 1)),
            "farNDC": ndc(projection, SIMD4(0, 0, -5000, 1)),
            "sceneCenterNDC": ndc(viewProjection, SIMD4(width / 2, height / 2, 0, 1)),
            "sceneTopRightNDC": ndc(viewProjection, SIMD4(width, height, 0, 1)),
            "invalidPerspectiveIsIdentity": SceneMatrix.perspectiveRHMetal(
                fovYRadians: 0, aspect: 0, near: -1, far: 0
            ) == SceneMatrix.identity(),
            "depthAndOverbrightPixel": depthAndOverbrightPixel(),
            "projectedSpriteProfiles": projectedSpriteProfiles(),
            "depthTargetLease": depthTargetLeaseContract(),
            "cullContract": cullContract(),
        ]
    }

    static func ndc(_ matrix: simd_float4x4, _ point: SIMD4<Float>) -> [Float] {
        let clip = matrix * point
        return [clip.x / clip.w, clip.y / clip.w, clip.z / clip.w]
    }

    static func depthAndOverbrightPixel(
        uniforms: SceneParticleLayerUniforms? = nil,
        nearZ: Float = 0.2, farZ: Float = 0.8, particleSize: Float = 1,
        nearState: SceneParticlePipelineRenderState? = nil,
        farState: SceneParticlePipelineRenderState? = nil,
        nearFirst: Bool = true
    ) -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer(),
              let depthLease = pipeline.acquireDepthTarget(width: size, height: size)
        else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let red = device.makeTexture(descriptor: inputDescriptor),
              let green = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        var redPixel: [UInt8] = [255, 0, 0, 255]
        var greenPixel: [UInt8] = [0, 255, 0, 255]
        red.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &redPixel,
            bytesPerRow: 4
        )
        green.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &greenPixel,
            bytesPerRow: 4
        )
        let near = SceneParticleMetalInstanceBuffer()
        let far = SceneParticleMetalInstanceBuffer()
        guard near.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 0, z: nearZ, size: particleSize)]),
              far.update(device: device, instances: [SceneParticleOffscreenReadbackHarness.instance(x: 0, z: farZ, size: particleSize)]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depthLease.texture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        let drawUniforms = uniforms ?? SceneParticleLayerUniforms(
            viewProjection: SceneMatrix.identity(),
            layerModel: SceneMatrix.identity(),
            basis: SceneParticleOrientation.screen.basis(
                cameraRight: SIMD3(1, 0, 0),
                cameraUp: SIMD3(0, 1, 0),
                cameraForward: SIMD3(0, 0, -1)
            )
        )
        let state = SceneParticlePipelineRenderState(
            blendMode: .translucent,
            cullMode: .none,
            depthTestEnabled: true,
            depthWriteEnabled: true,
            overbright: 0.5
        )
        let draws = [(red, near, nearState ?? state), (green, far, farState ?? state)]
        for (texture, instances, renderState) in nearFirst ? draws : Array(draws.reversed()) {
            guard pipeline.draw(
                texture: texture, instances: instances, uniforms: drawUniforms,
                renderState: renderState, colorSampling: .directImageFallback,
                usesDepthAttachment: true, encoder: encoder
            ) else { return [] }
        }
        encoder.endEncoding()
        guard near.markSubmitted(on: command), far.markSubmitted(on: command) else { return [] }
        depthLease.arm(on: command)
        guard SceneParticleOffscreenReadbackHarness.commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    static func projectedSpriteProfiles() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [:] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [:] }
        var marker: [UInt8] = [255,0,0,255, 255,0,0,255, 0,0,255,255, 0,0,255,255]
        texture.replace(region: MTLRegionMake2D(0,0,2,2), mipmapLevel: 0,
                        withBytes: &marker, bytesPerRow: 8)
        let depthState: (Bool, Bool) -> SceneParticlePipelineRenderState = { test, write in
            .init(blendMode: .translucent, cullMode: .none,
                  depthTestEnabled: test, depthWriteEnabled: write)
        }
        let eyeDistance = 64 / tan(Float.pi / 6)
        let cameraState = SceneParticlePipelineRenderState(
            blendMode: .translucent, cullMode: .none, usesSceneCamera: true)
        var rows: [[String: Any]] = []
        for cameraName in ["orthographic", "canvas-perspective", "native-perspective", "native-perspective-flag-off"] {
            let native = cameraName.hasPrefix("native-perspective")
            let perspective = cameraName != "orthographic" && cameraName != "native-perspective-flag-off"
            let frame = SceneParticleCameraFrame(camera: .init(
                eye: [64,64,eyeDistance], center: [64,64,0], up: [0,1,0],
                orthoWidth: native ? nil : 128, orthoHeight: native ? nil : 128,
                fovDegrees: native ? 60 : nil,
                perspectiveOverrideFOVDegrees: cameraName == "canvas-perspective" ? 60 : nil,
                nearZ: 1, farZ: 2000), viewportSize: CGSize(width: 64,height: 64))
            let model = SceneParticleCameraFrame.particleLayerModel(
                worldFrame: SceneMatrix.translation(SIMD3(64,64,0)), parallaxOffset: .zero)
            for (space, orientation, worldSize) in [
                ("local", SceneParticleOrientation.screen, false),
                ("world", SceneParticleOrientation.worldScreen, true)
            ] {
                let uniforms = frame.particleUniforms(
                    layerModel: model, orientation: orientation, orientationAxis: nil,
                    usesPerspective: perspective, usesSceneCamera: cameraState.usesSceneCamera,
                    viewportSize: SIMD2(64,64), sizeIsWorldSpace: worldSize)
                let nearClip = uniforms.viewProjection * uniforms.layerModel * SIMD4<Float>(0,0,10,1)
                let farClip = uniforms.viewProjection * uniforms.layerModel * SIMD4<Float>(0,0,-10,1)
                func depth(_ near: SceneParticlePipelineRenderState,
                           _ far: SceneParticlePipelineRenderState,
                           nearFirst: Bool = true) -> [Int] {
                    depthAndOverbrightPixel(uniforms: uniforms, nearZ: 10, farZ: -10,
                        particleSize: 64, nearState: near, farState: far, nearFirst: nearFirst)
                }
                rows.append([
                    "camera": cameraName, "space": space,
                    "nearDepth": nearClip.z / nearClip.w, "farDepth": farClip.z / farClip.w,
                    "testWrite": depth(depthState(true,true), depthState(true,true)),
                    "writeDisabled": depth(depthState(true,false), depthState(true,false)),
                    "testDisabled": depth(depthState(true,true), depthState(false,false)),
                    "bothDisabled": depth(depthState(false,false), depthState(false,false)),
                    "writeWithoutTest": depth(depthState(false,true), depthState(true,false)),
                    "farFirst": depth(depthState(true,true), depthState(true,true), nearFirst: false),
                    "frontBackCull": SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture, cullMode: .back,
                        uniforms: uniforms, particleSize: 64, outputSize: 64),
                    "reversedBackCull": SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture, cullMode: .back,
                        reversesWinding: true, uniforms: uniforms, particleSize: 64, outputSize: 64),
                    "reversedNoCull": SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture, cullMode: .none,
                        reversesWinding: true, uniforms: uniforms, particleSize: 64, outputSize: 64),
                    "topMarker": SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture, uniforms: uniforms,
                        particleSize: 64, outputSize: 64, sampleY: 28),
                    "bottomMarker": SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture, uniforms: uniforms,
                        particleSize: 64, outputSize: 64, sampleY: 36)
                ])
            }
        }
        return ["rows": rows]
    }

    static func depthTargetLeaseContract() -> [String: Bool] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let first = pipeline.acquireDepthTarget(width: 8, height: 8),
              let second = pipeline.acquireDepthTarget(width: 8, height: 8),
              let third = pipeline.acquireDepthTarget(width: 8, height: 8) else { return [:] }
        let rejectsFourth = pipeline.acquireDepthTarget(width: 8, height: 8) == nil
        let firstTexture = first.texture
        first.cancel()
        let replacement = pipeline.acquireDepthTarget(width: 8, height: 8)
        let reusesReleased = replacement?.texture === firstTexture
        replacement?.cancel()
        second.cancel()
        third.cancel()
        guard let command = queue.makeCommandBuffer(),
              let armed = pipeline.acquireDepthTarget(width: 8, height: 8) else { return [:] }
        let armedTexture = armed.texture
        armed.arm(on: command)
        let completed = SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        let afterCompletion = pipeline.acquireDepthTarget(width: 8, height: 8)
        let completionReleased = completed && afterCompletion?.texture === armedTexture
        afterCompletion?.cancel()
        return [
            "rejectsFourth": rejectsFourth,
            "reusesReleased": reusesReleased,
            "completionReleased": completionReleased,
        ]
    }

    static func cullContract() -> [String: [Int]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [:] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [:] }
        var white = [UInt8](repeating: 255, count: 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        return [
            "frontBackCull": SceneParticleOffscreenReadbackHarness.centerPixel(texture: texture, cullMode: .back),
            "reversedBackCull": SceneParticleOffscreenReadbackHarness.centerPixel(
                texture: texture, cullMode: .back, reversesWinding: true
            ),
            "reversedNoCull": SceneParticleOffscreenReadbackHarness.centerPixel(
                texture: texture, cullMode: .none, reversesWinding: true
            ),
        ]
    }
}
