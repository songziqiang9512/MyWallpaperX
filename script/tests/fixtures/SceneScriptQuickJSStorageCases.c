#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static MWXSceneQuickJSStorageReadResult mwx_fixture_storage_read(
    void *opaque,
    MWXSceneQuickJSOwner *owner,
    const char *screen_identity,
    size_t screen_identity_length,
    uint32_t global_scope,
    const char *key,
    size_t key_length,
    char *json,
    size_t json_capacity,
    size_t *json_length
) {
    if (owner == NULL) return MWX_SCENE_QUICKJS_STORAGE_READ_ERROR;
    int *reads = opaque;
    *reads += 1;
    if (key_length == 4 && memcmp(key, "fail", 4) == 0) {
        return MWX_SCENE_QUICKJS_STORAGE_READ_ERROR;
    }
    const char *value = NULL;
    if (!global_scope && screen_identity_length == 8 &&
        memcmp(screen_identity, "screen-a", 8) == 0 &&
        key_length == 4 && memcmp(key, "base", 4) == 0) {
        value = "5";
    } else if (key_length == 7 && memcmp(key, "corrupt", 7) == 0) {
        value = "{";
    }
    if (value == NULL) return MWX_SCENE_QUICKJS_STORAGE_READ_MISSING;
    const size_t length = strlen(value);
    *json_length = length;
    if (json == NULL || json_capacity <= length) {
        return MWX_SCENE_QUICKJS_STORAGE_READ_BUFFER_TOO_SMALL;
    }
    memcpy(json, value, length + 1);
    return MWX_SCENE_QUICKJS_STORAGE_READ_FOUND;
}


void mwx_fixture_storage_cases(MWXSceneScriptQuickJSFixture *fixture) {
    fixture->storage_reads = 0;
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_domain_configure_storage(
            fixture->domain, mwx_fixture_storage_read, &fixture->storage_reads,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "localStorage provider configured", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_domain_set_storage_screen_identity(
            fixture->domain, "screen-a", 8, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "localStorage screen configured", fixture->diagnostic
    );
    const char *storage_source =
        "export function update(value){"
        "if(localStorage.get('base')!==5)throw new Error('baseline');"
        "if(localStorage.get('corrupt')!==undefined)throw new Error('corrupt');"
        "if(localStorage.delete('missing'))throw new Error('missing delete');"
        "localStorage.set('vec',{x:1,y:2,z:3});"
        "if(localStorage.get('vec').z!==3)throw new Error('staged read');"
        "localStorage.set('drop',9);localStorage.set('drop',undefined);"
        "if(localStorage.get('drop')!==undefined)throw new Error('undefined delete');"
        "localStorage.set('g',7,LOCATION_GLOBAL);"
        "if(!localStorage.delete('g',LOCATION_GLOBAL))throw new Error('global delete');"
        "localStorage.set('a',1);localStorage.clear();localStorage.set('b',2);"
        "if(localStorage.get('base')!==undefined)throw new Error('clear ordering');"
        "return localStorage.get('b');}";
    fixture->storage_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, storage_source, strlen(storage_source),
        47, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->storage_owner != NULL, "localStorage owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->storage_owner, 47, 0, MWX_SCENE_QUICKJS_OK, 2,
        "localStorage screen/global staged execution"
    );
    fixture->failures += mwx_fixture_check(
        fixture->storage_reads >= 3 &&
            mwx_scene_quickjs_owner_storage_mutation_count(fixture->storage_owner) == 8,
        "localStorage baseline and ordered mutation count", ""
    );
    MWXSceneQuickJSStorageMutation storage_mutation = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_storage_mutation_at(
            fixture->storage_owner, 0, &storage_mutation,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK &&
            storage_mutation.kind == MWX_SCENE_QUICKJS_STORAGE_SET &&
            storage_mutation.global_scope == 0 &&
            storage_mutation.screen_identity_length == 8 &&
            storage_mutation.key_length == 3 &&
            storage_mutation.json_length == 19,
        "localStorage typed mutation DTO", fixture->diagnostic
    );
    mwx_scene_quickjs_owner_discard_storage_transaction(fixture->storage_owner);
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_storage_mutation_count(fixture->storage_owner) == 0,
        "localStorage transaction discarded", ""
    );

    const char *storage_throw_source =
        "export function update(value){localStorage.set('x',1);throw new Error('rollback');}";
    fixture->storage_throw = mwx_scene_quickjs_owner_create(
        fixture->domain, storage_throw_source, strlen(storage_throw_source),
        48, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->storage_throw != NULL, "localStorage throw compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->storage_throw, 48, 0, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "localStorage callback failure remains staged"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_storage_mutation_count(fixture->storage_throw) == 1,
        "localStorage failed callback did not publish", ""
    );
    mwx_scene_quickjs_owner_discard_storage_transaction(fixture->storage_throw);

    const char *value_storage_source =
        "export function update(value){localStorage.set('x',1,LOCATION_GLOBAL);return value;}";
    fixture->value_storage =
        mwx_scene_quickjs_owner_create_value_only_with_budget(
            fixture->domain, value_storage_source, strlen(value_storage_source),
            49, 1000000, &fixture->value_only_create_result,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(fixture->value_storage != NULL, "value localStorage compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_bool(
        fixture->value_storage, 49, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "value-only localStorage write rejected"
    );

    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_domain_set_storage_screen_identity(
            fixture->domain, NULL, 0, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "localStorage screen cleared", fixture->diagnostic
    );
    const char *missing_screen_source =
        "export function update(value){return localStorage.get('base')||value;}";
    fixture->missing_screen_storage = mwx_scene_quickjs_owner_create(
        fixture->domain, missing_screen_source, strlen(missing_screen_source),
        50, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->missing_screen_storage != NULL, "missing screen localStorage compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->missing_screen_storage, 50, 3, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "screen localStorage rejects ambiguous surface"
    );

    const char *storage_budget_source =
        "export function update(value){for(let i=0;i<65;i++)"
        "localStorage.set(String(i),i,LOCATION_GLOBAL);return value;}";
    fixture->storage_budget = mwx_scene_quickjs_owner_create(
        fixture->domain, storage_budget_source, strlen(storage_budget_source),
        51, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->storage_budget != NULL, "localStorage budget compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->storage_budget, 51, 3, MWX_SCENE_QUICKJS_MUTATION_OVERFLOW, 0,
        "localStorage mutation budget is sticky"
    );
    mwx_scene_quickjs_owner_discard_storage_transaction(fixture->storage_budget);

}
