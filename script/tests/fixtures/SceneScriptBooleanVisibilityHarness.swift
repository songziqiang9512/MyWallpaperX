import Foundation

private func descriptor(
    parentID: Int? = nil,
    effects: [SceneRenderDescriptor.EffectDescriptor] = [],
    effectFiles: [String] = [],
    contentKind: String = "image"
) -> SceneRenderDescriptor {
    SceneRenderDescriptor(layers: [
        .init(
            id: 7,
            layerIndex: 0,
            name: "leaf",
            visible: false,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: nil,
            alpha: 1,
            effects: effects,
            contentKind: contentKind,
            parentID: parentID,
            effectFiles: effectFiles
        ),
    ])
}

private func namedReferenceDescriptor(
    targetIsConsumer: Bool,
    userTextureShadowsReference: Bool = false
) -> SceneRenderDescriptor {
    let providerLayerID = targetIsConsumer ? 8 : 7
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        id: nil,
        constantShaderValues: [:],
        textureSlots: ["_rt_imageLayerComposite_\(providerLayerID)_a"],
        userTextureInputs: userTextureShadowsReference ? [true] : []
    )
    let referenceEffect = SceneRenderDescriptor.EffectDescriptor(
        name: "named-reference",
        passes: [pass],
        id: "named-reference"
    )
    let genericEffect = SceneRenderDescriptor.EffectDescriptor(
        name: "generic-effect"
    )
    return SceneRenderDescriptor(layers: [
        .init(
            id: 7,
            layerIndex: 0,
            name: "leaf",
            visible: false,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: nil,
            alpha: 1,
            effects: targetIsConsumer ? [referenceEffect] : [genericEffect]
        ),
        .init(
            id: 8,
            layerIndex: 1,
            name: "peer",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: nil,
            alpha: 1,
            effects: targetIsConsumer ? [] : [referenceEffect]
        ),
    ])
}

private func dynamicImageDescriptor() -> SceneRenderDescriptor {
    var peer = SceneRenderDescriptor.Layer(
        id: 8, layerIndex: 1, name: "peer", visible: true,
        originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
        scaleHasScript: nil, alpha: 1, effects: []
    )
    peer.contentKind = "text"
    peer.text = "authored"
    peer.textStyle = .init(
        fontPath: nil, colorRGB: [1, 1, 1], pointSize: 32
    )
    return SceneRenderDescriptor(
        layers: [
            .init(
                id: 7, layerIndex: 0, name: "bars", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                scaleHasScript: nil, alpha: 1, effects: [],
                contentKind: "container"
            ),
            peer,
        ],
        modelMaterialLinks: [
            .init(modelPath: "models/workshop/2727665642/bar.json"),
        ]
    )
}

private func binding(
    source: String,
    wrapperKeys: [String] = ["script", "value"],
    authored: Bool = false
) -> SceneScriptBindingIR {
    .init(
        source: source,
        owner: .init(
            kind: .object,
            objectIndex: 0,
            objectID: 7,
            effectIndex: nil,
            effectID: nil,
            passIndex: nil,
            passID: nil
        ),
        targetPath: [.key("objects"), .index(0), .key("visible")],
        properties: [:],
        authoredValue: .bool(authored),
        valueType: .boolean,
        wrapperKeys: wrapperKeys
    )
}

private func frame(runtime: TimeInterval) -> SceneScriptFrameInput {
    .init(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0),
        simulationFrameTime: 1.0 / 60.0,
        sceneTime: runtime
    ))
}

private func boolValue(
    _ result: SceneScriptVectorFrameResult,
    target: SceneDynamicTarget
) -> Bool? {
    guard case let .bool(value)? = result.values[target] else { return nil }
    return value
}

private func evaluateValueOnlyOwner(
    source: String,
    target: SceneDynamicTarget,
    generation: UInt64
) throws -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
    let domain = try SceneScriptQuickJSDomain()
    try domain.configureLayerCatalog(descriptor())
    let owner = try SceneScriptValueOwner(
        domain: domain,
        source: source,
        target: target,
        valueType: .bool,
        effectNames: [],
        generation: generation,
        budget: .default
    )
    return owner.evaluate(
        input: .bool(false),
        frame: frame(runtime: 2),
        scriptPropertiesJSON: "",
        userPropertiesJSON: "{}",
        expectedGeneration: generation,
        interruptBudget: nil
    )
}

private func failureCode(
    _ result: Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure>
) -> String? {
    guard case let .failure(failure) = result else { return nil }
    return failure.code
}

@main
enum Harness {
    static func main() throws {
        // Exercise the real Swift Program -> C owner -> typed Boolean result
        // -> frame finalizer chain, including a rejected submission retry.
        let effectTarget = SceneDynamicTarget.effectVisibility(layerID: 7, effectIndex: 0)
        func effectProgram(_ source: String) throws -> SceneScriptVectorProgram {
            let effectBinding = SceneScriptBindingIR(
                source: source,
                owner: .init(kind: .effect, objectIndex: 0, objectID: 7,
                    effectIndex: 0, effectID: 100, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(0), .key("effects"),
                    .index(0), .key("visible")],
                properties: [:], authoredValue: .bool(true), valueType: .boolean,
                wrapperKeys: ["script", "value"]
            )
            return SceneScriptVectorProgram.compile(
                domain: try SceneScriptQuickJSDomain(),
                descriptor: descriptor(effects: [
                    .init(name: "transaction", effectID: 100, visible: true)
                ]),
                scriptBindings: [effectBinding], userPropertyDefinitions: [], generation: 91
            )
        }
        func effectFrame(_ program: SceneScriptVectorProgram, input: Bool,
                         time: Double) -> SceneScriptVectorFrameResult {
            program.evaluate(inputs: [effectTarget: .bool(input)],
                effectivePropertyValues: [:], frame: frame(runtime: time))
        }
        let effectToggle = try effectProgram("""
            export function update(value) {
                thisObject.visible = !thisObject.visible; return value;
            }
            """)
        precondition(boolValue(effectFrame(effectToggle, input: true, time: 1), target: effectTarget) == false)
        effectToggle.finalizeLayerMutations(committing: true)
        precondition(boolValue(effectFrame(effectToggle, input: false, time: 2), target: effectTarget) == true)
        effectToggle.finalizeLayerMutations(committing: false)
        precondition(boolValue(effectFrame(effectToggle, input: false, time: 3), target: effectTarget) == true)
        effectToggle.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [effectTarget])
        precondition(boolValue(effectFrame(effectToggle, input: false, time: 4), target: effectTarget) == true)
        effectToggle.finalizeLayerMutations(committing: true)
        precondition(boolValue(effectFrame(effectToggle, input: true, time: 5), target: effectTarget) == false)
        effectToggle.finalizeLayerMutations(committing: true)

        let effectRetry = try effectProgram("""
            let first = true;
            export function update(value) {
                if (first) { first = false; thisObject.visible = false; return 'bad'; }
                return thisObject.visible;
            }
            """)
        let failedEffect = effectFrame(effectRetry, input: true, time: 1)
        precondition(boolValue(failedEffect, target: effectTarget) == false)
        precondition(failedEffect.failures.isEmpty)
        effectRetry.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [effectTarget])
        precondition(boolValue(effectFrame(effectRetry, input: true, time: 2), target: effectTarget) == true)
        effectRetry.finalizeLayerMutations(committing: true)

        let effectInit = try effectProgram("""
            export function init(value) { thisObject.visible = false; return value; }
            export function applyUserProperties(properties) {
                if (thisObject.visible !== false) throw new Error('lost init visibility');
            }
            export function update(value) { return thisObject.visible; }
            """)
        precondition(boolValue(effectFrame(effectInit, input: true, time: 1), target: effectTarget) == false)
        effectInit.finalizeLayerMutations(committing: true)
        precondition(boolValue(effectFrame(effectInit, input: false, time: 2), target: effectTarget) == false)
        effectInit.finalizeLayerMutations(committing: true)

        let target = SceneDynamicTarget.layer(layerID: 7, field: .visibility)
        let source = "export function update(value) { return engine.runtime >= 1; }"
        let authoredBinding = binding(source: source)
        let program = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [authoredBinding],
            userPropertyDefinitions: [],
            generation: 1
        )
        let first = program.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 0)
        )
        let second = program.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )

        let badProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(
                // Non-Bool returns preserve the typed input without conversion.
                source: "export function update(value) { return 'yes'; }"
            )],
            userPropertyDefinitions: [],
            generation: 2
        )
        let bad = badProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let badAgain = badProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 3)
        )

        let undefinedProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function update(value) { return undefined; }"
            )],
            userPropertyDefinitions: [],
            generation: 3
        )
        let undefinedResult = undefinedProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )

        let hiddenShared = try evaluateValueOnlyOwner(
            source: "export function update(value) { return shared.enabled; }",
            target: target,
            generation: 4
        )
        let hiddenHandle = try evaluateValueOnlyOwner(
            source: "export function update(value) { return thisScene.getLayerCount() > 0; }",
            target: target,
            generation: 5
        )
        let timer = try evaluateValueOnlyOwner(
            source: """
                export function update(value) {
                    engine.setTimeout(() => {}, 0);
                    return value;
                }
                """,
            target: target,
            generation: 6
        )

        let audioProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                const spectrum = engine["register" + "AudioBuffers"]();
                export function update(value) { return value; }
                """)],
            userPropertyDefinitions: [],
            generation: 7
        )
        let eventAudioDomain = try SceneScriptQuickJSDomain()
        try eventAudioDomain.configureLayerCatalog(descriptor())
        let eventOnlyAudioProgram = SceneScriptVectorProgram.compile(
            domain: eventAudioDomain,
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                const spectrum = engine.registerAudioBuffers(64);
                let callbacks = 0;
                export function mediaPlaybackChanged() {
                    thisLayer.origin = new Vec3(spectrum.left[0], spectrum.right[0], ++callbacks);
                }
                """)],
            userPropertyDefinitions: [],
            generation: 14
        )
        let eventAudio = eventOnlyAudioProgram.evaluate(
            inputs: [target: .bool(true)], effectivePropertyValues: [:],
            frame: frame(runtime: 1), mediaPlaybackEvent: .init(state: 1, generation: 1),
            audioSpectrum: .init(left: Array(repeating: 0, count: 16),
                right: Array(repeating: 0, count: 16),
                left64: [0.4] + Array(repeating: 0, count: 63),
                right64: [0.7] + Array(repeating: 0, count: 63), generation: 1)
        )
        eventOnlyAudioProgram.finalizeLayerMutations(committing: true)
        let eventSilent = eventOnlyAudioProgram.evaluate(
            inputs: [target: .bool(true)], effectivePropertyValues: [:],
            frame: frame(runtime: 2), mediaPlaybackEvent: .init(state: 2, generation: 2),
            audioSpectrum: .init(left: Array(repeating: 0, count: 16),
                right: Array(repeating: 0, count: 16), generation: 2)
        )
        eventOnlyAudioProgram.finalizeLayerMutations(committing: true)
        let eventQuiet = eventOnlyAudioProgram.evaluate(
            inputs: [target: .bool(true)], effectivePropertyValues: [:],
            frame: frame(runtime: 3), mediaPlaybackEvent: .init(state: 2, generation: 2)
        )
        let destroyProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) { return value; }
                export function destroy() {}
                """)],
            userPropertyDefinitions: [],
            generation: 8
        )
        let destroyTeardown = destroyProgram.teardown(
            frame: frame(runtime: 3),
            effectivePropertyValues: [:],
            userPropertiesJSON: "{}"
        ).first

        let parented = SceneScriptVectorProgram.project(
            descriptor: descriptor(parentID: 99),
            scriptBindings: [authoredBinding]
        )
        let userWrapped = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: source,
                wrapperKeys: ["script", "user", "value"]
            )]
        )
        let textLeaf = SceneScriptVectorProgram.project(
            descriptor: descriptor(contentKind: "text"),
            scriptBindings: [authoredBinding]
        )
        let effectBearingProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(
                effects: [.init(name: "generic-effect")],
                effectFiles: ["effects/generic-effect.json"]
            ),
            scriptBindings: [authoredBinding],
            userPropertyDefinitions: [],
            generation: 10
        )
        let effectBearing = effectBearingProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let namedConsumer = SceneScriptVectorProgram.project(
            descriptor: namedReferenceDescriptor(targetIsConsumer: true),
            scriptBindings: [authoredBinding]
        )
        let namedProvider = SceneScriptVectorProgram.project(
            descriptor: namedReferenceDescriptor(targetIsConsumer: false),
            scriptBindings: [authoredBinding]
        )
        let shadowedNamedConsumer = SceneScriptVectorProgram.project(
            descriptor: namedReferenceDescriptor(
                targetIsConsumer: true,
                userTextureShadowsReference: true
            ),
            scriptBindings: [authoredBinding]
        )
        let cursorOnly = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function cursorClick() {}"
            )]
        )
        let sharedUpdate = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function update(value) { return shared.enabled; }"
            )]
        )
        let statefulParented = SceneScriptVectorProgram.project(
            descriptor: descriptor(parentID: 99, contentKind: "container"),
            scriptBindings: [binding(source: """
                export function update(value) {
                    shared.enabled = true;
                    return value;
                }
                """)]
        )
        let handleUpdate = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function update(value) { return thisScene.visible; }"
            )]
        )
        let dynamicGlobalWrite = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                const root = [].filter.constructor("return this")();
                root.__mwxBoolPoison = true;
                export function update(value) { return value; }
                """)]
        )
        let escapedStatefulProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: #"""
                const identity = Function("value", "return value");
                const escaped = "\x6f\x6b";
                export function update(value) {
                    shared[escaped] = true;
                    return identity(value);
                }
                """#)],
            userPropertyDefinitions: [],
            generation: 22
        )
        let escapedStateful = escapedStatefulProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let selfDestroyProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) {
                    thisScene.destroyLayer('leaf');
                    return true;
                }
                """)],
            userPropertyDefinitions: [],
            generation: 23
        )
        let selfDestroy = selfDestroyProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let logoDefinition = SceneUserPropertyDefinition(
            key: "logo", title: "Opening logo", kind: .bool,
            runtimeType: "bool", order: 0, index: nil,
            minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: false, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: .bool(true), options: []
        )
        let propertyDestroyProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) { return value; }
                export function applyUserProperties(properties) {
                    if (properties.hasOwnProperty('logo') && !properties.logo) {
                        thisScene.destroyLayer('leaf');
                    }
                }
                """)],
            userPropertyDefinitions: [logoDefinition],
            generation: 24
        )
        let propertyDestroy = propertyDestroyProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: ["logo": .bool(false)],
            frame: frame(runtime: 2),
            propertyRevision: 1
        )
        let eventfulProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) { return value; }
                export function cursorClick() {}
                """)],
            userPropertyDefinitions: [],
            generation: 9
        )
        let statefulCursorProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function cursorDown() { shared.dragging = true; }
                export function cursorUp() { shared.dragging = false; }
                export function update(value) {
                    shared.angle = (shared.angle || 0) + 1;
                    return value;
                }
                """)],
            userPropertyDefinitions: [],
            generation: 13
        )
        let statefulCursor = statefulCursorProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let boneProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                let bone;
                export function init() { bone = thisLayer.getBoneIndex('tip'); }
                export function update(value) {
                    const pose = thisLayer.getLocalBoneTransform(bone);
                    thisLayer.setLocalBoneTransform(bone, pose.translation(new Vec3(12, 3, 0)));
                    return bone === 1;
                }
                export function cursorDown() { thisLayer.getBoneTransform(bone); }
                export function cursorUp() {}
                """)],
            userPropertyDefinitions: [], generation: 21
        )
        let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
        for binding in boneProgram.bindings {
            try binding.owner.configurePuppetBones(
                layerID: 7, localMatrices: identity + identity, names: ["root", "tip"]
            )
        }
        let boneResult = boneProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let dynamicSource = """
            export let __workshopId = '2727665642';
            const audio = engine.registerAudioBuffers(64);
            const bars = [];
            let isMediaPlaying = false;
            let initCount = 0;
            let mediaEventCount = 0;
            export function init() {
                initCount += 1;
                const index = thisScene.getLayerIndex(thisLayer);
                for (let i = 0; i < 2; ++i) {
                    const bar = thisScene.createLayer({
                        image: 'models/bar.json',
                        origin: new Vec3(i * 10, 0, 0),
                        scale: new Vec3(1, 2, 1),
                        color: new Vec3(0.2, 0.4, 0.6),
                        alpha: 0.5,
                        visible: false
                    });
                    thisScene.sortLayer(bar, index);
                    bars.push(bar);
                }
            }
            export function mediaPlaybackChanged(event) {
                mediaEventCount += 1;
                isMediaPlaying = event.state !== MediaPlaybackEvent.PLAYBACK_STOPPED;
                for (const bar of bars) { bar.visible = isMediaPlaying; }
            }
            export function update(value) {
                thisLayer.scale = new Vec3(2, 3, 1);
                const peer = thisScene.getLayer('peer');
                peer.scale = new Vec3(4, 5, 1);
                peer.visible = false;
                peer.alpha = 0.25;
                peer.color = new Vec3(0.2, 0.4, 0.6);
                if (peer.alpha !== 0.25 || peer.color.y !== 0.4) {
                    throw new Error('authored style read-your-writes lost');
                }
                peer.text = 'changed';
                for (let i = 0; i < bars.length; ++i) {
                    bars[i].origin = new Vec3(i * 10, 0, 0);
                    bars[i].scale = new Vec3(1, audio.average[i] * 10, 1);
                }
                return initCount === 1 && mediaEventCount === 1 ? value : false;
            }
            """
        let dynamicProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: dynamicImageDescriptor(),
            scriptBindings: [binding(source: dynamicSource, authored: true)],
            userPropertyDefinitions: [],
            generation: 11
        )
        let dynamicAudio = SceneAudioSpectrumSnapshot(
            left: Array(repeating: 0, count: 16),
            right: Array(repeating: 0, count: 16),
            left64: [1] + Array(repeating: 0, count: 63),
            right64: [1] + Array(repeating: 0, count: 63),
            generation: 1
        )
        let dynamic = dynamicProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2),
            mediaPlaybackEvent: .init(state: 1, generation: 1),
            audioSpectrum: dynamicAudio
        )
        let dynamicDuplicate = dynamicProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 3),
            mediaPlaybackEvent: .init(state: 1, generation: 1),
            audioSpectrum: dynamicAudio
        )
        let dynamicCreated = dynamic.layerMutations.filter {
            $0.isDynamic && $0.assetPath != nil
        }
        let sharedHeapDomain = try SceneScriptQuickJSDomain()
        let failedStyleProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(), descriptor: dynamicImageDescriptor(),
            scriptBindings: [binding(source: """
                export function update(value) {
                    thisScene.getLayer('peer').alpha = 0.2;
                    shared.styleAttempt = true;
                    if (value) throw new Error('local failure after style write');
                    return value;
                }
                """, authored: true)],
            userPropertyDefinitions: [], generation: 17
        )
        let failedStyle = failedStyleProgram.evaluate(inputs: [target: .bool(true)],
            effectivePropertyValues: [:], frame: frame(runtime: 2))
        let sharedHeapProgram = SceneScriptVectorProgram.compile(
            domain: sharedHeapDomain,
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) {
                    shared.counter = (shared.counter || 0) + 1;
                    return shared.counter === 1;
                }
                """)],
            userPropertyDefinitions: [],
            generation: 12
        )
        let sharedHeapFirst = sharedHeapProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 3)
        )
        sharedHeapProgram.finalizeLayerMutations(committing: false)
        let sharedHeapRetry = sharedHeapProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 3)
        )
        sharedHeapProgram.finalizeLayerMutations(committing: true)
        let sharedHeapCommitted = sharedHeapProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 4)
        )
        let teardown = program.teardown(
            frame: frame(runtime: 3),
            effectivePropertyValues: [:],
            userPropertiesJSON: "{}"
        ).first
        let payload: [String: Any] = [
            "projectVisibility": try SceneScriptProjectVisibilityChecks.run(),
            "returnContract": try SceneScriptBooleanReturnChecks.run(),
            "boneDefinitions": boneProgram.definitions.count,
            "boneValue": boolValue(boneResult, target: target) as Any,
            "boneFailure": String(describing: boneResult.failures),
            "boneMutationCount": boneResult.ownerEffects.first?.puppetBoneMutations.count ?? 0,
            "boneTranslation": boneResult.ownerEffects.first?.puppetBoneMutations.first?.matrix[12] ?? -1,
            "boneCursorOwners": boneProgram.cursorOwnerRegistrations.count,
            "definitions": program.definitions.count,
            "first": boolValue(first, target: target) as Any,
            "second": boolValue(second, target: target) as Any,
            "badValue": boolValue(bad, target: target) as Any,
            "badCode": bad.failures[target]?.code as Any,
            "badAgainValue": boolValue(badAgain, target: target) as Any,
            "badAgainFailed": badAgain.failures[target] != nil,
            "badAgainCode": badAgain.failures[target]?.code as Any,
            "undefinedValue": boolValue(undefinedResult, target: target) as Any,
            "hiddenSharedCode": failureCode(hiddenShared) as Any,
            "hiddenHandleCode": failureCode(hiddenHandle) as Any,
            "timerCode": failureCode(timer) as Any,
            "audioDefinitions": audioProgram.definitions.count,
            "eventOnlyAudioDefinitions":
                eventOnlyAudioProgram.definitions.count,
            "eventAudioX": eventAudio.layerMutations.first?.origin.x ?? -1,
            "eventAudioY": eventAudio.layerMutations.first?.origin.y ?? -1,
            "eventSilentX": eventSilent.layerMutations.first?.origin.x ?? -1,
            "eventCallbackCount": eventSilent.layerMutations.first?.origin.z ?? -1,
            "eventAudioFailures": eventAudio.failures.count + eventSilent.failures.count + eventQuiet.failures.count,
            "eventQuiet": eventQuiet.values.isEmpty && eventQuiet.layerMutations.isEmpty,
            "destroyDefinitions": destroyProgram.definitions.count,
            "destroyTeardownInvoked": destroyTeardown?.destroyCallbackInvoked as Any,
            "destroyTeardownQuiescent": destroyTeardown?.snapshot.isQuiescent as Any,
            "destroyTeardownFailed": destroyTeardown?.failure != nil,
            "parentedProjected": parented.targets.count,
            "userWrappedProjected": userWrapped.targets.count,
            "textLeafProjected": textLeaf.targets.count,
            "effectBearingDefinitions": effectBearingProgram.definitions.count,
            "effectBearingValue": boolValue(effectBearing, target: target) as Any,
            "namedConsumerProjected": namedConsumer.targets.count,
            "namedProviderProjected": namedProvider.targets.count,
            "shadowedNamedConsumerProjected": shadowedNamedConsumer.targets.count,
            "cursorOnlyProjected": cursorOnly.targets.count,
            "sharedUpdateProjected": sharedUpdate.targets.count,
            "statefulParentedProjected": statefulParented.targets.count,
            "handleUpdateProjected": handleUpdate.targets.count,
            "dynamicGlobalWriteProjected": dynamicGlobalWrite.targets.count,
            "escapedStatefulDefinitions": escapedStatefulProgram.definitions.count,
            "escapedStatefulValue": boolValue(
                escapedStateful, target: target
            ) as Any,
            "selfDestroyValue": boolValue(selfDestroy, target: target) as Any,
            "selfDestroyMutation": selfDestroy.layerMutations.contains {
                $0.kind == .destroy && !$0.isDynamic && $0.layerID == 7
                    && $0.fields.isEmpty
            },
            "propertyDestroyValue": boolValue(
                propertyDestroy, target: target
            ) as Any,
            "propertyDestroyMutation": propertyDestroy.layerMutations.contains {
                $0.kind == .destroy && !$0.isDynamic && $0.layerID == 7
                    && $0.fields.isEmpty
            },
            "eventfulDefinitions": eventfulProgram.definitions.count,
            "statefulCursorDefinitions":
                statefulCursorProgram.definitions.count,
            "statefulCursorValue":
                boolValue(statefulCursor, target: target) as Any,
            "statefulCursorRegistrationCount":
                statefulCursorProgram.cursorOwnerRegistrations.count,
            "statefulCursorEvents": statefulCursorProgram
                .cursorOwnerRegistrations.first?.owner.exportedCursorEvents
                .map(\.callbackName).sorted() ?? [],
            "dynamicDefinitions": dynamicProgram.definitions.count,
            "dynamicHasAudio": dynamicProgram.hasAudioConsumers,
            "dynamicMediaOwnerCount":
                dynamicProgram.mediaOwnerRegistrations.count,
            "dynamicValue": boolValue(dynamic, target: target) as Any,
            "dynamicLayerCount": dynamic.layerMutations.count,
            "dynamicMediaVisible": dynamicCreated.count == 2
                && dynamicCreated.allSatisfy(\.visible),
            "dynamicAudioScaleY": dynamicCreated.first?.scale.y ?? -1,
            "dynamicFailureCount": dynamic.failures.count,
            "dynamicDuplicateValue":
                boolValue(dynamicDuplicate, target: target) as Any,
            "dynamicDuplicateFailureCount": dynamicDuplicate.failures.count,
            "authoredStyleAlpha": dynamic.layerMutations.first(where: { !$0.isDynamic && $0.fields.contains(.alpha) })?.alpha ?? -1,
            "authoredStyleColorY": dynamic.layerMutations.first(where: { !$0.isDynamic && $0.fields.contains(.color) })?.color.y ?? -1,
            "failedStyleDiscarded": failedStyle.values.isEmpty && failedStyle.layerMutations.isEmpty && !failedStyle.failures.isEmpty,
            "dynamicOwnerEffectsCount": dynamic.ownerEffects.count,
            "dynamicOwnerEffectsTarget": dynamic.ownerEffects.first?
                .ownerTarget == target,
            "dynamicOwnerEffectsLayerCount": dynamic.ownerEffects.first?
                .layerMutations.count ?? -1,
            "sharedHeapFirst":
                boolValue(sharedHeapFirst, target: target) as Any,
            "sharedHeapRetry":
                boolValue(sharedHeapRetry, target: target) as Any,
            "sharedHeapCommitted":
                boolValue(sharedHeapCommitted, target: target) as Any,
            "dynamicModelPaths": dynamic.layerMutations.compactMap(\.assetPath),
            "dynamicPeerMutation": dynamic.layerMutations.contains {
                $0.layerID == 8 && $0.fields == [.scale, .visibility, .text, .alpha, .color]
                    && $0.scale == .init(4, 5, 1)
                    && !$0.visible && $0.text == "changed"
            },
            "teardownDestroyInvoked": teardown?.destroyCallbackInvoked as Any,
            "teardownQuiescent": teardown?.snapshot.isQuiescent as Any,
            "teardownFailed": teardown?.failure != nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
