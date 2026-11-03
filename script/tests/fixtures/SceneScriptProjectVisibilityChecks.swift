import Foundation

/// Self-authored root utility callbacks through the real projection,
/// QuickJS owner, Boolean result and side-effect journal.
enum SceneScriptProjectVisibilityChecks {
    private static func scene(ownerID: Int, peerID: Int, name: String,
                              effectName: String,
                              kind: SceneUtilityLayer.Kind = .project) -> SceneRenderDescriptor {
        var project = SceneRenderDescriptor.Layer(
            id: ownerID, layerIndex: 0, name: "\(name)-\(kind.rawValue)",
            visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            alpha: 1, effects: [], contentKind: kind.rawValue)
        project.imagePath = "models/util/\(kind.rawValue)layer.json"
        project.utilityLayer = .init(kind: kind, copyBackground: false,
                                     passthrough: false)
        var peer = SceneRenderDescriptor.Layer(
            id: peerID, layerIndex: 1, name: name, visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1,
            effects: [.init(name: effectName, effectID: peerID + 1, visible: true)])
        peer.imagePath = "models/\(name).json"
        return .init(layers: [project, peer])
    }

    private static func binding(ownerID: Int, source: String,
                                seed: SceneJSONValue = .bool(false),
                                wrapperKeys: [String] = ["script", "value"]) -> SceneScriptBindingIR {
        .init(source: source,
              owner: .init(kind: .object, objectIndex: 0, objectID: ownerID,
                           effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
              targetPath: [.key("objects"), .index(0), .key("visible")],
              properties: [:], authoredValue: seed, valueType: .boolean,
              wrapperKeys: wrapperKeys)
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
        facts.merge(try fullscreenChecks()) { _, current in current }
        return facts
    }

    private static func fullscreenChecks() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (index, names) in [("screen-card", "tone-filter", "showCard"),
                               ("renamed-surface", "renamed-filter", "enabledPane")].enumerated() {
            let ownerID = 310 + index * 40, peerID = ownerID + 9
            var descriptor = scene(ownerID: ownerID, peerID: peerID,
                name: names.0, effectName: names.1, kind: .fullscreen)
            descriptor.layers[1].imagePath = "models/renamed-assets/\(names.0).json"
            let target = SceneDynamicTarget.layer(layerID: ownerID, field: .visibility)
            let resultExpression = index == 0 ? "allowed" : "allowed ? true : false"
            let source = """
                let initialized = false, allowed = false;
                export function init(incoming) {
                    initialized = incoming === false;
                    return incoming;
                }
                export function applyUserProperties(properties) {
                    allowed = properties.\(names.2);
                }
                export function update(incoming) {
                    if (!initialized) throw Error('init seed missing');
                    const filter = thisScene.getLayer('\(names.0)').getEffect('\(names.1)');
                    if (filter.visible !== true) throw Error('discarded effect survived');
                    filter.visible = allowed;
                    return \(resultExpression);
                }
                """
            let property = SceneUserPropertyDefinition(
                key: names.2, title: names.0, kind: .bool, runtimeType: "bool",
                order: 0, index: nil, minimumValue: nil, maximumValue: nil,
                stepValue: nil, allowsFractionalValues: false, fractionalPrecision: nil,
                displayCondition: nil, defaultValue: .bool(false), options: [])
            let domain = try SceneScriptQuickJSDomain()
            try domain.configureLayerCatalog(descriptor)
            try domain.configureLayerRuntimeFields(descriptor)
            let program = SceneScriptVectorProgram.compile(
                domain: domain, descriptor: descriptor,
                scriptBindings: [binding(ownerID: ownerID, source: source)],
                userPropertyDefinitions: [property], generation: UInt64(ownerID))
            let first = program.evaluate(inputs: [target: .bool(false)],
                effectivePropertyValues: [names.2: .bool(false)], frame: frame(1),
                propertyRevision: 1)
            facts["fullscreen-\(index)-init-property-event-and-update"] = program.definitions.count == 1
                && first.failures.isEmpty && value(first, target: target) == false
                && effectValue(first, layerID: peerID) == false
                && first.ownerEffects.count == 1
                && first.ownerEffects.first?.ownerTarget == target
            program.finalizeLayerMutations(committing: false)
            let second = program.evaluate(inputs: [target: .bool(false)],
                effectivePropertyValues: [names.2: .bool(true)], frame: frame(2),
                propertyRevision: 2)
            facts["fullscreen-\(index)-discard-then-reveal"] = second.failures.isEmpty
                && value(second, target: target) == true
                && effectValue(second, layerID: peerID) == true
            program.finalizeLayerMutations(committing: true)
            let third = program.evaluate(inputs: [target: .bool(true)],
                effectivePropertyValues: [names.2: .bool(false)], frame: frame(3),
                propertyRevision: 3)
            facts["fullscreen-\(index)-later-property-event-hides"] = third.failures.isEmpty
                && value(third, target: target) == false
                && effectValue(third, layerID: peerID) == false
            program.finalizeLayerMutations(committing: true)
        }

        let base = scene(ownerID: 410, peerID: 419, name: "boundary-peer",
                         effectName: "boundary-filter", kind: .fullscreen)
        let probe = binding(ownerID: 410,
                            source: "export function update(value) { return value; }")
        func projected(_ descriptor: SceneRenderDescriptor,
                       bindings: [SceneScriptBindingIR]? = nil) -> Bool {
            !SceneScriptVectorProgram.project(descriptor: descriptor,
                scriptBindings: bindings ?? [probe]).targets.isEmpty
        }
        for (label, seed) in [("string", SceneJSONValue.string("false")),
                              ("number", .number(0))] {
            facts["fullscreen-\(label)-seed-rejected"] = !projected(base, bindings: [
                binding(ownerID: 410, source: probe.source, seed: seed)])
        }
        facts["fullscreen-unknown-wrapper-rejected"] = !projected(base, bindings: [
            binding(ownerID: 410, source: probe.source,
                    wrapperKeys: ["script", "value", "unknown"])])
        let duplicate = SceneScriptVectorProgram.project(descriptor: base,
            scriptBindings: [probe, probe])
        facts["fullscreen-duplicate-target-rejected"] = duplicate.targets.isEmpty
            && duplicate.duplicateTargets == [.layer(layerID: 410, field: .visibility)]
        var image = base
        image.layers[0].contentKind = "image"
        image.layers[0].utilityLayer = nil
        facts["ordinary-image-owner-preserved"] = projected(image)
        let domain = try SceneScriptQuickJSDomain()
        let wrongReturn = SceneScriptVectorProgram.compile(domain: domain, descriptor: base,
            scriptBindings: [binding(ownerID: 410,
                source: "export function update(value) { return 'true'; }")],
            userPropertyDefinitions: [], generation: 410)
        let target = SceneDynamicTarget.layer(layerID: 410, field: .visibility)
        let preserved = wrongReturn.evaluate(inputs: [target: .bool(false)],
            effectivePropertyValues: [:], frame: frame(1))
        wrongReturn.finalizeLayerMutations(committing: true)
        facts["fullscreen-non-Bool-return-preserves-typed-input"] = wrongReturn.definitions.count == 1
            && preserved.failures.isEmpty && value(preserved, target: target) == false
        return facts
    }
}
