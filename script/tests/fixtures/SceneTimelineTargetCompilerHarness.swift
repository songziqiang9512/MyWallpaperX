
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
    let isNamedBinding = true
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
            "layerColorRuntime": layerColorRuntime(descriptor: descriptor, program: program,
                snapshots: [first.snapshot, second.snapshot]),
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

    static func layerColorRuntime(descriptor: SceneRenderDescriptor, program: SceneTimelineProgram,
                                  snapshots: [SceneDynamicSnapshot]) -> [String: Any] {
        let definitions = SceneTimelineRuntime.mergedDefinitions(propertyDefinitions: [], timelineProgram: program)
        let timelineValues = SceneTimelineRuntime.values(program: program, sceneTime: 1)
        var layers: [String: Any] = [:]
        for layer in descriptor.layers {
            let target = SceneDynamicTarget.layer(layerID: layer.id, field: .color)
            func observation(_ snapshot: SceneDynamicSnapshot) -> [String: Any] {
                let color = SceneDynamicLayerValues.color(layerID: layer.id,
                    authoredValue: layer.colorRGB, snapshot: snapshot)
                return ["value": snapshot[target].map { describe($0.value) } ?? "missing",
                        "source": snapshot[target]?.source.rawValue ?? "missing",
                        "consumed": [color.x, color.y, color.z],
                        "alpha": SceneDynamicLayerValues.alpha(layerID: layer.id,
                            authoredValue: layer.alpha, snapshot: snapshot),
                        "alphaSource": snapshot[.layer(layerID: layer.id, field: .alpha)]?.source.rawValue ?? "missing"]
            }
            var result: [String: Any] = ["phases": snapshots.map(observation)]
            if program.bindings.contains(where: { $0.target == target }) {
                let user = SceneDynamicValue.vector3(0.25, 0.75, 0.125)
                let script = SceneDynamicValue.vector3(0.5, 0.125, 0.75)
                let stages: [(String, SceneDynamicValue?, Bool, SceneDynamicValue?)] = [
                    ("authored", nil, false, nil), ("user", user, false, nil),
                    ("timeline", user, true, nil), ("script", user, true, script),
                    ("invalid-script", user, true, .scalar(1)),
                    ("invalid-user", .scalar(1), false, nil),
                ]
                var transaction = SceneEvaluationTransaction()
                var sources: [String: Any] = [:]
                for (index, stage) in stages.enumerated() {
                    let resolution = transaction.evaluate(frameIndex: UInt64(index + 1),
                        definitions: definitions, userValues: stage.1.map { [target: $0] } ?? [:],
                        timelineValues: stage.2 ? timelineValues : [:],
                        sceneScriptValues: stage.3.map { [target: $0] } ?? [:])
                    var value = observation(resolution.snapshot)
                    value["diagnostics"] = resolution.diagnostics.filter { $0.target == target }.map(\.code.rawValue)
                    sources[stage.0] = value
                }
                result["sources"] = sources
            }
            layers[String(layer.id)] = result
        }
        return layers
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
        func scene(_ wrapper: Any?, layerID: Int, resource: String,
                   rawColor: String? = nil, version: Any? = 3, scriptedAlpha: Bool = false) -> [String: Any] {
            var instance: [String: Any] = [:]
            if let wrapper { instance["colorn"] = wrapper }
            if let rawColor { instance["color"] = rawColor }
            if scriptedAlpha {
                instance["alpha"] = ["value": 0.5, "script": "export function update(value) { return value; }"]
            }
            var particle: [String: Any] = ["id": layerID, "name": "carrier-\(layerID)", "particle": resource]
            if !instance.isEmpty { particle["instanceoverride"] = instance }
            var root: [String: Any] = ["objects": [
                particle,
                ["id": layerID + 1, "image": "models/healthy-\(layerID).json", "alpha": [
                    "value": 1, "animation": ["c0": [key(0, 0), key(30, 1)],
                        "options": ["fps": 30, "length": 60, "mode": "loop"]]]],
            ]]
            if let version { root["version"] = version }
            return root
        }
        func compile(_ root: [String: Any], admittedAlphaFor id: Int? = nil) throws
            -> (SceneRenderDescriptor, SceneTimelineProgram) {
            let url = URL(fileURLWithPath: "/fixture/particle-timeline.json")
            let document = try SceneDocumentLoader().load(data: JSONSerialization.data(withJSONObject: root), sourcePath: url.path)
            let authored = try makeDescriptor(document: document, sceneURL: url)
            var admittedTargets: Set<SceneDynamicTarget> = []
            if let id {
                guard authored.layers.first(where: { $0.id == id })?.particleInstanceOverride?.alpha?.hasScript == true
                else { throw HarnessError.descriptorRejected }
                admittedTargets.insert(.particle(layerID: id, field: .alpha))
            }
            let descriptor = SceneScriptParticleProjection.apply(admittedTargets: admittedTargets, to: authored)
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
        func particle(flags: Int = 0, material: String, initializerColor: String? = nil) -> SceneParticleDefinition {
            var initializers: [[String: Any]] = [["name": "lifetimerandom", "min": 10, "max": 10]]
            if let initializerColor {
                initializers.append(["name": "colorrandom", "min": initializerColor, "max": initializerColor])
            }
            return SceneParticleDefinitionParser().parse(root: ["flags": flags, "maxcount": 20,
                "material": material,
                "emitter": [["name": "boxrandom", "rate": 4, "distancemin": 0, "distancemax": 0]],
                "initializer": initializers, "renderer": [["name": "sprite"]]])
        }
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
            let definition = particle(flags: flags,
                material: renamed ? "materials/second-color.json" : "materials/first-color.json")
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
        let id = 81
        let target = SceneDynamicTarget.particle(layerID: id, field: .normalizedColor)
        let wrapper: [String: Any] = ["value": "0.25 0.5 0.75", "animation": animation()]
        let authoredLegacy = "64 128 191"
        let directLegacy = SIMD3<Double>(64, 128, 191) / 255
        let squaredLegacy = SIMD3<Double>(4096, 16384, 36481) / 65025
        let resource = "particles/revision-color.json"
        let definition = particle(material: "materials/revision-color.json", initializerColor: authoredLegacy)
        func equivalentColors(_ actual: [SIMD3<Double>], _ expected: [SIMD3<Double>]) -> Bool {
            actual.count == expected.count && zip(actual, expected).allSatisfy { left, right in
                let error = left - right
                return max(abs(error.x), abs(error.y), abs(error.z)) < 1e-12
            }
        }
        func authoredBirthColors(_ root: [String: Any]) throws -> [SIMD3<Double>] {
            let (descriptor, _) = try compile(root)
            let simulator = SceneParticleSimulator(definition: definition,
                instanceOverride: descriptor.layers.first { $0.id == id }?.particleInstanceOverride,
                seed: 31, fixedTimeStep: 0.25)
            simulator.advance(by: 0.25)
            return simulator.particles.map(\.color)
        }
        for version in [1, 3, 4, 5] {
            let name = "version-\(version)"
            let (descriptor, program) = try compile(scene(wrapper, layerID: id, resource: resource, version: version,
                scriptedAlpha: true), admittedAlphaFor: id)
            let authored = descriptor.layers.first { $0.id == id }?.particleInstanceOverride
            let quarter = snapshot(program, phase: 0.25)
            let resolved = SceneParticleInstanceOverride.resolving(authored: authored,
                dynamic: quarter.particleInstanceValues(layerID: id))
            let simulator = SceneParticleSimulator(definition: definition, instanceOverride: authored,
                seed: 31, fixedTimeStep: 0.25)
            simulator.advance(by: 0.25)
            let first = simulator.particles
            let checkpoint = simulator.frameSnapshot()
            simulator.advance(by: 0.25, dynamicInstanceOverride: resolved)
            let second = simulator.particles
            simulator.restoreFrame(checkpoint)
            simulator.advance(by: 0.25, dynamicInstanceOverride: resolved)
            let replayed = simulator.particles == second
            simulator.restoreFrame(checkpoint)
            try simulator.emitExplicitly(count: 1, context: .init(instanceOverride: resolved)) { _ in }
            let explicit = simulator.particles.map(\.color)
            simulator.restoreFrame(checkpoint)
            simulator.advance(by: 0.25)
            let restored = simulator.particles.map(\.color)

            let expectedAuthored = version == 5 ? SIMD3<Double>(0.25, 0.5, 0.75) : SIMD3(0.0625, 0.25, 0.5625)
            let expectedDynamic = version == 5 ? SIMD3<Double>(0.75, 0, 0.25) : SIMD3(0.5625, 0, 0.0625)
            checks[name + "-projected-alpha-keeps-authored-value"] = authored?.alpha?.hasScript == false
                && first.map(\.alpha) == [0.5]
            checks[name + "-authored-fallback-color"] = first.map(\.color) == [expectedAuthored]
            checks[name + "-timeline-interpolates-authored-space"] = quarter[target]?.value == .vector3(0.75, 0, 0.25)
            checks[name + "-dynamic-affects-new-births-only"] = equivalentColors(second.map(\.color), [expectedAuthored, expectedDynamic])
                && second.first?.id == first.first?.id
            checks[name + "-explicit-birth-uses-resolved-color"] = equivalentColors(explicit, [expectedAuthored, expectedDynamic])
            checks[name + "-snapshot-restores-color-and-replays-particle-states"] = replayed
                && restored == [expectedAuthored, expectedAuthored]

            let (legacyDescriptor, legacyProgram) = try compile(scene(wrapper, layerID: id, resource: resource,
                rawColor: authoredLegacy, version: version, scriptedAlpha: true), admittedAlphaFor: id)
            let legacyAuthored = legacyDescriptor.layers.first { $0.id == id }?.particleInstanceOverride
            let legacyFrame = snapshot(legacyProgram, phase: 0.25)
            let legacy = SceneParticleSimulator(definition: definition, instanceOverride: legacyAuthored,
                seed: 31, fixedTimeStep: 0.25)
            legacy.advance(by: 0.25, dynamicInstanceOverride: SceneParticleInstanceOverride.resolving(
                authored: legacyAuthored, dynamic: legacyFrame.particleInstanceValues(layerID: id)))
            let expectedLegacy = version == 5 ? directLegacy : squaredLegacy
            let legacyColor = legacy.particles.first?.color ?? .zero
            checks[name + "-legacy-priority-and-255-units"] = legacyFrame[target]?.value == .vector3(0.75, 0, 0.25)
                && legacy.particles.count == 1 && zip(vector(legacyColor), vector(expectedLegacy)).allSatisfy { actual, expected in
                    abs(actual - expected) < 1e-12
                }

            let plain = try authoredBirthColors(scene(nil, layerID: id, resource: resource, version: version))
            checks[name + "-no-override-preserves-color-initializer"] = plain == [directLegacy]

            let uncoloredDefinition = particle(material: "materials/default-birth-color.json")
            let uncolored = SceneParticleSimulator(definition: uncoloredDefinition, instanceOverride: authored,
                seed: 31, fixedTimeStep: 0.25)
            uncolored.advance(by: 0.25)
            uncolored.advance(by: 0.25, dynamicInstanceOverride: resolved)
            checks[name + "-default-birth-color-keeps-authored-override"] = uncolored.particles.map(\.color) == [
                SIMD3<Double>(0.25, 0.5, 0.75), SIMD3<Double>(0.75, 0, 0.25),
            ]
            let uncoloredLegacy = SceneParticleSimulator(definition: uncoloredDefinition, instanceOverride: legacyAuthored,
                seed: 31, fixedTimeStep: 0.25)
            uncoloredLegacy.advance(by: 0.25)
            checks[name + "-default-birth-color-keeps-legacy-255-override"] = uncoloredLegacy.particles.map(\.color) == [directLegacy]
            observations[name] = ["timeline": quarter[target].map { describe($0.value) } ?? "missing",
                "first": first.map { vector($0.color) }, "second": second.map { vector($0.color) },
                "explicit": explicit.map(vector), "restored": restored.map(vector),
                "legacy": vector(legacyColor), "plain": plain.map(vector)]
        }
        let additionalVersions: [(String, Any?, Bool)] = [
            ("missing", nil, true), ("0", 0, true), ("2", 2, true), ("6", 6, false), ("string-5", "5", true),
        ]
        for (label, version, legacy) in additionalVersions {
            let name = "version-" + label
            let colors = try authoredBirthColors(scene("0.25 0.5 0.75", layerID: id,
                resource: resource, version: version))
            let expected = legacy ? SIMD3<Double>(0.0625, 0.25, 0.5625) : SIMD3(0.25, 0.5, 0.75)
            checks[name + "-authored-color"] = colors == [expected]
            observations[name] = colors.map(vector)
        }
        for version in [4, 5] {
            let normalized = try authoredBirthColors(scene("0.25 -0.5 0.75", layerID: id,
                resource: resource, version: version))
            let legacy = try authoredBirthColors(scene(nil, layerID: id, resource: resource,
                rawColor: "64 -128 191", version: version))
            checks["version-\(version)-negative-colorn-keeps-initializer"] = normalized == [directLegacy]
            checks["version-\(version)-negative-color-keeps-initializer"] = legacy == [directLegacy]
            observations["version-\(version)-negative"] = ["colorn": normalized.map(vector), "color": legacy.map(vector)]
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
