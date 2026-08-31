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

static int update_at(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    double frame_time,
    double runtime,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    double output = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = frame_time,
        .runtime = runtime,
        .has_surface_input = 1,
        .canvas_width = 100,
        .canvas_height = 50,
        .screen_width = 200,
        .screen_height = 100,
        .cursor_world_x = 10,
        .cursor_world_y = 20,
        .cursor_world_z = 0,
        .cursor_screen_x = 30,
        .cursor_screen_y = 40,
        .cursor_left_down = 1,
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

static int update(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
) {
    return update_at(
        owner, generation, input, 1.0 / 60.0, 2.0,
        expected, expected_output, label
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

static int media_timeline(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double position,
    double duration,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaTimelineEvent event = {
        .position = position,
        .duration = duration,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_timeline(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
}

static int user_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *changed,
    const char *script_properties,
    const char *all_properties,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_user_properties(
            owner, generation,
            changed, strlen(changed),
            script_properties, strlen(script_properties),
            &frame,
            all_properties, strlen(all_properties),
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
}

static int cursor_event(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    MWXSceneQuickJSCursorEventKind kind,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSCursorEvent event = {
        .world_x = 10,
        .world_y = 20,
        .world_z = 0,
        .local_x = 0.5,
        .local_y = 0.25,
        .local_z = 0,
    };
    const char *properties = "{\"enabled\":true}";
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_dispatch_cursor(
        owner, generation, kind, &event, &frame,
        properties, strlen(properties),
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

static int refresh_audio(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t resolution,
    const float *left,
    const float *right,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_refresh_audio_resolution(
            owner, generation, resolution, left, right, resolution,
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
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

static int configure_owner_layer(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_configure_layer_identity(
            owner, layer_id, diagnostic, sizeof(diagnostic)
        );
    return check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}

static int layer_mutation(
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
    MWXSceneQuickJSLayerMutation mutation = {0};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_layer_mutation_at(
        owner, index, &mutation, diagnostic, sizeof(diagnostic)
    );
    return check(
        result == MWX_SCENE_QUICKJS_OK
            && mutation.kind == expected_kind
            && mutation.dynamic == (uint32_t)expected_dynamic
            && mutation.fields == expected_fields
            && (expected_id == 0 || mutation.layer_id == expected_id)
            && mutation.order_index == expected_order
            && strcmp(mutation.text, expected_text) == 0,
        label,
        diagnostic
    );
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
        const double scale[3] = {1, 1, 1};
        const double angles[3] = {0, 0, 0};
        const double color[3] = {1, 1, 1};
        result = mwx_scene_quickjs_domain_update_layer_runtime_fields(
            domain, 0, scale, angles, 1, 1,
            "", 0, "", 0, 32, color, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        const double scale[3] = {2, 3, 4};
        const double angles[3] = {0, 0, 0};
        const double color[3] = {1, 1, 1};
        result = mwx_scene_quickjs_domain_update_layer_runtime_fields(
            domain, 1, scale, angles, 1, 0.75,
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
        result = mwx_scene_quickjs_domain_commit_layer_snapshot(
            domain, diagnostic, sizeof(diagnostic)
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
        "  if (thisLayer.id !== 42 || thisLayer.name !== 'C1') throw new Error('layer identity');\n"
        "  const origin = thisLayer.origin;\n"
        "  if (origin.x !== 4 || origin.y !== 5 || origin.z !== 6) throw new Error('layer origin');\n"
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
            "  if (thisLayer.id !== 42 || thisLayer.name !== 'C1') throw new Error('layer identity');\n"
            "  const origin = thisLayer.origin;\n"
            "  if (origin.x !== 4 || origin.y !== 5 || origin.z !== 6) throw new Error('layer origin');\n"
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
    failures += configure_owner_layer(
        positive, 42, "positive layer identity"
    );
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

    const char *surface_input_source =
        "'use strict';\n"
        "export function update(value) {\n"
        "  const world = input.cursorWorldPosition;\n"
        "  const screen = input.cursorScreenPosition;\n"
        "  const canvas = engine.canvasSize;\n"
        "  if (!(screen instanceof Vec2) || !(canvas instanceof Vec2) ||\n"
        "      !Object.isFrozen(input) || !Object.isFrozen(world) ||\n"
        "      !Object.isFrozen(screen) || !Object.isFrozen(canvas)) {\n"
        "    throw new Error('mutable surface snapshot');\n"
        "  }\n"
        "  const divisor = new Vec3(canvas, 1).divide(new Vec3(10, 5, 1));\n"
        "  const arithmetic = new Vec3(15, 15, 2).subtract(divisor);\n"
        "  const pair = new Vec2('2 3').add(new Vec2(4)).multiply(2);\n"
        "  return value + world.x + world.y + world.z +\n"
        "    screen.x + screen.y + canvas.x + canvas.y +\n"
        "    (input.cursorLeftDown ? 1 : 0) +\n"
        "    arithmetic.x + arithmetic.y + arithmetic.z + pair.x + pair.y;\n"
        "}";
    MWXSceneQuickJSOwner *surface_input = mwx_scene_quickjs_owner_create(
        domain, surface_input_source, strlen(surface_input_source),
        48, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        surface_input != NULL, "surface input compile", diagnostic
    );
    failures += update(
        surface_input, 48, 1, MWX_SCENE_QUICKJS_OK, 289,
        "callback surface input and Vec2/Vec3 arithmetic"
    );
    MWXSceneQuickJSFrameInput refreshed_surface_frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
        .has_surface_input = 1,
        .canvas_width = 200,
        .canvas_height = 100,
        .screen_width = 400,
        .screen_height = 200,
        .cursor_world_x = 1,
        .cursor_world_y = 2,
        .cursor_world_z = 3,
        .cursor_screen_x = 4,
        .cursor_screen_y = 5,
        .cursor_left_down = 0,
    };
    double refreshed_surface_output = 0;
    failures += check(
        mwx_scene_quickjs_owner_update_scalar(
            surface_input, 48, 1, &refreshed_surface_frame,
            &refreshed_surface_output, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && refreshed_surface_output == 333,
        "surface input refreshes per callback",
        diagnostic
    );

    const char *immutable_surface_source =
        "'use strict'; export function update(value) {"
        "input.cursorWorldPosition.x = 99; return value; }";
    MWXSceneQuickJSOwner *immutable_surface = mwx_scene_quickjs_owner_create(
        domain, immutable_surface_source, strlen(immutable_surface_source),
        49, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        immutable_surface != NULL, "immutable surface compile", diagnostic
    );
    failures += update(
        immutable_surface, 49, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "surface snapshots are immutable"
    );
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "surface mutation failure preserves peer owner"
    );

    const char *global_surface_source =
        "let rejected = false; "
        "try { input.cursorWorldPosition; } catch (error) { rejected = true; } "
        "export function update(value) { return rejected ? value + 1 : -1; }";
    MWXSceneQuickJSOwner *global_surface = mwx_scene_quickjs_owner_create(
        domain, global_surface_source, strlen(global_surface_source),
        50, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        global_surface != NULL,
        "global phase rejects surface input",
        diagnostic
    );
    failures += update(
        global_surface, 50, 1, MWX_SCENE_QUICKJS_OK, 2,
        "global phase rejection is observable"
    );

    MWXSceneQuickJSFrameInput missing_surface_frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    double missing_surface_output = 0;
    failures += check(
        mwx_scene_quickjs_owner_update_scalar(
            surface_input, 48, 1, &missing_surface_frame,
            &missing_surface_output, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_EXCEPTION,
        "missing exact surface fails only consumer callback",
        diagnostic
    );
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "missing surface failure preserves peer owner"
    );

    MWXSceneQuickJSFrameInput invalid_surface_frame = missing_surface_frame;
    invalid_surface_frame.has_surface_input = 1;
    invalid_surface_frame.canvas_width = 0;
    invalid_surface_frame.canvas_height = 50;
    invalid_surface_frame.screen_width = 200;
    invalid_surface_frame.screen_height = 100;
    MWXSceneQuickJSOwner *invalid_surface = mwx_scene_quickjs_owner_create(
        domain, surface_input_source, strlen(surface_input_source),
        51, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        invalid_surface != NULL, "invalid surface owner compile", diagnostic
    );
    failures += check(
        mwx_scene_quickjs_owner_update_scalar(
            invalid_surface, 51, 1, &invalid_surface_frame,
            &missing_surface_output, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_EXCEPTION,
        "invalid surface ABI fails closed",
        diagnostic
    );

    MWXSceneQuickJSOwner *wemath_mix = mwx_scene_quickjs_owner_create(
        domain,
        "import * as WEMath from 'WEMath';\n"
        "export function update(value) { return WEMath.mix(value, 10, 0.25); }",
        strlen(
            "import * as WEMath from 'WEMath';\n"
            "export function update(value) { return WEMath.mix(value, 10, 0.25); }"
        ),
        28, diagnostic, sizeof(diagnostic)
    );
    failures += check(wemath_mix != NULL, "WEMath.mix compile", diagnostic);
    failures += update(
        wemath_mix, 28, 2, MWX_SCENE_QUICKJS_OK, 4,
        "WEMath.mix scalar interpolation"
    );

    MWXSceneQuickJSOwner *invalid_wemath_mix = mwx_scene_quickjs_owner_create(
        domain,
        "import * as WEMath from 'WEMath';\n"
        "export function update(value) { return WEMath.mix(value, Infinity, 0.5); }",
        strlen(
            "import * as WEMath from 'WEMath';\n"
            "export function update(value) { return WEMath.mix(value, Infinity, 0.5); }"
        ),
        29, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        invalid_wemath_mix != NULL, "invalid WEMath.mix compile", diagnostic
    );
    failures += update(
        invalid_wemath_mix, 29, 2, MWX_SCENE_QUICKJS_EXCEPTION, 2,
        "WEMath.mix rejects non-finite input"
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
    scalar_user_result =
        mwx_scene_quickjs_owner_update_scalar_with_user_properties(
            scalar_user, 15, 0, &scalar_user_frame,
            "{\"live\":6}", strlen("{\"live\":6}"),
            &scalar_user_output, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        scalar_user_result == MWX_SCENE_QUICKJS_OK && scalar_user_output == 6,
        "unchanged user property snapshot",
        diagnostic
    );
    scalar_user_result =
        mwx_scene_quickjs_owner_update_scalar_with_user_properties(
            scalar_user, 15, 0, &scalar_user_frame,
            "{\"live\":7}", strlen("{\"live\":7}"),
            &scalar_user_output, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        scalar_user_result == MWX_SCENE_QUICKJS_OK && scalar_user_output == 7,
        "changed user property snapshot",
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

    const char *wecolor_source =
        "import * as WEColor from 'WEColor';\n"
        "export function update(value) {\n"
        "  return WEColor.hsv2rgb({x:0.5,y:1,z:1}).multiply(0.5);\n"
        "}";
    MWXSceneQuickJSOwner *wecolor = mwx_scene_quickjs_owner_create(
        domain, wecolor_source, strlen(wecolor_source),
        52, diagnostic, sizeof(diagnostic)
    );
    failures += check(wecolor != NULL, "WEColor.hsv2rgb compile", diagnostic);
    const double wecolor_expected[3] = {0, 0.5, 0.5};
    failures += update_vec3(
        wecolor, 52, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, wecolor_expected,
        "WEColor.hsv2rgb returns Vec3"
    );

    const char *wecolor_wrap_source =
        "import * as WEColor from 'WEColor';\n"
        "export function update(value) {\n"
        "  return WEColor.hsv2rgb({x:2,y:1,z:1});\n"
        "}";
    MWXSceneQuickJSOwner *wecolor_wrap = mwx_scene_quickjs_owner_create(
        domain, wecolor_wrap_source, strlen(wecolor_wrap_source),
        53, diagnostic, sizeof(diagnostic)
    );
    failures += check(wecolor_wrap != NULL, "WEColor hue wrap compile", diagnostic);
    const double red[3] = {1, 0, 0};
    failures += update_vec3(
        wecolor_wrap, 53, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, red, "WEColor hue wraps"
    );

    const char *wecolor_invalid_source =
        "import * as WEColor from 'WEColor';\n"
        "export function update(value) {\n"
        "  return WEColor.hsv2rgb({x:0,y:2,z:1});\n"
        "}";
    MWXSceneQuickJSOwner *wecolor_invalid = mwx_scene_quickjs_owner_create(
        domain, wecolor_invalid_source, strlen(wecolor_invalid_source),
        54, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        wecolor_invalid != NULL, "invalid WEColor compile", diagnostic
    );
    failures += update_vec3(
        wecolor_invalid, 54, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_EXCEPTION, vec3_input,
        "WEColor rejects non-normalized saturation"
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

    const char *media_timeline_source =
        "let progress=0;"
        "export function mediaTimelineChanged(event){"
        "if(!Object.isFrozen(event))throw new Error('mutable timeline');"
        "progress=event.duration===0?0:event.position/event.duration;}"
        "export function update(){return progress;}";
    MWXSceneQuickJSOwner *media_timeline_owner = mwx_scene_quickjs_owner_create(
        domain, media_timeline_source, strlen(media_timeline_source),
        25, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        media_timeline_owner != NULL, "media timeline compile", diagnostic
    );
    failures += media_timeline(
        media_timeline_owner, 25, 12.5, 100,
        MWX_SCENE_QUICKJS_OK, "media timeline event"
    );
    failures += update(
        media_timeline_owner, 25, 0, MWX_SCENE_QUICKJS_OK, 0.125,
        "media timeline update"
    );
    failures += media_timeline(
        media_timeline_owner, 25, -1, 100,
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "negative media timeline"
    );
    failures += media_timeline(
        media_timeline_owner, 25, 1, INFINITY,
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "non-finite media timeline"
    );
    failures += update(
        media_timeline_owner, 25, 0, MWX_SCENE_QUICKJS_OK, 0.125,
        "invalid media timeline preserves owner"
    );

    const char *cursor_source =
        "export function cursorEnter(event){"
        "if(!Object.isFrozen(event)||!Object.isFrozen(event.worldPosition)||"
        "!Object.isFrozen(event.localPosition))throw new Error('mutable cursor');"
        "shared.hover=event.worldPosition.x===10&&event.localPosition.y===0.25;}"
        "export function cursorLeave(event){shared.hover=false;}"
        "export function cursorDown(event){shared.pointerOrder='down';}"
        "export function cursorMove(event){"
        "if(shared.pointerOrder!=='down')throw new Error('cursor move order');"
        "shared.pointerOrder='move';}"
        "export function cursorUp(event){"
        "if(shared.pointerOrder!=='move')throw new Error('cursor order');"
        "shared.pointerOrder='up';}"
        "export function cursorClick(event){"
        "if(shared.pointerOrder!=='up')throw new Error('cursor order');"
        "shared.pointerOrder='click';}";
    MWXSceneQuickJSOwner *cursor_owner = mwx_scene_quickjs_owner_create(
        domain, cursor_source, strlen(cursor_source),
        26, diagnostic, sizeof(diagnostic)
    );
    failures += check(cursor_owner != NULL, "cursor owner compile", diagnostic);
    const char *cursor_consumer_source =
        "export var scriptProperties=createScriptProperties()"
        ".addSlider({name:'factor',value:2}).finish();"
        "let enabled=false;"
        "export function applyUserProperties(changed){"
        "if(!Object.isFrozen(changed))throw new Error('mutable properties');"
        "const copied=new Vec3(new Vec3(scriptProperties.factor));"
        "enabled=changed.enabled===true&&copied.x===3&&copied.y===3&&copied.z===3;}"
        "export function update(value){"
        "return shared.hover&&enabled?value*scriptProperties.factor:value;}";
    MWXSceneQuickJSOwner *cursor_consumer = mwx_scene_quickjs_owner_create(
        domain, cursor_consumer_source, strlen(cursor_consumer_source),
        27, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        cursor_consumer != NULL, "cursor consumer compile", diagnostic
    );
    failures += user_properties(
        cursor_consumer, 27, "{\"enabled\":true}", "{\"factor\":3}",
        "{\"enabled\":true}", MWX_SCENE_QUICKJS_OK,
        "initial user properties event"
    );
    failures += cursor_event(
        cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_ENTER,
        MWX_SCENE_QUICKJS_OK, "cursor enter event"
    );
    failures += update(
        cursor_consumer, 27, 2, MWX_SCENE_QUICKJS_OK, 6,
        "cursor shared state reaches property owner"
    );
    failures += cursor_event(
        cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_LEAVE,
        MWX_SCENE_QUICKJS_OK, "cursor leave event"
    );
    failures += cursor_event(
        cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_DOWN,
        MWX_SCENE_QUICKJS_OK, "cursor down event"
    );
    failures += cursor_event(
        cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_MOVE,
        MWX_SCENE_QUICKJS_OK, "cursor move event"
    );
    failures += cursor_event(
        cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_UP,
        MWX_SCENE_QUICKJS_OK, "cursor up event"
    );
    failures += cursor_event(
        cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_CLICK,
        MWX_SCENE_QUICKJS_OK, "cursor click event"
    );
    failures += update(
        cursor_consumer, 27, 2, MWX_SCENE_QUICKJS_OK, 2,
        "cursor leave restores authored value"
    );
    failures += cursor_event(
        cursor_owner, 28, MWX_SCENE_QUICKJS_CURSOR_ENTER,
        MWX_SCENE_QUICKJS_STALE_OWNER, "stale cursor owner"
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

    const char *audio_source =
        "const audio=engine.registerAudioBuffers();"
        "const same=engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);"
        "const medium=engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_32);"
        "const extended=engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_64);"
        "const identity=audio.average;"
        "export function update(value){"
        "if(audio!==same||audio.average!==identity||"
        "!(audio.left instanceof Float32Array)||audio.left.length!==16||"
        "medium.left.length!==32||extended.left.length!==64)"
        "throw new Error('audio identity');"
        "const result=value+audio.left[0]+audio.right[1]+audio.average[2]+"
        "medium.left[31]+extended.right[63];"
        "audio.average[2]=99;return result;}";
    MWXSceneQuickJSOwner *audio_owner = mwx_scene_quickjs_owner_create(
        domain, audio_source, strlen(audio_source),
        25, diagnostic, sizeof(diagnostic)
    );
    failures += check(audio_owner != NULL, "audio owner compile", diagnostic);
    failures += check(
        mwx_scene_quickjs_owner_audio_registration_count(audio_owner) == 3,
        "audio resolutions and duplicate identity", diagnostic
    );
    float audio_left[16] = {0};
    float audio_right[16] = {0};
    audio_left[0] = 1;
    audio_right[1] = 2;
    audio_left[2] = 4;
    audio_right[2] = 2;
    float audio_left32[32] = {0};
    float audio_right32[32] = {0};
    audio_left32[31] = 4;
    float audio_left64[64] = {0};
    float audio_right64[64] = {0};
    audio_right64[63] = 5;
    failures += refresh_audio(
        audio_owner, 25, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_OK, "audio snapshot refresh"
    );
    failures += refresh_audio(
        audio_owner, 25, 32, audio_left32, audio_right32,
        MWX_SCENE_QUICKJS_OK, "audio 32 snapshot refresh"
    );
    failures += refresh_audio(
        audio_owner, 25, 64, audio_left64, audio_right64,
        MWX_SCENE_QUICKJS_OK, "audio 64 snapshot refresh"
    );
    failures += update(
        audio_owner, 25, 1, MWX_SCENE_QUICKJS_OK, 16,
        "audio left right average and resolutions"
    );
    audio_left[0] = -1;
    failures += refresh_audio(
        audio_owner, 25, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "invalid audio sample"
    );
    audio_left[0] = 1;
    failures += refresh_audio(
        audio_owner, 25, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_OK, "audio same snapshot refresh"
    );
    failures += update(
        audio_owner, 25, 1, MWX_SCENE_QUICKJS_OK, 16,
        "audio host overwrites script mutation"
    );
    failures += refresh_audio(
        audio_owner, 26, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_STALE_OWNER, "stale audio owner"
    );

    const char *invalid_audio_source =
        "const audio=engine.registerAudioBuffers(8);"
        "export function update(value){return value+audio.average[0];}";
    MWXSceneQuickJSOwner *invalid_audio = mwx_scene_quickjs_owner_create(
        domain, invalid_audio_source, strlen(invalid_audio_source),
        26, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        invalid_audio == NULL, "invalid audio resolution rejected", diagnostic
    );

    const char *callback_audio_source =
        "export function update(value){"
        "engine.registerAudioBuffers(16);return value;}";
    MWXSceneQuickJSOwner *callback_audio = mwx_scene_quickjs_owner_create(
        domain, callback_audio_source, strlen(callback_audio_source),
        27, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        callback_audio != NULL, "callback audio owner compile", diagnostic
    );
    failures += update(
        callback_audio, 27, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "audio registration is global-only"
    );

    const char *promise_source =
        "let state=0;"
        "export function init(value){"
        "Promise.resolve().then(()=>{state=4;});return value;}"
        "export function update(value){return value+state;}";
    MWXSceneQuickJSOwner *promise_owner = mwx_scene_quickjs_owner_create(
        domain, promise_source, strlen(promise_source),
        37, diagnostic, sizeof(diagnostic)
    );
    failures += check(promise_owner != NULL, "promise owner compile", diagnostic);
    failures += update(
        promise_owner, 37, 1, MWX_SCENE_QUICKJS_OK, 5,
        "promise job drains before next owner hook"
    );

    const char *promise_mutation_source =
        "export function update(value){"
        "Promise.resolve().then(()=>{"
        "thisLayer.getEffect(0).executeMaterialFunction('asyncMutate');});"
        "return value;}";
    MWXSceneQuickJSOwner *promise_mutation = mwx_scene_quickjs_owner_create(
        domain, promise_mutation_source, strlen(promise_mutation_source),
        43, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        promise_mutation != NULL, "promise mutation compile", diagnostic
    );
    failures += configure_effects(
        promise_mutation, 1, 0, "async", "promise mutation catalog"
    );
    failures += update(
        promise_mutation, 43, 1, MWX_SCENE_QUICKJS_OK, 1,
        "promise mutation callback"
    );
    failures += mutation(
        promise_mutation, 0, 0, "asyncMutate",
        "promise job retains owner handle"
    );

    const char *event_promise_source =
        "export function cursorClick(){"
        "Promise.resolve().then(()=>{shared.eventJob=9;});}"
        "export function update(value){return value+(shared.eventJob||0);}";
    MWXSceneQuickJSOwner *event_promise = mwx_scene_quickjs_owner_create(
        domain, event_promise_source, strlen(event_promise_source),
        44, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        event_promise != NULL, "event promise compile", diagnostic
    );
    failures += cursor_event(
        event_promise, 44, MWX_SCENE_QUICKJS_CURSOR_CLICK,
        MWX_SCENE_QUICKJS_OK, "event promise drains before return"
    );
    failures += update(
        event_promise, 44, 1, MWX_SCENE_QUICKJS_OK, 10,
        "event promise state is visible"
    );

    const char *handled_rejection_source =
        "let state=0;"
        "export function init(value){"
        "Promise.reject(new Error('handled')).catch(()=>{state=3;});"
        "return value;}"
        "export function update(value){return value+state;}";
    MWXSceneQuickJSOwner *handled_rejection = mwx_scene_quickjs_owner_create(
        domain, handled_rejection_source, strlen(handled_rejection_source),
        38, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        handled_rejection != NULL, "handled rejection compile", diagnostic
    );
    failures += update(
        handled_rejection, 38, 1, MWX_SCENE_QUICKJS_OK, 4,
        "handled rejection remains healthy"
    );

    const char *unhandled_rejection_source =
        "export function update(value){"
        "Promise.reject(new Error('unhandled'));return value;}";
    MWXSceneQuickJSOwner *unhandled_rejection = mwx_scene_quickjs_owner_create(
        domain, unhandled_rejection_source, strlen(unhandled_rejection_source),
        39, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        unhandled_rejection != NULL, "unhandled rejection compile", diagnostic
    );
    failures += update(
        unhandled_rejection, 39, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "unhandled rejection disables owner"
    );

    const char *job_budget_source =
        "export function update(value){"
        "let chain=Promise.resolve();"
        "for(let i=0;i<65;i+=1)chain=chain.then(()=>{});"
        "return value;}";
    MWXSceneQuickJSOwner *job_budget = mwx_scene_quickjs_owner_create(
        domain, job_budget_source, strlen(job_budget_source),
        40, diagnostic, sizeof(diagnostic)
    );
    failures += check(job_budget != NULL, "job budget compile", diagnostic);
    failures += update(
        job_budget, 40, 1, MWX_SCENE_QUICKJS_BUDGET_EXCEEDED, 0,
        "job budget disables owner"
    );
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "job failure preserves peer owner"
    );

    const char *module_job_source =
        "Promise.resolve().then(()=>{});"
        "export function update(value){return value;}";
    MWXSceneQuickJSOwner *module_job = mwx_scene_quickjs_owner_create(
        domain, module_job_source, strlen(module_job_source),
        41, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        module_job == NULL, "module job rejected and discarded", diagnostic
    );
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "module job rejection preserves peer owner"
    );

    const char *timer_promise_source =
        "let state=0,resolveValue;"
        "export function init(value){"
        "new Promise(resolve=>{resolveValue=resolve;})"
        ".then(next=>{state=next;});"
        "engine.setTimeout(()=>{resolveValue(6);},10);return value;}"
        "export function update(value){return value+state;}";
    MWXSceneQuickJSOwner *timer_promise = mwx_scene_quickjs_owner_create(
        domain, timer_promise_source, strlen(timer_promise_source),
        42, diagnostic, sizeof(diagnostic)
    );
    failures += check(timer_promise != NULL, "timer promise compile", diagnostic);
    failures += update_at(
        timer_promise, 42, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer promise initialization"
    );
    failures += update_at(
        timer_promise, 42, 1, 0.01, 0.01,
        MWX_SCENE_QUICKJS_OK, 7, "timer resolves promise before update"
    );

    const char *timer_source =
        "let once=0,ticks=0,cancelInterval;"
        "export function init(value){"
        "engine.setTimeout(()=>{once=5;},100);"
        "cancelInterval=engine.setInterval(()=>{"
        "ticks+=1;if(ticks===2)cancelInterval();},50);"
        "const cancelled=engine.setTimeout(()=>{once=99;},0);"
        "cancelled();return value;}"
        "export function update(value){return value+once+ticks;}";
    MWXSceneQuickJSOwner *timer_owner = mwx_scene_quickjs_owner_create(
        domain, timer_source, strlen(timer_source),
        30, diagnostic, sizeof(diagnostic)
    );
    failures += check(timer_owner != NULL, "timer owner compile", diagnostic);
    failures += update_at(
        timer_owner, 30, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer initialization"
    );
    failures += check(
        mwx_scene_quickjs_owner_active_timer_count(timer_owner) == 2,
        "cancelled timer removed", ""
    );
    failures += update_at(
        timer_owner, 30, 1, 0.04, 0.04,
        MWX_SCENE_QUICKJS_OK, 1, "timers wait for delay"
    );
    failures += update_at(
        timer_owner, 30, 1, 0.02, 0.06,
        MWX_SCENE_QUICKJS_OK, 2, "interval first tick"
    );
    failures += update_at(
        timer_owner, 30, 1, 0.06, 0.12,
        MWX_SCENE_QUICKJS_OK, 8, "timeout and self-cancel interval"
    );
    failures += check(
        mwx_scene_quickjs_owner_active_timer_count(timer_owner) == 0,
        "timer slots released", ""
    );
    failures += update_at(
        timer_owner, 30, 1, 0.06, 0.12,
        MWX_SCENE_QUICKJS_OK, 8, "same runtime does not advance timers"
    );

    const char *interval_source =
        "let ticks=0;"
        "export function init(value){"
        "engine.setInterval(()=>{ticks+=1;},10);return value;}"
        "export function update(value){return value+ticks;}";
    MWXSceneQuickJSOwner *interval_owner = mwx_scene_quickjs_owner_create(
        domain, interval_source, strlen(interval_source),
        31, diagnostic, sizeof(diagnostic)
    );
    failures += check(interval_owner != NULL, "interval owner compile", diagnostic);
    failures += update_at(
        interval_owner, 31, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "interval initialization"
    );
    failures += update_at(
        interval_owner, 31, 1, 1, 1,
        MWX_SCENE_QUICKJS_OK, 2, "interval long frame runs once"
    );
    failures += update_at(
        interval_owner, 31, 1, 1, 2,
        MWX_SCENE_QUICKJS_OK, 3, "interval does not catch up"
    );

    const char *timer_cancel_owner_source =
        "export function init(value){"
        "shared.cancel=engine.setTimeout(()=>{},1000);return value;}"
        "export function update(value){return value;}";
    MWXSceneQuickJSOwner *timer_cancel_owner = mwx_scene_quickjs_owner_create(
        domain, timer_cancel_owner_source, strlen(timer_cancel_owner_source),
        35, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        timer_cancel_owner != NULL, "timer cancel owner compile", diagnostic
    );
    failures += update_at(
        timer_cancel_owner, 35, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer cancel owner initialization"
    );
    MWXSceneQuickJSOwner *timer_cancel_intruder = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value){shared.cancel();return value;}",
        strlen("export function update(value){shared.cancel();return value;}"),
        36, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        timer_cancel_intruder != NULL, "timer cancel intruder compile", diagnostic
    );
    failures += update_at(
        timer_cancel_intruder, 36, 1, 0, 0,
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "cross-owner timer cancel rejected"
    );
    failures += check(
        mwx_scene_quickjs_owner_active_timer_count(timer_cancel_owner) == 1,
        "cross-owner cancel preserves timer", ""
    );

    const char *invalid_timer_source =
        "export function update(value){"
        "engine.setTimeout(()=>{},-1);return value;}";
    MWXSceneQuickJSOwner *invalid_timer = mwx_scene_quickjs_owner_create(
        domain, invalid_timer_source, strlen(invalid_timer_source),
        32, diagnostic, sizeof(diagnostic)
    );
    failures += check(invalid_timer != NULL, "invalid timer owner compile", diagnostic);
    failures += update_at(
        invalid_timer, 32, 1, 0, 0,
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "invalid timer disables owner"
    );

    const char *timer_budget_source =
        "export function update(value){"
        "for(let i=0;i<33;i+=1)engine.setTimeout(()=>{},1000);"
        "return value;}";
    MWXSceneQuickJSOwner *timer_budget = mwx_scene_quickjs_owner_create(
        domain, timer_budget_source, strlen(timer_budget_source),
        33, diagnostic, sizeof(diagnostic)
    );
    failures += check(timer_budget != NULL, "timer budget owner compile", diagnostic);
    failures += update_at(
        timer_budget, 33, 1, 0, 0,
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "timer budget disables owner"
    );
    failures += check(
        mwx_scene_quickjs_owner_active_timer_count(timer_budget) == 32,
        "timer budget remains bounded", ""
    );

    const char *timer_exception_source =
        "export function init(value){"
        "engine.setTimeout(()=>{throw new Error('timer boom');},0);"
        "return value;}"
        "export function update(value){return value;}";
    MWXSceneQuickJSOwner *timer_exception = mwx_scene_quickjs_owner_create(
        domain, timer_exception_source, strlen(timer_exception_source),
        34, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        timer_exception != NULL, "timer exception owner compile", diagnostic
    );
    failures += update_at(
        timer_exception, 34, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer exception initialization"
    );
    failures += update_at(
        timer_exception, 34, 1, 0.01, 0.01,
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "timer exception disables owner"
    );
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "timer exception preserves peer owner"
    );

    const char *dynamic_layer_source =
        "let shadow;"
        "export function init(value){"
        "shadow=thisScene.createLayer({text:'shadow',color:'0 0 0',alpha:1,"
        "pointsize:thisLayer.pointsize,font:thisLayer.font});"
        "shadow.origin=thisLayer.origin;shadow.scale=thisLayer.scale;"
        "thisScene.sortLayer(shadow,thisScene.getLayerIndex(thisLayer));"
        "shared.dynamicLayer=shadow;return value;}"
        "export function update(value){"
        "shadow.text='tick';shadow.angles=new Vec3(1,2,3);"
        "return thisScene.getLayerIndex(shadow)*100+thisScene.getLayerCount();}";
    MWXSceneQuickJSOwner *dynamic_layer = mwx_scene_quickjs_owner_create(
        domain, dynamic_layer_source, strlen(dynamic_layer_source),
        40, diagnostic, sizeof(diagnostic)
    );
    failures += check(dynamic_layer != NULL, "dynamic layer owner compile", diagnostic);
    failures += configure_owner_layer(dynamic_layer, 42, "dynamic layer owner identity");
    failures += update(
        dynamic_layer, 40, 1, MWX_SCENE_QUICKJS_OK, 103,
        "dynamic layer create update"
    );
    failures += check(
        mwx_scene_quickjs_owner_layer_mutation_count(dynamic_layer) == 1,
        "dynamic layer mutation coalesced", ""
    );
    failures += layer_mutation(
        dynamic_layer, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
        1, 0, 0, 1, "tick", "dynamic layer snapshot"
    );
    failures += update(
        dynamic_layer, 40, 1, MWX_SCENE_QUICKJS_OK, 103,
        "dynamic layer handle persists"
    );
    failures += check(
        mwx_scene_quickjs_owner_layer_mutation_count(dynamic_layer) == 0,
        "unchanged dynamic layer setters are deduplicated", ""
    );

    MWXSceneQuickJSOwner *dynamic_intruder = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value){thisScene.sortLayer(shared.dynamicLayer,0);return value;}",
        strlen("export function update(value){thisScene.sortLayer(shared.dynamicLayer,0);return value;}"),
        41, diagnostic, sizeof(diagnostic)
    );
    failures += check(dynamic_intruder != NULL, "dynamic intruder compile", diagnostic);
    failures += configure_owner_layer(dynamic_intruder, 17, "dynamic intruder identity");
    failures += update(
        dynamic_intruder, 41, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "cross-owner dynamic layer handle rejected"
    );

    MWXSceneQuickJSOwner *static_sort = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value){thisScene.sortLayer(thisLayer,0);return value;}",
        strlen("export function update(value){thisScene.sortLayer(thisLayer,0);return value;}"),
        44, diagnostic, sizeof(diagnostic)
    );
    failures += check(static_sort != NULL, "static sort owner compile", diagnostic);
    failures += configure_owner_layer(static_sort, 42, "static sort owner identity");
    failures += update(
        static_sort, 44, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "static layer sort rejected until topology publication is supported"
    );

    MWXSceneQuickJSOwner *static_setter = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value){thisLayer.origin=new Vec3(1,2,3);return value;}",
        strlen("export function update(value){thisLayer.origin=new Vec3(1,2,3);return value;}"),
        45, diagnostic, sizeof(diagnostic)
    );
    failures += check(static_setter != NULL, "static setter owner compile", diagnostic);
    failures += configure_owner_layer(static_setter, 42, "static setter owner identity");
    failures += update(
        static_setter, 45, 1, MWX_SCENE_QUICKJS_OK, 1,
        "static layer transform setter accepted"
    );
    failures += check(
        mwx_scene_quickjs_owner_layer_mutation_count(static_setter) == 1,
        "static layer transform mutation coalesced", ""
    );
    failures += layer_mutation(
        static_setter, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
        0, MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN,
        42, 1, "clock", "static layer transform snapshot"
    );

    MWXSceneQuickJSOwner *static_visible = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value){thisLayer.visible=false;return value;}",
        strlen("export function update(value){thisLayer.visible=false;return value;}"),
        46, diagnostic, sizeof(diagnostic)
    );
    failures += check(static_visible != NULL, "static visible owner compile", diagnostic);
    failures += configure_owner_layer(static_visible, 42, "static visible owner identity");
    failures += update(
        static_visible, 46, 1, MWX_SCENE_QUICKJS_OK, 1,
        "static layer visibility setter accepted"
    );
    failures += check(
        mwx_scene_quickjs_owner_layer_mutation_count(static_visible) == 1,
        "static layer visibility mutation coalesced", ""
    );
    failures += layer_mutation(
        static_visible, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
        0, MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY,
        42, 1, "clock", "static layer visibility snapshot"
    );
    MWXSceneQuickJSLayerMutation static_visibility_mutation = {0};
    failures += check(
        mwx_scene_quickjs_owner_layer_mutation_at(
            static_visible, 0, &static_visibility_mutation,
            diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK &&
            static_visibility_mutation.visible == 0,
        "static layer visibility value", diagnostic
    );

    const char *forged_layer_source =
        "export function update(value){"
        "if(thisScene.getLayerIndex({id:42})!==-1)throw new Error('forged index');"
        "thisScene.sortLayer({id:42},0);return value;}";
    MWXSceneQuickJSOwner *forged_layer = mwx_scene_quickjs_owner_create(
        domain, forged_layer_source, strlen(forged_layer_source),
        43, diagnostic, sizeof(diagnostic)
    );
    failures += check(forged_layer != NULL, "forged layer owner compile", diagnostic);
    failures += configure_owner_layer(forged_layer, 42, "forged layer owner identity");
    failures += update(
        forged_layer, 43, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "forged layer object rejected"
    );

    const char *dynamic_budget_source =
        "export function update(value){for(let i=0;i<65;i+=1)"
        "thisScene.createLayer({text:'x'});return value;}";
    MWXSceneQuickJSOwner *dynamic_budget = mwx_scene_quickjs_owner_create(
        domain, dynamic_budget_source, strlen(dynamic_budget_source),
        42, diagnostic, sizeof(diagnostic)
    );
    failures += check(dynamic_budget != NULL, "dynamic budget compile", diagnostic);
    failures += configure_owner_layer(dynamic_budget, 17, "dynamic budget identity");
    failures += update(
        dynamic_budget, 42, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "dynamic layer budget rejected"
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
    mwx_scene_quickjs_owner_destroy(media_timeline_owner);
    mwx_scene_quickjs_owner_destroy(bad_string);
    mwx_scene_quickjs_owner_destroy(cursor_consumer);
    mwx_scene_quickjs_owner_destroy(cursor_owner);
    mwx_scene_quickjs_owner_destroy(audio_owner);
    mwx_scene_quickjs_owner_destroy(callback_audio);
    mwx_scene_quickjs_owner_destroy(promise_owner);
    mwx_scene_quickjs_owner_destroy(promise_mutation);
    mwx_scene_quickjs_owner_destroy(event_promise);
    mwx_scene_quickjs_owner_destroy(handled_rejection);
    mwx_scene_quickjs_owner_destroy(unhandled_rejection);
    mwx_scene_quickjs_owner_destroy(job_budget);
    mwx_scene_quickjs_owner_destroy(timer_promise);
    mwx_scene_quickjs_owner_destroy(timer_owner);
    mwx_scene_quickjs_owner_destroy(interval_owner);
    mwx_scene_quickjs_owner_destroy(timer_cancel_owner);
    mwx_scene_quickjs_owner_destroy(timer_cancel_intruder);
    mwx_scene_quickjs_owner_destroy(invalid_timer);
    mwx_scene_quickjs_owner_destroy(timer_budget);
    mwx_scene_quickjs_owner_destroy(timer_exception);
    mwx_scene_quickjs_owner_destroy(dynamic_layer);
    mwx_scene_quickjs_owner_destroy(dynamic_intruder);
    mwx_scene_quickjs_owner_destroy(static_sort);
    mwx_scene_quickjs_owner_destroy(static_setter);
    mwx_scene_quickjs_owner_destroy(static_visible);
    mwx_scene_quickjs_owner_destroy(forged_layer);
    mwx_scene_quickjs_owner_destroy(dynamic_budget);
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
    mwx_scene_quickjs_owner_destroy(invalid_wemath_mix);
    mwx_scene_quickjs_owner_destroy(wemath_mix);
    mwx_scene_quickjs_owner_destroy(immutable_surface);
    mwx_scene_quickjs_owner_destroy(surface_input);
    mwx_scene_quickjs_owner_destroy(invalid_surface);
    mwx_scene_quickjs_owner_destroy(global_surface);
    mwx_scene_quickjs_owner_destroy(immutable_frame);
    mwx_scene_quickjs_owner_destroy(vec3);
    mwx_scene_quickjs_owner_destroy(wecolor);
    mwx_scene_quickjs_owner_destroy(wecolor_wrap);
    mwx_scene_quickjs_owner_destroy(wecolor_invalid);
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
            str(SCENE_SCRIPT / "SceneQuickJSValueHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSModuleHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSAnimationHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSAudioHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSMediaEventHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSHandleHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSLayerHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSLayerSnapshotHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSJobHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSTimerHost.c"),
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

    def test_host_wiring_preserves_public_frame_order(self) -> None:
        launch = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        startup_report = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperLaunchContext+StartupReport.swift"
        ).read_text(encoding="utf-8")
        frame = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        model = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRuntimeModel.swift"
        ).read_text(encoding="utf-8")
        cursor = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptCursorProgram.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "scalarExcludedTargets: boundedSceneScriptTargets",
            launch,
        )
        self.assertIn(
            "route=generic-only fallback=current-frame-lower-priority",
            startup_report,
        )
        self.assertIn("let propertyVectorProjection =", model)
        self.assertNotIn("SceneScriptVectorProgram.compileNonPass(", model)
        provisional_capabilities = launch.index(
            "let provisionalMaterialExecutionCapabilities ="
        )
        material_consumer_c = launch.index("let admittedVectorPassTargets =")
        final_capabilities = launch.index(
            "let resolvedMaterialExecutionCapabilities ="
        )
        fresh_candidate = launch.index("let compileSceneScriptPrograms:")
        self.assertLess(provisional_capabilities, material_consumer_c)
        self.assertLess(material_consumer_c, final_capabilities)
        self.assertLess(final_capabilities, fresh_candidate)
        consumer_slice = launch[material_consumer_c:final_capabilities]
        self.assertIn(
            "provisionalMaterialExecutionCapabilities.sceneScriptConsumerTargets",
            consumer_slice,
        )
        self.assertIn(
            ".intersection(propertyVectorPassCandidateTargets)",
            consumer_slice,
        )
        self.assertIn("guard committedPrograms.constructionReport.isComplete", launch)
        self.assertIn("passCompilation.instantiatedTargets", launch)
        self.assertNotIn("prunePassOwners", model + launch)
        self.assertNotIn("SceneMediaColorTransition", model + launch + frame)
        bounded_ownership = launch[
            launch.index("let boundedProducerTargets:"):
            launch.index("let sceneScriptScalarProgram =")
        ]
        self.assertIn('("property-vector"', bounded_ownership)
        self.assertNotIn('("media-color"', bounded_ownership)
        self.assertNotIn('("launch-origin"', bounded_ownership)
        self.assertNotIn('("audio-scaled"', bounded_ownership)
        self.assertNotIn('("hover-origin"', bounded_ownership)
        self.assertNotIn('("media-placeholder"', bounded_ownership)
        self.assertNotIn('("time-of-day"', bounded_ownership)
        self.assertIn("targets.count != definitionCount", bounded_ownership)
        for conflict in ("duplicate", "property", "timeline", "bounded-peer"):
            self.assertIn(
                f'boundedProducerConflicts.append("\\(name)/{conflict}")',
                bounded_ownership,
            )
        self.assertIn(
            "scene cursor events: schema=quickjs-ng-cursor-v1", startup_report
        )
        self.assertIn(
            "cursorDown,cursorMove,cursorUp,cursorClick", startup_report
        )
        self.assertIn("owner.exportedCursorEvents", cursor)
        self.assertIn("previousHits", cursor)
        self.assertNotIn("launchTransitionTargets", model)
        self.assertNotIn("SceneHoverOriginTransition", model + launch + frame)
        self.assertNotIn("SceneLaunchOriginTransitionProgramCompiler", model + launch + frame)
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
        self.assertLess(
            frame.index("sceneScriptCursorProgram.dispatch"),
            frame.index("SceneScriptMediaFrameCoordinator.evaluate"),
        )
        scalar_ownership = launch[
            launch.index("let sceneScriptScalarTargets ="):
            launch.index("let provisionalSceneScriptValueTargets =")
        ]
        self.assertIn(
            "guard sceneScriptScalarTargets.isDisjoint(",
            scalar_ownership,
        )
        self.assertIn("with: boundedSceneScriptTargets", scalar_ownership)
        self.assertNotIn("propertyBindingProgram", scalar_ownership)
        self.assertNotIn("timelineProgram", scalar_ownership)
        string_projection = launch.index("let sceneScriptStringTargets =")
        legacy_text_compile = launch.index("let textScriptProgram =")
        self.assertLess(string_projection, legacy_text_compile)
        self.assertIn(
            "excludedTargets: sceneScriptStringTargets",
            launch[
                legacy_text_compile:
                launch.index("let provisionalSceneScriptValueTargets =")
            ],
        )
        self.assertNotIn("SceneTimeOfDayEffectScriptProgram", launch)
        self.assertIn("let sceneScriptFrame = SceneScriptFrameInput(", frame)
        self.assertIn("surface: sceneScriptSurfaceInput", frame)
        timeline = frame.index("let timelineValues = launchContext.timelinePlaybackRuntime.values")
        preliminary = frame.index("let preliminaryForSceneScript =")
        evaluate = frame.index("SceneScriptMediaFrameCoordinator.evaluate(")
        final_snapshot = frame.index("let resolvedDynamicValues = surface.evaluationTransaction.evaluate")
        self.assertLess(timeline, preliminary)
        self.assertLess(preliminary, evaluate)
        self.assertLess(evaluate, final_snapshot)
        self.assertIn("teardownSceneScriptOwners(launchContext, reason: reason)", frame)
        self.assertNotIn("sceneScriptScalarProgram.invalidate()", frame)

if __name__ == "__main__":
    unittest.main()
