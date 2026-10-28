"""Execute the real QuickJS host through its Swift ABI, not source-string checks."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(.init(layers: [.init(
            id: 42, layerIndex: 0, name: "puppet", visible: true,
            originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil,
            alpha: 1, effects: []
        )]))
        let owner = try SceneScriptValueOwner(
            domain: domain,
            source: """
            let dragging = false, start, offset;
            export function cursorDown(e) {
                const root = thisLayer.getBoneTransform(0).translation();
                const distance = root.copy().subtract(input.cursorWorldPosition);
                if (distance.length() < 10) { start = root; offset = distance; dragging = true; }
            }
            export function cursorUp(e) { dragging = false; }
            export function update(v) {
                if (v.x === 5 && dragging) {
                    const delta = input.cursorWorldPosition.subtract(start);
                    const distance = delta.length();
                    const point = start.add(delta.divide(distance).multiply(Math.min(10,distance))).add(offset);
                    thisLayer.setBoneTransform(1, thisLayer.getBoneTransform(1).translation(point));
                }
                if (v.x === 1) {
                    thisLayer.setBoneTransform(0, Mat4.fromTranslation(new Vec3(20,0,0)));
                    thisLayer.setBoneTransform(1, Mat4.fromTranslation(new Vec3(31,0,0)));
                }
                if (v.x === 4) {
                    const delta = new Vec3(3,4,12);
                    const translated = thisLayer.getBoneTransform(1).translation(delta.copy());
                    return new Vec3(translated.translation().length(),
                        delta.normalize().length(), new Vec3().normalize().length());
                }
                if (v.x === 3) {
                    const m = Mat4.identity(); m.m[0] = 0;
                    thisLayer.setLocalBoneTransform(0, m);
                    thisLayer.setBoneTransform(1, Mat4.identity());
                }
                return new Vec3(thisLayer.getBoneTransform(1).translation().x,
                    thisLayer.getLocalBoneTransform(1).translation().x,
                    thisLayer.getBoneTransform(2).translation().x);
            }
            """,
            target: .layer(layerID: 42, field: .origin),
            effectNames: [], generation: 1, budget: .default)
        func matrix(_ x: Double) -> [Double] {
            [1,0,0,0, 0,1,0,0, 0,0,1,0, x,0,0,1]
        }
        try owner.configurePuppetBones(layerID: 42,
            localMatrices: matrix(2) + matrix(3) + matrix(5),
            names: ["root", "left", "right"], parents: [-1,0,0],
            layerToWorld: matrix(10))
        var pointerX = 14.0
        func frame() -> SceneScriptFrameInput {
            .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1/60, sceneTime: 0), surface: .init(
                canvasSize: .init(100,100), screenSize: .init(100,100),
                cursorWorldPosition: .init(pointerX,0,0), cursorScreenPosition: .zero,
                cursorLeftDown: true))
        }
        func run(_ mode: Double) -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
            owner.evaluate(input: .vector3(mode,0,0),
                frame: frame(),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)
        }
        func values(_ result: Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure>) throws -> [Double] {
            let evaluation = try result.get()
            if case let .vector3(x,y,z) = evaluation.value { return [x,y,z] }
            return []
        }
        func impulseChecks(_ boneName: String) throws -> [String: Any] {
            let source = """
                export function update(v) {
                    const bone='\(boneName)';
                    if(v.x===1) {
                        const local=thisLayer.getLocalBoneOrigin(bone).copy();
                        const world=thisLayer.getBoneTransform(bone).translation();
                        thisLayer.applyBonePhysicsImpulse(bone,new Vec3(-2,3,4));
                        if(thisLayer.getLocalBoneOrigin(bone).subtract(local).length()!==0 ||
                           thisLayer.getBoneTransform(bone).translation().subtract(world).length()!==0)
                            throw new Error('impulse changed published getter');
                        thisLayer.setLocalBoneOrigin(bone,new Vec3(8,0,0));
                        thisLayer.applyBonePhysicsImpulse(1,new Vec3(5,6,7),new Vec3(-0,0,0));
                        thisLayer.setLocalBoneTransform(bone,Mat4.fromTranslation(new Vec3(9,0,0)));
                    }
                    if(v.x===2) {
                        const invalid=[
                            ()=>thisLayer.applyBonePhysicsImpulse(1,new Vec3(NaN,0,0)),
                            ()=>thisLayer.applyBonePhysicsImpulse(1,new Vec3(0,Infinity,0)),
                            ()=>thisLayer.applyBonePhysicsImpulse(1,{x:1,y:2}),
                            ()=>thisLayer.applyBonePhysicsImpulse('missing',new Vec3(1,2,3)),
                            ()=>thisLayer.applyBonePhysicsImpulse(-1,new Vec3(1,2,3)),
                            ()=>thisLayer.applyBonePhysicsImpulse(1.5,new Vec3(1,2,3)),
                            ()=>thisLayer.applyBonePhysicsImpulse(3,new Vec3(1,2,3)),
                            ()=>thisLayer.applyBonePhysicsImpulse(),
                            ()=>thisLayer.applyBonePhysicsImpulse(1),
                            ()=>thisLayer.applyBonePhysicsImpulse(1,new Vec3(1,2,3),new Vec3(0),0),
                            ()=>thisLayer.applyBonePhysicsImpulse(1,new Vec3(1,2,3),new Vec3(0,0,1)),
                            ()=>thisLayer.applyBonePhysicsImpulse(1,new Vec3(1,2,3),new Vec3(NaN,0,0)),
                            ()=>thisLayer.applyBonePhysicsImpulse(1,new Vec3(1,2,3),0)
                        ];
                        let rejected=0;for(const call of invalid){try{call();}catch(e){rejected++;}}
                        return new Vec3(rejected,thisLayer.getLocalBoneOrigin(bone).x,0);
                    }
                    if(v.x===3) {
                        thisLayer.applyBonePhysicsImpulse(bone,new Vec3(1,2,3));
                        thisLayer.setLocalBoneOrigin(bone,new Vec3(99,0,0));
                        throw new Error('abort mixed commands');
                    }
                    if(v.x===4) {
                        for(let i=0;i<257;i++) {
                            if(i%2)thisLayer.setLocalBoneOrigin(bone,new Vec3(i,0,0));
                            else thisLayer.applyBonePhysicsImpulse(bone,new Vec3(i,0,0));
                        }
                    }
                    if(v.x===5)thisLayer.applyBonePhysicsImpulse(bone,new Vec3(1e300,-1e300,0));
                    return thisLayer.getLocalBoneOrigin(bone);
                }
                """
            func make() throws -> SceneScriptValueOwner {
                let candidate=try SceneScriptValueOwner(domain:domain,source:source,
                    target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
                try candidate.configurePuppetBones(layerID:42,
                    localMatrices:matrix(2)+matrix(3)+matrix(5),names:["trunk",boneName,"neighbor"],
                    parents:[-1,0,0],layerToWorld:matrix(10))
                return candidate
            }
            func evaluate(_ candidate:SceneScriptValueOwner,_ mode:Double) -> Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure> {
                candidate.evaluate(input:.vector3(mode,0,0),frame:frame(),scriptPropertiesJSON:"",
                    userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
            }
            let candidate=try make()
            let mixed=try evaluate(candidate,1).get()
            let commands:[[String:Any]]=mixed.puppetBoneMutations.map {
                switch $0.operation {
                case let .matrix(m): return ["kind":"matrix","values":[m[12],m[13],m[14]]]
                case let .impulse(v): return ["kind":"impulse","values":[v.x,v.y,v.z]]
                }
            }
            candidate.discardLayerMutations()
            let discardedCount=mwx_scene_quickjs_owner_puppet_bone_mutation_count(candidate.handle)
            let rolledBack=try values(evaluate(candidate,0));candidate.commitLayerMutations()
            let invalid=try evaluate(candidate,2).get();candidate.commitLayerMutations()
            let large=try evaluate(candidate,5).get();candidate.discardLayerMutations()
            let largeValue:[Double]
            if case let .impulse(v)?=large.puppetBoneMutations.first?.operation { largeValue=[v.x,v.y,v.z] }
            else { largeValue=[] }
            var failures:[String:Any]=[:]
            for mode in [3,4] {
                let failing=try make()
                if case let .failure(error)=evaluate(failing,Double(mode)) { failures["\(mode)"]=error.code }
                failing.discardLayerMutations()
                failures["\(mode)Writes"]=mwx_scene_quickjs_owner_puppet_bone_mutation_count(failing.handle)
            }
            return ["commands":commands,"bones":mixed.puppetBoneMutations.map(\.boneIndex),
                "ordinals":mixed.puppetBoneMutations.map(\.ordinal),
                "epochs":mixed.puppetBoneMutations.map(\.callbackEpoch),
                "rollback":rolledBack,"discardedCount":discardedCount,
                "invalid":try values(.success(invalid)),"invalidWrites":invalid.puppetBoneMutations.count,
                "large":largeValue,"failures":failures,
                "abiBytes":MemoryLayout<MWXSceneQuickJSPuppetBoneMutation>.stride]
        }
        func availabilityChecks(byName: Bool) throws -> [String: Any] {
            let blocked=byName ? "'blocked'" : "2"
            let candidate=try SceneScriptValueOwner(domain:domain,source:"""
                export function update(v) {
                    if(v.x===1) {
                        thisLayer.applyBonePhysicsImpulse('plain',new Vec3(1,0,0));
                        thisLayer.applyBonePhysicsImpulse(1,new Vec3(2,0,0));
                    }
                    if(v.x===2) {
                        thisLayer.setLocalBoneOrigin(0,new Vec3(99,0,0));
                        thisLayer.applyBonePhysicsImpulse(\(blocked),new Vec3(3,0,0));
                    }
                    return thisLayer.getLocalBoneOrigin(0);
                }
                """,target:.layer(layerID:42,field:.origin),effectNames:[],generation:1,budget:.default)
            let local=matrix(2)+matrix(3)+matrix(5)
            try candidate.configurePuppetBones(layerID:42,localMatrices:local,
                names:["plain","spring","blocked"],parents:[-1,0,0],impulseUnavailable:[0,0,7])
            var badCountRejected=false
            do { try candidate.configurePuppetBones(layerID:42,localMatrices:local,impulseUnavailable:[0,0]) }
            catch { badCountRejected=true }
            func evaluate(_ mode:Double) -> Result<SceneScriptValueEvaluation,SceneScriptScalarRuntimeFailure> {
                candidate.evaluate(input:.vector3(mode,0,0),frame:frame(),scriptPropertiesJSON:"",
                    userPropertiesJSON:"{}",expectedGeneration:1,interruptBudget:nil)
            }
            let allowed=try evaluate(1).get()
            candidate.commitLayerMutations()
            // Ordinary frame publication omits capability metadata.
            try candidate.configurePuppetBones(layerID:42,localMatrices:local,parents:[-1,0,0])
            let rejected=evaluate(2)
            var code="unexpected-success",message=""
            if case let .failure(failure)=rejected {
                code=failure.code
                if case let .exception(text)=failure { message=text }
            }
            candidate.discardLayerMutations()
            var disabled=false
            if case .failure(.disabled)=evaluate(0) { disabled=true }
            return ["allowedBones":allowed.puppetBoneMutations.map(\.boneIndex),
                "allowedPose":try values(.success(allowed)),"badCountRejected":badCountRejected,
                "failure":code,"message":message,"disabled":disabled,
                "publishedWrites":mwx_scene_quickjs_owner_puppet_bone_mutation_count(candidate.handle)]
        }
        let changed = run(1)
        let mutations = try changed.get().puppetBoneMutations
        owner.discardLayerMutations()
        let rolledBack = try values(run(0))
        owner.commitLayerMutations()
        let changedAgain = try values(run(1))
        owner.commitLayerMutations()
        let committed = try values(run(0))
        owner.commitLayerMutations()
        let vectorMethods = try values(run(4))
        owner.commitLayerMutations()
        try owner.configurePuppetBones(layerID: 42,
            localMatrices: matrix(2) + matrix(3) + matrix(5), names: [],
            parents: [-1,0,0], layerToWorld: matrix(10))
        func cursor(_ kind: SceneScriptCursorEventKind) throws {
            _ = try owner.dispatchCursor(.init(kind: kind, layerID: 42,
                worldPosition: .init(pointerX,0,0), localPosition: .zero),
                frame: frame(), scriptPropertiesJSON: "",
                userPropertiesJSON: "{}").get()
        }
        try cursor(.down)
        pointerX = 30
        let clamped = try values(run(5))
        owner.commitLayerMutations()
        try cursor(.up)
        pointerX = 60
        let released = try run(5).get()
        owner.commitLayerMutations()
        try cursor(.down) // Outside the authored radius must not capture.
        pointerX = 14
        let outside = try run(5).get()
        owner.commitLayerMutations()
        let singular = run(3)
        let rejected: Bool
        if case .failure = singular { rejected = true } else { rejected = false }
        owner.discardLayerMutations()
        let result: [String: Any] = [
            "impulse":try impulseChecks("left"),"renamedImpulse":try impulseChecks("leaf"),
            "unavailableName":try availabilityChecks(byName:true),"unavailableIndex":try availabilityChecks(byName:false),
            "clamped": clamped, "releasedWrites": released.puppetBoneMutations.count,
            "outsideWrites": outside.puppetBoneMutations.count,
            "vectorMethods": vectorMethods,
            "changed": try values(changed), "rollback": rolledBack,
            "retry": changedAgain, "committed": committed,
            "localWrites": mutations.map { mutation in
                guard case let .matrix(m)=mutation.operation else { fatalError("expected matrix command") }
                return m[12]
            }, "singularRejected": rejected
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    }
}
'''

class QuickJSPuppetBoneBehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-b9-host-")
        cls.addClassCleanup(cls.directory.cleanup)
        binary = compile_vector_harness(Path(cls.directory.name), HARNESS, "bone-host")
        run = subprocess.run([str(binary)], capture_output=True, text=True)
        if run.returncode:
            raise AssertionError(run.stderr[:5000])
        cls.result = json.loads(run.stdout.strip().splitlines()[-1])

    def test_world_setters_update_descendants_and_derive_local_journal(self):
        self.assertEqual(self.result['changed'], [31,11,25])
        self.assertEqual(self.result['localWrites'], [10,11])

    def test_owner_discard_restores_pose_and_commit_preserves_it(self):
        self.assertEqual(self.result['rollback'], [15,3,17])
        self.assertEqual(self.result['retry'], [31,11,25])
        self.assertEqual(self.result['committed'], [31,11,25])

    def test_matrix_translation_returns_complete_drag_vector(self):
        for actual, expected in zip(self.result['vectorMethods'], [13, 1, 0]):
            self.assertAlmostEqual(actual, expected)

    def test_same_owner_cursor_drag_clamps_and_release_or_outside_stops_writes(self):
        self.assertEqual(self.result['clamped'], [20,8,17])
        self.assertEqual(self.result['releasedWrites'], 0)
        self.assertEqual(self.result['outsideWrites'], 0)

    def test_singular_parent_rejects_world_write(self):
        self.assertTrue(self.result['singularRejected'])

    def test_impulse_and_matrix_share_order_without_immediate_impulse_pose(self):
        expected = [
            {"kind": "impulse", "values": [-2, 3, 4]},
            {"kind": "matrix", "values": [8, 0, 0]},
            {"kind": "impulse", "values": [5, 6, 7]},
            {"kind": "matrix", "values": [9, 0, 0]},
        ]
        for key in ("impulse", "renamedImpulse"):
            facts = self.result[key]
            self.assertEqual(facts["commands"], expected)
            self.assertEqual(facts["bones"], [1, 1, 1, 1])
            self.assertEqual(facts["ordinals"], [0, 1, 2, 3])
            self.assertEqual(len(set(facts["epochs"])), 1)
            self.assertGreater(facts["epochs"][0], 0)
            self.assertEqual(facts["rollback"], [3, 0, 0])
            self.assertEqual(facts["discardedCount"], 0)
            self.assertEqual(facts["abiBytes"], 152)

    def test_bad_impulses_and_nonzero_angular_are_rejected_without_commands(self):
        for key in ("impulse", "renamedImpulse"):
            self.assertEqual(self.result[key]["invalid"], [13, 3, 0])
            self.assertEqual(self.result[key]["invalidWrites"], 0)
            self.assertEqual(self.result[key]["large"], [1e300, -1e300, 0])

    def test_throw_and_shared_matrix_impulse_budget_discard_the_whole_journal(self):
        for key in ("impulse", "renamedImpulse"):
            self.assertEqual(self.result[key]["failures"],
                             {"3": "exception", "3Writes": 0,
                              "4": "exception", "4Writes": 0})

    def test_unsupported_physics_fails_atomically_and_nil_refresh_preserves_capability(self):
        for key in ("unavailableName","unavailableIndex"):
            facts=self.result[key]
            self.assertEqual(facts["allowedBones"],[0,1])
            self.assertEqual(facts["allowedPose"],[2,0,0])
            self.assertTrue(facts["badCountRejected"])
            self.assertEqual(facts["failure"],"exception")
            self.assertIn("bone physics impulse is unsupported",facts["message"])
            self.assertTrue(facts["disabled"])
            self.assertEqual(facts["publishedWrites"],0)

if __name__ == '__main__':
    unittest.main()
