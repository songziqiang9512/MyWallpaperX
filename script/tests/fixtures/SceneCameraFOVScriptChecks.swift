import Foundation
import simd

@main enum SceneCameraFOVScriptChecks {
    static let source = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name:'lower',value:1,min:0.5,max:1.5})
        .addSlider({name:'upper',value:1.2,min:0.5,max:1.5}).finish();
    const audio = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let initial = 0, initialized = 0, smoothed = 0;
    export function init(value) { initial = value; initialized++; }
    export function update() {
        smoothed = 0.5 * smoothed + 0.5 * audio.average[0];
        return initial * (scriptProperties.lower + smoothed *
            (scriptProperties.upper-scriptProperties.lower)) + (initialized-1)*1000;
    }
    """

    static func root(key: String = "lens", script: String = source,
                     host: String = "fov", camera: String = "default",
                     animation: Bool = false, propertyInputs: Bool = true) -> [String: Any] {
        var wrapper: [String: Any] = ["script": script, "value": 100.0]
        if propertyInputs {
            wrapper["scriptproperties"] = [
                "lower": ["user": key, "value": 1.0],
                "upper": ["user": "bounce", "value": 1.2],
            ]
        }
        if animation { wrapper["animation"] = ["id": 1] }
        return ["general": ["orthogonalprojection": NSNull()],
            "objects": [["id": 7, "camera": camera, "path": "scripts/route.json", host: wrapper]]]
    }

    static func descriptor(camera: String = "default", fov: Double = 100,
                           orthographic: Bool = false) -> SceneRenderDescriptor {
        var layer = SceneRenderDescriptor.Layer(id: 7, layerIndex: 0, name: "camera",
            visible: true, originXYZ: [0, 0, 10], scaleXYZ: [1, 1, 1],
            alpha: nil, effects: [], contentKind: "camera")
        layer.cameraPath = .init(camera: camera, fov: fov)
        var result = SceneRenderDescriptor(layers: [layer])
        if orthographic { result.camera.orthoWidth = 1920; result.camera.orthoHeight = 1080 }
        return result
    }

    static func catalog(key: String = "lens") -> SceneUserPropertyCatalog {
        SceneUserPropertyDefinitionParser().parse(properties: [
            key: ["type": "slider", "value": 1.0, "min": 0.5, "max": 1.5],
            "bounce": ["type": "slider", "value": 1.2, "min": 0.5, "max": 1.5],
        ])
    }

    static func scalar(_ value: SceneDynamicValue?) -> Double? {
        guard case let .scalar(number)? = value else { return nil }
        return number
    }

    static func snapshot(_ definitions: [SceneDynamicTargetDefinition],
                         values: [SceneDynamicTarget: SceneDynamicValue] = [:],
                         user: [SceneDynamicTarget: SceneDynamicValue] = [:],
                         timeline: [SceneDynamicTarget: SceneDynamicValue] = [:]) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 11,
            definitions: definitions, userValues: user, timelineValues: timeline,
            sceneScriptValues: values).snapshot
    }

    static func cameraOverride(_ descriptor: SceneRenderDescriptor, _ values: SceneDynamicSnapshot)
        -> SceneParticleCameraFrame.NativePerspectiveOverride? {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let world = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: byID)
        return SceneParticleCameraFrame.nativePerspectiveOverride(descriptor: descriptor,
            layersByID: byID, worldFrames: world, dynamicValues: values)
    }

    static func lifecycleContext(generation: UInt64 = 11, script: String = source,
                                 propertyInputs: Bool = true) throws
        -> SceneDesktopWallpaperLaunchContext {
        var scene = descriptor()
        let peerSource = "export function update(value) { return value; }"
        var peer = SceneRenderDescriptor.Layer(id: 8, layerIndex: 1, name: "healthy peer",
            visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 0.5,
            effects: [], contentKind: "text", text: "ready",
            textStyle: .init(fontPath: nil, colorRGB: [1, 1, 1], pointSize: 32))
        peer.textScript = .init(source: peerSource)
        scene.layers.append(peer)
        var document = root(script: script, propertyInputs: propertyInputs)
        var objects = document["objects"] as! [[String: Any]]
        objects.append(["id": 8, "alpha": ["value": 0.5, "script": peerSource],
                        "text": ["value": "ready", "script": peerSource]])
        document["objects"] = objects
        let bindings = SceneScriptBindingIRParser.parse(document: document).bindings
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor: scene,
            runtimeDescriptor: scene, scriptBindings: bindings,
            vectorProjection: SceneScriptVectorProgram.project(descriptor: scene, scriptBindings: bindings),
            userPropertyDefinitions: catalog().definitions, timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [], admittedVectorPassTargets: [],
            generation: generation)
        let propertyProgram = ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: document), catalog: catalog()).program
        let schema = SceneDesktopWallpaperLaunchFrameSchema(
            runtimeInput: .init(propertyBindingProgram: propertyProgram, renderDescriptor: scene),
            sharedLayerAlphaProgram: .init(), propertyVectorScriptProgram: candidate.vectorProgram,
            sceneScriptFallbackDefinitions: [], sceneScriptScalarProgram: candidate.scalarProgram,
            sceneScriptStringProgram: candidate.stringProgram, sceneScriptOwnerLayerIDs: [7, 8],
            preparedResourceLayerTemplates: [:], timelineProgram: .init(), textScriptProgram: .init())
        return .init(frameSchema: schema, sceneScriptScalarProgram: candidate.scalarProgram,
            sceneScriptStringProgram: candidate.stringProgram, sceneScriptCursorProgram: candidate.cursorProgram,
            propertyVectorScriptProgram: candidate.vectorProgram,
            liveState: .init(program: propertyProgram, effectiveValues: catalog().effectiveValues(overrides: [:]),
                activeConsumerTargets: candidate.scalarProgram.activeLivePropertyInputTargets))
    }

    static func lifecycleFacts(frame: SceneScriptFrameInput) throws -> [String: Bool] {
        let target = SceneDynamicTarget.layer(layerID: 7, field: .fov)
        let alpha = SceneDynamicTarget.layer(layerID: 8, field: .alpha)
        let text = SceneDynamicTarget.text(layerID: 8, field: .content)
        let context = try lifecycleContext()
        let schema = context.frameSchema
        var transaction = SceneEvaluationTransaction()
        let held = transaction.evaluate(frameIndex: 1, index: schema.dynamicDefinitionIndex,
            sceneScriptValues: [target: .scalar(80), alpha: .scalar(0.6), text: .string("alive")]).snapshot
        let initialTargets = schema.sceneScriptStatefulTargets
        let session = SceneDesktopWallpaperSession()
        session.retireCommittedLayers(context, layerIDs: [], frame: frame)
        let notRetired = schema.sceneScriptStatefulTargets == initialTargets
        session.retireCommittedLayers(context, layerIDs: [7], frame: frame)
        let registeredAfterFirst = schema.sceneScriptStatefulTargets
        session.retireCommittedLayers(context, layerIDs: [999], frame: frame)
        for _ in 0..<5 {
            session.retireCommittedLayers(context, layerIDs: [7], frame: frame)
        }
        let previous = transaction.previousValues(for: schema.sceneScriptStatefulTargets)
        let timeline = transaction.evaluate(frameIndex: 2, index: schema.dynamicDefinitionIndex,
            userValues: [target: .scalar(110)], timelineValues: [target: .scalar(90)], sceneScriptValues: previous).snapshot
        let user = transaction.evaluate(frameIndex: 3, index: schema.dynamicDefinitionIndex,
            userValues: [target: .scalar(110)],
            sceneScriptValues: transaction.previousValues(for: schema.sceneScriptStatefulTargets)).snapshot
        let authored = transaction.evaluate(frameIndex: 4, index: schema.dynamicDefinitionIndex,
            sceneScriptValues: transaction.previousValues(for: schema.sceneScriptStatefulTargets)).snapshot
        let peerScalar = context.sceneScriptScalarProgram.evaluate(inputs: [target: .scalar(80), alpha: .scalar(0.6)],
            frame: frame, effectivePropertyValues: context.liveState.effectiveValues)
        let peerString = context.sceneScriptStringProgram.evaluate(inputs: [text: .string("alive")],
            effectivePropertyValues: context.liveState.effectiveValues, frame: frame)
        let newContext = try lifecycleContext(generation: 12)
        session.retireCommittedLayers(context, layerIDs: [7], frame: frame)
        let fresh = newContext.sceneScriptScalarProgram.evaluate(inputs: [target: .scalar(100), alpha: .scalar(0.5)],
            frame: frame, effectivePropertyValues: ["lens": .number(0.8), "bounce": .number(1.2)])

        let failureContext = try lifecycleContext(script: """
            let count = 0;
            export function update() { if (++count > 1) throw new Error('fuse'); return 80; }
            """, propertyInputs: false)
        let failedProgram = failureContext.sceneScriptScalarProgram
        let first = failedProgram.evaluate(inputs: [target: .scalar(100), alpha: .scalar(0.6)], frame: frame)
        var failedTransaction = SceneEvaluationTransaction()
        _ = failedTransaction.evaluate(frameIndex: 1, index: failureContext.frameSchema.dynamicDefinitionIndex,
            sceneScriptValues: first.values)
        let failure = failedProgram.evaluate(inputs: [target: .scalar(80), alpha: .scalar(0.6)], frame: frame)
        let retained = failedTransaction.evaluate(frameIndex: 2,
            index: failureContext.frameSchema.dynamicDefinitionIndex,
            sceneScriptValues: failedTransaction.previousValues(for: failureContext.frameSchema.sceneScriptStatefulTargets)).snapshot
        return [
            "retirement-schema-prepared-cohort": initialTargets.isSuperset(of: [target, alpha, text]),
            "uncommitted-empty-retirement-keeps-registration": notRetired,
            "cumulative-tombstone-keeps-registration": schema.sceneScriptStatefulTargets == registeredAfterFirst,
            "retirement-withdraws-only-owner-registration": !schema.sceneScriptStatefulTargets.contains(target)
                && schema.sceneScriptStatefulTargets.isSuperset(of: [alpha, text]) && previous[target] == nil,
            "retirement-next-cadence-timeline-fallback": timeline[target]?.value == .scalar(90)
                && timeline[target]?.source == .timeline,
            "retirement-next-cadence-user-fallback": user[target]?.value == .scalar(110)
                && user[target]?.source == .userProperty,
            "retirement-next-cadence-authored-fallback": authored[target]?.value == .scalar(100)
                && authored[target]?.source == .authored,
            "retirement-keeps-healthy-peers": peerScalar.values[alpha] == .scalar(0.6)
                && peerScalar.values[target] == nil && peerString.values[text] == .string("alive")
                && authored[alpha]?.value == .scalar(0.6) && authored[text]?.value == .string("alive"),
            "retirement-keeps-held-snapshot": held[target]?.value == .scalar(80) && held[target]?.source == .sceneScript,
            "old-retirement-cannot-revoke-new-generation": newContext.frameSchema.sceneScriptStatefulTargets.contains(target)
                && fresh.values[target] == .scalar(80),
            "permanent-failure-preserves-previous-current": first.values[target] == .scalar(80)
                && failure.failures[target]?.permanentlyDisablesOwner == true
                && failedProgram.disabledTargets.contains(target)
                && failureContext.frameSchema.sceneScriptStatefulTargets.contains(target)
                && retained[target]?.value == .scalar(80) && retained[target]?.source == .sceneScript,
        ]
    }

    static func main() throws {
        var facts: [String: Bool] = [:]
        let document = root()
        let report = SceneUserPropertyBindingParser().parse(root: document)
        facts["real-parser-routes-fov-inputs"] = report.bindings.count == 2 && report.bindings.allSatisfy {
            if case .scriptProperty = $0.target { return true }; return false
        }
        let bindings = SceneScriptBindingIRParser.parse(document: document).bindings
        let scene = descriptor()
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerRuntimeFields(scene)
        try domain.configureNamedAnimations([])
        let program = SceneScriptScalarProgram.compile(domain: domain, descriptor: scene,
            scriptBindings: bindings, userPropertyDefinitions: catalog().definitions, generation: 11)
        facts["real-fov-script-prepared"] = program.bindings.count == 1
        let target = SceneDynamicTarget.layer(layerID: 7, field: .fov)
        let compiled = ScenePropertyBindingCompiler().compile(report: report, catalog: catalog())
        facts["property-program-not-rebuild"] = compiled.program.rebuildRequiredPropertyKeys.isEmpty
            && compiled.program.instructions.count == 2
        var live = ScenePropertyLiveUpdateState(program: compiled.program,
            effectiveValues: catalog().effectiveValues(overrides: [:]),
            activeConsumerTargets: program.activeLivePropertyInputTargets)
        let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1.0/60, sceneTime: 1), timeZone: TimeZone(secondsFromGMT: 0)!)
        var current = 100.0
        func evaluate(audio: SceneAudioSpectrumSnapshot = .silent) -> SceneScriptScalarFrameResult {
            let result = program.evaluate(inputs: [target: .scalar(current)], frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision,
                audioSpectrum: audio)
            if let value = scalar(result.values[target]) { current = value }
            return result
        }
        let first = evaluate()
        facts["initial-fov-100"] = scalar(first.values[target]) == 100 && first.failures.isEmpty
        facts["hot-slider-admitted"] = live.apply(.number(0.8), forPropertyKey: "lens")
        let changed = evaluate()
        facts["changed-fov-80"] = scalar(changed.values[target]) == 80 && changed.failures.isEmpty
        let held = snapshot(program.definitions, values: changed.values)
        facts["same-camera-reads-hot-fov"] = cameraOverride(scene, held)?.fovDegrees == 80
        var rebuilt = scene; rebuilt.layers[0].cameraPath = .init(camera: "default", fov: 80)
        let cold = cameraOverride(rebuilt, snapshot([]))
        let viewport = CGSize(width: 1920, height: 1080)
        let hotFrame = SceneParticleCameraFrame(camera: scene.camera, viewportSize: viewport,
            nativePerspectiveOverride: cameraOverride(scene, held), dynamicValues: held)
        let coldFrame = SceneParticleCameraFrame(camera: rebuilt.camera, viewportSize: viewport,
            nativePerspectiveOverride: cold)
        facts["typed-vs-same-cold-projection"] = hotFrame.perspectiveViewProjection == coldFrame.perspectiveViewProjection
        facts["fov-changes-projection"] = hotFrame.perspectiveViewProjection != SceneParticleCameraFrame(
            camera: scene.camera, viewportSize: viewport, nativePerspectiveOverride: cameraOverride(scene, snapshot([]))).perspectiveViewProjection
        var noSceneFallback = scene
        noSceneFallback.camera.eye = []; noSceneFallback.camera.center = []
        noSceneFallback.camera.up = []; noSceneFallback.camera.fovDegrees = nil
        let noFallbackProgram = SceneScriptScalarProgram.compile(domain: domain, descriptor: noSceneFallback,
            scriptBindings: bindings, generation: 11)
        let noFallbackOverride = cameraOverride(noSceneFallback, held)
        let noFallbackFrame = SceneParticleCameraFrame(camera: noSceneFallback.camera, viewportSize: viewport,
            nativePerspectiveOverride: noFallbackOverride, dynamicValues: held)
        facts["layer-camera-needs-no-scene-fallback"] = noFallbackProgram.bindings.count == 1
            && !SceneParticleCameraFrame.usesNativePerspective(camera: noSceneFallback.camera)
            && SceneParticleCameraFrame.usesNativePerspective(camera: noSceneFallback.camera,
                nativePerspectiveOverride: noFallbackOverride)
            && noFallbackFrame.perspectiveViewProjection == hotFrame.perspectiveViewProjection
        facts["timeline-target-conflict-not-prepared"] = SceneScriptScalarProgram.compile(domain: domain,
            descriptor: scene, scriptBindings: bindings, timelineTargets: [target], generation: 11).bindings.isEmpty
        facts["second-slider-admitted"] = live.apply(.number(1.2), forPropertyKey: "lens")
        facts["init-not-repeated-on-edit"] = scalar(evaluate().values[target]) == 120
        facts["reset-input-admitted"] = live.apply(.number(1), forPropertyKey: "lens")
        facts["reset-restores-100-without-init"] = scalar(evaluate().values[target]) == 100
        facts["held-old-snapshot-immutable"] = cameraOverride(scene, held)?.fovDegrees == 80
        let audio = SceneAudioSpectrumSnapshot(left: Array(repeating: 0.4, count: 16),
            right: Array(repeating: 0.4, count: 16), generation: 1)
        facts["audio-state-prepared"] = abs((scalar(evaluate(audio: audio).values[target]) ?? 0)-104) < 0.00001
        let editRetainsSmoothing = live.apply(.number(0.8), forPropertyKey: "lens")
            && abs((scalar(evaluate().values[target]) ?? 0)-84) < 0.00001
        let resetRetainsSmoothing = live.apply(.number(1), forPropertyKey: "lens")
            && abs((scalar(evaluate().values[target]) ?? 0)-101) < 0.00001
        facts["edit-preserves-audio-smoothing"] = editRetainsSmoothing
        facts["reset-preserves-audio-smoothing"] = resetRetainsSmoothing
        let revision = live.revision
        facts["bad-input-rejected-revision-stable"] = !live.apply(.string("bad"), forPropertyKey: "lens") && live.revision == revision
        var unavailable = live
        facts["missing-consumer-rejected"] = !unavailable.apply(.number(0.9), forPropertyKey: "lens",
            unavailableConsumerTargets: program.livePropertyInputTargets) && unavailable.revision == revision

        let renamedRoot = root(key: "renamed-control")
        let renamedReport = SceneUserPropertyBindingParser().parse(root: renamedRoot)
        let renamed = SceneScriptScalarProgram.compile(domain: domain, descriptor: scene,
            scriptBindings: SceneScriptBindingIRParser.parse(document: renamedRoot).bindings, generation: 11)
        facts["renamed-property-routes-same-consumer"] = renamedReport.bindings.allSatisfy {
            if case .scriptProperty = $0.target { return true }; return false
        } && renamed.bindings.count == 1
        facts["renamed-property-has-same-output"] = scalar(renamed.evaluate(inputs: [target: .scalar(100)],
            frame: frame, effectivePropertyValues: ["renamed-control": .number(0.8), "bounce": .number(1.2)]).values[target]) == 80

        for (name, input, descriptor) in [
            ("orthographic", document, Self.descriptor(orthographic: true)),
            ("non-default", root(camera: "alternate"), Self.descriptor(camera: "alternate")),
            ("wrong-host", root(host: "zoom"), scene),
            ("animation-conflict", root(animation: true), scene),
        ] {
            let unavailableProgram = SceneScriptScalarProgram.compile(domain: domain,
                descriptor: descriptor, scriptBindings: SceneScriptBindingIRParser.parse(document: input).bindings,
                generation: 11)
            facts[name+"-not-prepared"] = unavailableProgram.bindings.isEmpty
            let propertyProgram = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: input), catalog: catalog()).program
            var unavailableLive = ScenePropertyLiveUpdateState(program: propertyProgram,
                effectiveValues: catalog().effectiveValues(overrides: [:]),
                activeConsumerTargets: unavailableProgram.activeLivePropertyInputTargets)
            facts[name+"-input-rejected"] = !unavailableLive.apply(.number(0.8), forPropertyKey: "lens")
                && unavailableLive.revision == 0
        }
        for invalid in [0.0, 180, -1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude, 179.999999999] {
            let value = snapshot(program.definitions, values: [target: .scalar(invalid)])
            facts["invalid-typed-\(invalid)-keeps-authored"] = scalar(value[target]?.value) == 100
                && value[target]?.source == .authored
        }
        let ordered = snapshot(program.definitions, values: [target: .scalar(80)],
            user: [target: .scalar(110)], timeline: [target: .scalar(90)])
        facts["original-source-priority"] = scalar(ordered[target]?.value) == 80 && ordered[target]?.source == .sceneScript

        var mixedRoot = document
        var objects = mixedRoot["objects"] as! [[String: Any]]
        objects.append(["id": 9, "unknownhost": ["user": "lens", "value": 1]])
        mixedRoot["objects"] = objects
        let mixed = ScenePropertyBindingCompiler().compile(report: SceneUserPropertyBindingParser().parse(root: mixedRoot), catalog: catalog())
        var mixedLive = ScenePropertyLiveUpdateState(program: mixed.program,
            effectiveValues: catalog().effectiveValues(overrides: [:]), activeConsumerTargets: program.activeLivePropertyInputTargets)
        facts["same-key-unsupported-target-atomic"] = !mixedLive.apply(.number(0.8), forPropertyKey: "lens")
            && mixedLive.revision == 0

        let badSource = """
        export function update() { thisLayer.alpha=0.25; return 180; }
        """
        let bad = SceneScriptScalarProgram.compile(domain: domain, descriptor: scene,
            scriptBindings: SceneScriptBindingIRParser.parse(document: root(script: badSource, propertyInputs: false)).bindings,
            generation: 11)
        let rejected = bad.evaluate(inputs: [target: .scalar(80)], frame: frame)
        facts["invalid-return-rejected-before-bundle"] = rejected.failures[target]?.code == "bad-return"
            && rejected.values.isEmpty && rejected.layerMutations.isEmpty && rejected.ownerEffects.isEmpty

        var layered = scene
        var other = scene.layers[0]; other = .init(id: 8, layerIndex: 1, name: "later camera",
            visible: true, originXYZ: [0, 0, 10], scaleXYZ: [1, 1, 1], alpha: nil, effects: [], contentKind: "camera")
        other.cameraPath = .init(camera: "default", fov: 60)
        layered.layers.append(other)
        facts["later-camera-keeps-own-static-fov"] = cameraOverride(layered, held)?.fovDegrees == 60
        let visibility = SceneDynamicTarget.layer(layerID: 8, field: .visibility)
        let hidden = snapshot(program.definitions + [.init(target: visibility, valueType: .bool, authoredValue: .bool(true))],
            values: [target: .scalar(80), visibility: .bool(false)])
        facts["hidden-camera-restores-original-order"] = cameraOverride(layered, hidden)?.fovDegrees == 80

        let teardown = program.retire(layerIDs: [7], frame: frame, userPropertiesJSON: "{}")
        facts["retired-owner-quiescent"] = teardown.count == 1 && teardown.allSatisfy { $0.snapshot.isQuiescent }
        facts["retired-input-consumer-unavailable"] = program.activeLivePropertyInputTargets.isEmpty
        let retired = evaluate()
        facts["retired-owner-no-new-output"] = retired.values.isEmpty && retired.ownerEffects.isEmpty
        facts["retirement-does-not-rewrite-held-snapshot"] = cameraOverride(scene, held)?.fovDegrees == 80
        facts.merge(try lifecycleFacts(frame: frame)) { _, value in value }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
