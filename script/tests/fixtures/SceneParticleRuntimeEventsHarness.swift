import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func realEventSpawnSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        )
        _ = runtime.advance(by: 0.5)
        let batches = runtime.advance(by: 1.0 / 60.0)
        let childPath = "particles/workshop/2562725207/presets/shootingstarglow.json"
        var facts1: [String: Any] = [
            "activeLayerIDs": runtime.activeLayerIDs,
            "childInstanceCount": batches.first { $0.particlePath == childPath }?.instances.count ?? 0,
            "childTextureWidth": batches.first { $0.particlePath == childPath }?.texture.width ?? 0,
        ]
#if DEBUG
        facts1["layer264ChildUnsupported"] = runtime.diagnostics.contains {
            $0.layerID == 264 && $0.kind == .childSystemsUnsupported
        }
#endif
        return facts1
    }

    static func realEventDeathSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        )
        let hitPath = "particles/workshop/2110548715/presets/fireworks1hit.json"
        var firstHitBatches: [SceneParticleDrawBatch] = []
        var firstRootInstances: [SceneParticleGPUInstance] = []
        var firstHitFrame = -1
        for frame in 0..<(8 * 60) {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let hitBatches = batches.filter { $0.particlePath == hitPath }
            if !hitBatches.isEmpty {
                firstHitFrame = frame
                firstHitBatches = hitBatches
                firstRootInstances = batches.filter {
                    $0.layerID == 529 && $0.particlePath != hitPath
                }.flatMap(\.instances)
                break
            }
        }
        let hitBatches = firstHitBatches
        let hitInstances = hitBatches.flatMap(\.instances)
        let pixels = renderEventDeathBatches(hitBatches, device: device)
        var facts2: [String: Any] = [
            "firstHitFrame": firstHitFrame,
            "hitInstanceCount": hitInstances.count,
            "hitMaximumAlpha": hitInstances.map(\.rotationAndAlpha.w).max() ?? -1,
            "hitMaximumSize": hitInstances.map(\.positionAndSize.w).max() ?? -1,
            "hitMaximumTrailStretch": hitInstances.map(\.velocityAndTrail.w).max() ?? -1,
            "hitMinimumPosition": vector(hitInstances.map(\.positionAndSize).min {
                $0.y < $1.y
            } ?? .zero),
            "hitMaximumPosition": vector(hitInstances.map(\.positionAndSize).max {
                $0.y < $1.y
            } ?? .zero),
            "rootPositions": firstRootInstances.map { vector($0.positionAndSize) },
            "renderedPixelCount": pixels["count"] ?? 0,
            "renderedPixelWidth": pixels["width"] ?? 0,
            "renderedPixelHeight": pixels["height"] ?? 0,
            "hitUsesTrail": hitBatches.contains {
                ($0.instances.first?.velocityAndTrail.w ?? -1) >= 0
            },
        ]
#if DEBUG
        facts2["layer529ChildUnsupported"] = runtime.diagnostics.contains {
            $0.layerID == 529 && $0.kind == .childSystemsUnsupported
        }
        facts2["layer529SimulationDetails"] = runtime.diagnostics.compactMap {
            $0.layerID == 529 && $0.kind == .simulationLimitation ? $0.detail : nil
        }
#endif
        return facts2
    }

    static func renderEventDeathBatches(
        _ batches: [SceneParticleDrawBatch],
        device: MTLDevice
    ) -> [String: Int] {
        let width = 1280
        let height = 831
        guard !batches.isEmpty,
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [:] }
        let prepared = pipeline.prepare(batches)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor) else { return [:] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [:] }

        let origin = SIMD2<Float>(1783.794, 2160 - 589.649)
        let halfExtents = SIMD2<Float>(Float(width) / Float(height) * 1080, 1080)
        let model = simd_float4x4(columns: (
            SIMD4(1 / halfExtents.x, 0, 0, 0),
            SIMD4(0, 1 / halfExtents.y, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(
                (origin.x - 1920) / halfExtents.x,
                1 - origin.y / halfExtents.y,
                0,
                1
            )
        ))
        let basis = SceneParticleOrientation.screen.basis(
            cameraRight: SIMD3(1, 0, 0),
            cameraUp: SIMD3(0, -1, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        for batch in prepared {
            pipeline.draw(
                texture: batch.draw.texture,
                instances: batch.instanceBuffer,
                uniforms: SceneParticleLayerUniforms(
                    viewProjection: matrix_identity_float4x4,
                    layerModel: model,
                    basis: basis
                ),
                renderState: batch.draw.renderState,
                colorSampling: batch.draw.colorSampling,
                encoder: encoder
            )
        }
        encoder.endEncoding()
        for batch in prepared { batch.instanceBuffer.markSubmitted(on: command) }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return [:] }

        var values = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(
            &values,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        var count = 0
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard values[offset] > 3 || values[offset + 1] > 3 || values[offset + 2] > 3 else {
                    continue
                }
                count += 1
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        return [
            "count": count,
            "width": maximumX >= minimumX ? maximumX - minimumX + 1 : 0,
            "height": maximumY >= minimumY ? maximumY - minimumY + 1 : 0,
        ]
    }

    static func childOptionBehavior(directory: URL, device: MTLDevice,
                                    materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor]) throws -> [String: Any] {
        let zeroPoints: [[String: Any]] = (0..<8).map { ["id": $0, "flags": 0, "offset": "0 0 0"] }
        func leaf(origin: String = "0 0 0") -> [String: Any] {
            ["material": "materials/shared.json", "maxcount": 3, "flags": 0, "controlpoint": zeroPoints,
             "emitter": [["name": "sphererandom", "instantaneous": 1, "rate": 0, "origin": origin,
                "distancemin": 0, "distancemax": 0, "speedmin": 0, "speedmax": 0]],
             "initializer": [["name": "lifetimerandom", "min": 2, "max": 2],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "colorrandom", "min": "255 255 255", "max": "255 255 255"],
                ["name": "alpharandom", "min": 0.5, "max": 0.5]],
             "operator": [["name": "movement", "drag": 0, "gravity": "0 0 0"]],
             "renderer": [["name": "sprite"]], "children": []]
        }
        func parent(_ children: [[String: Any]]) -> [String: Any] {
            var value = leaf(origin: "16 0 0"); value["controlpoint"] = []; value["maxcount"] = 1
            var writers = value["initializer"] as! [[String: Any]]
            writers[0]["min"] = 2.0 / 60; writers[0]["max"] = 2.0 / 60
            value["initializer"] = writers; value["children"] = children
            return value
        }
        func runtime(_ path: String, id: Int = 701) -> SceneParticleRuntime {
            let descriptor = SceneRenderDescriptor(layers: [layer(id, path), layer(702, "particles/options-peer.json")],
                renderOrderLayerIDs: [id, 702], materialPasses: materialPasses)
            return SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
        }
        var glow = leaf()
        let emitter = (glow["emitter"] as! [[String: Any]])[0]
        glow["emitter"] = ["0 0 0", "16 0 0", "0 24 0"].enumerated().map { index, origin in
            var item = emitter; item["id"] = index + 1; item["origin"] = origin; return item
        }
        try writeJSON(glow, to: directory.appendingPathComponent("particles/options-glow.json"))
        try writeJSON(glow, to: directory.appendingPathComponent("particles/options-renamed.json"))
        try writeJSON(leaf(origin: "64 0 0"), to: directory.appendingPathComponent("particles/options-peer.json"))
        var facts: [String: Bool] = [:], observed: [String: Any] = [:]
        let variants: [(String, Int, Int?, String, Int)] = [
            ("zero", 0, nil, "particles/options-glow.json", 701),
            ("one", 1, nil, "particles/options-glow.json", 701),
            ("start-only", 0, 99, "particles/options-glow.json", 701),
            ("opaque-renamed", 1 << 24, 99, "particles/options-renamed.json", 901),
        ]
        for (name, flags, start, childPath, id) in variants {
            var declaration: [String: Any] = ["name": childPath, "type": "eventdeath", "flags": flags]
            if let start { declaration["controlpointstartindex"] = start }
            let path = "particles/options-\(name)-parent.json"
            try writeJSON(parent([declaration]), to: directory.appendingPathComponent(path))
            let value = runtime(path, id: id); _ = value.advance(by: 1.0 / 60)
            let checkpoint = value.frameSnapshot()
            _ = value.advance(by: 0.1)
            // Death creates the system; its natural emitter runs next cadence.
            let batches = value.advance(by: 1.0 / 60)
            let first = value.frameSnapshot().layers[0].child?.systems.first
            let positions = batches.filter { $0.particlePath == childPath }.flatMap(\.instances).map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            }
            facts[name + "/death-three-L-and-peer"] = positions == [[16, 0, 0], [32, 0, 0], [16, 24, 0]]
                && value.lifecycleSnapshot.childParticleCount == 3 && value.lifecycleSnapshot.childSystemCount == 1
                && value.frameSnapshot().layers[0].root?.simulatorFrame.particles.isEmpty == true
                && batches.contains { $0.layerID == 702 && $0.instances.count == 1 }
            observed[name] = positions
            value.restoreFrame(checkpoint); _ = value.advance(by: 0.1)
            _ = value.advance(by: 1.0 / 60)
            let replay = value.frameSnapshot().layers[0].child?.systems.first
            facts[name + "/retry"] = first != nil && replay?.id == first?.id
                && replay?.simulatorFrame.particles == first?.simulatorFrame.particles
                && replay?.simulatorFrame.random.state == first?.simulatorFrame.random.state
                && replay?.simulatorFrame.nextParticleID == first?.simulatorFrame.nextParticleID
        }
        var readerPrepared: [String: Bool] = [:], declarations: [[String: Any]] = []
        for name in ["emitter", "pointer0", "between", "around", "maintain", "radius", "force", "reduce", "v2"] {
            var raw = leaf(), writers = raw["initializer"] as! [[String: Any]]
            switch name {
            case "emitter":
                var emitters = raw["emitter"] as! [[String: Any]]; emitters[0]["controlpoint"] = 1; raw["emitter"] = emitters
            case "pointer0":
                var points = zeroPoints; points[0]["flags"] = 1; raw["controlpoint"] = points
            case "between": writers.append(["name": "mapsequencebetweencontrolpoints", "count": 3])
            case "around": writers.append(["name": "mapsequencearoundcontrolpoint", "count": 4])
            case "maintain": raw["operator"] = [["name": "maintaindistancebetweencontrolpoints"]]
            case "radius": raw["operator"] = [["name": "maintaindistancetocontrolpoint", "distance": 16, "variablestrength": 0]]
            case "force": raw["operator"] = [["name": "controlpointattract", "controlpoint": 1, "scale": 4, "threshold": 64]]
            case "reduce": raw["operator"] = [["name": "reducemovementnearcontrolpoint", "distanceinner": 0, "distanceouter": 64, "reductioninner": 1]]
            default: raw["operator"] = [["name": "vortex_v2", "distanceinner": 0, "distanceouter": 64, "speedinner": 4, "speedouter": 4]]
            }
            raw["initializer"] = writers
            let definition = SceneParticleDefinitionParser().parse(root: raw), op = definition.operators[0]
            switch name {
            case "emitter": readerPrepared[name] = definition.emitterControlPointSource(for: definition.emitters[0]) == 1
            case "pointer0": readerPrepared[name] = definition.emitters[0].controlPoint == nil
                && definition.emitterControlPointSource(for: definition.emitters[0]) == 0
            case "between": readerPrepared[name] = definition.initializers.last?.positionBetweenControlPointsPlan != nil
            case "around": readerPrepared[name] = definition.initializers.last.map { definition.supportsBoundedPositionAroundControlPoint($0) } == true
            case "maintain": if case let .maintainControlPointDistance(plan) = op.kind { readerPrepared[name] = plan != nil }
            case "radius": if case let .controlPointRadius(plan) = op.kind { readerPrepared[name] = plan != nil }
            case "force": readerPrepared[name] = definition.controlPointForcePlan(for: op) != nil
            case "reduce": readerPrepared[name] = definition.supportsBoundedReduceMovement(op)
            default: readerPrepared[name] = definition.vortexPlan(for: op)?.usesControlPointOrigin == true
            }
            let path = "particles/options-reader-\(name).json"
            try writeJSON(raw, to: directory.appendingPathComponent(path))
            var declaration: [String: Any] = ["name": path, "type": "eventdeath", "flags": 1]
            if name != "emitter" { declaration["controlpointstartindex"] = 1 }
            declarations.append(declaration)
        }
        var sphere = leaf(origin: "3 0 0")
        sphere["operator"] = [["name": "collisionsphere", "origin": "0 0 0", "radius": 4, "bouncefactor": 0.5, "controlpoint": 333]]
        let sphereDefinition = SceneParticleDefinitionParser().parse(root: sphere)
        if case let .collisionSphere(plan) = sphereDefinition.operators[0].kind { facts["sphere-real-plan"] = plan != nil }
        try writeJSON(sphere, to: directory.appendingPathComponent("particles/options-sphere.json"))
        var nested = leaf(); nested["children"] = [["name": "particles/options-peer.json", "type": "eventdeath"]]
        try writeJSON(nested, to: directory.appendingPathComponent("particles/options-nested.json"))
        declarations += [["name": "particles/options-nested.json", "type": "eventdeath", "flags": 1],
            ["name": "particles/options-sphere.json", "type": "eventdeath", "flags": 1 << 24, "controlpointstartindex": 99],
            ["name": "particles/options-peer.json", "type": "eventdeath"]]
        try writeJSON(parent(declarations), to: directory.appendingPathComponent("particles/options-readers-parent.json"))
        let value = runtime("particles/options-readers-parent.json"); _ = value.advance(by: 1.0 / 60)
        _ = value.advance(by: 0.1)
        let batches = value.advance(by: 1.0 / 60)
        let children = batches.filter { $0.layerID == 701 && $0.childTemplateIndex != nil }
        facts["readers-local-no-default-particles"] = Set(children.map(\.particlePath))
            == Set(["particles/options-sphere.json", "particles/options-peer.json"])
            && value.lifecycleSnapshot.childParticleCount == 2 && value.lifecycleSnapshot.childSystemCount == 2
        facts["sphere333-no-CP-consumption"] = children.first { $0.particlePath == "particles/options-sphere.json" }?.instances.first?.positionAndSize.x == 20
        facts["healthy-suffix-and-peer"] = children.contains { $0.particlePath == "particles/options-peer.json" && $0.instances.count == 1 }
            && batches.contains { $0.layerID == 702 && $0.instances.count == 1 }
#if DEBUG
        let rejected = Set(value.diagnostics.filter { $0.kind == .childSystemsUnsupported }.compactMap(\.detail))
        // The existing "children" entry summarizes the root, not another template.
        let expected = Set(readerPrepared.keys.map {
            "particles/options-reader-\($0).json:childControlPointBindingUnavailable"
        } + ["particles/options-nested.json:childControlPointBindingUnavailable", "children"])
        facts["each-real-reader-has-local-binding-rejection"] = rejected == expected
        observed["bindingRejections"] = rejected.sorted()
#endif
        var staticCP = leaf(), points = zeroPoints; points[1]["offset"] = "64 0 0"
        staticCP["controlpoint"] = points
        staticCP["operator"] = [["name": "maintaindistancetocontrolpoint", "controlpoint": 1,
                                  "distance": 16, "variablestrength": 0]]
        try writeJSON(staticCP, to: directory.appendingPathComponent("particles/options-static-cp.json"))
        try writeJSON(parent([["name": "particles/options-static-cp.json", "type": "eventdeath", "flags": 0],
            ["name": "particles/options-static-cp.json", "type": "eventdeath", "flags": 0, "controlpointstartindex": 1]]),
            to: directory.appendingPathComponent("particles/options-inactive-start-parent.json"))
        let inactiveStart = runtime("particles/options-inactive-start-parent.json")
        _ = inactiveStart.advance(by: 1.0 / 60)
        _ = inactiveStart.advance(by: 0.1)
        let staticBatches = inactiveStart.advance(by: 1.0 / 60).filter { $0.layerID == 701 }
        let staticPositions = staticBatches.flatMap(\.instances).map { [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z] }
        facts["flags0-start-index-does-not-activate-binding"] = staticPositions == [[64, 0, 0], [64, 0, 0]]
            && inactiveStart.lifecycleSnapshot.childSystemCount == 2
        observed["flags0-static-cp-positions"] = staticPositions
        return ["facts": facts, "observed": observed, "readerPrepared": readerPrepared]
    }

    static func eventValueBehavior(
        directory: URL, device: MTLDevice,
        materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor]
    ) throws -> [String: Any] {
        func raw(size: Double = 4, alpha: Double = 0.25, life: Double = 2,
                 extra: [[String: Any]] = [], operators: [[String: Any]] = [],
                 children: [[String: Any]] = [], rate: Double = 0,
                 instantaneous: Int = 1) -> [String: Any] {
            ["material": "materials/shared.json", "maxcount": 4,
             "emitter": [["name": "boxrandom", "distancemax": 0, "rate": rate,
                          "instantaneous": instantaneous]],
             "initializer": [["name": "lifetimerandom", "min": life, "max": life],
                 ["name": "sizerandom", "min": size, "max": size],
                 ["name": "colorrandom", "min": "255 255 255", "max": "255 255 255"],
                 ["name": "alpharandom", "min": alpha, "max": alpha]] + extra,
             "operator": operators, "renderer": [["name": "sprite"]], "children": children]
        }
        let inherit: [[String: Any]] = [["id": 31, "name": "inheritinitialvaluefromevent"],
            ["id": 32, "name": "inheritinitialvaluefromevent", "input": "multiplysize"],
            ["id": 33, "name": "inheritinitialvaluefromevent", "input": "setopacity"]]
        let deathChildren: [[String: Any]] = ["values-child", "values-after", "values-renamed", "values-bad",
                             "values-overflow", "values-healthy"].map {
            ["name": "particles/\($0).json", "type": "eventdeath"]
        }
        let constant: [[String: Any]] = [
            ["name": "sizechange", "startvalue": 3, "endvalue": 3],
            ["name": "alphachange", "startvalue": 0.5, "endvalue": 0.5],
            ["name": "colorchange", "startvalue": "0.2 0.4 0.6", "endvalue": "0.2 0.4 0.6"]]
        try writeJSON(raw(size: 10, alpha: 1, life: 3.0 / 60,
            operators: constant, children: deathChildren),
            to: directory.appendingPathComponent("particles/values-root.json"))
        try writeJSON(raw(extra: inherit), to: directory.appendingPathComponent("particles/values-child.json"))
        try writeJSON(raw(extra: inherit + [
            ["name": "sizerandom", "min": 2, "max": 2],
            ["name": "alpharandom", "min": 0.4, "max": 0.4]]),
            to: directory.appendingPathComponent("particles/values-after.json"))
        var renamed = raw(extra: inherit.map { item in
            var value = item; value["id"] = 900 + (item["id"] as! Int)
            value["unconsumedEditorField"] = ["arbitrary": true]; return value
        })
        renamed["material"] = "materials/renamed.json"
        try writePNG(directory.appendingPathComponent("materials/renamed.png"))
        try writeJSON(renamed, to: directory.appendingPathComponent("particles/values-renamed.json"))
        try writeJSON(raw(size: 4, alpha: 0.75,
            extra: [["name": "inheritinitialvaluefromevent", "input": "not-an-event-selector"]],
            operators: [["name": "alphachange", "startvalue": 0.5, "endvalue": 0.5]]),
            to: directory.appendingPathComponent("particles/values-bad.json"))
        try writeJSON(raw(size: 1e38, alpha: 1,
            extra: [["name": "inheritinitialvaluefromevent", "input": "multiplysize"]]),
            to: directory.appendingPathComponent("particles/values-overflow.json"))
        try writeJSON(raw(size: 6, alpha: 0.75),
            to: directory.appendingPathComponent("particles/values-healthy.json"))
        try writeJSON(raw(size: 4, alpha: 0.5, extra: [
            ["name": "sizerandom", "min": 6, "max": 6],
            ["name": "alpharandom", "min": 0.8, "max": 0.8]]),
            to: directory.appendingPathComponent("particles/values-repeat.json"))
        var noSize = raw()
        noSize["initializer"] = (noSize["initializer"] as! [[String: Any]]).filter {
            $0["name"] as? String != "sizerandom"
        }
        try writeJSON(noSize, to: directory.appendingPathComponent("particles/values-default-size.json"))
        let followOperators: [[String: Any]] = [
            ["name": "sizechange", "starttime": 0.02, "endtime": 0.02, "startvalue": 2, "endvalue": 4],
            ["name": "alphachange", "starttime": 0.02, "endtime": 0.02, "startvalue": 0.5, "endvalue": 0.25],
            ["name": "colorchange", "starttime": 0.04, "endtime": 0.04,
             "startvalue": "1 1 1", "endvalue": "0 0.5 1"]]
        try writeJSON(raw(size: 10, alpha: 1, life: 1, operators: followOperators,
            children: [["name": "particles/values-follow-child.json", "type": "eventfollow"]]),
            to: directory.appendingPathComponent("particles/values-follow-root.json"))
        try writeJSON(raw(extra: inherit, operators: [
            ["name": "inheritvaluefromevent"],
            ["name": "inheritvaluefromevent", "input": "multiplysize"],
            ["name": "inheritvaluefromevent", "input": "setopacity"]], rate: 60, instantaneous: 0),
            to: directory.appendingPathComponent("particles/values-follow-child.json"))
        let passes = materialPasses + [.init(materialPath: "materials/renamed.json",
            shaderPath: "genericparticle", texturePaths: ["renamed.png"], blending: "additive")]
        let descriptor = SceneRenderDescriptor(layers: [
            layer(20, "particles/values-root.json"), layer(21, "particles/values-follow-root.json"),
            layer(22, "particles/values-repeat.json"), layer(23, "particles/values-default-size.json")],
            renderOrderLayerIDs: [20, 21, 22, 23], materialPasses: passes)
        let runtime = SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
        func frames(_ value: SceneParticleRuntime.FrameSnapshot, layerID: Int)
            -> [SceneParticleChildRuntime.FrameSnapshot.SystemSnapshot] {
            let index = runtime.layers.firstIndex { $0.layerID == layerID }!
            return value.layers[index].child?.systems ?? []
        }
        func matches(_ value: SceneParticleGPUInstance?, halfSize: Float, alpha: Float) -> Bool {
            guard let value else { return false }
            return abs(value.positionAndSize.w - halfSize) < 1e-5
                && abs(value.rotationAndAlpha.w - alpha) < 1e-6
        }
        func state(_ snapshot: SceneParticleRuntime.FrameSnapshot, layerID: Int,
                   childPath: String? = nil) -> SceneParticleState? {
            let index = runtime.layers.firstIndex { $0.layerID == layerID }!
            guard let childPath else { return snapshot.layers[index].root?.simulatorFrame.particles.first }
            let declarationIndex = deathChildren.firstIndex { $0["name"] as? String == "particles/\(childPath).json" }!
            return frames(snapshot, layerID: layerID).first { $0.templateIndex == declarationIndex }?.simulatorFrame.particles.first
        }
        func batch(_ batches: [SceneParticleDrawBatch], _ path: String) -> SceneParticleGPUInstance? {
            batches.first { $0.particlePath == "particles/\(path).json" }?.instances.first
        }
        var facts: [String: Bool] = [:]
        _ = runtime.advance(by: 1.0 / 60)
        let earlyFollow = frames(runtime.frameSnapshot(), layerID: 21).first?.simulatorFrame
        facts["follow-start-context-has-real-current-values-before-any-child-birth"] =
            earlyFollow?.eventValueContext == .follow(.init(color: SIMD3(repeating: 1), size: 20, alpha: 0.5))
            && earlyFollow?.particles.isEmpty == true
        _ = runtime.advance(by: 1.0 / 60)
        let before = runtime.frameSnapshot()
        let rootIndex = runtime.layers.firstIndex { $0.layerID == 20 }!
        let parent = before.layers[rootIndex].root?.simulatorFrame.particles.first
        facts["real-parent-current-and-initial-values-are-distinct"] = parent?.size == 30
            && parent?.initialSize == 10 && parent?.alpha == 0.5 && parent?.initialAlpha == 1
            && parent?.color == SIMD3(0.2, 0.4, 0.6) && parent?.initialColor == SIMD3(repeating: 1)
        _ = runtime.advance(by: 1.0 / 60)
        let follow = frames(runtime.frameSnapshot(), layerID: 21).first?.simulatorFrame
        facts["follow-later-births-refresh-scalars-without-reinitializing-the-old-particle"] =
            follow?.particles.map(\.initialSize) == [80, 80]
            && follow?.particles.map(\.initialAlpha) == [0.25, 0.25]
            && follow?.particles.map(\.size) == [80, 80]
            && follow?.particles.map(\.alpha) == [0.25, 0.25]
        facts["continuous-operator-keeps-only-color-live"] =
            follow?.particles.first?.initialColor == SIMD3(repeating: 1)
            && follow?.particles.map(\.color) == [SIMD3(0, 0.5, 1), SIMD3(0, 0.5, 1)]
        let batches = runtime.advance(by: 1.0 / 60)
        let accepted = runtime.frameSnapshot()
        let value = batch(batches, "values-child")
        let after = batch(batches, "values-after")
        let childState = state(accepted, layerID: 20, childPath: "values-child")
        let afterState = state(accepted, layerID: 20, childPath: "values-after")
        facts["death-three-values-reach-production-batch-with-half-parent-size-units"] =
            childState?.size == 60 && childState?.alpha == 0.5
            && matches(value, halfSize: 30, alpha: 0.5)
            && value?.colorAndFrameMix.x == 0.2 && value?.colorAndFrameMix.y == 0.4
            && value?.colorAndFrameMix.z == 0.6
        facts["post-inheritance-random-writers-multiply-the-current-values"] =
            afterState?.size == 120 && afterState?.alpha == 0.2
            && matches(after, halfSize: 60, alpha: 0.2)
        facts["independent-repeated-writers-use-multiplicative-identity"] =
            state(accepted, layerID: 22)?.size == 24 && state(accepted, layerID: 22)?.alpha == 0.4
            && state(accepted, layerID: 23)?.size == 20 && state(accepted, layerID: 23)?.alpha == 0.25
            && matches(batch(batches, "values-repeat"), halfSize: 12, alpha: 0.4)
            && matches(batch(batches, "values-default-size"), halfSize: 10, alpha: 0.25)
        facts["renamed-resource-id-and-unconsumed-field-keep-exact-numeric-output"] =
            state(accepted, layerID: 20, childPath: "values-renamed")?.size == 60
            && state(accepted, layerID: 20, childPath: "values-renamed")?.alpha == 0.5
            && matches(batch(batches, "values-renamed"), halfSize: 30, alpha: 0.5)
        facts["unknown-selector-is-local-and-healthy-operator-still-runs"] =
            state(accepted, layerID: 20, childPath: "values-bad")?.size == 4
            && state(accepted, layerID: 20, childPath: "values-bad")?.alpha == 0.375
            && matches(batch(batches, "values-bad"), halfSize: 2, alpha: 0.375)
        facts["overflow-birth-does-not-remove-the-healthy-sibling"] =
            state(accepted, layerID: 20, childPath: "values-overflow") == nil
            && batch(batches, "values-overflow") == nil
            && state(accepted, layerID: 20, childPath: "values-healthy")?.size == 6
            && state(accepted, layerID: 20, childPath: "values-healthy")?.alpha == 0.75
            && matches(batch(batches, "values-healthy"), halfSize: 3, alpha: 0.75)
        let inherited = frames(accepted, layerID: 20).filter {
            $0.simulatorFrame.particles.first?.initialSize == 60
        }
        facts["child-context-and-birth-initials-store-the-actual-event-values"] =
            !inherited.isEmpty && inherited.allSatisfy {
                $0.simulatorFrame.eventValueContext == .snapshot(.init(color: SIMD3(0.2, 0.4, 0.6), size: 30, alpha: 0.5))
                    && $0.simulatorFrame.particles.first?.initialAlpha == 0.5
            }
        var observed: [String: Any] = ["cpuChildValues": frames(accepted, layerID: 20).map {
            ["templateIndex": $0.templateIndex, "values": $0.simulatorFrame.particles.map {
                [$0.size, $0.alpha, $0.color.x, $0.color.y, $0.color.z]
            }] as [String: Any]
        }, "batchValues": batches.map {
            ["path": $0.particlePath, "values": $0.instances.map {
                [$0.positionAndSize.w, $0.rotationAndAlpha.w, $0.colorAndFrameMix.x,
                 $0.colorAndFrameMix.y, $0.colorAndFrameMix.z]
            }] as [String: Any]
        }]
#if DEBUG
        let evaluations = runtime.consumeComponentObservations()
        facts["eventValueDebugWitness"] = evaluations.contains {
            $0.particlePath == "particles/values-child.json" && $0.evaluation.category == "initializer"
                && $0.evaluation.stage == "evaluated" && $0.evaluation.reason == "event-value-applied"
        } && evaluations.contains {
            $0.particlePath == "particles/values-bad.json" && $0.evaluation.category == "initializer"
                && $0.evaluation.stage == "unavailable"
        }
        observed["eventValueDiagnostics"] = evaluations.filter {
            $0.particlePath.contains("values-") && $0.evaluation.category == "initializer"
        }.map { ["path": $0.particlePath, "index": $0.evaluation.componentIndex,
                 "stage": $0.evaluation.stage, "reason": $0.evaluation.reason] as [String: Any] }
#endif
        runtime.restoreFrame(before)
        _ = runtime.advance(by: 1.0 / 60)
        let replayBatches = runtime.advance(by: 1.0 / 60)
        let replay = runtime.frameSnapshot()
        let expectedSystems = frames(accepted, layerID: 20), replaySystems = frames(replay, layerID: 20)
        facts["snapshot-retry-restores-event-values-particles-rng-and-identities"] =
            expectedSystems.count == replaySystems.count && zip(expectedSystems, replaySystems).allSatisfy { left, right in
                left.id == right.id && left.simulatorFrame.particles == right.simulatorFrame.particles
                    && left.simulatorFrame.random.state == right.simulatorFrame.random.state
                    && left.simulatorFrame.nextParticleID == right.simulatorFrame.nextParticleID
                    && left.simulatorFrame.eventValueContext == right.simulatorFrame.eventValueContext
            } && state(replay, layerID: 20, childPath: "values-child")?.size == 60
            && matches(batch(replayBatches, "values-child"), halfSize: 30, alpha: 0.5)
        return ["facts": facts, "observed": observed]
    }

    static func syntheticEventFollow() throws -> [String: Any] {
        setenv("MWX_SCENE_PARTICLE_COMPONENT_OBSERVATION", "1", 1)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-follow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/follow-root.json", material: "materials/shared.json",
            velocityX: 60, lifetime: 4.0 / 60.0, moves: true, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/follow-child.json", "type": "eventfollow", "maxcount": 1,
                "scale": "2.5 2.5 1",
            ]], under: directory
        )
        try writeParticle(
            "particles/follow-child.json", material: "materials/shared.json",
            flags: 1, rate: 60, under: directory
        )
        try writeParticle(
            "particles/bounded-root.json", material: "materials/shared.json",
            lifetime: 1.0 / 60.0, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/bounded-child.json", "type": "eventspawn",
                "scale": "0.2 0.2 0.2",
            ]], under: directory
        )
        try writeParticle(
            "particles/bounded-child.json", material: "materials/shared.json",
            lifetime: 2.0 / 60.0, rate: 60, emitterDuration: 3.0 / 60.0, under: directory
        )
        try writeParticle(
            "particles/budget-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 100,
            children: [[
                "name": "particles/budget-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/budget-child.json", material: "materials/shared.json",
            rate: 60, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/audio-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/audio-child.json", "type": "eventspawn",
            ], [
                "name": "particles/audio-operator-child.json", "type": "static",
            ]], under: directory
        )
        try writeParticle(
            "particles/audio-child.json", material: "materials/shared.json",
            rate: 60, audioProcessingMode: 1, under: directory
        )
        try writeParticle(
            "particles/audio-operator-child.json", material: "materials/shared.json",
            rate: 0, operatorAudioProcessingMode: 1, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/audio-churn-root.json", material: "materials/shared.json",
            lifetime: 1.0 / 60.0, rate: 60,
            children: [[
                "name": "particles/audio-churn-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/audio-churn-child.json", material: "materials/shared.json",
            rate: 0, operatorAudioProcessingMode: 1, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/window-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/window-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/window-child.json", material: "materials/shared.json",
            lifetime: 2.0 / 60.0, rate: 60, under: directory
        )
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1, "max": 1],
                ["name": "colorrandom", "min": "255 255 255", "max": "255 255 255"],
            ],
            "operator": [[
                "name": "colorchange", "starttime": 0, "endtime": 1,
                "startvalue": "1 1 1", "endvalue": "0 0 1",
            ]],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/inherit-follow-child.json", "type": "eventfollow",
            ]],
        ], to: directory.appendingPathComponent("particles/inherit-follow-root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "operator": [["name": "inheritvaluefromevent"]],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/inherit-follow-child.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1.0 / 60.0, "max": 1.0 / 60.0],
                ["name": "colorrandom", "min": "51 102 153", "max": "51 102 153"],
            ],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/inherit-death-child.json", "type": "eventdeath",
            ]],
        ], to: directory.appendingPathComponent("particles/inherit-death-root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1, "max": 1],
                ["name": "inheritinitialvaluefromevent"],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/inherit-death-child.json"))
        for (path, component): (String, [String: Any]) in [
            ("particles/invalid-inherit-static.json", ["name": "inheritinitialvaluefromevent"]),
            ("particles/invalid-inherit-death.json", ["name": "inheritvaluefromevent"]),
            ("particles/invalid-inherit-follow.json", [
                "name": "inheritvaluefromevent", "input": "setsize",
            ]),
        ] {
            var initializers: [[String: Any]] = [
                ["name": "lifetimerandom", "min": 1, "max": 1],
            ]
            var operators: [[String: Any]] = []
            if component["name"] as? String == "inheritinitialvaluefromevent" {
                initializers.append(component)
            } else {
                operators.append(component)
            }
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 1,
                "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
                "initializer": initializers,
                "operator": operators,
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeParticle(
            "particles/invalid-inherit-root.json", material: "materials/shared.json",
            lifetime: 3.0 / 60.0, rate: 0, instantaneous: 1,
            children: [
                ["name": "particles/invalid-inherit-static.json", "type": "static"],
                ["name": "particles/invalid-inherit-death.json", "type": "eventdeath"],
                ["name": "particles/invalid-inherit-follow.json", "type": "eventfollow"],
            ], under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(10, "particles/follow-root.json"),
                layer(11, "particles/bounded-root.json"),
                layer(12, "particles/budget-root.json"),
                layer(13, "particles/audio-root.json"),
                layer(14, "particles/window-root.json"),
                layer(15, "particles/inherit-follow-root.json"),
                layer(16, "particles/inherit-death-root.json"),
                layer(17, "particles/invalid-inherit-root.json"),
            ],
            renderOrderLayerIDs: [10, 11, 12, 13, 14, 15, 16, 17],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let activeAudioRuntime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let activeAudioInput = SceneParticleAudioInput(
            left: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            right: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            generation: 7
        )
        for _ in 0..<2 {
            _ = activeAudioRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        }
        let activeChildAudioInput = activeAudioRuntime.frameSnapshot().layers
            .compactMap { $0.child?.systems.first?.simulatorFrame.audioInput.left.first }
            .first ?? 0
        let churnDescriptor = SceneRenderDescriptor(
            layers: [layer(18, "particles/audio-churn-root.json")],
            renderOrderLayerIDs: [18],
            materialPasses: descriptor.materialPasses
        )
        let churnRuntime = SceneParticleRuntime(
            descriptor: churnDescriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        let churnRollbackSnapshot = churnRuntime.frameSnapshot()
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
#if DEBUG
        let rejectedChurnObservations = churnRuntime.consumeAudioEvaluationObservations()
#endif
        churnRuntime.restoreFrame(churnRollbackSnapshot)
#if DEBUG
        let churnObservationsAfterRestore = churnRuntime
            .consumeAudioEvaluationObservations()
#endif
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
#if DEBUG
        let retryChurnObservations = churnRuntime.consumeAudioEvaluationObservations()
        var laterChurnObservationCount = 0
#endif
        for _ in 0..<6 {
            _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
#if DEBUG
            laterChurnObservationCount += churnRuntime
                .consumeAudioEvaluationObservations().count
#endif
        }
        var childCounts: [Int] = []
        var childPositions: [Float] = []
        var childSizes: [Float] = []
        var boundedCounts: [Int] = []
        var boundedSizes: [Float] = []
        var budgetCounts: [Int] = []
        var windowCounts: [Int] = []
        var inheritedFollowMatches: [Bool] = []
        var inheritedDeathColors: [[Float]] = []
        var localFallbackPaths: Set<String> = []
        for _ in 0..<6 {
            let batches = runtime.advance(by: 1.0 / 60.0)
            for batch in batches where batch.particlePath.hasPrefix("particles/invalid-inherit-")
                && !batch.particlePath.hasSuffix("root.json") && !batch.instances.isEmpty {
                localFallbackPaths.insert(batch.particlePath)
            }
            let instances = batches.first {
                $0.particlePath == "particles/follow-child.json"
            }?.instances ?? []
            childCounts.append(instances.count)
            if let position = instances.first?.positionAndSize.x {
                childPositions.append(position)
            }
            if let size = instances.first?.positionAndSize.w {
                childSizes.append(size)
            }
            let boundedInstances = batches.first {
                $0.particlePath == "particles/bounded-child.json"
            }?.instances ?? []
            boundedCounts.append(boundedInstances.count)
            if let size = boundedInstances.first?.positionAndSize.w {
                boundedSizes.append(size)
            }
            budgetCounts.append(batches.first {
                $0.particlePath == "particles/budget-child.json"
            }?.instances.count ?? 0)
            windowCounts.append(batches.first {
                $0.particlePath == "particles/window-child.json"
            }?.instances.count ?? 0)
            let followRootColor = batches.first {
                $0.particlePath == "particles/inherit-follow-root.json"
            }?.instances.first?.colorAndFrameMix
            let followChildColor = batches.first {
                $0.particlePath == "particles/inherit-follow-child.json"
            }?.instances.first?.colorAndFrameMix
            if let root = followRootColor, let child = followChildColor {
                inheritedFollowMatches.append(
                    abs(root.x - child.x) < 1e-6 && abs(root.y - child.y) < 1e-6
                        && abs(root.z - child.z) < 1e-6
                )
            }
            if let color = batches.first(where: {
                $0.particlePath == "particles/inherit-death-child.json"
            })?.instances.first?.colorAndFrameMix {
                inheritedDeathColors.append([color.x, color.y, color.z])
            }
        }
        var facts3: [String: Any] = [
            "windowCounts": windowCounts,
            "childCounts": childCounts,
            "childPositions": childPositions,
            "childSizes": childSizes,
            "boundedCounts": boundedCounts,
            "boundedSizes": boundedSizes,
            "budgetCounts": budgetCounts,
            "inheritedFollowMatches": inheritedFollowMatches,
            "inheritedDeathColors": inheritedDeathColors,
            "eventValueLocalFallbackPaths": localFallbackPaths.sorted(),
            "eventValues": try eventValueBehavior(directory: directory, device: device,
                                                  materialPasses: descriptor.materialPasses),
            "childOptions": try childOptionBehavior(directory: directory, device: device,
                                                    materialPasses: descriptor.materialPasses),
            "hasAudioConsumer": runtime.hasAudioConsumer,
            "activeChildAudioInput": activeChildAudioInput,
        ]
#if DEBUG
        facts3["rejectedChurnObservationCount"] = rejectedChurnObservations.count
        facts3["churnObservationsAfterRestore"] = churnObservationsAfterRestore.count
        facts3["retryChurnObservationCount"] = retryChurnObservations.count
        facts3["retryChurnObservationPaths"] = retryChurnObservations.map(\.particlePath)
        facts3["laterChurnObservationCount"] = laterChurnObservationCount
        facts3["childUnsupportedLayers"] = runtime.diagnostics.compactMap {
            $0.kind == .childSystemsUnsupported && ![13, 17].contains($0.layerID)
                ? $0.layerID : nil
        }
        facts3["budgetDetails"] = runtime.diagnostics.compactMap {
            $0.layerID == 12 && $0.kind == .simulationLimitation ? $0.detail : nil
        }
        facts3["audioChildDetails"] = runtime.diagnostics.compactMap {
            $0.layerID == 13 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
        }
        facts3["childScaleDetails"] = runtime.diagnostics.compactMap {
            $0.kind == .simulationLimitation && $0.detail?.contains("childScaleBounded") == true
                ? $0.detail : nil
        }
#endif
        return facts3
    }

}
