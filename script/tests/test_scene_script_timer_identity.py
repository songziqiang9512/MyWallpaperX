"""Timer cancellation capabilities retain identity across transactional retry."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import C_SOURCES, VM, QUICKJS, compile_vector_harness


HARNESS = r'''
@main enum Harness {
    static func make(_ source: String) throws -> SceneScriptVectorOwner {
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(.init(layers: [.init(id: 1, layerIndex: 0,
            name: "timer", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1],
            scaleHasScript: nil, alpha: 1, effects: [])]))
        return try .init(domain: domain, source: source,
            target: .layer(layerID: 1, field: .origin), effectNames: [],
            allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
    }
    static func evaluate(_ owner: SceneScriptVectorOwner, _ time: Double) -> Double {
        let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970:0),
            simulationFrameTime: 0.1, sceneTime: time))
        let result = owner.evaluate(input: .vector3(0,0,0), frame: frame,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil)
        guard case let .success(value) = result,
              case let .vector3(x,_,_) = value.value else { return -999 }
        return x
    }
    static func main() throws {
        var out: [String: Any] = [:]
        // The JS heap keeps the first cancellation closure after init is
        // rejected. It must not cancel the new timer created by the retry.
        for wholeFrame in [false, true] {
            for repeating in [false, true] {
                let method = repeating ? "setInterval" : "setTimeout"
                let owner = try make("""
                    let attempts=0, stale, fired=0;
                    export function init(v) {
                        const cancel=engine.\(method)(()=>{fired++;},10);
                        if(++attempts===1){stale=cancel;return {};}
                        stale(); return v;
                    }
                    export function update(v){return new Vec3(fired,0,0);}
                    """)
                let before = owner.timerFrameSnapshot()
                let failed = evaluate(owner, 0)
                owner.discardLayerMutations()
                if wholeFrame { owner.restoreTimerFrame(before) }
                owner.discardTimerFrame(before)
                _ = evaluate(owner, 1);owner.commitLayerMutations()
                let live = mwx_scene_quickjs_owner_active_timer_count(owner.handle)
                let first = evaluate(owner, 2);owner.commitLayerMutations()
                let next = evaluate(owner, 3);owner.commitLayerMutations()
                out["init-\(wholeFrame)-\(repeating)"] = [failed,Double(live),first,next]
            }
        }
        // A committed owner's frame can also mint an escaping cancellation
        // closure. Two nested snapshots must never rewind issuance identity.
        let owner = try make("""
            let updates=0, stale=[], fired=0;
            export function update(v){
                updates++;
                if(updates<=3){
                    const cancel=engine.setTimeout(()=>{fired++;},1000);
                    if(updates<=2)stale.push(cancel);else stale.forEach(f=>f());
                }
                return new Vec3(fired,0,0);
            }
            """)
        let initial = owner.timerFrameSnapshot()
        _ = evaluate(owner,0);owner.commitLayerMutations()
        let nested = owner.timerFrameSnapshot()
        _ = evaluate(owner,0.1);owner.discardLayerMutations()
        owner.restoreTimerFrame(nested);owner.discardTimerFrame(nested)
        owner.restoreTimerFrame(initial);owner.discardTimerFrame(initial)
        _ = evaluate(owner,0.2);owner.commitLayerMutations()
        out["nestedLive"] = mwx_scene_quickjs_owner_active_timer_count(owner.handle)
        var fired = 0.0
        for n in 1...12 {fired=evaluate(owner,Double(n));owner.commitLayerMutations()}
        out["nestedFired"] = fired

        // Restoring a timer preserves its original capability: cancellation
        // of an already committed timer must still work after frame rollback.
        let kept = try make("""
            let cancel, updates=0, fired=0;
            export function init(v){cancel=engine.setInterval(()=>{fired++;},10000);return v;}
            export function update(v){if(++updates>=2)cancel();return new Vec3(fired,0,0);}
            """)
        _ = evaluate(kept,0);kept.commitLayerMutations()
        let checkpoint = kept.timerFrameSnapshot()
        _ = evaluate(kept,1);kept.discardLayerMutations()
        out["canceledBeforeRestore"] = mwx_scene_quickjs_owner_active_timer_count(kept.handle)
        kept.restoreTimerFrame(checkpoint);kept.discardTimerFrame(checkpoint)
        out["restoredCommitted"] = mwx_scene_quickjs_owner_active_timer_count(kept.handle)
        _ = evaluate(kept,2);kept.commitLayerMutations()
        out["canceledAfterRestore"] = mwx_scene_quickjs_owner_active_timer_count(kept.handle)

        // A current cancellation closure remains effective and idempotent.
        let current = try make("""
            let fired=0;
            export function init(v){const cancel=engine.setTimeout(()=>{fired++;},1);cancel();cancel();return v;}
            export function update(v){return new Vec3(fired,0,0);}
            """)
        _ = evaluate(current,0);current.commitLayerMutations()
        out["currentCanceled"] = evaluate(current,1);current.commitLayerMutations()
        out["currentLive"] = mwx_scene_quickjs_owner_active_timer_count(current.handle)
        print(String(decoding: try JSONSerialization.data(withJSONObject:out, options:[.sortedKeys]),as:UTF8.self))
    }
}
'''


class SceneScriptTimerIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="scene-timer-identity-")
        binary = compile_vector_harness(Path(cls.temporary.name), HARNESS, "timer-identity")
        result = subprocess.run([str(binary)], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.value = json.loads(result.stdout.strip().splitlines()[-1])

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_rejected_init_timeout_capability_does_not_alias_retry(self):
        self.assertEqual(self.value["init-false-false"], [-999,1,1,1])

    def test_rejected_init_interval_capability_does_not_alias_retry(self):
        self.assertEqual(self.value["init-false-true"], [-999,1,1,2])

    def test_whole_frame_restore_cannot_reuse_init_timer_identity(self):
        self.assertEqual(self.value["init-true-false"], [-999,1,1,1])
        self.assertEqual(self.value["init-true-true"], [-999,1,1,2])

    def test_nested_restore_cannot_reuse_escaped_timer_identity(self):
        self.assertEqual(self.value["nestedLive"], 1)
        self.assertEqual(self.value["nestedFired"], 1)

    def test_committed_timer_preserves_its_cancellation_capability(self):
        self.assertEqual([self.value[k] for k in (
            "canceledBeforeRestore", "restoredCommitted", "canceledAfterRestore")], [0,1,0])

    def test_current_cancellation_remains_effective_and_idempotent(self):
        self.assertEqual(self.value["currentCanceled"], 0)
        self.assertEqual(self.value["currentLive"], 0)


class SceneScriptTimerIdentityExhaustionTests(unittest.TestCase):
    def test_last_exact_identity_cancels_and_further_issuance_is_rejected(self):
        # Seed a lifetime counter near exhaustion; exercising 2^53 callbacks
        # would be impractical. Assertions concern author-visible behavior.
        source = r'''
        #include "SceneQuickJSInternal.h"
        #include <string.h>
        #include <stdio.h>
        int main(void) {
            char diagnostic[512]={0};
            MWXSceneQuickJSDomain *d=mwx_scene_quickjs_domain_create(
                8*1024*1024,512*1024,100000,diagnostic,sizeof(diagnostic));
            if(!d)return 2;
            const char *source="export function update(v){"
                "if(engine.runtime>1){let rejected=false;try{engine.setTimeout(()=>{},10);}catch(e){rejected=e instanceof RangeError;}return new Vec3(rejected?1:0,0,0);}"
                "const cancel=engine.setTimeout(()=>{},10);"
                "let rejected=false;try{engine.setTimeout(()=>{},10);}catch(e){rejected=e instanceof RangeError;}"
                "cancel();return new Vec3(rejected?1:0,0,0);}";
            MWXSceneQuickJSOwner *o=mwx_scene_quickjs_owner_create(
                d,source,strlen(source),1,diagnostic,sizeof(diagnostic));
            if(!o)return 3;
            o->next_timer_identity=UINT64_C(9007199254740990);
            MWXSceneQuickJSTimerFrameSnapshot *before=mwx_scene_quickjs_owner_timer_snapshot(o);
            const double input[3]={0};double output[3]={0};
            MWXSceneQuickJSFrameInput f={.runtime=1,.frame_time=.016};
            MWXSceneQuickJSResult result=mwx_scene_quickjs_owner_update_vec3(
                o,1,input,&f,"",0,"{}",2,output,diagnostic,sizeof(diagnostic));
            int failed=result!=MWX_SCENE_QUICKJS_OK || output[0]!=1 ||
                mwx_scene_quickjs_owner_active_timer_count(o)!=0;
            if(failed)fprintf(stderr,"result=%d rejected=%.0f active=%u %s\n",
                result,output[0],mwx_scene_quickjs_owner_active_timer_count(o),diagnostic);
            mwx_scene_quickjs_owner_timer_restore(o,before);
            mwx_scene_quickjs_owner_timer_snapshot_destroy(before,o);
            f.runtime=2;output[0]=0;
            result=mwx_scene_quickjs_owner_update_vec3(o,1,input,&f,"",0,"{}",2,output,diagnostic,sizeof(diagnostic));
            failed |= result!=MWX_SCENE_QUICKJS_OK || output[0]!=1 ||
                mwx_scene_quickjs_owner_active_timer_count(o)!=0;
            mwx_scene_quickjs_owner_destroy(o);mwx_scene_quickjs_domain_destroy(d);
            return failed;
        }
        '''
        with tempfile.TemporaryDirectory(prefix="scene-timer-exhaustion-") as directory:
            root = Path(directory)
            path = root / "harness.c"
            path.write_text(source)
            binary = root / "harness"
            result = subprocess.run([shutil.which("clang") or "clang", "-std=c11", "-O1",
                "-I", str(VM), "-I", str(QUICKJS), *map(str,C_SOURCES), str(path),
                "-lm", "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result = subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
