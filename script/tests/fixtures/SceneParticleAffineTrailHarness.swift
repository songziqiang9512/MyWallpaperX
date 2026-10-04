import Foundation
import Metal
import simd

/// Self-authored white-on-black inputs exercising the production particle
/// pipeline. Readback publishes every covered pixel as row runs; the Python
/// test owns an independent affine-polygon oracle. The extra vertex probe only
/// redirects production output publication so subpixel cards remain observable;
/// no position/tangent calculation is replaced and no stock asset is read.
enum SceneParticleAffineTrailHarness {
    struct Case: Decodable {
        let name: String
        let kind: String
        let scale: [Float]
        let velocity: [Float]
        let angle: Float
        let size: Float
        let stretch: Float
        let tiltX: Float?
        let worldSize: Bool?
        let vertexOnly: Bool?
        let orientation: String?
        let orientationAxis: [Float]?
    }

    enum Failure: Error {
        case unavailable(String)
        case malformedCase(String)
        case encodeFailed(String)
        case completionFailed(String)
    }

    static let extent = 512
    // Tilted valid cards extend outside +/-10 in world Z. Keep this geometry
    // test's camera from clipping them before the coverage oracle can observe
    // the complete quad; depth behavior is not the property under test.
    static let depthHalfExtent: Float = 1000

    static func run(casesURL: URL) throws -> [String: Any] {
        let cases = try JSONDecoder().decode(
            [Case].self, from: Data(contentsOf: casesURL)
        )
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue() else {
            throw Failure.unavailable("Metal device, pipeline, or queue")
        }
        let vertexProbe = try makeVertexProbe(device: device)
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = .shaderRead
        guard let source = device.makeTexture(descriptor: sourceDescriptor) else {
            throw Failure.unavailable("self-authored white texture")
        }
        var white: [UInt8] = [255, 255, 255, 255]
        source.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        let camera = SceneParticleCameraFrame(
            camera: .init(
                eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
                orthoWidth: Float(extent), orthoHeight: Float(extent),
                fovDegrees: nil, perspectiveOverrideFOVDegrees: nil,
                nearZ: 0.1, farZ: 1000
            ),
            viewportSize: CGSize(width: CGFloat(extent), height: CGFloat(extent))
        )
        var rows: [[String: Any]] = []
        for value in cases {
            rows.append(try render(
                value, device: device, queue: queue, pipeline: pipeline,
                source: source, camera: camera, vertexProbe: vertexProbe
            ))
        }
        return ["extent": extent, "alphaThreshold": 127,
                "clipDepthSpan": depthHalfExtent * 2, "cases": rows]
    }

    private static func render(
        _ value: Case,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneParticleMetalPipeline,
        source: MTLTexture,
        camera: SceneParticleCameraFrame,
        vertexProbe: MTLRenderPipelineState
    ) throws -> [String: Any] {
        guard value.scale.count == 3, value.velocity.count == 3,
              value.scale.allSatisfy(\.isFinite),
              value.velocity.allSatisfy(\.isFinite),
              value.angle.isFinite, value.size.isFinite,
              value.stretch.isFinite else {
            throw Failure.malformedCase(value.name)
        }
        let scale = SIMD3(value.scale[0], value.scale[1], value.scale[2])
        let velocity = SIMD3(value.velocity[0], value.velocity[1], value.velocity[2])
        let magnitude = simd_length(velocity)
        guard magnitude > 0 else { throw Failure.malformedCase(value.name) }
        let direction = velocity / magnitude
        // Match the public Scene Y-down layer-frame convention: reflect the
        // authored layer rotation and local particle Y exactly once.
        let center: Float = value.vertexOnly == true ? 0 : Float(extent) / 2
        let worldFrame = SceneMatrix.translation(SIMD3(center, center, 0))
            * SceneMatrix.rotationX(value.tiltX ?? 0)
            * SceneMatrix.rotationZ(-value.angle) * SceneMatrix.scale(scale)
        let model = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: worldFrame, parallaxOffset: .zero
        )
        let instances = try makeInstances(value, direction: direction)
        let instancesAreFinite = instances.allSatisfy(\.isFinite)
        guard instancesAreFinite, !instances.isEmpty else {
            throw Failure.malformedCase(value.name)
        }
        let buffer = SceneParticleMetalInstanceBuffer()
        guard buffer.update(device: device, instances: instances),
              let command = queue.makeCommandBuffer() else {
            throw Failure.unavailable("instance buffer or command buffer")
        }
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: extent, height: extent, mipmapped: false
        )
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = .renderTarget
        guard let target = device.makeTexture(descriptor: targetDescriptor) else {
            throw Failure.unavailable("readback target")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw Failure.unavailable("render encoder")
        }
        let projection = value.vertexOnly == true ? SceneMatrix.identity() : SceneMatrix.ortho(
            left: 0, right: Float(extent), bottom: Float(extent), top: 0,
            near: -depthHalfExtent, far: depthHalfExtent
        )
        let orientation = SceneParticleOrientation(authoredValue: value.orientation)
        let axis: SIMD3<Float>
        if let components = value.orientationAxis {
            guard components.count == 3, components.allSatisfy(\.isFinite) else {
                throw Failure.malformedCase(value.name)
            }
            axis = SIMD3(components[0], components[1], components[2])
        } else {
            axis = SIMD3(0, 0, 1)
        }
        let basis = camera.basis(
            for: orientation, layerModel: model, orientationAxis: axis
        )
        let uniforms = SceneParticleLayerUniforms(
            viewProjection: projection, layerModel: model, basis: basis,
            viewportSize: SIMD2(repeating: Float(extent)),
            sizeIsWorldSpace: value.worldSize == true,
            viewBasis: camera.basis(for: .screen)
        )
        let encoded = pipeline.draw(
            texture: source, instances: buffer, uniforms: uniforms,
            renderState: .init(blendMode: .translucent, cullMode: .none),
            colorSampling: .init(texFlags: 3),
            encoder: encoder
        )
        encoder.endEncoding()
        guard encoded, buffer.markSubmitted(on: command) else {
            throw Failure.encodeFailed(value.name)
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw command.error ?? Failure.completionFailed(value.name)
        }
        var pixels = [UInt8](repeating: 0, count: extent * extent * 4)
        target.getBytes(
            &pixels, bytesPerRow: extent * 4,
            from: MTLRegionMake2D(0, 0, extent, extent), mipmapLevel: 0
        )
        var result = summarize(pixels)
        result["name"] = value.name
        result["encoded"] = encoded
        result["gpuCompleted"] = true
        result["instancesFinite"] = instancesAreFinite
        result["instanceCount"] = instances.count
        result["vertexOnly"] = value.vertexOnly == true
        result["probePositions"] = try captureVertices(
            instances[0], uniforms: uniforms, device: device,
            queue: queue, pipeline: vertexProbe
        )
        return result
    }

    private static func makeVertexProbe(device: MTLDevice) throws -> MTLRenderPipelineState {
        // The existing FixedGeometryHarness uses the same bounded publication
        // probe. Compile the production body unchanged; only its entry return
        // and final result publication are redirected into a shared buffer.
        let source = sceneParticleShaderSource
            .replacingOccurrences(
                of: "vertex Varyings sceneParticleVert",
                with: "vertex void sceneParticleVert"
            )
            .replacingOccurrences(
                of: "constant LayerUniforms &uniforms [[buffer(2)]])",
                with: "constant LayerUniforms &uniforms [[buffer(2)]], device float4 *probe [[buffer(3)]])"
            )
            .replacingOccurrences(
                of: "    return out;",
                with: "    probe[vertexID] = out.position;\n    return;"
            )
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "sceneParticleVert")
        descriptor.isRasterizationEnabled = false
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func captureVertices(
        _ particle: SceneParticleGPUInstance,
        uniforms: SceneParticleLayerUniforms,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: MTLRenderPipelineState
    ) throws -> [[Float]] {
        guard let command = queue.makeCommandBuffer(),
              let output = device.makeBuffer(length: 4 * 16, options: .storageModeShared) else {
            throw Failure.unavailable("vertex probe buffer")
        }
        let pass = MTLRenderPassDescriptor()
        pass.renderTargetWidth = 1
        pass.renderTargetHeight = 1
        pass.defaultRasterSampleCount = 1
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw Failure.unavailable("vertex probe encoder")
        }
        var quad: [SIMD4<Float>] = [
            SIMD4(-0.5, -0.5, 0, 1), SIMD4(0.5, -0.5, 1, 1),
            SIMD4(-0.5, 0.5, 0, 0), SIMD4(0.5, 0.5, 1, 0)
        ]
        var instance = particle
        var uniformCopy = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&quad, length: quad.count * 16, index: 0)
        encoder.setVertexBytes(&instance, length: MemoryLayout<SceneParticleGPUInstance>.stride, index: 1)
        encoder.setVertexBytes(&uniformCopy, length: MemoryLayout<SceneParticleLayerUniforms>.stride, index: 2)
        encoder.setVertexBuffer(output, offset: 0, index: 3)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw command.error ?? Failure.completionFailed("vertex probe")
        }
        let pointer = output.contents().bindMemory(to: Float.self, capacity: 16)
        return (0..<4).map {
            Array(UnsafeBufferPointer(start: pointer + $0 * 4, count: 4))
        }
    }

    private static func makeInstances(
        _ value: Case, direction: SIMD3<Float>
    ) throws -> [SceneParticleGPUInstance] {
        switch value.kind {
        case "trail":
            // The plan's fixed equal bounds preserve orientation without
            // relying on a velocity threshold or elapsed simulation time.
            guard let plan = SceneParticleTrailRenderPlan(
                length: 0, minimumLength: Double(value.stretch),
                maximumLength: Double(value.stretch)
            ) else { throw Failure.malformedCase(value.name) }
            let velocity = SIMD3<Double>(
                Double(value.velocity[0]), Double(value.velocity[1]),
                Double(value.velocity[2])
            )
            return [SceneParticleGPUInstance(
                position: .zero, size: value.size, rotation: .zero,
                color: SIMD3(repeating: 1), alpha: 1,
                velocity: plan.direction(for: velocity),
                trailStretch: plan.stretch(for: velocity),
                currentFrame: .identity.orientedForTrail(true)
            )]
        case "sprite":
            return [SceneParticleGPUInstance(
                position: .zero, size: value.size, rotation: .zero,
                color: SIMD3(repeating: 1), alpha: 1
            )]
        case "rope":
            let definition = SceneParticleDefinitionParser().parse(root: [
                "material": "self-authored/white.json",
                "renderer": [["name": "rope", "subdivision": 0]]
            ])
            guard let plan = SceneParticleRopePlan(
                renderer: definition.renderers[0], rendererCount: 1,
                maximumParticleCount: 2
            ) else { throw Failure.malformedCase(value.name) }
            let halfLength = Double(value.size * 0.5 * value.stretch * 0.5)
            let delta = SIMD3<Double>(
                Double(direction.x), Double(direction.y), Double(direction.z)
            ) * halfLength
            let particles = [particle(0, -delta, value.size), particle(1, delta, value.size)]
            return plan.instances(particles: particles, layerAlpha: 1)
        default:
            throw Failure.malformedCase(value.name)
        }
    }

    private static func particle(
        _ id: UInt64, _ position: SIMD3<Double>, _ size: Float
    ) -> SceneParticleState {
        SceneParticleState(
            id: id, position: position, velocity: .zero,
            color: SIMD3(repeating: 1), alpha: 1, size: Double(size),
            rotation: .zero, angularVelocity: .zero, age: 0, lifetime: 100,
            initialColor: SIMD3(repeating: 1), initialAlpha: 1,
            initialSize: Double(size)
        )
    }

    private static func summarize(_ pixels: [UInt8]) -> [String: Any] {
        var runs: [[Int]] = []
        var visible = 0
        var minimum = [255, 255, 255, 255]
        var maximum = [0, 0, 0, 0]
        var minX = extent, minY = extent, maxX = -1, maxY = -1
        for y in 0..<extent {
            var runStart: Int?
            for x in 0..<extent {
                let index = (y * extent + x) * 4
                let covered = pixels[index + 3] > 127
                if covered {
                    if runStart == nil { runStart = x }
                    visible += 1
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                    for channel in 0..<4 {
                        minimum[channel] = min(minimum[channel], Int(pixels[index + channel]))
                        maximum[channel] = max(maximum[channel], Int(pixels[index + channel]))
                    }
                } else if let start = runStart {
                    runs.append([y, start, x - 1])
                    runStart = nil
                }
            }
            if let start = runStart { runs.append([y, start, extent - 1]) }
        }
        return [
            "coveredRuns": runs, "visiblePixels": visible,
            "bounds": visible == 0 ? [] : [minX, minY, maxX, maxY],
            "coveredMinimumBGRA": visible == 0 ? [] : minimum,
            "coveredMaximumBGRA": visible == 0 ? [] : maximum
        ]
    }
}
