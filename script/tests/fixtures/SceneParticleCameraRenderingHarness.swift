import Foundation
import CryptoKit
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
            "nativeRopeProfiles": nativeRopeProfiles(),
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
              case let .acquired(depthLease) = pipeline.acquireDepthTarget(width: size, height: size, on: command)
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

    static func nativeRopeProfiles() -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue() else { return [] }
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = .shaderRead
        guard let source = device.makeTexture(descriptor: sourceDescriptor) else { return [] }
        var sides: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255]
        source.replace(region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0,
                       withBytes: &sides, bytesPerRow: 8)
        let extent = 256
        let viewport = SIMD2<Float>(repeating: Float(extent))
        let camera = SceneParticleCameraFrame(camera: .init(
            eye: [0.8, 0.6, 1], center: [0, 0, -8], up: [0.2, 1, 0.1],
            orthoWidth: nil, orthoHeight: nil, fovDegrees: 60,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.1, farZ: 1000),
            viewportSize: CGSize(width: CGFloat(extent), height: CGFloat(extent)))
        let layer = SceneRenderDescriptor.Layer(utilityLayer: nil, usesPerspective: nil)
        let points: [SIMD3<Float>] = [SIMD3(-1.5, -0.8, 0.3),
                                     SIMD3(0, 0.6, 0), SIMD3(1.7, -0.3, -0.8)]
        var rows: [[String: Any]] = []
        for (name, depth, identifier, material) in [
            ("native-parent-near", Float(-8), 1, "materials/card.json"),
            ("renamed-equivalent", Float(-8), 71, "materials/renamed-ribbon.json"),
            ("native-parent-far", Float(-14), 1, "materials/card.json")
        ] {
            let definition = SceneParticleDefinitionParser().parse(root: [
                "maxcount": 1, "material": material, "flags": 0,
                "renderer": [["id": identifier, "name": "ropetrail", "length": 1,
                              "segments": 2, "subdivision": 0]]])
            guard let renderer = definition.renderers.first,
                  let plan = SceneParticleRopeTrailPlan(renderer: renderer,
                    rendererCount: definition.renderers.count, maximumParticleCount: 1)
            else { return [["name": name, "completed": false, "reason": "plan"]] }
            var history = SceneParticleRopeTrailHistory(plan: plan)
            var values: [SceneParticleGPUInstance] = []
            for (index, point) in points.enumerated() {
                values = history.advance(by: index == 0 ? 0 : 0.5,
                    particles: [.init(id: 1, position: point, size: 0.6,
                                      color: SIMD3(repeating: 1), alpha: 0.5)], layerAlpha: 1)
            }
            let parent = SceneMatrix.translation(SIMD3<Float>(0.3, -0.2, 0))
                * SceneMatrix.rotationZ(0.27) * SceneMatrix.scale(SIMD3(1, 0.75, 1))
            let world = parent * SceneMatrix.translation(SIMD3<Float>(0, 0, depth))
                * SceneMatrix.rotationY(0.16)
            let model = SceneParticleCameraFrame.particleLayerModel(
                worldFrame: world, parallaxOffset: .zero)
            let uniforms = camera.particleUniforms(layerModel: model, orientation: .screen,
                orientationAxis: nil, usesPerspective: definition.flags.usesPerspective,
                usesSceneCamera: false, inheritsNativeSceneCamera: true,
                layerUsesPerspective: camera.resolvesPerspective(for: layer),
                viewportSize: viewport, sizeIsWorldSpace: false)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: extent, height: extent, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .renderTarget
            guard let target = device.makeTexture(descriptor: descriptor),
                  let command = queue.makeCommandBuffer() else { return [] }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let buffer = SceneParticleMetalInstanceBuffer()
            guard buffer.update(device: device, instances: values),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
            let encoded = pipeline.draw(texture: source, instances: buffer, uniforms: uniforms,
                renderState: .init(blendMode: .translucent, cullMode: .none),
                colorSampling: .init(texFlags: 3), encoder: encoder)
            encoder.endEncoding()
            let completed = encoded && buffer.markSubmitted(on: command)
                && SceneParticleOffscreenReadbackHarness.commitAndWait(command)
            guard completed else { return [["name": name, "completed": false, "reason": "GPU"]] }
            var pixels = [UInt8](repeating: 0, count: extent * extent * 4)
            target.getBytes(&pixels, bytesPerRow: extent * 4,
                            from: MTLRegionMake2D(0, 0, extent, extent), mipmapLevel: 0)
            // Expected positions use authored world + native VP, independently
            // of the particle uniform selection and its incoming canvas flip.
            func project(_ point: SIMD3<Float>) -> SIMD2<Float> {
                let clip = camera.perspectiveViewProjection * world * SIMD4(point, 1)
                return SIMD2((clip.x / clip.w + 1) * 0.5,
                             (1 - clip.y / clip.w) * 0.5) * viewport
            }
            let expected = points.map(project)
            let probes = [points[0] * 0.8 + points[1] * 0.2, points[1],
                          points[1] * 0.2 + points[2] * 0.8].map(project)
            let pathAlpha = probes.map { probe -> Int in
                let x = Int(probe.x.rounded()), y = Int(probe.y.rounded())
                return ((y - 1)...(y + 1)).flatMap { row in
                    ((x - 1)...(x + 1)).map { column -> Int in
                        guard (0..<extent).contains(row), (0..<extent).contains(column)
                        else { return 0 }
                        return Int(pixels[(row * extent + column) * 4 + 3])
                    }
                }.max() ?? 0
            }
            var bounds = [extent, extent, -1, -1]
            var count = 0, maximumAlpha = 0, red = 0, blue = 0
            for y in 0..<extent { for x in 0..<extent {
                let offset = (y * extent + x) * 4
                let alpha = Int(pixels[offset + 3])
                maximumAlpha = max(maximumAlpha, alpha)
                guard alpha >= 20 else { continue }
                count += 1
                bounds = [min(bounds[0], x), min(bounds[1], y),
                          max(bounds[2], x), max(bounds[3], y)]
                if pixels[offset + 2] > 20 && pixels[offset] < 10 { red += 1 }
                if pixels[offset] > 20 && pixels[offset + 2] < 10 { blue += 1 }
            } }
            rows.append(["name": name, "completed": completed,
                "instanceCount": values.count, "preservesWorldModel": uniforms.layerModel == world,
                "pathAlpha": pathAlpha, "maximumAlpha": maximumAlpha,
                "visiblePixels": count, "redPixels": red, "bluePixels": blue,
                "bounds": bounds, "expectedBounds": [expected.map(\.x).min()!,
                    expected.map(\.y).min()!, expected.map(\.x).max()!, expected.map(\.y).max()!],
                "pixelSHA256": SHA256.hash(data: Data(pixels)).map { String(format: "%02x", $0) }.joined()
            ])
        }
        return rows
    }

    static func depthTargetLeaseContract() -> [String: Bool] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let owner = queue.makeCommandBuffer(),
              case let .acquired(first) = pipeline.acquireDepthTarget(width: 8, height: 8, on: owner),
              case let .acquired(second) = pipeline.acquireDepthTarget(width: 8, height: 8, on: owner),
              case let .acquired(third) = pipeline.acquireDepthTarget(width: 8, height: 8, on: owner) else { return [:] }
        let rejectsFourth: Bool
        if case .currentFrameCapacityExceeded = pipeline.acquireDepthTarget(width: 8, height: 8, on: owner) {
            rejectsFourth = true
        } else { rejectsFourth = false }
        let firstTexture = first.texture
        first.cancel()
        guard case let .acquired(replacement) = pipeline.acquireDepthTarget(width: 8, height: 8, on: owner)
        else { return [:] }
        let reusesReleased = replacement.texture === firstTexture
        replacement.cancel()
        second.cancel()
        third.cancel()
        guard let command = queue.makeCommandBuffer(),
              case let .acquired(armed) = pipeline.acquireDepthTarget(width: 8, height: 8, on: command) else { return [:] }
        let armedTexture = armed.texture
        armed.arm(on: command)
        let completed = SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        guard let next = queue.makeCommandBuffer(),
              case let .acquired(afterCompletion) = pipeline.acquireDepthTarget(width: 8, height: 8, on: next)
        else { return [:] }
        let completionReleased = completed && afterCompletion.texture === armedTexture
        afterCompletion.cancel()
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
