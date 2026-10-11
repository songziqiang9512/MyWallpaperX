#include "SceneQuickJS.h"
#include <stdio.h>
#include <string.h>

static int perspective_failures;
static char perspective_diagnostic[512];

static void perspective_check(int condition, const char *label) {
    if (condition) return;
    fprintf(stderr, "FAIL perspective %s: %s\n", label, perspective_diagnostic);
    perspective_failures++;
}

static MWXSceneQuickJSDomain *perspective_domain(uint32_t native) {
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        16 * 1024 * 1024, 512 * 1024, 100000,
        perspective_diagnostic, sizeof(perspective_diagnostic));
    perspective_check(domain != NULL, "domain");
    if (domain == NULL) return NULL;
    perspective_check(mwx_scene_quickjs_domain_configure_layer_catalog(domain, 1,
        native, perspective_diagnostic, sizeof(perspective_diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "catalog");
    const double origin[3] = {160, 90, 120}, size[2] = {100, 60};
    perspective_check(mwx_scene_quickjs_domain_set_layer_descriptor(domain, 0, 73,
        0, 0, "UnseenCanvas", 12, origin, size,
        perspective_diagnostic, sizeof(perspective_diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "renamed layer");
    return domain;
}

static MWXSceneQuickJSOwner *perspective_owner(MWXSceneQuickJSDomain *domain,
                                               const char *source) {
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(domain,
        source, strlen(source), 19, perspective_diagnostic, sizeof(perspective_diagnostic));
    perspective_check(owner != NULL, "owner");
    if (owner == NULL) return NULL;
    perspective_check(mwx_scene_quickjs_owner_configure_layer_identity(owner, 73,
        perspective_diagnostic, sizeof(perspective_diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "identity");
    return owner;
}

static void perspective_update(MWXSceneQuickJSOwner *owner, double input,
                               MWXSceneQuickJSResult expected) {
    MWXSceneQuickJSFrameInput frame = {.runtime = input, .frame_time = .1};
    double output = -1;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_update_scalar(owner,
        19, input, &frame, &output, perspective_diagnostic, sizeof(perspective_diagnostic));
    perspective_check(result == expected, "callback result");
    if (expected == MWX_SCENE_QUICKJS_OK)
        perspective_check(output == input, "value unchanged");
}

static MWXSceneQuickJSLayerMutation perspective_mutation(MWXSceneQuickJSOwner *owner) {
    MWXSceneQuickJSLayerMutation mutation = {0};
    perspective_check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 1,
        "one existing journal record");
    perspective_check(mwx_scene_quickjs_owner_layer_mutation_at(owner, 0, &mutation,
        perspective_diagnostic, sizeof(perspective_diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "typed ABI");
    return mutation;
}

static void perspective_publish(MWXSceneQuickJSDomain *domain, uint64_t generation,
                                uint32_t native, uint32_t explicit_value) {
    const double scale[3] = {1, 1, 1}, angles[3] = {0, 0, 0}, color[3] = {1, 1, 1};
    perspective_check(mwx_scene_quickjs_domain_begin_layer_snapshot(domain,
        generation, native, perspective_diagnostic, sizeof(perspective_diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "begin default snapshot");
    perspective_check(mwx_scene_quickjs_domain_update_layer_runtime_fields(domain, 0,
        scale, angles, 0, 1, 1, explicit_value, 1, "", 0, "", 0, 32, color,
        perspective_diagnostic, sizeof(perspective_diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "snapshot preserves inherit sentinel");
    perspective_check(mwx_scene_quickjs_domain_commit_layer_snapshot(domain,
        perspective_diagnostic, sizeof(perspective_diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "commit default snapshot");
}

int mwx_test_layer_perspective_cases(void) {
    perspective_failures = 0;
    MWXSceneQuickJSDomain *domain = perspective_domain(0);
    if (domain == NULL) return 1;
    MWXSceneQuickJSOwner *owner = perspective_owner(domain,
        "export function init(v){let renamed=thisScene.getLayer('UnseenCanvas');"
        "if(renamed.perspective!==false)throw Error('default');"
        "renamed.perspective=1;renamed.perspective='false';"
        "if(renamed.perspective!==false)throw Error('nonbool false');"
        "const alias=renamed;alias.perspective=(3>2);alias.perspective=0;"
        "if(thisLayer.perspective!==true||thisScene.getLayer(0).perspective!==true)"
        "throw Error('same callback');return v;}"
        "export function update(v){if(thisLayer.perspective!==true)"
        "throw Error('init retained');return v;}");
    perspective_update(owner, 1, MWX_SCENE_QUICKJS_OK);
    MWXSceneQuickJSLayerMutation mutation = perspective_mutation(owner);
    perspective_check(!mutation.dynamic && mutation.perspective == 1 &&
        mutation.fields == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE,
        "authored Boolean field");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    owner = perspective_owner(domain,
        "export function update(v){if(thisLayer.perspective!==false)throw Error('discard');"
        "thisLayer.perspective=true;throw Error('own failure');}");
    perspective_update(owner, 2, MWX_SCENE_QUICKJS_EXCEPTION);
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    owner = perspective_owner(domain,
        "let cloned;export function init(v){cloned=thisScene.createLayer({"
        "name:'ShiftedAsset',image:'models/unseen/relabelled.json'});return v;}"
        "export function update(v){if(v===1){if(cloned.perspective!==false)throw Error('inherit');"
        "cloned.perspective=Boolean(1);cloned.perspective='false';}else{"
        "if(cloned.perspective!==true)throw Error('committed');cloned.perspective=false;}"
        "return v;}");
    perspective_update(owner, 1, MWX_SCENE_QUICKJS_OK);
    mutation = perspective_mutation(owner);
    perspective_check(mutation.dynamic && mutation.fields == 0 && mutation.perspective == 1 &&
        strcmp(mutation.asset_path, "models/unseen/relabelled.json") == 0,
        "renamed dynamic resource receives same setter");
    mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    perspective_update(owner, 2, MWX_SCENE_QUICKJS_OK);
    perspective_check(perspective_mutation(owner).perspective == 0, "dynamic false write");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    perspective_update(owner, 3, MWX_SCENE_QUICKJS_OK);
    perspective_check(perspective_mutation(owner).perspective == 0,
        "dynamic rollback retains true before next false write");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);

    domain = perspective_domain(0);
    owner = perspective_owner(domain,
        "export function update(v){thisLayer.perspective=false;return v;}");
    perspective_update(owner, 5, MWX_SCENE_QUICKJS_OK);
    perspective_check(perspective_mutation(owner).perspective == 0,
        "first write of inherited default creates explicit override");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    perspective_publish(domain, 1, 0, 0);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    owner = perspective_owner(domain,
        "export function update(v){thisLayer.perspective=false;thisLayer.perspective=1;"
        "if(thisLayer.perspective!==false)throw Error('explicit no-op');return v;}");
    perspective_update(owner, 6, MWX_SCENE_QUICKJS_OK);
    perspective_check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0,
        "same explicit Boolean and non-Boolean values produce no DTO");
    mwx_scene_quickjs_owner_destroy(owner);
    perspective_publish(domain, 2, 1, 2);
    owner = perspective_owner(domain,
        "export function update(v){if(thisLayer.perspective!==true)throw Error('camera layer default');"
        "thisLayer.perspective=false;return v;}");
    perspective_update(owner, 7, MWX_SCENE_QUICKJS_OK);
    perspective_check(perspective_mutation(owner).perspective == 0,
        "active native default can be explicitly disabled");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    perspective_check(mwx_scene_quickjs_domain_rollback_layer_snapshot(domain), "rollback camera default");
    owner = perspective_owner(domain,
        "export function update(v){if(thisLayer.perspective!==false)throw Error('rolled back camera');return v;}");
    perspective_update(owner, 8, MWX_SCENE_QUICKJS_OK);
    perspective_check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0,
        "rollback restores default and explicit mirror in one transaction");
    mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);

    domain = perspective_domain(1);
    if (domain == NULL) return perspective_failures + 1;
    owner = perspective_owner(domain,
        "export function update(v){const inherited=thisScene.createLayer({text:'unseen'});"
        "if(thisLayer.perspective!==true||inherited.perspective!==true)throw Error('native default');"
        "inherited.perspective=false;if(inherited.perspective!==false)throw Error('explicit');"
        "return v;}");
    perspective_update(owner, 4, MWX_SCENE_QUICKJS_OK);
    perspective_check(perspective_mutation(owner).perspective == 0,
        "native inherited policy is overridden only by Boolean write");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);
    return perspective_failures;
}
