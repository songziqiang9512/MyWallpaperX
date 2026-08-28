#!/usr/bin/env python3

"""Contract gate for the QuickJS-NG SceneScript typed owners."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_SCRIPT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript"
QUICKJS = SCENE_SCRIPT / "QuickJSNG"

HARNESS = r'''
#include "SceneQuickJS.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int check(int condition, const char *label, const char *diagnostic) {
    if (condition) return 0;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic ? diagnostic : "");
    return 1;
}

static int update(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    double output = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_scalar(
        owner, generation, input, &frame, &output, diagnostic, sizeof(diagnostic)
    );
    return check(
        actual == expected
            && (expected != MWX_SCENE_QUICKJS_OK || output == expected_output),
        label,
        diagnostic
    );
}

static int media_thumbnail(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    int has_thumbnail,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaThumbnailEvent event = {
        .has_thumbnail = has_thumbnail ? 1 : 0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_thumbnail(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
}

static int media_playback(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t state,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaPlaybackEvent event = {.state = state};
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_playback(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
}

static int media_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *title,
    const char *artist,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaPropertiesEvent event = {
        .title = title,
        .title_length = strlen(title),
        .artist = artist,
        .artist_length = strlen(artist),
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_properties(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
}

static int update_string(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *input,
    MWXSceneQuickJSResult expected,
    const char *expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    char output[65537] = {0};
    size_t output_length = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_string(
        owner, generation, input, strlen(input), &frame, "{}", 2,
        output, sizeof(output), &output_length, diagnostic, sizeof(diagnostic)
    );
    return check(
        actual == expected && (
            expected != MWX_SCENE_QUICKJS_OK || (
                output_length == strlen(expected_output) &&
                memcmp(output, expected_output, output_length) == 0
            )
        ),
        label,
        diagnostic
    );
}

static int update_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const double input[3],
    const char *script_properties,
    const char *user_properties,
    MWXSceneQuickJSResult expected,
    const double expected_output[3],
    const char *label
) {
    char diagnostic[512] = {0};
    double output[3] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_vec3(
        owner, generation, input, &frame,
        script_properties, strlen(script_properties),
        user_properties, strlen(user_properties),
        output, diagnostic, sizeof(diagnostic)
    );
    return check(
        actual == expected && (
            expected != MWX_SCENE_QUICKJS_OK || (
                output[0] == expected_output[0] &&
                output[1] == expected_output[1] &&
                output[2] == expected_output[2]
            )
        ),
        label,
        diagnostic
    );
}

static int mutation(
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
    return check(
        result == MWX_SCENE_QUICKJS_OK
            && effect == expected_effect
            && strcmp(name, expected_name) == 0,
        label,
        diagnostic
    );
}

static int animation_command(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSAnimationCommand expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSAnimationCommand command = 0;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_animation_command_at(
        owner, index, &command, diagnostic, sizeof(diagnostic)
    );
    return check(
        result == MWX_SCENE_QUICKJS_OK && command == expected,
        label,
        diagnostic
    );
}

static int configure_effects(
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
    return check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}

static int configure_layers(MWXSceneQuickJSDomain *domain) {
    char diagnostic[512] = {0};
    const double authored_zero[3] = {1, 2, 3};
    const double authored_day[3] = {10, 20, 30};
    const double current_day[3] = {4, 5, 6};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_configure_layer_catalog(
        domain, 2, diagnostic, sizeof(diagnostic)
    );
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            domain, 0, 17, "anchor", strlen("anchor"), authored_zero,
            diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            domain, 1, 42, "C1", strlen("C1"), authored_day,
            diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_begin_layer_snapshot(
            domain, 1, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_origin(
            domain, 1, current_day, diagnostic, sizeof(diagnostic)
        );
    }
    return check(result == MWX_SCENE_QUICKJS_OK, "layer catalog", diagnostic);
}

int main(void) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
    );
    if (check(domain != NULL, "domain", diagnostic)) return 1;

    int failures = 0;
    failures += configure_layers(domain);
    MWXSceneQuickJSOwner *positive = mwx_scene_quickjs_owner_create(
        domain,
        "'use strict';\n"
        "export let __workshopId = 'contract';\n"
        "export function init(value) { return value + 1; }\n"
        "export function update(value) {\n"
        "  if (thisLayer.getEffectCount() !== 3) throw new Error('effect count');\n"
        "  const effect = thisLayer.getEffect('history');\n"
        "  if (effect.name !== 'history') throw new Error('effect name');\n"
        "  effect.executeMaterialFunction('clearHistory');\n"
        "  return value * 2;\n"
        "}",
        strlen(
            "'use strict';\n"
            "export let __workshopId = 'contract';\n"
            "export function init(value) { return value + 1; }\n"
            "export function update(value) {\n"
            "  if (thisLayer.getEffectCount() !== 3) throw new Error('effect count');\n"
            "  const effect = thisLayer.getEffect('history');\n"
            "  if (effect.name !== 'history') throw new Error('effect name');\n"
            "  effect.executeMaterialFunction('clearHistory');\n"
            "  return value * 2;\n"
            "}"
        ),
        1,
        diagnostic,
        sizeof(diagnostic)
    );
    failures += check(positive != NULL, "positive compile", diagnostic);
    failures += configure_effects(positive, 3, 2, "history", "positive effect catalog");
    failures += update(
        positive, 1, 3, MWX_SCENE_QUICKJS_OK, 8, "init/update"
    );
    failures += check(
        mwx_scene_quickjs_owner_material_function_count(positive) == 1,
        "mutation count",
        ""
    );
    failures += mutation(positive, 0, 2, "clearHistory", "mutation identity");

    MWXSceneQuickJSOwner *cross_owner = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) {\n"
        "  thisLayer.getEffect(9).executeMaterialFunction('crossOwner');\n"
        "  return value;\n"
        "}",
        strlen(
            "export function update(value) {\n"
            "  thisLayer.getEffect(9).executeMaterialFunction('crossOwner');\n"
            "  return value;\n"
            "}"
        ),
        10, diagnostic, sizeof(diagnostic)
    );
    failures += check(cross_owner != NULL, "cross-owner compile", diagnostic);
    failures += configure_effects(cross_owner, 10, 0, NULL, "cross-owner catalog");
    failures += update(
        cross_owner, 10, 3, MWX_SCENE_QUICKJS_OK, 3, "cross-owner callback"
    );
    failures += check(
        mwx_scene_quickjs_owner_material_function_count(cross_owner) == 1,
        "cross-owner mutation count",
        ""
    );
    failures += update(
        positive, 1, 7, MWX_SCENE_QUICKJS_OK, 14, "second callback"
    );
    failures += mutation(positive, 0, 2, "clearHistory", "cross-owner isolation");
    failures += check(
        mwx_scene_quickjs_owner_material_function_count(positive) == 1,
        "mutation reset",
        ""
    );

    MWXSceneQuickJSOwner *isolated = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) { return value + 10; }",
        strlen("export function update(value) { return value + 10; }"),
        2,
        diagnostic,
        sizeof(diagnostic)
    );
    failures += check(isolated != NULL, "owner isolation compile", diagnostic);
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13, "owner isolation"
    );

    MWXSceneQuickJSOwner *metadata_only = mwx_scene_quickjs_owner_create(
        domain,
        "export let __workshopId = 'metadata-only';",
        strlen("export let __workshopId = 'metadata-only';"),
        7, diagnostic, sizeof(diagnostic)
    );
    failures += check(metadata_only != NULL, "export metadata compile", diagnostic);
    failures += update(
        metadata_only, 7, 5, MWX_SCENE_QUICKJS_OK, 5, "missing callbacks preserve input"
    );

    MWXSceneQuickJSOwner *time_of_day = mwx_scene_quickjs_owner_create(
        domain,
        "import * as WEMath from 'WEMath';\n"
        "'use strict';\n"
        "export function update(value) {\n"
        "  if (engine.frametime <= 0 || engine.runtime !== 2) return -1;\n"
        "  return Math.max(\n"
        "    WEMath.smoothStep(7 / 24, 6.996 / 24, engine.timeOfDay),\n"
        "    WEMath.smoothStep(17.996 / 24, 18 / 24, engine.timeOfDay)\n"
        "  );\n"
        "}",
        strlen(
            "import * as WEMath from 'WEMath';\n"
            "'use strict';\n"
            "export function update(value) {\n"
            "  if (engine.frametime <= 0 || engine.runtime !== 2) return -1;\n"
            "  return Math.max(\n"
            "    WEMath.smoothStep(7 / 24, 6.996 / 24, engine.timeOfDay),\n"
            "    WEMath.smoothStep(17.996 / 24, 18 / 24, engine.timeOfDay)\n"
            "  );\n"
            "}"
        ),
        11, diagnostic, sizeof(diagnostic)
    );
    failures += check(time_of_day != NULL, "WEMath compile", diagnostic);
    failures += update(
        time_of_day, 11, 0, MWX_SCENE_QUICKJS_OK, 1,
        "WEMath engine.timeOfDay"
    );

    const char *scalar_user_source =
        "export function update(value) { return engine.userProperties.live; }";
    MWXSceneQuickJSOwner *scalar_user = mwx_scene_quickjs_owner_create(
        domain, scalar_user_source, strlen(scalar_user_source),
        15, diagnostic, sizeof(diagnostic)
    );
    failures += check(scalar_user != NULL, "scalar user properties compile", diagnostic);
    double scalar_user_output = 0;
    MWXSceneQuickJSFrameInput scalar_user_frame = {
        .time_of_day = 0.25, .frame_time = 1.0 / 60.0, .runtime = 2.0,
    };
    MWXSceneQuickJSResult scalar_user_result =
        mwx_scene_quickjs_owner_update_scalar_with_user_properties(
            scalar_user, 15, 0, &scalar_user_frame,
            "{\"live\":6}", strlen("{\"live\":6}"),
            &scalar_user_output, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        scalar_user_result == MWX_SCENE_QUICKJS_OK && scalar_user_output == 6,
        "scalar engine.userProperties",
        diagnostic
    );

    const char *vec3_source =
        "'use strict';\n"
        "export var scriptProperties = createScriptProperties()\n"
        "  .addSlider({name:'x',label:'X',value:1,min:0,max:10,integer:false})\n"
        "  .finish();\n"
        "export function update(value) {\n"
        "  value.x = scriptProperties.x;\n"
        "  value.y = engine.userProperties.live;\n"
        "  value.z = engine.userProperties.tint.x;\n"
        "  return value;\n"
        "}";
    MWXSceneQuickJSOwner *vec3 = mwx_scene_quickjs_owner_create(
        domain, vec3_source, strlen(vec3_source),
        13, diagnostic, sizeof(diagnostic)
    );
    failures += check(vec3 != NULL, "Vec3 compile", diagnostic);
    const double vec3_input[3] = {1, 2, 3};
    const double vec3_expected[3] = {4, 5, 0.25};
    failures += update_vec3(
        vec3, 13, vec3_input,
        "{\"x\":4}",
        "{\"live\":5,\"tint\":{\"x\":0.25,\"y\":0.5,\"z\":1}}",
        MWX_SCENE_QUICKJS_OK, vec3_expected,
        "Vec3/scriptProperties/engine.userProperties"
    );

    const char *immutable_user_source =
        "'use strict'; export function update(value) {"
        "engine.userProperties.live = 9; return value; }";
    MWXSceneQuickJSOwner *immutable_user = mwx_scene_quickjs_owner_create(
        domain, immutable_user_source, strlen(immutable_user_source),
        14, diagnostic, sizeof(diagnostic)
    );
    failures += check(immutable_user != NULL, "immutable user compile", diagnostic);
    failures += update_vec3(
        immutable_user, 14, vec3_input, "", "{\"live\":5}",
        MWX_SCENE_QUICKJS_EXCEPTION, vec3_input,
        "engine.userProperties is immutable"
    );

    MWXSceneQuickJSOwner *immutable_frame = mwx_scene_quickjs_owner_create(
        domain,
        "'use strict';\n"
        "export function update(value) {\n"
        "  engine.timeOfDay = 0.75;\n"
        "  return value;\n"
        "}",
        strlen(
            "'use strict';\n"
            "export function update(value) {\n"
            "  engine.timeOfDay = 0.75;\n"
            "  return value;\n"
            "}"
        ),
        12, diagnostic, sizeof(diagnostic)
    );
    failures += check(immutable_frame != NULL, "immutable frame compile", diagnostic);
    failures += update(
        immutable_frame, 12, 0, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "engine frame is immutable"
    );

    MWXSceneQuickJSOwner *unresolved_import = mwx_scene_quickjs_owner_create(
        domain,
        "import * as Unsupported from 'Unsupported';\n"
        "export function update(value) { return Unsupported.abs(value); }",
        strlen(
            "import * as Unsupported from 'Unsupported';\n"
            "export function update(value) { return Unsupported.abs(value); }"
        ),
        8, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        unresolved_import == NULL,
        "unresolved import fails closed",
        diagnostic
    );

    MWXSceneQuickJSOwner *compile_error = mwx_scene_quickjs_owner_create(
        domain, "function update(value) {", strlen("function update(value) {"),
        3, diagnostic, sizeof(diagnostic)
    );
    failures += check(compile_error == NULL, "compile exception", diagnostic);

    MWXSceneQuickJSOwner *callback_error = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) { throw new Error('callback'); }",
        strlen("export function update(value) { throw new Error('callback'); }"),
        4, diagnostic, sizeof(diagnostic)
    );
    failures += check(callback_error != NULL, "callback compile", diagnostic);
    failures += update(
        callback_error, 4, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "callback exception"
    );
    failures += update(
        callback_error, 4, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "callback disabled after exception"
    );

    MWXSceneQuickJSOwner *bad_return = mwx_scene_quickjs_owner_create(
        domain, "export function update(value) { return {}; }",
        strlen("export function update(value) { return {}; }"),
        5, diagnostic, sizeof(diagnostic)
    );
    failures += check(bad_return != NULL, "bad return compile", diagnostic);
    failures += update(
        bad_return, 5, 1, MWX_SCENE_QUICKJS_BAD_RETURN, 0, "bad return"
    );

    MWXSceneQuickJSOwner *budget = mwx_scene_quickjs_owner_create(
        domain, "export function update(value) { while (true) { value = value; }; }",
        strlen("export function update(value) { while (true) { value = value; }; }"),
        6, diagnostic, sizeof(diagnostic)
    );
    failures += check(budget != NULL, "budget compile", diagnostic);
    mwx_scene_quickjs_domain_reset_budget(domain, 32);
    failures += update(
        budget, 6, 1, MWX_SCENE_QUICKJS_BUDGET_EXCEEDED, 0, "interrupt budget"
    );

    MWXSceneQuickJSOwner *mutation_overflow = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) {\n"
        "  for (let i = 0; i < 17; ++i) {\n"
        "    thisLayer.getEffect(i).executeMaterialFunction('clear');\n"
        "  }\n"
        "  return value;\n"
        "}",
        strlen(
            "export function update(value) {\n"
            "  for (let i = 0; i < 17; ++i) {\n"
            "    thisLayer.getEffect(i).executeMaterialFunction('clear');\n"
            "  }\n"
            "  return value;\n"
            "}"
        ),
        9, diagnostic, sizeof(diagnostic)
    );
    failures += check(mutation_overflow != NULL, "mutation overflow compile", diagnostic);
    failures += configure_effects(
        mutation_overflow, 17, 0, NULL, "mutation overflow catalog"
    );
    failures += update(
        mutation_overflow, 9, 1, MWX_SCENE_QUICKJS_MUTATION_OVERFLOW, 0,
        "mutation overflow"
    );

    MWXSceneQuickJSOwner *invalid_effect = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) { thisLayer.getEffect('missing'); return value; }",
        strlen("export function update(value) { thisLayer.getEffect('missing'); return value; }"),
        11, diagnostic, sizeof(diagnostic)
    );
    failures += check(invalid_effect != NULL, "invalid effect compile", diagnostic);
    failures += configure_effects(
        invalid_effect, 1, 0, "known", "invalid effect catalog"
    );
    failures += update(
        invalid_effect, 11, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "invalid effect rejected at handle lookup"
    );

    MWXSceneQuickJSOwner *immutable_handle = mwx_scene_quickjs_owner_create(
        domain,
        "'use strict'; export function update(value) { thisLayer.getEffect = null; return value; }",
        strlen("'use strict'; export function update(value) { thisLayer.getEffect = null; return value; }"),
        12, diagnostic, sizeof(diagnostic)
    );
    failures += check(immutable_handle != NULL, "immutable handle compile", diagnostic);
    failures += configure_effects(
        immutable_handle, 1, 0, "known", "immutable handle catalog"
    );
    failures += update(
        immutable_handle, 12, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "immutable handle method"
    );

    const char *layer_source =
        "export function update(value) {"
        "const day=1; const layer=thisScene.getLayer(`C${day}`);"
        "if(thisScene.getLayerCount()!==2||thisScene.getLayer(1).id!==42||"
        "thisScene.getLayerByID(42).name!=='C1')throw new Error('layer identity');"
        "return layer.origin.copy().add(new Vec3(1,1,1));}";
    MWXSceneQuickJSOwner *layer_owner = mwx_scene_quickjs_owner_create(
        domain, layer_source, strlen(layer_source),
        13, diagnostic, sizeof(diagnostic)
    );
    failures += check(layer_owner != NULL, "layer handle compile", diagnostic);
    const double layer_input[3] = {0, 0, 0};
    const double layer_output[3] = {5, 6, 7};
    failures += update_vec3(
        layer_owner, 13, layer_input, "", "{}", MWX_SCENE_QUICKJS_OK,
        layer_output, "layer current origin"
    );

    const char *stale_layer_source =
        "let saved; export function update(value){"
        "if(!saved){saved=thisScene.getLayer('C1');return saved.origin;}"
        "return saved.origin;}";
    MWXSceneQuickJSOwner *stale_layer = mwx_scene_quickjs_owner_create(
        domain, stale_layer_source, strlen(stale_layer_source),
        14, diagnostic, sizeof(diagnostic)
    );
    failures += check(stale_layer != NULL, "stale layer compile", diagnostic);
    const double current_layer[3] = {4, 5, 6};
    failures += update_vec3(
        stale_layer, 14, layer_input, "", "{}", MWX_SCENE_QUICKJS_OK,
        current_layer, "layer handle callback scope"
    );
    failures += update_vec3(
        stale_layer, 14, layer_input, "", "{}", MWX_SCENE_QUICKJS_EXCEPTION,
        layer_input, "stale layer handle rejected"
    );

    const char *stale_effect_source =
        "let saved; export function update(value){"
        "if(!saved){saved=thisLayer.getEffect(0);return value;}"
        "saved.executeMaterialFunction('stale');return value;}";
    MWXSceneQuickJSOwner *stale_effect = mwx_scene_quickjs_owner_create(
        domain, stale_effect_source, strlen(stale_effect_source),
        15, diagnostic, sizeof(diagnostic)
    );
    failures += check(stale_effect != NULL, "stale effect compile", diagnostic);
    failures += configure_effects(
        stale_effect, 1, 0, "known", "stale effect catalog"
    );
    failures += update(
        stale_effect, 15, 1, MWX_SCENE_QUICKJS_OK, 1,
        "effect handle callback scope"
    );
    failures += update(
        stale_effect, 15, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "stale effect handle rejected"
    );

    const char *animation_source =
        "export function init(value){thisObject.getAnimation().play();return value;}";
    MWXSceneQuickJSOwner *animation_owner = mwx_scene_quickjs_owner_create(
        domain, animation_source, strlen(animation_source),
        16, diagnostic, sizeof(diagnostic)
    );
    failures += check(animation_owner != NULL, "animation handle compile", diagnostic);
    failures += check(
        mwx_scene_quickjs_owner_configure_current_animation(
            animation_owner, 1, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "animation handle configure", diagnostic
    );
    failures += update(
        animation_owner, 16, 1, MWX_SCENE_QUICKJS_OK, 1,
        "animation play callback"
    );
    failures += check(
        mwx_scene_quickjs_owner_animation_command_count(animation_owner) == 1,
        "animation command count", diagnostic
    );
    failures += animation_command(
        animation_owner, 0, MWX_SCENE_QUICKJS_ANIMATION_PLAY,
        "animation play mutation"
    );

    const char *stale_animation_source =
        "let saved;export function update(value){"
        "if(!saved){saved=thisObject.getAnimation();return value;}"
        "saved.pause();return value;}";
    MWXSceneQuickJSOwner *stale_animation = mwx_scene_quickjs_owner_create(
        domain, stale_animation_source, strlen(stale_animation_source),
        17, diagnostic, sizeof(diagnostic)
    );
    failures += check(stale_animation != NULL, "stale animation compile", diagnostic);
    failures += check(
        mwx_scene_quickjs_owner_configure_current_animation(
            stale_animation, 1, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "stale animation configure", diagnostic
    );
    failures += update(
        stale_animation, 17, 1, MWX_SCENE_QUICKJS_OK, 1,
        "animation handle callback scope"
    );
    failures += update(
        stale_animation, 17, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "stale animation handle rejected"
    );

    const char *named_animation_source =
        "export function update(value){thisObject.getAnimation('named');return value;}";
    MWXSceneQuickJSOwner *named_animation = mwx_scene_quickjs_owner_create(
        domain, named_animation_source, strlen(named_animation_source),
        18, diagnostic, sizeof(diagnostic)
    );
    failures += check(named_animation != NULL, "named animation compile", diagnostic);
    failures += check(
        mwx_scene_quickjs_owner_configure_current_animation(
            named_animation, 1, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "named animation configure", diagnostic
    );
    failures += update(
        named_animation, 18, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "named animation lookup rejected"
    );

    const char *media_animation_source =
        "export function mediaThumbnailChanged(event){"
        "if(event.hasThumbnail){const a=thisObject.getAnimation();a.stop();a.play();}}";
    MWXSceneQuickJSOwner *media_animation = mwx_scene_quickjs_owner_create(
        domain, media_animation_source, strlen(media_animation_source),
        19, diagnostic, sizeof(diagnostic)
    );
    failures += check(media_animation != NULL, "media animation compile", diagnostic);
    failures += check(
        mwx_scene_quickjs_owner_configure_current_animation(
            media_animation, 1, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "media animation configure", diagnostic
    );
    failures += update(
        media_animation, 19, 1, MWX_SCENE_QUICKJS_OK, 1,
        "media animation initialize"
    );
    failures += media_thumbnail(
        media_animation, 19, 0, MWX_SCENE_QUICKJS_OK,
        "media thumbnail absent event"
    );
    failures += check(
        mwx_scene_quickjs_owner_animation_command_count(media_animation) == 0,
        "media absent command count", diagnostic
    );
    failures += media_thumbnail(
        media_animation, 19, 1, MWX_SCENE_QUICKJS_OK,
        "media thumbnail present event"
    );
    failures += check(
        mwx_scene_quickjs_owner_animation_command_count(media_animation) == 2,
        "media present command count", diagnostic
    );
    failures += animation_command(
        media_animation, 0, MWX_SCENE_QUICKJS_ANIMATION_STOP,
        "media animation stop mutation"
    );
    failures += animation_command(
        media_animation, 1, MWX_SCENE_QUICKJS_ANIMATION_PLAY,
        "media animation play mutation"
    );

    const char *media_playback_source =
        "let state=MediaPlaybackEvent.PLAYBACK_STOPPED;"
        "export function mediaPlaybackChanged(event){state=event.state;}"
        "export function update(value){"
        "if(MediaPlaybackEvent.PLAYBACK_PLAYING!==1||"
        "MediaPlaybackEvent.PLAYBACK_PAUSED!==2)throw new Error('enum');"
        "return value+state;}";
    MWXSceneQuickJSOwner *media_playback_owner = mwx_scene_quickjs_owner_create(
        domain, media_playback_source, strlen(media_playback_source),
        20, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        media_playback_owner != NULL, "media playback compile", diagnostic
    );
    failures += update(
        media_playback_owner, 20, 3, MWX_SCENE_QUICKJS_OK, 3,
        "media playback stopped initial state"
    );
    failures += media_playback(
        media_playback_owner, 20, 1, MWX_SCENE_QUICKJS_OK,
        "media playback playing event"
    );
    failures += update(
        media_playback_owner, 20, 3, MWX_SCENE_QUICKJS_OK, 4,
        "media playback event updates same owner state"
    );
    failures += media_playback(
        media_playback_owner, 20, 3, MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "invalid media playback state"
    );
    failures += media_playback(
        media_playback_owner, 21, 2, MWX_SCENE_QUICKJS_STALE_OWNER,
        "stale media playback owner"
    );

    const char *immutable_media_playback_source =
        "'use strict';export function update(value){"
        "MediaPlaybackEvent.PLAYBACK_STOPPED=9;return value;}";
    MWXSceneQuickJSOwner *immutable_media_playback =
        mwx_scene_quickjs_owner_create(
            domain, immutable_media_playback_source,
            strlen(immutable_media_playback_source),
            21, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        immutable_media_playback != NULL,
        "immutable media playback compile", diagnostic
    );
    failures += update(
        immutable_media_playback, 21, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "MediaPlaybackEvent is immutable"
    );

    const char *playback_error_source =
        "export function mediaPlaybackChanged(){throw new Error('playback');}"
        "export function update(value){return value;}";
    MWXSceneQuickJSOwner *playback_error = mwx_scene_quickjs_owner_create(
        domain, playback_error_source, strlen(playback_error_source),
        22, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        playback_error != NULL, "media playback error compile", diagnostic
    );
    failures += media_playback(
        playback_error, 22, 1, MWX_SCENE_QUICKJS_EXCEPTION,
        "media playback callback exception"
    );
    failures += update(
        playback_error, 22, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "media playback callback disables only its owner"
    );
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "media playback failure preserves peer owner"
    );

    const char *media_properties_source =
        "let text='';"
        "export function mediaPropertiesChanged(event){"
        "text=event.title+' / '+event.artist;}"
        "export function update(value){return text||value;}";
    MWXSceneQuickJSOwner *media_properties_owner = mwx_scene_quickjs_owner_create(
        domain, media_properties_source, strlen(media_properties_source),
        23, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        media_properties_owner != NULL, "media properties compile", diagnostic
    );
    uint32_t string_update_available = 0;
    failures += check(
        mwx_scene_quickjs_owner_has_function(
            media_properties_owner, "update", 6, &string_update_available,
            diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && string_update_available == 1,
        "string update export", diagnostic
    );
    failures += update_string(
        media_properties_owner, 23, "Placeholder", MWX_SCENE_QUICKJS_OK,
        "Placeholder", "string authored fallback"
    );
    failures += media_properties(
        media_properties_owner, 23, "Song", "Artist", MWX_SCENE_QUICKJS_OK,
        "media properties event"
    );
    failures += update_string(
        media_properties_owner, 23, "Placeholder", MWX_SCENE_QUICKJS_OK,
        "Song / Artist", "media properties update string"
    );
    failures += media_properties(
        media_properties_owner, 24, "Stale", "Artist",
        MWX_SCENE_QUICKJS_STALE_OWNER, "stale media properties owner"
    );

    const char *bad_string_source =
        "export function update(){return 42;}";
    MWXSceneQuickJSOwner *bad_string = mwx_scene_quickjs_owner_create(
        domain, bad_string_source, strlen(bad_string_source),
        24, diagnostic, sizeof(diagnostic)
    );
    failures += check(bad_string != NULL, "bad string compile", diagnostic);
    failures += update_string(
        bad_string, 24, "safe", MWX_SCENE_QUICKJS_BAD_RETURN, "",
        "non-string callback return rejected"
    );

    mwx_scene_quickjs_owner_invalidate(positive);
    failures += update(
        positive, 1, 3, MWX_SCENE_QUICKJS_STALE_OWNER, 0, "stale owner"
    );

    mwx_scene_quickjs_owner_destroy(budget);
    mwx_scene_quickjs_owner_destroy(invalid_effect);
    mwx_scene_quickjs_owner_destroy(immutable_handle);
    mwx_scene_quickjs_owner_destroy(stale_effect);
    mwx_scene_quickjs_owner_destroy(named_animation);
    mwx_scene_quickjs_owner_destroy(media_animation);
    mwx_scene_quickjs_owner_destroy(immutable_media_playback);
    mwx_scene_quickjs_owner_destroy(playback_error);
    mwx_scene_quickjs_owner_destroy(media_playback_owner);
    mwx_scene_quickjs_owner_destroy(media_properties_owner);
    mwx_scene_quickjs_owner_destroy(bad_string);
    mwx_scene_quickjs_owner_destroy(stale_animation);
    mwx_scene_quickjs_owner_destroy(animation_owner);
    mwx_scene_quickjs_owner_destroy(stale_layer);
    mwx_scene_quickjs_owner_destroy(layer_owner);
    mwx_scene_quickjs_owner_destroy(cross_owner);
    mwx_scene_quickjs_owner_destroy(mutation_overflow);
    mwx_scene_quickjs_owner_destroy(bad_return);
    mwx_scene_quickjs_owner_destroy(callback_error);
    mwx_scene_quickjs_owner_destroy(isolated);
    mwx_scene_quickjs_owner_destroy(positive);
    mwx_scene_quickjs_owner_destroy(metadata_only);
    mwx_scene_quickjs_owner_destroy(time_of_day);
    mwx_scene_quickjs_owner_destroy(immutable_frame);
    mwx_scene_quickjs_owner_destroy(vec3);
    mwx_scene_quickjs_owner_destroy(immutable_user);
    mwx_scene_quickjs_owner_destroy(scalar_user);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures == 0 ? 0 : 1;
}
'''


class SceneScriptQuickJSTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS contract gate")
        cls._temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-quickjs-"
        )
        root = Path(cls._temporary_directory.name)
        harness = root / "harness.c"
        binary = root / "harness"
        harness.write_text(HARNESS, encoding="utf-8")
        command = [
            clang,
            "-std=c11",
            "-O0",
            "-I",
            str(SCENE_SCRIPT),
            "-I",
            str(QUICKJS),
            str(SCENE_SCRIPT / "SceneQuickJS.c"),
            str(SCENE_SCRIPT / "SceneQuickJSAnimationHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSMediaEventHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSHandleHost.c"),
            str(QUICKJS / "quickjs.c"),
            str(QUICKJS / "dtoa.c"),
            str(QUICKJS / "libregexp.c"),
            str(QUICKJS / "libunicode.c"),
            str(harness),
            "-lm",
            "-o",
            str(binary),
        ]
        compilation = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True
        )
        if compilation.returncode != 0:
            cls._temporary_directory.cleanup()
            raise AssertionError(
                "QuickJS contract harness did not compile:\n"
                + compilation.stdout
                + compilation.stderr
            )
        cls._binary = binary

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def test_real_ecmascript_owner_contract(self) -> None:
        completed = subprocess.run(
            [str(self._binary)], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )

    def test_host_wiring_preserves_public_frame_order_and_route(self) -> None:
        launch = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        frame = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("excludedTargets: boundedSceneScriptTargets", launch)
        self.assertIn("route=generic-only fallback=previous-current", launch)
        bounded_ownership = launch[
            launch.index("let boundedProducerTargets:"):
            launch.index("let sceneScriptScalarProgram =")
        ]
        for producer in (
            "launch-origin", "hover-origin", "audio-scaled", "property-vector",
            "media-color",
        ):
            self.assertIn(f'("{producer}"', bounded_ownership)
        self.assertNotIn('("media-placeholder"', bounded_ownership)
        self.assertNotIn('("time-of-day"', bounded_ownership)
        self.assertIn(
            "targets.isDisjoint(with: propertyBindingTargets)",
            bounded_ownership,
        )
        self.assertIn(
            "targets.intersection(timelineTargets)",
            bounded_ownership,
        )
        self.assertIn(".subtracting(allowedTimelineTargets)", bounded_ownership)
        self.assertIn(
            "targets.isDisjoint(with: boundedSceneScriptTargets)",
            bounded_ownership,
        )
        scalar_ownership = launch[
            launch.index("let sceneScriptScalarTargets ="):
            launch.index("let provenSceneScriptValueTargets =")
        ]
        self.assertIn(
            "sceneScriptScalarTargets.isDisjoint(with: boundedSceneScriptTargets)",
            scalar_ownership,
        )
        self.assertNotIn("propertyBindingProgram", scalar_ownership)
        self.assertNotIn("timelineProgram", scalar_ownership)
        string_compile = launch.index("let sceneScriptStringProgram =")
        legacy_text_compile = launch.index("let textScriptProgram =")
        self.assertLess(string_compile, legacy_text_compile)
        self.assertIn(
            "excludedTargets: sceneScriptStringTargets",
            launch[legacy_text_compile:launch.index("let provenSceneScriptValueTargets =")],
        )
        self.assertNotIn("SceneTimeOfDayEffectScriptProgram", launch)
        self.assertIn("SceneScriptFrameInput(timing: timing)", frame)
        timeline = frame.index("let timelineValues = launchContext.timelinePlaybackRuntime.values")
        preliminary = frame.index("let preliminaryForSceneScript =")
        evaluate = frame.index("let sceneScriptResult = launchContext.sceneScriptScalarProgram.evaluate")
        final_snapshot = frame.index("let resolvedDynamicValues = surface.evaluationTransaction.evaluate")
        self.assertLess(timeline, preliminary)
        self.assertLess(preliminary, evaluate)
        self.assertLess(evaluate, final_snapshot)
        self.assertIn("sceneScriptScalarProgram.invalidate()", frame)


if __name__ == "__main__":
    unittest.main()
