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
            "ropeProjectionConditioning": ropeProjectionConditioningProfiles(),
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

    static func ropeProjectionConditioningProfiles() -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue() else { return [] }
        let extent = 256
        let camera = SceneParticleCameraFrame(camera: .init(
            eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
            orthoWidth: nil, orthoHeight: nil, fovDegrees: 90,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.1, farZ: 100),
            viewportSize: CGSize(width: CGFloat(extent), height: CGFloat(extent)))
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = .shaderRead
        guard let source = device.makeTexture(descriptor: sourceDescriptor) else { return [] }
        var magenta: [UInt8] = [255, 0, 255, 255]
        source.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                       withBytes: &magenta, bytesPerRow: 4)
        let definition = SceneParticleDefinitionParser().parse(root: [
            "maxcount": 1, "material": "materials/conditioning-card.json", "flags": 0,
            "renderer": [["id": 73, "name": "ropetrail", "length": 1,
                          "segments": 2, "subdivision": 0]]])
        guard let renderer = definition.renderers.first,
              let plan = SceneParticleRopeTrailPlan(renderer: renderer,
                rendererCount: 1, maximumParticleCount: 1) else { return [] }
        let layer = SceneRenderDescriptor.Layer(utilityLayer: nil, usesPerspective: nil)
        // Independent authored geometry: a one-unit horizontal centerline at
        // depth ten, packed world width .05, all anchors inside a 90-degree frustum.
        // The tilted basis plane approaches edge-on to the endpoint's ray;
        // anchor w remains ten throughout. No author script or random seed.
        let criticalY = -10 / sqrt(Float(3))
        let cases: [(String, Float, Float)] = [
            ("safe-before", 0, -5.8203125 - criticalY),
            ("safe-after", 0, -5.7421875 - criticalY),
            ("tilted-before-0.1", .pi / 3, -0.1),
            ("tilted-before-0.01", .pi / 3, -0.01),
            ("tilted-before-0.001", .pi / 3, -0.001),
            ("tilted-after-0.001", .pi / 3, 0.001),
            ("tilted-after-0.01", .pi / 3, 0.01),
            ("tilted-after-0.1", .pi / 3, 0.1),
        ]
        var rows: [[String: Any]] = []
        for (name, tilt, deltaY) in cases {
            let world = SceneMatrix.rotationX(tilt)
                * SceneMatrix.scale(SIMD3<Float>(repeating: 0.1))
            let inverse = simd_inverse(world)
            let endpoints = [SIMD3<Float>(-0.5, criticalY + deltaY, -10),
                             SIMD3<Float>(0.5, criticalY + deltaY, -10)]
            var history = SceneParticleRopeTrailHistory(plan: plan)
            var values: [SceneParticleGPUInstance] = []
            for (index, point) in endpoints.enumerated() {
                let local = inverse * SIMD4(point, 1)
                values = history.advance(by: index == 0 ? 0 : 0.5, particles: [
                    .init(id: 1, position: SIMD3(local.x, local.y, local.z),
                          size: 1, color: SIMD3(repeating: 1), alpha: 0.5)
                ], layerAlpha: 1)
            }
            let uniforms = camera.particleUniforms(
                layerModel: SceneParticleCameraFrame.particleLayerModel(
                    worldFrame: world, parallaxOffset: .zero),
                orientation: .screen, orientationAxis: nil, usesPerspective: false,
                usesSceneCamera: false, inheritsNativeSceneCamera: true,
                layerUsesPerspective: camera.resolvesPerspective(for: layer),
                viewportSize: SIMD2(repeating: Float(extent)), sizeIsWorldSpace: false)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: extent, height: extent, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .renderTarget
            guard let output = device.makeTexture(descriptor: descriptor),
                  let command = queue.makeCommandBuffer() else { return [] }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let buffer = SceneParticleMetalInstanceBuffer()
            guard buffer.update(device: device, instances: values),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
            let encoded = pipeline.draw(texture: source, instances: buffer,
                uniforms: uniforms, renderState: .init(blendMode: .additive, cullMode: .none),
                colorSampling: .directImageFallback, encoder: encoder)
            encoder.endEncoding()
            let completed = encoded && buffer.markSubmitted(on: command)
                && SceneParticleOffscreenReadbackHarness.commitAndWait(command)
            guard completed else { return [["name": name, "completed": false]] }
            var pixels = [UInt8](repeating: 0, count: extent * extent * 4)
            output.getBytes(&pixels, bytesPerRow: extent * 4,
                            from: MTLRegionMake2D(0, 0, extent, extent), mipmapLevel: 0)
            // Analytic 90-degree projection, independent of the shader width
            // solver. Packed width .05 at depth ten is .64px; even the established
            // fourfold miter bound fits a four-pixel pad including rasterization.
            let projected = endpoints.map { point in
                SIMD2((point.x / 10 + 1) * 128, (1 - point.y / 10) * 128)
            }
            let allowed = [Int(floor(projected[0].x)) - 4,
                           Int(floor(projected[0].y)) - 4,
                           Int(ceil(projected[1].x)) + 4,
                           Int(ceil(projected[1].y)) + 4]
            var visible = 0, outside = 0, maximumAlpha = 0
            var bounds = [extent, extent, -1, -1]
            for y in 0..<extent { for x in 0..<extent {
                let alpha = Int(pixels[(y * extent + x) * 4 + 3])
                maximumAlpha = max(maximumAlpha, alpha)
                guard alpha >= 20 else { continue }
                visible += 1
                bounds = [min(bounds[0], x), min(bounds[1], y),
                          max(bounds[2], x), max(bounds[3], y)]
                if x < allowed[0] || y < allowed[1] || x > allowed[2] || y > allowed[3] {
                    outside += 1
                }
            } }
            rows.append(["name": name, "completed": completed,
                "instanceCount": values.count, "inputFinite": values.allSatisfy(\.isFinite),
                "anchorW": endpoints.map { point in
                    (camera.perspectiveViewProjection * SIMD4(point, 1)).w
                }, "preservesWorldModel": uniforms.layerModel == world,
                "basisRight": [uniforms.basisRight.x, uniforms.basisRight.y, uniforms.basisRight.z],
                "basisUp": [uniforms.basisUp.x, uniforms.basisUp.y, uniforms.basisUp.z],
                "allowedBounds": allowed, "bounds": bounds, "visiblePixels": visible,
                "outsidePixels": outside, "maximumAlpha": maximumAlpha,
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

    #if MWX_PARTICLE_CAMERA_DEPTH_PROBES
    static func depthTexture(_ device: MTLDevice, width: Int = 1, height: Int = 1,
        pixels: [UInt8], target: Bool = false) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: target ? .bgra8Unorm : .rgba8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = target ? [.renderTarget, .shaderRead] : .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        pixels.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        return texture
    }

    static func depthBackground() -> [UInt8] {
        var pixels: [UInt8] = []
        for y in 0..<64 {
            for x in 0..<64 {
                let blue: UInt8 = UInt8(24 + x * 2)
                let green: UInt8 = UInt8(32 + y * 2)
                let red: UInt8 = UInt8(56 + (x + y) / 4)
                pixels.append(blue)
                pixels.append(green)
                pixels.append(red)
                pixels.append(UInt8(255))
            }
        }
        return pixels
    }

    static func depthBatch(_ device: MTLDevice, texture: MTLTexture,
        state: SceneParticlePipelineRenderState, z: Float, size: Float, x: Float = 0,
        refraction: SceneParticleRefractionBinding? = nil, rotation: Float = 0,
        layerID: Int = 731, path: String = "particles/depth.json",
        orientation: SceneParticleOrientation = .screen, trailVelocity: SIMD3<Float>? = nil,
        perspective: Bool = true, worldSize: Bool = false) -> SceneParticleDrawBatch? {
        let values = [SceneParticleGPUInstance(position: SIMD3(x, 0, z), size: size,
            rotation: SIMD3(0, rotation, 0), color: SIMD3(repeating: 1), alpha: 1,
            velocity: trailVelocity ?? .zero, trailStretch: trailVelocity == nil ? nil : 1)]
        return .init(layerID: layerID, particlePath: path, texture: texture,
            colorUVScale: SIMD2(repeating: 1), colorSampling: .directImageFallback,
            refraction: refraction, renderState: state, childTemplateIndex: nil,
            instances: values, orientation: orientation, orientationAxis: nil,
            usesPerspective: perspective, sizeIsWorldSpace: worldSize)
    }

    static func commonCullProfiles() -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice(), let pipeline = SceneParticleMetalPipeline(device: device),
              let white = depthTexture(device, pixels: [255,255,255,255]),
              let red = depthTexture(device, pixels: [255,0,0,255]),
              let normal = depthTexture(device, pixels: [255,128,0,255]) else { return [] }
        let binding = SceneParticleRefractionBinding(normalTexture: normal, amount: 0.125,
            overbright: 1, colorEncoding: .rgba, normalUsesParticleFrames: false,
            normalUVScale: SIMD2(repeating: 1), normalSampling: .directImageFallback, normalFormat: .rgba8888)
        let geometries: [(String, SceneParticleOrientation, SIMD3<Float>, Float, Bool, SIMD3<Float>?, Bool?)] = [
            ("local-screen", .screen, SIMD3(1,1,1), 0, false, nil, true),
            ("local-reflected", .screen, SIMD3(-1,1,1), 0, false, nil, false),
            ("local-double-reflected", .screen, SIMD3(-1,-1,1), 0, false, nil, true),
            ("local-anisotropic-rolled", .screen, SIMD3(1.5,0.5,1), 0.3, false, nil, true),
            ("fixed", .fixed, SIMD3(1,1,1), 0, false, nil, true),
            ("fixed-reflected", .fixed, SIMD3(-1,1,1), 0, false, nil, false),
            ("world-size-reflected", .worldScreen, SIMD3(-1,1,1), 0, true, nil, true),
            ("trail", .screen, SIMD3(1,1,1), 0, false, SIMD3(1,0,0), nil),
            ("trail-reflected", .screen, SIMD3(-1,1,1), 0, false, SIMD3(1,0,0), nil),
        ]
        var rows: [[String: Any]] = []
        for perspective in [false, true] {
            let camera = SceneParticleCameraFrame(camera: .init(eye: [32,32,64], center: [32,32,0], up: [0,1,0],
                orthoWidth: 64, orthoHeight: 64, fovDegrees: nil,
                perspectiveOverrideFOVDegrees: 2 * atan(0.5) * 180 / .pi, nearZ: 1, farZ: 200),
                viewportSize: CGSize(width: 64,height: 64))
            for (name, orientation, scale, roll, worldSize, velocity, front) in geometries {
                let model = SceneParticleCameraFrame.particleLayerModel(worldFrame:
                    SceneMatrix.translation(SIMD3(32,32,0)) * SceneMatrix.rotationZ(roll)
                        * SceneMatrix.scale(scale), parallaxOffset: .zero)
                var masks: [[Bool]] = [], completed = true, leased = false
                var geometry: [[Float]] = [], projectedAreas: [Float] = []
                for refract in [false, true] {
                    for cull in [SceneParticlePipelineCullMode.back, .none] {
                        let state = SceneParticlePipelineRenderState(blendMode: .translucent, cullMode: cull,
                            usesSceneCamera: !refract && orientation != .fixed)
                        let uniforms = camera.particleUniforms(layerModel: model, orientation: orientation,
                            orientationAxis: nil, usesPerspective: perspective, usesSceneCamera: state.usesSceneCamera,
                            viewportSize: SIMD2(64,64), sizeIsWorldSpace: worldSize)
                        geometry.append([uniforms.spriteRight.x,uniforms.spriteRight.y,
                            uniforms.spriteUp.x,uniforms.spriteUp.y])
                        let right = uniforms.viewProjection * uniforms.spriteRight
                        let up = uniforms.viewProjection * uniforms.spriteUp
                        projectedAreas.append(right.x * up.y - right.y * up.x)
                        guard let batch = depthBatch(device, texture: refract ? white : red, state: state,
                            z: 0, size: 20, refraction: refract ? binding : nil,
                            path: "particles/renamed-\(name).json", orientation: orientation,
                            trailVelocity: velocity, perspective: perspective, worldSize: worldSize),
                              let result = depthDraw("cull-\(perspective)-\(name)-\(refract)-\(cull.rawValue)",
                                device: device, pipeline: pipeline, batches: pipeline.prepare([batch]),
                                camera: camera, model: model) else { return [] }
                        completed = completed && result.completed; leased = leased || result.hasLease || result.depthBytes != 0
                        let original = depthBackground()
                        masks.append(stride(from: 0,to: original.count,by: 4).map {
                            result.pixels[$0..<$0+4] != original[$0..<$0+4]
                        })
                    }
                }
                rows.append(["name": name, "perspective": perspective, "completed": completed,
                    "hasDepth": leased, "ordinaryBackCount": masks[0].filter { $0 }.count,
                    "ordinaryNoneCount": masks[1].filter { $0 }.count,
                    "refractionBackCount": masks[2].filter { $0 }.count,
                    "refractionNoneCount": masks[3].filter { $0 }.count,
                    "sameBackCoverage": masks[0] == masks[2], "sameNoneCoverage": masks[1] == masks[3],
                    "expectedFront": front.map { $0 as Any } ?? NSNull(),
                    "geometryAxes": geometry, "spriteProjectedAreas": projectedAreas])
            }
        }
        return rows
    }

    static func depthDraw(_ name: String, device: MTLDevice, pipeline: SceneParticleMetalPipeline,
        batches: [SceneParticleMetalPipeline.PreparedBatch], camera: SceneParticleCameraFrame,
        model: simd_float4x4 = SceneMatrix.identity())
        -> (pixels: [UInt8], hasLease: Bool, depthBytes: Int, completed: Bool)? {
        guard let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(),
              let target = depthTexture(device, width: 64, height: 64,
                pixels: depthBackground(), target: true) else { return nil }
        let pass = SceneMainPassEncoder(commandBuffer: command, target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: false)
        var observations: [SceneParticlePerformanceObservation]? = nil
        let lease = pipeline.drawBatches(batches, model: model,
            cameraFrame: camera, viewportSize: SIMD2(repeating: 64), mainPass: pass,
            commandBuffer: command, preparedDepth: nil, performanceObservations: &observations)
        let finished = pass.finishEnsuringClear()
        lease?.arm(on: command)
        pass.armCompositionPins()
        let completed = finished && SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        guard completed else { return nil }
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        target.getBytes(&pixels, bytesPerRow: 64 * 4,
            from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
        if let root = ProcessInfo.processInfo.environment["MWX_PARTICLE_CAMERA_READBACK_DIR"] {
            let directory = URL(fileURLWithPath: root, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(pixels).write(to: directory.appendingPathComponent(name + ".bgra"))
            } catch { return nil }
        }
        return (pixels, lease != nil,
            pipeline.renderTargetResidentByteCost - pipeline.framebufferSnapshot.residentByteCost, completed)
    }

    static func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        stride(from: 0, to: min(a.count, b.count), by: 4).filter {
            a[$0..<$0 + 4] != b[$0..<$0 + 4]
        }.count
    }

    static func refractionDepthProfiles() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let white = depthTexture(device, pixels: [255, 255, 255, 255]),
              let normal = depthTexture(device, pixels: [255, 128, 0, 255]),
              let red = depthTexture(device, pixels: [160, 0, 0, 255]),
              let green = depthTexture(device, pixels: [0, 255, 0, 255]),
              let blue = depthTexture(device, pixels: [0, 0, 255, 255]) else { return [:] }
        let required: Set<SceneParticlePipelineVariant> = [
            .init(isRefraction: true, blendMode: .translucent),
            .init(isRefraction: true, blendMode: .translucent, usesDepthAttachment: true),
            .init(isRefraction: true, blendMode: .additive),
            .init(isRefraction: true, blendMode: .additive, usesDepthAttachment: true),
            .init(blendMode: .translucent, usesDepthAttachment: true),
            .init(blendMode: .alphaToCoverage, usesDepthAttachment: true),
        ]
        guard let pipeline = SceneParticleMetalPipeline(device: device, requiredVariants: required),
              let readonlyPipeline = SceneParticleMetalPipeline(device: device, requiredVariants: [
                .init(isRefraction: true, blendMode: .translucent),
                .init(isRefraction: true, blendMode: .additive),
              ]) else { return [:] }
        let camera = SceneParticleCameraFrame(camera: .init(eye: [0, 0, 0], center: [0, 0, -1],
            up: [0, 1, 0], orthoWidth: nil, orthoHeight: nil, fovDegrees: 90,
            perspectiveOverrideFOVDegrees: nil, nearZ: 1, farZ: 20),
            viewportSize: CGSize(width: 64, height: 64))
        let binding = SceneParticleRefractionBinding(normalTexture: normal, amount: 0.15,
            overbright: 0.6, colorEncoding: .rgba, normalUsesParticleFrames: false,
            normalUVScale: SIMD2(repeating: 1), normalSampling: .directImageFallback, normalFormat: .rgba8888)
        func state(_ test: Bool, write: Bool = false, blend: SceneParticlePipelineBlendMode = .translucent,
                   cull: SceneParticlePipelineCullMode = .none)
            -> SceneParticlePipelineRenderState {
            .init(blendMode: blend, cullMode: cull, depthTestEnabled: test, depthWriteEnabled: write)
        }
        func center(_ pixels: [UInt8]) -> [Int] {
            Array(pixels[(32 * 64 + 32) * 4..<(32 * 64 + 32) * 4 + 4]).map(Int.init)
        }
        var readonly: [[String: Any]] = [], mixed: [[String: Any]] = [], clipRows: [[String: Any]] = []
        for renamed in [false, true] {
            let variant = renamed ? "renamed" : "original"
            let path = renamed ? "particles/independent/renamed-reader.json" : "particles/depth-reader.json"
            let shift: Float = renamed ? 0.125 : 0
            for reversed in [false, true] {
                let order = reversed ? "reversed" : "forward"
                var results: [(pixels: [UInt8], hasLease: Bool, depthBytes: Int, completed: Bool)] = []
                for test in [true, false] {
                    guard let a = depthBatch(device, texture: white, state: state(test, blend: .additive,
                            cull: renamed ? .back : .none),
                        z: -4, size: 3.2, x: -0.3 + shift, refraction: binding, path: path),
                        let b = depthBatch(device, texture: white, state: state(test, blend: .additive,
                            cull: renamed ? .back : .none),
                        z: -7, size: 5.6, x: 0.4 + shift, refraction: binding, layerID: 732, path: path),
                        let result = depthDraw("A-\(variant)-\(order)-\(test)", device: device,
                            pipeline: readonlyPipeline, batches: readonlyPipeline.prepare(reversed ? [b, a] : [a, b]), camera: camera)
                    else { return ["failure": "A-\(variant)-\(order)"] }
                    results.append(result)
                }
                readonly.append(["variant": variant, "order": order,
                    "completed": results.allSatisfy(\.completed), "equalPixels": results[0].pixels == results[1].pixels,
                    "changedPixels": changedPixels(results[0].pixels, depthBackground()),
                    "hasLease": results.map(\.hasLease), "depthBytes": results.map(\.depthBytes)])
            }
            for writerFirst in [true, false] {
                let order = writerFirst ? "writer-first" : "writer-last"
                var results: [(pixels: [UInt8], hasLease: Bool, depthBytes: Int, completed: Bool)] = []
                guard let writer = depthBatch(device, texture: red, state: state(true, write: true),
                    z: -3, size: 2.4), let baseline = depthDraw("B-\(variant)-writer", device: device,
                        pipeline: pipeline, batches: pipeline.prepare([writer]), camera: camera) else { return ["failure": "B-writer"] }
                for test in [true, false] {
                    guard let writer = depthBatch(device, texture: red, state: state(true, write: true), z: -3, size: 2.4),
                          let reader = depthBatch(device, texture: white,
                            state: state(test, blend: renamed ? .additive : .translucent,
                                cull: renamed ? .back : .none),
                            z: -6, size: 6, x: shift, refraction: binding, layerID: 732, path: path),
                          let probe = depthBatch(device, texture: green, state: state(true), z: -8, size: 3, layerID: 733),
                          let coverage = depthBatch(device, texture: blue, state: state(true, blend: .alphaToCoverage),
                            z: -6, size: 1, x: 2.8, layerID: 734),
                          let result = depthDraw("B-\(variant)-\(order)-\(test)", device: device,
                            pipeline: pipeline, batches: pipeline.prepare((writerFirst ? [writer, reader] : [reader, writer])
                                + [probe, coverage]), camera: camera) else { return ["failure": "B-\(variant)-\(order)"] }
                    results.append(result)
                }
                mixed.append(["variant": variant, "order": order, "completed": results.allSatisfy(\.completed),
                    "readerBlend": renamed ? "additive" : "translucent",
                    "writerCenter": center(baseline.pixels), "onCenter": center(results[0].pixels),
                    "offCenter": center(results[1].pixels),
                    "coveragePixels": results.map { Array($0.pixels[(32 * 64 + 47) * 4..<(32 * 64 + 47) * 4 + 4]).map(Int.init) },
                    "differentPixels": changedPixels(results[0].pixels, results[1].pixels),
                    "hasLease": results.map(\.hasLease), "depthBytes": results.map(\.depthBytes),
                    "greenProbePixels": results.map { result in stride(from: 0, to: result.pixels.count, by: 4).filter {
                        result.pixels[$0 + 1] > 245 && result.pixels[$0] < 5 && result.pixels[$0 + 2] < 5
                    }.count }])
            }
            let geometries: [(String, Float, Float, Float)] = [
                ("legal-near", -2, 1.6, 0), ("legal-far", -15, 8, 0),
                ("cross-near", -1.1, 1.2, 1), ("cross-far", -19, 12, 1), ("behind-eye", 3, 1, 0),
            ]
            for (name, z, size, rotation) in geometries {
                var results: [(pixels: [UInt8], hasLease: Bool, depthBytes: Int, completed: Bool)] = []
                var mvps: [simd_float4x4] = []
                let uniforms = camera.particleUniforms(layerModel: SceneMatrix.identity(), orientation: .screen,
                    orientationAxis: nil, usesPerspective: true, usesSceneCamera: false,
                    viewportSize: SIMD2(repeating: 64), sizeIsWorldSpace: false)
                let corners = [-size / 2, size / 2].flatMap { x in [-size / 2, size / 2].map { y in
                    let local = SceneMatrix.rotationY(-rotation) * SIMD4(x, y, 0, 0)
                    return uniforms.viewProjection * (uniforms.layerModel * SIMD4(shift, 0, z, 1)
                        + uniforms.spriteRight * local.x + uniforms.spriteUp * local.y + uniforms.spriteForward * local.z)
                } }
                for test in [true, false] {
                    let renderState = state(test, cull: renamed ? .back : .none)
                    let actual = camera.particleUniforms(layerModel: SceneMatrix.identity(), orientation: .screen,
                        orientationAxis: nil, usesPerspective: true, usesSceneCamera: renderState.usesSceneCamera,
                        viewportSize: SIMD2(repeating: 64), sizeIsWorldSpace: false)
                    mvps.append(actual.viewProjection * actual.layerModel)
                    guard let batch = depthBatch(device, texture: white, state: renderState,
                        z: z, size: size, x: shift, refraction: binding, rotation: rotation, path: path),
                          let result = depthDraw("C-\(variant)-\(name)-\(test)", device: device,
                            pipeline: readonlyPipeline, batches: readonlyPipeline.prepare([batch]), camera: camera) else { return ["failure": "C-\(name)"] }
                    results.append(result)
                }
                clipRows.append(["variant": variant, "geometry": name,
                    "completed": results.allSatisfy(\.completed), "sameMVP": mvps[0] == mvps[1],
                    "equalPixels": results[0].pixels == results[1].pixels,
                    "changedPixels": changedPixels(results[0].pixels, depthBackground()),
                    "outsideCorners": corners.filter { $0.w <= 0 || $0.z < 0 || $0.z > $0.w }.count,
                    "inputClipZW": corners.map { [$0.z, $0.w] }, "depthBytes": results.map(\.depthBytes)])
            }
        }
        return ["readonly": readonly, "mixed": mixed, "clip": clipRows,
            "nearDepth": ndc(camera.perspectiveViewProjection, SIMD4(0, 0, -1, 1))[2],
            "farDepth": ndc(camera.perspectiveViewProjection, SIMD4(0, 0, -20, 1))[2],
            "fov90Edge": ndc(camera.perspectiveViewProjection, SIMD4(1, 0, -1, 1))[0],
            "compiledVariants": pipelineVariantNames(Set(pipeline.pipelineStates.keys))]
    }

    static func pipelineVariantNames(_ variants: Set<SceneParticlePipelineVariant>) -> [String] {
        variants.map { "\($0.isRefraction ? "refraction" : "ordinary")/\($0.blendMode.rawValue)/\($0.usesDepthAttachment ? "depth" : "plain")" }.sorted()
    }

    static func particleVariantDemand() -> [[String: Any]] {
        do { return try preparedVariantDemand() }
        catch { return [["completed": false, "reason": String(describing: error)]] }
    }

    static func preparedVariantDemand() throws -> [[String: Any]] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-camera-particle-demand-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("materials"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = CGDataProvider(data: Data([255, 255, 255, 255]) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent("materials/source.png") as CFURL,
            "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        try CameraHarness.writeAnimatedTEX(directory.appendingPathComponent("materials/source.tex"))
        guard CGImageDestinationFinalize(destination), let device = MTLCreateSystemDefaultDevice()
        else { return [["completed": false, "reason": "image/device"]] }
        func particle(_ name: String, material: String, delayed: Bool = false, children: [[String: Any]] = []) throws {
            let path = directory.appendingPathComponent("particles/\(name).json")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["material": "materials/\(material).json", "maxcount": 2,
                "starttime": 0, "flags": 0,
                "emitter": [["name": "sphererandom", "rate": delayed ? 4 : 0,
                    "instantaneous": delayed ? 0 : 1, "distancemin": 0, "distancemax": 0,
                    "origin": name == "coverage" ? [16, 0, 0] : [0, 0, name == "writer" ? 2 : (name == "reader" ? -2 : 0)]]],
                "initializer": [["name": "lifetimerandom", "min": 10, "max": 10], ["name": "sizerandom", "min": 8, "max": 8]],
                "renderer": [["name": "sprite"]], "children": children]).write(to: path)
        }
        try particle("ordinary", material: "ordinary", delayed: true)
        try particle("readonly", material: "reader", delayed: true)
        for name in ["writer", "reader", "coverage"] { try particle(name, material: name) }
        try particle("mixed", material: "root", delayed: true, children: ["writer", "reader", "coverage"].map {
            ["name": "particles/\($0).json", "type": "eventspawn"]
        })
        func overbright(_ value: Double) -> [String: SceneDocument.ShaderValue] {
            ["ui_editor_properties_overbright": .init(rawValue: String(value), valueKind: "number",
                components: [value], userBinding: nil, timeline: nil, timelineDiagnostics: [])]
        }
        let passes: [SceneRenderDescriptor.MaterialPassDescriptor] = [
            .init(materialPath: "materials/ordinary.json", shaderPath: "genericparticle", texturePaths: ["source.png"], blending: "translucent"),
            .init(materialPath: "materials/root.json", shaderPath: "genericparticle", texturePaths: ["source.png"],
                constantShaderValues: overbright(0), blending: "additive"),
            .init(materialPath: "materials/reader.json", shaderPath: "genericparticle", texturePaths: ["source.tex"],
                constantShaderValues: overbright(0.5), blending: "translucent", combos: ["REFRACT": 1], depthTest: "enabled"),
            .init(materialPath: "materials/writer.json", shaderPath: "genericparticle", texturePaths: ["source.png"],
                blending: "translucent", depthTest: "enabled", depthWrite: "enabled"),
            .init(materialPath: "materials/coverage.json", shaderPath: "genericparticle", texturePaths: ["source.png"], blending: "alphatocoverage"),
        ]
        let camera = SceneParticleCameraFrame(camera: .init(eye: [32, 32, 64], center: [32, 32, 0], up: [0, 1, 0],
            orthoWidth: 64, orthoHeight: 64, fovDegrees: nil, perspectiveOverrideFOVDegrees: nil,
            nearZ: 1, farZ: 1000), viewportSize: CGSize(width: 64, height: 64))
        var rows: [[String: Any]] = []
        for scenario in ["ordinary", "readonly", "mixed"] {
            let layer = SceneRenderDescriptor.Layer(id: 731, name: nil, contentKind: "particle",
                particlePath: "particles/\(scenario).json", particleInstanceOverride: nil,
                parentID: nil, visible: true, alpha: 1)
            let descriptor = SceneRenderDescriptor(layers: [layer], renderOrderLayerIDs: [731], materialPasses: passes)
            let graph = try SceneParticleRuntime.prepareAssets(descriptor: descriptor,
                resourceView: .init(projectRootURL: directory, packageRootURL: nil, stockAssetsRootURL: nil), stockTextureBundleURL: nil)
            let runtime = SceneParticleRuntime(descriptor: descriptor, preparedAssets: graph, device: device)
            let required = runtime.requiredPipelineVariants
            guard let pipeline = SceneParticleMetalPipeline(device: device, requiredVariants: required)
            else { return [["scenario": scenario, "completed": false, "reason": "pipeline"]] }
            let before = pipelineVariantNames(Set(pipeline.pipelineStates.keys))
            let initial = runtime.advance(by: 0)
            _ = runtime.advance(by: 0.3)
            let later = runtime.advance(by: 1.0 / 60.0)
            let prepared = pipeline.prepare(later)
            guard prepared.count == later.count else {
                runtime.teardown()
                return [["scenario": scenario, "completed": false, "reason": "instance-buffer-upload"]]
            }
            let uploadedInstanceCounts = prepared.map { $0.instanceBuffer.count }
            let model = SceneParticleCameraFrame.particleLayerModel(
                worldFrame: SceneMatrix.translation(SIMD3(32, 32, 0)), parallaxOffset: .zero)
            let draw = depthDraw("D-\(scenario)", device: device, pipeline: pipeline, batches: prepared, camera: camera, model: model)
            var initialInstances: Int = 0
            for batch in initial { initialInstances += batch.instances.count }
            var center: [Int] = []
            if let pixels = draw?.pixels {
                for channel in 0..<4 { center.append(Int(pixels[(32 * 64 + 32) * 4 + channel])) }
            }
            var refractionCameras: [Bool] = []
            for batch in later where batch.refraction != nil {
                refractionCameras.append(batch.renderState.usesSceneCamera)
            }
            let writerIndex: Int = later.firstIndex { $0.particlePath == "particles/writer.json" } ?? -1
            let readerIndex: Int = later.firstIndex { $0.particlePath == "particles/reader.json" } ?? -1
            let laterPaths: [String] = later.map(\.particlePath)
            var row: [String: Any] = [:]
            row["scenario"] = scenario
            row["completed"] = draw?.completed ?? false
            row["initialBatches"] = initial.count
            row["laterBatches"] = later.count
            row["uploadedInstanceCounts"] = uploadedInstanceCounts
            row["initialInstances"] = initialInstances
            row["hasLease"] = draw?.hasLease ?? false
            row["depthBytes"] = draw?.depthBytes ?? -1
            row["center"] = center
            row["refractionUsesSceneCamera"] = refractionCameras
            row["required"] = pipelineVariantNames(required)
            row["compiledBefore"] = before
            row["compiledAfter"] = pipelineVariantNames(Set(pipeline.pipelineStates.keys))
            row["writerIndex"] = writerIndex
            row["readerIndex"] = readerIndex
            row["laterPaths"] = laterPaths
            let graphDiagnostics: [[String: String]] = graph.diagnostics.map {
                ["kind": $0.kind.rawValue, "assetPath": $0.assetPath, "detail": $0.detail ?? ""]
            }
            row["graphDiagnostics"] = graphDiagnostics
            #if DEBUG
            let runtimeDiagnostics: [[String: String]] = runtime.diagnostics.map {
                ["kind": $0.kind.rawValue, "particlePath": $0.particlePath, "detail": $0.detail ?? ""]
            }
            row["runtimeDiagnostics"] = runtimeDiagnostics
            #else
            row["runtimeDiagnostics"] = "unavailable-in-release"
            #endif
            rows.append(row)
            runtime.teardown()
        }
        return rows
    }
    #endif // MWX_PARTICLE_CAMERA_DEPTH_PROBES
}
