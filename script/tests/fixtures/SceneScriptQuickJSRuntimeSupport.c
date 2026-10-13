#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

int mwx_fixture_check(int condition, const char *label, const char *diagnostic) {
    if (condition) return 0;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic ? diagnostic : "");
    return 1;
}


int mwx_fixture_update_at(
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
    return mwx_fixture_check(
        actual == expected
            && (expected != MWX_SCENE_QUICKJS_OK || output == expected_output),
        label,
        diagnostic
    );
}


int mwx_fixture_update(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
) {
    return mwx_fixture_update_at(
        owner, generation, input, 1.0 / 60.0, 2.0,
        expected, expected_output, label
    );
}


int mwx_fixture_update_bool(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t input,
    MWXSceneQuickJSResult expected,
    uint32_t expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    uint32_t output = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_update_bool_with_properties(
            owner, generation, input, &frame, NULL, 0, "{}", 2,
            &output, diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(
        actual == expected &&
            (expected != MWX_SCENE_QUICKJS_OK || output == expected_output),
        label,
        diagnostic
    );
}


int mwx_fixture_update_effectful_bool(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t input,
    MWXSceneQuickJSResult expected,
    uint32_t expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    uint32_t output = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_update_effectful_bool_with_properties(
            owner, generation, input, &frame, NULL, 0, "{}", 2,
            &output, diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(
        actual == expected &&
            (expected != MWX_SCENE_QUICKJS_OK || output == expected_output),
        label,
        diagnostic
    );
}


int mwx_fixture_update_string(
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
        owner, generation, input, strlen(input), &frame,
        "", 0, "{}", 2,
        output, sizeof(output), &output_length, diagnostic, sizeof(diagnostic)
    );
    return mwx_fixture_check(
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


int mwx_fixture_update_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const double input[3],
    const char *script_properties,
    const char *mwx_fixture_user_properties,
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
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_vector(
        owner, generation, input, 3, &frame,
        script_properties, strlen(script_properties),
        mwx_fixture_user_properties, strlen(mwx_fixture_user_properties),
        output, diagnostic, sizeof(diagnostic)
    );
    return mwx_fixture_check(
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


int mwx_fixture_update_vec3_diagnostic_contains(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const double input[3],
    MWXSceneQuickJSResult expected,
    const char *expected_diagnostic,
    const char *label
) {
    char diagnostic[512] = {0};
    double output[3] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_vector(
        owner, generation, input, 3, &frame, "", 0, "{}", 2,
        output, diagnostic, sizeof(diagnostic)
    );
    return mwx_fixture_check(
        actual == expected && strstr(diagnostic, expected_diagnostic) != NULL,
        label,
        diagnostic
    );
}
