#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

void mwx_fixture_typed_value_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *scalar_user_source =
        "export function update(value) { return engine.userProperties.live; }";
    fixture->scalar_user = mwx_scene_quickjs_owner_create(
        fixture->domain, scalar_user_source, strlen(scalar_user_source),
        15, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->scalar_user != NULL, "scalar user properties compile", fixture->diagnostic);
    double scalar_user_output = 0;
    MWXSceneQuickJSFrameInput scalar_user_frame = {
        .time_of_day = 0.25, .frame_time = 1.0 / 60.0, .runtime = 2.0,
    };
    MWXSceneQuickJSResult scalar_user_result =
        mwx_scene_quickjs_owner_update_scalar_with_user_properties(
            fixture->scalar_user, 15, 0, &scalar_user_frame,
            "{\"live\":6}", strlen("{\"live\":6}"),
            &scalar_user_output, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        scalar_user_result == MWX_SCENE_QUICKJS_OK && scalar_user_output == 6,
        "scalar engine.userProperties",
        fixture->diagnostic
    );
    scalar_user_result =
        mwx_scene_quickjs_owner_update_scalar_with_user_properties(
            fixture->scalar_user, 15, 0, &scalar_user_frame,
            "{\"live\":6}", strlen("{\"live\":6}"),
            &scalar_user_output, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        scalar_user_result == MWX_SCENE_QUICKJS_OK && scalar_user_output == 6,
        "unchanged user property snapshot",
        fixture->diagnostic
    );
    scalar_user_result =
        mwx_scene_quickjs_owner_update_scalar_with_user_properties(
            fixture->scalar_user, 15, 0, &scalar_user_frame,
            "{\"live\":7}", strlen("{\"live\":7}"),
            &scalar_user_output, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        scalar_user_result == MWX_SCENE_QUICKJS_OK && scalar_user_output == 7,
        "changed user property snapshot",
        fixture->diagnostic
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
    fixture->vec3 = mwx_scene_quickjs_owner_create(
        fixture->domain, vec3_source, strlen(vec3_source),
        13, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->vec3 != NULL, "Vec3 compile", fixture->diagnostic);
    const double vec3_input[3] = {1, 2, 3};
    const double vec3_expected[3] = {4, 5, 0.25};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->vec3, 13, vec3_input,
        "{\"x\":4}",
        "{\"live\":5,\"tint\":{\"x\":0.25,\"y\":0.5,\"z\":1}}",
        MWX_SCENE_QUICKJS_OK, vec3_expected,
        "Vec3/scriptProperties/engine.userProperties"
    );

    const char *vec3_return_contract_source =
        "export function update(value) {"
        "thisLayer.angles = new Vec3(4, 5, 6);"
        "return value;"
        "}";
    fixture->vec3_return_contract = mwx_scene_quickjs_owner_create(
        fixture->domain, vec3_return_contract_source,
        strlen(vec3_return_contract_source), 131,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->vec3_return_contract != NULL,
        "Vec3 callback return contract compile",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->vec3_return_contract, 42,
        "Vec3 callback return contract layer identity"
    );
    const double vec3_return_expected[3] = {1, 2, 3};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->vec3_return_contract, 131, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, vec3_return_expected,
        "Vec3 callback returns host Vec3 input after layer mutation"
    );

    // Official Vec2/Vec3 contract: mix(other, amount: Number|Vec) is the
    // per-component lerp the corpus uses for audio-driven colors
    // (`3470948192` godrays color constant).
    const char *vec3_mix_source =
        "export function update(value) {"
        "return new Vec3(0,0,0).mix(new Vec3(10,20,30),0.5)"
        ".mix(new Vec3(0,0,0),new Vec3(0.4,0.5,0.6));}";
    fixture->vec3_mix = mwx_scene_quickjs_owner_create(
        fixture->domain, vec3_mix_source, strlen(vec3_mix_source), 135,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->vec3_mix != NULL, "Vec3 mix compile", fixture->diagnostic);
    const double vec3_mix_expected[3] = {3, 5, 6};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->vec3_mix, 135, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, vec3_mix_expected,
        "Vec3 mix with number and vector amounts"
    );

    const char *vec2_mix_source =
        "let saved;"
        "export function init(){saved=new Vec2(0,0).mix(new Vec2(4,8),0.25);}"
        "export function update(value){value.x=saved.x;value.y=saved.y;"
        "value.z=0;return value;}";
    fixture->vec2_mix = mwx_scene_quickjs_owner_create(
        fixture->domain, vec2_mix_source, strlen(vec2_mix_source), 136,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->vec2_mix != NULL, "Vec2 mix compile", fixture->diagnostic);
    const double vec2_mix_expected[3] = {1, 2, 0};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->vec2_mix, 136, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, vec2_mix_expected,
        "Vec2 mix with number amount"
    );

    const char *vec3_noop_mutation_source =
        "export function update(value) {"
        "thisLayer.angles = new Vec3(0, 0, 0);"
        "return 'LEON';"
        "}";
    fixture->vec3_noop_mutation = mwx_scene_quickjs_owner_create(
        fixture->domain, vec3_noop_mutation_source,
        strlen(vec3_noop_mutation_source), 134,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->vec3_noop_mutation != NULL,
        "Vec3 no-op mutation callback compile",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->vec3_noop_mutation, 42,
        "Vec3 no-op mutation callback layer identity"
    );
    fixture->failures += mwx_fixture_update_vec3(
        fixture->vec3_noop_mutation, 134, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, vec3_input,
        "Vec3 no-op layer mutation preserves typed input"
    );

    const char *nonfinite_angles_returns[] = {
        "'LEON'", "new Vec3(NaN,0,0)"
    };
    for (size_t index = 0; index < 2; ++index) {
        char source[256];
        snprintf(source, sizeof(source),
            "export function update(v){thisLayer.angles=new Vec3(NaN,0,0);return %s;}",
            nonfinite_angles_returns[index]);
        MWXSceneQuickJSOwner *invalid_angles = mwx_scene_quickjs_owner_create(
            fixture->domain, source, strlen(source), 823, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_configure_owner_layer(invalid_angles, 42, "invalid angles target");
        fixture->failures += mwx_fixture_update_vec3(invalid_angles, 823, vec3_input, "", "{}",
            MWX_SCENE_QUICKJS_BAD_RETURN, NULL,
            "rejected angles cannot authorize an invalid typed return");
        fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(invalid_angles) == 0,
            "rejected angles creates no passthrough mutation", fixture->diagnostic);
        mwx_scene_quickjs_owner_destroy(invalid_angles);
    }

    const char *vec3_invalid_return_source =
        "export function update(value) { return [value.x, value.y, value.z]; }";
    fixture->vec3_invalid_return = mwx_scene_quickjs_owner_create(
        fixture->domain, vec3_invalid_return_source,
        strlen(vec3_invalid_return_source), 132,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->vec3_invalid_return != NULL,
        "Vec3 invalid return fixture compile",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_vec3_diagnostic_contains(
        fixture->vec3_invalid_return, 132, vec3_input,
        MWX_SCENE_QUICKJS_BAD_RETURN, "(returned array)",
        "Vec3 array return diagnostic identifies shape"
    );

    const char *vec3_nonfinite_return_source =
        "export function update(value) { return {x:value.x, y:value.y>1?NaN:value.y, z:value.z}; }";
    fixture->vec3_nonfinite_return = mwx_scene_quickjs_owner_create(
        fixture->domain, vec3_nonfinite_return_source,
        strlen(vec3_nonfinite_return_source), 133,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->vec3_nonfinite_return != NULL,
        "Vec3 non-finite return fixture compile",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_vec3(
        fixture->vec3_nonfinite_return, 133, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_BAD_RETURN, NULL,
        "Vec3 callback non-finite component remains rejected"
    );
    // Retry contract: the same owner succeeds on a later frame with valid
    // data, proving the bad-return did not fuse the owner off.
    const double vec3_recovered_input[3] = {7, 0, 0};
    const double vec3_recovered_expected[3] = {7, 0, 0};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->vec3_nonfinite_return, 133, vec3_recovered_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, vec3_recovered_expected,
        "Vec3 bad-return owner recovers on the next frame"
    );

    const char *vec3_string_return_source =
        "export function update(value) { return 'LEON'; }";
    fixture->vec3_string_return = mwx_scene_quickjs_owner_create(
        fixture->domain, vec3_string_return_source,
        strlen(vec3_string_return_source), 135,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->vec3_string_return != NULL,
        "Vec3 string return fixture compile",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_vec3_diagnostic_contains(
        fixture->vec3_string_return, 135, vec3_input,
        MWX_SCENE_QUICKJS_BAD_RETURN, "(returned string)",
        "Vec3 string return diagnostic identifies shape"
    );

    const char *wecolor_source =
        "import * as WEColor from 'WEColor';\n"
        "export function update(value) {\n"
        "  return WEColor.hsv2rgb({x:0.5,y:1,z:1}).multiply(0.5);\n"
        "}";
    fixture->wecolor = mwx_scene_quickjs_owner_create(
        fixture->domain, wecolor_source, strlen(wecolor_source),
        52, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->wecolor != NULL, "WEColor.hsv2rgb compile", fixture->diagnostic);
    const double wecolor_expected[3] = {0, 0.5, 0.5};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->wecolor, 52, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, wecolor_expected,
        "WEColor.hsv2rgb returns Vec3"
    );

    const char *wecolor_wrap_source =
        "import * as WEColor from 'WEColor';\n"
        "export function update(value) {\n"
        "  return WEColor.hsv2rgb({x:2,y:1,z:1});\n"
        "}";
    fixture->wecolor_wrap = mwx_scene_quickjs_owner_create(
        fixture->domain, wecolor_wrap_source, strlen(wecolor_wrap_source),
        53, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->wecolor_wrap != NULL, "WEColor hue wrap compile", fixture->diagnostic);
    const double red[3] = {1, 0, 0};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->wecolor_wrap, 53, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, red, "WEColor hue wraps"
    );

    // The first four outputs are from the public official WEColor probe;
    // negative value uses the independent normalized-output scaling identity.
    // Negative/HDR values must survive; malformed/nonfinite/overflow must fail.
    static const struct {
        const char *input;
        MWXSceneQuickJSResult result;
        double rgb[3];
        const char *label;
    } hsv_cases[] = {
        {"{x:0.25,y:1,z:1}", MWX_SCENE_QUICKJS_OK, {0.5,1,0}, "WEColor normalized quarter hue"},
        {"{x:0.25,y:2.16,z:4.32}", MWX_SCENE_QUICKJS_OK, {-0.3456,4.32,-5.0112}, "WEColor finite HDR quarter hue"},
        {"{x:0.5,y:2.16,z:4.32}", MWX_SCENE_QUICKJS_OK, {-5.0112,4.32,4.32}, "WEColor finite HDR half hue"},
        {"{x:0.25,y:-0.2,z:4.32}", MWX_SCENE_QUICKJS_OK, {4.752,4.32,5.184}, "WEColor finite negative saturation"},
        {"{x:0.25,y:1,z:-2}", MWX_SCENE_QUICKJS_OK, {-1,-2,0}, "WEColor finite negative value scales normalized output"},
        {"undefined", MWX_SCENE_QUICKJS_EXCEPTION, {0}, "WEColor missing Vec3 rejects"},
        {"{x:0.25,y:1}", MWX_SCENE_QUICKJS_EXCEPTION, {0}, "WEColor incomplete Vec3 rejects"},
        {"{x:NaN,y:1,z:1}", MWX_SCENE_QUICKJS_EXCEPTION, {0}, "WEColor NaN hue rejects"},
        {"{x:0.25,y:Infinity,z:1}", MWX_SCENE_QUICKJS_EXCEPTION, {0}, "WEColor infinite saturation rejects"},
        {"{x:0.25,y:1,z:-Infinity}", MWX_SCENE_QUICKJS_EXCEPTION, {0}, "WEColor infinite value rejects"},
        {"{x:0.25,y:Number.MAX_VALUE,z:Number.MAX_VALUE}", MWX_SCENE_QUICKJS_BAD_RETURN, {0}, "WEColor finite overflow is not a typed publication"},
    };
    for (size_t index = 0; index < sizeof(hsv_cases) / sizeof(hsv_cases[0]); ++index) {
        char source[512];
        snprintf(source, sizeof(source),
            "import * as WEColor from 'WEColor';"
            "export var scriptProperties = createScriptProperties().addCheckbox({name:'recover',value:false}).finish();"
            "export function update(value) {"
            "if (scriptProperties.recover) return value; return WEColor.hsv2rgb(%s);}", hsv_cases[index].input);
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
            fixture->domain, source, strlen(source), 54, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(owner != NULL, hsv_cases[index].label, fixture->diagnostic);
        const MWXSceneQuickJSFrameInput frame = {.time_of_day = 0.25, .frame_time = 1.0 / 60.0, .runtime = 2};
        double output[3] = {0};
        const MWXSceneQuickJSResult status = mwx_scene_quickjs_owner_update_vector(
            owner, 54, vec3_input, 3, &frame, "{}", 2, "{}", 2, output, fixture->diagnostic, sizeof(fixture->diagnostic));
        bool passed = status == hsv_cases[index].result;
        if (status == MWX_SCENE_QUICKJS_OK) {
            for (size_t component = 0; component < 3; ++component)
                passed = passed && isfinite(output[component]) && fabs(output[component] - hsv_cases[index].rgb[component]) <= 1e-12;
        }
        fixture->failures += mwx_fixture_check(passed, hsv_cases[index].label, fixture->diagnostic);
        if (status == MWX_SCENE_QUICKJS_OK)
            printf("WEColor probe: %s status=%d rgb=[%.12g,%.12g,%.12g]\n",
                hsv_cases[index].label, status, output[0], output[1], output[2]);
        else
            printf("WEColor probe: %s status=%d typedPublication=false\n", hsv_cases[index].label, status);
        if (hsv_cases[index].result == MWX_SCENE_QUICKJS_BAD_RETURN)
            fixture->failures += mwx_fixture_update_vec3(owner, 54, vec3_input, "{\"recover\":true}", "{}",
                MWX_SCENE_QUICKJS_OK, vec3_input, "WEColor overflow owner recovers on the next finite frame");
        mwx_scene_quickjs_owner_destroy(owner);
    }

    const char *wecolor_normalize_source =
        "import * as WEColor from 'WEColor';\n"
        "export function update(value) {\n"
        "  return WEColor.normalizeColor(new Vec3(200,200,255));\n"
        "}";
    fixture->wecolor_normalize = mwx_scene_quickjs_owner_create(
        fixture->domain, wecolor_normalize_source, strlen(wecolor_normalize_source),
        55, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->wecolor_normalize != NULL, "WEColor.normalizeColor compile", fixture->diagnostic
    );
    const double normalized_blue[3] = {200.0 / 255.0, 200.0 / 255.0, 1};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->wecolor_normalize, 55, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_OK, normalized_blue,
        "WEColor.normalizeColor maps byte RGB to normalized Vec3"
    );

    const char *wecolor_normalize_invalid_source =
        "import * as WEColor from 'WEColor';\n"
        "export function update(value) {\n"
        "  return WEColor.normalizeColor(new Vec3(300,0,0));\n"
        "}";
    fixture->wecolor_normalize_invalid =
        mwx_scene_quickjs_owner_create(
            fixture->domain, wecolor_normalize_invalid_source,
            strlen(wecolor_normalize_invalid_source),
            56, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->wecolor_normalize_invalid != NULL,
        "invalid WEColor.normalizeColor compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_vec3(
        fixture->wecolor_normalize_invalid, 56, vec3_input, "", "{}",
        MWX_SCENE_QUICKJS_EXCEPTION, vec3_input,
        "WEColor.normalizeColor rejects components outside byte RGB"
    );

    const char *immutable_user_source =
        "'use strict'; export function update(value) {"
        "engine.userProperties.live = 9; return value; }";
    fixture->immutable_user = mwx_scene_quickjs_owner_create(
        fixture->domain, immutable_user_source, strlen(immutable_user_source),
        14, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->immutable_user != NULL, "immutable user compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_vec3(
        fixture->immutable_user, 14, vec3_input, "", "{\"live\":5}",
        MWX_SCENE_QUICKJS_EXCEPTION, vec3_input,
        "engine.userProperties is immutable"
    );

}

void mwx_fixture_string_value_cases(MWXSceneScriptQuickJSFixture *fixture) {
    // String properties take Numbers via JS ToString coercion: the corpus
    // computes dates as Numbers (`3122339805` World Time). Non-numbers stay
    // rejected so a broken script cannot silently publish junk.
    const char *numeric_string_source =
        "export function update(){return 25;}";
    fixture->numeric_string = mwx_scene_quickjs_owner_create(
        fixture->domain, numeric_string_source, strlen(numeric_string_source),
        24, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->numeric_string != NULL, "numeric string compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_string(
        fixture->numeric_string, 24, "safe", MWX_SCENE_QUICKJS_OK, "25",
        "numeric callback return coerced to string"
    );

    const char *fractional_string_source =
        "export function update(){return 1.5;}";
    fixture->fractional_string = mwx_scene_quickjs_owner_create(
        fixture->domain, fractional_string_source, strlen(fractional_string_source),
        25, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->fractional_string != NULL, "fractional string compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_string(
        fixture->fractional_string, 25, "safe", MWX_SCENE_QUICKJS_OK, "1.5",
        "fractional callback return coerced to string"
    );

    const char *bad_string_source =
        "export function update(){return {value:42};}";
    fixture->bad_string = mwx_scene_quickjs_owner_create(
        fixture->domain, bad_string_source, strlen(bad_string_source),
        26, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->bad_string != NULL, "bad string compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_string(
        fixture->bad_string, 26, "safe", MWX_SCENE_QUICKJS_BAD_RETURN, "",
        "non-numeric non-string callback return rejected"
    );

}
