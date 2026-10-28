import Foundation
import simd

// The main fixture owns parser/descriptor/VM/resolver/camera construction.
// These cases exercise the handle alias and transaction boundary on that chain.
extension SceneDefault2DCameraInputChecks {
    static func setterScene(_ source: String, cameraID: Int = 7, ownerID: Int = 8,
                            renamed: Bool = false) -> [String: Any] {
        var scene = root(id: cameraID, variant: renamed ? 1 : 0, scripted: false)
        var objects = scene["objects"] as! [[String: Any]]
        objects.append(["id": ownerID, "name": renamed ? "different controller" : "controller",
            "image": renamed ? "models/renamed-controller.json" : "models/controller.json",
            "size": "10 10", "origin": ["value": "0 0 0", "script": source]])
        objects.append(["id": ownerID + 1, "image": "models/healthy-adjacent.json",
            "size": "10 10", "origin": "0 0 0", "alpha": ["value": 0.5,
                "script": "export function update(v){return 0.6;}"]])
        scene["objects"] = objects
        return scene
    }

    static func setterAliases(_ variant: Int) throws -> [String: Bool] {
        let id = variant == 0 ? 7 : 37, ownerID = id + 1
        let handle = variant == 0 ? "lens" : "retainedReference"
        let expression = variant == 0 ? "new Vec3(9,8,700)" : "new Vec3(3*3,4+4,350*2)"
        let source = """
            let \(handle), ticks=0;
            export function init(v){\(handle)=thisScene.getLayerByID(\(id));return v;}
            export function update(v){
                if(++ticks===1) \(handle).origin=\(expression);
                else if(\(handle).origin.x!==9)throw Error('cached handle lost alias');
                if(\(handle).origin.y!==8||thisScene.getLayerByID(\(id)).origin.z!==700)throw Error('immediate readback');
                return v;
            }
            """
        let fixture = try Fixture(setterScene(source, cameraID: id, ownerID: ownerID,
                                               renamed: variant == 1), key: "lensScale")
        let owner = fixture.vector.bindings.first?.owner
        let (first, evaluation) = try fixture.frame()
        let held = fixture.layers.snapshot()
        let firstCamera = fixture.camera(first)
        let (next, second) = try fixture.frame()
        try fixture.domain.publishLayerSnapshot(next, descriptor: fixture.descriptor)
        return [
            "real-parser-prepared-unique-source": fixture.descriptor.camera.default2DOriginInputLayerID == id
                && fixture.document.objects.contains { $0.id == ownerID && $0.imagePath != nil },
            "setter-real-c-journal": evaluation.failures.isEmpty && second.failures.isEmpty
                && evaluation.layerMutations.contains { $0.layerID == id && $0.fields.contains(.origin) },
            "setter-does-not-claim-current-snapshot": first[originTarget]?.value == .vector3(0,0,500)
                && firstCamera.cameraOrigin == SIMD3(0,0,500),
            "one-typed-alias-no-layer-writer": held.authoredLayerValues[originTarget] == .vector3(9,8,700)
                && held.authoredLayerValues[.layer(layerID: id, field: .origin)] == nil
                && fixture.layers.authoredLayerDefinitions.filter { $0.target == originTarget }.count == 1
                && !fixture.definitions.contains { $0.target == .layer(layerID: id, field: .origin) },
            "next-cadence-camera-and-current-origin": next[originTarget]?.value == .vector3(9,8,700)
                && next[originTarget]?.source == .sceneScript
                && fixture.camera(next).cameraOrigin == SIMD3(9,8,700),
            "cached-handle-owner-reused": fixture.vector.bindings.first?.owner === owner
                && fixture.rejectedOwners.isEmpty,
            "published-getter-alias": try observe(fixture, id: ownerID,
                condition: "thisScene.getLayerByID(\(id)).origin.x===9&&thisScene.getLayerByID(\(id)).origin.z===700"),
            "held-input-snapshot-stable": first[originTarget]?.value == .vector3(0,0,500)
                && held.authoredLayerValues[originTarget] == .vector3(9,8,700),
        ]
    }

    static func setterFailures() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let target = SceneDynamicTarget.layer(layerID: 8, field: .origin)
        for mode in ["throw", "over-limit", "external-late-reject", "nan", "infinity"] {
            let value = mode == "over-limit" ? "new Vec3(10000001,8,700)"
                : mode == "nan" ? "{x:NaN,y:8,z:700}"
                : mode == "infinity" ? "{x:9,y:Infinity,z:700}" : "new Vec3(9,8,700)"
            let source = """
                export function init(v){
                    thisScene.getLayerByID(9).alpha=0.2;
                    thisScene.getLayerByID(7).origin=\(value);
                    \(mode == "throw" ? "throw Error('rollback');" : "return v;")
                }
                """
            let fixture = try Fixture(setterScene(source), key: "lensScale")
            let (first, evaluation) = try fixture.frame(
                excludingOwners: mode == "external-late-reject" ? [target] : [])
            let rejected = fixture.rejectedOwners
            let state = fixture.layers.snapshot()
            let (next, _) = try fixture.frame()
            facts[mode + "-camera-remains-safe"] = first[originTarget]?.value == .vector3(0,0,500)
                && next[originTarget]?.value == .vector3(0,0,500)
                && fixture.camera(next).cameraOrigin == SIMD3(0,0,500)
                && state.authoredLayerValues[originTarget] == nil
            facts[mode + "-healthy-primary-peer-survives"] =
                first[.layer(layerID: 9, field: .alpha)]?.value == .scalar(0.6)
            if mode == "nan" || mode == "infinity" {
                // Existing numeric-nonfinite C setters are ignored, preserving
                // other valid mutations in that callback; no new policy here.
                facts[mode + "-ignored-before-swift"] = evaluation.failures.isEmpty
                    && !evaluation.layerMutations.contains { $0.layerID == 7 && $0.fields.contains(.origin) }
                    && state.authoredLayerValues[.layer(layerID: 9, field: .alpha)] == .scalar(0.2)
            } else {
                facts[mode + "-whole-bundle-rolled-back"] = state.authoredLayerValues.isEmpty
                facts[mode + "-correct-rejection-boundary"] = mode == "throw"
                    ? evaluation.failures[target]?.code == "exception"
                    : evaluation.failures.isEmpty && rejected == [target]
                if mode == "over-limit" {
                    facts["over-limit-reached-swift"] = evaluation.layerMutations.contains {
                        $0.layerID == 7 && $0.origin.x == 10000001 && $0.fields.contains(.origin)
                    }
                }
                try fixture.domain.publishLayerSnapshot(first, descriptor: fixture.descriptor)
                facts[mode + "-c-journal-current-restored"] = try observe(fixture, id: 8,
                    condition: "thisScene.getLayerByID(7).origin.x===0&&thisScene.getLayerByID(9).alpha===0.6")
            }
        }
        return facts
    }

    static func setterPeers() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for same in [true, false] {
            let source = "export function init(v){thisScene.getLayerByID(7).origin=new Vec3(9,8,700);return v;}"
            var scene = setterScene(source)
            var objects = scene["objects"] as! [[String: Any]]
            objects[2]["origin"] = ["value": "0 0 0", "script": """
                export function init(v){
                    thisScene.getLayerByID(7).origin=new Vec3(\(same ? 9 : 19),8,700);
                    thisScene.getLayerByID(8).alpha=0.25;
                    return v;
                }
                """]
            scene["objects"] = objects
            let fixture = try Fixture(scene, key: "lensScale")
            let (_, evaluation) = try fixture.frame()
            let rejected = fixture.rejectedOwners
            let state = fixture.layers.snapshot()
            let (next, _) = try fixture.frame()
            let prefix = same ? "same" : "different"
            facts[prefix + "-writers-reach-journal"] = evaluation.failures.isEmpty
                && evaluation.layerMutations.filter { $0.layerID == 7 && $0.fields.contains(.origin) }.count == 2
            facts[prefix + "-one-camera-value"] = state.authoredLayerValues[originTarget] == .vector3(9,8,700)
                && next[originTarget]?.value == .vector3(9,8,700)
                && fixture.camera(next).cameraOrigin == SIMD3(9,8,700)
            facts[prefix + "-owner-conflict-contract"] = same ? rejected.isEmpty
                : rejected == [.layer(layerID: 9, field: .origin)]
            facts[prefix + "-peer-bundle-atomic"] = state.authoredLayerValues[.layer(layerID: 8, field: .alpha)]
                == (same ? .scalar(0.25) : nil)
            try fixture.domain.publishLayerSnapshot(next, descriptor: fixture.descriptor)
            facts[prefix + "-rejected-c-handle-does-not-leak"] = try observe(fixture, id: 8,
                condition: "thisScene.getLayerByID(7).origin.x===9")
        }
        return facts
    }

    static func setterRetirement() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for reject in [false, true] {
            let fixture = try Fixture(setterScene("""
                let saved, ticks=0;
                export function init(v){saved=thisScene.getLayerByID(7);return v;}
                export function update(v){
                    if(++ticks===1)saved.origin=new Vec3(9,8,700);
                    else thisScene.destroyLayer(saved);
                    return v;
                }
                """), key: "lensScale")
            _ = try fixture.frame()
            let held = fixture.layers.snapshot()
            let (snapshot, evaluation) = try fixture.frame(excludingOwners: reject
                ? [.layer(layerID: 8, field: .origin)] : [])
            let state = fixture.layers.snapshot()
            let prefix = reject ? "discard" : "destroy"
            facts[prefix + "-real-c-destroy-request"] = evaluation.failures.isEmpty
                && evaluation.layerMutations.contains { $0.layerID == 7 && $0.kind == .destroy }
            facts[prefix + "-held-state-unchanged"] = held.authoredLayerValues[originTarget] == .vector3(9,8,700)
                && held.destroyedAuthoredLayerIDs.isEmpty
            facts[prefix + "-alias-and-membership-atomic"] = reject
                ? state.authoredLayerValues[originTarget] == .vector3(9,8,700)
                    && !state.destroyedAuthoredLayerIDs.contains(7)
                    && fixture.layers.authoredLayerDefinitions.contains { $0.target == originTarget }
                : state.authoredLayerValues[originTarget] == nil
                    && state.destroyedAuthoredLayerIDs.contains(7)
                    && !fixture.layers.authoredLayerDefinitions.contains { $0.target == originTarget }
            // Authored tombstones become C handle state through the existing
            // next publication, not by treating a journal commit as publication.
            try fixture.domain.publishLayerSnapshot(snapshot, descriptor: fixture.descriptor,
                destroyedAuthoredLayerIDs: state.destroyedAuthoredLayerIDs)
            facts[prefix + "-c-lifecycle-agrees"] = try observe(fixture, id: 8,
                condition: reject ? "thisScene.getLayerByID(7).origin.x===9"
                    : "thisScene.getLayerByID(7)===null")
        }
        return facts
    }

    static func setterNeighbors() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for invalid in [false, true] {
            var scene = setterScene("""
                export function init(v){thisScene.getLayerByID(7).origin=new Vec3(9,8,700);return v;}
                """)
            scene = changingFirst(scene) {
                if invalid { $0["camera"] = "secondary" }
                else { $0.removeValue(forKey: "camera"); $0.removeValue(forKey: "path")
                    $0["image"] = "models/ordinary-origin.json"; $0["size"] = "10 10" }
            }
            let fixture = try Fixture(scene, key: "lensScale")
            _ = try fixture.frame()
            let (next, _) = try fixture.frame()
            facts[invalid ? "bad-path-retains-layer-route" : "ordinary-layer-retains-layer-route"] =
                fixture.descriptor.camera.default2DOriginInputLayerID == nil
                && fixture.layers.snapshot().authoredLayerValues[.layer(layerID: 7, field: .origin)] == .vector3(9,8,700)
                && next[originTarget] == nil && fixture.camera(next).cameraOrigin == .zero
        }
        let source = "export function init(v){thisScene.getLayerByID(7).origin=new Vec3(9,8,700);return v;}"
        var scene = setterScene(source)
        scene = changingFirst(scene) {
            $0["origin"] = ["value": "0 0 500", "animation": single(
                [[0,120],[0,-40],[0,100]], fps: 10, length: 20, relative: true)]
        }
        let fixture = try Fixture(scene, key: "lensScale")
        let (first, _) = try fixture.frame(sceneTime: 1)
        let changed = fixture.live.apply(.number(1), forPropertyKey: "lensScale")
        let (next, _) = try fixture.frame(sceneTime: 1.5)
        facts["timeline-remains-current-before-setter-cadence"] = first[originTarget]?.source == .timeline
            && first[originTarget]?.value == .vector3(60,-20,550)
        facts["committed-setter-keeps-existing-script-over-timeline-priority"] =
            next[originTarget]?.source == .sceneScript && next[originTarget]?.value == .vector3(9,8,700)
            && fixture.camera(next).cameraOrigin == SIMD3(9,8,700)
        facts["independent-live-zoom-remains-effective"] = changed
            && next[zoomTarget]?.value == .scalar(1) && fixture.camera(next).coverHalfExtents.x == 1920
        return facts
    }

    static func setterCreatorRetirement() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for reject in [false, true] {
            var scene = setterScene("""
                let ticks=0;
                export function update(v){
                    if(++ticks===1)thisScene.getLayerByID(7).origin=new Vec3(9,8,700);
                    else thisScene.destroyLayer(thisScene.getLayerByID(7));
                    return v;
                }
                """)
            scene = changingFirst(scene) {
                $0["origin"] = ["value": "0 0 500", "script": """
                    export function init(v){
                        const child=thisScene.createLayer({text:'camera-owned child',pointsize:32});
                        if(child===null)throw Error('child unavailable');
                        child.origin=new Vec3(3,4,0);
                        return v;
                    }
                    """]
            }
            let fixture = try Fixture(scene, key: "lensScale")
            let (_, birth) = try fixture.frame()
            let held = fixture.layers.snapshot()
            let childIDs = Set(held.dynamicLayers.map(\.id))
            let (_, removal) = try fixture.frame(excludingOwners: reject
                ? [.layer(layerID: 8, field: .origin)] : [])
            let state = fixture.layers.snapshot()
            let prefix = reject ? "discard" : "retire"
            facts[prefix + "-camera-owner-created-real-child"] = birth.failures.isEmpty
                && birth.ownerEffects.contains { $0.ownerTarget == originTarget
                    && $0.layerMutations.contains { $0.isDynamic && $0.kind == .upsert } }
                && childIDs.count == 1 && held.dynamicLayers.first?.text == "camera-owned child"
                && held.authoredLayerValues[originTarget] == .vector3(9,8,700)
            facts[prefix + "-source-destroy-reached-journal"] = removal.failures.isEmpty
                && removal.layerMutations.contains { $0.layerID == 7 && $0.kind == .destroy }
            facts[prefix + "-creator-membership-and-values-atomic"] = reject
                ? Set(state.dynamicLayers.map(\.id)) == childIDs
                    && state.authoredLayerValues[originTarget] == .vector3(9,8,700)
                    && !state.destroyedAuthoredLayerIDs.contains(7)
                : state.dynamicLayers.isEmpty && state.authoredLayerValues[originTarget] == nil
                    && state.destroyedAuthoredLayerIDs.contains(7)
                    && !fixture.layers.authoredLayerDefinitions.contains { definition in
                        if case let .text(id, _) = definition.target { return childIDs.contains(id) }
                        if case let .layer(id, _) = definition.target { return childIDs.contains(id) }
                        return definition.target == originTarget
                    }
            facts[prefix + "-held-child-snapshot-stays-live"] =
                held.dynamicLayers.count == 1 && held.destroyedAuthoredLayerIDs.isEmpty
        }
        return facts
    }

    static func staticCameraScene() -> [String: Any] {
        var scene = setterScene("export function update(v){return v;}")
        scene["camera"] = ["eye": "80 -60 0", "center": "80 -60 -1", "up": "0 1 0"]
        scene["objects"] = (scene["objects"] as! [[String: Any]]).filter { ($0["id"] as? Int) != 7 }
        return scene
    }

    static func staticCameraBridge() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for renamed in [false, true] {
            let fixture = try Fixture(staticCameraScene(), key: "unusedCameraProperty")
            let name = renamed ? "anotherView" : "view"
            let expression = renamed ? "new Vec3(25*4,2-2,0)" : "new Vec3(100,0,0)"
            let owner = try SceneScriptValueOwner(domain: fixture.domain, source: """
                export function init(v){
                    const c=thisScene.getCameraTransforms();
                    if(c.eye.x!==2||c.eye.y!==2||c.eye.z!==2)throw Error('constructor phase');
                    thisScene.setCameraTransforms({eye:new Vec3(17,0,0)});
                    if(thisScene.getCameraTransforms().eye.x!==17)throw Error('init overlay');
                    return v;
                }
                export function update(v){
                    const \(name)=thisScene.getCameraTransforms();
                    if(\(name).eye.x!==0||\(name).center.z!==-1)throw Error('published seed');
                    \(name).eye.x=999;
                    if(thisScene.getCameraTransforms().eye.x!==0)throw Error('detached copy');
                    thisScene.setCameraTransforms({eye:\(expression),center:undefined});
                    thisScene.setCameraTransforms({zoom:0.5});
                    const actual=thisScene.getCameraTransforms();
                    if(actual.eye.x!==100||actual.center.z!==-1||actual.up.y!==1||actual.zoom!==0.5)
                        throw Error('partial readback');
                    return v;
                }
                """, target: .layer(layerID: 8, field: .visibility), valueType: .bool,
                effectNames: [], allowsStatefulLayerSideEffects: true, generation: 17, budget: .default)
            func run(_ valueOwner: SceneScriptValueOwner) throws -> SceneScriptValueEvaluation {
                try valueOwner.evaluate(input: .bool(true), frame: .init(timing: .init(
                    wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1.0/60, sceneTime: 1)),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 17,
                    interruptBudget: nil).get()
            }
            for call in ["getCameraTransforms()", "setCameraTransforms({zoom:1})"] {
                var rejected = false
                do {
                    _ = try SceneScriptValueOwner(domain: fixture.domain,
                        source: "thisScene.\(call);export function update(v){return v;}",
                        target: .layer(layerID:8,field:.visibility), valueType:.bool,
                        effectNames:[], allowsStatefulLayerSideEffects:true, generation:17, budget:.default)
                } catch { rejected = true }
                facts["global-phase-\(call)-\(renamed)"] = rejected
            }
            let first = try run(owner), checkpoint = owner.timerFrameSnapshot()
            let second = try run(owner)
            owner.restoreTimerFrame(checkpoint); owner.discardTimerFrame(checkpoint)
            let restored = try SceneScriptCameraCommandBridge.commands(owner: owner.handle).get()
            facts["partial-copy-phase-and-cursor-\(renamed)"] = first.cameraCommands.map(\.fields.rawValue) == [1,1,8]
                && first.cameraCommands[0].eye.x == 17 && first.cameraCommands[1].eye.x == 100
                && first.cameraCommands[2].zoom == 0.5 && second.cameraCommands.count == 2
                && restored == first.cameraCommands
            facts["no-published-mirror-leak-\(renamed)"] = try observe(fixture, id: 9,
                condition: "thisScene.getCameraTransforms().eye.x===0&&thisScene.getCameraTransforms().zoom===1")
            owner.discardLayerMutations()
            facts["discard-clears-camera-range-\(renamed)"] = mwx_scene_quickjs_owner_camera_command_count(owner.handle) == 0
            for (tag, value) in [("nonfinite", "{eye:new Vec3(NaN,0,0)}"),
                                 ("float-range", "{eye:new Vec3(1e100,0,0)}"),
                                 ("zoom-zero", "{zoom:0}"), ("wrong-type", "{eye:7}"),
                                 ("overflow", "{}") ] {
                let action = tag == "overflow"
                    ? "for(let i=0;i<65;i++){try{thisScene.setCameraTransforms({zoom:1});}catch(e){}}"
                    : "thisScene.setCameraTransforms(\(value));"
                let bad = try SceneScriptValueOwner(domain: fixture.domain,
                    source: "export function update(v){thisLayer.alpha=0.25;\(action)return v;}",
                    target: .layer(layerID: 8, field: .visibility), valueType: .bool,
                    effectNames: [], allowsStatefulLayerSideEffects: true, generation: 17, budget: .default)
                var rejected = false
                do { _ = try run(bad) } catch { rejected = true }
                let unchanged = try observe(fixture, id: 9,
                    condition: "thisScene.getLayerByID(8).alpha===1&&thisScene.getCameraTransforms().eye.x===0")
                facts["rejected-bundle-\(tag)-\(renamed)"] = rejected
                    && mwx_scene_quickjs_owner_camera_command_count(bad.handle) == 0 && unchanged
            }
        }
        return facts
    }

    static func staticCameraTransactions() throws -> [String: Bool] {
        let fixture = try Fixture(staticCameraScene(), key: "unusedCameraProperty")
        let a = SceneDynamicTarget.layer(layerID: 8, field: .origin)
        let b = SceneDynamicTarget.layer(layerID: 9, field: .alpha)
        func command(_ x: Double, _ epoch: UInt64, _ ordinal: UInt32 = 0,
                     fields: SceneScriptCameraCommand.Fields = .eye) -> SceneScriptCameraCommand {
            .init(fields: fields, eye: .init(x,0,0), center: .init(x,0,-1), up: .init(0,1,0),
                zoom: x, callbackEpoch: epoch, ordinal: ordinal)
        }
        func layer(_ id: Int, _ alpha: Double, owner: SceneDynamicTarget) -> SceneScriptLayerMutation {
            .init(kind: .upsert, isDynamic: false, fields: .alpha, layerID: id, orderIndex: -1,
                visible: true, alpha: alpha, origin: .zero, scale: .init(repeating: 1),
                angles: .zero, color: .init(repeating: 1), pointSize: 32, text: "", font: "",
                assetPath: nil, ownerTarget: owner)
        }
        func effect(_ target: SceneDynamicTarget, _ commands: [SceneScriptCameraCommand],
                    layers: [SceneScriptLayerMutation] = []) -> SceneScriptOwnerEffects {
            .init(ownerTarget: target, materialFunctionMutations: [], animationMutations: [],
                layerMutations: layers, mediaPlaybackCommands: [], cameraCommands: commands)
        }
        let first = effect(a, [command(10,10), command(20,20)])
        let peer = effect(b, [command(30,15), command(5,30,fields:.center), command(0.5,30,1,fields:.zoom)],
            layers: [layer(9,0.3,owner:b)])
        let forward = fixture.layers.preflightOwnerEffects([first,peer])
        let reverse = fixture.layers.preflightOwnerEffects([peer,first])
        var facts = ["ordered-partials-ignore-effect-array-order":
            forward.layerPlan.authoredLayerValues == reverse.layerPlan.authoredLayerValues
                && forward.layerPlan.authoredLayerValues[.camera(.eye)] == .vector3(20,0,0)
                && forward.layerPlan.authoredLayerValues[.camera(.center)] == .vector3(5,0,-1)
                && forward.layerPlan.authoredLayerValues[.camera(.zoom)] == .scalar(0.5)]
        let bad = effect(a, first.cameraCommands, layers: [layer(8,.nan,owner:a)])
        let isolated = fixture.layers.preflightOwnerEffects([bad,peer])
        facts["bad-layer-rejects-source-camera-only"] = isolated.rejectedOwners.contains { $0.ownerTarget == a }
            && isolated.layerPlan.authoredLayerValues[.camera(.eye)] == .vector3(30,0,0)
            && isolated.layerPlan.authoredLayerValues[.layer(layerID:9,field:.alpha)] == .scalar(0.3)
        fixture.layers.commit(forward.layerPlan)
        let fixed = fixture.layers.preflightOwnerEffectsToFixedPoint(
            [effect(a,[command(80,40)]),effect(b,[],layers:[layer(9,0.4,owner:b)])],
            rejectingExternally: { _ in [a] })
        fixture.layers.commit(fixed.admission.layerPlan)
        facts["external-rejection-retains-previous-current-without-replay"] = fixed.externallyRejectedOwners == [a]
            && fixture.layers.snapshot().authoredLayerValues[.camera(.eye)] == .vector3(20,0,0)
            && fixture.layers.preflightOwnerEffects([]).layerPlan.authoredLayerValues[.camera(.eye)] == .vector3(20,0,0)
        facts["camera-source-has-no-synthetic-layer"] = first.sourceLayerID == nil
            && first.layerMutations.isEmpty && fixture.descriptor.camera.default2DInputLayerID == nil
        var native = staticCameraScene(), general = native["general"] as! [String:Any]
        general["orthogonalprojection"] = NSNull(); native["general"] = general
        native["camera"] = ["eye":"1 2 6","center":"0 0 0","up":"0 1 0"]
        let nativeFixture = try Fixture(native,key:"unusedCameraProperty")
        let (snapshot,_) = try nativeFixture.frame()
        facts["native-no-api-keeps-authored-camera"] = snapshot[.camera(.eye)]?.value == .vector3(1,2,6)
            && snapshot[.camera(.center)]?.value == .vector3(0,0,0)
            && snapshot[.camera(.up)]?.value == .vector3(0,1,0)
        facts["native-published-getter-keeps-authored-camera"] = try observe(nativeFixture, id:9,
            condition: "thisScene.getCameraTransforms().eye.x===1&&thisScene.getCameraTransforms().eye.y===2&&thisScene.getCameraTransforms().eye.z===6")
        return facts
    }

    static func setterCanonicalSeed() throws -> [String: Bool] {
        var scene = setterScene("""
            export function init(v){thisScene.getLayerByID(7).origin=new Vec3(9,8,700);return v;}
            """)
        scene = changingFirst(scene) { $0["origin"] = "0.1 -0.2 500.3" }
        let fixture = try Fixture(scene, key: "lensScale")
        let canonical = SceneDynamicValue.vector3(0.1,-0.2,500.3)
        let (first, evaluation) = try fixture.frame()
        let dynamicSeed = fixture.layers.authoredLayerDefinitions.first { $0.target == originTarget }?.authoredValue
        let (next, _) = try fixture.frame()
        // Match the real launch-before-dynamic order with the real merger.
        // This is not a replacement harness for the complete LaunchFrameSchema.
        let unoverlaid = SceneDynamicSnapshotResolver().resolve(frameIndex: 100, generation: 0,
            index: SceneDynamicSnapshotResolver.prepare(definitions: fixture.definitions)).snapshot
        return [
            "raw-seed-keeps-canonical-double-precision": evaluation.failures.isEmpty
                && first[originTarget]?.value == canonical,
            "dynamic-alias-seed-is-distinct-parsed-float": dynamicSeed != nil && dynamicSeed != canonical
                && dynamicSeed == .vector3(Double(Float(0.1)),Double(Float(-0.2)),Double(Float(500.3))),
            "launch-definition-wins-and-remains-unique":
                fixture.definitions.filter { $0.target == originTarget }.count == 1
                && fixture.definitions.first { $0.target == originTarget }?.authoredValue == canonical
                && unoverlaid[originTarget]?.value == canonical,
            "current-alias-does-not-replace-authored-seed": next[originTarget]?.value == .vector3(9,8,700)
                && fixture.camera(next).cameraOrigin == SIMD3(9,8,700),
        ]
    }
}
