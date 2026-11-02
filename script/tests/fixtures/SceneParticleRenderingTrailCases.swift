extension Harness {
    private static func ropeTrailJoinContract(connectParticles: Bool = false) -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = .shaderRead
        let input = device.makeTexture(descriptor: inputDescriptor)!
        var white: [UInt8] = [255, 255, 255, 255]
        input.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                      withBytes: &white, bytesPerRow: 4)
        var transforms = [SceneMatrix.identity(), SceneMatrix.scale(SIMD3(-1.2, 0.8, 1)),
                          SceneMatrix.rotationZ(0.37) * SceneMatrix.scale(SIMD3(0.8, 1.2, 1)),
                          SceneMatrix.identity(), SceneMatrix.identity()]
        if connectParticles { transforms += [SceneMatrix.identity(), SceneMatrix.identity()] }
        return transforms.enumerated().map { transformIndex, model in
            let repeated = transformIndex == 3
            let perspective = transformIndex == 4
            let tapered = transformIndex == 5
            let points: [SIMD3<Float>] = tapered
                ? [SIMD3(-0.7, 0, 0), .zero, SIMD3(0.7, 0, 0)]
                : perspective
                ? [SIMD3(0, 0, -5), SIMD3(0.5, 0, -1), SIMD3(0.6, 0, -0.8)]
                : repeated
                    ? [SIMD3(-0.5, 0, 0), .zero, .zero, SIMD3(0, 0.5, 0)]
                    : [SIMD3(-0.5, 0, 0), .zero, SIMD3(0, 0.5, 0)]
            let projection = perspective ? simd_float4x4(
                SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
                SIMD4(0, 0, -1.01, -1), SIMD4(0, 0, -0.101, 0)
            ) : SceneMatrix.identity()
            let definition = SceneParticleDefinitionParser().parse(root: [
                "maxcount": 1, "material": "materials/particle.json",
                "emitter": [["name": "sphererandom"]],
                "renderer": [["name": "ropetrail", "length": Double(points.count - 1) * 0.5, "segments": points.count - 1, "subdivision": 0]]])
            let plan = SceneParticleRopeTrailPlan(renderer: definition.renderers[0],
                rendererCount: 1, maximumParticleCount: 1)!
            var history = SceneParticleRopeTrailHistory(plan: plan)
            var values: [SceneParticleGPUInstance] = []
            for (i, point) in points.enumerated() {
                values = history.advance(by: i == 0 ? 0 : 0.5,
                    particles: [.init(id: 1, position: point, size: i == 1 ? 0.5 : 0.3,
                                      color: SIMD3(repeating: 1), alpha: 0.5)], layerAlpha: 1)
            }
            if connectParticles {
                let ropeDefinition = SceneParticleDefinitionParser().parse(root: [
                    "maxcount": points.count, "material": "materials/particle.json",
                    "renderer": [["name": "rope", "subdivision": transformIndex == 6 ? 3 : 0]]])
                let rope = SceneParticleRopePlan(renderer: ropeDefinition.renderers[0],
                    rendererCount: 1, maximumParticleCount: points.count)!
                let particles = points.enumerated().map { i, point in
                    let size: Double = tapered ? [0.2, 0.6, 0][i] : (repeated && i == 2 ? 0.8 : 0.3)
                    return SceneParticleState(id: UInt64(i),
                        position: SIMD3(Double(point.x), Double(point.y), Double(point.z)),
                        velocity: .zero, color: SIMD3(repeating: 1), alpha: 0.5,
                        size: size, rotation: .zero, angularVelocity: .zero,
                        age: 0, lifetime: 1, initialColor: SIMD3(repeating: 1),
                        initialAlpha: 0.5, initialSize: size)
                }
                values = rope.instances(particles: particles, layerAlpha: 1)
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .renderTarget
            let output = device.makeTexture(descriptor: descriptor)!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            let instances = SceneParticleMetalInstanceBuffer()
            guard instances.update(device: device, instances: values) else { return ["completed": false] }
            pipeline.draw(texture: input, instances: instances,
                uniforms: .init(viewProjection: projection, layerModel: model,
                    basis: SceneParticleOrientation.screen.basis(cameraRight: SIMD3(1, 0, 0),
                        cameraUp: SIMD3(0, 1, 0), cameraForward: SIMD3(0, 0, -1)),
                    viewportSize: SIMD2(256, 256)),
                renderState: particleState(.translucent), colorSampling: .directImageFallback, encoder: encoder)
            encoder.endEncoding()
            guard instances.markSubmitted(on: command), SceneParticleOffscreenReadbackHarness.commitAndWait(command), command.status == .completed else {
                return ["completed": false]
            }
            var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
            output.getBytes(&pixels, bytesPerRow: 256 * 4,
                           from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
            let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            let jointX = perspective ? 192 : 128
            let jointCovered = (125...130).allSatisfy { y in
                ((jointX - 3)...(jointX + 2)).allSatisfy { x in pixels[(y * 256 + x) * 4 + 3] >= 127 }
            }
            return ["completed": true, "transform": transformIndex,
                    "maximumAlpha": Int(alphas.max() ?? 0),
                    "visiblePixels": alphas.filter { $0 > 0 }.count,
                    "jointCovered": jointCovered,
                    "columnWidths": [44, 96, 128, 160, 214].map { x in
                        (0..<256).filter { y in pixels[(y * 256 + x) * 4 + 3] > 0 }.count
                    }]
        }
    }

    private static func ropeTrailRenderContract() -> [String: Any] {
        let definition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 1,
            "emitter": [["name": "sphererandom"]],
            "renderer": [[
                "name": "ropetrail",
                "length": 1,
                "segments": 4,
                "subdivision": 0,
                "fadealpha": true,
            ]],
        ])
        guard let renderer = definition.renderers.first,
              let plan = SceneParticleRopeTrailPlan(
                renderer: renderer,
                rendererCount: definition.renderers.count,
                maximumParticleCount: 1
              ) else {
            return ["available": false]
        }
        let points: [SIMD2<Float>] = [
            SIMD2(-0.6, -0.6),
            SIMD2(-0.6, -0.2),
            SIMD2(-0.6, 0.2),
            SIMD2(-0.2, 0.2),
            SIMD2(0.2, 0.2),
        ]
        var history = SceneParticleRopeTrailHistory(plan: plan)
        var values: [SceneParticleGPUInstance] = []
        for (index, point) in points.enumerated() {
            values = history.advance(
                by: index == 0 ? 0 : 0.25,
                particles: [SceneParticleRopeTrailParticle(
                    id: 1,
                    position: SIMD3(point.x, point.y, 0),
                    // GPU records expose half the authored particle size. Keep
                    // this raster contract's historical on-screen thickness.
                    size: 0.24,
                    color: SIMD3(repeating: 1),
                    alpha: 1
                )],
                layerAlpha: 1
            )
        }

        let size = 128
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 8,
            height: 32,
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
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else {
            return ["available": false]
        }
        var drop = [UInt8](repeating: 0, count: 8 * 32 * 4)
        for y in 0..<32 {
            for x in 0..<8 {
                let cross = max(0, 1 - abs(Float(x) - 3.5) / 3.5)
                let trail = 1 - Float(y) / 31
                let alpha = UInt8(max(0, min(255, Int(255 * cross * trail))))
                let offset = (y * 8 + x) * 4
                drop[offset] = alpha
                drop[offset + 1] = alpha
                drop[offset + 2] = alpha
                drop[offset + 3] = alpha
            }
        }
        input.replace(
            region: MTLRegionMake2D(0, 0, 8, 32),
            mipmapLevel: 0,
            withBytes: &drop,
            bytesPerRow: 8 * 4
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: values) else {
            return ["available": false]
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return ["available": false]
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
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), SceneParticleOffscreenReadbackHarness.commitAndWait(command) else {
            return ["available": false]
        }

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
        let headAlpha = visible
            .filter { $0 % size > 64 && (44...58).contains($0 / size) }
            .map { Int(pixels[$0 * 4 + 3]) }
            .max() ?? 0
        let tailAlpha = visible
            .filter { (20...32).contains($0 % size) && $0 / size > 85 }
            .map { Int(pixels[$0 * 4 + 3]) }
            .max() ?? 0
        return [
            "available": true,
            "instanceCount": values.count,
            "width": (xs.max() ?? 0) - (xs.min() ?? 0) + 1,
            "height": (ys.max() ?? 0) - (ys.min() ?? 0) + 1,
            "visiblePixels": visible.count,
            "headAlpha": headAlpha,
            "tailAlpha": tailAlpha,
            "horizontalSegments": values.filter {
                abs($0.velocityAndTrail.x) > abs($0.velocityAndTrail.y)
            }.count,
            "verticalSegments": values.filter {
                abs($0.velocityAndTrail.y) > abs($0.velocityAndTrail.x)
            }.count,
        ]
    }

    private static func ropeTrailTransformContract() -> [String: Any] {
        let size = 256
        let tail = SIMD3<Float>(-0.35, -0.2, 0)
        let head = SIMD3<Float>(0.45, 0.3, 0)
        let center = (tail + head) * 0.5
        let displacement = head - tail
        let angle = Float.pi / 6
        let scale = SIMD2<Float>(1.4, 0.6)
        let layerModel = simd_float4x4(columns: (
            SIMD4(cos(angle) * scale.x, sin(angle) * scale.x, 0, 0),
            SIMD4(-sin(angle) * scale.y, cos(angle) * scale.y, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0.1, -0.05, 0, 1)
        ))
        let transformedTail = layerModel * SIMD4(tail, 1)
        let transformedHead = layerModel * SIMD4(head, 1)
        let transformedTailXY = SIMD2(transformedTail.x, transformedTail.y)
        let transformedHeadXY = SIMD2(transformedHead.x, transformedHead.y)
        let transformedDisplacement = transformedHeadXY - transformedTailXY
        let direction = simd_normalize(transformedDisplacement)
        let expectedTail = simd_dot(transformedTailXY, direction)
        let expectedHead = simd_dot(transformedHeadXY, direction)

        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 9,
            height: 33,
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
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else {
            return ["available": false]
        }
        var centerline = [UInt8](repeating: 0, count: 9 * 33 * 4)
        for y in 0..<33 {
            for x in 3...5 {
                let offset = (y * 9 + x) * 4
                centerline[offset] = 255
                centerline[offset + 1] = 255
                centerline[offset + 2] = 255
                centerline[offset + 3] = 255
            }
        }
        input.replace(
            region: MTLRegionMake2D(0, 0, 9, 33),
            mipmapLevel: 0,
            withBytes: &centerline,
            bytesPerRow: 9 * 4
        )
        let segmentSize: Float = 0.08
        let frame = SceneParticleFrameTransform.identity.verticalTrailSlice(
            tailPosition: 0,
            headPosition: 1
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: center,
                size: segmentSize,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1,
                velocity: displacement,
                trailStretch: simd_length(displacement) / segmentSize,
                trailUVRange: SIMD2(0, 1),
                usesTrailDisplacement: true,
                currentFrame: frame
            ),
        ]) else {
            return ["available": false]
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return ["available": false]
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: layerModel,
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), SceneParticleOffscreenReadbackHarness.commitAndWait(command) else {
            return ["available": false]
        }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        let projections = (0..<(size * size)).compactMap { index -> Float? in
            guard pixels[index * 4 + 3] > 64 else { return nil }
            let x = Float(index % size) + 0.5
            let y = Float(index / size) + 0.5
            let ndc = SIMD2(
                x / Float(size) * 2 - 1,
                1 - y / Float(size) * 2
            )
            return simd_dot(ndc, direction)
        }
        return [
            "available": true,
            "expectedTail": min(expectedTail, expectedHead),
            "expectedHead": max(expectedTail, expectedHead),
            "observedTail": projections.min() ?? 0,
            "observedHead": projections.max() ?? 0,
            "visiblePixels": projections.count,
        ]
    }

    private static func ropeTrailAspectContract() -> [String: Any] {
        let width = 320
        let height = 180
        let tail = SIMD3<Float>(-0.55, -0.38, 0)
        let head = SIMD3<Float>(0.55, 0.38, 0)
        let displacement = head - tail
        let pathPixelDirection = simd_normalize(SIMD2(
            displacement.x * Float(width),
            -displacement.y * Float(height)
        ))
        let legacyPerpendicular = simd_normalize(SIMD2(
            -displacement.y * Float(width),
            -displacement.x * Float(height)
        ))

        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let inputWidth = 33
        let inputHeight = 65
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: inputWidth,
            height: inputHeight,
            mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else {
            return ["available": false]
        }
        var crossbar = [UInt8](repeating: 0, count: inputWidth * inputHeight * 4)
        for y in 31...33 {
            for x in 0..<inputWidth {
                let offset = (y * inputWidth + x) * 4
                crossbar[offset] = 255
                crossbar[offset + 1] = 255
                crossbar[offset + 2] = 255
                crossbar[offset + 3] = 255
            }
        }
        input.replace(
            region: MTLRegionMake2D(0, 0, inputWidth, inputHeight),
            mipmapLevel: 0,
            withBytes: &crossbar,
            bytesPerRow: inputWidth * 4
        )
        let segmentSize: Float = 0.42
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: (tail + head) * 0.5,
                size: segmentSize,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1,
                velocity: displacement,
                trailStretch: simd_length(displacement) / segmentSize,
                trailUVRange: SIMD2(0, 1),
                usesTrailDisplacement: true,
                currentFrame: SceneParticleFrameTransform.identity.verticalTrailSlice(
                    tailPosition: 0,
                    headPosition: 1
                )
            ),
        ]) else {
            return ["available": false]
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return ["available": false]
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
                ),
                viewportSize: SIMD2(Float(width), Float(height))
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), SceneParticleOffscreenReadbackHarness.commitAndWait(command) else {
            return ["available": false]
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        let points = (0..<(width * height)).compactMap { index -> SIMD2<Float>? in
            guard pixels[index * 4 + 3] > 64 else { return nil }
            return SIMD2(
                Float(index % width) + 0.5,
                Float(index / width) + 0.5
            )
        }
        guard points.count > 2 else {
            return ["available": true, "visiblePixels": points.count]
        }
        let mean = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let covariance = points.reduce(SIMD3<Float>.zero) { partial, point in
            let delta = point - mean
            return partial + SIMD3(
                delta.x * delta.x,
                delta.x * delta.y,
                delta.y * delta.y
            )
        } / Float(points.count)
        let angle = 0.5 * atan2(
            2 * covariance.y,
            covariance.x - covariance.z
        )
        let crossPixelDirection = SIMD2(cos(angle), sin(angle))
        let discriminant = sqrt(
            (covariance.x - covariance.z) * (covariance.x - covariance.z)
                + 4 * covariance.y * covariance.y
        )
        let majorVariance = (covariance.x + covariance.z + discriminant) * 0.5
        let minorVariance = (covariance.x + covariance.z - discriminant) * 0.5
        return [
            "available": true,
            "visiblePixels": points.count,
            "absoluteDot": abs(simd_dot(
                pathPixelDirection,
                crossPixelDirection
            )),
            "legacyAbsoluteDot": abs(simd_dot(
                pathPixelDirection,
                legacyPerpendicular
            )),
            "varianceRatio": majorVariance / max(minorVariance, 0.0001),
        ]
    }

    private static func authoredRotationBounds(_ value: Any) -> [String: Int] {
        let data = try! JSONSerialization.data(withJSONObject: [
            "initializer": [["name": "rotationrandom", "min": value, "max": value]]
        ])
        let definition = try! SceneParticleDefinitionParser().parse(data: data)
        let angles = definition.initializers[0].minimum!.vectorValue!
        return spriteBounds(currentAspect: 0.25, nextAspect: 0.25, frameMix: 0,
                            rotation: SIMD3(Float(angles[0]), Float(angles[1]), Float(angles[2])),
                            marked: true)
    }

    private static func defaultTrailBounds() -> [String: [[String: Int]]] {
        let plans = [
            "omitted": SceneParticleTrailRenderPlan(length: 0.007, minimumLength: nil, maximumLength: nil)!,
            "explicit": SceneParticleTrailRenderPlan(length: 0.007, minimumLength: 0, maximumLength: 10)!,
            "fixed": SceneParticleTrailRenderPlan(length: 0.007, minimumLength: 1, maximumLength: 1)!
        ]
        return plans.mapValues { plan in
            [100.0, 200.0, 400.0].map { speed in
                trailBounds(velocity: SIMD3(Float(speed), 0, 0),
                            stretch: plan.stretch(for: SIMD3(speed, 0, 0)))
            }
        }
    }

    private static func trailBounds(
        velocity: SIMD3<Float>,
        layerModel: simd_float4x4 = SceneMatrix.identity(),
        rope: Bool = false,
        sizeIsWorldSpace: Bool = false,
        particleSize: Float = 0.2,
        stretch: Float = 4,
        currentAspect: Float = 1,
        nextAspect: Float? = nil,
        frameMix: Float = 0,
        viewProjection: simd_float4x4 = SceneMatrix.identity(),
        basis: SceneParticleOrientationBasis = .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0))
    ) -> [String: Int] {
        let size = 256
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [:] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [:] }
        var white = [UInt8](repeating: 255, count: 4)
        input.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        let instances = SceneParticleMetalInstanceBuffer()
        let values = [SceneParticleGPUInstance(
            position: .zero, size: particleSize, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1,
            velocity: rope ? velocity * 0.12 : velocity, trailStretch: stretch,
            usesTrailDisplacement: rope,
            trailHeadDirection: rope ? velocity * 0.12 : nil,
            trailTailDirection: rope ? velocity * 0.12 : nil,
            trailEndpointSizes: rope ? SIMD2(repeating: particleSize) : nil,
            currentFrameAspect: currentAspect, nextFrameAspect: nextAspect, frameMix: frameMix
        )]
        guard instances.update(device: device, instances: values) else { return [:] }
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
                basis: basis, viewportSize: SIMD2(256, 256), sizeIsWorldSpace: sizeIsWorldSpace
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
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
        var minimumX = size
        var minimumY = size
        var maximumX = -1
        var maximumY = -1
        for y in 0..<size {
            for x in 0..<size where pixels[(y * size + x) * 4 + 3] > 0 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        return [
            "width": maximumX >= minimumX ? maximumX - minimumX + 1 : 0,
            "height": maximumY >= minimumY ? maximumY - minimumY + 1 : 0,
        ]
    }
}
