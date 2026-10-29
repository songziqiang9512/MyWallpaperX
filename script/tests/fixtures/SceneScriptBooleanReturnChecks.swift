import Foundation

/// Real typed Bool Program/ValueOwner callbacks: return acceptance, continued
/// events/timers, and the independent failure/transaction boundaries.
enum SceneScriptBooleanReturnChecks {
    static let target = SceneDynamicTarget.layer(layerID: 73, field: .visibility)

    static func descriptor(_ name: String = "own-return-probe") -> SceneRenderDescriptor {
        var layer = SceneRenderDescriptor.Layer(id: 73, layerIndex: 0, name: name,
            visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            alpha: 1, effects: [], sizeWH: [80, 80])
        layer.imagePath = "models/\(name).json"
        return .init(layers: [layer])
    }

    static func program(_ source: String, name: String = "own-return-probe") throws
        -> SceneScriptVectorProgram {
        let domain = try SceneScriptQuickJSDomain()
        let scene = descriptor(name)
        try domain.configureLayerCatalog(scene)
        try domain.configureLayerRuntimeFields(scene)
        return .compile(domain: domain, descriptor: scene, scriptBindings: [
            .init(source: source,
                owner: .init(kind: .object, objectIndex: 0, objectID: 73,
                    effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(0), .key("visible")],
                properties: [:], authoredValue: .bool(false), valueType: .boolean,
                wrapperKeys: ["script", "value"])
        ], userPropertyDefinitions: [], generation: 61)
    }

    static func frame(_ time: Double) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 0.05, sceneTime: time))
    }

    static func evaluate(_ program: SceneScriptVectorProgram, input: Bool,
                         time: Double = 1, budget: UInt64? = nil) -> SceneScriptVectorFrameResult {
        program.evaluate(inputs: [target: .bool(input)], effectivePropertyValues: [:],
            frame: frame(time), interruptBudget: budget)
    }

    static func value(_ result: SceneScriptVectorFrameResult) -> Bool? {
        guard case let .bool(value)? = result.values[target] else { return nil }
        return value
    }

    static func preparedVideoChecks() throws -> [String: Bool] {
        let paths = ["models/prepared-selection.json", "models/renamed-selection.json"]
        let still = "models/neighbor-still.json", unbound = "models/unbound-selection.json"
        let incarnation = UUID(uuidString: "00000000-0000-0000-0000-000000000073")!
        var templates = Dictionary(uniqueKeysWithValues: (paths + [unbound]).map {
            ($0, SceneScriptPreparedResourceLayerTemplate(modelPath: $0,
                renderSizeWH: [320, 180], autosize: true, isVideo: true))
        })
        templates[still] = .init(modelPath: still, renderSizeWH: [20, 10], autosize: true)
        func makeProgram(_ source: String, peer: String? = nil,
                         configuration: SceneJSONValue? = nil) throws -> SceneScriptVectorProgram {
            let domain = try SceneScriptQuickJSDomain()
            var scene = descriptor()
            scene.layers[0].initialConfiguration = configuration
            if peer != nil {
                scene.layers.append(.init(id: 74, layerIndex: 1, name: "independent-peer",
                    visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                    alpha: 1, effects: [], sizeWH: [80, 80]))
            }
            try domain.configureLayerCatalog(scene)
            try domain.configurePreparedResourceLayerCatalog(templates)
            try domain.configurePreparedVideoSources(Dictionary(uniqueKeysWithValues: paths.map { ($0, 0) }))
            try domain.publishLayerSnapshot(
                SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1, definitions: []).snapshot,
                descriptor: scene, videoSnapshots: .init(sources: [
                    .init(sourceIncarnation: incarnation, duration: 10, rate: 1, loop: true,
                        currentTime: 3, isPlaying: true, endedGeneration: 0)
                ], layerBindings: [:]))
            let bindings = ([source] + (peer.map { [$0] } ?? [])).enumerated().map { index, source in
                SceneScriptBindingIR(source: source,
                    owner: .init(kind: .object, objectIndex: index, objectID: 73 + index,
                        effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                    targetPath: [.key("objects"), .index(index), .key("visible")],
                    properties: [:], authoredValue: .bool(false), valueType: .boolean,
                    wrapperKeys: ["script", "value"])
            }
            return .compile(domain: domain, descriptor: scene, scriptBindings: bindings,
                userPropertyDefinitions: [], generation: 73)
        }
        var facts: [String: Bool] = [:]
        for (index, seed) in [false, true].enumerated() {
            let initial: SceneJSONValue = .object([
                "id": .number(73), "image": .string(paths[index]),
                "visible": .object(["script": .string("// inactive visibility\n/* raw authored data */"), "value": .bool(seed)]),
                "solid": .object(["user": .string("unresolved-neighbor"), "value": .bool(!seed)]),
            ])
            let program = try makeProgram("""
                export function update(value) {
                    const inherited = thisScene.getInitialLayerConfig(thisLayer);
                    const before = JSON.stringify(inherited);
                    if (inherited.visible.value !== \(seed) || inherited.solid.value !== \(!seed) ||
                        inherited.visible.script !== '// inactive visibility\\n/* raw authored data */' || 'id' in inherited)
                        throw Error('initial Boolean envelopes were rewritten');
                    const fresh = thisScene.createLayer(inherited);
                    if (!fresh || fresh.visible !== \(seed) || fresh.solid !== \(!seed))
                        throw Error('inherited Boolean literal not consumed');
                    fresh.visible = true;
                    if (fresh.visible !== true || inherited.visible.value !== \(seed) || JSON.stringify(inherited) !== before)
                        throw Error('scalar setter changed inherited configuration');
                    fresh.getVideoTexture().play(); thisScene.destroyLayer(fresh);
                    let reads = 0;
                    Object.defineProperty(inherited.visible, 'script', {get(){++reads;throw Error('script getter executed');}});
                    Object.defineProperty(inherited.solid, 'user', {get(){++reads;throw Error('user getter executed');}});
                    const spied = thisScene.createLayer(inherited);
                    if (!spied || spied.visible !== \(seed) || spied.solid !== \(!seed) || reads !== 0)
                        throw Error('constructor evaluated Boolean property controls');
                    spied.getVideoTexture().play(); thisScene.destroyLayer(spied);
                    thisLayer.visible = true;
                    if (thisLayer.visible !== true || JSON.stringify(thisScene.getInitialLayerConfig(thisLayer)) !== before)
                        throw Error('current visibility replaced initial raw value');
                    return false;
                }
                """, configuration: initial)
            let result = evaluate(program, input: false)
            let commands = SceneScriptMediaPlaybackCommandBridge.orderedCommands(in: result.ownerEffects)
            let born = result.layerMutations.filter(\.isNewborn)
            facts["inherited-envelope-\(seed)-raw-scalar-and-controls"] = result.failures.isEmpty
                && value(result) == true && born.count == 2 && commands.count == 2
                && born.allSatisfy { $0.assetPath == paths[index] && $0.solid == !seed && $0.kind == .destroy }
                && commands.allSatisfy { $0.action == .play && $0.videoSourceIncarnation == incarnation }
                && commands.first.flatMap { command in born.first { $0.layerID == command.layerID } }?.visible == true
            program.finalizeLayerMutations(committing: true)
        }
        for (label, field, invalid) in [
            ("number", "visible", "{value:1}"), ("string", "solid", "{value:'false'}"),
            ("missing", "visible", "{script:'// no value'}"), ("nested", "solid", "{value:{value:false}}"),
            ("truthy-object", "visible", "{value:{}}"), ("scalar-number", "solid", "1"),
            ("scalar-string", "visible", "'true'"),
        ] {
            let program = try makeProgram("""
                export function update(value) {
                    const provisional = thisScene.createLayer({name:'rejected-envelope-layer',image:'\(paths[0])'});
                    provisional.getVideoTexture().play();
                    const inherited = thisScene.getInitialLayerConfig(thisLayer);
                    inherited.\(field) = \(invalid);
                    thisScene.createLayer(inherited); return value;
                }
                """, peer: """
                export function update(value) {
                    if (thisScene.getLayer('rejected-envelope-layer') !== null) throw Error('failed owner escaped');
                    const layer = thisScene.createLayer('\(paths[1])');
                    layer.getVideoTexture().play(); thisScene.destroyLayer(layer); return true;
                }
                """, configuration: .object(["image": .string(paths[0]), "visible": .object(["value": .bool(false)]),
                    "solid": .object(["value": .bool(true)])]))
            let peerTarget = SceneDynamicTarget.layer(layerID: 74, field: .visibility)
            let result = program.evaluate(inputs: [target: .bool(false), peerTarget: .bool(false)],
                effectivePropertyValues: [:], frame: frame(1))
            let commands = SceneScriptMediaPlaybackCommandBridge.orderedCommands(in: result.ownerEffects)
            facts["invalid-envelope-\(label)-rejects-only-owner"] = result.failures[target]?.code == "exception"
                && result.failures[peerTarget] == nil && result.values[peerTarget] == .bool(true)
                && result.ownerEffects.allSatisfy { $0.ownerTarget == peerTarget }
                && result.layerMutations.filter(\.isNewborn).count == 1
                && result.layerMutations.filter(\.isNewborn).allSatisfy { $0.assetPath == paths[1] }
                && commands.count == 1 && commands.first?.videoSourceIncarnation == incarnation
            program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [target])
        }
        for (index, path) in paths.enumerated() {
            let argument = index == 0 ? "{image:'\(path)',name:'selected'}"
                : "{name:'renamed',image:'models/'+'renamed-selection.json'}"
            let program = try makeProgram("""
                let previous, phase = 0;
                export function update(value) {
                    ++phase;
                    if (previous) thisScene.destroyLayer(previous);
                    const fresh = thisScene.createLayer(\(argument));
                    if (!fresh) throw Error('prepared-only video failed to construct');
                    const video = fresh.getVideoTexture();
                    if (!video || video.duration !== 10 || video.rate !== 1 || video.getCurrentTime() !== 3)
                        throw Error('prepared Source observation missing');
                    video.play(); video.setCurrentTime(4);
                    if (video.getCurrentTime() !== 3) throw Error('journal invented a media clock');
                    const image = thisScene.createLayer('\(still)');
                    const label = thisScene.createLayer({text:'neighbor'});
                    if (!image || !label || image.getVideoTexture() !== undefined || label.getVideoTexture() !== undefined)
                        throw Error('neighbor resource acquired video capability');
                    thisScene.destroyLayer(image); thisScene.destroyLayer(label);
                    if (phase === 3) { thisScene.destroyLayer(fresh); previous = null; }
                    else previous = fresh;
                    return value;
                }
                """)
            facts["variant\(index)-prepared-without-video-prototype"] = program.definitions.count == 1
                && program.descriptor.layers.count == 1 && program.descriptor.modelMaterialLinks.isEmpty
                && program.descriptor.layers.allSatisfy { $0.imagePath != path }
            var bornIDs: Set<Int> = []
            for phase in 1...3 {
                let result = evaluate(program, input: true, time: Double(phase))
                let commands = SceneScriptMediaPlaybackCommandBridge.orderedCommands(in: result.ownerEffects)
                let born = result.layerMutations.first { $0.isNewborn && $0.assetPath == path }
                facts["variant\(index)-phase\(phase)-Bool-and-resource"] = result.failures.isEmpty
                    && value(result) == true && born?.isDynamic == true
                    && born?.kind == (phase == 3 ? .destroy : .upsert)
                    && (phase == 1 || result.layerMutations.contains { $0.kind == .destroy && bornIDs.contains($0.layerID) })
                if let born {
                    let epoch = commands.first?.callbackEpoch ?? 0
                    facts["variant\(index)-phase\(phase)-typed-media-order"] = epoch > 0 && commands == [
                        .init(layerID: born.layerID, action: .play, callbackEpoch: epoch,
                            ordinal: 0, videoSourceIncarnation: incarnation),
                        .init(layerID: born.layerID, action: .setCurrentTime(4), callbackEpoch: epoch,
                            ordinal: 1, videoSourceIncarnation: incarnation),
                    ]
                    bornIDs.insert(born.layerID)
                } else { facts["variant\(index)-phase\(phase)-typed-media-order"] = false }
                program.finalizeLayerMutations(committing: true)
            }
            facts["variant\(index)-three-distinct-logical-consumers"] = bornIDs.count == 3
        }
        for path in ["models/not-prepared.json", unbound] {
            let program = try makeProgram("""
                export function update(value) {
                    if (thisScene.createLayer({image:'\(path)'}) !== null) throw Error('resource admission escaped');
                    return value;
                }
                """)
            let result = evaluate(program, input: true)
            facts["C-catalog-rejects-\(path)"] = result.failures.isEmpty && value(result) == true
                && result.layerMutations.isEmpty
                && SceneScriptMediaPlaybackCommandBridge.orderedCommands(in: result.ownerEffects).isEmpty
            program.finalizeLayerMutations(committing: true)
        }
        let failed = try makeProgram("""
            export function update(value) {
                const layer = thisScene.createLayer('\(paths[0])');
                layer.getVideoTexture().play(); throw Error('reject this owner');
            }
            """, peer: """
            export function update(value) {
                const layer = thisScene.createLayer('\(paths[1])');
                layer.getVideoTexture().play(); thisScene.destroyLayer(layer); return value;
            }
            """)
        let peerTarget = SceneDynamicTarget.layer(layerID: 74, field: .visibility)
        let result = failed.evaluate(inputs: [target: .bool(true), peerTarget: .bool(true)],
            effectivePropertyValues: [:], frame: frame(1))
        let commands = SceneScriptMediaPlaybackCommandBridge.orderedCommands(in: result.ownerEffects)
        facts["failed-video-owner-does-not-export-media-or-mutations"] = result.failures[target]?.code == "exception"
            && result.failures[peerTarget] == nil && result.ownerEffects.allSatisfy { $0.ownerTarget == peerTarget }
            && result.layerMutations.filter(\.isNewborn).allSatisfy { $0.assetPath == paths[1] }
            && commands.count == 1 && commands.first?.action == .play
            && commands.first?.videoSourceIncarnation == incarnation
        failed.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [target])
        return facts
    }

    static func run() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        // Opposite input makes accidental truthiness observable. These are
        // independent self-authored expressions, never a Workshop module.
        let cases: [(String, String, Bool, Bool)] = [
            ("native-true", "true", false, true),
            ("native-false", "false", true, false),
            ("undefined", "undefined", true, true),
            ("zero", "2 - 2", true, true),
            ("negative", "-(1 + 1)", false, false),
            ("nan", "0 / 0", true, true),
            ("null", "null", true, true),
            ("empty-string", "''", true, true),
            ("nonempty-string", "'not-a-boolean'", false, false),
            ("vector", "new Vec3(0, 0, 0)", false, false),
            ("object", "({})", false, false),
            ("array", "[]", false, false),
            ("conversion-hooks", "({[Symbol.toPrimitive](){throw Error('coercion');},valueOf(){throw Error('coercion');},toString(){throw Error('coercion');}})", false, false),
        ]
        for phase in ["init", "update"] {
            for (label, expression, input, expected) in cases {
                let source = """
                    export function \(phase)(incoming) {
                        engine.setTimeout(() => { thisLayer.origin = new Vec3(71, 2, 3); }, 0);
                        return \(expression);
                    }
                    """ + (phase == "init" ? "\nexport function update(current){return current;}" : "")
                let owner = try program(source)
                let first = evaluate(owner, input: input)
                owner.finalizeLayerMutations(committing: true)
                let second = evaluate(owner, input: input, time: 2)
                facts["\(phase)-\(label)-typed-return"] = owner.definitions.count == 1
                    && first.failures.isEmpty && second.failures.isEmpty
                    && value(first) == expected && value(second) == (phase == "init" ? input : expected)
                facts["\(phase)-\(label)-timer-side-effect"] = (first.layerMutations + second.layerMutations)
                    .contains { $0.layerID == 73 && $0.fields.contains(.origin) && $0.origin == .init(71, 2, 3) }
                owner.finalizeLayerMutations(committing: true)
            }
        }

        for (index, counter) in ["launchCount", "起動回数", "starts"].enumerated() {
            let returns = ["new Vec3(0, 0, 0)", "({})", "0 / 0"]
            let owner = try program("""
                let \(counter)=0, presses=0, ticks=0;
                export function init(seed) {
                    ++\(counter); engine.setTimeout(() => { ++ticks; }, 0);
                    return \(returns[index]);
                }
                export function cursorClick(event) { presses = presses + 1; }
                export function update(current) {
                    thisLayer.origin = new Vec3(\(counter), presses, ticks);
                    return \(returns[(index + 1) % returns.count]);
                }
                """, name: "renamed-resource-\(index)")
            let first = evaluate(owner, input: false)
            owner.finalizeLayerMutations(committing: true)
            guard let cursor = owner.cursorOwnerRegistrations.first else {
                facts["continuity-\(index)-cursor-registration"] = false
                continue
            }
            let clicked = try cursor.owner.dispatchCursor(
                .init(kind: .click, layerID: 73, worldPosition: .zero, localPosition: .zero),
                frame: frame(2), scriptPropertiesJSON: "", userPropertiesJSON: "{}").get()
            let second = evaluate(owner, input: true, time: 2)
            owner.finalizeLayerMutations(committing: true)
            let third = evaluate(owner, input: false, time: 3)
            facts["continuity-\(index)-init-once-cursor-and-timer"] = first.failures.isEmpty
                && clicked.layers.isEmpty && second.failures.isEmpty && third.failures.isEmpty
                && value(first) == false && value(second) == true && value(third) == false
                && [second, third].allSatisfy { result in result.layerMutations.contains {
                    $0.fields.contains(.origin) && $0.origin == .init(1, 1, 1)
                } }
            owner.finalizeLayerMutations(committing: true)
            let stale = cursor.owner.evaluate(input: .bool(false), frame: frame(4),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 62,
                interruptBudget: nil)
            if case let .failure(error) = stale {
                facts["continuity-\(index)-stale-still-rejected"] = error == .staleOwner
            } else { facts["continuity-\(index)-stale-still-rejected"] = false }
        }

        for (label, body, budget) in [
            ("throw", "throw Error('independent exception');", Optional<UInt64>.none),
            ("budget", "while(true){}", Optional<UInt64>.some(100)),
        ] {
            let owner = try program("""
                export function update(current) {
                    thisLayer.origin = new Vec3(9, 9, 9); \(body)
                }
                """)
            let rejected = evaluate(owner, input: true, budget: budget)
            facts["\(label)-keeps-atomic-failure"] = rejected.values.isEmpty
                && rejected.layerMutations.isEmpty && rejected.failures.count == 1
                && rejected.failures[target]?.code == (label == "throw" ? "exception" : "budget-exceeded")
            owner.finalizeLayerMutations(committing: false)
            let peer = try program("export function update(current){return false;}")
            let healthy = evaluate(peer, input: true)
            facts["\(label)-healthy-peer"] = healthy.failures.isEmpty && value(healthy) == false
            peer.finalizeLayerMutations(committing: true)
        }
        return facts
    }
}
