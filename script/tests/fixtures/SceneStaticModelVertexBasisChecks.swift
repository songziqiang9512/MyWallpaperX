import Foundation
import Metal
import simd

// Uses the parts fixture's real Reader/resources, StaticModels, pipeline and
// shadow preparation. The oracle composes authored Y-up points independently;
// it does not duplicate the production world-frame resolver.
enum SceneStaticModelVertexBasisChecks {
    static let width = 160
    static let height = 128
    static let sourceNormal = simd_normalize(SIMD3<Float>(0, -0.4, 1))
    static let centers = (0..<3).map { SIMD3<Float>(6 + Float($0) * 13, 13, 5.2) }

    static func run(root: URL, device: MTLDevice, queue: MTLCommandQueue) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for renamed in [false, true] {
            let directory = root.appendingPathComponent(renamed ? "basis-renamed" : "basis")
            for mode in ["positive", "negative-x", "negative-y", "parent-mixed", "dynamic-parent", "native"] {
                rows.append(try autoreleasepool {
                    try check(mode: mode, renamed: renamed, root: directory, device: device, queue: queue)
                })
            }
        }
        return rows
    }

    static func check(mode: String, renamed: Bool, root: URL,
                      device: MTLDevice, queue: MTLCommandQueue) throws -> [String: Any] {
        let native = mode == "native", dynamic = mode == "dynamic-parent"
        let parented = mode == "parent-mixed" || dynamic || native
        let id = renamed ? 37 : 2, parentID = renamed ? 91 : 10
        var child = SceneRenderDescriptor.Layer(id: id,
            staticModelPath: renamed ? "models/alternate.mdl" : "models/basis.mdl")
        child.utilityLayer = nil // Ordinary production models have no utility descriptor.
        child.originXYZ = parented ? [2, 3, -4] : [44, 68, -4]
        child.scaleXYZ = mode == "negative-x" ? [-1, 1, 1]
            : mode == "negative-y" ? [1, -1, 1] : [1, 1, 1]
        if mode == "negative-x" { child.originXYZ = [105, 68, -4] }
        child.anglesXYZ = parented ? [0.12, -0.18, 0.1] : [0, 0, 0]
        child.usesPerspective = native
        var parent = SceneRenderDescriptor.Layer(id: parentID, contentKind: "object")
        parent.originXYZ = native ? [42, 44, 0] : [43, 66, 0]
        parent.scaleXYZ = [1.15, 0.85, 1.1]
        parent.anglesXYZ = [0.2, -0.15, 0.24]
        if parented { child.parentID = parentID }
        let layers = parented ? [parent, child] : [child]
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("materials"),
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let passes = try files.map { file -> SceneRenderDescriptor.MaterialPassDescriptor in
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let pass = (object["passes"] as! [[String: Any]])[0]
            var result = SceneRenderDescriptor.MaterialPassDescriptor(
                materialPath: "materials/" + file.lastPathComponent,
                textureSlots: (pass["textures"] as! [String]).map(Optional.some),
                combos: pass["combos"] as! [String: Int], constantShaderValues: [:])
            result.cullMode = pass["cullmode"] as? String
            return result
        }
        var descriptor = SceneRenderDescriptor(lighting: nil, layers: layers,
            renderOrderLayerIDs: [id], materialPasses: passes)
        descriptor.camera = .init(eye: native ? [80, 64, 200] : [0, 0, 0],
            center: native ? [80, 64, 0] : [0, 0, -1], up: [0, 1, 0],
            orthoWidth: native ? nil : 160, orthoHeight: native ? nil : 128,
            fovDegrees: native ? 60 : nil, perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 1000)
        let byID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        let staticFrames = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: byID)
        let target = SceneDynamicTarget.layer(layerID: parentID, field: .angles)
        let animated = SIMD3<Float>(-0.17, 0.26, -0.21)
        let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 2,
            definitions: [.init(target: target, valueType: .vector3,
                authoredValue: .vector3(0.2, -0.15, 0.24))],
            timelineValues: dynamic ? [target: .vector3(Double(animated.x), Double(animated.y), Double(animated.z))] : [:]).snapshot
        let worlds = SceneLayerDynamicWorldFrameResolver.resolve(descriptor: descriptor, byID: byID,
            snapshot: snapshot, staticFrames: staticFrames)
        func authored(_ layer: SceneRenderDescriptor.Layer, angles: SIMD3<Float>? = nil) -> simd_float4x4 {
            SceneMatrix.translation(SIMD3(layer.originXYZ!, fill: 0))
                * SceneMatrix.eulerXYZ(angles ?? SIMD3(layer.anglesXYZ!, fill: 0))
                * SceneMatrix.scale(SIMD3(layer.scaleXYZ!, fill: 1))
        }
        let authorWorld = parented ? authored(parent, angles: dynamic ? animated : nil) * authored(child) : authored(child)
        // Convert final authored world points once. Native world points stay Y-up.
        let expected = native ? authorWorld
            : SceneMatrix.translation(SIMD3(0, 128, 0)) * SceneMatrix.scale(SIMD3(1, -1, 1)) * authorWorld
        let loader = try SceneTextureLoader(root: root, device: device)
        let resources = try ScenePreparedStaticModelResources.prepare(descriptor: descriptor,
            resourceView: .init(root: root), device: device, textureLoader: loader, cancellationCheck: {})
        let renderer = SceneMetalRenderer(device: device, resources: resources)
        renderer.renderDescriptor = descriptor
        let draws = renderer.staticModelDraws(layer: child, worldFrames: worlds, snapshot: snapshot)!
        precondition(draws.count == 3)
        var worldError: Float = 0, normalError: Float = 0
        for draw in draws {
            for point in [SIMD4<Float>(0, 0, 0, 1), SIMD4(6, 13, 5.2, 1), SIMD4(-3, 7, 2.8, 1)] {
                worldError = max(worldError, simd_distance(draw.world * point, expected * point))
            }
            let actualNormal = simd_normalize(SceneStaticModelPipeline.normalMatrix(for: draw.world)! * sourceNormal)
            normalError = max(normalError, simd_distance(actualNormal, expectedNormal(expected)))
        }
        let reference = draws.map { draw in
            SceneMetalRenderer.StaticModelDraw(entry: draw.entry, mesh: draw.mesh, texture: draw.texture,
                textureFrame: draw.textureFrame, sampling: draw.sampling, premultiplied: draw.premultiplied,
                world: expected, material: draw.material, alpha: draw.alpha)
        }
        let camera = SceneParticleCameraFrame(camera: descriptor.camera,
            viewportSize: CGSize(width: width, height: height), dynamicValues: snapshot)
        precondition(camera.resolvesPerspective(for: child) == native)
        let lighting = SceneLightSnapshot(ambient: SIMD3(repeating: 0.1), skylight: .zero,
            directional: [.init(layerID: 8, castsShadow: false,
                directionTowardLight: expectedNormal(expected), color: SIMD3(repeating: 1), intensity: 2)],
            point: [], spot: [], overflowCount: 0)
        let actualPixels = color(renderer: renderer, layer: child, draws: draws, worldFrames: worlds,
            snapshot: snapshot, camera: camera, lighting: lighting, device: device, queue: queue, actual: true)
        let referencePixels = color(renderer: renderer, layer: child, draws: reference, worldFrames: worlds,
            snapshot: snapshot, camera: camera, lighting: lighting, device: device, queue: queue, actual: false)
        let vp = camera.reverseDepthViewProjection(usesPerspective: native)
        let colorMatches = zip(actualPixels, referencePixels).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
        var cullAndMirror = true
        for index in 0..<3 {
            let x0 = Float(2 + index * 13)
            let points = [SIMD3(x0, 4, 1.6), SIMD3(x0 + 8, 4, 1.6), SIMD3(x0 + 8, 22, 8.8)]
            let q = points.map { projected(vp * expected, $0) }
            let signedArea = (q[1].x - q[0].x) * (q[2].y - q[0].y)
                - (q[1].y - q[0].y) * (q[2].x - q[0].x)
            let shouldDraw = index == 2 || (index == 0 ? signedArea > 0 : signedArea < 0)
            let sample = pixel(actualPixels, projected(vp * expected, centers[index]))
            cullAndMirror = cullAndMirror && (shouldDraw ? sample.prefix(3).max()! > 30 : sample.prefix(3).max()! == 0)
            // The reflected local point is outside every positive-Y test part.
            if mode == "positive" {
                let mirror = SIMD3(centers[index].x, -centers[index].y, -centers[index].z)
                cullAndMirror = cullAndMirror && pixel(actualPixels, projected(vp * expected, mirror)).prefix(3).max()! == 0
            }
        }
        var shadowMatches: [Bool] = [], shadowHasGeometry: [Bool] = [], shadowCull: [Bool] = []
        var shadowDepths: [[Float]] = []
        for kind in ["directional", "spot", "point"] {
            let actualDepth = shadows(kind: kind, renderer: renderer, layer: child, draws: draws,
                snapshot: snapshot, camera: camera, expected: expected, device: device, queue: queue)
            let referenceDepth = shadows(kind: kind, renderer: renderer, layer: child, draws: reference,
                snapshot: snapshot, camera: camera, expected: expected, device: device, queue: queue)
            shadowMatches.append(zip(actualDepth, referenceDepth).allSatisfy { abs($0 - $1) < 0.0002 })
            shadowHasGeometry.append(actualDepth.contains { $0 < 0.999 })
            shadowDepths.append(actualDepth)
            // One-sided visibility comes from the authored triangle's geometric
            // light-facing side, independently of the renderer's winding switch.
            let tx = authorWorld * SIMD4<Float>(1, 0, 0, 0)
            let ty = authorWorld * SIMD4<Float>(0, 1, 0.4, 0)
            let faceNormal = simd_cross(SIMD3(tx.x, tx.y, tx.z), SIMD3(ty.x, ty.y, ty.z))
            let middle = expected * SIMD4(centers[1], 1)
            let lightPosition = SIMD3(middle.x, middle.y, middle.z) + SIMD3<Float>(0, 0, 200)
            let expectedVisible = centers.enumerated().map { index, local -> Bool in
                if index == 2 { return true }
                let point = expected * SIMD4(local, 1)
                var toward = kind == "directional" ? SIMD3<Float>(0, 0, 1)
                    : lightPosition - SIMD3(point.x, point.y, point.z)
                if !native { toward.y = -toward.y }
                return simd_dot(faceNormal, toward) * (index == 1 ? -1 : 1) > 0
            }
            shadowCull.append(zip(actualDepth, expectedVisible).allSatisfy { ($0 < 0.999) == $1 })
        }
        let canonical = SceneLayerDynamicWorldFrameResolver.resolve(descriptor: descriptor, byID: byID,
            snapshot: snapshot, staticFrames: staticFrames)
        let unchanged = worlds.allSatisfy { key, value in
            (0..<4).allSatisfy { value[$0] == canonical[key]![$0] }
        }
        return ["variant": renamed ? "renamed" : "original", "mode": mode, "native": native,
            "dynamic": dynamic, "worldError": Double(worldError), "normalError": Double(normalError),
            "canonicalUnchanged": unchanged, "colorMatchesReference": colorMatches,
            "colorCullAndMirror": cullAndMirror, "encoded": renderer.dependencyRuntime.encoded[id] == true,
            "completed": true, "shadowKinds": ["directional", "spot", "point"],
            "shadowMatchesReference": shadowMatches, "shadowHasGeometry": shadowHasGeometry,
            "shadowCullMatchesGeometry": shadowCull, "shadowDepths": shadowDepths]
    }

    static func expectedNormal(_ world: simd_float4x4) -> SIMD3<Float> {
        let x = world * SIMD4<Float>(1, 0, 0, 0), y = world * SIMD4<Float>(0, 1, 0.4, 0)
        let cross = simd_cross(SIMD3(x.x, x.y, x.z), SIMD3(y.x, y.y, y.z))
        return simd_normalize(cross) * (simd_determinant(world) < 0 ? -1 : 1)
    }

    static func projected(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let clip = matrix * SIMD4(point, 1)
        precondition(clip.w.isFinite && clip.w != 0)
        return SIMD3(clip.x, clip.y, clip.z) / clip.w
    }

    static func pixel(_ bytes: [UInt8], _ ndc: SIMD3<Float>) -> [Int] {
        let x = Int((ndc.x + 1) * Float(width) * 0.5)
        let y = Int((1 - ndc.y) * Float(height) * 0.5)
        precondition(x >= 0 && x < width && y >= 0 && y < height)
        let offset = (y * width + x) * 4
        return [Int(bytes[offset + 2]), Int(bytes[offset + 1]), Int(bytes[offset]), Int(bytes[offset + 3])]
    }

    static func target(_ device: MTLDevice) -> MTLTexture {
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        description.storageMode = .shared; description.usage = [.renderTarget, .shaderRead]
        return device.makeTexture(descriptor: description)!
    }

    static func color(renderer: SceneMetalRenderer, layer: SceneRenderDescriptor.Layer,
                      draws: [SceneMetalRenderer.StaticModelDraw], worldFrames: [Int: simd_float4x4],
                      snapshot: SceneDynamicSnapshot, camera: SceneParticleCameraFrame,
                      lighting: SceneLightSnapshot, device: MTLDevice, queue: MTLCommandQueue,
                      actual: Bool) -> [UInt8] {
        let texture = target(device), cb = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: texture,
            clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
        let state = SceneMetalRenderer.StaticModelFrame(commandBuffer: cb)
        var leases: [SceneParticleDepthTargetLease] = []
        if actual {
            _ = renderer.drawStaticModel(layer: layer, state: state, worldFrames: worldFrames,
                frameContext: .init(dynamicValues: snapshot), cameraFrame: camera,
                lighting: lighting, pass: pass, commandBuffer: cb, leases: &leases)
        } else {
            guard case let .acquired(depth) = renderer.staticModelDepthTargetPool.acquire(
                device: device, width: width, height: height, on: cb)
            else { preconditionFailure("reference depth") }
            leases.append(depth)
            for (index, draw) in draws.enumerated() {
                let encoder = pass.encoder(depthTexture: depth.texture, clearsDepth: index == 0, clearDepth: 0)!
                precondition(renderer.staticModelResources.pipeline!.draw(mesh: draw.entry.mesh,
                    texture: draw.texture, colorTextureIsPremultiplied: draw.premultiplied,
                    emissiveMask: nil, emissiveMaskTextureFrame: nil, emissiveMaskSampling: nil,
                    modelMatrix: draw.world,
                    viewProjection: camera.reverseDepthViewProjection(usesPerspective: layer.usesPerspective == true),
                    cameraPosition: camera.perspectiveEyePosition, textureFrame: draw.textureFrame,
                    sampling: draw.sampling, layerAlpha: draw.alpha, material: draw.material,
                    lighting: lighting, writesDepth: draw.entry.writesDepth, commandBuffer: cb, encoder: encoder))
            }
        }
        precondition(pass.finishEnsuringClear())
        leases.forEach { $0.arm(on: cb) }; state.arm(on: cb)
        cb.commit(); cb.waitUntilCompleted()
        precondition(cb.status == .completed && cb.error == nil)
        var result = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&result, bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return result
    }

    static func shadows(kind: String, renderer: SceneMetalRenderer, layer: SceneRenderDescriptor.Layer,
                        draws: [SceneMetalRenderer.StaticModelDraw], snapshot: SceneDynamicSnapshot,
                        camera: SceneParticleCameraFrame, expected: simd_float4x4,
                        device: MTLDevice, queue: MTLCommandQueue) -> [Float] {
        let center4 = expected * SIMD4(centers[1], 1)
        let center = SIMD3(center4.x, center4.y, center4.z)
        let lightPosition = center + SIMD3<Float>(0, 0, 200)
        let light: SceneLightSnapshot.ShadowLight
        if kind == "directional" {
            light = .directional(.init(layerID: 7, castsShadow: true,
                directionTowardLight: SIMD3(0, 0, 1), color: SIMD3(repeating: 1), intensity: 1))
        } else if kind == "spot" {
            light = .spot(.init(layerID: 7, castsShadow: true, position: lightPosition,
                directionFromLight: SIMD3(0, 0, -1), color: SIMD3(repeating: 1), intensity: 1,
                radius: 500, innerConeCosine: 0.9, outerConeCosine: cos(.pi / 4), outerConeDegrees: 45))
        } else {
            light = .point(.init(layerID: 7, castsShadow: true, position: lightPosition,
                color: SIMD3(repeating: 1), intensity: 1, radius: 500))
        }
        let cb = queue.makeCommandBuffer()!, texture = target(device)
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: texture,
            clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
        let state = SceneMetalRenderer.StaticModelFrame(commandBuffer: cb)
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .bgra8Unorm,
            residentByteBudget: 64 * 1024 * 1024)
        var leases: [SceneParticleDepthTargetLease] = []
        renderer.prepareModelShadow(state: state, candidates: [layer.id: draws], lights: [light],
            orderedLayers: [layer], visible: [layer.id], batches: [:], particlePipeline: nil,
            mainPass: pass, groups: nil, pool: pool, commandBuffer: cb, leases: &leases,
            mandatoryCapacity: { true }, recordsEvidence: false, cameraFrame: camera)
        precondition(state.shadows.count == 1)
        let shadow = state.shadows[0], map = shadow.texture, blit = cb.makeBlitCommandEncoder()!
        let buffers = centers.map { local -> MTLBuffer in
            let q = expected * SIMD4(local, 1), point = SIMD3(q.x, q.y, q.z)
            let clip: SIMD3<Float>, face: Int
            switch shadow.projection {
            case .directional(let projection):
                let value = projection.worldToClip * SIMD4(point, 1)
                clip = SIMD3(value.x, value.y, value.z); face = 0
            case .spot(let projection):
                let value = projection.worldToLight * SIMD4(point - projection.position, 0)
                clip = SIMD3(value.x / (value.z * projection.tanHalfAngle),
                    value.y / (value.z * projection.tanHalfAngle), 0); face = 0
            case .point(let projection):
                face = 5
                let value = ScenePointShadowProjection.worldToFaces[face] * SIMD4(point - projection.position, 0)
                clip = SIMD3(value.x / value.z, value.y / value.z, 0)
            }
            let viewport = shadow.projection.viewport(face: face, width: map.width, height: map.height)
            let x = Int(viewport.originX + (Double(clip.x) + 1) * viewport.width * 0.5)
            let y = Int(viewport.originY + (1 - Double(clip.y)) * viewport.height * 0.5)
            precondition(x >= 0 && x < map.width && y >= 0 && y < map.height)
            let buffer = device.makeBuffer(length: 256, options: .storageModeShared)!
            blit.copy(from: map, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: x, y: y, z: 0),
                sourceSize: .init(width: 1, height: 1, depth: 1), to: buffer, destinationOffset: 0,
                destinationBytesPerRow: 256, destinationBytesPerImage: 256)
            return buffer
        }
        blit.endEncoding(); precondition(pass.finishEnsuringClear())
        leases.forEach { $0.arm(on: cb) }; state.arm(on: cb)
        cb.commit(); cb.waitUntilCompleted()
        precondition(cb.status == .completed && cb.error == nil)
        return buffers.map { $0.contents().bindMemory(to: Float.self, capacity: 1).pointee }
    }
}
