import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    /// Executes the production root/child instance builders with own assets.
    /// A real device prepares the resources; this mode submits no GPU work.
    static func syntheticTrailDirection() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-trail-direction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        let cases: [(String, String, String?, String)] = [
            ("curve", "10 300 0", "0 -150 0", "spritetrail"),
            ("slow-y", "0 1e-12 0", nil, "spritetrail"),
            ("zero", "0 0 0", nil, "spritetrail"),
            ("large", "1e38 -1e38 1e38", nil, "spritetrail"),
            ("ordinary", "0 2 0", nil, "sprite"),
        ]
        var layers: [SceneRenderDescriptor.Layer] = []
        for (index, item) in cases.enumerated() {
            let (name, velocity, gravity, renderer) = item
            let childPath = "particles/\(name)-child.json"
            var authored: [String: Any] = [
                "material": "materials/shared.json", "maxcount": 1, "flags": 0,
                "emitter": [["name": "boxrandom", "rate": 0, "instantaneous": 1,
                             "distancemin": "0 0 0", "distancemax": "0 0 0"]],
                "initializer": [["name": "lifetimerandom", "min": 10, "max": 10],
                                ["name": "sizerandom", "min": 8, "max": 8],
                                ["name": "velocityrandom", "min": velocity, "max": velocity]],
                "operator": gravity.map { [["name": "movement", "flags": 0,
                                             "gravity": $0, "drag": 0] as [String: Any]] } ?? [],
                "renderer": [["name": renderer, "length": 0.05,
                              "minlength": 0.2, "maxlength": 10]],
            ]
            try writeJSON(authored, to: directory.appendingPathComponent(childPath))
            authored["children"] = [["name": childPath, "type": "static"]]
            let rootPath = "particles/\(name)-root.json"
            try writeJSON(authored, to: directory.appendingPathComponent(rootPath))
            layers.append(layer(101 + index, rootPath))
        }
        let descriptor = SceneRenderDescriptor(layers: layers,
            renderOrderLayerIDs: layers.map(\.id), materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive")])
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
        var batches: [SceneParticleDrawBatch] = []
        func advance(_ steps: Int) {
            for _ in 0..<steps { batches = runtime.advance(by: 1.0 / 60.0) }
        }
        func observation() -> [String: Any] {
            let snapshot = runtime.frameSnapshot()
            var output: [String: Any] = [:]
            for (index, item) in cases.enumerated() {
                let (name, _, _, _) = item
                let states = snapshot.layers[index]
                for (kind, particle) in [
                    ("root", states.root?.simulatorFrame.particles.first),
                    ("child", states.child?.systems.first?.simulatorFrame.particles.first),
                ] {
                    guard let particle, let batch = batches.first(where: {
                        $0.layerID == 101 + index && $0.particlePath == "particles/\(name)-\(kind).json"
                    }), batch.instances.count == 1, let instance = batch.instances.first else {
                        continue
                    }
                    output["\(name)-\(kind)"] = [
                        "velocity": [particle.velocity.x, particle.velocity.y, particle.velocity.z],
                        "packedDirection": [instance.velocityAndTrail.x, instance.velocityAndTrail.y,
                                            instance.velocityAndTrail.z],
                        "stretch": instance.velocityAndTrail.w,
                        "gpuFinite": instance.isFinite, "age": particle.age,
                    ]
                }
            }
            return output
        }
        advance(117)
        let rising = observation()
        advance(6)
        return ["rising": rising, "falling": observation(),
                "activeLayerIDs": runtime.activeLayerIDs,
                "rootCount": runtime.lifecycleSnapshot.rootParticleCount,
                "childCount": runtime.lifecycleSnapshot.childParticleCount,
                "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue)]
    }

    static func instanceBufferBudget() throws -> [String: Any] {
        // The per-system instance buffer growth ceiling is tied to the
        // frozen whole-layer segment-instance budget: an emission beyond it
        // fails closed through the existing instanceBufferAllocationFailed
        // path instead of growing device memory without bound.
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let instance = SceneParticleGPUInstance(
            position: SIMD3(1, 2, 3), size: 4, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1
        )
        func accepts(_ count: Int) -> Bool {
            SceneParticleMetalInstanceBuffer().update(
                device: device,
                instances: Array(repeating: instance, count: count)
            )
        }
        return [
            "withinBudgetAccepted": accepts(
                SceneParticleRopeTrailPlan.maximumSegmentInstanceCount
            ),
            "overBudgetRejected": !accepts(
                SceneParticleRopeTrailPlan.maximumSegmentInstanceCount + 1
            ),
        ]
    }

    static func stockSynthetic(bundlePath: String) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-stock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeParticle(
            "particles/stock.json",
            material: "materials/stock.json",
            children: [[
                "name": "particles/repeat-child.json",
                "type": "static",
            ]],
            under: directory
        )
        try writeParticle(
            "particles/repeat-child.json",
            material: "materials/repeat.json",
            under: directory
        )
        try writeParticle(
            "particles/wide.json",
            material: "materials/wide.json",
            under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(21, "particles/stock.json"),
                layer(22, "particles/wide.json"),
            ],
            renderOrderLayerIDs: [21, 22],
            materialPasses: [
                .init(
                    materialPath: "materials/stock.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["particle/debris/debris1.tex"],
                    blending: "translucent"
                ),
                .init(
                    materialPath: "materials/repeat.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["particle/nature/leaves7"],
                    blending: "translucent"
                ),
                .init(
                    materialPath: "materials/wide.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["particle/lightning/lightning3"],
                    blending: "translucent"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let bundleURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device,
            stockTextureBundleURL: bundleURL
        )
        let batches = runtime.advance(by: 1.0 / 60.0)
        let root = batches.first { $0.particlePath == "particles/stock.json" }
        let child = batches.first {
            $0.particlePath == "particles/repeat-child.json"
        }
        let wide = batches.first { $0.particlePath == "particles/wide.json" }
        let refractionSampling: [String: Any]
        if let resolver = SceneStockTextureResolver(bundleRoot: bundleURL),
           let colorURL = resolver.textureURL(for: "particle/misc/wave"),
           let normalURL = resolver.textureURL(for: "particle/normal_splash"),
           let loaded = SceneParticleRefractionTextureLoader.load(
               colorSource: .file(colorURL),
               declaration: SceneParticleRefractionDeclaration(
                   normalTextureSource: .file(normalURL),
                   amount: 1,
                   overbright: 1
               ),
               textureLoader: SceneTextureLoader(),
               device: device
           ) {
            refractionSampling = [
                "color": sampling(loaded.colorSampling),
                "normal": loaded.binding.resolvedNormalArguments().map {
                    sampling($0.sampling)
                } ?? [:],
            ]
        } else {
            refractionSampling = [:]
        }
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "textureWidth": root?.texture.width ?? 0,
            "textureHeight": root?.texture.height ?? 0,
            "rootSampling": root.map { sampling($0.colorSampling) } ?? [:],
            "childTextureWidth": child?.texture.width ?? 0,
            "childFrameAspects": child?.instances.first.map {
                [$0.frame0B.z, $0.frame0B.w]
            } ?? [],
            "childSampling": child.map { sampling($0.colorSampling) } ?? [:],
            "wideFrameAspects": wide?.instances.first.map {
                [$0.frame0B.z, $0.frame0B.w]
            } ?? [],
            "refractionSampling": refractionSampling,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    static func syntheticLayerAlpha() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mwx-layer-alpha-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle("particles/child.json", material: "materials/shared.json",
            startTime: 0.1, rate: 0, instantaneous: 1, under: directory)
        try writeParticle("particles/root.json", material: "materials/shared.json",
            startTime: 0.1, rate: 0, instantaneous: 1,
            children: [["name": "particles/child.json", "type": "static"]], under: directory)
        let descriptor = SceneRenderDescriptor(
            layers: [layer(91, "particles/root.json", particleAlpha: 0.5, layerAlpha: 0.4)],
            renderOrderLayerIDs: [91], materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive")])
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
        let target = SceneDynamicTarget.layer(layerID: 91, field: .alpha)
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ alpha: Double) -> SceneDynamicSnapshot {
            resolver.resolve(frameIndex: 1, generation: 1,
                definitions: [.init(target: target, valueType: .scalar, authoredValue: .scalar(0.4))],
                userValues: [target: .scalar(alpha)]).snapshot
        }
        func values(_ batches: [SceneParticleDrawBatch]) -> [Float] {
            batches.flatMap { $0.instances.map { $0.rotationAndAlpha.w } }
        }
        let initial = runtime.advance(by: 0.1)
        let changed = runtime.advance(by: 0, dynamicValues: snapshot(0.8))
        let hidden = runtime.advance(by: 0, dynamicValues: snapshot(0))
        let recovered = runtime.advance(by: 0, dynamicValues: snapshot(1))
        let fallback = runtime.advance(by: 0)
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor, cacheDirectory: directory, device: device,
            initialDynamicValues: snapshot(0.8)) else { throw HarnessError.noParticlePipeline }
        let startup = values(playback.batches)
        let rejected = values(playback.advance(by: 0, dynamicValues: snapshot(0)))
        let restored = values(playback.batches)
        let retry = values(playback.advance(by: 0, dynamicValues: snapshot(0.5)))
        return ["startup": startup, "rejected": rejected, "restored": restored, "retry": retry,
            "initial": values(initial), "changed": values(changed),
            "hidden": values(hidden), "recovered": values(recovered), "fallback": values(fallback),
            "positionsUnchanged": initial.flatMap(\.instances).map(\.positionAndSize)
                == recovered.flatMap(\.instances).map(\.positionAndSize),
            "rootParticles": runtime.lifecycleSnapshot.rootParticleCount,
            "childParticles": runtime.lifecycleSnapshot.childParticleCount]
    }

    static func syntheticDynamicInstanceOverride() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-dynamic-override-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/live-override.json", material: "materials/shared.json",
            lifetime: 10, rate: 4, under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(
                91, "particles/live-override.json", particleAlpha: 0,
                particleSize: 1, particleCount: 1,
                particleNormalizedColor: SIMD3(1, 1, 1), alphaHasUser: true
            )],
            renderOrderLayerIDs: [91],
            materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor, cacheDirectory: directory, device: device
        )
        let alpha = SceneDynamicTarget.particle(layerID: 91, field: .alpha)
        let size = SceneDynamicTarget.particle(layerID: 91, field: .size)
        let count = SceneDynamicTarget.particle(layerID: 91, field: .count)
        let color = SceneDynamicTarget.particle(layerID: 91, field: .normalizedColor)
        let definitions = [
            SceneDynamicTargetDefinition(target: alpha, valueType: .scalar, authoredValue: .scalar(0)),
            .init(target: size, valueType: .scalar, authoredValue: .scalar(1)),
            .init(target: count, valueType: .scalar, authoredValue: .scalar(1)),
            .init(target: color, valueType: .vector3, authoredValue: .vector3(1, 1, 1)),
        ]
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ values: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshot {
            resolver.resolve(
                frameIndex: 1, generation: 1, definitions: definitions, userValues: values
            ).snapshot
        }
        let zero = runtime.advance(by: 0.25, dynamicValues: snapshot([count: .scalar(0)]))
        let dynamic = runtime.advance(by: 0.25, dynamicValues: snapshot([
            alpha: .scalar(0.25), size: .scalar(3), count: .scalar(2),
            color: .vector3(0.5, 1, 0.25),
        ]))
        let fallback = runtime.advance(by: 0.25)
        let dynamicParticle = dynamic.first?.instances.first
        let fallbackParticle = fallback.first?.instances.last
        return [
            "zeroCount": zero.first?.instances.count ?? 0,
            "dynamicCount": dynamic.first?.instances.count ?? 0,
            "dynamicAlpha": dynamicParticle?.rotationAndAlpha.w ?? -1,
            "dynamicSize": dynamicParticle?.positionAndSize.w ?? -1,
            "dynamicColor": dynamicParticle.map {
                [$0.colorAndFrameMix.x, $0.colorAndFrameMix.y, $0.colorAndFrameMix.z]
            } ?? [],
            "fallbackCount": fallback.first?.instances.count ?? 0,
            "fallbackAlpha": fallbackParticle?.rotationAndAlpha.w ?? -1,
            "fallbackSize": fallbackParticle?.positionAndSize.w ?? -1,
            "fallbackColor": fallbackParticle.map {
                [$0.colorAndFrameMix.x, $0.colorAndFrameMix.y, $0.colorAndFrameMix.z]
            } ?? [],
        ]
    }

    static func syntheticSpriteGeometry() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-sprite-geometry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func texture(_ name: String, embedded: Bool, atlas: Bool = false) throws {
            var rgba = [UInt8](repeating: 0, count: 8 * 8 * 4)
            for y in 0..<8 { for x in 0..<2 { for c in 0..<4 { rgba[(y * 8 + x) * 4 + c] = 255 } } }
            var payload = Data(rgba)
            if embedded {
                let encoded = NSMutableData()
                guard let provider = CGDataProvider(data: payload as CFData),
                      let image = CGImage(width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                      let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil)
                else { throw HarnessError.imageWrite }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
                payload = encoded as Data
            }
            var data = Data("TEXV0005\0TEXI0001\0".utf8)
            for value: UInt32 in [0, atlas ? 7 : 3, 8, 8, 2, 8, 0] { appendUInt32(value, to: &data) }
            data.append(Data((embedded ? "TEXB0003\0" : "TEXB0002\0").utf8))
            appendUInt32(1, to: &data)
            if embedded { appendUInt32(13, to: &data) }
            for value: UInt32 in [1, 8, 8, 0, 0, UInt32(payload.count)] { appendUInt32(value, to: &data) }
            data.append(payload)
            if atlas {
                data.append(Data("TEXS0002\0".utf8)); appendUInt32(1, to: &data)
                appendUInt32(0, to: &data); appendFloat32(1, to: &data)
                for value: Float in [0, 0, 2, 0, 0, 8] { appendFloat32(value, to: &data) }
            }
            let url = directory.appendingPathComponent("materials/\(name).tex")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try texture("raw", embedded: false)
        try texture("embedded", embedded: true)
        try texture("atlas", embedded: false, atlas: true)
        let names = ["raw", "embedded", "atlas", "refract"]
        var layers: [SceneRenderDescriptor.Layer] = []
        var materials: [SceneRenderDescriptor.MaterialPassDescriptor] = []
        for (index, name) in names.enumerated() {
            let material = "materials/\(name).json"
            try writeParticle("particles/\(name).json", material: material,
                instantaneous: 1, children: name == "raw" ? [[
                    "name": "particles/child.json", "type": "static"
                ], ["name": "particles/child-refract.json", "type": "static"]] : [], under: directory)
            layers.append(layer(index + 1, "particles/\(name).json"))
            materials.append(.init(materialPath: material, shaderPath: "genericparticle",
                texturePaths: ["materials/\(name == "refract" ? "raw" : name).tex"],
                blending: "translucent", combos: name == "refract" ? ["REFRACT": 1] : [:]))
        }
        try writeParticle("particles/child.json", material: "materials/embedded.json",
            instantaneous: 1, under: directory)
        try writeParticle("particles/child-refract.json", material: "materials/refract.json",
            instantaneous: 1, under: directory)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(descriptor: .init(layers: layers,
            renderOrderLayerIDs: [1, 2, 3, 4], materialPasses: materials),
            cacheDirectory: directory, device: device)
        let batches = runtime.advance(by: 1.0 / 60.0)
        var result: [String: Any] = [:]
        for batch in batches {
            guard let instance = batch.instances.first else { continue }
            let name = URL(fileURLWithPath: batch.particlePath).deletingPathExtension().lastPathComponent
            result[name] = [
                "aspect": [instance.frame0B.z, instance.frame0B.w],
                "uvScale": [batch.colorUVScale.x, batch.colorUVScale.y],
                "textureSize": [batch.texture.width, batch.texture.height],
                "pixels": spriteBatchBounds(batch, device: device)
            ]
        }
        result["active"] = runtime.activeLayerIDs
        return result
    }

    static func spriteBatchBounds(_ batch: SceneParticleDrawBatch, device: MTLDevice) -> [Int] {
        guard batch.instanceBuffer.update(device: device, instances: batch.instances) else { return [] }
        let size = 64
        guard let pipeline = SceneParticleMetalPipeline(device: device),
              let command = device.makeCommandQueue()?.makeCommandBuffer() else { return [] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = .renderTarget; descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        pipeline.draw(texture: batch.texture, instances: batch.instanceBuffer,
            uniforms: SceneParticleLayerUniforms(viewProjection: simd_float4x4(diagonal: SIMD4(1.0 / 32, 1.0 / 32, 1, 1)),
                layerModel: matrix_identity_float4x4, basis: .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0))),
            renderState: batch.renderState, colorUVScale: batch.colorUVScale,
            colorSampling: batch.colorSampling, encoder: encoder)
        encoder.endEncoding()
        guard batch.instanceBuffer.markSubmitted(on: command) else { return [] }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return [] }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(&bytes, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        let lit = (0..<(size * size)).filter { bytes[$0 * 4 + 3] > 127 }
        let xs = lit.map { $0 % size }, ys = lit.map { $0 / size }
        return [(xs.max() ?? -1) - (xs.min() ?? 0) + 1,
                (ys.max() ?? -1) - (ys.min() ?? 0) + 1,
                (xs.max() ?? -1) + (xs.min() ?? 0), (ys.max() ?? -1) + (ys.min() ?? 0)]
    }

    static func synthetic() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))

        try writeParticle("particles/no-texture.json", material: "materials/no-texture.json", under: directory)
        try writeParticle("particles/world.json", material: "materials/shared.json", flags: 1, under: directory)
        try writeParticle(
            "particles/world-dynamic.json", material: "materials/shared.json",
            flags: 1, under: directory
        )
        try writeParticle(
            "particles/renderer-world.json", material: "materials/shared.json",
            rendererFlags: 1, under: directory
        )
        try writeParticle(
            "particles/movement-world.json", material: "materials/shared.json",
            moves: true, movementFlags: 1, under: directory
        )
        try writeParticle(
            "particles/trail.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererLength: 0.05,
            rendererMinimumLength: 1, rendererMaximumLength: 10,
            velocityX: 100, under: directory
        )
        try writeParticle(
            "particles/default-trail.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererMaximumLength: 2,
            velocityX: 100, under: directory
        )
        try writeParticle(
            "particles/malformed-trail.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererLength: "invalid",
            velocityX: 100, under: directory
        )
        try writeParticle(
            "particles/child-root.json", material: "materials/shared.json",
            children: [
                ["name": "particles/child.json", "type": "eventspawn", "maxcount": 500],
                ["name": "particles/trail-child.json", "type": "eventspawn", "maxcount": 500],
            ], under: directory
        )
        try writeParticle(
            "particles/child.json", material: "materials/normal-cull.json",
            rate: 0, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/trail-child.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererMaximumLength: 2,
            velocityX: 100, rate: 0, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/unsupported-child-root.json", material: "materials/shared.json",
            children: [
                ["name": "particles/child.json", "type": "static"],
                ["name": "particles/child.json"],
                ["name": "particles/origin-child.json", "type": "static", "origin": "1 2 3"],
                ["name": "particles/angles-child.json", "type": "static", "angles": "1 0 0"],
                ["name": "particles/scale-child.json", "type": "static", "scale": "2 2 2"],
                ["name": "particles/zero-scale-child.json", "type": "static", "scale": "0 0 1"],
                ["name": "particles/negative-scale-child.json", "type": "static", "scale": "-1 -1 1"],
                ["name": "particles/nonuniform-scale-child.json", "type": "static", "scale": "2 3 1"],
                ["name": "particles/huge-scale-child.json", "type": "static", "scale": "2048 2048 1"],
                ["name": "particles/malformed-scale-child.json", "type": "static", "scale": "invalid"],
                ["name": "particles/event-origin-child.json", "type": "eventspawn", "origin": "1 2 3"],
                ["name": "particles/nan-origin-child.json", "type": "static", "origin": "nan 0 0"],
                ["name": "particles/probability-child.json", "type": "static", "probability": 0.5],
                ["name": "particles/custom-shader.json", "type": "static"],
            ], under: directory
        )
        for path in [
            "particles/origin-child.json", "particles/angles-child.json",
            "particles/event-origin-child.json",
            "particles/nan-origin-child.json", "particles/probability-child.json",
        ] {
            try writeParticle(
                path, material: "materials/shared.json", rate: 0, instantaneous: 1,
                under: directory
            )
        try writeParticle(
            "particles/scale-child.json", material: "materials/shared.json",
            velocityX: 4, moves: true, rate: 0, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/control-point-copy-root.json", material: "materials/shared.json",
            emitterControlPoint: 1, controlPointOffset: [0, 0, 0],
            children: [
                ["name": "particles/raw-copy-child.json", "type": "static"],
                ["name": "particles/adjusted-copy-child.json", "type": "static"],
                ["name": "particles/malformed-copy-child.json", "type": "static"],
                ["name": "particles/raw-copy-child.json", "type": "eventspawn"],
            ], under: directory
        )
        for (path, flags) in [
            ("particles/raw-copy-child.json", 4),
            ("particles/adjusted-copy-child.json", 0),
        ] {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 10,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "controlpoint": 1, "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
                "renderer": [["name": "sprite"]],
                "controlpoint": [[
                    "id": 1, "flags": flags, "offset": [0, 0, 0],
                    "parentcontrolpoint": 1,
                ]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 10,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
            "renderer": [["name": "sprite"]],
            "controlpoint": [["id": 1, "flags": 4, "offset": [0, 0, 0]]],
        ], to: directory.appendingPathComponent("particles/malformed-copy-child.json"))
        }
        try writeParticle("particles/drop.json", material: "materials/drop.json", under: directory)
        try writeParticle("particles/halo.json", material: "materials/halo.json", under: directory)
        try writeParticle("particles/unknown.json", material: "materials/unknown.json", under: directory)
        try writeParticle(
            "particles/custom-shader.json", material: "materials/custom-shader.json",
            under: directory
        )
        try writeParticle(
            "particles/normal-cull.json", material: "materials/normal-cull.json",
            under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(1, "particles/no-texture.json"),
                layer(2, "particles/world.json"),
                layer(3, "particles/trail.json"),
                layer(4, "particles/child-root.json"),
                layer(5, "particles/hidden-never-loaded.json", visible: false),
                layer(6, "particles/drop.json"),
                layer(7, "particles/halo.json"),
                layer(8, "particles/unknown.json"),
                layer(9, "particles/unsupported-child-root.json"),
                layer(10, "particles/trail.json", particleAlpha: 0),
                layer(11, "particles/trail.json", particleAlpha: 0, alphaHasScript: true),
                layer(12, "particles/world-dynamic.json"),
                layer(13, "particles/renderer-world.json"),
                layer(14, "particles/movement-world.json"),
                layer(15, "particles/custom-shader.json"),
                layer(16, "particles/normal-cull.json"),
                layer(
                    17, "particles/control-point-copy-root.json",
                    controlPoint: SIMD3(22, 0, 0)
                ),
                layer(
                    18, "particles/control-point-copy-root.json",
                    controlPoint: SIMD3(22, 0, 0), controlPointHasAnimation: true
                ),
                layer(19, "particles/default-trail.json"),
                layer(20, "particles/malformed-trail.json"),
            ],
            renderOrderLayerIDs: Array(1 ... 20),
            materialPasses: [
                .init(
                    materialPath: "materials/no-texture.json",
                    shaderPath: "genericparticle", texturePaths: [], blending: "translucent"
                ),
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/drop.json",
                    shaderPath: "genericparticle", texturePaths: ["particle/drop"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/halo.json",
                    shaderPath: "genericparticle", texturePaths: ["particle/halo"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/unknown.json",
                    shaderPath: "genericparticle", texturePaths: ["particle/not-supported"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/custom-shader.json",
                    shaderPath: "customparticle", texturePaths: ["shared.png"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/normal-cull.json",
                    shaderPath: "genericparticle", texturePaths: ["shared.png"],
                    blending: "translucent", combos: ["REFRACT": 0], cullMode: "normal"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device,
            staticWorldSpaceFrames: [
                2: SceneParticleWorldSpaceFrame(worldFrame: matrix_identity_float4x4)!,
                14: SceneParticleWorldSpaceFrame(worldFrame: matrix_identity_float4x4)!,
            ]
        )
        _ = runtime.advance(by: 0.25)
        let batches = runtime.advance(by: 0.25)
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "batchLayerIDs": batches.map(\.layerID),
            "zeroInstanceAlphaGPUValues": batches.filter { $0.layerID == 10 }
                .flatMap { $0.instances.map { $0.rotationAndAlpha.w } },
            "activeParticleCount": batches.first?.instances.count ?? 0,
            "childInstanceCount": batches.first {
                $0.particlePath == "particles/child.json"
            }?.instances.count ?? 0,
            "childCullStates": batches.filter {
                $0.particlePath == "particles/child.json"
            }.map { $0.renderState.cullMode.rawValue },
            "staticChildInstanceCount": batches.filter {
                $0.layerID == 9 && $0.particlePath != "particles/unsupported-child-root.json"
            }.reduce(0) { $0 + $1.instances.count },
            "staticChildOrigins": batches.filter {
                $0.layerID == 9 && $0.particlePath != "particles/unsupported-child-root.json"
            }.compactMap { batch in
                batch.instances.first.map {
                    [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
                }
            },
            "scaledStaticInstance": batches.first {
                $0.layerID == 9 && $0.particlePath == "particles/scale-child.json"
            }?.instances.first.map {
                [
                    "position": [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z],
                    "size": [$0.positionAndSize.w],
                    "velocity": [$0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z],
                ]
            } ?? [:],
            "staticChildScaleBounded": runtime.diagnostics.contains {
                $0.layerID == 9
                    && $0.detail == "particles/scale-child.json:childScaleBounded:scale=2.0,2.0,2.0"
            },
            "staticChildUnsupportedDetails": runtime.diagnostics.compactMap {
                $0.layerID == 9 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "batchTextureSizes": batches.reduce(into: [String: [Int]]()) {
                $0[String($1.layerID)] = [$1.texture.width, $1.texture.height]
            },
            "trailStretch": batches.first(where: { $0.layerID == 3 })?
                .instances.first?.velocityAndTrail.w ?? -1,
            "trailVelocity": batches.first(where: { $0.layerID == 3 })?
                .instances.first.map {
                    [$0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z]
                } ?? [],
            "defaultTrailStretch": batches.first(where: { $0.layerID == 19 })?
                .instances.first?.velocityAndTrail.w ?? -1,
            "childTrailStretch": batches.first {
                $0.particlePath == "particles/trail-child.json"
            }?.instances.first?.velocityAndTrail.w ?? -1,
            "rendererWorldOrientation": batches.first(where: { $0.layerID == 13 })?
                .orientation == .worldScreen,
            "movementWorldLayerLoaded": batches.contains { $0.layerID == 14 },
            "normalCullState": batches.first(where: { $0.layerID == 16 })?
                .renderState.cullMode.rawValue ?? "",
            "rawControlPointCopyPositions": batches.first {
                $0.particlePath == "particles/raw-copy-child.json"
            }?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "adjustedControlPointCopyLoaded": batches.contains {
                $0.particlePath == "particles/adjusted-copy-child.json"
            },
            "rawControlPointCopyBounded": runtime.diagnostics.contains {
                $0.detail == "particles/raw-copy-child.json:rawParentControlPointCopyBounded:mappings=1"
            },
            "rawControlPointCopyLayerIDs": batches.filter {
                $0.particlePath == "particles/raw-copy-child.json"
            }.map(\.layerID),
            "diagnostics": runtime.diagnostics.map {
                [
                    "kind": $0.kind.rawValue,
                    "layer": $0.layerID as Any,
                    "path": $0.particlePath,
                    "detail": $0.detail as Any,
                ]
            },
            "hiddenMentioned": runtime.diagnostics.contains {
                $0.layerID == 5 || $0.particlePath.contains("hidden-never-loaded")
            },
        ]
    }

    static func syntheticBatchEvidence() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-evidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle("particles/burst.json", material: "materials/shared.json",
                          lifetime: 0.05, rate: 60, emitterDuration: 0.034, under: directory)
        try writeParticle("particles/dormant.json", material: "materials/shared.json",
                          rate: 0, under: directory)
        let descriptor = SceneRenderDescriptor(
            layers: [layer(200, "particles/burst.json"), layer(201, "particles/dormant.json")],
            renderOrderLayerIDs: [200, 201],
            materialPasses: [.init(materialPath: "materials/shared.json",
                shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive")]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor, cacheDirectory: directory, device: device
        ) else { throw HarnessError.noParticlePipeline }
        let initial = playback.loadReportLines(descriptor: descriptor)
        let rejected = playback.advance(by: 1.0 / 30.0)
        let beforeCommit = playback.committedNonemptyBatchLayerIDs.sorted()
        let discarded = playback.loadReportLines(descriptor: descriptor)
        // CPU simulation is committed without requiring any GPU submission.
        let afterDiscard = playback.committedNonemptyBatchLayerIDs.sorted()
        let retried = playback.advance(by: 1.0 / 30.0)
        let committed = playback.committedNonemptyBatchLayerIDs.sorted()
        for _ in 0..<20 {
                _ = playback.advance(by: 1.0 / 30.0)
            }
        return [
            "initial": initial,
            "rejectedCount": rejected.reduce(0) { $0 + $1.instances.count },
            "retriedCount": retried.reduce(0) { $0 + $1.instances.count },
            "beforeCommit": beforeCommit,
            "afterDiscard": afterDiscard,
            "discarded": discarded,
            "committed": committed,
            "dormant": playback.loadReportLines(descriptor: descriptor),
        ]
    }

}
