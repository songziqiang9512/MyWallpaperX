extension Harness {
    private static func refractionBasis(
        rotation: SIMD3<Float> = .zero,
        basis: SceneParticleOrientationBasis = .init(right: SIMD3(1,0,0), up: SIMD3(0,1,0)),
        viewBasis: SceneParticleOrientationBasis = .init(right: SIMD3(1,0,0), up: SIMD3(0,1,0)),
        particleSize: Float = 2,
        aspect: Float = 1,
        model: simd_float4x4 = SceneMatrix.identity(),
        projection: simd_float4x4 = SceneMatrix.identity(),
        position: SIMD3<Float> = SIMD3(0,0,0.5),
        trailVelocity: SIMD3<Float>? = nil,
        joinDirection: SIMD3<Float>? = nil
    ) -> [Float] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let source = sceneParticleShaderSource + """
        fragment float4 readRefractionBasis(Varyings in [[stage_in]]) {
            return float4(in.screenTangentX, in.screenTangentY);
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil) else { return [] }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "sceneParticleVert")
        descriptor.fragmentFunction = library.makeFunction(name: "readRefractionBasis")
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return [] }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
            width: 32, height: 32, mipmapped: false)
        td.usage = .renderTarget; td.storageMode = .shared
        guard let target = device.makeTexture(descriptor: td) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(99,99,99,99)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        encoder.setRenderPipelineState(pipeline)
        var quad: [SIMD4<Float>] = [SIMD4(-0.5,-0.5,0,1), SIMD4(0.5,-0.5,1,1),
                                  SIMD4(-0.5,0.5,0,0), SIMD4(0.5,0.5,1,0)]
        var instance = SceneParticleGPUInstance(position: position, size: particleSize,
            rotation: rotation, color: SIMD3(repeating: 1), alpha: 1,
            velocity: trailVelocity ?? .zero,
            trailStretch: trailVelocity == nil ? nil : 2,
            usesTrailDisplacement: trailVelocity != nil,
            trailHeadDirection: joinDirection, trailTailDirection: joinDirection,
            trailEndpointSizes: joinDirection == nil ? nil : SIMD2(repeating: particleSize),
            currentFrameAspect: aspect)
        var uniforms = SceneParticleLayerUniforms(viewProjection: projection, layerModel: model,
            basis: basis, viewportSize: SIMD2(32,32), viewBasis: viewBasis)
        encoder.setVertexBytes(&quad, length: quad.count * 16, index: 0)
        encoder.setVertexBytes(&instance, length: MemoryLayout<SceneParticleGPUInstance>.stride, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneParticleLayerUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return [] }
        var pixels = [Float](repeating: 0, count: 32 * 32 * 4)
        target.getBytes(&pixels, bytesPerRow: 32 * 16, from: MTLRegionMake2D(0,0,32,32), mipmapLevel: 0)
        // Tangents are constant per Sprite. Select a covered pixel, allowing
        // the camera/depth cases to move the card without coupling the oracle
        // to a particular raster sample.
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] != 99 {
            return Array(pixels[index..<index+4])
        }
        return [99,99,99,99]
    }

    private static func refractionBasisCases() -> [[Float]] {
        let tilted = SceneParticleOrientationBasis(
            right: SIMD3(sqrt(0.5),0,-sqrt(0.5)), up: SIMD3(0,1,0))
        let turned = SceneParticleOrientationBasis(right: SIMD3(0,1,0), up: SIMD3(-1,0,0))
        let mixed = SIMD3<Float>(0.2,-0.4,0.7)
        let camera = SceneParticleCameraFrame(camera: .init(
            eye: [3,2,5], center: [0,0,0], up: [0,1,0],
            orthoWidth: nil, orthoHeight: nil, fovDegrees: 50,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 100),
            viewportSize: CGSize(width: 512,height: 384))
        let canvas = SceneParticleCameraFrame(camera: .init(
            eye: [0,0,0], center: [0,0,-1], up: [0,1,0],
            orthoWidth: 1920, orthoHeight: 1080, fovDegrees: nil,
            perspectiveOverrideFOVDegrees: 50, nearZ: 0.01, farZ: 10000),
            viewportSize: CGSize(width: 512,height: 384))
        let cameraBasis = camera.basis(for: .screen)
        return [
            refractionBasis(),
            refractionBasis(rotation: SIMD3(0,0,Float.pi/2)),
            refractionBasis(rotation: SIMD3(0,0,-Float.pi/2)),
            refractionBasis(rotation: mixed),
            refractionBasis(rotation: SIMD3(Float.pi/4,0,0), basis: tilted),
            refractionBasis(rotation: SIMD3(Float.pi/4,0,0), basis: tilted, viewBasis: tilted),
            refractionBasis(rotation: mixed, viewBasis: tilted),
            refractionBasis(rotation: mixed, basis: turned),
            refractionBasis(rotation: mixed, particleSize: 3, aspect: 0.25,
                model: SceneMatrix.scale(SIMD3(2,3,1))),
            refractionBasis(rotation: mixed, projection: SceneMatrix.perspectiveRHMetal(
                fovYRadians: 1, aspect: 1.5, near: 0.01, far: 100), position: SIMD3(0,0,-5)),
            refractionBasis(rotation: mixed, projection: SceneMatrix.perspectiveRHMetal(
                fovYRadians: 1, aspect: 1.5, near: 0.01, far: 100), position: SIMD3(1,0,-8)),
            refractionBasis(rotation: mixed, basis: cameraBasis, viewBasis: cameraBasis,
                projection: camera.perspectiveViewProjection, position: .zero),
            refractionBasis(rotation: mixed, basis: canvas.basis(for: .screen),
                viewBasis: canvas.basis(for: .screen), particleSize: 200,
                projection: canvas.perspectiveViewProjection, position: SIMD3(960,540,0)),
        ]
    }

    private static func refractionTrailBasisCases() -> [[Float]] {
        [
            refractionBasis(trailVelocity: SIMD3(1,0,0)),
            refractionBasis(model: SceneMatrix.scale(SIMD3(-1,2,1)), trailVelocity: SIMD3(1,0,0)),
            refractionBasis(trailVelocity: SIMD3(1,0,0), joinDirection: SIMD3(0,1,0)),
            refractionBasis(trailVelocity: .zero),
            refractionBasis(particleSize: 0, trailVelocity: SIMD3(1,0,0)),
            refractionBasis(trailVelocity: SIMD3(1,0,0), joinDirection: SIMD3(-1,0,0)),
            refractionBasis(particleSize: 0.0000001, trailVelocity: SIMD3(1,0,0)),
        ]
    }

    private static func refractionContractTest() -> [String: Any] {
        let neutral = refractedCenter(normalX: 128, amount: 0.25)
        let shifted = refractedCenter(normalX: 255, amount: 0.25)
        let trailNeutral = refractedCenter(
            normalX: 128,
            normalY: 128,
            amount: 0.25,
            trailVelocity: SIMD3(1, 0, 0),
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let trailAlong = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(1, 0, 0),
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let trailAcross = refractedCenter(
            normalX: 255,
            normalY: 128,
            amount: 0.25,
            trailVelocity: SIMD3(1, 0, 0),
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let magnitudeNeutral = refractedCenter(
            normalX: 128,
            normalY: 128,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 2,
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let fullSpanShortStretch = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 2,
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let fullSpanLongStretch = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 8,
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let halfSpanLongStretch = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 8,
            trailUVRange: SIMD2(0.25, 0.75),
            usesTrailDisplacement: true
        )
        return [
            "neutral": neutral,
            "shifted": shifted,
            "maskedOut": refractedCenter(normalX: 255, amount: 0.25, normalMask: 0),
            "halfMask": refractedCenter(normalX: 255, amount: 0.25, normalMask: 128),
            "halfAlpha": refractedCenter(normalX: 255, amount: 0.25, particleAlpha: 0.5),
            "halfMaskHalfAlpha": refractedCenter(normalX: 255, amount: 0.25,
                normalMask: 128, particleAlpha: 0.5),
            "zeroAlpha": refractedCenter(normalX: 255, amount: 0.25, particleAlpha: 0),
            "halfAlbedo": refractedCenter(normalX: 255, amount: 0.25, albedoAlpha: 128),
            "rotatedShiftedX": refractedCenter(normalX: 255, amount: 0.25,
                rotation: SIMD3(0, 0, Float.pi / 2)),
            "reverseRotatedShiftedX": refractedCenter(normalX: 255, amount: 0.25,
                rotation: SIMD3(0, 0, -Float.pi / 2)),
            "tallShiftedX": refractedCenter(normalX: 255, amount: 0.25, spriteAspect: 0.25),
            "squareShiftedY": refractedCenter(normalX: 128, normalY: 255, amount: 0.1),
            "tallShiftedY": refractedCenter(normalX: 128, normalY: 255, amount: 0.1, spriteAspect: 0.25),
            "trailNeutral": trailNeutral,
            "trailAlong": trailAlong,
            "trailAcross": trailAcross,
            "magnitudeNeutral": magnitudeNeutral,
            "fullSpanShortStretch": fullSpanShortStretch,
            "fullSpanLongStretch": fullSpanLongStretch,
            "halfSpanLongStretch": halfSpanLongStretch,
        ]
    }

    private static func refractedCenter(
        normalX: UInt8,
        normalY: UInt8 = 128,
        amount: Float,
        trailVelocity: SIMD3<Float>? = nil,
        trailStretch: Float = 2,
        trailUVRange: SIMD2<Float>? = nil,
        usesTrailDisplacement: Bool = false,
        spriteAspect: Float = 1,
        rotation: SIMD3<Float> = .zero,
        normalMask: UInt8 = 255,
        particleAlpha: Float = 1,
        albedoAlpha: UInt8 = 255
    ) -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        targetDescriptor.storageMode = .shared
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: targetDescriptor),
              let color = device.makeTexture(descriptor: inputDescriptor),
              let normal = device.makeTexture(descriptor: inputDescriptor) else { return [] }
        var background = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                background[offset] = UInt8(20 + x * 20)
                background[offset + 1] = UInt8(30 + y * 10)
                background[offset + 2] = 40
                background[offset + 3] = 255
            }
        }
        target.replace(
            region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
            withBytes: &background, bytesPerRow: size * 4
        )
        var white: [UInt8] = [255, 255, 255, albedoAlpha]
        var packedNormal: [UInt8] = [normalMask, normalY, 0, normalX]
        color.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        normal.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &packedNormal, bytesPerRow: 4
        )
        guard let captured = pipeline.snapshot(target: target, commandBuffer: command) else {
            return []
        }
        let instances = SceneParticleMetalInstanceBuffer()
        let instance = SceneParticleGPUInstance(
            position: .zero,
            size: 2,
            rotation: rotation,
            color: SIMD3(repeating: 1),
            alpha: particleAlpha,
            velocity: trailVelocity ?? .zero,
            trailStretch: trailVelocity == nil ? nil : trailStretch,
            trailUVRange: trailUVRange,
            usesTrailDisplacement: usesTrailDisplacement,
            currentFrameAspect: spriteAspect
        )
        guard instances.update(device: device, instances: [instance]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        pipeline.drawRefraction(
            texture: color,
            binding: SceneParticleRefractionBinding(
                normalTexture: normal,
                amount: amount,
                overbright: 1,
                colorEncoding: .rgba,
                normalUsesParticleFrames: false,
                normalUVScale: SIMD2(repeating: 1),
                normalSampling: .directImageFallback,
                normalFormat: .rgba8888
            ),
            background: captured,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.translucent),
            colorUVScale: SIMD2(repeating: 1),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        instances.markSubmitted(on: command)
        guard SceneParticleOffscreenReadbackHarness.commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        target.getBytes(
            &pixel, bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1), mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func samplerPixels() -> [String: Any] {
        [
            "clamp": sampledCenter(
                sampling: SceneParticleTextureSampling(texFlags: 2)
            ),
            "repeat": sampledCenter(
                sampling: SceneParticleTextureSampling(texFlags: 0)
            ),
        ]
    }

    private static func mipSamplerPixels() -> [String: Any] {
        [
            "linear": sampledMipCenter(
                sampling: SceneParticleTextureSampling(texFlags: 2),
                mipmapped: true
            ),
            "nearest": sampledMipCenter(
                sampling: SceneParticleTextureSampling(texFlags: 3),
                mipmapped: true
            ),
            "singleLevel": sampledMipCenter(
                sampling: SceneParticleTextureSampling(texFlags: 2),
                mipmapped: false
            ),
        ]
    }

    private static func sampledMipCenter(
        sampling: SceneParticleTextureSampling,
        mipmapped: Bool
    ) -> [Int] {
        let outputSize = 64
        let inputSize = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: inputSize,
            height: inputSize,
            mipmapped: mipmapped
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: outputSize,
            height: outputSize,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        for level in 0..<input.mipmapLevelCount {
            let width = max(input.width >> level, 1)
            let height = max(input.height >> level, 1)
            let color: [UInt8] = mipmapped
                ? (level == 0 ? [255, 0, 0, 255] : [0, 255, 0, 255])
                : [0, 0, 255, 255]
            var texels = [UInt8]()
            texels.reserveCapacity(width * height * 4)
            for _ in 0..<(width * height) {
                texels.append(contentsOf: color)
            }
            input.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: level,
                withBytes: &texels,
                bytesPerRow: width * 4
            )
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: .zero,
                // Preserve the intended four-pixel minification footprint
                // after the authored-size to GPU-half-size conversion.
                size: 0.125,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1
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
            renderState: particleState(.translucent),
            colorSampling: sampling,
            encoder: encoder
        )
        encoder.endEncoding()
        instances.markSubmitted(on: command)
        guard SceneParticleOffscreenReadbackHarness.commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: outputSize * 4,
            from: MTLRegionMake2D(outputSize / 2, outputSize / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func sampledCenter(
        sampling: SceneParticleTextureSampling
    ) -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false
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
        var texels: [UInt8] = [
            0, 255, 0, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 255, 0, 0, 255,
        ]
        input.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: &texels,
            bytesPerRow: 8
        )
        let frame = SceneParticleFrameTransform(
            origin: SIMD2(0, 1),
            xAxis: SIMD2(1, 0),
            yAxis: SIMD2(0, 1)
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: .zero,
                size: 2,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1,
                currentFrame: frame
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
            renderState: particleState(.translucent),
            colorSampling: sampling,
            encoder: encoder
        )
        encoder.endEncoding()
        instances.markSubmitted(on: command)
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
}
