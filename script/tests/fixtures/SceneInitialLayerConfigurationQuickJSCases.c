#include "SceneQuickJS.h"

#include <stdio.h>
#include <string.h>

static int failures;
static int facts;

static void expect(int condition, const char *label, const char *diagnostic) {
    facts += 1;
    if (condition) return;
    failures += 1;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic ? diagnostic : "");
}

static const char *authored =
    "{\"id\":17,\"name\":\"anchor\",\"origin\":{\"value\":\"1 2 3\","
    "\"script\":\"export function update(v){return v;}\","
    "\"scriptproperties\":{\"bias\":{\"value\":2,\"user\":\"slider\"}}},"
    "\"nested\":{\"id\":77,\"parts\":[{\"id\":88,\"name\":\"虹\"}]},"
    "\"flags\":[true,null,3],\"text\":\"authored\"}";

static MWXSceneQuickJSDomain *make_domain(void) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic));
    expect(domain != NULL, "domain", diagnostic);
    if (domain == NULL) return NULL;
    expect(mwx_scene_quickjs_domain_configure_layer_catalog(
        domain, 3, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "catalog", diagnostic);
    const char *names[] = {"anchor", "nil-config", "callback-target"};
    const double origin[3] = {1, 2, 3};
    const double size[2] = {100, 50};
    for (uint32_t i = 0; i < 3; ++i) {
        expect(mwx_scene_quickjs_domain_set_layer_descriptor(domain, i,
            17 + i, 0, 0, names[i], strlen(names[i]), origin, size,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "descriptor", diagnostic);
    }
    expect(mwx_scene_quickjs_domain_set_layer_initial_configuration(domain, 0,
        authored, strlen(authored), diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "authored configuration", diagnostic);
    expect(mwx_scene_quickjs_domain_set_layer_initial_configuration(domain, 0,
        "{\"name\":\"replacement\"}", 22, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "repeat cannot overwrite", diagnostic);
    expect(mwx_scene_quickjs_domain_set_layer_initial_configuration(domain, 99,
        "{}", 2, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "out-of-range setter", diagnostic);
    expect(mwx_scene_quickjs_domain_set_layer_initial_configuration(domain, 1,
        "[]", 2, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "array cannot become layer configuration", diagnostic);
    return domain;
}

static void publish(MWXSceneQuickJSDomain *domain, uint64_t epoch, double x) {
    char diagnostic[512] = {0};
    const double scale[3] = {1, 1, 1}, angles[3] = {0, 0, 0}, color[3] = {1, 1, 1};
    const double origin[3] = {x, 8, 7};
    expect(mwx_scene_quickjs_domain_begin_layer_snapshot(domain, epoch,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "begin snapshot", diagnostic);
    for (uint32_t i = 0; i < 3; ++i) {
        expect(mwx_scene_quickjs_domain_update_layer_runtime_fields(domain, i,
            scale, angles, 0, 1, 1, .5, "current", 7, "", 0, 32, color,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "runtime fields", diagnostic);
        expect(mwx_scene_quickjs_domain_set_layer_origin(domain, i, origin,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "current origin", diagnostic);
    }
    expect(mwx_scene_quickjs_domain_commit_layer_snapshot(domain,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "commit snapshot", diagnostic);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
}

static MWXSceneQuickJSOwner *owner(MWXSceneQuickJSDomain *domain, const char *source) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSOwner *value = mwx_scene_quickjs_owner_create(domain,
        source, strlen(source), 41, diagnostic, sizeof(diagnostic));
    expect(value != NULL, "owner compile", diagnostic);
    if (value != NULL) expect(mwx_scene_quickjs_owner_configure_layer_identity(
        value, 17, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "owner identity", diagnostic);
    return value;
}

static void update(MWXSceneQuickJSOwner *value, double input, double expected,
                   const char *label) {
    char diagnostic[512] = {0};
    double output = -1;
    MWXSceneQuickJSFrameInput frame = {.frame_time = 1.0 / 60.0, .runtime = input};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_update_scalar(value,
        41, input, &frame, &output, diagnostic, sizeof(diagnostic));
    expect(result == MWX_SCENE_QUICKJS_OK && output == expected, label, diagnostic);
}

struct CallbackAttempt { MWXSceneQuickJSDomain *domain; int count; MWXSceneQuickJSResult result; };

static MWXSceneQuickJSStorageReadResult callback_setter(
    void *opaque, MWXSceneQuickJSOwner *owner, const char *screen, size_t screen_length,
    uint32_t global, const char *key, size_t key_length,
    char *json, size_t capacity, size_t *length
) {
    (void)owner; (void)screen; (void)screen_length; (void)global; (void)key; (void)key_length;
    struct CallbackAttempt *attempt = opaque;
    char diagnostic[512] = {0};
    attempt->count += 1;
    attempt->result = mwx_scene_quickjs_domain_set_layer_initial_configuration(
        attempt->domain, 2, "{\"name\":\"injected\"}", 19, diagnostic, sizeof(diagnostic));
    *length = 1;
    if (capacity < 2) return MWX_SCENE_QUICKJS_STORAGE_READ_BUFFER_TOO_SMALL;
    memcpy(json, "0", 2);
    return MWX_SCENE_QUICKJS_STORAGE_READ_FOUND;
}

int main(void) {
    MWXSceneQuickJSDomain *domain = make_domain();
    if (domain == NULL) return 1;
    publish(domain, 1, 9);
    const char *read_source =
        "function verify(c){if(!c||'id' in c||c.name!=='anchor'||c.nested.id!==77||"
        "c.nested.parts[0].id!==88||c.nested.parts[0].name!=='虹'||"
        "c.origin.value!=='1 2 3'||c.origin.script!=='export function update(v){return v;}'||"
        "c.origin.scriptproperties.bias.user!=='slider'||c.flags[0]!==true||"
        "c.flags[1]!==null||c.flags[2]!==3||c.text!=='authored')throw Error('config');}"
        "export function update(v){"
        "const queries=['anchor',0,thisScene.getLayer('anchor')];"
        "for(const q of queries){const a=thisScene.getInitialLayerConfig(q);verify(a);"
        "a.nested.id=1;a.nested.parts[0].name='changed';a.flags.push(4);"
        "a.origin.scriptproperties.bias.value=99;"
        "const b=thisScene.getInitialLayerConfig(q);verify(b);"
        "if(a===b||a.nested===b.nested||a.flags===b.flags)throw Error('alias');}"
        "if(thisLayer.origin.x!==v||thisLayer.text!=='current')throw Error('current');"
        "for(const q of ['missing',-1,3,999])if(thisScene.getInitialLayerConfig(q)!==null)"
        "throw Error('missing');"
        "if(thisScene.getInitialLayerConfig('nil-config')!==null)throw Error('nil');"
        "let locked=false;try{thisScene.getInitialLayerConfig=()=>null;}catch(e){locked=true;}"
        "if(!locked)throw Error('getter writable');return 9;}";
    MWXSceneQuickJSOwner *read = owner(domain, read_source);
    if (read != NULL) {
        update(read, 9, 9, "three entrances, raw fields and fresh deep copies");
        publish(domain, 2, 21);
        update(read, 21, 9, "later current frame cannot mutate initial configuration");
    }
    char diagnostic[512] = {0};
    struct CallbackAttempt attempt = {.domain = domain};
    expect(mwx_scene_quickjs_domain_configure_storage(domain, callback_setter,
        &attempt, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "storage callback configured", diagnostic);
    expect(mwx_scene_quickjs_domain_set_storage_screen_identity(domain, "test", 4,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "storage screen", diagnostic);
    MWXSceneQuickJSOwner *callback = owner(domain,
        "export function update(v){localStorage.get('lock');"
        "if(thisScene.getInitialLayerConfig('callback-target')!==null)throw Error('injected');return 1;}");
    if (callback != NULL) update(callback, 1, 1, "host callback cannot inject catalog configuration");
    expect(attempt.count > 0 && attempt.result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "preparation-only setter rejects active callback", diagnostic);
    const char *dynamic_source =
        "function unavailable(layer){let caught=false;"
        "try{thisScene.getInitialLayerConfig(layer);}catch(e){"
        "caught=String(e).includes('unavailable');}if(!caught)throw Error('dynamic supported');}"
        "let layer;export function update(v){"
        "if(v===1||v===2){if(v===2&&(thisScene.getLayer('dynamic')!==null||"
        "thisScene.getInitialLayerConfig(layer)!==null))throw Error('discard');"
        "const input={id:901,name:'dynamic',text:'first',nested:{id:55,items:[2,3]}};"
        "layer=thisScene.createLayer(input);if(!layer||input.id!==901)throw Error('create');"
        "unavailable(layer);return v;}"
        "if(v===3){layer.text='current';unavailable(layer);return v;}"
        "if(v===4||v===6){if(layer.text!=='first')throw Error('restore');"
        "unavailable(layer);return v;}"
        "if(v===5||v===7){thisScene.destroyLayer(layer);"
        "if(thisScene.getInitialLayerConfig(layer)!==null)throw Error('destroy');return v;}"
        "if(v===8){if(thisScene.getInitialLayerConfig(layer)!==null||"
        "thisScene.getLayer('dynamic')!==null)throw Error('dead');return v;}return 0;}";
    MWXSceneQuickJSOwner *dynamic = owner(domain, dynamic_source);
    if (dynamic != NULL) {
        update(dynamic, 1, 1, "dynamic JSON create remains valid and getter rejects explicitly");
        mwx_scene_quickjs_owner_discard_layer_mutations(dynamic);
        update(dynamic, 2, 2, "create rollback invalidates old handle and allows retry");
        mwx_scene_quickjs_owner_commit_layer_mutations(dynamic);
        update(dynamic, 3, 3, "dynamic current text is writable despite unavailable configuration");
        mwx_scene_quickjs_owner_discard_layer_mutations(dynamic);
        update(dynamic, 4, 4, "discard restores dynamic current text");
        update(dynamic, 5, 5, "provisional destroy invalidates dynamic handle");
        mwx_scene_quickjs_owner_discard_layer_mutations(dynamic);
        update(dynamic, 6, 6, "destroy rollback restores dynamic handle");
        update(dynamic, 7, 7, "destroy may be committed");
        mwx_scene_quickjs_owner_commit_layer_mutations(dynamic);
        update(dynamic, 8, 8, "committed destroy leaves stale handle null");
    }
    MWXSceneQuickJSOwner *unsupported = owner(domain,
        "let reads=0;export function update(v){"
        "const cyclic={name:'cycle',text:'cycle'};cyclic.extra=cyclic;"
        "const indexed=[];Object.defineProperty(indexed,0,{get(){reads++;return 1;}});"
        "const hole=[];hole.length=1;"
        "Object.setPrototypeOf(hole,{get 0(){reads++;return 1;}});"
        "const inputs=[{name:'function',text:'function',extra:()=>1},"
        "{name:'accessor',text:'accessor',extra:{get value(){reads++;return 1;}}},"
        "{name:'indexed',text:'indexed',extra:indexed},"
        "{name:'hole',text:'hole',extra:hole},cyclic];"
        "for(const input of inputs){const layer=thisScene.createLayer(input);"
        "if(!layer)throw Error('creation regression');let unavailable=false;"
        "try{thisScene.getInitialLayerConfig(layer);}catch(e){"
        "unavailable=String(e).includes('unavailable');}"
        "if(!unavailable)throw Error('dynamic snapshot');}"
        "if(reads!==0)throw Error('executed unknown getter');return 5;}");
    if (unsupported != NULL) {
        update(unsupported, 1, 5, "unsupported extra values preserve create and never invoke getters");
        mwx_scene_quickjs_owner_commit_layer_mutations(unsupported);
    }
    mwx_scene_quickjs_owner_destroy(unsupported);
    mwx_scene_quickjs_owner_destroy(dynamic);
    mwx_scene_quickjs_owner_destroy(callback);
    mwx_scene_quickjs_owner_destroy(read);
    mwx_scene_quickjs_domain_destroy(domain);
    printf("{\"facts\":%d,\"failures\":%d}\n", facts, failures);
    return failures == 0 ? 0 : 1;
}
