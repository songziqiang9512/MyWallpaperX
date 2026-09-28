"""Cross-layer effect writes use the production cursor and layer transaction."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static let target = SceneDynamicTarget.layer(layerID: 1, field: .origin)
    static let effect = SceneDynamicTarget.effectVisibility(layerID: 2, effectIndex: 0)
    static let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 0.016, sceneTime: 1))
    static let descriptor = SceneRenderDescriptor(layers: [
        .init(id: 1, layerIndex: 0, name: "controller", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: false, alpha: 1, effects: []),
        .init(id: 2, layerIndex: 1, name: "card", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: false, alpha: 1,
              effects: [.init(name: "beam", visible: false), .init(name: "beam", visible: true)], contentKind: "text", text: "card", textStyle: .init(fontPath: "fonts/original.ttf", colorRGB: nil, pointSize: 20))
    ])
    static func make(_ source: String, destroyOwner: Bool = false) throws -> (SceneScriptQuickJSDomain, SceneScriptCursorProgram) {
        let d = try SceneScriptQuickJSDomain()
        try d.configureLayerCatalog(descriptor)
        let o = try SceneScriptValueOwner(domain: d, source: source, target: destroyOwner ? .layer(layerID: 2, field: .visibility) : target, valueType: destroyOwner ? .bool : .vector3, effectNames: [], allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        let b = SceneScriptCursorBinding(layerID: destroyOwner ? 2 : 1, authoredOrdinal: 0, owner: o, events: o.exportedCursorEvents, ownsOwner: true, scriptProperties: [:], ownerSeedValue: destroyOwner ? .bool(true) : .vector3(0,0,0))
        return (d, .init(bindings: [b], generation: 1))
    }
    static func sample(_ down: Bool, layerID: Int = 1) -> SceneScriptCursorFrameSample {
        .init(hits: [layerID: .init(layerID: layerID, worldPosition: .zero, localPosition: .zero)], pointerPosition: .zero, primaryButtonIsDown: down)
    }
    static func click(_ p: SceneScriptCursorProgram, layerID: Int = 1) -> SceneScriptCursorFrameResult {
        p.dispatch(batch: .init(samples: [sample(false, layerID: layerID), sample(true, layerID: layerID), sample(false, layerID: layerID)], overflowed: false), frame: frame, userPropertiesJSON: "{}")
    }
    static func main() throws {
        var out: [String: Any] = [:]
        let source = """
        let retained;
        const firstFont=engine.registerAsset("fonts/first.ttf");
        const secondFont=engine.registerAsset("fonts/second.ttf");
        export function cursorDown(e) {
            const layer=thisScene.getLayer('card');
            if(layer.getEffectCount()!==2) throw new Error('count');
            retained=layer.getEffect('beam');
            if(retained.name!=='beam') throw new Error('name');
            retained.visible=true;
            layer.font=firstFont;
            layer.font=secondFont;
            shared.effect=retained;
            if(!layer.getEffect(0).visible || !layer.getEffect(1).visible) throw new Error('read own write');
        }
        export function cursorClick(e) {
            if(!retained.visible) throw new Error('earlier callback baseline lost');
            thisScene.getLayer('card').getEffect(1).visible=false;
            thisLayer.origin=new Vec3(5,0,0);
        }
        """
        let (domain, program) = try make(source)
        let result = click(program)
        out["failures"] = result.failures.count
        let mutations = SceneScriptLayerMutation.coalescing(result.layerMutations)
        out["effects"] = Dictionary(uniqueKeysWithValues: (mutations.first { $0.layerID == 2 }?.effectVisibilities ?? [:]).map { (String($0.key), $0.value ? 1 : 0) })
        out["font"] = mutations.first { $0.layerID == 2 }?.font ?? ""
        out["origin"] = mutations.first { $0.layerID == 1 }?.origin.x ?? -1
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [1,2])
        let plan = runtime.preflightOwnerEffects(result.ownerEffects)
        out["rejected"] = plan.rejectedOwners.count
        out["beforeCommitEmpty"] = runtime.snapshot().authoredLayerValues[effect] == nil
        runtime.commit(plan.layerPlan)
        program.finalizeLayerMutations(committing: true)
        out["published"] = runtime.snapshot().authoredLayerValues[effect] == .bool(true)
        let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 2,
            definitions: runtime.authoredLayerDefinitions, sceneScriptValues: runtime.snapshot().authoredLayerValues).snapshot
        try domain.publishLayerSnapshot(snapshot, descriptor: descriptor)
        let reader = try SceneScriptValueOwner(domain: domain, source: "export function update(v){return new Vec3(thisScene.getLayer('card').getEffect(0).visible?1:0,thisScene.getLayer('card').getEffect(1).visible?1:0,0);}", target: target, effectNames: [], allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        if case let .success(value) = reader.evaluate(input: .vector3(0,0,0), frame: frame, scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil) {
            out["nextFrame"] = value.value == .vector3(1,0,0)
        } else { out["nextFrame"] = false }
        let foreignReader = try SceneScriptValueOwner(domain: domain, source: "export function update(v){shared.effect.visible=false;return v;}", target: target, effectNames: [], allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        if case .failure = foreignReader.evaluate(input: .vector3(0,0,0), frame: frame, scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil) {
            out["foreignOwnerRejected"] = true
        } else { out["foreignOwnerRejected"] = false }
        for (key, operation) in [("range", "getEffect(999).visible=true"), ("type", "getEffect(0).visible=3")] {
            let (_, p) = try make("export function cursorClick(e){thisLayer.origin=new Vec3(9,0,0);thisScene.getLayer('card').getEffect(0).visible=true;thisScene.getLayer('card')."+operation+";}")
            let failure = click(p)
            out[key+"Failed"] = !failure.failures.isEmpty
            out[key+"RolledBack"] = failure.layerMutations.isEmpty
            p.finalizeLayerMutations(committing: false)
        }
        let (_, destroyProgram) = try make("export function cursorClick(e){const l=thisScene.getLayer('card'); l.getEffect(0).visible=true; thisScene.destroyLayer(l);}", destroyOwner: true)
        let destroyed = click(destroyProgram, layerID: 2)
        out["destroyDetails"] = String(describing: destroyed.failures) + String(describing: destroyed.layerMutations)
        out["destroyAfterWrite"] = destroyed.failures.isEmpty && destroyed.layerMutations.contains { $0.layerID == 2 && $0.kind == .destroy }
        destroyProgram.finalizeLayerMutations(committing: false)
        let (staleDomain, staleProgram) = try make("let f; export function cursorClick(e){if(f){f.visible=true;}else{f=thisScene.getLayer('card').getEffect(0);}}")
        let retained = click(staleProgram)
        out["retained"] = retained.failures.isEmpty
        staleProgram.finalizeLayerMutations(committing: true)
        try staleDomain.publishLayerSnapshot(.empty(frameIndex: 3), descriptor: descriptor, destroyedAuthoredLayerIDs: [2])
        let stale = click(staleProgram)
        out["staleRejected"] = !stale.failures.isEmpty && stale.layerMutations.isEmpty
        staleProgram.finalizeLayerMutations(committing: false)
        // Rejected host transaction must leave persistent values untouched.
        let (_, rejectedProgram) = try make(source)
        let rejectedResult = click(rejectedProgram)
        let uncommitted = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [1,2])
        _ = uncommitted.preflightOwnerEffects(rejectedResult.ownerEffects)
        rejectedProgram.finalizeLayerMutations(committing: false)
        out["discarded"] = uncommitted.snapshot().authoredLayerValues.isEmpty
        print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''

class CrossLayerEffectVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix='mwx-cross-effect-test-') as tmp:
            binary = compile_vector_harness(Path(tmp), HARNESS, 'cross-effects')
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            cls.result = json.loads(result.stdout.strip().splitlines()[-1])

    def test_lookup_and_callback_coalescing(self):
        self.assertEqual(self.result['failures'], 0)
        self.assertEqual(self.result['effects'], {'0': 1, '1': 0})
        self.assertEqual(self.result['origin'], 5)
        self.assertEqual(self.result['font'], 'fonts/second.ttf')

    def test_typed_publication_and_next_frame(self):
        self.assertEqual(self.result['rejected'], 0)
        self.assertTrue(self.result['beforeCommitEmpty'])
        self.assertTrue(self.result['published'])
        self.assertTrue(self.result['nextFrame'])

    def test_invalid_operations_roll_back_whole_callback(self):
        for kind in ['range', 'type']:
            self.assertTrue(self.result[kind+'Failed'])
            self.assertTrue(self.result[kind+'RolledBack'])
        self.assertTrue(self.result['discarded'])
        self.assertTrue(self.result['destroyAfterWrite'], self.result['destroyDetails'])
        self.assertTrue(self.result['foreignOwnerRejected'])
        self.assertTrue(self.result['retained'])
        self.assertTrue(self.result['staleRejected'])
