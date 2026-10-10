"""Execute named property Timeline handles through the real QuickJS journal."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import C_SOURCES, ROOT, VM, QUICKJS


HARNESS = r'''
#include "SceneQuickJS.h"
#include <stdio.h>
#include <string.h>

static int failures;
static char diagnostic[512];

static void check(int condition, const char *label) {
    if (!condition) {
        fprintf(stderr, "FAIL %s: %s\n", label, diagnostic);
        failures++;
    }
}

static MWXSceneQuickJSDomain *domain(void) {
    MWXSceneQuickJSDomain *d = mwx_scene_quickjs_domain_create(
        16 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic));
    check(d != NULL, "domain creates");
    if (d == NULL) return NULL;
    check(mwx_scene_quickjs_domain_configure_layer_catalog(d, 2,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "layer catalog");
    const double origin[3] = {0, 0, 0}, size[2] = {100, 100};
    check(mwx_scene_quickjs_domain_set_layer_descriptor(d, 0, 17, 0, 0,
        "A", 1, origin, size, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "first layer descriptor");
    check(mwx_scene_quickjs_domain_set_layer_descriptor(d, 1, 42, 0, 0,
        "B", 1, origin, size, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "second layer descriptor");
    return d;
}

static void catalog(MWXSceneQuickJSDomain *d) {
    char retained_name[] = "same";
    char boundary[256]; memset(boundary, 'z', sizeof(boundary));
    MWXSceneQuickJSNamedAnimation entries[] = {
        {7, 17, retained_name, 4}, {11, 42, "same", 4},
        {12, 17, "ambiguous", 9}, {13, 17, "ambiguous", 9},
        {14, 17, boundary, sizeof(boundary)}, {15, 42, "精确名", strlen("精确名")},
    };
    check(mwx_scene_quickjs_domain_configure_named_animations(d, entries, 6,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "named catalog accepts");
    memset(retained_name, 'x', 4);
    check(mwx_scene_quickjs_domain_configure_named_animations(d, entries, 6,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "named catalog immutable");
}

static MWXSceneQuickJSOwner *owner(MWXSceneQuickJSDomain *d, const char *source,
                                  int layer_scope) {
    MWXSceneQuickJSOwner *o = mwx_scene_quickjs_owner_create(d, source, strlen(source),
        91, diagnostic, sizeof(diagnostic));
    check(o != NULL, "owner creates");
    if (o == NULL) return NULL;
    check(mwx_scene_quickjs_owner_configure_layer_identity(o, 17,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "owner layer identity");
    check(mwx_scene_quickjs_owner_set_property_object_scope(o, layer_scope,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "property object scope");
    return o;
}

static void update_step(MWXSceneQuickJSOwner *o, double input, double step, double runtime,
                        MWXSceneQuickJSResult expected) {
    MWXSceneQuickJSFrameInput frame = {.frame_time = step, .runtime = runtime};
    double output = 0;
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_scalar(
        o, 91, input, &frame, &output, diagnostic, sizeof(diagnostic));
    if (actual != expected) fprintf(stderr, "callback status actual=%d expected=%d\n", actual, expected);
    check(actual == expected, "callback result");
    if (expected == MWX_SCENE_QUICKJS_OK) check(output == input, "callback value preserved");
}

static void update(MWXSceneQuickJSOwner *o, double input, double runtime,
                   MWXSceneQuickJSResult expected) {
    update_step(o, input, 0.1, runtime, expected);
}

static void command(MWXSceneQuickJSOwner *o, size_t index,
                    MWXSceneQuickJSAnimationCommand expected, uint32_t target) {
    MWXSceneQuickJSAnimationCommand actual = 0; uint32_t actual_target = 0;
    check(mwx_scene_quickjs_owner_animation_command_at(o, index, &actual, &actual_target,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK &&
        actual == expected && actual_target == target, "ordered typed animation command");
}

static void invalid_catalogs(void) {
    MWXSceneQuickJSDomain *d = domain(); if (d == NULL) return;
    MWXSceneQuickJSNamedAnimation valid = {7, 17, "same", 4};
    MWXSceneQuickJSNamedAnimation bad[] = {
        {UINT32_MAX, 17, "same", 4}, {8, 999, "same", 4},
        {9, 17, "", 0}, {10, 17, "a\0b", 3}, {11, 17, NULL, 4},
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) {
        MWXSceneQuickJSNamedAnimation partial[] = {valid, bad[i]};
        check(mwx_scene_quickjs_domain_configure_named_animations(d, partial, 2,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
            "invalid late record leaves no partial catalog");
    }
    MWXSceneQuickJSNamedAnimation duplicate[] = {valid, {7, 42, "other", 5}};
    check(mwx_scene_quickjs_domain_configure_named_animations(d, duplicate, 2,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "duplicate target index rejected");
    char large[257]; memset(large, 'x', sizeof(large));
    MWXSceneQuickJSNamedAnimation too_long = {8, 17, large, sizeof(large)};
    check(mwx_scene_quickjs_domain_configure_named_animations(d, &too_long, 1,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "name byte budget enforced");
    check(mwx_scene_quickjs_domain_configure_named_animations(d, &valid, 4097,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "catalog budget rejects before dereference");
    catalog(d);
    mwx_scene_quickjs_domain_destroy(d);
    d = domain(); if (d == NULL) return;
    check(mwx_scene_quickjs_domain_configure_named_animations(d, NULL, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "empty catalog valid");
    mwx_scene_quickjs_domain_destroy(d);
}

static void retained_and_scopes(void) {
    MWXSceneQuickJSDomain *d = domain(); if (d == NULL) return;
    catalog(d);
    const char *source =
        "let a,b;export function init(v){"
        "const layer=thisScene.getLayer('A');a=layer.getAnimation('same');"
        "b=thisScene.getLayerByID(42).getAnimation('same');"
        "shared.a=a;shared.getter=layer.getAnimation;shared.obj=thisObject;"
        "a.play();b.pause();thisLayer.getAnimation('same').stop();"
        "thisObject.getAnimation('same').play();thisObject.getAnimation().pause();"
        "engine.setTimeout(()=>{a.pause();b.stop();},1500);return v;}"
        "export function update(v){if(v===2)shared.getter('same').play();"
        "if(v===3){a.stop();throw new Error('late');}return v;}";
    MWXSceneQuickJSOwner *o = owner(d, source, 1);
    check(mwx_scene_quickjs_owner_configure_current_animation(o, 1,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "current animation compatible");
    update(o, 1, 0, MWX_SCENE_QUICKJS_OK);
    check(mwx_scene_quickjs_owner_animation_command_count(o) == 5, "one mixed journal");
    command(o, 0, MWX_SCENE_QUICKJS_ANIMATION_PLAY, 7);
    command(o, 1, MWX_SCENE_QUICKJS_ANIMATION_PAUSE, 11);
    command(o, 2, MWX_SCENE_QUICKJS_ANIMATION_STOP, 7);
    command(o, 3, MWX_SCENE_QUICKJS_ANIMATION_PLAY, 7);
    command(o, 4, MWX_SCENE_QUICKJS_ANIMATION_PAUSE, UINT32_MAX);
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    update_step(o, 2, 1, 1, MWX_SCENE_QUICKJS_OK);
    command(o, 0, MWX_SCENE_QUICKJS_ANIMATION_PLAY, 7);
    mwx_scene_quickjs_owner_discard_layer_mutations(o);
    update_step(o, 1, 0.5, 1.5, MWX_SCENE_QUICKJS_OK);
    check(mwx_scene_quickjs_owner_animation_command_count(o) == 2, "timer retains both targets");
    command(o, 0, MWX_SCENE_QUICKJS_ANIMATION_PAUSE, 7);
    command(o, 1, MWX_SCENE_QUICKJS_ANIMATION_STOP, 11);
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    MWXSceneQuickJSOwner *peer = owner(d,
        "export function update(v){let rejected=0;"
        "for(const f of [()=>shared.a.play(),()=>shared.getter('same').play(),"
        "()=>shared.obj.getAnimation('same').play()]){"
        "try{f();}catch(e){if(e instanceof TypeError)rejected++;}}"
        "if(rejected!==3)throw new Error('foreign handle');return v;}", 0);
    update(peer, 1, 1.5, MWX_SCENE_QUICKJS_OK);
    check(mwx_scene_quickjs_owner_animation_command_count(peer) == 0, "foreign owner cannot borrow");
    mwx_scene_quickjs_owner_commit_layer_mutations(peer);
    MWXSceneQuickJSOwner *outside = mwx_scene_quickjs_owner_create(d,
        "shared.a.play();export function update(v){return v;}",
        strlen("shared.a.play();export function update(v){return v;}"),
        91, diagnostic, sizeof(diagnostic));
    check(outside == NULL, "callback-external mutation rejected");
    if (outside != NULL) mwx_scene_quickjs_owner_destroy(outside);
    MWXSceneQuickJSFrameInput frame = {.runtime = 1.5}; double value = 0;
    check(mwx_scene_quickjs_owner_update_scalar(o, 92, 1, &frame, &value,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_STALE_OWNER, "stale generation rejected");
    update(o, 3, 1.6, MWX_SCENE_QUICKJS_EXCEPTION);
    update(o, 1, 1.7, MWX_SCENE_QUICKJS_DISABLED);
    update(peer, 1, 1.6, MWX_SCENE_QUICKJS_OK);
    mwx_scene_quickjs_owner_commit_layer_mutations(peer);
    mwx_scene_quickjs_owner_destroy(o);
    update(peer, 1, 1.7, MWX_SCENE_QUICKJS_OK);
    check(mwx_scene_quickjs_owner_animation_command_count(peer) == 0, "freed owner not dereferenced");
    mwx_scene_quickjs_owner_destroy(peer);
    mwx_scene_quickjs_domain_destroy(d);
}

static void rejection_and_deletion(void) {
    MWXSceneQuickJSDomain *d = domain(); if (d == NULL) return; catalog(d);
    MWXSceneQuickJSOwner *o = owner(d,
        "export function update(v){let rejected=0;const layer=thisScene.getLayer('A');"
        "for(const f of [()=>layer.getAnimation('absent'),()=>layer.getAnimation('ambiguous'),"
        "()=>layer.getAnimation(''),()=>layer.getAnimation('a\\0b'),"
        "()=>layer.getAnimation('z'.repeat(257)),()=>layer.getAnimation(1),"
        "()=>layer.getAnimation(),()=>thisObject.getAnimation('same')]){"
        "try{f();}catch(e){if(e instanceof TypeError||e instanceof RangeError)rejected++;}}"
        "if(rejected!==8)throw new Error('lookup scope');"
        "layer.getAnimation('z'.repeat(256)).stop();"
        "thisScene.getLayer('B').getAnimation('精确名').play();return v;}", 0);
    update(o, 1, 0, MWX_SCENE_QUICKJS_OK);
    command(o, 0, MWX_SCENE_QUICKJS_ANIMATION_STOP, 14);
    command(o, 1, MWX_SCENE_QUICKJS_ANIMATION_PLAY, 15);
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    MWXSceneQuickJSOwner *pending = owner(d,
        "export function update(v){const a=thisScene.getLayer('B').getAnimation('same');"
        "thisScene.destroyLayer('B');a.play();return v;}", 0);
    update(pending, 1, 0, MWX_SCENE_QUICKJS_EXCEPTION);
    check(mwx_scene_quickjs_owner_animation_command_count(pending) == 0,
        "pending deletion rejects retained target");
    MWXSceneQuickJSOwner *retained = owner(d,
        "let a;export function init(v){a=thisScene.getLayer('B').getAnimation('same');return v;}"
        "export function update(v){if(v===2)a.play();return v;}", 0);
    update(retained, 1, 0, MWX_SCENE_QUICKJS_OK);
    mwx_scene_quickjs_owner_commit_layer_mutations(retained);
    MWXSceneQuickJSOwner *deleter = owner(d,
        "export function update(v){thisScene.destroyLayer('B');return v;}", 0);
    update(deleter, 1, 0, MWX_SCENE_QUICKJS_OK);
    mwx_scene_quickjs_owner_commit_layer_mutations(deleter);
    // The host applies accepted authored removal and then publishes its next
    // typed snapshot. Committing a C journal alone does not alter authored data.
    const double scale[3] = {1, 1, 1}, angles[3] = {0, 0, 0}, color[3] = {1, 1, 1};
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(d, 1,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "deletion snapshot begins");
    check(mwx_scene_quickjs_domain_reuse_layer_runtime_fields(d, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "unaffected layer preserved");
    check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, 1, scale, angles,
        1, 1, 1, 1, "", 0, "", 0, 32, color, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_OK, "accepted deletion mirrored");
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(d, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_OK, "deletion snapshot publishes");
    update(retained, 2, 0.1, MWX_SCENE_QUICKJS_EXCEPTION);
    update(retained, 1, 0.2, MWX_SCENE_QUICKJS_DISABLED);
    MWXSceneQuickJSOwner *clone = owner(d,
        "export function update(v){const layer=thisScene.createLayer({name:'B',text:'clone'});"
        "if(!layer)throw new Error('clone unavailable');let rejected=false;"
        "try{layer.getAnimation('same').play();}catch(e){rejected=e instanceof TypeError;}"
        "if(!rejected)throw new Error('clone reused Timeline');return v;}", 0);
    update(clone, 1, 0.2, MWX_SCENE_QUICKJS_OK);
    check(mwx_scene_quickjs_owner_animation_command_count(clone) == 0,
        "dynamic clone inherits no prepared Timeline");
    mwx_scene_quickjs_owner_destroy(clone);
    mwx_scene_quickjs_owner_destroy(deleter);
    mwx_scene_quickjs_owner_destroy(retained);
    mwx_scene_quickjs_owner_destroy(pending);
    mwx_scene_quickjs_owner_destroy(o);
    mwx_scene_quickjs_domain_destroy(d);
}

static void readonly_and_budget(void) {
    MWXSceneQuickJSDomain *d = domain(); if (d == NULL) return; catalog(d);
    const char *source = "export function update(v){let rejected=false;"
        "try{thisScene.getLayer('A').getAnimation('same').play();}"
        "catch(e){rejected=e instanceof TypeError;}return rejected&&v;}";
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    MWXSceneQuickJSOwner *o = mwx_scene_quickjs_owner_create_value_only_with_budget(d,
        source, strlen(source), 91, 100000, &result, diagnostic, sizeof(diagnostic));
    check(o != NULL && result == MWX_SCENE_QUICKJS_OK, "value-only owner creates");
    MWXSceneQuickJSFrameInput frame = {.runtime = 0}; uint32_t output = 0;
    check(mwx_scene_quickjs_owner_update_bool_with_properties(
        o, 91, 1, &frame, NULL, 0, "{}", 2, &output,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK && output == 1,
        "Boolean owner retains read-only authority");
    check(mwx_scene_quickjs_owner_animation_command_count(o) == 0, "read-only stages no command");
    mwx_scene_quickjs_owner_destroy(o);
    o = owner(d, "export function update(v){const a=thisLayer.getAnimation('same');"
        "for(let i=0;i<17;i++){try{a.play();}catch(e){}}return v;}", 0);
    update(o, 1, 0, MWX_SCENE_QUICKJS_OK);
    MWXSceneQuickJSAnimationCommand actual = 0; uint32_t actual_target = 0;
    check(mwx_scene_quickjs_owner_animation_command_at(o, 0, &actual, &actual_target,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_MUTATION_OVERFLOW,
        "caught overflow cannot expose a partial command prefix");
    mwx_scene_quickjs_owner_discard_layer_mutations(o);
    mwx_scene_quickjs_owner_destroy(o);
    mwx_scene_quickjs_domain_destroy(d);
    d = domain(); if (d == NULL) return;
    o = owner(d, "export function update(v){return v;}", 0);
    update(o, 1, 0, MWX_SCENE_QUICKJS_OK);
    check(mwx_scene_quickjs_domain_configure_named_animations(d, NULL, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "post-callback catalog construction rejected");
    mwx_scene_quickjs_owner_destroy(o); mwx_scene_quickjs_domain_destroy(d);
}

int main(void) {
    invalid_catalogs(); retained_and_scopes(); rejection_and_deletion(); readonly_and_budget();
    return failures == 0 ? 0 : 1;
}
'''


class NamedAnimationHostTests(unittest.TestCase):
    def _run_harness(self, sanitized: bool) -> None:
        clang = shutil.which("clang")
        if clang is None:
            self.skipTest("clang is required for the real QuickJS host gate")
        with tempfile.TemporaryDirectory(prefix="mwx-named-animation-") as directory:
            root = Path(directory)
            harness = root / "harness.c"
            binary = root / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            flags = ["-fsanitize=address", "-fno-omit-frame-pointer"] if sanitized else []
            compiled = subprocess.run(
                [clang, "-std=c11", "-O0", "-g", *flags, "-I", str(VM), "-I",
                 str(QUICKJS), *map(str, C_SOURCES), str(harness), "-lm", "-o", str(binary)],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            completed = subprocess.run([str(binary)], cwd=ROOT, text=True, capture_output=True)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_named_animation_identity_and_journal(self) -> None:
        self._run_harness(False)

    def test_retained_named_animation_under_address_sanitizer(self) -> None:
        self._run_harness(True)


if __name__ == "__main__":
    unittest.main()
