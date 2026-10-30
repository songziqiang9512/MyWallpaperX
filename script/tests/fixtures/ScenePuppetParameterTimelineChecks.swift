import Foundation
import simd

enum ScenePuppetParameterTimelineChecks {
    static func curve(_ pairs: [(Double, Double)]) -> [String: Any] {
        ["options": ["fps": 1, "length": 4, "mode": "single"],
         "c0": pairs.map { ["frame": $0.0, "value": $0.1] }]
    }

    static func animationLayer(_ id: Int, renamed: Bool = false) -> [String: Any] {
        ["id": id, "animation": 100, "name": renamed ? "Other motion" : "Motion",
         "visible": ["value": true, "script": "export function update(value){return value;}"],
         "rate": ["value": 1, "animation": curve([(0, 0), (1, 0), (2, 1), (4, 1)])],
         "blend": ["value": 1, "animation": curve([(0, 0), (1, 0), (2, 1.5), (4, 1.5)])],
         "additive": false, "blendin": false, "blendout": false, "blendtime": 0]
    }

    static func descriptor(_ clips: [[String: Any]], id: Int, renamed: Bool = false) throws -> SceneRenderDescriptor {
        let object: [String: Any] = ["id": id, "name": renamed ? "Other subject" : "Subject",
            "image": renamed ? "models/renamed.json" : "models/subject.json",
            "size": "100 100", "animationlayers": clips]
        let root: [String: Any] = ["objects": [object]]
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("parameters.json")
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        let document = try SceneDocumentLoader().load(from: url)
        return SceneRenderDescriptorBuilder().build(project: SceneProject(
            rootURL: url.deletingLastPathComponent(), entryPath: url.lastPathComponent,
            userProperties: .empty), sceneDocument: document,
            assetCatalog: SceneAssetCatalog(models: [], materials: [], effectDefinitions: [],
                effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []),
            resourceReferences: SceneResourceReferenceIndex(missingReferences: [],
                builtInReferenceCount: 0, runtimeProvidedReferenceCount: 0),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: []))!
    }

    static func target(_ parent: Int, _ id: Int, _ field: String) -> SceneDynamicTarget {
        .scriptInstanceProperty(layerID: parent, path: ["puppetAnimationLayer", String(id), field])
    }

    static func clipAnimation() -> SceneMdlPuppetAnimation {
        .init(id: 100, name: "Pose", mode: "single", framesPerSecond: 1, frameCount: 4,
            transformsByBone: [(0...4).map { .init(translation: SIMD3(Float($0), 0, 0),
                rotation: .zero, scale: SIMD3(repeating: 1)) }],
            alphaByBone: [[1, 0.75, 0.5, 0.25, 0]])
    }

    static func runtime(_ descriptor: SceneRenderDescriptor)
        throws -> (ScenePuppetAnimationPlaybackRuntime, ScenePuppetAnimationSelection) {
        let layer = descriptor.layers[0]
        let selection = try ScenePuppetAnimationSelector.select(layers: layer.puppetAnimationLayers,
            animationSet: .init(boneCount: 1, animations: [clipAnimation()])).get()!
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: layer.id, selection: selection,
            authoredLayers: layer.puppetAnimationLayers).get()
        return (runtime, selection)
    }

    static func snapshot(_ program: SceneTimelineProgram, at time: Double, frame: UInt64,
                         extra: [SceneDynamicTarget: SceneDynamicValue] = [:],
                         definitions: [SceneDynamicTargetDefinition] = [],
                         scripts: [SceneDynamicTarget: SceneDynamicValue] = [:]) -> SceneDynamicSnapshot {
        var values = SceneTimelineRuntime.values(program: program, sceneTime: time)
        values.merge(extra) { _, next in next }
        return SceneDynamicSnapshotResolver().resolve(frameIndex: frame, generation: 1,
            definitions: program.bindings.map(\.definition) + definitions, timelineValues: values,
            sceneScriptValues: scripts).snapshot
    }

    static func evaluator(_ selection: ScenePuppetAnimationSelection) throws -> ScenePuppetAnimationEvaluator {
        let matrix: [Float] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
        let rig = SceneMdlPuppetRig(bones: [.init(parentIndex: -1,
            bindLocalMatrixColumnMajor: matrix)], vertexWeights: [.init(
                boneIndices: SIMD4(0,0,0,0), boneWeights: SIMD4(1,0,0,0))])
        return try .init(bindPositions: [SIMD3(1,0,0)], rig: rig,
            additiveAnimations: selection.clips.map(\.animation))
    }

    static func run() throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for (parent, id, renamed) in [(42, 91, false), (73, 208, true)] {
            let authored = animationLayer(id, renamed: renamed)
            let descriptor = try descriptor([authored], id: parent, renamed: renamed)
            let program = SceneTimelineTargetCompiler.compile(descriptor: descriptor)
            let rate = target(parent, id, "rate"), blend = target(parent, id, "blend")
            let prefix = "\(parent)-\(id)"
            checks[prefix + "-targets"] = Set(program.bindings.map(\.target)) == [rate, blend]
                && program.diagnostics.isEmpty
            let (runtime, selection) = try runtime(descriptor)
            let evaluator = try evaluator(selection)
            var phases: [Double] = [], positions: [Float] = [], coverages: [Float] = []
            var local = [matrix_identity_float4x4], skin = local, world = local
            var output = [SIMD2<Float>.zero]
            for frame in 0...3 {
                let sampled = runtime.advance(frameIndex: UInt64(frame), sceneTime: Double(frame),
                    dynamicValues: snapshot(program, at: Double(frame), frame: UInt64(frame)))
                let pose = sampled[parent]!
                phases.append(sampled.animationSnapshots[0].currentFrame)
                try output.withUnsafeMutableBufferPointer {
                    try evaluator.writeDeformedPositions(selection: selection, frameSamples: pose.samples,
                        into: $0, localMatricesScratch: &local, skinMatricesScratch: &skin,
                        worldMatricesScratch: &world, blends: pose.blends)
                }
                positions.append(output[0].x)
                var coverage: [Float] = [0], scratch: [Float] = [0]
                try evaluator.writeVertexCoverages(selection: selection, frameSamples: pose.samples,
                    blends: pose.blends, into: &coverage, boneScratch: &scratch)
                coverages.append(coverage[0])
            }
            checks[prefix + "-zero-rate-starts-on-scene-clock"] = phases == [0,0,1,2]
            checks[prefix + "-blend-controls-pose-and-alpha"] = positions == [1,1,2.5,4]
                && coverages == [1,1,0.625,0.25]
            let same = runtime.advance(frameIndex: 3, sceneTime: 99,
                dynamicValues: snapshot(program, at: 0, frame: 3))
            checks[prefix + "-same-cadence"] = same.animationSnapshots[0].currentFrame == 2
                && same.animationSnapshots[0].blend == 1.5
            let visibility = ScenePuppetAnimationPropertyTarget.visibility(layerID: parent, animationLayerID: id)
            let visibilityDefinition = SceneDynamicTargetDefinition(target: visibility,
                valueType: .bool, authoredValue: .bool(true))
            let hidden = runtime.advance(frameIndex: 4, sceneTime: 4,
                dynamicValues: snapshot(program, at: 4, frame: 4,
                    definitions: [visibilityDefinition], scripts: [visibility: .bool(false)]))
            let restored = runtime.advance(frameIndex: 5, sceneTime: 5,
                dynamicValues: snapshot(program, at: 5, frame: 5,
                    definitions: [visibilityDefinition], scripts: [visibility: .bool(true)]))
            checks[prefix + "-visibility-keeps-frozen-position"] = hidden[parent]!.samples[0] == nil
                && hidden.animationSnapshots[0].currentFrame == 2
                && restored.animationSnapshots[0].currentFrame == 3
            for (offset, bad) in [Double(-1), 1e100].enumerated() {
                let badFrame = runtime.advance(frameIndex: UInt64(offset + 6), sceneTime: Double(offset + 6),
                    dynamicValues: snapshot(program, at: 4, frame: UInt64(offset + 6),
                        extra: [rate: .scalar(bad), blend: .scalar(bad)]))
                checks[prefix + "-invalid-local-\(offset)"] = badFrame.animationSnapshots[0].rate == 1
                    && badFrame.animationSnapshots[0].blend == 1.5
            }
            var equivalent = authored
            equivalent["rate"] = ["value": 1, "animation": curve([(0,0),(0.5,0),(1,0),(2,1),(3,1),(4,1)])]
            let equivalentProgram = SceneTimelineTargetCompiler.compile(descriptor:
                try self.descriptor([equivalent], id: parent, renamed: !renamed))
            checks[prefix + "-equivalent-curve"] = [0.0,0.5,1,1.5,2,3].allSatisfy {
                SceneTimelineRuntime.values(program: equivalentProgram, sceneTime: $0)[rate]
                    == SceneTimelineRuntime.values(program: program, sceneTime: $0)[rate]
            }
            for field in ["rate", "blend"] {
                let healthy = field == "rate" ? blend : rate
                for source in ["script", "user"] {
                    var mixed = authored, wrapper = mixed[field] as! [String: Any]
                    wrapper[source] = source == "script" ? "export function update(v){return v;}" : "setting"
                    mixed[field] = wrapper
                    let rejected = SceneTimelineTargetCompiler.compile(descriptor:
                        try self.descriptor([mixed], id: parent))
                    checks[prefix + "-mixed-\(field)-\(source)"] = Set(rejected.bindings.map(\.target)) == [healthy]
                        && rejected.diagnostics.contains { $0.contains(field) }
                    wrapper[source] = NSNull(); mixed[field] = wrapper
                    let nullSource = SceneTimelineTargetCompiler.compile(descriptor:
                        try self.descriptor([mixed], id: parent))
                    checks[prefix + "-null-source-\(field)-\(source)"] = Set(nullSource.bindings.map(\.target)) == [rate, blend]
                        && nullSource.diagnostics.isEmpty
                }
                var malformed = authored
                malformed[field] = ["value": 1, "animation": ["c0": [["frame": 0, "value": 0]]]]
                let rejected = SceneTimelineTargetCompiler.compile(descriptor:
                    try self.descriptor([malformed], id: parent))
                checks[prefix + "-malformed-\(field)"] = Set(rejected.bindings.map(\.target)) == [healthy]
                    && !rejected.diagnostics.isEmpty
                var configured = authored, metadata = configured[field] as! [String: Any]
                metadata["scriptproperties"] = ["unused": 0.5]; configured[field] = metadata
                let configuredProgram = SceneTimelineTargetCompiler.compile(descriptor:
                    try self.descriptor([configured], id: parent))
                checks[prefix + "-unused-configuration-\(field)"] = Set(configuredProgram.bindings.map(\.target)) == [rate, blend]
            }
            var zero = authored, zeroRate = zero["rate"] as! [String: Any]
            zeroRate["value"] = 0; zero["rate"] = zeroRate
            let zeroDescriptor = try self.descriptor([zero], id: parent)
            let zeroSelection = ScenePuppetAnimationSelector.select(
                layers: zeroDescriptor.layers[0].puppetAnimationLayers,
                animationSet: .init(boneCount: 1, animations: [clipAnimation()]))
            if case let .success(selection?) = zeroSelection {
                let zeroRuntime = ScenePuppetAnimationPlaybackRuntime()
                try zeroRuntime.register(layerID: parent, selection: selection,
                    authoredLayers: zeroDescriptor.layers[0].puppetAnimationLayers).get()
                let zeroProgram = SceneTimelineTargetCompiler.compile(descriptor: zeroDescriptor)
                _ = zeroRuntime.advance(frameIndex: 0, sceneTime: 0,
                    dynamicValues: snapshot(zeroProgram, at: 0, frame: 0))
                let resumed = zeroRuntime.advance(frameIndex: 1, sceneTime: 2,
                    dynamicValues: snapshot(zeroProgram, at: 2, frame: 1))
                checks[prefix + "-zero-fallback-gets-real-consumer"] = resumed.animationSnapshots[0].rate == 1
                    && resumed.animationSnapshots[0].currentFrame == 2
            } else { checks[prefix + "-zero-fallback-gets-real-consumer"] = false }
            for (name, edit) in [("relative", ["relative": true]),
                                  ("combined", ["options": ["fps": 1, "length": 4,
                                      "mode": "single", "parent": ["key": "blend"]]])] as [(String, [String: Any])] {
                var rejectedLayer = authored, wrapper = rejectedLayer["rate"] as! [String: Any]
                var changed = wrapper["animation"] as! [String: Any]
                changed.merge(edit) { _, next in next }; wrapper["animation"] = changed
                rejectedLayer["rate"] = wrapper
                let rejected = SceneTimelineTargetCompiler.compile(descriptor:
                    try self.descriptor([rejectedLayer], id: parent))
                checks[prefix + "-\(name)"] = Set(rejected.bindings.map(\.target)) == [blend]
                    && !rejected.diagnostics.isEmpty
            }
            var noID = authored; noID.removeValue(forKey: "id")
            let missing = SceneTimelineTargetCompiler.compile(descriptor:
                try self.descriptor([noID], id: parent))
            let duplicate = SceneTimelineTargetCompiler.compile(descriptor:
                try self.descriptor([authored, authored], id: parent))
            checks[prefix + "-missing-duplicate-identity"] = missing.bindings.isEmpty
                && duplicate.bindings.isEmpty && !missing.diagnostics.isEmpty && !duplicate.diagnostics.isEmpty
        }
        let base = animationLayer(91)
        var plain = base; plain["rate"] = 1; plain["blend"] = 1
        let plainDescriptor = try descriptor([plain], id: 42)
        let (plainRuntime, _) = try runtime(plainDescriptor)
        let rate = target(42, 91, "rate"), blend = target(42, 91, "blend")
        let definitions = [rate,blend].map { SceneDynamicTargetDefinition(target: $0,
            valueType: .scalar, authoredValue: .scalar(1)) }
        let injected = SceneDynamicSnapshotResolver().resolve(frameIndex: 0, generation: 1,
            definitions: definitions, timelineValues: [rate: .scalar(99), blend: .scalar(99)]).snapshot
        let unchanged = plainRuntime.advance(frameIndex: 0, sceneTime: 0, dynamicValues: injected)
        checks["unprepared-timeline99-ignored"] = unchanged.animationSnapshots[0].rate == 1
            && unchanged.animationSnapshots[0].blend == 1
        plain["rate"] = 0
        let zeroDescriptor = try descriptor([plain], id: 42)
        let zeroSelection = ScenePuppetAnimationSelector.select(
            layers: zeroDescriptor.layers[0].puppetAnimationLayers,
            animationSet: .init(boneCount: 1, animations: [clipAnimation()]))
        if case .success = zeroSelection {
            let (zeroRuntime, _) = try runtime(zeroDescriptor)
            let first = zeroRuntime.advance(frameIndex: 0, sceneTime: 0, dynamicValues: .empty(frameIndex: 0))
            let later = zeroRuntime.advance(frameIndex: 1, sceneTime: 10, dynamicValues: .empty(frameIndex: 1))
            checks["static-zero-rate-freezes"] = first.animationSnapshots[0].currentFrame == 0
                && later.animationSnapshots[0].currentFrame == 0 && later.animationSnapshots[0].rate == 0
        } else { checks["static-zero-rate-freezes"] = false }
        for (index, bad) in [Double(-1), .nan, .infinity, -.infinity].enumerated() {
            let result = ScenePuppetAnimationSelector.select(layers: [layer(animationID: 100, rate: bad)],
                animationSet: .init(boneCount: 1, animations: [clipAnimation()]))
            if case .failure(.unsupportedLayer) = result {
                checks["static-invalid-rate-\(index)"] = true
            } else { checks["static-invalid-rate-\(index)"] = false }
        }
        return checks
    }
}
