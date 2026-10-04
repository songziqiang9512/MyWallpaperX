"""Effect-owned cursor writes publish through the existing Boolean transaction."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static func target(_ index: Int = 0) -> SceneDynamicTarget {
        .effectVisibility(layerID: 10, effectIndex: index)
    }
    static func frame(_ time: Double = 1) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: time), simulationFrameTime: 0.016, sceneTime: time))
    }
    static func make(_ sources: [String], unboundEffects: Int = 0, foreign: Bool = false) throws -> SceneScriptQuickJSProgramCandidate {
        let effects: [SceneRenderDescriptor.EffectDescriptor] = (0..<(sources.count + unboundEffects)).map {
            .init(name: "effect\($0)", effectID: 100 + $0, visible: false)
        }
        var layers: [SceneRenderDescriptor.Layer] = [.init(id: 10, layerIndex: 0, name: "card", visible: true,
            originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: false, alpha: 1,
            effects: effects, contentKind: "image", sizeWH: [100,100])]
        if foreign {
            layers.append(.init(id: 20, layerIndex: 1, name: "peer", visible: true,
                originXYZ: [1,2,3], scaleXYZ: [1,1,1], scaleHasScript: false, alpha: 1,
                effects: [.init(name: "effect0", effectID: 200, visible: false)],
                contentKind: "image", sizeWH: [100,100]))
        }
        let d = SceneRenderDescriptor(layers: layers)
        let bindings: [SceneScriptBindingIR] = sources.enumerated().map { index, source in
            .init(source: source, owner: .init(kind: .effect, objectIndex: 0, objectID: 10,
                effectIndex: index, effectID: 100 + index, passIndex: nil, passID: nil),
                targetPath: [.key("objects"),.index(0),.key("effects"),.index(index),.key("visible")],
                properties: [:], authoredValue: .bool(false), valueType: .boolean, wrapperKeys: ["script","value"])
        }
        return try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor: d, runtimeDescriptor: d,
            scriptBindings: bindings, vectorProjection: SceneScriptVectorProgram.project(descriptor: d,scriptBindings: bindings),
            userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 1)
    }
    static func sample(_ down: Bool, hit: Bool = true) -> SceneScriptCursorFrameSample {
        .init(hits: hit ? [10: .init(layerID: 10, worldPosition: .init(20,30,0), localPosition: .init(20,30,0))] : [:],
              pointerPosition: .init(0.2,0.3), primaryButtonIsDown: down)
    }
    static func dispatch(_ c: SceneScriptQuickJSProgramCandidate, _ samples: [SceneScriptCursorFrameSample], time: Double = 1) -> SceneScriptCursorFrameResult {
        c.cursorProgram.dispatch(batch: .init(samples: samples, overflowed: false), frame: frame(time),userPropertiesJSON: "{}")
    }
    static func values(_ c: SceneScriptQuickJSProgramCandidate, time: Double = 1) -> SceneScriptVectorFrameResult {
        c.vectorProgram.evaluate(inputs: Dictionary(uniqueKeysWithValues: c.vectorProgram.definitions.map { ($0.target,.bool(false)) }),
            effectivePropertyValues: [:],frame: frame(time))
    }
    static func finish(_ c: SceneScriptQuickJSProgramCandidate, commit: Bool = true, rejected: Set<SceneDynamicTarget> = []) {
        c.cursorProgram.finalizeLayerMutations(committing: commit, rejectedOwnerTargets: rejected)
        c.vectorProgram.finalizeLayerMutations(committing: commit, rejectedOwnerTargets: rejected)
    }
    static func bool(_ r: SceneScriptVectorFrameResult, _ index: Int = 0) -> Int {
        guard case let .bool(v)? = r.values[target(index)] else { return -1 };return v ? 1 : 0
    }
    static let hold = """
      export function init(v) { thisObject.visible=false; return v; }
      export function cursorDown(e) { thisObject.visible=true; }
      export function cursorUp(e) { thisObject.visible=false; }
      """
    static let toggle = "export function cursorClick(e) { thisObject.visible=!thisObject.visible; }"
    static func main() throws {
        var out: [String:Any] = [:]
        let c = try make([hold]);out["owners"] = c.cursorProgram.ownerCount
        out["borrowed"] = c.cursorProgram.bindings.allSatisfy { !$0.ownsOwner }
        _ = dispatch(c,[sample(false)]);out["initial"] = bool(values(c));finish(c)
        out["idleBefore"] = values(c).values.isEmpty;finish(c)
        _ = dispatch(c,[sample(true)]);out["down"] = bool(values(c));finish(c)
        out["idleHeld"] = values(c).values.isEmpty;finish(c)
        _ = dispatch(c,[sample(false)]);out["up"] = bool(values(c));finish(c)
        out["idleAfter"] = values(c).values.isEmpty;finish(c)

        let t = try make([toggle,toggle]);let click = [sample(false),sample(true),sample(false)]
        _ = dispatch(t,click);let first=values(t);out["first"]=[bool(first),bool(first,1)]
        finish(t,rejected:[target()])
        _ = dispatch(t,[sample(false)]);let retry=values(t);out["retry"]=[bool(retry),bool(retry,1)]
        finish(t);out["confirmedQuiet"] = values(t).values.isEmpty;finish(t)
        _ = dispatch(t,click);let second=values(t);out["second"]=[bool(second),bool(second,1)];finish(t)

        let whole = try make([toggle]);let edges=whole.cursorProgram.edgeStateSnapshot()
        _ = dispatch(whole,click);out["discardCandidate"]=bool(values(whole));finish(whole,commit:false)
        whole.cursorProgram.restoreEdgeState(edges)
        _ = dispatch(whole,click);out["discardRetry"]=bool(values(whole));finish(whole)

        let bad = try make(["export function cursorDown(e){thisObject.visible=true;thisLayer.origin=new Vec3(5,6,7);}",hold])
        // Commit initial property delivery before testing callback rollback.
        out["badInitial"] = bool(values(bad));finish(bad)
        let rejected=dispatch(bad,[sample(false),sample(true)]);out["cohortFailure"]=rejected.failures[target()]?.code ?? "none"
        let peer=values(bad);out["badValueAbsent"]=peer.values[target()]==nil;out["peerVisible"]=bool(peer,1)
        finish(bad,rejected:Set(rejected.failures.keys))

        let failedUpdate = try make([hold + "\nexport function update(v){if(engine.runtime===1)return 'bad';return thisObject.visible;}"])
        _ = dispatch(failedUpdate,[sample(false),sample(true)]);let failed=values(failedUpdate)
        out["updateFailure"]=failed.failures[target()]?.code ?? "none";finish(failedUpdate,rejected:[target()])
        _ = dispatch(failedUpdate,[sample(true)],time:2);out["updateRetry"]=bool(values(failedUpdate,time:2));finish(failedUpdate)

        var aliases: [String:Bool] = [:]
        var details: [String:Any] = [:]
        for (name, body, expected) in [
            ("directObject", "thisObject.visible=true;return true;", 1),
            ("effectIndex", "thisLayer.getEffect(0).visible=true;return true;", 1),
            ("effectName", "thisLayer.getEffect('effect0').visible=true;return true;", 1),
            ("sceneSameLayer", "thisScene.getLayer('card').getEffect(0).visible=true;return true;", 1),
            ("objectThenHandle", "thisObject.visible=true;if(!thisLayer.getEffect(0).visible)throw Error('handle missed staged true');thisLayer.getEffect('effect0').visible=false;return thisObject.visible;", 0),
            ("handleThenObject", "thisLayer.getEffect(0).visible=true;if(!thisObject.visible)throw Error('object missed staged true');thisObject.visible=false;return thisLayer.getEffect('effect0').visible;", 0),
        ] {
            let candidate = try make(["export function update(v){" + body + "}"])
            let result = values(candidate)
            aliases[name] = bool(result) == expected && result.failures.isEmpty
                && result.layerMutations.isEmpty && result.ownerEffects.isEmpty
            details[name] = ["value": bool(result), "failure": result.failures[target()]?.code ?? "none",
                             "layerMutations": result.layerMutations.count]
            finish(candidate, rejected: Set(result.failures.keys))
        }

        let aliasToggle = try make(["export function cursorClick(e){const f=thisLayer.getEffect('effect0');f.visible=!f.visible;}"])
        let seeded = values(aliasToggle);finish(aliasToggle)
        let aliasEdges = aliasToggle.cursorProgram.edgeStateSnapshot()
        let firstDispatch = dispatch(aliasToggle,click)
        let aliasFirst = values(aliasToggle)
        finish(aliasToggle,commit:false);aliasToggle.cursorProgram.restoreEdgeState(aliasEdges)
        let retryDispatch = dispatch(aliasToggle,click)
        let aliasRetry = values(aliasToggle);finish(aliasToggle)
        let aliasIdle = values(aliasToggle);finish(aliasToggle)
        let nextDispatch = dispatch(aliasToggle,click)
        let aliasNext = values(aliasToggle);finish(aliasToggle)
        aliases["eventRollbackRetryAndIdle"] = bool(seeded) == 0
            && firstDispatch.failures.isEmpty && retryDispatch.failures.isEmpty && nextDispatch.failures.isEmpty
            && bool(aliasFirst) == 1 && bool(aliasRetry) == 1 && bool(aliasNext) == 0
            && aliasFirst.layerMutations.isEmpty && aliasRetry.layerMutations.isEmpty
            && aliasIdle.values.isEmpty && aliasIdle.failures.isEmpty
        details["eventRollbackRetryAndIdle"] = ["values": [bool(seeded),bool(aliasFirst),bool(aliasRetry),bool(aliasNext)],
            "firstFailure": firstDispatch.failures[target()]?.code ?? "none",
            "retryFailure": retryDispatch.failures[target()]?.code ?? "none", "idle": aliasIdle.values.isEmpty]

        let aliasBadReturn = try make(["export function update(v){const f=thisLayer.getEffect(0);if(engine.runtime===1){f.visible=true;return 'bad';}return f.visible;}"])
        let aliasFailed = values(aliasBadReturn);finish(aliasBadReturn,rejected:[target()])
        let aliasRestored = values(aliasBadReturn,time:2);finish(aliasBadReturn)
        aliases["failedUpdateRestoresAliasGetter"] = aliasFailed.failures[target()]?.code == "bad-return"
            && bool(aliasRestored) == 0 && aliasRestored.failures.isEmpty
        details["failedUpdateRestoresAliasGetter"] = ["failure": aliasFailed.failures[target()]?.code ?? "none",
                                                    "restored": bool(aliasRestored)]

        for (name, body, foreign) in [
            ("crossEffectRejected", "thisLayer.getEffect(1).visible=true;return true;", false),
            ("foreignEffectRejected", "thisScene.getLayer('peer').getEffect(0).visible=true;return true;", true),
            ("foreignOriginRejected", "thisLayer.getEffect(0).visible=true;thisScene.getLayer('peer').origin=new Vec3(5,6,7);return true;", true),
        ] {
            let candidate = try make(["export function update(v){" + body + "}"], unboundEffects: 1, foreign: foreign)
            let result = values(candidate)
            aliases[name] = result.failures[target()]?.code == "invalid-argument"
                && result.values[target()] == nil && result.layerMutations.isEmpty && result.ownerEffects.isEmpty
            details[name] = ["failure": result.failures[target()]?.code ?? "none", "value": bool(result),
                             "layerMutations": result.layerMutations.count]
            finish(candidate,rejected:Set(result.failures.keys))
        }
        out["aliases"] = aliases;out["aliasDetails"] = details
        print(String(decoding:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''

class SceneEffectCursorVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-effect-cursor-")
        binary = compile_vector_harness(Path(cls.temp.name), HARNESS, "effect-cursor")
        result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        cls.value = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_hold_publishes_and_idle_owner_stays_quiet(self):
        v=self.value
        self.assertEqual(v["owners"],1);self.assertTrue(v["borrowed"])
        self.assertEqual([v["initial"],v["down"],v["up"]],[0,1,0])
        self.assertTrue(v["idleBefore"] and v["idleHeld"] and v["idleAfter"])

    def test_rejected_owner_retries_without_retoggling_peer(self):
        self.assertEqual(self.value["first"],[1,1])
        self.assertEqual(self.value["retry"],[1,-1])
        self.assertTrue(self.value["confirmedQuiet"])
        self.assertEqual(self.value["second"],[0,0])

    def test_whole_frame_discard_restores_visible_getter(self):
        self.assertEqual(self.value["discardCandidate"],1)
        self.assertEqual(self.value["discardRetry"],1)

    def test_cross_cohort_write_is_rejected_and_peer_publishes(self):
        self.assertEqual(self.value["badInitial"],0)
        self.assertEqual(self.value["cohortFailure"],"invalid-argument")
        self.assertTrue(self.value["badValueAbsent"])
        self.assertEqual(self.value["peerVisible"],1)

    def test_late_update_failure_retries_staged_event(self):
        self.assertEqual(self.value["updateFailure"],"bad-return")
        self.assertEqual(self.value["updateRetry"],1)

    def test_same_effect_handles_share_visibility_transaction_and_keep_cohort_rejection(self):
        expected = {"directObject", "effectIndex", "effectName", "sceneSameLayer", "objectThenHandle", "handleThenObject",
                    "eventRollbackRetryAndIdle", "failedUpdateRestoresAliasGetter", "crossEffectRejected",
                    "foreignEffectRejected", "foreignOriginRejected"}
        self.assertEqual(set(self.value["aliases"]), expected)
        for name, passed in self.value["aliases"].items():
            with self.subTest(input=name):
                self.assertTrue(passed, self.value["aliasDetails"][name])
