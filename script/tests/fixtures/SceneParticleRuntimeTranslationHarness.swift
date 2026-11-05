import CoreGraphics
import Foundation
import Metal
import simd

/// Own input and independent world-coordinate oracles. All admission, birth,
/// checkpoint and model/parallax decisions are compiled production methods.
final class TranslationInput {
    let directory: URL
    let device: MTLDevice
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mwx-world-translation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw Harness.HarnessError.noMetal }
        self.device = device
        try Harness.writePNG(directory.appendingPathComponent("materials/owned.png"))
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func particle(_ path: String, world: Bool = true, start: Double = 0,
                  edit: (inout [String: Any]) -> Void = { _ in }) throws {
        var value: [String: Any] = [
            "material": "materials/owned.json", "flags": world ? 1 : 0,
            "maxcount": 64, "starttime": start,
            "emitter": [["name": "boxrandom", "rate": 60, "distancemin": 0, "distancemax": 0]],
            "initializer": [["name": "lifetimerandom", "min": 100, "max": 100],
                            ["name": "sizerandom", "min": 2, "max": 2]],
            "operator": [["name": "movement", "gravity": "0 0 0"]],
            "renderer": [["name": "sprite"]],
        ]
        edit(&value)
        try Harness.writeJSON(value, to: directory.appendingPathComponent(path))
    }
    func layer(_ id: Int, _ path: String, writer: Bool = true) -> SceneRenderDescriptor.Layer {
        var value = Harness.layer(id, path)
        value.originXYZ = [100, 200, 0]
        value.scaleXYZ = [1, 1, 1]
        value.anglesXYZ = [0, 0, 0]
        value.originHasScript = writer
        return value
    }
    func descriptor(_ layers: [SceneRenderDescriptor.Layer], authoredProjection: Bool? = nil) -> SceneRenderDescriptor {
        var value = SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: layers.map(\.id), materialPasses: [
            .init(materialPath: "materials/owned.json", shaderPath: "genericparticle",
                  texturePaths: ["owned.png"], blending: "translucent"),
        ])
        value.camera = .init(authoredOrthographicProjectionActive: authoredProjection)
        value.camera.orthoWidth = 1000
        value.camera.orthoHeight = 800
        return value
    }
    func runtime(_ descriptor: SceneRenderDescriptor,
                 initial: SceneDynamicSnapshot = .empty(frameIndex: 0)) -> SceneParticleRuntime {
        SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device,
                             initialDynamicValues: initial)
    }
    func snapshot(_ origins: [Int: SIMD3<Double>], scale: (Int, SIMD3<Double>)? = nil) -> SceneDynamicSnapshot {
        var definitions: [SceneDynamicTargetDefinition] = []
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for (id, v) in origins {
            let target = SceneDynamicTarget.layer(layerID: id, field: .origin)
            definitions.append(.init(target: target, valueType: .vector3, authoredValue: .vector3(100, 200, 0)))
            values[target] = .vector3(v.x, v.y, v.z)
        }
        if let (id, v) = scale {
            let target = SceneDynamicTarget.layer(layerID: id, field: .scale)
            definitions.append(.init(target: target, valueType: .vector3, authoredValue: .vector3(1, 1, 1)))
            values[target] = .vector3(v.x, v.y, v.z)
        }
        return SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1, definitions: definitions,
                                                       sceneScriptValues: values).snapshot
    }
    func frames(_ descriptor: SceneRenderDescriptor, _ snapshot: SceneDynamicSnapshot) -> [Int: simd_float4x4] {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return SceneLayerDynamicWorldFrameResolver.resolve(descriptor: descriptor, byID: byID, snapshot: snapshot,
            staticFrames: SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: byID))
    }
}

extension Harness {
    static func translationAnchoring() throws -> [String: Any] {
        let input = try TranslationInput()
        var rows: [[String: Any]] = []
        for (id, name, scale, angles) in [
            (11, "spark", SIMD3<Float>(1, 1, 1), SIMD3<Float>.zero),
            (211, "renamed-lumen", SIMD3<Float>(2, 3, 1), SIMD3<Float>(0, 0, .pi / 2)),
        ] {
            let path = "particles/\(name).json", localPath = "particles/\(name)-local.json"
            try input.particle(path)
            try input.particle(localPath, world: false)
            var root = input.layer(id, path)
            root.scaleXYZ = [scale.x, scale.y, scale.z]
            root.anglesXYZ = [angles.x, angles.y, angles.z]
            var local = input.layer(id + 1, localPath)
            local.scaleXYZ = root.scaleXYZ
            local.anglesXYZ = root.anglesXYZ
            let descriptor = input.descriptor([root, local])
            let t0 = input.snapshot([id: SIMD3(100, 200, 0), id + 1: SIMD3(100, 200, 0)])
            let t1 = input.snapshot([id: SIMD3(140, 260, 0), id + 1: SIMD3(140, 260, 0)])
            let frames0 = input.frames(descriptor, t0), frames1 = input.frames(descriptor, t1)
            let runtime = input.runtime(descriptor, initial: t0)
            let first = runtime.advance(by: 1.0 / 60, dynamicValues: t0, layerWorldFrames: frames0)
            let second = runtime.advance(by: 1.0 / 60, dynamicValues: t1, layerWorldFrames: frames1)
            guard let world0 = first.first(where: { $0.layerID == id }),
                  let world1 = second.first(where: { $0.layerID == id }),
                  let local1 = second.first(where: { $0.layerID == id + 1 }) else {
                return ["admitted": false, "active": runtime.activeLayerIDs]
            }
            let renderer = SceneMetalRenderer(parallaxByLayerID: [id: .init(sourceLayerID: id, depth: SIMD2(0.5, 0.25))])
            let disabled = SceneLayerParallax.Configuration(enabled: false, amount: 0.4, mouseInfluence: 0.75,
                orthoSize: SIMD2(1000, 800), cameraPosition: SIMD2(500, 400), worldYDown: true)
            func model(_ batch: SceneParticleDrawBatch, _ frames: [Int: simd_float4x4],
                       _ config: SceneLayerParallax.Configuration = disabled,
                       _ pointer: SIMD2<Float> = .zero) -> simd_float4x4 {
                renderer.particleModelMatrix(for: batch.layerID == id ? root : local,
                    worldFramesByLayerID: frames, parallaxMouseNormalized: pointer,
                    configuration: config, referenceWorldFrame: batch.referenceWorldFrame)
            }
            func points(_ batch: SceneParticleDrawBatch, _ matrix: simd_float4x4) -> [[Float]] {
                batch.instances.map { value in
                    let p = matrix * SIMD4<Float>(value.positionAndSize.x, value.positionAndSize.y, value.positionAndSize.z, 1)
                    return [p.x, p.y, p.z]
                }.sorted { $0[0] < $1[0] }
            }
            let enabled = SceneLayerParallax.Configuration(enabled: true, amount: 0.4, mouseInfluence: 0.75,
                orthoSize: SIMD2(1000, 800), cameraPosition: SIMD2(500, 400), worldYDown: true)
            let cameraMoved = SceneLayerParallax.Configuration(enabled: true, amount: 0.4, mouseInfluence: 0.75,
                orthoSize: SIMD2(1000, 800), cameraPosition: SIMD2(520, 410), worldYDown: true)
            let origin = SIMD4<Float>(0, 0, 0, 1)
            let a = model(world0, frames0, enabled, SIMD2(0.2, -0.3)) * origin
            let b = model(world1, frames1, enabled, SIMD2(0.2, -0.3)) * origin
            let pointer = model(world1, frames1, enabled, SIMD2(0.6, 0.1)) * origin
            let camera = model(world1, frames1, cameraMoved, SIMD2(0.2, -0.3)) * origin
            let viewport = CGSize(width: 1000, height: 800)
            let view0 = SceneParticleCameraFrame(camera: descriptor.camera, viewportSize: viewport)
            let view1 = SceneParticleCameraFrame(camera: descriptor.camera, viewportSize: viewport,
                                                 cameraOrigin: SIMD3(20, -10, 0), cameraZoom: 1.4)
            let p0 = view0.orthographicViewProjection * a, p1 = view1.orthographicViewProjection * a
            rows.append([
                "name": name, "admitted": runtime.activeLayerIDs.sorted() == [id, id + 1],
                "referencePublished": world0.referenceWorldFrame != nil && world1.referenceWorldFrame == world0.referenceWorldFrame,
                "localHasNoReference": local1.referenceWorldFrame == nil,
                "firstWorld": points(world0, model(world0, frames0)),
                "secondWorld": points(world1, model(world1, frames1)),
                "secondLocal": points(local1, model(local1, frames1)),
                "parallaxOriginDelta": [b.x - a.x, b.y - a.y],
                "pointerDelta": [pointer.x - b.x, pointer.y - b.y],
                "cameraParallaxDelta": [camera.x - b.x, camera.y - b.y],
                "cameraViewChanged": abs(p0.x / p0.w - p1.x / p1.w) > 0.01 || abs(p0.y / p0.w - p1.y / p1.w) > 0.01,
            ])
        }
        return ["admitted": true, "rows": rows,
            "ancestry": try ancestryAnchoring(input), "families": try ancestryFamilies(input),
            "prewarm": try ancestryPrewarm(input), "ropeTrail": try ancestryRopeTrail(input),
            "spatialConsumers": try ancestrySpatialConsumers(input)]
    }

    static func translationEdges() throws -> [String: Any] {
        let input = try TranslationInput()
        try input.particle("particles/root.json")
        try input.particle("particles/local-peer.json", world: false)
        let root = input.layer(31, "particles/root.json")
        let peer = input.layer(32, "particles/local-peer.json", writer: false)
        let descriptor = input.descriptor([root, peer])
        let current = input.snapshot([31: SIMD3(140, 260, 0)])
        let frames = input.frames(descriptor, current)
        let runtime = input.runtime(descriptor, initial: current)
        _ = runtime.advance(by: 1.0 / 60, dynamicValues: current, layerWorldFrames: frames)
        guard let sim = runtime.playbackSimulators.first(where: { $0.0 == 31 })?.1,
              let peerSim = runtime.playbackSimulators.first(where: { $0.0 == 32 })?.1 else {
            return ["admitted": false]
        }
        var result: [String: Bool] = ["admitted": true]
        let referenceFrame = SceneMatrix.translation(SIMD3<Float>(100, 600, 0))
            * SceneMatrix.rotationZ(0.4) * SceneMatrix.scale(SIMD3(2, 3, 1))
        let finitePlan = SceneParticleRootWorldTranslationPlan(referenceWorldFrame: referenceFrame)!
        var rejectsNonfiniteLanes = true
        for column in 0..<4 { for row in 0..<4 {
            for value in [Float.nan, Float.infinity, -Float.infinity] {
                var invalid = referenceFrame
                invalid[column][row] = value
                rejectsNonfiniteLanes = rejectsNonfiniteLanes && finitePlan.frame(currentWorldFrame: invalid) == nil
            }
        }}
        result["reference-plan-rejects-all-48-nonfinite-current-lanes"] = rejectsNonfiniteLanes
        var translated = referenceFrame
        translated.columns.3.x += 40; translated.columns.3.y -= 60
        var changedBasis = translated
        changedBasis.columns.0.x += 0.1
        result["reference-plan-finite-offset-and-basis-recovery"] = finitePlan.frame(currentWorldFrame: translated) != nil
            && finitePlan.frame(currentWorldFrame: changedBasis) == nil
            && finitePlan.frame(currentWorldFrame: translated) != nil
        let reference = runtime.advance(by: 0, dynamicValues: current, layerWorldFrames: frames)
            .first(where: { $0.layerID == 31 })?.referenceWorldFrame
        for (name, bad) in ["missing": nil, "singular": simd_float4x4(),
                            "basis": SceneMatrix.scale(SIMD3(2, 1, 1)),
                            "z": SceneMatrix.translation(SIMD3(140, 540, 2))] as [String: simd_float4x4?] {
            var values = frames
            if let bad { values[31] = bad } else { values.removeValue(forKey: 31) }
            let before = sim.frameSnapshot(), peerTime = peerSim.simulationTime
            let batches = runtime.advance(by: 0.25, dynamicValues: current, layerWorldFrames: values)
            let after = sim.frameSnapshot()
            result["freeze-\(name)"] = after.particles == before.particles && after.random.state == before.random.state
                && after.nextParticleID == before.nextParticleID && after.simulationTime == before.simulationTime
                && after.accumulator == before.accumulator && peerSim.simulationTime > peerTime
                && batches.first(where: { $0.layerID == 31 })?.referenceWorldFrame == reference
            do {
                _ = try runtime.emissionContext(layerID: 31, dynamicValues: current, pointerLocalPosition: nil,
                    audio: .silent, worldFrame: values[31])
                result["emit-rejected-\(name)"] = false
            } catch { result["emit-rejected-\(name)"] = true }
            let beforeRecovery = sim.simulationTime
            _ = runtime.advance(by: 1.0 / 60, dynamicValues: current, layerWorldFrames: frames)
            result["recover-\(name)"] = abs(sim.simulationTime - beforeRecovery - 1.0 / 60) < 1e-9
        }
        let populationCount = sim.particles.count
        runtime.applyPlaybackTransitions([.init(layerID: 31, action: .pause, revision: 1)])
        _ = runtime.advance(by: 1.0 / 60, dynamicValues: current, layerWorldFrames: frames)
        result["pause-keeps-population"] = sim.particles.count == populationCount
        let stop = SceneParticlePlaybackTransition(layerID: 31, action: .stop, revision: 2)
        runtime.applyPlaybackTransitions([stop])
        result["stop-clears"] = sim.particles.isEmpty
        runtime.applyPlaybackTransitions([.init(layerID: 31, action: .play, revision: 3)])
        let resumed = runtime.advance(by: 1.0 / 60, dynamicValues: current, layerWorldFrames: frames)
        result["play-keeps-reference"] = !sim.particles.isEmpty
            && resumed.first(where: { $0.layerID == 31 })?.referenceWorldFrame == reference
        try input.particle("particles/prewarm.json", start: 0.05)
        let preDescriptor = input.descriptor([input.layer(41, "particles/prewarm.json")])
        let initial = input.snapshot([41: SIMD3(140, 260, 0)])
        let prewarm = input.runtime(preDescriptor, initial: initial)
        let births = prewarm.advance(by: 0, dynamicValues: initial, layerWorldFrames: input.frames(preDescriptor, initial))
        let batch = births.first(where: { $0.layerID == 41 })
        if let batch, let ref = batch.referenceWorldFrame {
            let model = SceneParticleCameraFrame.particleLayerModel(worldFrame: ref, parallaxOffset: .zero)
            result["prewarm-uses-initial-current"] = batch.instances.count >= 2 && batch.instances.allSatisfy {
                let p = model * SIMD4($0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z, 1)
                return abs(p.x - 140) < 0.001 && abs(p.y - 540) < 0.001
            }
        } else { result["prewarm-uses-initial-current"] = false }
        let invalidInitial = input.snapshot([31: SIMD3(100, 200, 0)], scale: (31, SIMD3(0, 1, 1)))
        result["invalid-initial-no-simulator"] = !input.runtime(descriptor, initial: invalidInitial).activeLayerIDs.contains(31)
        for mode in ["angles-writer", "scale-writer", "parent", "declared-child", "actual-child", "attachment", "perspective", "native-camera"] {
            var layer = root, peer = peer
            switch mode {
            case "angles-writer": layer.anglesHasScript = true
            case "scale-writer": layer.scaleHasScript = true
            case "parent": layer.parentID = 32
            case "declared-child": layer.childLayerIDs = [32]
            case "actual-child": peer.parentID = 31
            case "attachment": layer.attachmentName = "socket"
            case "perspective": layer.usesPerspective = true
            default: break
            }
            var d = input.descriptor([layer, peer])
            if mode == "native-camera" { d.camera.orthoWidth = nil; d.camera.orthoHeight = nil }
            let active = input.runtime(d).activeLayerIDs.contains(31)
            result["admission-\(mode)"] = ["parent", "declared-child", "actual-child"].contains(mode) ? active : !active
        }
        for mode in ["trail", "child", "pointer-cp", "force", "unknown-operator"] {
            let path = "particles/reject-\(mode).json"
            try input.particle(path) { value in
                switch mode {
                case "trail": value["renderer"] = [["name": "spritetrail"]]
                case "child": value["children"] = [["name": "particles/local-peer.json", "type": "static"]]
                case "pointer-cp":
                    value["controlpoint"] = [["id": 0, "flags": 1]]
                    value["emitter"] = [["name": "boxrandom", "rate": 60, "controlpoint": 0]]
                case "force": value["operator"] = [["name": "controlpointforce", "controlpoint": 0]]
                default: value["operator"] = [["name": "unrecognized-spatial-law"]]
                }
            }
            let d = input.descriptor([input.layer(31, path), peer])
            let actual = input.runtime(d)
            let batches = actual.advance(by: 1.0 / 60,
                pointerLocalPositions: [31: SIMD3(40, 0, 0)], layerWorldFrames: input.frames(d, .empty(frameIndex: 0)))
            result["component-does-not-revoke-root-\(mode)"] = actual.activeLayerIDs.contains(31)
                && actual.activeLayerIDs.contains(32) && batches.contains { $0.layerID == 31 && $0.referenceWorldFrame != nil }
        }
        return result
    }
}

extension TranslationInput {
    func ancestry(_ id: Int, path: String, mirror: Bool = false,
                  localPath: String? = nil) -> SceneRenderDescriptor {
        func container(_ key: Int, parent: Int?, origin: [Float]) -> SceneRenderDescriptor.Layer {
            var value = SceneRenderDescriptor.Layer(id: key, name: "ancestor-\(key)", contentKind: "container",
                particlePath: nil, particleInstanceOverride: nil, parentID: parent, visible: true, alpha: nil)
            value.originXYZ = origin; value.scaleXYZ = [1, 1, 1]; value.anglesXYZ = [0, 0, 0]
            value.originHasScript = true
            return value
        }
        var grand = container(id - 2, parent: nil, origin: [100, 200, 0])
        if mirror { grand.scaleXYZ = [-2, 3, 1]; grand.anglesXYZ = [0, 0, .pi / 2] }
        let parent = container(id - 1, parent: id - 2, origin: [10, 20, 0])
        var root = layer(id, path, writer: false)
        root.parentID = id - 1; root.originXYZ = [5, 7, 0]
        var layers = [grand, parent, root]
        if let localPath {
            var local = layer(id + 1, localPath, writer: false)
            local.parentID = id - 1; local.originXYZ = root.originXYZ
            layers.append(local)
        }
        return descriptor(layers, authoredProjection: true)
    }
    func ancestrySnapshot(_ id: Int, moved: Bool) -> SceneDynamicSnapshot {
        snapshot(moved ? [id - 2: SIMD3(120, 230, 0), id - 1: SIMD3(30, 50, 0)]
                       : [id - 2: SIMD3(100, 200, 0), id - 1: SIMD3(10, 20, 0)])
    }
    func model(_ batch: SceneParticleDrawBatch, descriptor: SceneRenderDescriptor,
               frames: [Int: simd_float4x4]) -> simd_float4x4 {
        let renderer = SceneMetalRenderer(parallaxByLayerID: [:])
        let config = SceneLayerParallax.Configuration(enabled: false, amount: 0, mouseInfluence: 0,
            orthoSize: SIMD2(1000, 800), cameraPosition: SIMD2(500, 400), worldYDown: true)
        return renderer.particleModelMatrix(for: descriptor.layers.first { $0.id == batch.layerID }!,
            worldFramesByLayerID: frames, parallaxMouseNormalized: .zero,
            configuration: config, referenceWorldFrame: batch.referenceWorldFrame)
    }
    func points(_ batches: [SceneParticleDrawBatch], descriptor: SceneRenderDescriptor,
                frames: [Int: simd_float4x4], path: String) -> [[Float]] {
        var result: [[Float]] = []
        for batch in batches where batch.particlePath == path {
            let transform: simd_float4x4 = model(batch, descriptor: descriptor, frames: frames)
            for instance in batch.instances {
                let position = instance.positionAndSize
                let local = SIMD4<Float>(position.x, position.y, position.z, 1)
                let world: SIMD4<Float> = simd_mul(transform, local)
                result.append([world.x, world.y, world.z])
            }
        }
        return result.sorted { a, b in a[0] == b[0] ? a[1] < b[1] : a[0] < b[0] }
    }
}

extension Harness {
    static func ancestryAnchoring(_ input: TranslationInput) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for (id, name, mirror) in [(1011, "plain-ancestor", false), (3011, "renamed-mirror", true)] {
            let path = "particles/\(name).json", localPath = "particles/\(name)-local.json"
            try input.particle(path); try input.particle(localPath, world: false)
            let d = input.ancestry(id, path: path, mirror: mirror, localPath: localPath)
            let s0 = input.ancestrySnapshot(id, moved: false), s1 = input.ancestrySnapshot(id, moved: true)
            let f0 = input.frames(d, s0), f1 = input.frames(d, s1)
            let runtime = input.runtime(d, initial: s0)
            let first = runtime.advance(by: 1.0 / 60, dynamicValues: s0, layerWorldFrames: f0)
            let second = runtime.advance(by: 1.0 / 60, dynamicValues: s1, layerWorldFrames: f1)
            let ref = first.first { $0.layerID == id }?.referenceWorldFrame
            rows.append(["name": name, "active": runtime.activeLayerIDs.sorted(),
                "rootHasNoOwnWriter": d.layers.first { $0.id == id }!.originHasScript == false,
                "sameReference": ref != nil && second.first { $0.layerID == id }?.referenceWorldFrame == ref,
                "localNoReference": second.first { $0.layerID == id + 1 }?.referenceWorldFrame == nil,
                "first": input.points(first, descriptor: d, frames: f0, path: path),
                "world": input.points(second, descriptor: d, frames: f1, path: path),
                "local": input.points(second, descriptor: d, frames: f1, path: localPath)])
        }
        return rows
    }

    static func sameTranslationSimulation(_ a: SceneParticleSimulator.FrameSnapshot,
                                          _ b: SceneParticleSimulator.FrameSnapshot) -> Bool {
        a.particles == b.particles && a.birthEvents == b.birthEvents && a.deathEvents == b.deathEvents
            && a.random.state == b.random.state && a.nextParticleID == b.nextParticleID
            && a.simulationTime == b.simulationTime && a.accumulator == b.accumulator
    }
    static func sameTranslationLayer(_ a: SceneParticleRuntime.FrameSnapshot.LayerSnapshot,
                                     _ b: SceneParticleRuntime.FrameSnapshot.LayerSnapshot) -> Bool {
        guard let ar = a.root, let br = b.root,
              sameTranslationSimulation(ar.simulatorFrame, br.simulatorFrame),
              let ac = a.child, let bc = b.child,
              ac.nextSeed == bc.nextSeed, ac.nextSystemID == bc.nextSystemID,
              ac.systems.count == bc.systems.count else { return false }
        return zip(ac.systems, bc.systems).allSatisfy { x, y in
            x.id == y.id && x.templateIndex == y.templateIndex && x.depth == y.depth
                && x.spawnScopeID == y.spawnScopeID && x.parentParticleID == y.parentParticleID
                && x.origin == y.origin && x.particleOrigins == y.particleOrigins
                && sameTranslationSimulation(x.simulatorFrame, y.simulatorFrame)
        }
    }

    static func ancestryFamilies(_ input: TranslationInput) throws -> [String: Any] {
        let id = 5011, base = "particles/ancestry-family-"
        let names = ["static-world", "static-local", "spawn-world", "spawn-local", "follow-world", "follow-local",
                     "nested-spawn-world", "nested-follow-world", "nested-follow-local"]
        for name in names {
            let nested = name.hasPrefix("nested-"), spawn = name.hasPrefix("spawn-")
            try input.particle(base + name + ".json", world: !name.hasSuffix("local"),
                               start: spawn && name != "spawn-world" ? 0.05 : (nested ? 1.0 / 60 : 0)) { value in
                if spawn || nested { value["emitter"] = [["name": "boxrandom", "rate": 0,
                    "instantaneous": 1, "distancemin": 0, "distancemax": 0]] }
                if spawn {
                    var initializers = value["initializer"] as! [[String: Any]]
                    initializers.append(["name": "velocityrandom", "min": "60 0 0", "max": "60 0 0"])
                    value["initializer"] = initializers
                }
                if name == "spawn-world" {
                    value["children"] = [["name": base + "nested-spawn-world.json", "type": "eventspawn"],
                        ["name": base + "nested-follow-world.json", "type": "eventfollow"],
                        ["name": base + "nested-follow-local.json", "type": "eventfollow"]]
                }
            }
        }
        let rootPath = base + "root.json", peerPath = base + "peer.json"
        try input.particle(rootPath) { value in
            var initializers = value["initializer"] as! [[String: Any]]
            initializers.append(["name": "velocityrandom", "min": "60 0 0", "max": "60 0 0"])
            value["initializer"] = initializers
            value["children"] = [
                ["name": base + "static-world.json", "type": "static", "origin": "8 0 0"],
                ["name": base + "static-local.json", "type": "static", "origin": "-8 0 0"],
                ["name": base + "spawn-world.json", "type": "eventspawn"],
                ["name": base + "spawn-local.json", "type": "eventspawn"],
                ["name": base + "follow-world.json", "type": "eventfollow"],
                ["name": base + "follow-local.json", "type": "eventfollow"]]
        }
        try input.particle(peerPath, world: false)
        let ancestry = input.ancestry(id, path: rootPath)
        let d = input.descriptor(ancestry.layers + [input.layer(id + 1, peerPath, writer: false)],
                                 authoredProjection: true)
        let s0 = input.ancestrySnapshot(id, moved: false), s1 = input.ancestrySnapshot(id, moved: true)
        let f0 = input.frames(d, s0), f1 = input.frames(d, s1)
        let runtime = input.runtime(d, initial: s0)
        let first = runtime.advance(by: 1.0 / 60, dynamicValues: s0, layerWorldFrames: f0)
        _ = runtime.advance(by: 1.0 / 60, dynamicValues: s1, layerWorldFrames: f1)
        let third = runtime.advance(by: 1.0 / 60, dynamicValues: s1, layerWorldFrames: f1)
        let ref = first.first { $0.layerID == id }?.referenceWorldFrame
        var points: [String: [[Float]]] = [:]
        for name in names + ["root"] {
            points[name] = input.points(third, descriptor: d, frames: f1, path: base + name + ".json")
        }
        guard let rootIndex = runtime.layers.firstIndex(where: { $0.layerID == id }),
              let peer = runtime.playbackSimulators.first(where: { $0.0 == id + 1 })?.1 else {
            return ["points": points, "allChildReferences": false]
        }
        let before = runtime.frameSnapshot(), peerTime = peer.simulationTime
        var invalid = f1; invalid.removeValue(forKey: id)
        let held = runtime.advance(by: 0.25, dynamicValues: s1, layerWorldFrames: invalid)
        let frozen = runtime.frameSnapshot()
        let recovered = runtime.advance(by: 1.0 / 60, dynamicValues: s1, layerWorldFrames: f1)
        let recoveredState = runtime.frameSnapshot()
        runtime.restoreFrame(frozen)
        let replayed = runtime.advance(by: 1.0 / 60, dynamicValues: s1, layerWorldFrames: f1)
        let replayedState = runtime.frameSnapshot()
        let replayPoints = (names + ["root"]).allSatisfy { name in
            input.points(recovered, descriptor: d, frames: f1, path: base + name + ".json")
                == input.points(replayed, descriptor: d, frames: f1, path: base + name + ".json")
        }
        return ["points": points,
            "allChildReferences": ref != nil && third.filter { $0.layerID == id }.allSatisfy { $0.referenceWorldFrame == ref },
            "hasDepthTwo": before.layers[rootIndex].child?.systems.contains { $0.depth == 2 } == true,
            "freezePopulationAndPendingEvents": sameTranslationLayer(before.layers[rootIndex], frozen.layers[rootIndex]),
            "heldOutput": (names + ["root"]).allSatisfy { name in
                input.points(third, descriptor: d, frames: f1, path: base + name + ".json")
                    == input.points(held, descriptor: d, frames: invalid, path: base + name + ".json") },
            "peerAdvanced": peer.simulationTime > peerTime,
            "recoveryAdvanced": recoveredState.layers[rootIndex].root!.simulatorFrame.simulationTime
                > frozen.layers[rootIndex].root!.simulatorFrame.simulationTime,
            "rollbackStateAndOutput": replayPoints
                && sameTranslationLayer(recoveredState.layers[rootIndex], replayedState.layers[rootIndex])]
    }

    static func ancestryPrewarm(_ input: TranslationInput) throws -> [String: Any] {
        let id = 6011, rootPath = "particles/ancestor-prewarm.json"
        let worldPath = "particles/ancestor-prewarm-world.json", localPath = "particles/ancestor-prewarm-local.json"
        try input.particle(worldPath, start: 0.05)
        try input.particle(localPath, world: false, start: 0.05)
        try input.particle(rootPath, start: 0.05) { value in
            value["children"] = [["name": worldPath, "type": "static", "origin": "8 0 0"],
                ["name": localPath, "type": "static", "origin": "-8 0 0"]]
        }
        let d = input.ancestry(id, path: rootPath), s = input.ancestrySnapshot(id, moved: true)
        let frames = input.frames(d, s), runtime = input.runtime(d, initial: s)
        let batches = runtime.advance(by: 0, dynamicValues: s, layerWorldFrames: frames)
        return ["root": input.points(batches, descriptor: d, frames: frames, path: rootPath),
            "world": input.points(batches, descriptor: d, frames: frames, path: worldPath),
            "local": input.points(batches, descriptor: d, frames: frames, path: localPath)]
    }

    static func ancestryRopeTrail(_ input: TranslationInput) throws -> [String: Any] {
        let id = 7011, path = "particles/ancestor-history.json"
        try input.particle(path, start: 0.05) { value in
            value["renderer"] = [["name": "ropetrail", "length": 0.2]]
            var initializers = value["initializer"] as! [[String: Any]]
            initializers.append(["name": "velocityrandom", "min": "60 0 0", "max": "60 0 0"])
            value["initializer"] = initializers
        }
        let d = input.ancestry(id, path: path), s0 = input.ancestrySnapshot(id, moved: false)
        let s1 = input.ancestrySnapshot(id, moved: true), f0 = input.frames(d, s0), f1 = input.frames(d, s1)
        let runtime = input.runtime(d, initial: s0)
        let first = runtime.advance(by: 0, dynamicValues: s0, layerWorldFrames: f0)
        let held = runtime.advance(by: 0, dynamicValues: s1, layerWorldFrames: f1)
        _ = runtime.advance(by: 1.0 / 60, dynamicValues: s1, layerWorldFrames: f1)
        let last = runtime.advance(by: 1.0 / 60, dynamicValues: s1, layerWorldFrames: f1)
        guard let batch = last.first, let ref = batch.referenceWorldFrame,
              let sim = runtime.playbackSimulators.first(where: { $0.0 == id })?.1 else {
            return ["active": false]
        }
        let matrix = input.model(batch, descriptor: d, frames: f1)
        let population = sim.particles.map { value -> [Float] in
            let p = matrix * SIMD4(Float(value.position.x), Float(value.position.y), Float(value.position.z), 1)
            return [p.x, p.y, p.z]
        }.sorted { $0[0] < $1[0] }
        let centers = input.points(last, descriptor: d, frames: f1, path: path)
        return ["active": true, "population": population, "centers": centers,
            "reference": first.first?.referenceWorldFrame == ref && held.first?.referenceWorldFrame == ref,
            "zeroStepPreservesHistory": input.points(first, descriptor: d, frames: f0, path: path)
                == input.points(held, descriptor: d, frames: f1, path: path),
            "historyRetained": runtime.frameSnapshot().layers.first?.root?.ropeTrailHistory != nil]
    }

    static func ancestrySpatialConsumers(_ input: TranslationInput) throws -> [String: Any] {
        let id = 8011
        let operators: [(String, [String: Any], String)] = [
            ("force", ["name": "controlpointattract", "controlpoint": 1, "scale": 60, "threshold": 512], "0 0 0"),
            ("vortex", ["name": "vortex_v2", "distanceinner": 0, "distanceouter": 100,
                "speedinner": 60, "speedouter": 60], "10 0 0"),
            ("plane", ["name": "collisionplane", "plane": "0 1 0", "distance": 0, "bouncefactor": 1], "0 -2 0")]
        var rows: [String: Any] = [:]
        for (name, op, position) in operators {
            let path = "particles/ancestor-consumer-\(name).json"
            try input.particle(path) { value in
                value["emitter"] = [["name": "boxrandom", "rate": 0, "instantaneous": 1,
                    "distancemin": 0, "distancemax": 0, "origin": position]]
                value["controlpoint"] = [["id": 0, "flags": 0, "offset": "0 0 0"],
                    ["id": 1, "flags": 0, "offset": "10 0 0"]]
                value["operator"] = [op]
            }
            let d = input.ancestry(id, path: path), moved = input.ancestrySnapshot(id, moved: true)
            let runtime = input.runtime(d, initial: moved)
            _ = runtime.advance(by: 1.0 / 60, dynamicValues: moved, layerWorldFrames: input.frames(d, moved))
            guard let sim = runtime.playbackSimulators.first(where: { $0.0 == id })?.1,
                  let particle = sim.particles.first else { rows[name] = ["active": false]; continue }
            rows[name] = ["active": true, "position": [particle.position.x, particle.position.y, particle.position.z],
                "velocity": [particle.velocity.x, particle.velocity.y, particle.velocity.z]]
        }
        return rows
    }
}
