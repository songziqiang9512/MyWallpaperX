import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func syntheticChildCapacity() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-child-capacity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func particle(_ name: String, maximum: Int, burst: Int, lifetime: Double = 10,
                      rate: Double = 0, startTime: Double = 0, children: [[String: Any]] = []) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": maximum, "starttime": startTime,
                "emitter": [["name": "sphererandom", "rate": rate,
                    "instantaneous": burst, "distancemin": 0, "distancemax": 0]],
                "initializer": [["name": "lifetimerandom", "min": lifetime, "max": lifetime],
                    ["name": "sizerandom", "min": 4, "max": 4]],
                "renderer": [["name": "sprite"]], "children": children,
            ], to: directory.appendingPathComponent("particles/\(name).json"))
        }
        func child(_ name: String, _ trigger: String = "static") -> [String: Any] {
            ["name": "particles/\(name).json", "type": trigger]
        }
        try particle("dense", maximum: 20000, burst: 8500)
        try particle("warm", maximum: 20000, burst: 8500, startTime: 0.1)
        try particle("prewarm", maximum: 1, burst: 0, children: [child("warm")])
        try particle("large", maximum: 20000, burst: 20000)
        try particle("small", maximum: 5536, burst: 5536)
        try particle("short", maximum: 20000, burst: 8500, lifetime: 1.0 / 60.0)
        try particle("single", maximum: 1, burst: 0, children: [child("dense")])
        try particle("static", maximum: 1, burst: 0,
                     children: Array(repeating: child("large"), count: 65) + [child("small")])
        for trigger in ["eventspawn", "eventdeath", "eventfollow"] {
            try particle(trigger, maximum: 4, burst: 4,
                         lifetime: trigger == "eventdeath" ? 1.0 / 60.0 : 10,
                         children: [child("large", trigger)])
        }
        try particle("head", maximum: 4, burst: 4, children: [child("large", "eventspawn")])
        try particle("nested", maximum: 1, burst: 0,
                     children: [child("head"), child("large"), child("large"), child("large")])
        try particle("recycle", maximum: 16, burst: 4, rate: 60,
                     children: [child("short", "eventspawn")])
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/shared.json", shaderPath: "genericparticle",
            texturePaths: ["shared.png"], blending: "additive")
        func runtime(_ name: String) -> SceneParticleRuntime {
            SceneParticleRuntime(descriptor: SceneRenderDescriptor(
                layers: [layer(970, "particles/\(name).json")], renderOrderLayerIDs: [970],
                materialPasses: [pass]), cacheDirectory: directory, device: device)
        }
        func count(_ batches: [SceneParticleDrawBatch], path: String) -> Int {
            batches.filter { $0.particlePath == "particles/\(path).json" }
                .reduce(0) { $0 + $1.instances.count }
        }
        var output: [String: Any] = [:]
        for name in ["single", "prewarm", "static", "eventspawn", "eventdeath", "eventfollow", "nested"] {
            let value = runtime(name)
            var peak = 0
            for _ in 0..<4 {
                let batches = value.advance(by: 1.0 / 60.0)
                if name == "static" { output["smallPeer"] = count(batches, path: "small") }
                peak = max(peak, count(batches, path: name == "single" ? "dense" : (name == "prewarm" ? "warm" : "large"))
                    + (name == "static" ? count(batches, path: "small") : 0))
            }
            output[name] = peak
            output[name + "Diagnostics"] = value.diagnostics.compactMap {
                $0.kind == .simulationLimitation ? $0.detail : nil
            }
            let systems = value.frameSnapshot().layers.first?.child?.systems ?? []
            output[name + "Capacity"] = [1, 2].map { depth in
                systems.filter { $0.depth == depth }.reduce(0) { $0 + $1.simulator.maximumParticleCount }
            }
        }
        let retry = runtime("recycle")
        _ = retry.advance(by: 1.0 / 60.0)
        let before = retry.frameSnapshot()
        var firstCounts: [Int] = []
        var allocations: [[Int]] = []
        for _ in 0..<5 {
            firstCounts.append(count(retry.advance(by: 1.0 / 60.0), path: "short"))
            let systems = retry.frameSnapshot().layers.first!.child!.systems
            allocations.append([systems.count, systems.reduce(0) { $0 + $1.simulator.maximumParticleCount }])
        }
        output["recycleAllocations"] = allocations
        let firstState = retry.frameSnapshot().layers.first!.child!
        let firstIDs = firstState.systems.map(\.id)
        retry.restoreFrame(before)
        var replayCounts: [Int] = []
        for _ in 0..<5 { replayCounts.append(count(retry.advance(by: 1.0 / 60.0), path: "short")) }
        let replayState = retry.frameSnapshot().layers.first!.child!
        output["identityReplay"] = firstIDs == replayState.systems.map(\.id)
            && firstState.nextSeed == replayState.nextSeed
            && firstState.nextSystemID == replayState.nextSystemID
        output["recycle"] = firstCounts
        output["replay"] = replayCounts
        return output
    }

    static func syntheticSubframeChildLifecycle() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-subframe-child-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))

        func writeShortParticle(
            _ path: String,
            flags: Int = 0,
            children: [[String: Any]] = []
        ) throws {
            var root: [String: Any] = [
                "material": "materials/shared.json", "maxcount": 8,
                "flags": flags,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 0.0004, "max": 0.0004],
                    ["name": "sizerandom", "min": 4, "max": 4],
                ],
                "renderer": [["name": "sprite"]],
            ]
            if !children.isEmpty { root["children"] = children }
            try writeJSON(root, to: directory.appendingPathComponent(path))
        }

        try writeShortParticle("particles/static-world.json", flags: 1)
        try writeShortParticle("particles/spawn-leaf.json")
        try writeShortParticle("particles/death-leaf.json")
        try writeShortParticle("particles/nested-leaf.json")
        try writeShortParticle(
            "particles/spawn-parent.json",
            children: [[
                "name": "particles/nested-leaf.json", "type": "eventspawn",
                "maxcount": 1,
            ]]
        )

        func writeRoot(_ path: String, child: [String: Any]) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 8,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [[
                    "name": "lifetimerandom", "min": 0.0004, "max": 0.0004,
                ]],
                "renderer": [["name": "sprite"]],
                "children": [child],
            ], to: directory.appendingPathComponent(path))
        }
        try writeRoot("particles/root-static.json", child: [
            "name": "particles/static-world.json", "type": "static",
            "origin": "7 9 0", "maxcount": 1,
        ])
        try writeRoot("particles/root-spawn.json", child: [
            "name": "particles/spawn-leaf.json", "type": "eventspawn", "maxcount": 1,
        ])
        try writeRoot("particles/root-death.json", child: [
            "name": "particles/death-leaf.json", "type": "eventdeath", "maxcount": 1,
        ])
        try writeRoot("particles/root-depth-two.json", child: [
            "name": "particles/spawn-parent.json", "type": "eventspawn", "maxcount": 1,
        ])
        func writeRepeatingRoot(_ path: String, child: [String: Any]) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 16,
                "emitter": [[
                    "name": "sphererandom", "rate": 60,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [[
                    "name": "lifetimerandom", "min": 10, "max": 10,
                ]],
                "renderer": [["name": "sprite"]],
                "children": [child],
            ], to: directory.appendingPathComponent(path))
        }
        try writeRepeatingRoot("particles/root-replace-depth-one.json", child: [
            "name": "particles/spawn-leaf.json", "type": "eventspawn", "maxcount": 1,
        ])
        try writeRepeatingRoot("particles/root-replace-depth-two.json", child: [
            "name": "particles/spawn-parent.json", "type": "eventspawn", "maxcount": 1,
        ])

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/shared.json",
            shaderPath: "genericparticle",
            texturePaths: ["shared.png"],
            blending: "additive"
        )
        func runtime(_ id: Int, _ path: String) -> SceneParticleRuntime {
            SceneParticleRuntime(
                descriptor: SceneRenderDescriptor(
                    layers: [layer(id, path)],
                    renderOrderLayerIDs: [id],
                    materialPasses: [pass]
                ),
                cacheDirectory: directory,
                device: device
            )
        }
        func instances(
            _ batches: [SceneParticleDrawBatch], path: String
        ) -> [SceneParticleGPUInstance] {
            batches.first { $0.particlePath == path }?.instances ?? []
        }
        func childInstanceTotal(_ batches: [SceneParticleDrawBatch]) -> Int {
            batches.filter { $0.particlePath != "particles/root-static.json"
                && $0.particlePath != "particles/root-spawn.json"
                && $0.particlePath != "particles/root-death.json"
                && $0.particlePath != "particles/root-depth-two.json"
            }.reduce(0) { $0 + $1.instances.count }
        }

        let staticRuntime = runtime(991, "particles/root-static.json")
        let staticFirst = staticRuntime.advance(by: 1.0 / 60.0)
        let staticFirstLifecycle = staticRuntime.lifecycleSnapshot
        let staticSecond = staticRuntime.advance(by: 1.0 / 60.0)
        let staticInstances = instances(staticFirst, path: "particles/static-world.json")

        let spawnRuntime = runtime(992, "particles/root-spawn.json")
        _ = spawnRuntime.advance(by: 1.0 / 60.0)
        let spawnSecond = spawnRuntime.advance(by: 1.0 / 60.0)
        let spawnSecondLifecycle = spawnRuntime.lifecycleSnapshot
        let spawnThird = spawnRuntime.advance(by: 1.0 / 60.0)

        let deathRuntime = runtime(993, "particles/root-death.json")
        _ = deathRuntime.advance(by: 1.0 / 60.0)
        let deathSecond = deathRuntime.advance(by: 1.0 / 60.0)
        let deathSecondLifecycle = deathRuntime.lifecycleSnapshot
        let deathThird = deathRuntime.advance(by: 1.0 / 60.0)

        let depthRuntime = runtime(994, "particles/root-depth-two.json")
        _ = depthRuntime.advance(by: 1.0 / 60.0)
        let depthSecond = depthRuntime.advance(by: 1.0 / 60.0)
        let depthSecondLifecycle = depthRuntime.lifecycleSnapshot
        let depthThird = depthRuntime.advance(by: 1.0 / 60.0)
        let depthThirdLifecycle = depthRuntime.lifecycleSnapshot
        let depthFourth = depthRuntime.advance(by: 1.0 / 60.0)

        let replacementRuntime = runtime(995, "particles/root-replace-depth-one.json")
        _ = replacementRuntime.advance(by: 1.0 / 60.0)
        let replacementSecond = replacementRuntime.advance(by: 1.0 / 60.0)
        let replacementSecondLifecycle = replacementRuntime.lifecycleSnapshot
        let replacementThird = replacementRuntime.advance(by: 1.0 / 60.0)
        let replacementThirdLifecycle = replacementRuntime.lifecycleSnapshot

        let nestedReplacementRuntime = runtime(996, "particles/root-replace-depth-two.json")
        _ = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        _ = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        let nestedReplacementThird = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        let nestedReplacementThirdLifecycle = nestedReplacementRuntime.lifecycleSnapshot
        let nestedReplacementFourth = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        let nestedReplacementFourthLifecycle = nestedReplacementRuntime.lifecycleSnapshot

        return [
            "staticCount": staticInstances.count,
            "staticPosition": staticInstances.first.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "staticLifecycleSystems": staticFirstLifecycle.childSystemCount,
            "staticLifecycleParticles": staticFirstLifecycle.childParticleCount,
            "staticNextCount": childInstanceTotal(staticSecond),
            "spawnCount": instances(spawnSecond, path: "particles/spawn-leaf.json").count,
            "spawnLifecycleSystems": spawnSecondLifecycle.childSystemCount,
            "spawnLifecycleParticles": spawnSecondLifecycle.childParticleCount,
            "spawnNextCount": childInstanceTotal(spawnThird),
            "deathCount": instances(deathSecond, path: "particles/death-leaf.json").count,
            "deathLifecycleSystems": deathSecondLifecycle.childSystemCount,
            "deathLifecycleParticles": deathSecondLifecycle.childParticleCount,
            "deathNextCount": childInstanceTotal(deathThird),
            "depthOneCount": instances(
                depthSecond, path: "particles/spawn-parent.json"
            ).count,
            "depthOneRemainingSystems": depthSecondLifecycle.childSystemCount,
            "depthTwoCount": instances(
                depthThird, path: "particles/nested-leaf.json"
            ).count,
            "depthTwoLifecycleSystems": depthThirdLifecycle.childSystemCount,
            "depthTwoLifecycleParticles": depthThirdLifecycle.childParticleCount,
            "depthTwoNextCount": childInstanceTotal(depthFourth),
            "replacementSecondCount": instances(
                replacementSecond, path: "particles/spawn-leaf.json"
            ).count,
            "replacementSecondSystems": replacementSecondLifecycle.childSystemCount,
            "replacementThirdCount": instances(
                replacementThird, path: "particles/spawn-leaf.json"
            ).count,
            "replacementThirdSystems": replacementThirdLifecycle.childSystemCount,
            "nestedReplacementThirdCount": instances(
                nestedReplacementThird, path: "particles/nested-leaf.json"
            ).count,
            "nestedReplacementThirdSystems": nestedReplacementThirdLifecycle.childSystemCount,
            "nestedReplacementFourthCount": instances(
                nestedReplacementFourth, path: "particles/nested-leaf.json"
            ).count,
            "nestedReplacementFourthSystems": nestedReplacementFourthLifecycle.childSystemCount,
        ]
    }

    static func syntheticChildFloatSafety() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-child-float-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        try writeParticle("particles/child.json", material: "materials/shared.json",
            rate: 60, under: directory)
        try writeParticle("particles/root.json", material: "materials/shared.json",
            flags: 248, rate: 60, children: [["name": "particles/child.json",
                "type": "static", "scale": "1024 1024 1"]], under: directory)
        let runtime = SceneParticleRuntime(descriptor: .init(
            layers: [layer(91, "particles/root.json", particleSize: 1)],
            renderOrderLayerIDs: [91], materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive")]),
            cacheDirectory: directory, device: device)
        let target = SceneDynamicTarget.particle(layerID: 91, field: .size)
        let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: [.init(target: target, valueType: .scalar, authoredValue: .scalar(1))],
            userValues: [target: .scalar(1e35)]).snapshot
        _ = runtime.advance(by: 1.0 / 60)
        let batches = runtime.advance(by: 1.0 / 60, dynamicValues: dynamic)
        let child = batches.first { $0.particlePath == "particles/child.json" }!
        let unsafeCount = child.instances.filter { !$0.positionAndSize.w.isFinite }.count
        batches.forEach { _ = $0.instanceBuffer.update(device: device, instances: $0.instances) }
        let rootCount = batches.first { $0.particlePath == "particles/root.json" }!.instanceBuffer.count
        let safeCount = child.instanceBuffer.count
        let uploaded = child.instanceBuffer.buffer!.contents()
            .bindMemory(to: SceneParticleGPUInstance.self, capacity: safeCount)
        let finite = (0..<safeCount).allSatisfy { uploaded[$0].positionAndSize.w.isFinite }
        let next = runtime.advance(by: 1.0 / 60)
        next.forEach { _ = $0.instanceBuffer.update(device: device, instances: $0.instances) }
        let recovered = next.first { $0.particlePath == "particles/child.json" }!.instanceBuffer.count
        // Exercise every final ABI lane, with valid peers on either side.
        let peer = SceneParticleGPUInstance(position: .zero, size: 8, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1)
        let buffer = SceneParticleMetalInstanceBuffer()
        var following = peer; following.positionAndSize.x = 7
        var rejected = 0
        for lane in 0..<40 {
            var invalid = peer
            withUnsafeMutableBytes(of: &invalid) { bytes in
                bytes.bindMemory(to: Float.self)[lane] = lane % 2 == 0 ? .infinity : .nan
            }
            _ = buffer.update(device: device, instances: [peer, invalid, following])
            let records = buffer.buffer!.contents()
                .bindMemory(to: SceneParticleGPUInstance.self, capacity: 3)
            if buffer.count == 2 && records[0].positionAndSize.x == 0
                && records[1].positionAndSize.x == 7 { rejected += 1 }
        }
        var invalid = peer; invalid.positionAndSize.x = .infinity
        _ = buffer.update(device: device, instances: [invalid])
        let emptyDraw = buffer.currentDrawState() == nil
        _ = buffer.update(device: device, instances: [peer])
        return ["unsafeAssembled": unsafeCount, "uploadedCount": safeCount,
            "uploadedFinite": finite, "rootCount": rootCount, "recoveredCount": recovered,
            "rejectedLanes": rejected, "emptyDraw": emptyDraw, "recoveredBuffer": buffer.count]
    }

    static func syntheticChildInstanceOverride() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-child-modifiers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let alpha = SceneDynamicTarget.particle(layerID: 91, field: .alpha)
        let size = SceneDynamicTarget.particle(layerID: 91, field: .size)
        let count = SceneDynamicTarget.particle(layerID: 91, field: .count)
        let rate = SceneDynamicTarget.particle(layerID: 91, field: .rate)
        let lifetime = SceneDynamicTarget.particle(layerID: 91, field: .lifetime)
        let speed = SceneDynamicTarget.particle(layerID: 91, field: .speed)
        let brightness = SceneDynamicTarget.particle(layerID: 91, field: .brightness)
        let color = SceneDynamicTarget.particle(layerID: 91, field: .normalizedColor)
        let values: [SceneDynamicTarget: SceneDynamicValue] = [alpha: .scalar(0.25),
            size: .scalar(3), count: .scalar(2), rate: .scalar(0.5), lifetime: .scalar(2),
            speed: .scalar(3), brightness: .scalar(0.5), color: .vector3(0.5, 1, 0.25)]
        let definitions = values.keys.map { target in
            SceneDynamicTargetDefinition(target: target,
                valueType: target == color ? .vector3 : .scalar,
                authoredValue: target == color ? .vector3(1, 1, 1) : .scalar(1))
        }
        let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: definitions, userValues: values).snapshot
        func child(_ path: String, _ trigger: String = "static") -> [String: Any] {
            ["name": "particles/\(path).json", "type": trigger]
        }
        func make(_ trigger: String = "static", flags: Int = 0, warm: Bool = false,
                  nested: Bool = false, container: Bool = false, continuous: Bool = false,
                  initial: SceneDynamicSnapshot = .empty(frameIndex: 0)) throws -> SceneParticleRuntime {
            try writeParticle("particles/child.json", material: "materials/shared.json",
                flags: flags, velocityX: 2, lifetime: 10, startTime: warm ? 0.1 : 0,
                rate: continuous ? 60 : 0, instantaneous: continuous ? 0 : 2, under: directory)
            if nested {
                try writeParticle("particles/middle.json", material: "materials/shared.json",
                    lifetime: trigger == "eventdeath" ? 1.0 / 60 : 10,
                    rate: 0, instantaneous: 1, children: [child("child", trigger)], under: directory)
            }
            try writeParticle("particles/root.json", material: "materials/shared.json",
                flags: 248, lifetime: trigger == "eventdeath" ? 1.0 / 60 : 10,
                rate: 0, instantaneous: 1,
                children: [child(nested ? "middle" : "child", nested ? "static" : trigger)], under: directory)
            if container {
                let url = directory.appendingPathComponent("particles/root.json")
                var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
                json["renderer"] = []; json["emitter"] = []; json["initializer"] = []
                try writeJSON(json, to: url)
            }
            return SceneParticleRuntime(descriptor: .init(layers: [layer(91, "particles/root.json",
                particleAlpha: 0.4, particleSize: 2, particleLifetime: 1.5, particleRate: 1,
                particleCount: 1, particleNormalizedColor: SIMD3(1, 0.5, 1))],
                renderOrderLayerIDs: [91], materialPasses: [.init(
                    materialPath: "materials/shared.json", shaderPath: "genericparticle",
                    texturePaths: ["shared.png"], blending: "additive")]),
                cacheDirectory: directory, device: device, initialDynamicValues: initial)
        }
        func observe(_ runtime: SceneParticleRuntime, _ batches: [SceneParticleDrawBatch]) -> [String: Any] {
            let instances = batches.filter { $0.particlePath == "particles/child.json" }.flatMap(\.instances)
            let systems = runtime.frameSnapshot().layers.first?.child?.systems ?? []
            let system = systems.last
            let particle = system?.simulator.particles.first
            let item = instances.first
            return ["count": instances.count, "alpha": item?.rotationAndAlpha.w ?? -1,
                "size": item?.positionAndSize.w ?? -1,
                "color": item.map { [$0.colorAndFrameMix.x, $0.colorAndFrameMix.y, $0.colorAndFrameMix.z] } ?? [],
                "lifetime": particle?.lifetime ?? -1, "velocity": particle?.velocity.x ?? -1,
                "simulationTime": system?.simulator.simulationTime ?? -1]
        }
        var result: [String: Any] = [:]
        for (name, flags) in [("static", 0), ("disabled", 248)] {
            let runtime = try make(flags: flags)
            result[name] = observe(runtime, runtime.advance(by: 0.1))
            let replay = try make(flags: flags)
            let saved = replay.frameSnapshot()
            let batches = replay.advance(by: 0.1, dynamicValues: dynamic)
            let output = observe(replay, batches)
            result[name + "Dynamic"] = output
            replay.restoreFrame(saved)
            let retry = observe(replay, replay.advance(by: 0.1, dynamicValues: dynamic))
            result[name + "RetryEqual"] = NSDictionary(dictionary: output).isEqual(to: retry)
            replay.restoreFrame(saved)
            result[name + "Fallback"] = observe(replay, replay.advance(by: 0.1))
        }
        for flags in [0, 248] {
            let continuous = try make(flags: flags, continuous: true)
            result["continuous" + String(flags)] = observe(continuous,
                continuous.advance(by: 0.1, dynamicValues: dynamic))
        }
        let warm = try make(warm: true, initial: dynamic)
        result["prewarm"] = observe(warm, warm.advance(by: 0, dynamicValues: dynamic))
        let container = try make(container: true)
        result["container"] = observe(container, container.advance(by: 0.1, dynamicValues: dynamic))
        for trigger in ["eventspawn", "eventdeath", "eventfollow"] {
            for nested in [false, true] {
                let runtime = try make(trigger, warm: true, nested: nested)
                var batches: [SceneParticleDrawBatch] = []
                for _ in 0..<6 { batches = runtime.advance(by: 1.0 / 60, dynamicValues: dynamic) }
                result[trigger + (nested ? "Nested" : "")] = observe(runtime, batches)
            }
        }
        return result
    }

    static func syntheticNestedChildren() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-nested-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/nested-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/nested-head.json", "origin": "40 0 0"]],
            under: directory
        )
        try writeParticle(
            "particles/nested-head.json", material: "materials/shared.json",
            velocityX: 60, lifetime: 5.0 / 60.0, moves: true, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/nested-trail.json", "type": "eventfollow", "maxcount": 1,
            ]], under: directory
        )
        try writeParticle(
            "particles/nested-trail.json", material: "materials/shared.json",
            rate: 60, under: directory
        )
        try writeParticle(
            "particles/depth-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/depth-two.json", "type": "eventfollow"]],
            under: directory
        )
        try writeParticle(
            "particles/depth-two.json", material: "materials/shared.json",
            rate: 60,
            children: [["name": "particles/depth-three.json", "type": "eventfollow"]],
            under: directory
        )
        try writeParticle(
            "particles/depth-three.json", material: "materials/shared.json",
            rate: 60,
            children: [["name": "particles/depth-four.json", "type": "eventfollow"]],
            under: directory
        )
        try writeParticle(
            "particles/depth-four.json", material: "materials/shared.json",
            rate: 60, under: directory
        )
        try writeParticle(
            "particles/static-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/static-mid.json"]], under: directory
        )
        try writeParticle(
            "particles/static-mid.json", material: "materials/shared.json",
            rate: 60,
            children: [["name": "particles/static-leaf.json", "type": "static"]],
            under: directory
        )
        try writeParticle(
            "particles/static-leaf.json", material: "materials/shared.json",
            rate: 60, under: directory
        )
        try writeParticle(
            "particles/budget-nested-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/budget-nested-head.json"]], under: directory
        )
        try writeParticle(
            "particles/budget-nested-head.json", material: "materials/shared.json",
            rate: 0, instantaneous: 80,
            children: [[
                "name": "particles/budget-nested-trail.json", "type": "eventfollow",
                "maxcount": 512,
            ]], under: directory
        )
        try writeParticle(
            "particles/budget-nested-trail.json", material: "materials/shared.json",
            rate: 60, under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(20, "particles/nested-root.json"),
                layer(21, "particles/depth-root.json"),
                layer(22, "particles/static-root.json"),
                layer(23, "particles/budget-nested-root.json"),
            ],
            renderOrderLayerIDs: [20, 21, 22, 23],
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
        var trailCounts: [Int] = []
        var trailOrigins: [Float] = []
        var headPositions: [Float] = []
        var budgetTrailCounts: [Int] = []
        for _ in 0..<6 {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let trail = batches.first {
                $0.particlePath == "particles/nested-trail.json"
            }?.instances ?? []
            trailCounts.append(trail.count)
            if let first = trail.first { trailOrigins.append(first.positionAndSize.x) }
            let head = batches.first {
                $0.particlePath == "particles/nested-head.json"
            }?.instances ?? []
            if let first = head.first { headPositions.append(first.positionAndSize.x) }
            budgetTrailCounts.append(batches.first {
                $0.particlePath == "particles/budget-nested-trail.json"
            }?.instances.count ?? 0)
        }
        return [
            "trailCounts": trailCounts,
            "trailOrigins": trailOrigins,
            "headPositions": headPositions,
            "budgetTrailCounts": budgetTrailCounts,
            "depthDetails": runtime.diagnostics.compactMap {
                $0.layerID == 21 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "staticDetails": runtime.diagnostics.compactMap {
                $0.layerID == 22 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "budgetDetails": runtime.diagnostics.compactMap {
                $0.layerID == 23 && $0.kind == .simulationLimitation ? $0.detail : nil
            },
            "nestedUnsupportedLayers": runtime.diagnostics.compactMap {
                $0.kind == .childSystemsUnsupported && $0.layerID != 21 && $0.layerID != 22
                    ? $0.layerID : nil
            },
        ]
    }

    static func realNestedMatrix(
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
        for _ in 0..<4 { _ = runtime.advance(by: 1) }
        let batches = runtime.advance(by: 1.0 / 60.0)
        var headCount = 0
        var trailCount = 0
        var trailBatchCount = 0
        var headY: [Float] = []
        var headSize: [Float] = []
        var trailY: [Float] = []
        var trailSize: [Float] = []
        var trailVelocityY: [Float] = []
        for batch in batches {
            if batch.particlePath.hasSuffix("matrix_code_copy1.json") {
                headCount += batch.instances.count
                headY.append(contentsOf: batch.instances.map(\.positionAndSize.y))
                headSize.append(contentsOf: batch.instances.map(\.positionAndSize.w))
            }
            if batch.particlePath.hasSuffix("matrix_trail_copy1.json") {
                trailCount += batch.instances.count
                trailBatchCount += 1
                trailY.append(contentsOf: batch.instances.map(\.positionAndSize.y))
                trailSize.append(contentsOf: batch.instances.map(\.positionAndSize.w))
                trailVelocityY.append(contentsOf: batch.instances.map(\.velocityAndTrail.y))
            }
        }
        let staticRejections = runtime.diagnostics.filter {
            $0.kind == .childSystemsUnsupported
                && ($0.detail ?? "").contains("matrix_code_copy1.json")
        }
        return [
            "headCount": headCount,
            "trailCount": trailCount,
            "trailBatchCount": trailBatchCount,
            "headYRange": [headY.min() ?? 0, headY.max() ?? 0],
            "headSizeRange": [headSize.min() ?? 0, headSize.max() ?? 0],
            "trailYRange": [trailY.min() ?? 0, trailY.max() ?? 0],
            "trailSizeRange": [trailSize.min() ?? 0, trailSize.max() ?? 0],
            "trailVelocityYRange": [trailVelocityY.min() ?? 0, trailVelocityY.max() ?? 0],
            "staticRejections": staticRejections.count,
            "activeLayerIDs": runtime.activeLayerIDs,
            "nestedBudgetDetails": runtime.diagnostics.compactMap { value in
                (value.detail ?? "").contains("nestedAggregateSystemBudget")
                    ? (value.detail ?? "") : nil
            },
        ]
    }

    static func delayedChildren(edges: Bool = false) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mwx-child-delay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        let device = MTLCreateSystemDefaultDevice()!
        func make(_ trigger: String, continuous: Bool = false, duration: Double? = nil,
                  nested: Bool = false, warm: Double = 0, multiple: Bool = false,
                  delay: Any = 0.2, rate: Double = 60) throws -> SceneParticleRuntime {
            try writeParticle("particles/child.json", material: "materials/shared.json",
                lifetime: 0.1, startTime: warm, rate: continuous ? rate : 0,
                emitterDuration: duration, instantaneous: continuous ? nil : 1, under: directory)
            let url = directory.appendingPathComponent("particles/child.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            var emitters = json["emitter"] as! [[String: Any]]
            emitters[0]["delay"] = delay
            emitters[0]["origin"] = "30 0 0"
            if multiple { var early = emitters[0]; early["delay"] = 0; early["origin"] = "-30 0 0"; emitters.insert(early, at: 0) }
            json["emitter"] = emitters
            try writeJSON(json, to: url)
            let child: [String: Any] = ["name":"particles/child.json", "type":trigger]
            if nested {
                try writeParticle("particles/middle.json", material: "materials/shared.json",
                    lifetime: 0.05, rate: 0, instantaneous: 1, children: [child], under: directory)
            }
            try writeParticle("particles/root.json", material: "materials/shared.json",
                lifetime: trigger == "eventdeath" ? 0.05 : 1, rate: 0, instantaneous: 1,
                children: nested ? [["name":"particles/middle.json","type":"static"]] : [child], under: directory)
            return SceneParticleRuntime(descriptor: .init(layers: [layer(91,"particles/root.json",particleRate:1)],
                renderOrderLayerIDs:[91],materialPasses:[.init(materialPath:"materials/shared.json",
                    shaderPath:"genericparticle",texturePaths:["shared.png"],blending:"additive")]),
                cacheDirectory: directory,device:device)
        }
        func run(_ runtime: SceneParticleRuntime, pause: Bool = false) -> [String: Any] {
            let target=SceneDynamicTarget.particle(layerID:91,field:.rate)
            let zero=SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
                definitions:[.init(target:target,valueType:.scalar,authoredValue:.scalar(1))],
                userValues:[target:.scalar(0)]).snapshot
            if pause { for _ in 0..<60 { _=runtime.advance(by:1.0/60,dynamicValues:zero) } }
            var nonempty:[Int]=[];var counts:[Int]=[];var states:[Int]=[];var retryEqual=true
            for step in 1...180 {
                let before=runtime.frameSnapshot()
                let batches=runtime.advance(by:1.0/60)
                let count=batches.filter{$0.particlePath=="particles/child.json"}.reduce(0){$0+$1.instances.count}
                do {
                    let expected=batches.filter{$0.particlePath=="particles/child.json"}.flatMap(\.instances).map{vector($0.positionAndSize)+vector($0.rotationAndAlpha)}
                    let expectedState=runtime.frameSnapshot().layers.first?.child
                    runtime.restoreFrame(before)
                    let replay=runtime.advance(by:1.0/60).filter{$0.particlePath=="particles/child.json"}.flatMap(\.instances).map{vector($0.positionAndSize)+vector($0.rotationAndAlpha)}
                    let replayState=runtime.frameSnapshot().layers.first?.child
                    retryEqual = retryEqual && expected == replay
                        && expectedState?.systems.map(\.id) == replayState?.systems.map(\.id)
                        && expectedState?.nextSystemID == replayState?.nextSystemID
                        && expectedState?.nextSeed == replayState?.nextSeed
                }
                if count>0 { nonempty.append(step) };counts.append(count)
                states.append(runtime.frameSnapshot().layers.first?.child?.systems.count ?? 0)
            }
            return ["nonemptyFrames":nonempty,"counts":counts,"systems":states,"retryEqual":retryEqual]
        }
        if edges {
            return ["negativeDelay":run(try make("static",delay: -1)),
                    "excessiveDelay":run(try make("eventspawn",delay: 3601)),
                    "malformedDelay":run(try make("static",delay: "invalid")),
                    "invalidFinite":run(try make("static",continuous:true,duration:0.1,delay: -1)),
                    "safePeer":run(try make("static",multiple:true,delay: -1)),
                    "tinyBurst":run(try make("static",duration:1e-13,delay:0)),
                    "tinyDelayedBurst":run(try make("static",duration:1e-13)),
                    "tinyDelayedRate":run(try make("static",continuous:true,duration:1e-13,rate:1e14))]
        }
        return ["staticBurst":run(try make("static")),
                "staticFinite":run(try make("static",continuous:true,duration:0.1)),
                "spawnBurst":run(try make("eventspawn")),
                "deathBurst":run(try make("eventdeath")),
                "followBurst":run(try make("eventfollow")),
                "spawnFinite":run(try make("eventspawn",continuous:true,duration:0.1)),
                "spawnLongFinite":run(try make("eventspawn",continuous:true,duration:0.4)),
                "spawnFallback":run(try make("eventspawn",continuous:true)),
                "nestedBurst":run(try make("eventspawn",nested:true)),
                "multipleBurst":run(try make("static",multiple:true)),
                "prewarmBurst":run(try make("static",warm:0.25)),
                "pausedBurst":run(try make("static"),pause:true)]
    }

}
