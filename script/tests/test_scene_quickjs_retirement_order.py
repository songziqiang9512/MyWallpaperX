"""Real C VM catalog order at selective retirement and snapshot rollback."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import C_SOURCES, VM, QUICKJS


HARNESS = r'''
#include "SceneQuickJSInternal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
static char diagnostic[512];
static int fail_snapshot_malloc = 0;
void *retirement_snapshot_malloc(size_t size) {
    if (fail_snapshot_malloc) { fail_snapshot_malloc = 0; return NULL; }
    return malloc(size);
}
static void check(int condition, const char *label) {
    if (!condition) { fprintf(stderr, "FAIL %s: %s\n", label, diagnostic); failures++; }
}
static MWXSceneQuickJSDomain *catalog(void) {
    MWXSceneQuickJSDomain *d = mwx_scene_quickjs_domain_create(16 * 1024 * 1024, 1024 * 1024, 100000, diagnostic, sizeof(diagnostic));
    check(d != NULL, "domain");
    const double origin[3] = {0,0,0}, size[2] = {100,100};
    check(mwx_scene_quickjs_domain_configure_layer_catalog(d, 4, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "catalog");
    const char *names[] = {"A", "S", "H", "T"};
    for (uint32_t i = 0; i < 4; i++)
        check(mwx_scene_quickjs_domain_set_layer_descriptor(d, i, (i+1)*10, 0, 0,
            names[i], 1, origin, size, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "descriptor");
    return d;
}
static void stage_snapshot(MWXSceneQuickJSDomain *d, uint64_t generation, int dead) {
    const double scale[3] = {1,1,1}, angles[3] = {0,0,0}, color[3] = {1,1,1};
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(d, generation, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "snapshot begin");
    for (uint32_t i = 0; i < 4; i++)
        check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, i, scale, angles,
            dead == (int)i, 1, 1, 1, "", 0, "", 0, 32, color,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "snapshot fields");
    check(mwx_scene_quickjs_domain_update_layer_video_fields(d, 3, 1, 10, 1, 1, 0, 1, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "video metadata");
}
static void publish(MWXSceneQuickJSDomain *d, uint64_t generation, int dead) {
    stage_snapshot(d, generation, dead);
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(d, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "snapshot commit");
}
static MWXSceneQuickJSOwner *owner(MWXSceneQuickJSDomain *d, const char *source, int id) {
    MWXSceneQuickJSResult result;
    MWXSceneQuickJSOwner *o = mwx_scene_quickjs_owner_create_with_budget(d, source, strlen(source),
        1, 100000, &result, diagnostic, sizeof(diagnostic));
    check(o != NULL && result == MWX_SCENE_QUICKJS_OK, "owner");
    check(mwx_scene_quickjs_owner_configure_layer_identity(o, id, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "owner identity");
    return o;
}
static void update(MWXSceneQuickJSOwner *o) {
    MWXSceneQuickJSFrameInput f = {.time_of_day=.25, .frame_time=.1, .runtime=1};
    double value = 0;
    check(mwx_scene_quickjs_owner_update_scalar(o, 1, 1, &f, &value,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK && value == 1, "VM callback");
}
static void observe(MWXSceneQuickJSDomain *d, const char *expected) {
    char source[1024];
    snprintf(source, sizeof(source), "export function update(v){const a=thisScene.enumerateLayers();"
        "if(a.map(l=>l.name).join(',')!=='%s')throw new Error(a.map(l=>l.name).join(','));"
        "for(let i=0;i<a.length;i++)if(thisScene.getLayer(i).name!==a[i].name||"
        "thisScene.getLayerIndex(a[i])!==i)throw new Error('ordinal');return v;}", expected);
    MWXSceneQuickJSOwner *o = owner(d, source, 40);
    update(o);
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    mwx_scene_quickjs_owner_destroy(o);
}
static void snapshot_case(void) {
    MWXSceneQuickJSDomain *d = catalog(); publish(d, 1, -1);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    MWXSceneQuickJSOwner *creator = owner(d,
        "export function update(v){thisScene.createLayer({name:'X',text:'copy'});return v;}", 10);
    update(creator); mwx_scene_quickjs_owner_commit_layer_mutations(creator);
    observe(d, "A,S,H,T,X");
    stage_snapshot(d, 2, 1); fail_snapshot_malloc = 1;
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(d, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_MEMORY_EXCEEDED, "rank allocation failure is typed");
    check(d->layer_snapshot_generation == 1 && !d->layers[1].destroyed &&
        d->rollback_layer_order == NULL, "rank allocation failure preserves active snapshot");
    observe(d, "A,S,H,T,X");
    mwx_scene_quickjs_domain_abort_layer_snapshot(d);
    publish(d, 2, 1); observe(d, "A,H,T,X");
    check(d->rollback_layer_order != NULL, "retirement stores old dynamic and authored ranks");
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(d), "rollback tombstone");
    observe(d, "A,S,H,T,X");
    check(d->rollback_layer_order == NULL, "rollback releases rank buffer");
    publish(d, 2, 1); mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    observe(d, "A,H,T,X");
    check(d->rollback_layer_order == NULL, "accept releases rank buffer");
    publish(d, 3, 1);
    check(d->rollback_layer_order == NULL, "unchanged tombstone does not allocate ranks");
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    observe(d, "A,H,T,X");
    mwx_scene_quickjs_owner_destroy(creator); mwx_scene_quickjs_domain_destroy(d);
}
static void removal_case(void) {
    MWXSceneQuickJSDomain *d = catalog(); publish(d, 1, -1);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    MWXSceneQuickJSOwner *creator = owner(d,
        "export function update(v){const x=thisScene.createLayer({name:'D',text:'copy'});"
        "thisScene.sortLayer(x,1);thisScene.sortLayer(thisScene.getLayer('T'),2);"
        "thisScene.sortLayer(thisScene.getLayer('S'),4);return v;}", 10);
    update(creator); mwx_scene_quickjs_owner_commit_layer_mutations(creator);
    observe(d, "A,D,T,H,S");
    check(mwx_scene_quickjs_owner_remove_dynamic_layers(creator), "remove creator copy");
    observe(d, "A,T,H,S");
    publish(d, 2, 0); mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    observe(d, "T,H,S");
    mwx_scene_quickjs_owner_destroy(creator); mwx_scene_quickjs_domain_destroy(d);
}
static void rejection_case(void) {
    MWXSceneQuickJSDomain *d = catalog(); publish(d, 1, -1);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    MWXSceneQuickJSOwner *p = owner(d,
        "export function update(v){const x=thisScene.createLayer({name:'X',text:'copy'});"
        "thisScene.sortLayer(x,0);return v;}", 10);
    MWXSceneQuickJSOwner *q = owner(d,
        "export function update(v){thisScene.sortLayer(thisScene.getLayer('S'),3);"
        "thisScene.destroyLayer('A');return v;}", 40);
    update(p); update(q); observe(d, "X,A,H,S,T");
    mwx_scene_quickjs_owner_discard_layer_mutations(p);
    observe(d, "A,H,T,S");
    mwx_scene_quickjs_owner_commit_layer_mutations(q);
    publish(d, 2, 0); mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    observe(d, "H,T,S");
    mwx_scene_quickjs_owner_destroy(p); mwx_scene_quickjs_owner_destroy(q);
    mwx_scene_quickjs_domain_destroy(d);
}
static void video_roots_case(void) {
    MWXSceneQuickJSDomain *d = catalog(); publish(d, 1, -1);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    MWXSceneQuickJSOwner *o = owner(d,
        "export function update(v){thisScene.getLayer('T').getVideoTexture().addEndedCallback(()=>{});return v;}"
        "export function destroy(){thisScene.getLayer('T').getVideoTexture().addEndedCallback(()=>{});throw new Error('cleanup');}", 10);
    update(o); mwx_scene_quickjs_owner_commit_layer_mutations(o);
    check(o->video_ended_callback_count == 1, "real video root registered");
    MWXSceneQuickJSFrameInput f = {.time_of_day=.25, .frame_time=.1, .runtime=1};
    uint32_t invoked = 0, threw = 0;
    check(mwx_scene_quickjs_owner_teardown_with_provenance(o, 1, &f, NULL, 0, "{}", 2,
        &invoked, &threw, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_EXCEPTION
        && invoked && threw, "throwing video root cleanup callback");
    check(o->video_ended_callback_count == 0, "retirement frees video roots including cleanup-created root");
    for (size_t i = 0; i < MWX_SCENE_QUICKJS_MAX_VIDEO_ENDED_CALLBACKS; i++)
        check(!o->video_ended_callbacks[i].active, "all video root slots inactive");
    mwx_scene_quickjs_owner_destroy(o); mwx_scene_quickjs_domain_destroy(d);
}
int main(void) {
    snapshot_case(); removal_case(); rejection_case(); video_roots_case();
    printf("{\"passed\":%s}\n", failures ? "false" : "true");
    return failures ? 1 : 0;
}
'''


class SceneQuickJSRetirementOrderTests(unittest.TestCase):
    def test_real_vm_retirement_snapshot_rollback_creator_order_and_video_roots(self):
        clang = shutil.which("clang")
        if not clang:
            raise unittest.SkipTest("clang unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-quickjs-retirement-order-") as temp:
            root = Path(temp)
            source, binary = root / "harness.c", root / "harness"
            source.write_text(HARNESS, encoding="utf-8")
            snapshot = VM / "SceneQuickJSLayerSnapshotHost.c"
            snapshot_object = root / "snapshot.o"
            staged = subprocess.run([clang, "-std=c11", "-O0", "-I", str(VM), "-I", str(QUICKJS),
                "-Dmalloc=retirement_snapshot_malloc", "-c", str(snapshot), "-o", str(snapshot_object)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(staged.returncode, 0, staged.stdout + staged.stderr)
            command = [clang, "-std=c11", "-O0", "-I", str(VM), "-I", str(QUICKJS),
                       *map(str, (path for path in C_SOURCES if path != snapshot)),
                       str(snapshot_object), str(source), "-lm", "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            self.assertTrue(json.loads(ran.stdout)["passed"])


if __name__ == "__main__":
    unittest.main()
