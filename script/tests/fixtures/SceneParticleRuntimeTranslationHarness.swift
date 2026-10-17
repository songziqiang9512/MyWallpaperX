import CoreGraphics
import Foundation
import Metal
import simd

/// Own input and independent world-coordinate oracles. All admission, birth,
/// checkpoint and model/parallax decisions are compiled production methods.
private final class TranslationInput {
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
    func descriptor(_ layers: [SceneRenderDescriptor.Layer]) -> SceneRenderDescriptor {
        var value = SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: layers.map(\.id), materialPasses: [
            .init(materialPath: "materials/owned.json", shaderPath: "genericparticle",
                  texturePaths: ["owned.png"], blending: "translucent"),
        ])
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
                    let p = matrix * SIMD4(value.positionAndSize.x, value.positionAndSize.y, value.positionAndSize.z, 1)
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
        return ["admitted": true, "rows": rows]
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
            result["admission-\(mode)"] = !input.runtime(d).activeLayerIDs.contains(31)
        }
        for mode in ["rope", "trail", "child", "pointer-cp", "force", "unknown-operator"] {
            let path = "particles/reject-\(mode).json"
            try input.particle(path) { value in
                switch mode {
                case "rope": value["renderer"] = [["name": "rope"]]
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
            result["admission-\(mode)"] = !actual.activeLayerIDs.contains(31) && actual.activeLayerIDs.contains(32)
        }
        return result
    }
}
