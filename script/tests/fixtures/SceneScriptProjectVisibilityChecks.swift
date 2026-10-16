import Foundation

/// Self-authored project utility callbacks through the real projection,
/// QuickJS owner, Boolean result and side-effect journal.
enum SceneScriptProjectVisibilityChecks {
    private static func scene(ownerID: Int, peerID: Int, name: String,
                              effectName: String) -> SceneRenderDescriptor {
        var project = SceneRenderDescriptor.Layer(
            id: ownerID, layerIndex: 0, name: "\(name)-project",
            visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            alpha: 1, effects: [], contentKind: "project")
        project.imagePath = "models/util/projectlayer.json"
        project.utilityLayer = .init(kind: .project, copyBackground: false,
                                     passthrough: false)
        var peer = SceneRenderDescriptor.Layer(
            id: peerID, layerIndex: 1, name: name, visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1,
            effects: [.init(name: effectName, effectID: peerID + 1, visible: true)])
        peer.imagePath = "models/\(name).json"
        return .init(layers: [project, peer])
    }

    private static func binding(ownerID: Int, source: String,
                                seed: SceneJSONValue = .bool(false)) -> SceneScriptBindingIR {
        .init(source: source,
              owner: .init(kind: .object, objectIndex: 0, objectID: ownerID,
                           effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
              targetPath: [.key("objects"), .index(0), .key("visible")],
              properties: [:], authoredValue: seed, valueType: .boolean,
              wrapperKeys: ["script", "value"])
    }

    private static func frame(_ time: Double) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                           simulationFrameTime: 0.05, sceneTime: time))
    }

    private static func value(_ result: SceneScriptVectorFrameResult,
                              target: SceneDynamicTarget) -> Bool? {
        guard case let .bool(value)? = result.values[target] else { return nil }
        return value
    }

    private static func effectValue(_ result: SceneScriptVectorFrameResult,
                                    layerID: Int) -> Bool? {
        result.layerMutations.first {
            $0.layerID == layerID && $0.fields.contains(.effectVisibility)
        }?.effectVisibilities[0]
    }

    static func run() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (index, names) in [("pane", "filter", "incoming"),
                               ("renamed-card", "second-filter", "flag")].enumerated() {
            let ownerID = 140 + index * 40, peerID = ownerID + 9
            let descriptor = scene(ownerID: ownerID, peerID: peerID,
                                   name: names.0, effectName: names.1)
            let target = SceneDynamicTarget.layer(layerID: ownerID, field: .visibility)
            let resultExpression = index == 0 ? "!\(names.2)" : "\(names.2) ? false : true"
            let source = """
                export function update(\(names.2)) {
                    const peer = thisScene.getLayer('\(names.0)');
                    const filter = peer.getEffect('\(names.1)');
                    if (filter.visible !== true) throw Error('discarded write survived');
                    filter.visible = \(names.2);
                    return \(resultExpression);
                }
                """
            let domain = try SceneScriptQuickJSDomain()
            try domain.configureLayerCatalog(descriptor)
            try domain.configureLayerRuntimeFields(descriptor)
            let program = SceneScriptVectorProgram.compile(
                domain: domain, descriptor: descriptor,
                scriptBindings: [binding(ownerID: ownerID, source: source)],
                userPropertyDefinitions: [], generation: UInt64(140 + index))
            let first = program.evaluate(inputs: [target: .bool(false)],
                effectivePropertyValues: [:], frame: frame(1))
            facts["variant\(index)-constructed-owner"] = program.definitions.count == 1
            facts["variant\(index)-computed-Bool-and-effect"] = first.failures.isEmpty
                && value(first, target: target) == true
                && effectValue(first, layerID: peerID) == false
                && first.ownerEffects.count == 1
                && first.ownerEffects.first?.ownerTarget == target
            program.finalizeLayerMutations(committing: false)
            let second = program.evaluate(inputs: [target: .bool(true)],
                effectivePropertyValues: [:], frame: frame(2))
            facts["variant\(index)-rollback-and-next-callback"] = second.failures.isEmpty
                && value(second, target: target) == false
                && effectValue(second, layerID: peerID) == true
            program.finalizeLayerMutations(committing: true)
        }

        let base = scene(ownerID: 230, peerID: 239, name: "admission-peer",
                         effectName: "ordinary-effect")
        let probe = binding(ownerID: 230,
                            source: "export function update(value) { return value; }")
        func projected(_ descriptor: SceneRenderDescriptor) -> Bool {
            !SceneScriptVectorProgram.project(descriptor: descriptor,
                scriptBindings: [probe]).targets.isEmpty
        }
        var parented = base
        parented.layers[0].parentID = 239
        facts["parented-project-rejected"] = !projected(parented)
        var declaredChild = base
        declaredChild.layers[0].childLayerIDs = [239]
        facts["declared-child-rejected"] = !projected(declaredChild)
        var actualChild = base
        actualChild.layers[1].parentID = 230
        facts["unlisted-actual-child-rejected"] = !projected(actualChild)
        actualChild.layers[0].childLayerIDs = [239]
        facts["matching-child-subtree-rejected"] = !projected(actualChild)
        var dependency = base
        dependency.layers[0].dependencyLayerIDs = [239]
        facts["dependency-rejected"] = !projected(dependency)
        var authoredDependency = base
        authoredDependency.layers[0].authoredDependencies = [239]
        facts["authored-dependency-rejected"] = !projected(authoredDependency)
        var missingUtility = base
        missingUtility.layers[0].utilityLayer = nil
        facts["missing-utility-kind-rejected"] = !projected(missingUtility)
        var mismatchedUtility = base
        mismatchedUtility.layers[0].utilityLayer = .init(
            kind: .fullscreen, copyBackground: false, passthrough: false)
        facts["mismatched-utility-kind-rejected"] = !projected(mismatchedUtility)
        var compositionAsProject = base
        compositionAsProject.layers[0].utilityLayer = .init(
            kind: .composition, copyBackground: true, passthrough: false)
        facts["project-with-composition-kind-rejected"] = !projected(compositionAsProject)
        var mismatchedContent = base
        mismatchedContent.layers[0].contentKind = "image"
        facts["mismatched-content-kind-rejected"] = !projected(mismatchedContent)
        var fullscreen = base
        fullscreen.layers[0].contentKind = "fullscreen"
        fullscreen.layers[0].utilityLayer = .init(
            kind: .fullscreen, copyBackground: false, passthrough: false)
        facts["fullscreen-owner-not-expanded"] = !projected(fullscreen)
        var composition = base
        composition.layers[0].contentKind = "composition"
        composition.layers[0].imagePath = "models/util/composelayer.json"
        composition.layers[0].utilityLayer = .init(
            kind: .composition, copyBackground: true, passthrough: false)
        facts["ordinary-composition-owner-preserved"] = projected(composition)
        composition.layers[0].childLayerIDs = [239]
        composition.layers[1].parentID = 230
        facts["composition-child-profile-preserved"] = projected(composition)
        let wrongSeed = binding(ownerID: 230, source: probe.source, seed: .string("false"))
        facts["non-Bool-seed-rejected"] = SceneScriptVectorProgram.project(
            descriptor: base, scriptBindings: [wrongSeed]).targets.isEmpty
        return facts
    }
}
