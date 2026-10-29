#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

void mwx_fixture_scalar_runtime_cases(MWXSceneScriptQuickJSFixture *fixture) {
    fixture->positive = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "'use strict';\n"
        "export let __workshopId = 'contract';\n"
        "export function init(value) { return value + 1; }\n"
        "export function update(value) {\n"
        "  if (thisLayer.id !== 42 || thisLayer.name !== 'C1') throw new Error('layer identity');\n"
        "  const origin = thisLayer.origin;\n"
        "  if (origin.x !== 4 || origin.y !== 5 || origin.z !== 6) throw new Error('layer origin');\n"
        "  const size = thisLayer.size; size.x = -1;\n"
        "  if (!(size instanceof Vec2) || thisLayer.size.x !== 300 || thisLayer.size.y !== 400) throw new Error('layer size');\n"
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
            "  const size = thisLayer.size; size.x = -1;\n"
            "  if (!(size instanceof Vec2) || thisLayer.size.x !== 300 || thisLayer.size.y !== 400) throw new Error('layer size');\n"
            "  if (thisLayer.getEffectCount() !== 3) throw new Error('effect count');\n"
            "  const effect = thisLayer.getEffect('history');\n"
            "  if (effect.name !== 'history') throw new Error('effect name');\n"
            "  effect.executeMaterialFunction('clearHistory');\n"
            "  return value * 2;\n"
            "}"
        ),
        1,
        fixture->diagnostic,
        sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->positive != NULL, "positive compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->positive, 42, "positive layer identity"
    );
    fixture->failures += mwx_fixture_configure_effects(fixture->positive, 3, 2, "history", "positive effect catalog");
    fixture->failures += mwx_fixture_update(
        fixture->positive, 1, 3, MWX_SCENE_QUICKJS_OK, 8, "init/update"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_material_function_count(fixture->positive) == 1,
        "mutation count",
        ""
    );
    fixture->failures += mwx_fixture_mutation(fixture->positive, 0, 2, "clearHistory", "mutation identity");

    const char *console_mutation_source =
        "console=console||{};"
        "console.warn=function(){};"
        "export function update(value){"
        "return console.warn('author diagnostic')===undefined?value+2:0;}";
    fixture->console_mutation = mwx_scene_quickjs_owner_create(
        fixture->domain, console_mutation_source, strlen(console_mutation_source),
        66, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->console_mutation != NULL,
        "author console rebinding and method installation compile", fixture->diagnostic
    );
    if (fixture->console_mutation != NULL) {
        fixture->failures += mwx_fixture_update(
            fixture->console_mutation, 66, 3, MWX_SCENE_QUICKJS_OK, 5,
            "author console compatibility sink remains executable"
        );
    }

    fixture->cross_owner = mwx_scene_quickjs_owner_create(
        fixture->domain,
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
        10, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->cross_owner != NULL, "cross-owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_effects(fixture->cross_owner, 10, 0, NULL, "cross-owner catalog");
    fixture->failures += mwx_fixture_update(
        fixture->cross_owner, 10, 3, MWX_SCENE_QUICKJS_OK, 3, "cross-owner callback"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_material_function_count(fixture->cross_owner) == 1,
        "cross-owner mutation count",
        ""
    );
    fixture->failures += mwx_fixture_update(
        fixture->positive, 1, 7, MWX_SCENE_QUICKJS_OK, 14, "second callback"
    );
    fixture->failures += mwx_fixture_mutation(fixture->positive, 0, 2, "clearHistory", "cross-owner isolation");
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_material_function_count(fixture->positive) == 1,
        "mutation reset",
        ""
    );

    fixture->isolated = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value) { return value + 10; }",
        strlen("export function update(value) { return value + 10; }"),
        2,
        fixture->diagnostic,
        sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->isolated != NULL, "owner isolation compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13, "owner isolation"
    );

    fixture->metadata_only = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export let __workshopId = 'metadata-only';",
        strlen("export let __workshopId = 'metadata-only';"),
        7, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->metadata_only != NULL, "export metadata compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->metadata_only, 7, 5, MWX_SCENE_QUICKJS_OK, 5, "missing callbacks preserve input"
    );

    fixture->time_of_day = mwx_scene_quickjs_owner_create(
        fixture->domain,
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
        11, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->time_of_day != NULL, "WEMath compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->time_of_day, 11, 0, MWX_SCENE_QUICKJS_OK, 1,
        "WEMath engine.timeOfDay"
    );


    const char *screensaver_source =
        "'use strict'; const moduleMode=engine.isScreensaver();"
        "if(typeof engine.isScreensaver!=='function'||engine.isScreensaver.length!==0||"
        "typeof moduleMode!=='boolean'||moduleMode!==false)throw new Error('module mode');"
        "let moduleWriteRejected=false;try{engine.isScreensaver=()=>true;}"
        "catch(e){moduleWriteRejected=e instanceof TypeError;}"
        "if(!moduleWriteRejected)throw new Error('module method writable');"
        "let initialized=false,changed=false,fired=false;"
        "function desktop(){const mode=engine.isScreensaver();"
        "if(typeof mode!=='boolean'||mode!==false)throw new Error('callback mode');return !mode;}"
        "export function init(v){initialized=desktop();"
        "engine.setTimeout(()=>{fired=desktop();},50);return v;}"
        "export function applyUserProperties(){changed=desktop();}"
        "export function update(v){if(!initialized||!desktop())throw new Error('desktop init');"
        "return v+(changed?2:0)+(fired?4:0);}";
    MWXSceneQuickJSOwner *screensaver = mwx_scene_quickjs_owner_create(
        fixture->domain, screensaver_source, strlen(screensaver_source),
        86, fixture->diagnostic, sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(screensaver != NULL,
        "desktop screensaver query at module evaluation", fixture->diagnostic);
    if (screensaver != NULL) {
        fixture->failures += mwx_fixture_update_at(screensaver,86,3,0,0,
            MWX_SCENE_QUICKJS_OK,3,"strict false in init and first update");
        mwx_scene_quickjs_owner_commit_layer_mutations(screensaver);
        MWXSceneQuickJSFrameInput event_frame = {.frame_time=1.0/60.0,.runtime=0};
        fixture->failures += mwx_fixture_check(
            mwx_scene_quickjs_owner_dispatch_user_properties(screensaver,86,
                "{}",2,NULL,0,&event_frame,"{}",2,
                fixture->diagnostic,sizeof(fixture->diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "screensaver query in property event",fixture->diagnostic);
        mwx_scene_quickjs_owner_commit_layer_mutations(screensaver);
        fixture->failures += mwx_fixture_update_at(screensaver,86,3,0.2,0.2,
            MWX_SCENE_QUICKJS_OK,9,"event and due timer observe desktop mode");
        mwx_scene_quickjs_owner_commit_layer_mutations(screensaver);
    }
    const char *renamed_screensaver_source =
        "const atLoad=engine.isScreensaver();if(atLoad!==false)throw new Error('renamed module');"
        "let permitted=false;export function init(seed){permitted=!engine.isScreensaver();"
        "return seed+2;}export function update(seed){const hidden=engine.isScreensaver();"
        "if(typeof hidden!=='boolean'||!permitted)throw new Error('renamed mode');"
        "if(hidden)return -100;else return seed+3;}";
    MWXSceneQuickJSOwner *renamed_screensaver = mwx_scene_quickjs_owner_create(
        fixture->domain,renamed_screensaver_source,strlen(renamed_screensaver_source),
        87,fixture->diagnostic,sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(renamed_screensaver != NULL,
        "renamed equivalent desktop branch",fixture->diagnostic);
    if (renamed_screensaver != NULL) {
        fixture->failures += mwx_fixture_update(renamed_screensaver,87,3,
            MWX_SCENE_QUICKJS_OK,8,"renamed init and inverse branch");
        fixture->failures += mwx_fixture_update(renamed_screensaver,87,4,
            MWX_SCENE_QUICKJS_OK,7,"renamed later frame");
    }
    mwx_scene_quickjs_owner_destroy(renamed_screensaver);
    const char *screensaver_failures[] = {
        "'use strict';export function update(v){engine.isScreensaver=()=>true;return v;}",
        "'use strict';export function update(v){engine={isScreensaver:()=>true};return v;}",
        "export function update(v){return engine.isScreensaverUnknown()?v:0;}",
    };
    for (size_t index=0;index<sizeof(screensaver_failures)/sizeof(screensaver_failures[0]);++index) {
        const char *source=screensaver_failures[index];
        MWXSceneQuickJSOwner *rejected=mwx_scene_quickjs_owner_create(
            fixture->domain,source,strlen(source),88,fixture->diagnostic,sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(rejected != NULL,
            "screensaver negative owner compiles",fixture->diagnostic);
        if (rejected != NULL) {
            fixture->failures += mwx_fixture_update(rejected,88,3,
                MWX_SCENE_QUICKJS_EXCEPTION,0,"readonly global/method or unknown API rejects");
            fixture->failures += mwx_fixture_update(rejected,88,3,
                MWX_SCENE_QUICKJS_DISABLED,0,"failed query owner remains disabled");
        }
        mwx_scene_quickjs_owner_destroy(rejected);
        if (screensaver != NULL) fixture->failures += mwx_fixture_update_at(
            screensaver,86,3,0.2,0.2,MWX_SCENE_QUICKJS_OK,9,
            "query failure cannot poison healthy desktop owner");
    }
    mwx_scene_quickjs_owner_destroy(screensaver);

    const char *surface_input_source =
        "'use strict';\n"
        "export function update(value) {\n"
        "  const world = input.cursorWorldPosition;\n"
        "  const screen = input.cursorScreenPosition;\n"
        "  const canvas = engine.canvasSize;\n"
        "  const resolution = engine.screenResolution;\n"
        "  if (!(screen instanceof Vec2) || !(canvas instanceof Vec2) ||\n"
        "      !(resolution instanceof Vec2) ||\n"
        "      !Object.isFrozen(input) || !Object.isFrozen(world) ||\n"
        "      !Object.isFrozen(screen) || !Object.isFrozen(canvas) ||\n"
        "      !Object.isFrozen(resolution)) {\n"
        "    throw new Error('mutable surface snapshot');\n"
        "  }\n"
        "  const divisor = new Vec3(canvas, 1).divide(new Vec3(10, 5, 1));\n"
        "  const arithmetic = new Vec3(15, 15, 2).subtract(divisor);\n"
        "  const original = new Vec2(3,4); const unit = original.normalize();\n"
        "  if (original.length() !== 5 || original.x !== 3 || unit === original ||\n"
        "      Math.abs(unit.x-0.6)>1e-12 || Math.abs(unit.y-0.8)>1e-12 ||\n"
        "      new Vec2().normalize().length() !== 0 ||\n"
        "      !Number.isFinite(new Vec2(1e300,1e300).length())) throw new Error('Vec2 norm');\n"
        "  const pair = new Vec2('2 3').add(new Vec2(4)).multiply(2);\n"
        "  return value + world.x + world.y + world.z +\n"
        "    screen.x + screen.y + canvas.x + canvas.y +\n"
        "    resolution.x + resolution.y +\n"
        "    (input.cursorLeftDown ? 1 : 0) +\n"
        "    arithmetic.x + arithmetic.y + arithmetic.z + pair.x + pair.y;\n"
        "}";
    fixture->surface_input = mwx_scene_quickjs_owner_create(
        fixture->domain, surface_input_source, strlen(surface_input_source),
        48, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->surface_input != NULL, "surface input compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->surface_input, 48, 1, MWX_SCENE_QUICKJS_OK, 589,
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
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_update_scalar(
            fixture->surface_input, 48, 1, &refreshed_surface_frame,
            &refreshed_surface_output, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && refreshed_surface_output == 933,
        "surface input refreshes per callback",
        fixture->diagnostic
    );

    const char *immutable_surface_source =
        "'use strict'; export function update(value) {"
        "input.cursorWorldPosition.x = 99; return value; }";
    fixture->immutable_surface = mwx_scene_quickjs_owner_create(
        fixture->domain, immutable_surface_source, strlen(immutable_surface_source),
        49, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->immutable_surface != NULL, "immutable surface compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->immutable_surface, 49, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "surface snapshots are immutable"
    );
    fixture->failures += mwx_fixture_update(
        fixture->isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "surface mutation failure preserves peer owner"
    );

    const char *global_surface_source =
        "let rejected = false; "
        "try { input.cursorWorldPosition; } catch (error) { rejected = true; } "
        "export function update(value) { return rejected ? value + 1 : -1; }";
    fixture->global_surface = mwx_scene_quickjs_owner_create(
        fixture->domain, global_surface_source, strlen(global_surface_source),
        50, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->global_surface != NULL,
        "global phase rejects surface input",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->global_surface, 50, 1, MWX_SCENE_QUICKJS_OK, 2,
        "global phase rejection is observable"
    );

    MWXSceneQuickJSFrameInput missing_surface_frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    double missing_surface_output = 0;
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_update_scalar(
            fixture->surface_input, 48, 1, &missing_surface_frame,
            &missing_surface_output, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_EXCEPTION,
        "missing exact surface fails only consumer callback",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "missing surface failure preserves peer owner"
    );

    MWXSceneQuickJSFrameInput invalid_surface_frame = missing_surface_frame;
    invalid_surface_frame.has_surface_input = 1;
    invalid_surface_frame.canvas_width = 0;
    invalid_surface_frame.canvas_height = 50;
    invalid_surface_frame.screen_width = 200;
    invalid_surface_frame.screen_height = 100;
    fixture->invalid_surface = mwx_scene_quickjs_owner_create(
        fixture->domain, surface_input_source, strlen(surface_input_source),
        51, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->invalid_surface != NULL, "invalid surface owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_update_scalar(
            fixture->invalid_surface, 51, 1, &invalid_surface_frame,
            &missing_surface_output, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_EXCEPTION,
        "invalid surface ABI fails closed",
        fixture->diagnostic
    );

    fixture->wemath_mix = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "import * as WEMath from 'WEMath';\n"
        "export function update(value) { return WEMath.mix(value, 10, 0.25); }",
        strlen(
            "import * as WEMath from 'WEMath';\n"
            "export function update(value) { return WEMath.mix(value, 10, 0.25); }"
        ),
        28, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->wemath_mix != NULL, "WEMath.mix compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->wemath_mix, 28, 2, MWX_SCENE_QUICKJS_OK, 4,
        "WEMath.mix scalar interpolation"
    );

    fixture->invalid_wemath_mix = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "import * as WEMath from 'WEMath';\n"
        "export function update(value) { return WEMath.mix(value, Infinity, 0.5); }",
        strlen(
            "import * as WEMath from 'WEMath';\n"
            "export function update(value) { return WEMath.mix(value, Infinity, 0.5); }"
        ),
        29, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->invalid_wemath_mix != NULL, "invalid WEMath.mix compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->invalid_wemath_mix, 29, 2, MWX_SCENE_QUICKJS_BAD_RETURN, 2,
        "WEMath.mix Infinity cannot publish as a typed scalar"
    );

    // VM numeric values may remain nonfinite until a typed consumer reads them.
    // These cases preserve argument conversion failures and unbounded mixing.
    static const struct {
        const char *body;
        MWXSceneQuickJSResult status;
        double output;
        const char *label;
    } mix_cases[] = {
        {"return blend(seed,10,1.5);", MWX_SCENE_QUICKJS_OK, 14,
         "WEMath.mix extrapolates above one"},
        {"return blend(seed,10,-0.5);", MWX_SCENE_QUICKJS_OK, -2,
         "WEMath.mix extrapolates below zero"},
        {"const raw=blend(undefined,undefined,0.1);"
         "return Number.isNaN(raw)?seed+7:-1;", MWX_SCENE_QUICKJS_OK, 9,
         "WEMath.mix undefined NaN can be handled inside JavaScript"},
        {"const raw=blend(seed,Infinity,0.5);"
         "return raw===Infinity?seed+7:-1;", MWX_SCENE_QUICKJS_OK, 9,
         "WEMath.mix Infinity can be handled inside JavaScript"},
        {"const raw=blend(1e308,-1e308,0.5);"
         "return raw===-Infinity?seed+7:-1;", MWX_SCENE_QUICKJS_OK, 9,
         "WEMath.mix finite-input overflow stays a VM numeric value"},
        {"return blend(seed,10);", MWX_SCENE_QUICKJS_EXCEPTION, 0,
         "WEMath.mix missing argument still throws"},
        {"return blend(seed,10,0.5,0);", MWX_SCENE_QUICKJS_EXCEPTION, 0,
         "WEMath.mix extra argument still throws"},
        {"return blend(Symbol('unconvertible'),10,0.5);",
         MWX_SCENE_QUICKJS_EXCEPTION, 0,
         "WEMath.mix nonconvertible input still throws"},
    };
    for (size_t index = 0; index < sizeof(mix_cases) / sizeof(mix_cases[0]); ++index) {
        char source[512];
        snprintf(source, sizeof(source),
            "import {mix as blend} from 'WEMath';"
            "export function update(seed){%s}", mix_cases[index].body);
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
            fixture->domain, source, strlen(source), 281,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(owner != NULL,
            mix_cases[index].label, fixture->diagnostic);
        if (owner == NULL) continue;
        fixture->failures += mwx_fixture_update(owner, 281, 2,
            mix_cases[index].status, mix_cases[index].output, mix_cases[index].label);
        mwx_scene_quickjs_owner_destroy(owner);
    }

    // Existing native Vec2 consumption reads only its finite x/y prefix. The
    // Vec3 constructor must not turn an unused NaN z into a callback exception.
    const char *mix_prefix_source =
        "import {mix as blend} from 'WEMath';"
        "export function init(pair){"
        "if(!(pair instanceof Vec2)||pair.z!==undefined)throw Error('init shape');"
        "return new Vec3(pair.x,pair.y,blend(pair.z,pair.z,0.1));}"
        "export function update(pair){"
        "if(!(pair instanceof Vec2)||pair.z!==undefined)throw Error('update shape');"
        "const unused=blend(pair.z,pair.z,0.1);"
        "if(!Number.isNaN(unused))throw Error('missing lane');"
        "return new Vec3(pair.x===9?unused:pair.x+1,"
        "pair.y===9?unused:pair.y+2,unused);}";
    MWXSceneQuickJSOwner *mix_prefix = mwx_scene_quickjs_owner_create(
        fixture->domain, mix_prefix_source, strlen(mix_prefix_source), 282,
        fixture->diagnostic, sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(mix_prefix != NULL,
        "WEMath.mix Vec2 consumed prefix compile", fixture->diagnostic);
    MWXSceneQuickJSFrameInput mix_frame = {
        .time_of_day = 0.25, .frame_time = 1.0 / 60.0, .runtime = 2.0,
    };
    if (mix_prefix != NULL) {
        const double initial_pair[2] = {2, 3};
        struct { double before, xy[2], after; } guarded = {101, {0, 0}, 303};
        uint32_t initialized = 0;
        MWXSceneQuickJSResult status = mwx_scene_quickjs_owner_initialize_vector(
            mix_prefix, 282, initial_pair, 2, &mix_frame, "", 0, "{}", 2,
            guarded.xy, &initialized, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(status == MWX_SCENE_QUICKJS_OK &&
            initialized == 1 && guarded.xy[0] == 2 && guarded.xy[1] == 3 &&
            guarded.before == 101 && guarded.after == 303,
            "Vec2 init accepts finite Vec3 prefix and preserves output bounds",
            fixture->diagnostic);
        if (status == MWX_SCENE_QUICKJS_OK)
            mwx_scene_quickjs_owner_commit_layer_mutations(mix_prefix);
        static const struct {
            double xy[2];
            MWXSceneQuickJSResult status;
            const char *label;
        } prefix_cases[] = {
            {{2, 3}, MWX_SCENE_QUICKJS_OK, "Vec2 update ignores unused NaN z"},
            {{9, 3}, MWX_SCENE_QUICKJS_BAD_RETURN, "Vec2 consumed NaN x rejects"},
            {{2, 3}, MWX_SCENE_QUICKJS_OK, "same Vec2 owner recovers after NaN x"},
            {{2, 9}, MWX_SCENE_QUICKJS_BAD_RETURN, "Vec2 consumed NaN y rejects"},
            {{2, 3}, MWX_SCENE_QUICKJS_OK, "same Vec2 owner recovers after NaN y"},
        };
        for (size_t index = 0; index < sizeof(prefix_cases) / sizeof(prefix_cases[0]); ++index) {
            guarded.xy[0] = guarded.xy[1] = -1;
            status = mwx_scene_quickjs_owner_update_vector(mix_prefix, 282,
                prefix_cases[index].xy, 2, &mix_frame, "", 0, "{}", 2,
                guarded.xy, fixture->diagnostic, sizeof(fixture->diagnostic));
            fixture->failures += mwx_fixture_check(status == prefix_cases[index].status &&
                guarded.before == 101 && guarded.after == 303 &&
                (status != MWX_SCENE_QUICKJS_OK ||
                    (guarded.xy[0] == 3 && guarded.xy[1] == 5)),
                prefix_cases[index].label, fixture->diagnostic);
        }
        mwx_scene_quickjs_owner_destroy(mix_prefix);
    }
    const char *mix_vec3_source =
        "import {mix as blend} from 'WEMath';"
        "export function update(v){return new Vec3(v.x+1,v.y+2,"
        "blend(undefined,undefined,0.1));}";
    MWXSceneQuickJSOwner *mix_vec3 = mwx_scene_quickjs_owner_create(
        fixture->domain, mix_vec3_source, strlen(mix_vec3_source), 283,
        fixture->diagnostic, sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(mix_vec3 != NULL,
        "WEMath.mix Vec3 consumed z compile", fixture->diagnostic);
    if (mix_vec3 != NULL) {
        const double input[3] = {2, 3, 0};
        fixture->failures += mwx_fixture_update_vec3(mix_vec3, 283, input, "", "{}",
            MWX_SCENE_QUICKJS_BAD_RETURN, NULL,
            "same finite xy and NaN z cannot publish as typed Vec3");
        mwx_scene_quickjs_owner_destroy(mix_vec3);
    }

    fixture->wemath_angles = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "import * as WEMath from 'WEMath';\n"
        "export function update(value) {\n"
        "  const degrees = WEMath.deg2rad * 180;\n"
        "  const radians = WEMath.rad2deg * Math.PI;\n"
        "  return Math.abs(degrees - Math.PI) < 1e-12 &&\n"
        "    Math.abs(radians - 180) < 1e-12 ? value + 1 : -1;\n"
        "}",
        strlen(
            "import * as WEMath from 'WEMath';\n"
            "export function update(value) {\n"
            "  const degrees = WEMath.deg2rad * 180;\n"
            "  const radians = WEMath.rad2deg * Math.PI;\n"
            "  return Math.abs(degrees - Math.PI) < 1e-12 &&\n"
            "    Math.abs(radians - 180) < 1e-12 ? value + 1 : -1;\n"
            "}"
        ),
        57, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->wemath_angles != NULL, "WEMath angle constants compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->wemath_angles, 57, 2, MWX_SCENE_QUICKJS_OK, 3,
        "WEMath degree and radian constants"
    );

    const char *wevector_source =
        "import * as WEVector from 'WEVector';\n"
        "export function update(value) {\n"
        "  const up = WEVector.angleVector2(90);\n"
        "  const left = WEVector.angleVector2(180);\n"
        "  const angle = WEVector.vectorAngle2(new Vec2(0, -1));\n"
        "  const zero = WEVector.vectorAngle2(new Vec2(0, 0));\n"
        "  const roundTrip = WEVector.vectorAngle2(WEVector.angleVector2(135));\n"
        "  const lifted = new Vec3(WEVector.angleVector2(0));\n"
        "  const numericPair = new Vec3(2, 3);\n"
        "  return up instanceof Vec2 && Math.abs(up.x) < 1e-12 &&\n"
        "    Math.abs(up.y - 1) < 1e-12 && Math.abs(left.x + 1) < 1e-12 &&\n"
        "    Math.abs(left.y) < 1e-12 && angle === -90 && zero === 0 &&\n"
        "    Math.abs(roundTrip - 135) < 1e-12 && lifted.x === 1 &&\n"
        "    lifted.y === 0 && lifted.z === 0 && numericPair.x === 2 &&\n"
        "    numericPair.y === 3 && numericPair.z === 0 ? value + 1 : -1;\n"
        "}";
    fixture->wevector = mwx_scene_quickjs_owner_create(
        fixture->domain, wevector_source, strlen(wevector_source),
        58, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->wevector != NULL, "WEVector compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->wevector, 58, 2, MWX_SCENE_QUICKJS_OK, 3,
        "WEVector cardinal directions zero and 135 degree round trip"
    );

    const char *invalid_wevector_source =
        "import * as WEVector from 'WEVector';\n"
        "export function update(value) {\n"
        "  let angleRejected = false;\n"
        "  try { WEVector.angleVector2(Infinity); }\n"
        "  catch (error) { angleRejected = error instanceof TypeError; }\n"
        "  if (!angleRejected) return value;\n"
        "  return WEVector.vectorAngle2({x:0,y:NaN}) + value;\n"
        "}";
    fixture->invalid_wevector = mwx_scene_quickjs_owner_create(
        fixture->domain, invalid_wevector_source, strlen(invalid_wevector_source),
        59, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->invalid_wevector != NULL, "invalid WEVector compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->invalid_wevector, 59, 2, MWX_SCENE_QUICKJS_EXCEPTION, 2,
        "WEVector rejects non-finite inputs"
    );

}

void mwx_fixture_owner_failure_cases(MWXSceneScriptQuickJSFixture *fixture) {
    fixture->immutable_frame = mwx_scene_quickjs_owner_create(
        fixture->domain,
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
        12, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->immutable_frame != NULL, "immutable frame compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->immutable_frame, 12, 0, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "engine frame is immutable"
    );

    MWXSceneQuickJSOwner *unresolved_import = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "import * as Unsupported from 'Unsupported';\n"
        "export function update(value) { return Unsupported.abs(value); }",
        strlen(
            "import * as Unsupported from 'Unsupported';\n"
            "export function update(value) { return Unsupported.abs(value); }"
        ),
        8, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        unresolved_import == NULL,
        "unresolved import fails closed",
        fixture->diagnostic
    );

    MWXSceneQuickJSOwner *compile_error = mwx_scene_quickjs_owner_create(
        fixture->domain, "function update(value) {", strlen("function update(value) {"),
        3, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(compile_error == NULL, "compile exception", fixture->diagnostic);

    fixture->callback_error = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value) { throw new Error('callback'); }",
        strlen("export function update(value) { throw new Error('callback'); }"),
        4, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->callback_error != NULL, "callback compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->callback_error, 4, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "callback exception"
    );
    fixture->failures += mwx_fixture_update(
        fixture->callback_error, 4, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "callback disabled after exception"
    );

    fixture->bad_return = mwx_scene_quickjs_owner_create(
        fixture->domain, "export function update(value) { return {}; }",
        strlen("export function update(value) { return {}; }"),
        5, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->bad_return != NULL, "bad return compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->bad_return, 5, 1, MWX_SCENE_QUICKJS_BAD_RETURN, 0, "bad return"
    );
    // A value-validation failure is data-shaped: the owner stays callable and
    // retries the next frame instead of fusing off. Exceptions keep the fuse.
    fixture->failures += mwx_fixture_update(
        fixture->bad_return, 5, 1, MWX_SCENE_QUICKJS_BAD_RETURN, 0,
        "bad return retries instead of disabling"
    );

    // The 10-16 fixed official Bool-return contract accepts only Boolean values:
    // runtime-evidence-current.md#e-2026-10-16-bool-return. Other normal returns
    // preserve the input; they are neither truthiness coercions nor failures.
    const char *number_return_source =
        "export function update(value) { return value ? 0 : 0.75; }";
    MWXSceneQuickJSResult number_return_result = MWX_SCENE_QUICKJS_OK;
    fixture->number_return =
        mwx_scene_quickjs_owner_create_value_only_with_budget(
            fixture->domain, number_return_source, strlen(number_return_source),
            15, 100000, &number_return_result,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->number_return != NULL &&
            number_return_result == MWX_SCENE_QUICKJS_OK,
        "number return compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_bool(
        fixture->number_return, 15, 1, MWX_SCENE_QUICKJS_OK, 1,
        "number return 0 preserves true input"
    );
    fixture->failures += mwx_fixture_update_bool(
        fixture->number_return, 15, 0, MWX_SCENE_QUICKJS_OK, 0,
        "number return 0.75 preserves false input"
    );

    const char *nan_return_source =
        "export function update(value) { return value ? NaN : Infinity; }";
    MWXSceneQuickJSResult nan_return_result = MWX_SCENE_QUICKJS_OK;
    fixture->nan_return =
        mwx_scene_quickjs_owner_create_value_only_with_budget(
            fixture->domain, nan_return_source, strlen(nan_return_source),
            16, 100000, &nan_return_result,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->nan_return != NULL && nan_return_result == MWX_SCENE_QUICKJS_OK,
        "NaN return compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_bool(
        fixture->nan_return, 16, 1, MWX_SCENE_QUICKJS_OK, 1,
        "NaN return preserves true input"
    );
    fixture->failures += mwx_fixture_update_bool(
        fixture->nan_return, 16, 0, MWX_SCENE_QUICKJS_OK, 0,
        "Infinity return preserves false input"
    );

    const char *string_return_source =
        "export function update(value) { return 'yes'; }";
    MWXSceneQuickJSResult string_return_result = MWX_SCENE_QUICKJS_OK;
    fixture->string_return =
        mwx_scene_quickjs_owner_create_value_only_with_budget(
            fixture->domain, string_return_source, strlen(string_return_source),
            17, 100000, &string_return_result,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->string_return != NULL && string_return_result == MWX_SCENE_QUICKJS_OK,
        "string return compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_bool(
        fixture->string_return, 17, 1, MWX_SCENE_QUICKJS_OK, 1,
        "string return preserves true input"
    );
    fixture->failures += mwx_fixture_update_bool(
        fixture->string_return, 17, 0, MWX_SCENE_QUICKJS_OK, 0,
        "string return preserves false input"
    );

    fixture->budget = mwx_scene_quickjs_owner_create(
        fixture->domain, "export function update(value) { while (true) { value = value; }; }",
        strlen("export function update(value) { while (true) { value = value; }; }"),
        6, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->budget != NULL, "budget compile", fixture->diagnostic);
    mwx_scene_quickjs_domain_reset_budget(fixture->domain, 32);
    fixture->failures += mwx_fixture_update(
        fixture->budget, 6, 1, MWX_SCENE_QUICKJS_BUDGET_EXCEEDED, 0, "interrupt budget"
    );

    fixture->mutation_overflow = mwx_scene_quickjs_owner_create(
        fixture->domain,
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
        9, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->mutation_overflow != NULL, "mutation overflow compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_effects(
        fixture->mutation_overflow, 17, 0, NULL, "mutation overflow catalog"
    );
    fixture->failures += mwx_fixture_update(
        fixture->mutation_overflow, 9, 1, MWX_SCENE_QUICKJS_MUTATION_OVERFLOW, 0,
        "mutation overflow"
    );

    fixture->invalid_effect = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value) { thisLayer.getEffect('missing'); return value; }",
        strlen("export function update(value) { thisLayer.getEffect('missing'); return value; }"),
        11, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->invalid_effect != NULL, "invalid effect compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_effects(
        fixture->invalid_effect, 1, 0, "known", "invalid effect catalog"
    );
    fixture->failures += mwx_fixture_update(
        fixture->invalid_effect, 11, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "invalid effect rejected at handle lookup"
    );

    fixture->immutable_handle = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "'use strict'; export function update(value) { thisLayer.getEffect = null; return value; }",
        strlen("'use strict'; export function update(value) { thisLayer.getEffect = null; return value; }"),
        12, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->immutable_handle != NULL, "immutable handle compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_effects(
        fixture->immutable_handle, 1, 0, "known", "immutable handle catalog"
    );
    fixture->failures += mwx_fixture_update(
        fixture->immutable_handle, 12, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "immutable handle method"
    );

}
