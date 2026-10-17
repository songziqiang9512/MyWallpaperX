import Foundation
import simd

@main enum ForceHarness {
    static let canvas: [String: Any] = ["orthogonalprojection": ["width": 1000, "height": 800]]
    static func vector(_ value: SIMD3<Double>) -> [Double] { [value.x, value.y, value.z] }
    static func root(threshold: Any? = nil, point: SIMD3<Double> = .init(10, 0, 0),
                     pointFlags: Int = 0, systemFlags: Int = 0, material: String = "owned.json") -> [String: Any] {
        var force: [String: Any] = ["name": "controlpointattract", "controlpoint": 1,
                                    "origin": "0 0 0", "scale": 2]
        if let threshold { force["threshold"] = threshold }
        return ["material": material, "maxcount": 1, "flags": systemFlags,
                "emitter": [["name": "boxrandom", "instantaneous": 1, "distancemax": 0]],
                "initializer": [["name": "lifetimerandom", "min": 20, "max": 20]],
                "operator": [["name": "movement", "gravity": "0 0 0"], force],
                "renderer": [["name": "sprite"]],
                "controlpoint": [["id": 1, "flags": pointFlags,
                                   "offset": "\(point.x) \(point.y) \(point.z)"]]]
    }
    static func parse(_ root: [String: Any]) -> SceneParticleDefinition {
        SceneParticleDefinitionParser().parse(root: root)
    }
    static func descriptor(_ general: [String: Any]?, id: Int = 42,
                           origin: [Float] = [100, 200, 0], angles: [Float] = [0, 0, 0],
                           scale: [Float] = [1, 1, 1], name: String = "owned-lumen") throws -> SceneRenderDescriptor {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var scene: [String: Any] = ["objects": [["id": id, "name": name,
            "particle": "particles/\(name).json", "origin": origin.map { "\($0)" }.joined(separator: " "),
            "angles": angles.map { "\($0)" }.joined(separator: " "),
            "scale": scale.map { "\($0)" }.joined(separator: " ")]]]
        if let general { scene["general"] = general }
        let url = directory.appendingPathComponent("scene.json")
        try JSONSerialization.data(withJSONObject: scene).write(to: url)
        let document = try SceneDocumentLoader().load(from: url)
        let project = SceneProject(rootURL: directory, entryPath: "scene.json", userProperties: .empty)
        return SceneRenderDescriptorBuilder().build(project: project, sceneDocument: document,
            assetCatalog: .init(models: [], materials: [], effectDefinitions: [], effectDefinitionDiagnostics: [],
                                shaderReferences: [], textureReferences: []),
            resourceReferences: .init(missingReferences: [], builtInReferenceCount: 0, runtimeProvidedReferenceCount: 0),
            capabilityProfile: .init(firstStageRendererGaps: []))!
    }
    static func changingFirstLayer(_ descriptor: SceneRenderDescriptor, _ edits: [String: Any]) throws -> SceneRenderDescriptor {
        var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as! [String: Any]
        var layers = root["layers"] as! [[String: Any]]
        layers[0].merge(edits, uniquingKeysWith: { _, next in next })
        root["layers"] = layers
        return try JSONDecoder().decode(SceneRenderDescriptor.self, from: JSONSerialization.data(withJSONObject: root))
    }
    static func environment(_ descriptor: SceneRenderDescriptor, _ definition: SceneParticleDefinition)
        -> SceneParticleControlPointForceEnvironment {
        descriptor.particleControlPointForceEnvironment(for: descriptor.layers[0], definition: definition)
    }
    static func frame(_ descriptor: SceneRenderDescriptor) -> SceneParticleControlPointForceFrame? {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let matrix = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: byID)[descriptor.layers[0].id]!
        return SceneParticleControlPointForceFrame(worldFrame: matrix, sceneOrthoHeight: descriptor.camera.orthoHeight ?? 0)
    }
    static func forcePlan(_ definition: SceneParticleDefinition, _ environment: SceneParticleControlPointForceEnvironment)
        -> SceneParticleControlPointForcePlan? {
        definition.controlPointForcePlan(for: definition.operators[1], environment: environment)
    }
    static func simulator(_ definition: SceneParticleDefinition, _ environment: SceneParticleControlPointForceEnvironment,
                          _ frame: SceneParticleControlPointForceFrame? = nil) -> SceneParticleSimulator {
        SceneParticleSimulator(definition: definition, seed: 81, fixedTimeStep: 1,
                               controlPointForceEnvironment: environment, controlPointForceFrame: frame)
    }
    static func velocity(_ definition: SceneParticleDefinition, _ environment: SceneParticleControlPointForceEnvironment,
                         _ frame: SceneParticleControlPointForceFrame? = nil) -> [Double] {
        let sim = simulator(definition, environment, frame)
        sim.advance(by: 1, controlPointForceFrame: frame)
        return sim.particles.first.map { vector($0.velocity) } ?? []
    }
    static func main() throws {
        let inputs: [(String, [String: Any]?)] = [
            ("fixed", canvas), ("auto", ["orthogonalprojection": ["auto": true]]),
            ("auto-with-zero-size", ["orthogonalprojection": ["auto": true, "width": 0, "height": 0]]),
            ("zero", ["orthogonalprojection": ["width": 0, "height": 800]]),
            ("off", ["orthogonalprojection": ["auto": false]]), ("absent", nil)]
        var projection: [[String: Any]] = []
        for (name, general) in inputs {
            let d = try descriptor(general)
            let definition = parse(root(point: .init(100, 0, 0)))
            let env = environment(d, definition)
            let zero = parse(root(threshold: 0))
            projection.append(["name": name, "active": d.camera.authoredOrthographicProjectionActive ?? false, "activeKnown": d.camera.authoredOrthographicProjectionActive != nil,
                "default": env.defaultMaximumDistance ?? -1, "maximum": forcePlan(definition, env)?.maximumDistance ?? -1,
                "velocity": velocity(definition, env), "nearVelocity": velocity(parse(root(point: .init(2, 0, 0))), env),
                "explicitZeroMaximum": forcePlan(zero, env)?.maximumDistance ?? -1,
                "explicitZeroVelocity": velocity(zero, env),
                "explicit20Velocity": velocity(parse(root(threshold: 20)), env)])
        }
        let base = try descriptor(canvas)
        let ordinary = parse(root())
        let env = environment(base, ordinary)
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        var legacyCamera = legacyJSON["camera"] as! [String: Any]
        legacyCamera.removeValue(forKey: "authoredOrthographicProjectionActive")
        legacyJSON["camera"] = legacyCamera
        let legacy = try JSONDecoder().decode(SceneRenderDescriptor.self,
            from: JSONSerialization.data(withJSONObject: legacyJSON))
        let unknown = environment(legacy, ordinary)
        let malformedValues: [Any] = ["bad", true, [1, 2], ["other": 10]]
        let malformed = try malformedValues.map { value -> [String: Any] in
            let definition = parse(root(threshold: value))
            return ["plan": forcePlan(definition, env) != nil, "velocity": velocity(definition, env)]
        }
        var world: [[String: Any]] = []
        for (id, name, angle, scale) in [
            (42, "lumen", Float(0), SIMD3<Float>(1, 1, 1)),
            (902, "renamed-spark", Float.pi / 2, SIMD3<Float>(2, 3, 1)),
            (127, "ribbon-b", Float(-0.09853), SIMD3<Float>(1.5, 0.75, 1)),
        ] {
            // Independent authored-space oracle: local(10,20) through the declared planar TRS.
            let wx = 100 + Double(cos(angle) * scale.x * 10 - sin(angle) * scale.y * 20)
            let wy = 200 + Double(sin(angle) * scale.x * 10 + cos(angle) * scale.y * 20)
            let target = SIMD3(wx, wy, 0)
            let d = try descriptor(canvas, id: id, angles: [0, 0, angle],
                                   scale: [scale.x, scale.y, scale.z], name: name)
            let definition = parse(root(point: target, pointFlags: 2, material: "\(name)/white.json"))
            let e = environment(d, definition), f = frame(d)!
            let sim = simulator(definition, e, f)
            sim.advance(by: 1, controlPointForceFrame: f)
            let before = sim.particles[0].velocity
            let saved = sim.frameSnapshot()
            let shifted = try descriptor(canvas, id: id, origin: [500, 500, 0],
                                         angles: [0, 0, angle], scale: [scale.x, scale.y, scale.z], name: name)
            sim.advance(by: 1, controlPointForceFrame: frame(shifted))
            let change = sim.particles[0].velocity - before
            let newTarget = frame(shifted)!.localPosition(worldPoint: target)!
            let toward = newTarget - saved.particles[0].position
            let turns = simd_dot(change, toward) > 0 && simd_length(change) > 1
            sim.restoreFrame(saved)
            world.append(["name": name, "allowed": e.allowsWorldSource,
                "space": forcePlan(definition, e)?.sourceSpace == .world ? "world" : "local",
                "localPoint": vector(f.localPosition(worldPoint: target)!), "velocity": vector(before),
                "localVelocity": velocity(parse(root(point: .init(10, 0, 0))), e, f),
                "changedFrameTurnsForce": turns])
        }
        let fixedTarget = SIMD3<Double>(110, 220, 0)
        let shifted = try descriptor(canvas, origin: [140, 260, 0])
        let moving = parse(root(point: fixedTarget, pointFlags: 2))
        let live = simulator(moving, environment(base, moving), frame(base))
        live.advance(by: 1, controlPointForceFrame: frame(base))
        let saved = live.frameSnapshot()
        live.advance(by: 1, controlPointForceFrame: frame(shifted))
        live.restoreFrame(saved)
        let rollback = live.frameSnapshot().controlPointForceFrame == saved.controlPointForceFrame
        var warmRoot = root(point: fixedTarget, pointFlags: 2); warmRoot["starttime"] = 1
        let warm = simulator(parse(warmRoot), environment(base, moving), frame(base))
        let cold = simulator(moving, environment(base, moving), frame(base))
        cold.advance(by: 1, controlPointForceFrame: frame(base))
        let prewarm = warm.particles == cold.particles && warm.simulationTime == cold.simulationTime
        var admissions: [[String: Any]] = []
        for kind in ["parent", "attachment", "bind", "declared-child", "actual-child", "perspective", "general-world", "general-perspective", "definition-child"] {
            var d = base, raw = root(point: fixedTarget, pointFlags: 2)
            switch kind {
            case "parent": d = try changingFirstLayer(d, ["parentID": 99])
            case "attachment": d = try changingFirstLayer(d, ["attachmentName": "socket"])
            case "bind": d = try changingFirstLayer(d, ["parentAttachmentBindFrame": Array(repeating: 0, count: 16)])
            case "declared-child": d.layers[0].childLayerIDs = [99]
            case "actual-child": d.layers.append(try changingFirstLayer(descriptor(canvas, id: 99), ["parentID": 42]).layers[0])
            case "perspective": d.layers[0].usesPerspective = true
            case "general-world": raw["flags"] = 1
            case "general-perspective": raw["flags"] = 4
            default: raw["children"] = [["name": "particles/child.json"]]
            }
            let definition = parse(raw), e = environment(d, definition)
            admissions.append(["name": kind, "allowed": e.allowsWorldSource, "default": e.defaultMaximumDistance ?? -1,
                "worldPlan": forcePlan(definition, e) != nil,
                "localPlan": forcePlan(parse(root(threshold: 20)), e) != nil])
        }
        var unsafeFrames: [(String, simd_float4x4, Float)] = []
        var bad = matrix_identity_float4x4; bad[0][0] = .nan; unsafeFrames.append(("nan", bad, 800))
        bad = matrix_identity_float4x4; bad[0][0] = 0; unsafeFrames.append(("singular", bad, 800))
        bad = matrix_identity_float4x4; bad[0][3] = 1; unsafeFrames.append(("non-affine", bad, 800))
        unsafeFrames.append(("zero-height", matrix_identity_float4x4, 0))
        var invalidFrames: [[String: Any]] = []
        for (name, matrix, height) in unsafeFrames {
            let rejected = SceneParticleControlPointForceFrame(worldFrame: matrix, sceneOrthoHeight: height)
            var raw = root(point: fixedTarget, pointFlags: 2)
            var points = raw["controlpoint"] as! [[String: Any]]
            points.append(["id": 2, "flags": 0, "offset": "0 10 0"]); raw["controlpoint"] = points
            var operators = raw["operator"] as! [[String: Any]]
            operators.append(["name": "controlpointattract", "controlpoint": 2, "scale": 1, "threshold": 20])
            raw["operator"] = operators
            let sim = simulator(parse(raw), env)
            sim.advance(by: 1, controlPointForceFrame: rejected)
            let v = sim.particles[0].velocity
            sim.advance(by: 1, controlPointForceFrame: frame(base))
            invalidFrames.append(["name": name, "rejected": rejected == nil,
                "particleCount": sim.particles.count, "velocity": vector(v), "worldRecovers": sim.particles[0].velocity.x > 0])
        }
        var worldZero = root(point: fixedTarget, pointFlags: 2)
        var zeroOperators = worldZero["operator"] as! [[String: Any]]
        zeroOperators[1]["controlpoint"] = 0; worldZero["operator"] = zeroOperators
        worldZero["controlpoint"] = [["id": 0, "flags": 2, "offset": "110 220 0"]]
        let worldZeroDefinition = parse(worldZero)
        var localZero = root(threshold: 20)
        var localZeroOperators = localZero["operator"] as! [[String: Any]]
        localZeroOperators[1]["controlpoint"] = 0; localZero["operator"] = localZeroOperators
        localZero["controlpoint"] = [["id": 0, "flags": 0, "offset": "10 0 0"]]
        let zeroBoundary = forcePlan(worldZeroDefinition, environment(base, worldZeroDefinition)) == nil
            && forcePlan(parse(localZero), env) != nil
        var offsetWorld = root(point: fixedTarget, pointFlags: 2)
        var offsetOperators = offsetWorld["operator"] as! [[String: Any]]
        offsetOperators[1]["origin"] = "-22 20 0"; offsetWorld["operator"] = offsetOperators
        var offsetLocal = root(threshold: 20)
        var offsetLocalOperators = offsetLocal["operator"] as! [[String: Any]]
        offsetLocalOperators[1]["origin"] = "1 0 0"; offsetLocal["operator"] = offsetLocalOperators
        let originBoundary = forcePlan(parse(offsetWorld), env) == nil
            && forcePlan(parse(offsetLocal), env) != nil
        let unavailable = SceneParticleControlPointForceEnvironment.unavailable
        let childBoundary = forcePlan(ordinary, unavailable) == nil
            && forcePlan(parse(root(threshold: 20)), unavailable) != nil
            && forcePlan(moving, unavailable) == nil
        let output: [String: Any] = ["projection": projection, "legacyUnknownDefault": unknown.defaultMaximumDistance == nil,
            "malformedThreshold": malformed, "world": world, "admission": admissions, "invalidFrames": invalidFrames,
            "fixedWorldAfterTranslation": vector(frame(shifted)!.localPosition(worldPoint: fixedTarget)!),
            "rollbackRestoresForceFrame": rollback, "prewarmUsesInitialFrame": prewarm,
            "unpreparedChildKeepsExplicitLocalOnly": childBoundary, "worldZeroIsRejectedLocalZeroPreserved": zeroBoundary, "worldOffsetRejectedLocalOriginPreserved": originBoundary]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
