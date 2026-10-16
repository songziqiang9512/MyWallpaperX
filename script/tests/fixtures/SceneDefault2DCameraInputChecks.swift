import CoreGraphics
import Foundation
import simd

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
        var definitions: [SceneDynamicTargetDefinition]
        let layers: SceneScriptDynamicLayerRuntime
        var live: ScenePropertyLiveUpdateState
        var transaction = SceneEvaluationTransaction()
        var frameIndex: UInt64 = 0
        var rejectedOwners: Set<SceneDynamicTarget> = []

        init(_ root: [String: Any], key: String, schemaDefault: Double = 0.73) throws {
            serial += 1
            let directory = URL(fileURLWithPath: CommandLine.arguments[1])
            let url = directory.appendingPathComponent("own-camera-\(serial).json")
            try JSONSerialization.data(withJSONObject: root,
                options: serial.isMultiple(of: 2) ? [.sortedKeys] : []).write(to: url)
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
                key: ["type": "slider", "value": schemaDefault, "min": 0.01, "max": 100]])
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

        func frame() throws -> (SceneDynamicSnapshot, SceneScriptVectorFrameResult) {
            frameIndex += 1
            definitions = SceneDynamicDefinitionMerger.merge(
                propertyDefinitions: property.program.definitions, timelineProgram: timeline,
                textScriptProgram: .init(), additionalDefinitions: vector.definitions
                    + scalarProgram.definitions + layers.authoredLayerDefinitions
                    + SceneDefault2DCameraInputProfile.definitions(descriptor: descriptor,
                        timelineTargets: Set(timeline.bindings.map(\.target))))
            let index = SceneDynamicSnapshotResolver.prepare(definitions: definitions)
            let timelineValues = SceneTimelineRuntime.values(program: timeline, sceneTime: Double(frameIndex))
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
                    simulationFrameTime: 1.0/60.0, sceneTime: Double(frameIndex))),
                propertyRevision: live.revision)
            let scalar = scalarProgram.evaluate(inputs: preliminary.snapshot.typedValues(
                    for: scalarProgram.inputTargets, valueTypes: scalarProgram.inputValueTypes),
                frame: SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1.0/60.0, sceneTime: Double(frameIndex))),
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let admission = layers.preflightOwnerEffects(result.ownerEffects + scalar.ownerEffects)
            rejectedOwners = Set(admission.rejectedOwners.compactMap(\.ownerTarget))
            layers.commit(admission.layerPlan)
            let scriptValues = result.values.merging(scalar.values) { _, current in current }
                .filter { !rejectedOwners.contains($0.key) }
            let resolution = SceneDynamicSnapshotResolver().resolve(frameIndex: frameIndex,
                generation: 0, index: index, base: preliminary,
                timelineValues: timelineValues, sceneScriptValues: scriptValues)
            let pending = transaction.prepare(frameIndex: frameIndex, resolution: resolution)
            transaction.commit(pending)
            vector.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejectedOwners)
            scalarProgram.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejectedOwners)
            return (pending.snapshot, result)
        }

        func camera(_ snapshot: SceneDynamicSnapshot) -> SceneParticleCameraFrame {
            let transform = snapshot.cameraTransform()
            return SceneParticleCameraFrame(camera: descriptor.camera, viewportSize: viewport,
                cameraOrigin: transform.origin, cameraZoom: transform.zoom,
                dynamicValues: snapshot)
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

    static func main() throws {
        let result: [String: Any] = ["mixed": try [mixed(0), mixed(1)],
            "fallbacks": try fallbacks(), "rejections": try rejections()]
        print(String(data: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
