#include "SceneQuickJS.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Wire values are deliberate public inputs, including the old-source RED.
 * The fixture does not read internal records or emulate a mutation owner. */
enum { CAP_NONE = 0, CAP_TEXT = 1, CAP_IMAGE_FONT = 2 };
static char diagnostic[1024];
static int checks, failures;
extern size_t mwx_test_snapshot_string_copies;
static size_t snapshot_copies, repeated_image_copies, repeated_text_copies;
static size_t native_capability_copies;
static const double zero[3] = {0, 0, 0}, one[3] = {1, 1, 1};
static const double extent[2] = {100, 80};
static const uint64_t generation = 91;

static void check(int condition, const char *label) {
    ++checks;
    if (!condition) {
        ++failures;
        fprintf(stderr, "FAIL %s: %s\n", label, diagnostic);
    }
}

static MWXSceneQuickJSDomain *make_domain(const char *image_name) {
    MWXSceneQuickJSDomain *d = mwx_scene_quickjs_domain_create(
        16 * 1024 * 1024, 512 * 1024, 200000, diagnostic, sizeof(diagnostic));
    check(d != NULL, "domain constructs");
    if (d == NULL) return NULL;
    check(mwx_scene_quickjs_domain_configure_layer_catalog(d, 3, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "catalog configures");
    const char *names[] = {image_name, "Caption", "OtherKind"};
    const int64_t ids[] = {17, 42, 75};
    const uint32_t caps[] = {CAP_IMAGE_FONT, CAP_TEXT, CAP_NONE};
    for (uint32_t i = 0; i < 3; ++i) {
        const char *font = i == 1 ? "fonts/Native.ttf" : "";
        check(mwx_scene_quickjs_domain_set_layer_runtime_descriptor(d, i, ids[i],
            0, 0, names[i], strlen(names[i]), zero, extent, one, zero, 1, 1,
            "seed", 4, font, strlen(font), 12, one, diagnostic, sizeof(diagnostic))
            == MWX_SCENE_QUICKJS_OK, "authored descriptor publishes");
        check(mwx_scene_quickjs_domain_set_layer_mutation_capabilities(d, i,
            caps[i], diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            i == 0 ? "image capability2 accepted" : "existing capability accepted");
    }
    return d;
}

static MWXSceneQuickJSOwner *owner(MWXSceneQuickJSDomain *d, const char *source) {
    MWXSceneQuickJSOwner *o = mwx_scene_quickjs_owner_create(d, source, strlen(source),
        generation, diagnostic, sizeof(diagnostic));
    check(o != NULL, "owner constructs through real module compiler");
    if (o == NULL) return NULL;
    check(mwx_scene_quickjs_owner_configure_layer_identity(o, 42, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "owner targets native text peer");
    check(mwx_scene_quickjs_owner_set_property_object_scope(o, 1, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "owner layer scope configures");
    return o;
}

static void execute_at(MWXSceneQuickJSOwner *o, uint64_t expected_generation,
    const char *input, MWXSceneQuickJSResult expected, const char *output,
    const char *label) {
    if (o == NULL) { check(0, label); return; }
    MWXSceneQuickJSFrameInput frame = {.frame_time = 0.016, .runtime = 1};
    char actual[8192] = {0}; size_t length = 0;
    diagnostic[0] = '\0';
    MWXSceneQuickJSResult status = mwx_scene_quickjs_owner_update_string(o,
        expected_generation, input, strlen(input), &frame, "", 0, "{}", 2,
        actual, sizeof(actual), &length, diagnostic, sizeof(diagnostic));
    check(status == expected, label);
    if (expected == MWX_SCENE_QUICKJS_OK) {
        check(output != NULL && length == strlen(output)
            && memcmp(actual, output, length) == 0, "typed String output matches");
    }
}

static void execute(MWXSceneQuickJSOwner *o, const char *input,
    MWXSceneQuickJSResult expected, const char *output, const char *label) {
    execute_at(o, generation, input, expected, output, label);
}

static void no_native_mutation(MWXSceneQuickJSOwner *o) {
    check(mwx_scene_quickjs_owner_layer_mutation_count(o) == 0,
        "image state produces no native layer mutation");
}

static void read_font(MWXSceneQuickJSDomain *d, const char *name, const char *expected) {
    char source[512];
    snprintf(source, sizeof(source), "export function update(v){"
        "const r=thisScene.getLayer('%s');return r.font===undefined?'<unset>':r.font;}", name);
    MWXSceneQuickJSOwner *o = owner(d, source);
    execute(o, "", MWX_SCENE_QUICKJS_OK, expected, "fresh owner/lookup reads target state");
    no_native_mutation(o);
    mwx_scene_quickjs_owner_destroy(o);
}

static void write_font(MWXSceneQuickJSDomain *d, const char *name, const char *path) {
    char source[512];
    snprintf(source, sizeof(source), "export function update(v){"
        "const r=thisScene.getLayer('%s');r.font=v;return r.font;}", name);
    MWXSceneQuickJSOwner *o = owner(d, source);
    execute(o, path, MWX_SCENE_QUICKJS_OK, path, "image font accepts path String");
    no_native_mutation(o);
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    mwx_scene_quickjs_owner_destroy(o);
}

static void shared_state(void) {
    const char *names[] = {"Canvas", "RenamedSurface"};
    const char *expressions[] = {"v", "('fonts/'+v.slice(6))"};
    for (size_t i = 0; i < 2; ++i) {
        MWXSceneQuickJSDomain *d = make_domain(names[i]);
        read_font(d, names[i], "<unset>");
        char source[1024];
        snprintf(source, sizeof(source), "export function update(v){"
            "let renamed=thisScene.getLayer('%s');renamed.font=%s;"
            "shared.ref=renamed;"
            "const fresh=thisScene.getLayer('%s');"
            "if(typeof fresh.font!=='string'||fresh.font!==v)throw Error('fresh read');"
            "fresh.font=(''+fresh.font);return shared.ref.font;}",
            names[i], expressions[i], names[i]);
        const char *path = i == 0 ? "fonts/Monofur.ttf" : "fonts/renamed-asset.otf";
        MWXSceneQuickJSOwner *a = owner(d, source);
        execute(a, path, MWX_SCENE_QUICKJS_OK, path, "renamed/equivalent String roundtrip");
        no_native_mutation(a);
        MWXSceneQuickJSOwner *b = owner(d,
            "export function update(v){shared.ref.font=v;return shared.ref.font;}");
        execute(b, path, MWX_SCENE_QUICKJS_OK, path, "other owner same-value write");
        no_native_mutation(b);
        mwx_scene_quickjs_owner_destroy(a);
        execute(b, "fonts/peer-write.ttf", MWX_SCENE_QUICKJS_OK,
            "fonts/peer-write.ttf", "stored authored handle survives writer retirement");
        no_native_mutation(b);
        read_font(d, names[i], "fonts/peer-write.ttf");
        mwx_scene_quickjs_owner_destroy(b);
        mwx_scene_quickjs_domain_destroy(d);
    }
}

static void text_journal(MWXSceneQuickJSOwner *o, const char *expected) {
    check(mwx_scene_quickjs_owner_layer_mutation_count(o) == 1,
        "only native text participates in the journal");
    MWXSceneQuickJSLayerMutation m = {0};
    check(mwx_scene_quickjs_owner_layer_mutation_at(o, 0, &m, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "native text mutation reads");
    check(m.layer_id == 42 && m.dynamic == 0
        && m.fields == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT
        && m.font != NULL && strcmp(m.font, expected) == 0,
        "typed FONT belongs only to the text peer");
}

static void transactions(void) {
    MWXSceneQuickJSDomain *d = make_domain("Canvas");
    const char *source =
        "export function update(v){thisScene.getLayer('Canvas').font=v;"
        "thisLayer.font='fonts/PendingText.ttf';"
        "if(v==='fonts/throw.ttf')throw Error('after image');return v;}";
    MWXSceneQuickJSOwner *a = owner(d, source);
    execute(a, "fonts/throw.ttf", MWX_SCENE_QUICKJS_EXCEPTION, NULL,
        "uncaught failure happens after the image write");
    no_native_mutation(a);
    read_font(d, "Canvas", "fonts/throw.ttf");
    read_font(d, "Caption", "fonts/Native.ttf");
    /* An uncaught callback exception disables that execution owner. The shared
     * authored state remains, while the next transaction uses a fresh owner. */
    mwx_scene_quickjs_owner_destroy(a);
    a = owner(d, source);
    execute(a, "fonts/A.ttf", MWX_SCENE_QUICKJS_OK, "fonts/A.ttf",
        "A stages native text and changes ordinary image state");
    text_journal(a, "fonts/PendingText.ttf");
    MWXSceneQuickJSOwner *b = owner(d,
        "export function update(v){thisScene.getLayer('Canvas').font=v;return v;}");
    execute(b, "fonts/B.ttf", MWX_SCENE_QUICKJS_OK, "fonts/B.ttf", "B overwrites shared image state");
    no_native_mutation(b);
    mwx_scene_quickjs_owner_commit_layer_mutations(b);
    mwx_scene_quickjs_owner_discard_layer_mutations(a);
    read_font(d, "Canvas", "fonts/B.ttf");
    read_font(d, "Caption", "fonts/Native.ttf");
    mwx_scene_quickjs_owner_destroy(b);
    read_font(d, "Canvas", "fonts/B.ttf");
    execute(a, "fonts/late-discard.ttf", MWX_SCENE_QUICKJS_OK,
        "fonts/late-discard.ttf", "native late rejection candidate executes");
    text_journal(a, "fonts/PendingText.ttf");
    mwx_scene_quickjs_owner_discard_layer_mutations(a);
    read_font(d, "Canvas", "fonts/late-discard.ttf");
    read_font(d, "Caption", "fonts/Native.ttf");
    mwx_scene_quickjs_owner_destroy(a);
    mwx_scene_quickjs_domain_destroy(d);
}

static void stage_snapshot(MWXSceneQuickJSDomain *d, uint64_t revision,
    int destroy_image, const char *native_font) {
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(d, revision, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "native snapshot begins");
    const size_t batch_start = mwx_test_snapshot_string_copies;
    for (uint32_t i = 0; i < 3; ++i) {
        const char *font = i == 1 ? native_font : "";
        const size_t start = mwx_test_snapshot_string_copies;
        check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, i,
            one, zero, i == 0 && destroy_image, 1, 1, 0, 1, "seed", 4,
            font, strlen(font), 12, one, diagnostic, sizeof(diagnostic))
            == MWX_SCENE_QUICKJS_OK, "native runtime fields stage");
        check(mwx_test_snapshot_string_copies - start == (i == 0 ? 1 : 2),
            i == 0 ? "image snapshot copies text without unused native font"
                   : "non-image snapshot still copies text and native font");
    }
    snapshot_copies = mwx_test_snapshot_string_copies - batch_start;
}

static void commit_snapshot(MWXSceneQuickJSDomain *d) {
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(d, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "native snapshot commits");
}

static void snapshots(void) {
    MWXSceneQuickJSDomain *d = make_domain("Canvas");
    write_font(d, "Canvas", "fonts/before-snapshot.ttf");
    stage_snapshot(d, 1, 0, "fonts/NativeSnapshot.ttf");
    commit_snapshot(d);
    read_font(d, "Canvas", "fonts/before-snapshot.ttf");
    read_font(d, "Caption", "fonts/NativeSnapshot.ttf");
    write_font(d, "Canvas", "fonts/after-snapshot.ttf");
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(d), "native snapshot rolls back");
    read_font(d, "Canvas", "fonts/after-snapshot.ttf");
    read_font(d, "Caption", "fonts/Native.ttf");
    stage_snapshot(d, 2, 0, "fonts/Abort.ttf");
    mwx_scene_quickjs_domain_abort_layer_snapshot(d);
    read_font(d, "Canvas", "fonts/after-snapshot.ttf");
    read_font(d, "Caption", "fonts/Native.ttf");
    stage_snapshot(d, 3, 0, "fonts/Accepted.ttf");
    commit_snapshot(d);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    stage_snapshot(d, 4, 0, "fonts/Next.ttf");
    commit_snapshot(d);
    read_font(d, "Canvas", "fonts/after-snapshot.ttf");
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    stage_snapshot(d, 5, 0, "fonts/FirstStage.ttf");
    size_t start = mwx_test_snapshot_string_copies;
    check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, 0,
        one, zero, 0, 1, 1, 0, 1, "restaged image", 14,
        "fonts/Ignored.ttf", strlen("fonts/Ignored.ttf"), 12, one,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "image runtime fields can replace their pending stage");
    repeated_image_copies = mwx_test_snapshot_string_copies - start;
    check(repeated_image_copies == 1, "restaged image copies only consumed text");
    start = mwx_test_snapshot_string_copies;
    check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, 1,
        one, zero, 0, 1, 1, 0, 1, "restaged caption", 16,
        "fonts/Repeated.ttf", strlen("fonts/Repeated.ttf"), 12, one,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "text runtime fields can replace their pending stage");
    repeated_text_copies = mwx_test_snapshot_string_copies - start;
    check(repeated_text_copies == 2, "restaged text still copies text and native font");
    commit_snapshot(d);
    read_font(d, "Canvas", "fonts/after-snapshot.ttf");
    read_font(d, "Caption", "fonts/Repeated.ttf");
    MWXSceneQuickJSOwner *reader = owner(d,
        "export function update(v){return thisScene.getLayer(v).text;}");
    execute(reader, "Canvas", MWX_SCENE_QUICKJS_OK, "restaged image", "restaged image text publishes");
    execute(reader, "Caption", MWX_SCENE_QUICKJS_OK, "restaged caption", "restaged native text publishes");
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(d), "restaged snapshot rolls back");
    read_font(d, "Caption", "fonts/Next.ttf");
    execute(reader, "Canvas", MWX_SCENE_QUICKJS_OK, "seed", "image text baseline restores");
    execute(reader, "Caption", MWX_SCENE_QUICKJS_OK, "seed", "native text baseline restores");
    no_native_mutation(reader);
    mwx_scene_quickjs_owner_destroy(reader);
    mwx_scene_quickjs_domain_destroy(d);
}

static void lifecycle(void) {
    MWXSceneQuickJSDomain *d = make_domain("Canvas");
    MWXSceneQuickJSOwner *a = owner(d,
        "export function update(v){shared.ref=thisScene.getLayer('Canvas');"
        "shared.ref.font=v;return v;}");
    execute(a, "fonts/live.ttf", MWX_SCENE_QUICKJS_OK, "fonts/live.ttf", "lifecycle seed writes");
    execute_at(a, generation + 1, "fonts/stale.ttf", MWX_SCENE_QUICKJS_STALE_OWNER,
        NULL, "stale owner generation cannot write");
    read_font(d, "Canvas", "fonts/live.ttf");
    mwx_scene_quickjs_owner_destroy(a);
    MWXSceneQuickJSOwner *b = owner(d,
        "export function update(v){return shared.ref.font;}");
    execute(b, "", MWX_SCENE_QUICKJS_OK, "fonts/live.ttf", "retired writer handle remains ordinary authored reference");
    stage_snapshot(d, 1, 1, "fonts/Native.ttf");
    commit_snapshot(d);
    execute(b, "", MWX_SCENE_QUICKJS_EXCEPTION, NULL, "destroyed target rejects retained handle");
    no_native_mutation(b);
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(d), "destroyed native snapshot rolls back");
    read_font(d, "Canvas", "fonts/live.ttf");
    mwx_scene_quickjs_owner_destroy(b);
    mwx_scene_quickjs_domain_destroy(d);
    d = make_domain("Canvas");
    read_font(d, "Canvas", "<unset>");
    b = owner(d, "export function update(v){"
        "if(shared.ref!==undefined)throw Error('cross-domain reference');return v;}");
    execute(b, "fresh", MWX_SCENE_QUICKJS_OK, "fresh", "rebuilt domain has no prior shared references");
    no_native_mutation(b);
    mwx_scene_quickjs_owner_destroy(b);
    mwx_scene_quickjs_domain_destroy(d);
}

static void validation(void) {
    MWXSceneQuickJSDomain *d = make_domain("Canvas");
    write_font(d, "Canvas", "fonts/valid.ttf");
    const char *invalid_types[] = {
        "42", "true", "null", "undefined", "new String(v)", "[v]", "Symbol('font')",
        "({toString(){shared.coercions=1;return v;}})",
    };
    for (size_t i = 0; i < sizeof(invalid_types) / sizeof(invalid_types[0]); ++i) {
        char source[1024];
        snprintf(source, sizeof(source), "export function update(v){"
            "thisScene.getLayer('Canvas').font=%s;return v;}", invalid_types[i]);
        MWXSceneQuickJSOwner *o = owner(d, source);
        execute(o, "fonts/coerced.ttf", MWX_SCENE_QUICKJS_EXCEPTION, NULL,
            "nonprimitive String rejects without coercion");
        no_native_mutation(o);
        mwx_scene_quickjs_owner_destroy(o);
        read_font(d, "Canvas", "fonts/valid.ttf");
    }
    MWXSceneQuickJSOwner *coercion = owner(d,
        "export function update(v){if(shared.coercions!==undefined)throw Error('coerced');return v;}");
    execute(coercion, "not coerced", MWX_SCENE_QUICKJS_OK, "not coerced", "objects never execute coercion hooks");
    mwx_scene_quickjs_owner_destroy(coercion);
    MWXSceneQuickJSOwner *o;
    const char *invalid_paths[] = {"", "/absolute.ttf", "../escape.ttf", "fonts/../escape.ttf",
        "./font.ttf", "fonts//bad.ttf", "fonts/", "fonts\\bad.ttf"};
    for (size_t i = 0; i < sizeof(invalid_paths) / sizeof(invalid_paths[0]); ++i) {
        o = owner(d, "export function update(v){thisScene.getLayer('Canvas').font=v;return v;}");
        execute(o, invalid_paths[i], MWX_SCENE_QUICKJS_EXCEPTION, NULL, "unsafe/empty relative path rejects");
        no_native_mutation(o);
        mwx_scene_quickjs_owner_destroy(o);
        read_font(d, "Canvas", "fonts/valid.ttf");
    }
    const char *expressions[] = {
        "'fonts/'+ 'a'.repeat(1014)+'.ttf'",
        "'fonts/'+ 'é'.repeat(507)+'.ttf'",
        "'fonts/'+ 'a'.repeat(1015)+'.ttf'",
        "'fonts/'+ 'é'.repeat(507)+'x.ttf'",
        "v+'\\u0000tail'",
    };
    char accepted_path[1025] = "fonts/valid.ttf";
    for (size_t i = 0; i < 5; ++i) {
        char source[1024];
        snprintf(source, sizeof(source), "export function update(v){"
            "const p=%s;thisScene.getLayer('Canvas').font=p;return 'accepted';}", expressions[i]);
        o = owner(d, source);
        execute(o, "fonts/valid.ttf", i < 2 ? MWX_SCENE_QUICKJS_OK : MWX_SCENE_QUICKJS_EXCEPTION,
            i < 2 ? "accepted" : NULL, "1024 UTF8 bytes accepted; 1025 and embedded NUL reject");
        no_native_mutation(o);
        mwx_scene_quickjs_owner_destroy(o);
        if (i < 2) {
            char expected[1025]; size_t cursor = 0;
            memcpy(expected, "fonts/", 6); cursor = 6;
            for (size_t count = 0; count < (i == 0 ? 1014u : 507u); ++count) {
                if (i == 0) expected[cursor++] = 'a';
                else { expected[cursor++] = (char)0xc3; expected[cursor++] = (char)0xa9; }
            }
            memcpy(expected + cursor, ".ttf", 5);
            memcpy(accepted_path, expected, sizeof(accepted_path));
        }
        read_font(d, "Canvas", accepted_path);
    }
    mwx_scene_quickjs_domain_destroy(d);
}

static void capabilities(void) {
    MWXSceneQuickJSDomain *d = make_domain("Canvas");
    write_font(d, "Canvas", "fonts/retained.ttf");
    const uint32_t invalid[] = {3, 4, 7, UINT32_MAX};
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i) {
        check(mwx_scene_quickjs_domain_set_layer_mutation_capabilities(d, 0, invalid[i],
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
            "combined or unknown capability bits reject");
        write_font(d, "Canvas", "fonts/retained.ttf");
    }
    check(mwx_scene_quickjs_domain_set_layer_mutation_capabilities(d, 3, CAP_IMAGE_FONT,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "out-of-catalog capability rejects");
    const char *operations[] = {
        "thisScene.getLayer('OtherKind').font=v",
        "thisScene.getLayer('Canvas').text='not text'",
        "thisScene.getLayer('Canvas').pointsize=24",
    };
    for (size_t i = 0; i < 3; ++i) {
        char source[512];
        snprintf(source, sizeof(source), "export function update(v){%s;return v;}", operations[i]);
        MWXSceneQuickJSOwner *o = owner(d, source);
        execute(o, "fonts/no-authority.ttf", MWX_SCENE_QUICKJS_EXCEPTION, NULL,
            "image capability does not grant native text or other-kind authority");
        no_native_mutation(o);
        mwx_scene_quickjs_owner_destroy(o);
    }
    MWXSceneQuickJSOwner *text = owner(d,
        "export function update(v){thisLayer.font=v;return thisLayer.font;}");
    execute(text, "fonts/Text.ttf", MWX_SCENE_QUICKJS_OK, "fonts/Text.ttf", "text font retains native typed behavior");
    text_journal(text, "fonts/Text.ttf");
    mwx_scene_quickjs_owner_discard_layer_mutations(text);
    read_font(d, "Caption", "fonts/Native.ttf");
    mwx_scene_quickjs_owner_destroy(text);
    check(mwx_scene_quickjs_domain_set_layer_mutation_capabilities(d, 0, CAP_NONE,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "no capability publishes");
    MWXSceneQuickJSOwner *none = owner(d,
        "export function update(v){thisScene.getLayer('Canvas').font=v;return v;}");
    execute(none, "fonts/revoked.ttf", MWX_SCENE_QUICKJS_EXCEPTION, NULL,
        "no capability does not admit image writes");
    no_native_mutation(none);
    mwx_scene_quickjs_owner_destroy(none);
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(d, 1, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "snapshot begins after capability changes between frames");
    for (uint32_t i = 1; i < 3; ++i)
        check(mwx_scene_quickjs_domain_reuse_layer_runtime_fields(d, i,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "unchanged peer fields reuse");
    const size_t start = mwx_test_snapshot_string_copies;
    check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, 0,
        one, zero, 0, 1, 1, 0, 1, "seed", 4,
        "fonts/NowNative.ttf", strlen("fonts/NowNative.ttf"), 12, one,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "revoked image capability consumes native font again");
    native_capability_copies = mwx_test_snapshot_string_copies - start;
    check(native_capability_copies == 2, "current non-image capability copies both strings");
    commit_snapshot(d);
    read_font(d, "Canvas", "fonts/NowNative.ttf");
    mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
    check(mwx_scene_quickjs_domain_set_layer_mutation_capabilities(d, 0, CAP_IMAGE_FONT,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "image capability restores between finalized frames");
    stage_snapshot(d, 2, 0, "fonts/Caption.ttf");
    commit_snapshot(d);
    read_font(d, "Canvas", "fonts/NowNative.ttf");
    write_font(d, "Canvas", "fonts/ScriptAgain.ttf");
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(d), "restored image snapshot rolls back");
    read_font(d, "Canvas", "fonts/ScriptAgain.ttf");
    mwx_scene_quickjs_domain_destroy(d);
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    if (strcmp(argv[1], "shared") == 0) shared_state();
    else if (strcmp(argv[1], "transactions") == 0) transactions();
    else if (strcmp(argv[1], "snapshots") == 0) snapshots();
    else if (strcmp(argv[1], "lifecycle") == 0) lifecycle();
    else if (strcmp(argv[1], "validation") == 0) validation();
    else if (strcmp(argv[1], "capabilities") == 0) capabilities();
    else return 2;
    printf("{\"group\":\"%s\",\"checks\":%d,\"failures\":%d,"
        "\"snapshotStringCopies\":%zu,\"repeatedImageCopies\":%zu,"
        "\"repeatedTextCopies\":%zu,\"nativeCapabilityCopies\":%zu}\n",
        argv[1], checks, failures, snapshot_copies, repeated_image_copies,
        repeated_text_copies, native_capability_copies);
    return failures == 0 ? 0 : 1;
}
