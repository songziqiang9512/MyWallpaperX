
import Foundation
enum SceneGraphRenderTargetPlan { enum TextureFormat { case rgba16f, rgbaBackbuffer } }

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? { authoredSize }
}
struct SceneProject {
    let rootURL: URL
    let entryPath: String
    let userProperties: SceneUserPropertyCatalog
    var entryURL: URL { rootURL.appendingPathComponent(entryPath) }
}
struct SceneMdlPuppetAttachment {
    let name: String
    let sceneBindFrameColumnMajor: [Float]
}
struct SceneShaderContract {
    enum SourceKind { case hostBuiltin, authoredSource }
    struct Graph {
        struct Node {
            enum Provenance { case stock }
            let provenance: Provenance
        }
        let diagnostics: [String]
        let nodes: [Node]
    }
    let identity: String
    let sourceKind: SourceKind
    let sourceGraph: Graph?
}
struct SceneAssetCatalog {
    struct ModelAsset {
        var declaredSizeWH: [Float]? { nil }
        var passthrough: Bool? { nil }
        let relativePath: String
        let materialPath: String?
        let cropOffsetXY: [Float]?
        let isSolidLayer: Bool
        let puppetPath: String?
        let puppetAttachments: [SceneMdlPuppetAttachment]
    }
    struct MaterialAsset {
        struct Pass {
            let shader: String?
            let textures: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let userShaderValues: [String: String]
            let blending: String?
            let depthTest: String?
            let depthWrite: String?
            let cullMode: String?
            let alphaWriting: String?
        }
        let relativePath: String
        let rawSHA256: String
        let shaderPathIndependentSHA256: String
        let passes: [Pass]
    }
    let models: [ModelAsset]
    let materials: [MaterialAsset]
    let effectDefinitions: [SceneEffectDefinition]
    let effectDefinitionDiagnostics: [SceneEffectDefinitionDiagnostic]
    let shaderReferences: [String]
    var shaderContracts: [SceneShaderContract] { [] }
    let textureReferences: [String]
}
struct SceneResourceReferenceIndex {
    let missingReferences: [String]
    let builtInReferenceCount: Int
    let runtimeProvidedReferenceCount: Int
}
struct SceneCapabilityProfile { let firstStageRendererGaps: [String] }

struct SceneDiagnosticsReport {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let capabilityProfile: SceneCapabilityProfile?
}

enum HarnessError: Error { case missingFixture, descriptorRejected }

@main
enum Harness {
    static func main() throws {
        guard (2...3).contains(CommandLine.arguments.count) else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        if CommandLine.arguments.last == "particle-color" {
            print(String(decoding: try JSONSerialization.data(withJSONObject: particleColorTimeline(),
                options: [.sortedKeys]), as: UTF8.self))
            return
        }
        var descriptor = try makeDescriptor(document: document, sceneURL: sceneURL)
        if CommandLine.arguments.last == "duplicate-timeline" {
            // Duplicate a prepared typed target, after the real Loader's distinct-ID gate.
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as! [String: Any]
            var layers = object["layers"] as! [[String: Any]]
            var timelines = layers[0]["timelines"] as! [[String: Any]]
            timelines.append(timelines[1])
            layers[0]["timelines"] = timelines
            object["layers"] = layers
            descriptor = try JSONDecoder().decode(SceneRenderDescriptor.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        if CommandLine.arguments.last == "duplicate-group-layer" {
            // Prepared duplicate target: the full Compiler owns final group rejection.
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as! [String: Any]
            var layers = object["layers"] as! [[String: Any]]
            layers.append(layers[0])
            object["layers"] = layers
            descriptor = try JSONDecoder().decode(SceneRenderDescriptor.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        if let mode = CommandLine.arguments.last, mode.hasPrefix("typed-response:") {
            // Wire strings parse as nil. This separate IR boundary explicitly decodes IEEE values.
            let parts = mode.split(separator: ":").map(String.init)
            guard parts.count == 3, ["smoothing", "stiffness"].contains(parts[1]) else {
                throw HarnessError.missingFixture
            }
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as! [String: Any]
            var layers = object["layers"] as! [[String: Any]]
            var timelines = layers[0]["timelines"] as! [[String: Any]]
            let root = timelines.firstIndex { timeline in
                let animation = timeline["animation"] as? [String: Any]
                let options = animation?["options"] as? [String: Any]
                return !(options?["children"] as? [[String: Any]] ?? []).isEmpty
            }!
            var animation = timelines[root]["animation"] as! [String: Any]
            var options = animation["options"] as! [String: Any]
            options[parts[1]] = parts[2]
            animation["options"] = options
            timelines[root]["animation"] = animation
            layers[0]["timelines"] = timelines
            object["layers"] = layers
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
            descriptor = try decoder.decode(SceneRenderDescriptor.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        let program = SceneTimelineTargetCompiler.compile(descriptor: descriptor)
        let vectorTarget = SceneDynamicTarget.effectConstant(
            layerID: 30,
            effectIndex: 1,
            passIndex: 1,
            name: "neutralVector"
        )
        let definitions = SceneTimelineRuntime.mergedDefinitions(
            propertyDefinitions: [],
            timelineProgram: program
        )
        var transaction = SceneEvaluationTransaction()
        let first = transaction.evaluate(
            frameIndex: 1,
            definitions: definitions,
            timelineValues: SceneTimelineRuntime.values(
                program: program,
                sceneTime: 0
            )
        )
        let second = transaction.evaluate(
            frameIndex: 2,
            definitions: definitions,
            timelineValues: SceneTimelineRuntime.values(
                program: program,
                sceneTime: 1
            )
        )
        let firstVector = first.snapshot[vectorTarget]
        let secondVector = second.snapshot[vectorTarget]
        let cameraPathFOV: Double =
            descriptor.layers.first(where: { $0.id == 66 })?.cameraPath?.fov ?? -1
        let firstValue = firstVector.map { describe($0.value) } ?? "missing"
        let firstSource = firstVector?.source.rawValue ?? "missing"
        let firstDiagnostics = first.diagnostics.map(\.code.rawValue)
        let secondValue = secondVector.map { describe($0.value) } ?? "missing"
        let secondSource = secondVector?.source.rawValue ?? "missing"
        let secondDiagnostics = second.diagnostics.map(\.code.rawValue)
        let vectorRuntime: [String: Any] = [
            "firstValue": firstValue,
            "firstSource": firstSource,
            "firstGeneration": first.snapshot.generation,
            "firstDiagnostics": firstDiagnostics,
            "secondValue": secondValue,
            "secondSource": secondSource,
            "secondGeneration": second.snapshot.generation,
            "secondDiagnostics": secondDiagnostics,
        ]
        let payload: [String: Any] = [
            "diagnostics": program.diagnostics,
            "cameraPathFOV": cameraPathFOV,
            "vectorRuntime": vectorRuntime,
            "bindings": program.bindings.enumerated().map { index, binding -> [String: Any] in
                [
                    "target": describe(binding.definition.target),
                    "targetIndex": index,
                    "valueType": binding.definition.valueType.rawValue,
                    "authored": describe(binding.definition.authoredValue),
                    "mode": binding.animation.options.mode.rawValue,
                    "componentCount": binding.animation.componentCount,
                    "composition": binding.composition.rawValue,
                    "playbackOwner": binding.playbackOwner.map(describe) ?? "self",
                    "fps": binding.animation.options.fps,
                    "length": binding.animation.options.length,
                    "paused": binding.animation.options.startsPaused,
                    "name": binding.animation.options.name ?? "",
                    "sample": SceneTimelineRuntime.values(program: program, sceneTime: 1)[binding.target].map(describe) ?? "missing",
                ]
            },
        ]
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ), as: UTF8.self))
    }

    static func makeDescriptor(document: SceneDocument, sceneURL: URL) throws -> SceneRenderDescriptor {
        guard let descriptor = SceneRenderDescriptorBuilder().build(
            project: SceneProject(
                rootURL: sceneURL.deletingLastPathComponent(),
                entryPath: sceneURL.lastPathComponent,
                userProperties: .empty
            ),
            sceneDocument: document,
            assetCatalog: SceneAssetCatalog(
                models: [], materials: [], effectDefinitions: [],
                effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []
            ),
            resourceReferences: SceneResourceReferenceIndex(
                missingReferences: [], builtInReferenceCount: 0,
                runtimeProvidedReferenceCount: 0
            ),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])
        ) else {
            throw HarnessError.descriptorRejected
        }
        return descriptor
    }

    static func particleColorTimeline() throws -> [String: Any] {
        func key(_ frame: Int, _ value: Any) -> [String: Any] { ["frame": frame, "value": value] }
        func animation(renamed: Bool = false) -> [String: Any] {
            let middle = renamed ? 30 : 15, end = renamed ? 60 : 30
            return ["c0": [key(0, 1), key(middle, 0.5), key(end, 0)],
                "c1": [key(0, 0), key(end, 0)],
                "c2": [key(0, 0), key(middle, 0.5), key(end, 1)],
                "options": ["fps": renamed ? 60 : 30, "length": renamed ? 120 : 60, "mode": "loop"]]
        }
        func scene(_ wrapper: [String: Any], layerID: Int, resource: String,
                   rawColor: String? = nil) -> [String: Any] {
            var instance: [String: Any] = ["colorn": wrapper]
            if let rawColor { instance["color"] = rawColor }
            return ["version": 3, "objects": [
                ["id": layerID, "name": "carrier-\(layerID)", "particle": resource, "instanceoverride": instance],
                ["id": layerID + 1, "image": "models/healthy-\(layerID).json", "alpha": [
                    "value": 1, "animation": ["c0": [key(0, 0), key(30, 1)],
                        "options": ["fps": 30, "length": 60, "mode": "loop"]]]],
            ]]
        }
        func compile(_ root: [String: Any]) throws -> (SceneRenderDescriptor, SceneTimelineProgram) {
            let url = URL(fileURLWithPath: "/fixture/particle-timeline.json")
            let document = try SceneDocumentLoader().load(data: JSONSerialization.data(withJSONObject: root), sourcePath: url.path)
            let descriptor = try makeDescriptor(document: document, sceneURL: url)
            return (descriptor, SceneTimelineTargetCompiler.compile(descriptor: descriptor))
        }
        func snapshot(_ program: SceneTimelineProgram, phase: Double) -> SceneDynamicSnapshot {
            var clock = SceneClock(hostTime: 100)
            let time = clock.advance(hostTime: 100 + phase, wallDate: Date(timeIntervalSince1970: 0))
            var transaction = SceneEvaluationTransaction()
            return transaction.evaluate(frameIndex: time.frameIndex,
                definitions: SceneTimelineRuntime.mergedDefinitions(propertyDefinitions: [], timelineProgram: program),
                timelineValues: SceneTimelineRuntime.values(program: program, sceneTime: time.sceneTime)).snapshot
        }
        func vector(_ value: SIMD3<Double>) -> [Double] { [value.x, value.y, value.z] }
        var checks: [String: Bool] = [:], observations: [String: Any] = [:]
        let red = SIMD3<Double>(1, 0, 0), blue = SIMD3<Double>(0, 0, 1), white = SIMD3<Double>(repeating: 1)
        for (name, renamed, flags, raw) in [("two-color", false, 0, nil as String?),
                ("renamed-equivalent", true, 0, nil), ("flag8", false, 8, nil),
                ("raw255-precedence", true, 0, "255 0 0")] {
            let id = renamed ? 731 : 51
            let resource = renamed ? "particles/renamed/nested-resource.json" : "particles/color.json"
            let root = scene(["value": "1 1 1", "animation": animation(renamed: renamed)],
                layerID: id, resource: resource, rawColor: raw)
            let (descriptor, program) = try compile(root)
            let target = SceneDynamicTarget.particle(layerID: id, field: .normalizedColor)
            let original = descriptor.layers.first { $0.id == id }!.particleInstanceOverride
            let phases = [0.0, 1.0, 2.0].map { snapshot(program, phase: $0) }
            let resolved = phases.map { SceneParticleInstanceOverride.resolving(authored: original,
                dynamic: $0.particleInstanceValues(layerID: id)) }
            let definition = SceneParticleDefinitionParser().parse(root: ["flags": flags, "maxcount": 20,
                "material": renamed ? "materials/second-color.json" : "materials/first-color.json",
                "emitter": [["name": "boxrandom", "rate": 4, "distancemin": 0, "distancemax": 0]],
                "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
                "renderer": [["name": "sprite"]]])
            let simulator = SceneParticleSimulator(definition: definition, instanceOverride: original,
                initialDynamicInstanceOverride: resolved[0], seed: 31, fixedTimeStep: 0.25)
            simulator.advance(by: 0.25, dynamicInstanceOverride: resolved[0])
            let first = simulator.particles
            simulator.advance(by: 0.25, dynamicInstanceOverride: resolved[1])
            let second = simulator.particles
            simulator.advance(by: 0.25, dynamicInstanceOverride: resolved[2])
            let third = simulator.particles
            let expectedFirst = flags == 8 ? white : red
            let expectedSecond = flags == 8 ? white : raw == nil ? blue : red
            checks[name + "-binding"] = program.bindings.filter { $0.target == target }.count == 1
            checks[name + "-timeline-source"] = phases.allSatisfy { $0[target]?.source == .timeline }
            checks[name + "-two-birth-colors"] = first.count == 1 && second.count == 2
                && first[0].color == expectedFirst && second[1].color == expectedSecond
            checks[name + "-old-population-unchanged"] = first.count == 1 && second.first?.id == first.first?.id
                && second.first?.color == first.first?.color && third.first?.color == first.first?.color
            checks[name + "-loop-new-birth"] = third.count == 3 && third[2].color == expectedFirst
            checks[name + "-healthy-peer"] = phases[1][.layer(layerID: id + 1, field: .alpha)]?.value == .scalar(1)
            observations[name] = ["bindings": program.bindings.map { describe($0.target) },
                "diagnostics": program.diagnostics, "firstColors": first.map { vector($0.color) },
                "secondColors": second.map { vector($0.color) }, "thirdColors": third.map { vector($0.color) },
                "phaseValues": phases.map { $0[target].map { describe($0.value) } ?? "missing" }]
        }
        for name in ["wrong-lane", "relative", "group", "script-mixed", "user-mixed", "nonfinite-lane", "nonfinite-seed", "wrong-seed-shape", "raw-color-lane"] {
            var curve = animation(), wrapper: [String: Any] = ["value": "1 1 1"]
            switch name {
            case "wrong-lane": curve.removeValue(forKey: "c2")
            case "relative": curve["relative"] = true
            case "group":
                var options = curve["options"] as! [String: Any]
                options["children"] = [["key": "alpha"]]; curve["options"] = options
            case "script-mixed": wrapper["script"] = "export function update(v) { return v; }"
            case "user-mixed": wrapper["user"] = "unrelated-color-property"
            case "nonfinite-lane": curve["c1"] = [key(0, 0), key(30, "NaN")]
            case "nonfinite-seed": wrapper["value"] = "NaN 0 0"
            case "wrong-seed-shape": wrapper["value"] = "1 0"
            default: break
            }
            wrapper["animation"] = curve
            var root = scene(wrapper, layerID: 93, resource: "particles/rejected.json")
            if name == "raw-color-lane" {
                var objects = root["objects"] as! [[String: Any]]
                objects[0]["instanceoverride"] = ["color": wrapper]; root["objects"] = objects
            }
            let (_, program) = try compile(root)
            let values = snapshot(program, phase: 1)
            checks[name + "-locally-rejected"] = !program.bindings.contains {
                $0.target == .particle(layerID: 93, field: .normalizedColor)
            }
            checks[name + "-healthy-peer"] = values[.layer(layerID: 94, field: .alpha)]?.value == .scalar(1)
            observations[name] = ["bindings": program.bindings.map { describe($0.target) }, "diagnostics": program.diagnostics]
        }
        return ["checks": checks, "observations": observations]
    }

    static func describe(_ target: SceneDynamicTarget) -> String {
        switch target {
        case let .camera(field): "camera:\(field.rawValue)"
        case let .layer(layerID, field): "layer:\(layerID):\(field.rawValue)"
        case let .effectConstant(layerID, effectIndex, passIndex, name):
            "constant:\(layerID):\(effectIndex):\(passIndex):\(name)"
        case let .particle(layerID, field):
            switch field {
            case .alpha: "particle:\(layerID):alpha"
            case .size: "particle:\(layerID):size"
            case .count: "particle:\(layerID):count"
            case .normalizedColor: "particle:\(layerID):normalizedColor"
            case let .controlPoint(index): "particle:\(layerID):controlpoint:\(index)"
            case let .controlPointAngles(index): "particle:\(layerID):angles:\(index)"
            default: "particle:\(layerID):other"
            }
        case let .text(layerID, field): "text:\(layerID):\(field.rawValue)"
        default: "other"
        }
    }

    static func describe(_ value: SceneDynamicValue) -> String {
        switch value {
        case let .scalar(v): "scalar(\(v))"
        case let .vector2(x, y): "vector2(\(x),\(y))"
        case let .vector3(x, y, z): "vector3(\(x),\(y),\(z))"
        case let .vector4(x, y, z, w): "vector4(\(x),\(y),\(z),\(w))"
        case .bool, .string: "other"
        }
    }
}
