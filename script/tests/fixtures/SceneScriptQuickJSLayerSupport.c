#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

int mwx_fixture_mutation(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t expected_effect,
    const char *expected_name,
    const char *label
) {
    char diagnostic[512] = {0};
    char name[128] = {0};
    uint32_t effect = 0;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_material_function_at(
        owner, index, &effect, name, sizeof(name), diagnostic, sizeof(diagnostic)
    );
    return mwx_fixture_check(
        result == MWX_SCENE_QUICKJS_OK
            && effect == expected_effect
            && strcmp(name, expected_name) == 0,
        label,
        diagnostic
    );
}


int mwx_fixture_configure_effects(
    MWXSceneQuickJSOwner *owner,
    uint32_t count,
    uint32_t named_index,
    const char *name,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_configure_effect_catalog(
        owner, count, diagnostic, sizeof(diagnostic)
    );
    if (result == MWX_SCENE_QUICKJS_OK && name != NULL) {
        result = mwx_scene_quickjs_owner_set_effect_name(
            owner, named_index, name, strlen(name), diagnostic, sizeof(diagnostic)
        );
    }
    return mwx_fixture_check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}


int mwx_fixture_configure_owner_layer(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_configure_layer_identity(
            owner, layer_id, diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}


int mwx_fixture_layer_mutation(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t expected_kind,
    int expected_dynamic,
    uint32_t expected_fields,
    int64_t expected_id,
    int expected_order,
    const char *expected_text,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSLayerMutation mwx_fixture_mutation = {0};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_layer_mutation_at(
        owner, index, &mwx_fixture_mutation, diagnostic, sizeof(diagnostic)
    );
    return mwx_fixture_check(
        result == MWX_SCENE_QUICKJS_OK
            && mwx_fixture_mutation.kind == expected_kind
            && mwx_fixture_mutation.dynamic == (uint32_t)expected_dynamic
            && mwx_fixture_mutation.fields == expected_fields
            && (expected_id == 0 || mwx_fixture_mutation.layer_id == expected_id)
            && mwx_fixture_mutation.order_index == expected_order
            && strcmp(mwx_fixture_mutation.text, expected_text) == 0,
        label,
        diagnostic
    );
}


int mwx_fixture_configure_layers(MWXSceneQuickJSDomain *domain) {
    char diagnostic[512] = {0};
    const double authored_zero[3] = {1, 2, 3};
    const double authored_day[3] = {10, 20, 30};
    const double current_day[3] = {4, 5, 6};
    const double anchor_size[2] = {100, 200};
    const double day_size[2] = {300, 400};
    const double anchor_world[16] = {
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 1, 0, 11, 22, 0, 1,
    };
    const double child_world[16] = {
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 1, 0, 33, 44, 0, 1,
    };
    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_configure_layer_catalog(
        domain, 2, 0, diagnostic, sizeof(diagnostic)
    );
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            domain, 0, 17, 0, 0,
            "anchor", strlen("anchor"), authored_zero,
            anchor_size,
            diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            domain, 1, 42, 1, 17,
            "C1", strlen("C1"), authored_day,
            day_size,
            diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_mutation_capabilities(
            domain, 0, 1, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_begin_layer_snapshot(
            domain, 1, 0, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        const double scale[3] = {1, 1, 1};
        const double angles[3] = {0, 0, 0};
        const double color[3] = {1, 1, 1};
        result = mwx_scene_quickjs_domain_update_layer_runtime_fields(
            domain, 0, scale, angles, 0, 1, 1, 0, 1,
            "", 0, "", 0, 32, color, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        const double scale[3] = {2, 3, 4};
        const double angles[3] = {0, 0, 0};
        const double color[3] = {1, 1, 1};
        result = mwx_scene_quickjs_domain_update_layer_runtime_fields(
            domain, 1, scale, angles, 0, 1, 1, 0, 0.75,
            "clock", strlen("clock"), "clock.ttf", strlen("clock.ttf"),
            48, color, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_origin(
            domain, 1, current_day, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_update_layer_world_transform(
            domain, 0, anchor_world, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_update_layer_world_transform(
            domain, 1, child_world, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_commit_layer_snapshot(
            domain, diagnostic, sizeof(diagnostic)
        );
    }
    return mwx_fixture_check(result == MWX_SCENE_QUICKJS_OK, "layer catalog", diagnostic);
}


int mwx_fixture_reject_nonfinite_layer_world_snapshot(
    MWXSceneQuickJSDomain *domain
) {
    char diagnostic[512] = {0};
    const double valid[16] = {
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 1, 0, 77, 88, 0, 1,
    };
    double invalid[16] = {
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 1, 0, 55, 66, 0, 1,
    };
    invalid[12] = NAN;
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_begin_layer_snapshot(
        domain, 3, 0, diagnostic, sizeof(diagnostic)
    );
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
            domain, 0, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
            domain, 1, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_update_layer_world_transform(
            domain, 0, valid, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_update_layer_world_transform(
            domain, 1, invalid, diagnostic, sizeof(diagnostic)
        );
    }
    int failure = mwx_fixture_check(
        result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "non-finite layer world transform rejected",
        diagnostic
    );
    mwx_scene_quickjs_domain_abort_layer_snapshot(domain);
    return failure;
}


int mwx_fixture_commit_layer_world_snapshot(MWXSceneQuickJSDomain *domain) {
    char diagnostic[512] = {0};
    const double anchor_world[16] = {
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 1, 0, 77, 88, 0, 1,
    };
    const double child_world[16] = {
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 1, 0, 55, 66, 0, 1,
    };
    const double current_day[3] = {4, 5, 6};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_begin_layer_snapshot(
        domain, 3, 0, diagnostic, sizeof(diagnostic)
    );
    for (uint32_t index = 0;
         index < 2 && result == MWX_SCENE_QUICKJS_OK; ++index) {
        result = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
            domain, index, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_update_layer_world_transform(
            domain, 0, anchor_world, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_update_layer_world_transform(
            domain, 1, child_world, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_origin(
            domain, 1, current_day, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_commit_layer_snapshot(
            domain, diagnostic, sizeof(diagnostic)
        );
    }
    return mwx_fixture_check(
        result == MWX_SCENE_QUICKJS_OK,
        "updated layer world snapshot",
        diagnostic
    );
}
