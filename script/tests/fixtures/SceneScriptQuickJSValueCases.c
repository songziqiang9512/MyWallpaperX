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

    // Fixed official 2.8.0.42 contract: every component has abs(diff) < 1e-5.
    // Use a zero base at the boundary to avoid subtraction cancellation.
    // Only legal Vec3 operands are covered; this does not define type coercion.
    static const struct {
        const char *label;
        const char *left;
        const char *right;
        bool expected;
        bool bracket_call;
    } equals_cases[] = {
        {"independent equal values", "new Vec3(2,3,4)", "new Vec3(2,3,4)", true, false},
        {"copy", "new Vec3(-2,0.5,4)", "renamedLeft.copy()", true, false},
        {"copy constructor", "new Vec3(-2,0.5,4)", "new Vec3(renamedLeft)", true, false},
        {"renamed equivalent values", "new Vec3(2,3,4)", "new Vec3(4/2,6/2,2+2)", true, true},
        {"typed callback input", "value", "new Vec3(1,2,3)", true, false},
        {"zero constructors", "new Vec3()", "new Vec3(0,0,0)", true, false},
        {"x positive below", "new Vec3()", "new Vec3(0.000009,0,0)", true, false},
        {"x positive boundary", "new Vec3()", "new Vec3(0.00001,0,0)", false, false},
        {"x positive above", "new Vec3()", "new Vec3(0.000011,0,0)", false, false},
        {"x negative below", "new Vec3()", "new Vec3(-0.000009,0,0)", true, false},
        {"x negative boundary", "new Vec3()", "new Vec3(-0.00001,0,0)", false, false},
        {"x negative above", "new Vec3()", "new Vec3(-0.000011,0,0)", false, false},
        {"y positive below", "new Vec3()", "new Vec3(0,0.000009,0)", true, false},
        {"y positive boundary", "new Vec3()", "new Vec3(0,0.00001,0)", false, false},
        {"y positive above", "new Vec3()", "new Vec3(0,0.000011,0)", false, false},
        {"y negative below", "new Vec3()", "new Vec3(0,-0.000009,0)", true, false},
        {"y negative boundary", "new Vec3()", "new Vec3(0,-0.00001,0)", false, false},
        {"y negative above", "new Vec3()", "new Vec3(0,-0.000011,0)", false, false},
        {"z positive below", "new Vec3()", "new Vec3(0,0,0.000009)", true, false},
        {"z positive boundary", "new Vec3()", "new Vec3(0,0,0.00001)", false, false},
        {"z positive above", "new Vec3()", "new Vec3(0,0,0.000011)", false, false},
        {"z negative below", "new Vec3()", "new Vec3(0,0,-0.000009)", true, false},
        {"z negative boundary", "new Vec3()", "new Vec3(0,0,-0.00001)", false, false},
        {"z negative above", "new Vec3()", "new Vec3(0,0,-0.000011)", false, false},
        {"componentwise not Euclidean", "new Vec3()", "new Vec3(0.000008,-0.000008,0.000008)", true, false},
        {"componentwise reversed", "new Vec3(0.000008,-0.000008,0.000008)", "new Vec3()", true, true},
    };
    const char *equals_peer_source =
        "let healthyCalls=0;export function update(value){healthyCalls++;"
        "return new Vec3(value.x+1,healthyCalls,value.z);}";
    MWXSceneQuickJSOwner *equals_peer = mwx_scene_quickjs_owner_create(
        fixture->domain, equals_peer_source, strlen(equals_peer_source), 146,
        fixture->diagnostic, sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(
        equals_peer != NULL, "Vec3 equals healthy peer compile", fixture->diagnostic);
    size_t equals_callbacks_passed = 0, equals_peers_passed = 0, equals_peer_calls = 0;
    const size_t equals_case_count = sizeof(equals_cases) / sizeof(equals_cases[0]);
    for (size_t index = 0; index < equals_case_count; ++index) {
        char source[1536], label[160];
        const int written = snprintf(source, sizeof(source),
            "let callbackCount=0;export function update(value){"
            "const renamedLeft=%s;const candidate=%s;"
            "const before=[renamedLeft.x,renamedLeft.y,renamedLeft.z,"
            "candidate.x,candidate.y,candidate.z];"
            "const answer=%s;"
            "if(typeof answer!=='boolean')throw Error('equals must return Boolean');"
            "if(renamedLeft.x!==before[0]||renamedLeft.y!==before[1]||"
            "renamedLeft.z!==before[2]||candidate.x!==before[3]||"
            "candidate.y!==before[4]||candidate.z!==before[5])"
            "throw Error('equals mutated an operand');callbackCount++;"
            "return new Vec3(answer?1:0,callbackCount,value.z);}",
            equals_cases[index].left, equals_cases[index].right,
            equals_cases[index].bracket_call
                ? "renamedLeft['equals'](candidate)" : "renamedLeft.equals(candidate)");
        snprintf(label, sizeof(label), "Vec3 equals %s compile", equals_cases[index].label);
        if (written < 0 || (size_t)written >= sizeof(source)) {
            fixture->failures += mwx_fixture_check(false, label, "fixture source truncated");
            continue;
        }
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
            fixture->domain, source, strlen(source), 145,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(owner != NULL, label, fixture->diagnostic);
        if (owner == NULL) continue;
        for (size_t callback = 1; callback <= 2; ++callback) {
            const double expected[3] = {equals_cases[index].expected ? 1 : 0, (double)callback, 3};
            snprintf(label, sizeof(label), "Vec3 equals %s callback %zu", equals_cases[index].label, callback);
            const int failure = mwx_fixture_update_vec3(
                owner, 145, vec3_input, "", "{}", MWX_SCENE_QUICKJS_OK, expected, label);
            fixture->failures += failure;
            equals_callbacks_passed += failure == 0;
            if (equals_peer != NULL) {
                ++equals_peer_calls;
                const double peer_expected[3] = {2, (double)equals_peer_calls, 3};
                snprintf(label, sizeof(label), "Vec3 equals healthy peer after case %zu callback %zu", index, callback);
                const int peer_failure = mwx_fixture_update_vec3(
                    equals_peer, 146, vec3_input, "", "{}", MWX_SCENE_QUICKJS_OK, peer_expected, label);
                fixture->failures += peer_failure;
                equals_peers_passed += peer_failure == 0;
            }
        }
        mwx_scene_quickjs_owner_destroy(owner);
    }
    mwx_scene_quickjs_owner_destroy(equals_peer);
    printf("MWX_VEC3_EQUALS_CONTRACT {\"cases\":%zu,\"callbacksPassed\":%zu,\"peerCalls\":%zu,\"peersPassed\":%zu}\n",
        equals_case_count, equals_callbacks_passed, equals_peer_calls, equals_peers_passed);

    // Fixed official 2.8.0.42 finite-operand observations, with renamed and
    // equivalent expressions. Result class and RHS immutability below retain
    // this host's existing contract; the official probe did not measure them.
    static const struct {
        const char *method;
        double expected[4][3];
    } arithmetic_cases[] = {
        {"add", {{10,16,20}, {10,14,22}, {10,16,20}, {10,16,25}}},
        {"subtract", {{6,8,20}, {6,10,18}, {6,8,20}, {6,8,15}}},
        {"multiply", {{16,48,20}, {16,24,40}, {16,48,0}, {16,48,100}}},
        {"divide", {{4,3,20}, {4,6,10}, {4,3,INFINITY}, {4,3,4}}},
    };
    const char *arithmetic_operands[] = {
        "new Vec2(2,4)", "2", "new Vec3(2,4,0)", "new Vec3(2,4,5)"
    };
    for (size_t operation = 0; operation < 4; ++operation) {
        for (size_t operand = 0; operand < 4; ++operand) {
            char source[1024], label[128];
            const bool raw_infinity = isinf(arithmetic_cases[operation].expected[operand][2]);
            snprintf(source, sizeof(source),
                "export function update(value){"
                "const lhs=new Vec3(8,12,20);const rhs=%s;"
                "const rx=rhs.x,ry=rhs.y,rz=rhs.z;const result=lhs.%s(rhs);"
                "if(result===lhs||result===rhs||!(result instanceof Vec3)||"
                "lhs.x!==8||lhs.y!==12||lhs.z!==20||"
                "rhs.x!==rx||rhs.y!==ry||rhs.z!==rz)throw Error('arithmetic identity');%s}",
                arithmetic_operands[operand], arithmetic_cases[operation].method,
                raw_infinity
                    ? "if(result.z!==Infinity)throw Error('explicit zero divisor');return new Vec3(result.x,result.y,1);"
                    : "return result;");
            snprintf(label, sizeof(label), "Vec3 %s operand %s",
                arithmetic_cases[operation].method, arithmetic_operands[operand]);
            MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
                fixture->domain, source, strlen(source), 137,
                fixture->diagnostic, sizeof(fixture->diagnostic));
            fixture->failures += mwx_fixture_check(owner != NULL, label, fixture->diagnostic);
            if (owner == NULL) continue;
            double expected[3];
            memcpy(expected, arithmetic_cases[operation].expected[operand], sizeof(expected));
            if (raw_infinity) expected[2] = 1;
            fixture->failures += mwx_fixture_update_vec3(
                owner, 137, vec3_input, "", "{}", MWX_SCENE_QUICKJS_OK, expected, label);
            mwx_scene_quickjs_owner_destroy(owner);
        }

        char renamed_source[768], renamed_label[128];
        snprintf(renamed_source, sizeof(renamed_source),
            "export function update(renamedInput){"
            "const receiver=new Vec3(4,6,10).multiply(2);"
            "const delta=new Vec2(6/3,2+2);const next=receiver['%s'](delta);"
            "if(next===receiver||next===delta||!(next instanceof Vec3)||"
            "receiver.x!==8||receiver.y!==12||receiver.z!==20||"
            "delta.x!==2||delta.y!==4)throw Error('renamed arithmetic identity');return next;}",
            arithmetic_cases[operation].method);
        snprintf(renamed_label, sizeof(renamed_label), "Vec3 %s renamed equivalent Vec2",
            arithmetic_cases[operation].method);
        MWXSceneQuickJSOwner *renamed = mwx_scene_quickjs_owner_create(
            fixture->domain, renamed_source, strlen(renamed_source), 138,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(renamed != NULL, renamed_label, fixture->diagnostic);
        if (renamed != NULL) {
            fixture->failures += mwx_fixture_update_vec3(
                renamed, 138, vec3_input, "", "{}", MWX_SCENE_QUICKJS_OK,
                arithmetic_cases[operation].expected[0], renamed_label);
            mwx_scene_quickjs_owner_destroy(renamed);
        }
    }

    // Constructor lifting and invalid explicit Vec3/scalar inputs are separate
    // from the nominal Vec2 operand rule. No plain-object API is added here.
    static const struct {
        const char *expression;
        MWXSceneQuickJSResult status;
        double expected[3];
        const char *label;
    } arithmetic_neighbors[] = {
        {"new Vec3(new Vec2(2,4))", MWX_SCENE_QUICKJS_OK, {2,4,0}, "Vec3 Vec2 constructor still zero lifts"},
        {"new Vec3(2,4)", MWX_SCENE_QUICKJS_OK, {2,4,0}, "Vec3 two-number constructor still zero lifts"},
        {"new Vec3(2)", MWX_SCENE_QUICKJS_OK, {2,2,2}, "Vec3 scalar constructor still splats"},
        {"new Vec3(8,12,20).multiply(new Vec3(2,4,undefined))", MWX_SCENE_QUICKJS_BAD_RETURN, {0}, "explicit undefined Vec3 component is not a missing dimension"},
        {"new Vec3(8,12,20).add(new Vec3(2,4,NaN))", MWX_SCENE_QUICKJS_BAD_RETURN, {0}, "explicit NaN Vec3 component stays invalid"},
        {"new Vec3(8,12,20).add(new Vec3(2,4,Infinity))", MWX_SCENE_QUICKJS_BAD_RETURN, {0}, "explicit infinite Vec3 component stays invalid"},
        {"new Vec3(8,12,20).multiply(NaN)", MWX_SCENE_QUICKJS_BAD_RETURN, {0}, "nonfinite scalar does not become Vec2"},
        {"new Vec3(8,12,20).multiply({x:2,y:4})", MWX_SCENE_QUICKJS_BAD_RETURN, {0}, "plain xy object is not classified as Vec2"},
    };
    for (size_t index = 0; index < sizeof(arithmetic_neighbors) / sizeof(arithmetic_neighbors[0]); ++index) {
        char source[512];
        snprintf(source, sizeof(source), "export function update(v){return %s;}",
            arithmetic_neighbors[index].expression);
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
            fixture->domain, source, strlen(source), 139,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(owner != NULL, arithmetic_neighbors[index].label, fixture->diagnostic);
        if (owner == NULL) continue;
        fixture->failures += mwx_fixture_update_vec3(
            owner, 139, vec3_input, "", "{}", arithmetic_neighbors[index].status,
            arithmetic_neighbors[index].expected, arithmetic_neighbors[index].label);
        mwx_scene_quickjs_owner_destroy(owner);
    }

    const char *explicit_zero_divisor_source =
        "export function update(v){if(v.x===8)return v.divide(new Vec3(2,4,0));return v;}";
    MWXSceneQuickJSOwner *explicit_zero_divisor = mwx_scene_quickjs_owner_create(
        fixture->domain, explicit_zero_divisor_source, strlen(explicit_zero_divisor_source), 140,
        fixture->diagnostic, sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(explicit_zero_divisor != NULL,
        "explicit zero divisor compile", fixture->diagnostic);
    if (explicit_zero_divisor != NULL) {
        const double nonzero_z_input[3] = {8,12,20};
        fixture->failures += mwx_fixture_update_vec3(
            explicit_zero_divisor, 140, nonzero_z_input, "", "{}",
            MWX_SCENE_QUICKJS_BAD_RETURN, NULL, "explicit zero divide raw Infinity cannot publish as typed Vec3");
        fixture->failures += mwx_fixture_update_vec3(
            explicit_zero_divisor, 140, vec3_input, "", "{}", MWX_SCENE_QUICKJS_OK,
            vec3_input, "same owner recovers after explicit nonfinite arithmetic return");
        mwx_scene_quickjs_owner_destroy(explicit_zero_divisor);
    }

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
