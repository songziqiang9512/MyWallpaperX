import CoreGraphics
import Foundation
import simd

// Only the GPU renderer container and frame DTO are replaced. The camera
// consumer, visibility, projection and Timeline owners below are production.
struct SceneFrameContext {
    let sceneTime: Double
    let screenSize: CGSize
    let dynamicValues: SceneDynamicSnapshot
}

struct SceneMetalRenderer {
    let renderDescriptor: SceneRenderDescriptor
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let worldFramesByLayerID: [Int: simd_float4x4] = [:]

    init(_ descriptor: SceneRenderDescriptor) {
        renderDescriptor = descriptor
        layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
    }
}

@main enum SceneDefault2DCameraInputChecks {
    static let originTarget = SceneDynamicTarget.camera(.origin)
    static let zoomTarget = SceneDynamicTarget.camera(.zoom)
    static let viewport = CGSize(width: 3840, height: 2160)
    static var serial = 0

    static func root(id: Int = 7, key: String = "lensScale", variant: Int = 0,
                     scripted: Bool = true, direct: Bool = true) -> [String: Any] {
        let local = variant == 0 ? "initialConfig" : "originalSettings"
        let result = variant == 0 ? "new Vec3(120,-40,620)" : "new Vec3(60+60,-20*2,310*2)"
        let source = """
        let initializations=0;
        export function init(value){
            if(++initializations!==1)throw Error('repeated init');
            if(thisLayer.id!==\(id)||thisObject.origin.x!==0||thisObject.origin.y!==0||thisObject.origin.z!==500)throw Error('source identity');
            const \(local)=thisScene.getInitialLayerConfig(thisLayer);
            if(!\(local)||\(local).origin.value!=='0 0 500')throw Error('initial configuration');
            return \(result);
        }
        """
        let origin: Any = scripted ? ["value": "0 0 500", "script": source] : "0 0 500"
        let zoom: Any = direct ? ["user": key, "value": 0.73] : 0.73
        return ["version": 3, "camera": ["eye": "0 0 0", "center": "0 0 -1", "up": "0 1 0"],
            "general": ["orthogonalprojection": ["width": 3840, "height": 2160],
                "nearz": 0.01, "farz": 10000],
            "objects": [["id": id, "name": variant == 0 ? "own lens" : "renamed lens",
                "camera": "default", "path": variant == 0 ? "paths/own.json" : "paths/renamed.json",
                "origin": origin, "zoom": zoom]]]
    }

    static func changingFirst(_ root: [String: Any],
                              _ change: (inout [String: Any]) -> Void) -> [String: Any] {
        var root = root, objects = root["objects"] as! [[String: Any]]
        change(&objects[0]); root["objects"] = objects
        return root
    }

    final class Fixture {
        let descriptor: SceneRenderDescriptor
        let document: SceneDocument
        let property: ScenePropertyBindingCompilation
        let vector: SceneScriptVectorProgram
        let scalarProgram: SceneScriptScalarProgram
        let domain: SceneScriptQuickJSDomain
        let timeline: SceneTimelineProgram
        let playback: SceneTimelinePlaybackRuntime
        var definitions: [SceneDynamicTargetDefinition]
        let layers: SceneScriptDynamicLayerRuntime
        var live: ScenePropertyLiveUpdateState
        var transaction = SceneEvaluationTransaction()
        var frameIndex: UInt64 = 0
        var currentSceneTime: Double = 0
        var rejectedOwners: Set<SceneDynamicTarget> = []

        init(_ root: [String: Any], key: String, schemaDefault: Double = 0.73,
             additionalProperties: [String: Any] = [:]) throws {
            serial += 1
            let directory = URL(fileURLWithPath: CommandLine.arguments[1])
            let url = directory.appendingPathComponent("own-camera-\(serial).json")
            try JSONSerialization.data(withJSONObject: root,
                options: serial.isMultiple(of: 2) ? [.sortedKeys] : []).write(to: url)
            var properties = additionalProperties
            properties[key] = ["type": "slider", "value": schemaDefault, "min": 0.01, "max": 100]
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: properties)
            document = try SceneDocumentLoader().load(from: url, propertyCatalog: catalog)
            guard let descriptor = SceneRenderDescriptorBuilder().build(
                project: SceneProject(rootURL: directory, entryPath: url.lastPathComponent,
                    userProperties: catalog), sceneDocument: document,
                assetCatalog: SceneAssetCatalog(models: [], materials: [], effectDefinitions: [],
                    effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []),
                resourceReferences: SceneResourceReferenceIndex(missingReferences: [],
                    builtInReferenceCount: 0, runtimeProvidedReferenceCount: 0),
                capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("own descriptor rejected")
            }
            self.descriptor = descriptor
            property = ScenePropertyBindingCompiler().compile(
                report: document.userPropertyResolution.bindingReport, catalog: catalog,
                cameraInputLayerID: descriptor.camera.default2DInputLayerID)
            timeline = SceneTimelineTargetCompiler.compile(descriptor: descriptor)
            playback = SceneTimelinePlaybackRuntime(program: timeline)
            let timelineTargets = Set(timeline.bindings.map(\.target))
            domain = try SceneScriptQuickJSDomain()
            // Match the real candidate's bootstrap before constructing any owner.
            try domain.configureLayerRuntimeFields(descriptor)
            vector = SceneScriptVectorProgram.compile(domain: domain, descriptor: descriptor,
                scriptBindings: document.scriptBindings, userPropertyDefinitions: catalog.definitions,
                timelineTargets: timelineTargets, generation: 17)
            scalarProgram = SceneScriptScalarProgram.compile(domain: domain, descriptor: descriptor,
                scriptBindings: document.scriptBindings, userPropertyDefinitions: catalog.definitions,
                timelineTargets: timelineTargets, generation: 17)
            layers = SceneScriptDynamicLayerRuntime(descriptor: descriptor,
                authoredMutationLayerIDs: Set(descriptor.layers.map(\.id)))
            let cameraDefinitions = SceneDefault2DCameraInputProfile.definitions(
                descriptor: descriptor, timelineTargets: timelineTargets)
            definitions = SceneDynamicDefinitionMerger.merge(
                propertyDefinitions: property.program.definitions, timelineProgram: timeline,
                textScriptProgram: .init(), additionalDefinitions: vector.definitions
                    + scalarProgram.definitions + layers.authoredLayerDefinitions + cameraDefinitions)
            live = ScenePropertyLiveUpdateState(program: property.program,
                effectiveValues: catalog.effectiveValues(overrides: [:]),
                activeConsumerTargets: Set(definitions.map(\.target)),
                propertyDefinitions: catalog.definitions)
            _ = transaction.evaluate(frameIndex: 0, definitions: definitions, userValues: live.userValues)
        }

        func frame(sceneTime: Double? = nil,
                   committedValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
                   commands: [SceneTimelinePlaybackMutation] = []) throws
            -> (SceneDynamicSnapshot, SceneScriptVectorFrameResult) {
            frameIndex += 1
            let time = sceneTime ?? Double(frameIndex)
            currentSceneTime = time
            definitions = SceneDynamicDefinitionMerger.merge(
                propertyDefinitions: property.program.definitions, timelineProgram: timeline,
                textScriptProgram: .init(), additionalDefinitions: vector.definitions
                    + scalarProgram.definitions + layers.authoredLayerDefinitions
                    + SceneDefault2DCameraInputProfile.definitions(descriptor: descriptor,
                        timelineTargets: Set(timeline.bindings.map(\.target))))
            let index = SceneDynamicSnapshotResolver.prepare(definitions: definitions)
            let timelineValues = playback.values(sceneTime: time)
            let previous = transaction.previousValues(for: vector.inputTargets.union(scalarProgram.inputTargets))
                .merging(layers.snapshot().authoredLayerValues) { _, committed in committed }
            let preliminary = SceneDynamicSnapshotResolver().resolve(frameIndex: frameIndex,
                generation: transaction.committedSnapshot?.generation ?? 0, index: index,
                userValues: live.userValues, timelineValues: timelineValues,
                sceneScriptValues: previous)
            try domain.publishLayerSnapshot(preliminary.snapshot, descriptor: descriptor)
            let result = vector.evaluate(inputs: preliminary.snapshot.typedValues(
                    for: vector.inputTargets, valueTypes: vector.inputValueTypes),
                effectivePropertyValues: live.effectiveValues,
                frame: SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1.0/60.0, sceneTime: time)),
                propertyRevision: live.revision)
            let scalar = scalarProgram.evaluate(inputs: preliminary.snapshot.typedValues(
                    for: scalarProgram.inputTargets, valueTypes: scalarProgram.inputValueTypes),
                frame: SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1.0/60.0, sceneTime: time)),
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let admission = layers.preflightOwnerEffects(result.ownerEffects + scalar.ownerEffects)
            rejectedOwners = Set(admission.rejectedOwners.compactMap(\.ownerTarget))
            layers.commit(admission.layerPlan)
            let scriptValues = result.values.merging(scalar.values) { _, current in current }
                .filter { !rejectedOwners.contains($0.key) }
                .merging(committedValues) { _, current in current }
            let settledTimeline = timelineValues.merging(
                try playback.preview(commands, sceneTime: time).get()) { _, current in current }
            let resolution = SceneDynamicSnapshotResolver().resolve(frameIndex: frameIndex,
                generation: 0, index: index, base: preliminary,
                timelineValues: settledTimeline, sceneScriptValues: scriptValues)
            let pending = transaction.prepare(frameIndex: frameIndex, resolution: resolution)
            transaction.commit(pending)
            try playback.apply(commands, sceneTime: time).get()
            vector.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejectedOwners)
            scalarProgram.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejectedOwners)
            return (pending.snapshot, result)
        }

        func camera(_ snapshot: SceneDynamicSnapshot) -> SceneParticleCameraFrame {
            SceneMetalRenderer(descriptor).makeCameraFrame(frameContext: .init(
                sceneTime: currentSceneTime, screenSize: viewport, dynamicValues: snapshot),
                worldFrames: SceneLayerWorldFrameResolver.compute(descriptor: descriptor,
                    byID: Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })))
        }
    }

    static func scalar(_ value: SceneDynamicValue?) -> Double {
        guard case let .scalar(value)? = value else { return -999 }
        return value
    }

    static func vector(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector3(x, y, z)? = value else { return [] }
        return [x, y, z]
    }

    static func projected(_ frame: SceneParticleCameraFrame, _ world: SIMD3<Float>) -> SIMD3<Float> {
        let clip = frame.viewProjection(usesPerspective: false) * SIMD4(world, 1)
        return SIMD3(clip.x, clip.y, clip.z) / clip.w
    }

    static func near(_ a: Float, _ b: Float) -> Bool {
        abs(a-b) < max(0.00001, max(abs(a), abs(b)) * 0.000001)
    }

    static func observe(_ fixture: Fixture, id: Int, condition: String) throws -> Bool {
        let observer = try SceneScriptValueOwner(domain: fixture.domain,
            source: "export function update(v){return \(condition);}",
            target: .layer(layerID: id, field: .visibility), valueType: .bool,
            effectNames: [], allowsStatefulLayerSideEffects: true,
            generation: 17, budget: .default)
        let value = try observer.evaluate(input: .bool(true),
            frame: SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0/60.0, sceneTime: Double(fixture.frameIndex))),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 17,
            interruptBudget: nil).get().value
        return value == .bool(true)
    }

    static func mixed(_ variant: Int) throws -> [String: Any] {
        let id = variant == 0 ? 7 : 37, key = variant == 0 ? "lensScale" : "renamedMagnification"
        let fixture = try Fixture(root(id: id, key: key, variant: variant), key: key)
        let owner = fixture.vector.bindings.first?.owner
        var zooms: [Double] = [], origins: [[Double]] = [], projectedEdges: [Float] = []
        var facts: [String: Bool] = [
            "prepared-source-id": fixture.descriptor.camera.default2DInputLayerID == id
                && fixture.descriptor.camera.default2DOriginInputLayerID == id,
            "single-owner-camera-target": fixture.vector.bindings.count == 1
                && fixture.vector.inputTargets == [originTarget]
                && !fixture.definitions.contains { $0.target == .layer(layerID: id, field: .origin) },
            "real-property-target": fixture.property.diagnostics.isEmpty
                && fixture.property.program.instructions.count == 1
                && fixture.property.program.instructions.first?.target == zoomTarget
                && fixture.property.program.rebuildRequiredPropertyKeys.isEmpty,
            "one-definition-per-field": fixture.definitions.filter { $0.target == originTarget }.count == 1
                && fixture.definitions.filter { $0.target == zoomTarget }.count == 1,
        ]
        var first: SceneDynamicSnapshot?
        for (index, zoom) in [0.73, 1.0, 0.8].enumerated() {
            if index > 0 { facts["live-change-\(index)"] = fixture.live.apply(.number(zoom), forPropertyKey: key) }
            let (snapshot, evaluation) = try fixture.frame()
            try fixture.domain.publishLayerSnapshot(snapshot, descriptor: fixture.descriptor)
            let frame = fixture.camera(snapshot)
            zooms.append(scalar(snapshot[zoomTarget]?.value))
            origins.append(vector(snapshot[originTarget]?.value))
            let center = projected(frame, SIMD3(2040, 1040, 0))
            let edge = projected(frame, SIMD3(2140, 1040, 0))
            projectedEdges.append(edge.x)
            facts["callback-and-origin-\(index)"] = evaluation.failures.isEmpty
                && snapshot[originTarget]?.source == .sceneScript
                && snapshot[originTarget]?.value == .vector3(120, -40, 620)
                && fixture.vector.bindings.first?.owner === owner
            facts["settled-camera-\(index)"] = snapshot[zoomTarget]?.source == .userProperty
                && frame.cameraOrigin == SIMD3(120, -40, 620)
                && near(frame.coverHalfExtents.x * Float(zoom), 1920)
                && near(center.x, 0) && near(center.y, 0)
            facts["current-handle-alias-\(index)"] = try observe(fixture, id: id,
                condition: "thisLayer.origin.x===120&&thisObject.origin.y===-40&&thisScene.getLayerByID(\(id)).origin.z===620")
            if first == nil { first = snapshot }
        }
        facts["projection-follows-live-zoom"] = near(projectedEdges[0] / 0.73, projectedEdges[1])
            && near(projectedEdges[2] / 0.8, projectedEdges[1]) && projectedEdges[1] > 0
        facts["held-snapshot-immutable"] = first?[zoomTarget]?.value == .scalar(0.73)
            && first?[originTarget]?.value == .vector3(120, -40, 620)
        let before = fixture.live
        facts["same-value-is-noop"] = fixture.live.apply(.number(0.8), forPropertyKey: key)
            && fixture.live.revision == before.revision
        for (index, invalid) in [0.0, 101.0, .infinity].enumerated() {
            facts["invalid-zoom-atomic-\(index)"] = !fixture.live.apply(.number(invalid), forPropertyKey: key)
                && fixture.live.effectiveValues == before.effectiveValues
                && fixture.live.userValues == before.userValues && fixture.live.revision == before.revision
        }
        return ["facts": facts, "zooms": zooms, "origins": origins]
    }

    static func fallbacks() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let staticFixture = try Fixture(root(scripted: false, direct: false), key: "lensScale")
        let (staticSnapshot, staticEvaluation) = try staticFixture.frame()
        facts["static-path-values-reach-camera"] = staticEvaluation.failures.isEmpty
            && staticFixture.vector.bindings.isEmpty
            && staticSnapshot[originTarget]?.value == .vector3(0, 0, 500)
            && staticSnapshot[zoomTarget]?.value == .scalar(0.73)
            && staticSnapshot[originTarget]?.source == .authored
            && staticFixture.camera(staticSnapshot).cameraOrigin == SIMD3(0, 0, 500)
            && near(staticFixture.camera(staticSnapshot).coverHalfExtents.x * 0.73, 1920)
        let throwingRoot = changingFirst(root()) {
            $0["origin"] = ["value": "0 0 500", "script": "export function init(v){throw Error('own camera failure');}"]
        }
        let throwing = try Fixture(throwingRoot, key: "lensScale")
        let (first, failed) = try throwing.frame()
        facts["script-throw-keeps-authored-origin"] = failed.failures[originTarget]?.code == "exception"
            && first[originTarget]?.value == .vector3(0, 0, 500)
            && first[originTarget]?.source == .authored
            && throwing.camera(first).cameraOrigin == SIMD3(0, 0, 500)
        let applied = throwing.live.apply(.number(1), forPropertyKey: "lensScale")
        let (next, _) = try throwing.frame()
        facts["script-failure-does-not-poison-zoom"] = applied
            && next[originTarget]?.value == .vector3(0, 0, 500)
            && next[zoomTarget]?.value == .scalar(1)
            && throwing.camera(next).coverHalfExtents.x == 1920
        var peerScene = changingFirst(root()) {
            $0["origin"] = ["value": "0 0 500", "script": """
                export function init(value){
                    thisScene.getLayerByID(8).alpha=0.2;
                    return new Vec3(120,-40,620);
                }
                """]
        }
        var peerObjects = peerScene["objects"] as! [[String: Any]]
        peerObjects.append(["id": 8, "image": "models/healthy-peer.json", "origin": "0 0 0",
            "size": "10 10", "alpha": 0.5])
        peerScene["objects"] = peerObjects
        let peerFixture = try Fixture(peerScene, key: "lensScale")
        let (peerSnapshot, peerEvaluation) = try peerFixture.frame()
        facts["camera-return-and-healthy-peer-bundle-accepted"] = peerEvaluation.failures.isEmpty
            && peerFixture.rejectedOwners.isEmpty
            && peerEvaluation.layerMutations.contains { $0.layerID == 8 && $0.fields.contains(.alpha) }
            && peerSnapshot[originTarget]?.value == .vector3(120,-40,620)
            && peerFixture.layers.snapshot().authoredLayerValues[.layer(layerID: 8, field: .alpha)] == .scalar(0.2)
        let (peerNext, _) = try peerFixture.frame()
        facts["healthy-peer-next-cadence-typed-publication"] = peerNext[originTarget]?.value == .vector3(120,-40,620)
            && peerNext[.layer(layerID: 8, field: .alpha)]?.value == .scalar(0.2)
        try peerFixture.domain.publishLayerSnapshot(peerNext, descriptor: peerFixture.descriptor)
        facts["camera-and-healthy-peer-current-published"] = try observe(peerFixture, id: 8,
            condition: "thisLayer.alpha===0.2&&thisScene.getLayerByID(7).origin.x===120")
        var layerScene = changingFirst(root()) {
            $0["origin"] = ["value": "0 0 0", "script": """
                export function init(value){
                    if(thisLayer.id!==7||thisObject.origin.z!==0)throw Error('old layer identity');
                    thisScene.getLayerByID(8).alpha=0.2;
                    thisObject.origin=new Vec3(90,80,0);
                    return thisLayer.origin;
                }
                """]
        }
        var layerObjects = layerScene["objects"] as! [[String: Any]]
        layerObjects.append(["id": 8, "image": "models/old-peer.json", "origin": "0 0 0",
            "size": "10 10", "alpha": 0.5])
        layerScene["objects"] = layerObjects
        let layerFixture = try Fixture(layerScene, key: "lensScale")
        let oldOrigin = SceneDynamicTarget.layer(layerID: 7, field: .origin)
        let (layerSnapshot, layerEvaluation) = try layerFixture.frame()
        facts["camera-ineligible-origin-keeps-old-layer-owner"] = layerFixture.descriptor.camera.default2DInputLayerID == 7
            && layerFixture.descriptor.camera.default2DOriginInputLayerID == nil
            && layerFixture.vector.inputTargets == [oldOrigin]
            && layerFixture.definitions.filter { $0.target == oldOrigin }.count == 1
            && !layerFixture.definitions.contains { $0.target == originTarget }
            && layerEvaluation.failures.isEmpty && layerFixture.rejectedOwners.isEmpty
            && layerSnapshot[oldOrigin]?.value == .vector3(90,80,0)
            && layerFixture.layers.snapshot().authoredLayerValues[.layer(layerID: 8, field: .alpha)] == .scalar(0.2)
            && layerSnapshot[zoomTarget]?.value == .scalar(0.73)
            && layerEvaluation.layerMutations.contains { $0.layerID == 7 && $0.fields.contains(.origin) }
        try layerFixture.domain.publishLayerSnapshot(layerSnapshot, descriptor: layerFixture.descriptor)
        facts["camera-ineligible-origin-keeps-current-handle"] = try observe(layerFixture, id: 7,
            condition: "thisLayer.origin.x===90&&thisObject.origin.y===80&&thisScene.getLayerByID(7).origin.z===0")
        let oldZoomApplied = layerFixture.live.apply(.number(1), forPropertyKey: "lensScale")
        let (layerNext, _) = try layerFixture.frame()
        facts["camera-ineligible-origin-keeps-independent-zoom"] = oldZoomApplied
            && layerNext[oldOrigin]?.value == .vector3(90,80,0)
            && layerNext[.layer(layerID: 8, field: .alpha)]?.value == .scalar(0.2)
            && layerNext[zoomTarget]?.value == .scalar(1)
        for mode in ["setter", "throw"] {
            let ending = mode == "throw" ? "throw Error('own rollback');" : "return new Vec3(120,-40,620);"
            var scene = changingFirst(root()) {
                $0["origin"] = ["value": "0 0 500", "script": """
                    export function init(v){
                        thisScene.getLayerByID(8).alpha=0.2;
                        thisObject.origin=new Vec3(9,8,700);
                        \(ending)
                    }
                    """]
            }
            var objects = scene["objects"] as! [[String: Any]]
            objects.append(["id": 8, "image": "models/peer.json", "origin": "0 0 0",
                "size": "10 10", "alpha": ["value": 0.5,
                    "script": "export function update(value){return 0.6;}"]])
            scene["objects"] = objects
            let fixture = try Fixture(scene, key: "lensScale")
            let acceptedBeforeCallback = fixture.transaction.committedSnapshot
            let (snapshot, evaluation) = try fixture.frame()
            let cameThroughC = evaluation.layerMutations.contains { $0.layerID == 7 && $0.fields.contains(.origin) }
            facts[mode + "-rejects-the-whole-owner"] = mode == "setter"
                ? evaluation.failures.isEmpty && cameThroughC && fixture.rejectedOwners == [originTarget]
                : evaluation.failures[originTarget]?.code == "exception" && evaluation.layerMutations.isEmpty
            facts[mode + "-no-camera-or-peer-leak"] = snapshot[originTarget]?.value == .vector3(0,0,500)
                && snapshot[originTarget]?.value == acceptedBeforeCallback?[originTarget]?.value
                && snapshot[originTarget]?.source == .authored
                && fixture.scalarProgram.bindings.count == 1
                && snapshot[.layer(layerID: 8, field: .alpha)]?.value == .scalar(0.6)
                && snapshot[.layer(layerID: 8, field: .alpha)]?.source == .sceneScript
                && fixture.layers.snapshot().authoredLayerValues.isEmpty
                && !fixture.definitions.contains { $0.target == .layer(layerID: 7, field: .origin) }
            facts[mode + "-c-journal-rolled-back"] = try observe(fixture, id: 8,
                condition: "thisLayer.alpha===0.5&&thisScene.getLayerByID(7).origin.x===0")
        }
        return facts
    }

    static func rejections() throws -> [String: Bool] {
        let ordinary = root(scripted: false)
        var multiple = ordinary
        var objects = multiple["objects"] as! [[String: Any]]
        var second = objects[0]; second["id"] = 8; second["path"] = "paths/another.json"
        objects.append(second); multiple["objects"] = objects
        var native = ordinary; native["general"] = ["nearz": 0.01, "farz": 10000]
        let nondefault = changingFirst(ordinary) { $0["camera"] = "secondary" }
        let noncamera = changingFirst(ordinary) {
            $0.removeValue(forKey: "camera"); $0.removeValue(forKey: "path")
            $0["image"] = "models/self-owned.json"; $0["size"] = "10 10"
        }
        var facts: [String: Bool] = [:]
        for (name, scene) in [("multiple", multiple), ("native", native),
                               ("nondefault", nondefault), ("noncamera", noncamera)] {
            let fixture = try Fixture(scene, key: "lensScale")
            let (snapshot, _) = try fixture.frame()
            facts[name + "-not-a-default-2d-producer"] = fixture.descriptor.camera.default2DInputLayerID == nil
                && !fixture.definitions.contains { $0.target == originTarget || $0.target == zoomTarget }
                && !fixture.property.program.instructions.contains { $0.target == zoomTarget }
                && snapshot.cameraTransform() == .identity
        }
        let unknownZoomWrapper = changingFirst(ordinary) {
            $0["zoom"] = ["user": "lensScale", "value": 0.73, "unrecognized": true]
        }
        let unknown = try Fixture(unknownZoomWrapper, key: "lensScale")
        facts["unknown-zoom-wrapper-is-not-live"] = !unknown.property.program.instructions.contains {
            $0.target == zoomTarget
        } && !unknown.live.apply(.number(0.9), forPropertyKey: "lensScale")
        let invalid = try Fixture(changingFirst(ordinary) { $0["zoom"] = 0 }, key: "lensScale")
        let (invalidSnapshot, _) = try invalid.frame()
        facts["invalid-authored-zoom-keeps-identity-component"] = invalidSnapshot[zoomTarget] == nil
            && invalidSnapshot.cameraTransform().zoom == 1
        return facts
    }

    static func single(_ lanes: [[Double]], fps: Double, length: Double,
                       relative: Bool = false, paused: Bool = false) -> [String: Any] {
        var animation: [String: Any] = ["relative": relative,
            "options": ["mode": "single", "fps": fps, "length": length, "startpaused": paused]]
        for (index, values) in lanes.enumerated() {
            animation["c\(index)"] = [["frame": 0, "value": values[0]],
                                      ["frame": length, "value": values[1]]]
        }
        return animation
    }

    static func animated(_ variant: Int = 0, origin: Bool = true, zoom: Bool = true,
                         pausedZoom: Bool = false) -> [String: Any] {
        changingFirst(root(id: variant == 0 ? 7 : 709, variant: variant,
                           scripted: false, direct: false)) {
            if origin {
                $0["origin"] = ["value": "0 0 500", "animation": single(
                    [[0,120], [0,-40], [0,100]], fps: 10, length: 20, relative: true)]
            }
            if zoom {
                $0["zoom"] = ["value": 0.73, "animation": single(
                    [[1,2]], fps: 5, length: 20, paused: pausedZoom)]
            }
        }
    }

    static func combined(_ input: [String: Any]) -> [String: Any] {
        changingFirst(input) {
            var origin = $0["origin"] as! [String: Any], zoom = $0["zoom"] as! [String: Any]
            var a = origin["animation"] as! [String: Any], b = zoom["animation"] as! [String: Any]
            var ao = a["options"] as! [String: Any], bo = b["options"] as! [String: Any]
            ao["children"] = [["key": "zoom"]]; bo["parent"] = ["key": "origin"]
            a["options"] = ao; b["options"] = bo; origin["animation"] = a; zoom["animation"] = b
            $0["origin"] = origin; $0["zoom"] = zoom
        }
    }

    static func independent(_ variant: Int) throws -> [String: Bool] {
        let id = variant == 0 ? 7 : 709
        var input = animated(variant)
        if variant != 0 {
            input = changingFirst(input) {
                // Null competing sources are absent, independent of key order/name/path.
                var origin = $0["origin"] as! [String: Any]
                origin["script"] = NSNull(); origin["user"] = NSNull()
                $0["origin"] = origin
            }
        }
        let fixture = try Fixture(input, key: "lensScale")
        var facts: [String: Bool] = [
            "prepared-source": fixture.descriptor.camera.default2DInputLayerID == id
                && fixture.descriptor.camera.default2DOriginInputLayerID == id,
            "independent-owners": Set(fixture.timeline.bindings.map(\.playbackOwnerTarget))
                == [originTarget, zoomTarget],
            "source-has-one-origin-writer": !fixture.definitions.contains {
                $0.target == .layer(layerID: id, field: .origin)
            } && fixture.definitions.filter { $0.target == originTarget }.count == 1,
            "origin-fps-length": fixture.timeline.bindings.first { $0.target == originTarget }?
                .animation.options.durationSeconds == 2,
            "zoom-fps-length": fixture.timeline.bindings.first { $0.target == zoomTarget }?
                .animation.options.durationSeconds == 4,
        ]
        let (first, _) = try fixture.frame(sceneTime: 1)
        facts["independent-values"] = first[originTarget]?.value == .vector3(60,-20,550)
            && first[zoomTarget]?.value == .scalar(1.25)
            && first[originTarget]?.source == .timeline && first[zoomTarget]?.source == .timeline
        let camera = fixture.camera(first)
        facts["actual-camera-frame"] = camera.cameraOrigin == SIMD3(60,-20,550)
            && near(camera.coverHalfExtents.x * 1.25, 1920)
        try fixture.domain.publishLayerSnapshot(first, descriptor: fixture.descriptor)
        facts["source-getter-identity"] = try observe(fixture, id: id,
            condition: "thisScene.getLayerByID(\(id)).origin.x===60&&thisScene.getLayerByID(\(id)).origin.z===550")
        let (paused, _) = try fixture.frame(sceneTime: 1, commands: [.init(target: originTarget, command: .pause)])
        let (next, _) = try fixture.frame(sceneTime: 2)
        facts["pause-only-origin"] = paused[originTarget]?.value == next[originTarget]?.value
            && next[zoomTarget]?.value == .scalar(1.5)
        _ = try fixture.frame(sceneTime: 3, commands: [.init(target: originTarget, command: .play)])
        let (finished, _) = try fixture.frame(sceneTime: 4)
        facts["resume-and-finish"] = finished[originTarget]?.value == .vector3(120,-40,600)
            && finished[zoomTarget]?.value == .scalar(2)
        let (stopped, _) = try fixture.frame(sceneTime: 5,
            commands: [.init(target: zoomTarget, command: .stop)])
        facts["stop-only-zoom"] = stopped[zoomTarget]?.value == .scalar(1)
            && stopped[originTarget]?.value == finished[originTarget]?.value
        facts["held-snapshot"] = first[originTarget]?.value == .vector3(60,-20,550)
            && first[zoomTarget]?.value == .scalar(1.25)
        for (name, origin, zoom) in [("origin-only", true, false), ("zoom-only", false, true)] {
            let one = try Fixture(animated(variant, origin: origin, zoom: zoom), key: "lensScale")
            let (snapshot, _) = try one.frame(sceneTime: 1)
            facts[name] = one.timeline.bindings.count == 1
                && snapshot[originTarget]?.value == (origin ? .vector3(60,-20,550) : .vector3(0,0,500))
                && snapshot[zoomTarget]?.value == (zoom ? .scalar(1.25) : .scalar(0.73))
                && one.camera(snapshot).cameraOrigin == (origin ? SIMD3(60,-20,550) : SIMD3(0,0,500))
        }
        let startPaused = try Fixture(animated(variant, pausedZoom: true), key: "lensScale")
        let (held, _) = try startPaused.frame(sceneTime: 1)
        _ = try startPaused.frame(sceneTime: 1, commands: [.init(target: zoomTarget, command: .play)])
        let (running, _) = try startPaused.frame(sceneTime: 2)
        facts["independent-start-paused"] = held[originTarget]?.value == .vector3(60,-20,550)
            && held[zoomTarget]?.value == .scalar(1)
            && running[originTarget]?.value == .vector3(120,-40,600)
            && running[zoomTarget]?.value == .scalar(1.25)
        let old = try Fixture(combined(animated(variant)), key: "lensScale")
        let (oldFirst, _) = try old.frame(sceneTime: 1)
        _ = try old.frame(sceneTime: 1, commands: [.init(target: zoomTarget, command: .pause)])
        let (oldNext, _) = try old.frame(sceneTime: 2)
        facts["combined-owner-and-pause-preserved"] = old.timeline.bindings.count == 2
            && old.timeline.bindings.allSatisfy { $0.playbackOwnerTarget == originTarget }
            && oldFirst[zoomTarget]?.value == .scalar(1.5)
            && oldFirst[originTarget]?.value == oldNext[originTarget]?.value
            && oldFirst[zoomTarget]?.value == oldNext[zoomTarget]?.value
        return facts
    }

    static func pathVisibility() throws -> [String: Bool] {
        let input = changingFirst(animated()) { $0["visible"] = ["user": "openingGate", "value": true] }
        let properties: [String: Any] = ["openingGate": ["type": "bool", "value": true]]
        let fixture = try Fixture(input, key: "lensScale", additionalProperties: properties)
        let visible = SceneDynamicTarget.layer(layerID: 7, field: .visibility)
        var facts: [String: Bool] = ["bool-input-prepared": fixture.live.apply(.bool(false), forPropertyKey: "openingGate")]
        let (off, _) = try fixture.frame(sceneTime: 1)
        facts["launch-off-gates-camera-only"] = fixture.camera(off).cameraOrigin == .zero
            && near(fixture.camera(off).coverHalfExtents.x, 1920)
            && off[originTarget]?.value == .vector3(60,-20,550)
        let (scriptOn, _) = try fixture.frame(sceneTime: 1,
            committedValues: [visible: .bool(true)])
        facts["same-frame-committed-bool-wins"] = scriptOn[visible]?.source == .sceneScript
            && fixture.camera(scriptOn).cameraOrigin == SIMD3(60,-20,550)
        let (bad, _) = try fixture.frame(sceneTime: 1, committedValues: [visible: .scalar(1)])
        facts["wrong-type-does-not-enable"] = fixture.camera(bad).cameraOrigin == .zero
        facts["enable-existing-bool"] = fixture.live.apply(.bool(true), forPropertyKey: "openingGate")
        let (on, _) = try fixture.frame(sceneTime: 2)
        facts["hidden-time-continues"] = fixture.camera(on).cameraOrigin == SIMD3(120,-40,600)
            && on[zoomTarget]?.value == .scalar(1.5)
        _ = fixture.live.apply(.bool(false), forPropertyKey: "openingGate")
        _ = try fixture.frame(sceneTime: 3)
        _ = fixture.live.apply(.bool(true), forPropertyKey: "openingGate")
        let (after, _) = try fixture.frame(sceneTime: 5)
        facts["show-after-end-keeps-end-not-replay"] = fixture.camera(after).cameraOrigin == SIMD3(120,-40,600)
            && after[zoomTarget]?.value == .scalar(2)
        var parented = changingFirst(input) { $0["parent"] = 8 }
        var objects = parented["objects"] as! [[String: Any]]
        objects.append(["id": 8, "visible": false]); parented["objects"] = objects
        let parent = try Fixture(parented, key: "lensScale", additionalProperties: properties)
        let (hiddenParent, _) = try parent.frame(sceneTime: 1)
        let (shownParent, _) = try parent.frame(sceneTime: 1,
            committedValues: [.layer(layerID: 8, field: .visibility): .bool(true)])
        facts["parent-authority-same-snapshot"] = parent.camera(hiddenParent).cameraOrigin == .zero
            && parent.camera(shownParent).cameraOrigin == SIMD3(60,-20,550)
            && parent.camera(hiddenParent).cameraOrigin == .zero
        return facts
    }

    static func independentRejections() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("zero-origin-z", { var value = $0["origin"] as! [String: Any]; value["value"] = "0 0 0"; $0["origin"] = value }),
            ("unknown-origin-wrapper", { var value = $0["origin"] as! [String: Any]; value["unknown"] = true; $0["origin"] = value }),
            ("absolute-origin", { var value = $0["origin"] as! [String: Any]; var a = value["animation"] as! [String: Any]; a["relative"] = false; value["animation"] = a; $0["origin"] = value }),
            ("near-plane-control", { var value = $0["origin"] as! [String: Any]; var a = value["animation"] as! [String: Any]; a["c2"] = [["frame": 0, "value": -500], ["frame": 20, "value": 0]]; value["animation"] = a; $0["origin"] = value }),
            ("far-plane-control", { var value = $0["origin"] as! [String: Any]; var a = value["animation"] as! [String: Any]; a["c2"] = [["frame": 0, "value": 0, "front": ["enabled": true, "x": 0.5, "y": 10000]], ["frame": 20, "value": 0]]; value["animation"] = a; $0["origin"] = value }),
            ("bad-component", { var value = $0["origin"] as! [String: Any]; var a = value["animation"] as! [String: Any]; a.removeValue(forKey: "c2"); value["animation"] = a; $0["origin"] = value }),
            ("incoming-peer-keeps-independent-zoom", { var a = single([[0,1]], fps: 10, length: 20); var options = a["options"] as! [String: Any]; options["parent"] = ["key": "origin"]; a["options"] = options; $0["alpha"] = ["value": 1, "animation": a] }),
        ]
        for (name, change) in cases {
            let fixture = try Fixture(changingFirst(animated(), change), key: "lensScale")
            let (snapshot, _) = try fixture.frame(sceneTime: 1)
            facts[name] = fixture.timeline.bindings.map(\.target) == [zoomTarget]
                && fixture.descriptor.camera.default2DOriginInputLayerID == nil
                && snapshot[originTarget] == nil && snapshot[zoomTarget]?.value == .scalar(1.25)
                && fixture.camera(snapshot).cameraOrigin == .zero
        }
        let zoomBad = try Fixture(changingFirst(animated()) {
            $0["zoom"] = ["value": 0.73, "animation": single([[0,2]], fps: 5, length: 20)]
        }, key: "lensScale")
        let (zoomBadSnapshot, _) = try zoomBad.frame(sceneTime: 1)
        facts["bad-zoom-preserves-origin-not-static-fallback"] = zoomBad.timeline.bindings.map(\.target) == [originTarget]
            && zoomBadSnapshot[zoomTarget] == nil
            && zoomBad.camera(zoomBadSnapshot).cameraOrigin == SIMD3(60,-20,550)
            && near(zoomBad.camera(zoomBadSnapshot).coverHalfExtents.x, 1920)
        let disabledControl = try Fixture(changingFirst(animated()) {
            var value = $0["origin"] as! [String: Any], a = value["animation"] as! [String: Any]
            a["c2"] = [["frame": 0, "value": 0, "front": ["enabled": false, "x": 0.5, "y": 10000]],
                         ["frame": 20, "value": 0]]
            value["animation"] = a; $0["origin"] = value
        }, key: "lensScale")
        let (disabledSnapshot, _) = try disabledControl.frame(sceneTime: 1)
        facts["unconsumed-control-is-not-a-rejection"] = disabledControl.timeline.bindings.count == 2
            && disabledSnapshot[originTarget]?.value == .vector3(60,-20,500)
        var multiple = animated(), native = animated()
        var objects = multiple["objects"] as! [[String: Any]], second = objects[0]
        second["id"] = 8; second["path"] = "paths/another.json"
        objects.append(second); multiple["objects"] = objects
        var general = native["general"] as! [String: Any]
        general.removeValue(forKey: "orthogonalprojection"); native["general"] = general
        let secondary = changingFirst(animated()) { $0["camera"] = "secondary" }
        for (name, input) in [("multiple-animated-sources", multiple),
                              ("native-animated-source", native), ("secondary-animated-source", secondary)] {
            let fixture = try Fixture(input, key: "lensScale")
            let (snapshot, _) = try fixture.frame(sceneTime: 1)
            facts[name] = fixture.timeline.bindings.isEmpty
                && fixture.descriptor.camera.default2DInputLayerID == nil
                && snapshot[originTarget] == nil && snapshot[zoomTarget] == nil
                && snapshot.cameraTransform() == .identity
        }
        for reverse in [false, true] {
            let input = changingFirst(animated()) {
                let field = reverse ? "zoom" : "origin"
                var value = $0[field] as! [String: Any], a = value["animation"] as! [String: Any]
                var options = a["options"] as! [String: Any]
                options["children"] = [["key": reverse ? "origin" : "zoom"]]
                a["options"] = options; value["animation"] = a; $0[field] = value
                if reverse {
                    var origin = $0["origin"] as! [String: Any], oa = origin["animation"] as! [String: Any]
                    var oo = oa["options"] as! [String: Any]; oo["parent"] = ["key": "zoom"]
                    oa["options"] = oo; origin["animation"] = oa; $0["origin"] = origin
                }
            }
            let fixture = try Fixture(input, key: "lensScale")
            let (snapshot, _) = try fixture.frame(sceneTime: 1)
            facts[reverse ? "reverse-combined-rejected" : "incomplete-peer-rejected"] = fixture.timeline.bindings.isEmpty
                && snapshot[originTarget] == nil && snapshot[zoomTarget] == nil
        }
        return facts
    }

    static func malformedPeers() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for target in ["origin", "zoom"] {
            for error in ["unknown-mode", "empty-lane", "malformed-child"] {
                var peer = single([[0,1]], fps: 10, length: 20)
                var options = peer["options"] as! [String: Any]
                if error == "malformed-child" {
                    options["children"] = [["key": target], 17] as [Any]
                } else {
                    options["parent"] = ["key": target]
                    if error == "unknown-mode" { options["mode"] = "unknown" }
                    else { peer["c0"] = [] as [Any] }
                }
                peer["options"] = options
                let fixture = try Fixture(changingFirst(animated()) {
                    $0["alpha"] = ["value": 1, "animation": peer]
                }, key: "lensScale")
                let (snapshot, _) = try fixture.frame(sceneTime: 1)
                let blocksOrigin = target == "origin"
                let expected = blocksOrigin ? zoomTarget : originTarget
                let original = fixture.document.objects.first { $0.id == 7 }
                facts["\(target)-\(error)-parser-keeps-failure"] =
                    original?.timelines.contains { $0.host == .alpha } == false
                    && original?.timelineDiagnostics.contains { $0.hasPrefix("alpha:") } == true
                facts["\(target)-\(error)-local-rejection"] = fixture.timeline.bindings.map(\.target) == [expected]
                    && snapshot[blocksOrigin ? originTarget : zoomTarget] == nil
                    && snapshot[expected]?.value == (blocksOrigin ? .scalar(1.25) : .vector3(60,-20,550))
                    && fixture.camera(snapshot).cameraOrigin == (blocksOrigin ? .zero : SIMD3(60,-20,550))
                facts["\(target)-\(error)-origin-route"] =
                    (fixture.descriptor.camera.default2DOriginInputLayerID == nil) == blocksOrigin
                    && fixture.definitions.contains { $0.target == .layer(layerID: 7, field: .origin) } == blocksOrigin
                let grouped = try Fixture(changingFirst(combined(animated())) {
                    $0["alpha"] = ["value": 1, "animation": peer]
                }, key: "lensScale")
                let (groupSnapshot, _) = try grouped.frame(sceneTime: 1)
                facts["\(target)-\(error)-combined-rejects-external-peer"] = grouped.timeline.bindings.isEmpty
                    && groupSnapshot[originTarget] == nil && groupSnapshot[zoomTarget] == nil
            }
        }
        var unrelated = single([[0,1]], fps: 10, length: 20)
        var options = unrelated["options"] as! [String: Any]
        options["mode"] = "unknown"; options["parent"] = ["key": "scale"]
        unrelated["options"] = options
        let fixture = try Fixture(changingFirst(animated()) {
            $0["alpha"] = ["value": 1, "animation": unrelated]
        }, key: "lensScale")
        let (snapshot, _) = try fixture.frame(sceneTime: 1)
        facts["unrelated-hard-error-is-not-blanket-rejection"] = fixture.timeline.bindings.count == 2
            && snapshot[originTarget]?.value == .vector3(60,-20,550)
            && snapshot[zoomTarget]?.value == .scalar(1.25)
        return facts
    }

    static func main() throws {
        let result: [String: Any] = ["mixed": try [mixed(0), mixed(1)],
            "fallbacks": try fallbacks(), "rejections": try rejections(),
            "independent": try [independent(0), independent(1)],
            "pathVisibility": try pathVisibility(), "independentRejections": try independentRejections(),
            "malformedPeers": try malformedPeers()]
        print(String(data: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
