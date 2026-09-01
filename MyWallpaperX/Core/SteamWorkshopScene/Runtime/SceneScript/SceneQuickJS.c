#include "SceneQuickJS.h"
#include "SceneQuickJSInternal.h"
#include "SceneQuickJSModuleHost.h"

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum SceneInputProperty {
    SCENE_INPUT_CURSOR_WORLD_POSITION,
    SCENE_INPUT_CURSOR_SCREEN_POSITION,
    SCENE_INPUT_CURSOR_LEFT_DOWN,
};

static JSValue freeze_snapshot_value(
    MWXSceneQuickJSDomain *domain,
    JSValue value
) {
    if (JS_IsException(value)) return value;
    JSValue argument = JS_DupValue(domain->context, value);
    JSValue frozen = JS_Call(
        domain->context,
        domain->deep_freeze,
        JS_UNDEFINED,
        1,
        &argument
    );
    JS_FreeValue(domain->context, argument);
    if (JS_IsException(frozen)) {
        JS_FreeValue(domain->context, value);
        return JS_EXCEPTION;
    }
    JS_FreeValue(domain->context, frozen);
    return value;
}

static JSValue new_vec2_snapshot(
    MWXSceneQuickJSDomain *domain,
    double x,
    double y
) {
    JSContext *context = domain->context;
    JSValue arguments[2] = {
        JS_NewFloat64(context, x),
        JS_NewFloat64(context, y),
    };
    JSValue value = JS_CallConstructor(
        context,
        domain->vec2_constructor,
        2,
        arguments
    );
    for (size_t index = 0; index < 2; ++index) {
        JS_FreeValue(context, arguments[index]);
    }
    return freeze_snapshot_value(domain, value);
}

static JSValue new_vec3_snapshot(
    MWXSceneQuickJSDomain *domain,
    double x,
    double y,
    double z
) {
    JSContext *context = domain->context;
    JSValue arguments[3] = {
        JS_NewFloat64(context, x),
        JS_NewFloat64(context, y),
        JS_NewFloat64(context, z),
    };
    JSValue value = JS_CallConstructor(
        context,
        domain->vec3_constructor,
        3,
        arguments
    );
    for (size_t index = 0; index < 3; ++index) {
        JS_FreeValue(context, arguments[index]);
    }
    return freeze_snapshot_value(domain, value);
}

static JSValue scene_input_getter(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic
) {
    (void)this_value;
    (void)argc;
    (void)argv;
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain == NULL || !domain->callback_active ||
        !domain->frame_input_active ||
        domain->active_frame_input.has_surface_input != 1) {
        return JS_ThrowTypeError(
            context,
            "input is only available in a single-surface callback"
        );
    }
    const MWXSceneQuickJSFrameInput *frame = &domain->active_frame_input;
    switch ((enum SceneInputProperty)magic) {
    case SCENE_INPUT_CURSOR_WORLD_POSITION:
        return new_vec3_snapshot(
            domain,
            frame->cursor_world_x,
            frame->cursor_world_y,
            frame->cursor_world_z
        );
    case SCENE_INPUT_CURSOR_SCREEN_POSITION:
        return new_vec2_snapshot(
            domain,
            frame->cursor_screen_x,
            frame->cursor_screen_y
        );
    case SCENE_INPUT_CURSOR_LEFT_DOWN:
        return JS_NewBool(context, frame->cursor_left_down != 0);
    }
    return JS_UNDEFINED;
}

static bool install_input_host(MWXSceneQuickJSDomain *domain) {
    JSContext *context = domain->context;
    JSValue input = JS_NewObject(context);
    if (JS_IsException(input)) return false;
    const struct {
        const char *name;
        enum SceneInputProperty property;
    } fields[] = {
        {"cursorWorldPosition", SCENE_INPUT_CURSOR_WORLD_POSITION},
        {"cursorScreenPosition", SCENE_INPUT_CURSOR_SCREEN_POSITION},
        {"cursorLeftDown", SCENE_INPUT_CURSOR_LEFT_DOWN},
    };
    for (size_t index = 0; index < sizeof(fields) / sizeof(fields[0]); ++index) {
        JSValue getter = JS_NewCFunctionMagic(
            context,
            scene_input_getter,
            fields[index].name,
            0,
            JS_CFUNC_generic_magic,
            fields[index].property
        );
        JSAtom atom = JS_NewAtom(context, fields[index].name);
        int result = JS_DefinePropertyGetSet(
            context,
            input,
            atom,
            getter,
            JS_UNDEFINED,
            JS_PROP_ENUMERABLE
        );
        JS_FreeAtom(context, atom);
        if (result < 0) {
            JS_FreeValue(context, input);
            return false;
        }
    }
    if (JS_PreventExtensions(context, input) < 0) {
        JS_FreeValue(context, input);
        return false;
    }
    JSValue global = JS_GetGlobalObject(context);
    int result = JS_DefinePropertyValueStr(
        context,
        global,
        "input",
        input,
        JS_PROP_ENUMERABLE
    );
    JS_FreeValue(context, global);
    return result >= 0;
}

static void clear_diagnostic(char *diagnostic, size_t capacity) {
    if (diagnostic != NULL && capacity > 0) {
        diagnostic[0] = '\0';
    }
}

void mwx_scene_quickjs_write_diagnostic(
    char *diagnostic,
    size_t capacity,
    const char *message
) {
    if (diagnostic == NULL || capacity == 0) {
        return;
    }
    snprintf(diagnostic, capacity, "%s", message != NULL ? message : "");
}

#define write_diagnostic mwx_scene_quickjs_write_diagnostic

void mwx_scene_quickjs_write_exception(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t capacity
) {
    JSValue exception = JS_GetException(domain->context);
    const char *message = JS_ToCString(domain->context, exception);
    write_diagnostic(diagnostic, capacity, message != NULL ? message : "script exception");
    if (message != NULL) {
        JS_FreeCString(domain->context, message);
    }
    JS_FreeValue(domain->context, exception);
}

static void write_value_diagnostic(
    MWXSceneQuickJSDomain *domain,
    JSValueConst value,
    char *diagnostic,
    size_t capacity,
    const char *fallback
) {
    const char *message = JS_ToCString(domain->context, value);
    write_diagnostic(diagnostic, capacity, message != NULL ? message : fallback);
    if (message != NULL) {
        JS_FreeCString(domain->context, message);
    }
}

static bool valid_frame_input(const MWXSceneQuickJSFrameInput *frame) {
    if (frame == NULL || !isfinite(frame->time_of_day) ||
        frame->time_of_day < 0 || frame->time_of_day > 1 ||
        !isfinite(frame->frame_time) || frame->frame_time < 0 ||
        !isfinite(frame->runtime) || frame->runtime < 0 ||
        frame->has_surface_input > 1 || frame->cursor_left_down > 1) {
        return false;
    }
    if (frame->has_surface_input == 0) return true;
    return isfinite(frame->canvas_width) && frame->canvas_width > 0 &&
        isfinite(frame->canvas_height) && frame->canvas_height > 0 &&
        isfinite(frame->screen_width) && frame->screen_width > 0 &&
        isfinite(frame->screen_height) && frame->screen_height > 0 &&
        isfinite(frame->cursor_world_x) &&
        isfinite(frame->cursor_world_y) &&
        isfinite(frame->cursor_world_z) &&
        isfinite(frame->cursor_screen_x) &&
        isfinite(frame->cursor_screen_y);
}

static bool user_properties_snapshot(
    MWXSceneQuickJSDomain *domain,
    const char *json,
    size_t length,
    JSValue *snapshot
) {
    if (domain == NULL || snapshot == NULL || (length > 0 && json == NULL)) {
        return false;
    }
    if (domain->user_properties_snapshot_valid &&
        domain->user_properties_json_length == length &&
        (length == 0 || memcmp(domain->user_properties_json, json, length) == 0)) {
        *snapshot = JS_DupValue(
            domain->context, domain->user_properties_snapshot
        );
        return true;
    }

    JSContext *context = domain->context;
    JSValue value = length == 0
        ? JS_NewObject(context)
        : JS_ParseJSON(context, json, length, "engine.userProperties");
    if (JS_IsException(value) || !JS_IsObject(value)) {
        JS_FreeValue(context, value);
        return false;
    }
    JSValue freeze_argument = JS_DupValue(context, value);
    JSValue frozen = JS_Call(
        context, domain->deep_freeze, JS_UNDEFINED, 1, &freeze_argument
    );
    JS_FreeValue(context, freeze_argument);
    if (JS_IsException(frozen)) {
        JS_FreeValue(context, frozen);
        JS_FreeValue(context, value);
        return false;
    }
    JS_FreeValue(context, frozen);

    char *json_copy = NULL;
    if (length > 0) {
        json_copy = malloc(length);
        if (json_copy == NULL) {
            JS_FreeValue(context, value);
            return false;
        }
        memcpy(json_copy, json, length);
    }
    JS_FreeValue(context, domain->user_properties_snapshot);
    free(domain->user_properties_json);
    domain->user_properties_snapshot = value;
    domain->user_properties_json = json_copy;
    domain->user_properties_json_length = length;
    domain->user_properties_snapshot_valid = true;
    *snapshot = JS_DupValue(context, value);
    return true;
}

bool mwx_scene_quickjs_bind_frame_engine_host(
    MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    JSValue *previous_global_engine
) {
    if (owner == NULL || !valid_frame_input(frame) ||
        previous_global_engine == NULL) {
        return false;
    }
    JSContext *context = owner->domain->context;
    JSValue engine = JS_NewObject(context);
    if (JS_IsException(engine)) {
        return false;
    }
    const int read_only = JS_PROP_ENUMERABLE;
    JSValue user_properties = JS_UNDEFINED;
    if (!user_properties_snapshot(
            owner->domain,
            user_properties_json,
            user_properties_length,
            &user_properties
        )) {
        JS_FreeValue(context, engine);
        return false;
    }
    if (frame->has_surface_input == 1) {
        JSValue canvas_size = new_vec2_snapshot(
            owner->domain,
            frame->canvas_width,
            frame->canvas_height
        );
        if (JS_IsException(canvas_size)) {
            JS_FreeValue(context, canvas_size);
            JS_FreeValue(context, user_properties);
            JS_FreeValue(context, engine);
            return false;
        }
        if (JS_DefinePropertyValueStr(
                context,
                engine,
                "canvasSize",
                canvas_size,
                read_only
            ) < 0) {
            JS_FreeValue(context, user_properties);
            JS_FreeValue(context, engine);
            return false;
        }
    }
    if (JS_DefinePropertyValueStr(
            context,
            engine,
            "timeOfDay",
            JS_NewFloat64(context, frame->time_of_day),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context,
            engine,
            "frametime",
            JS_NewFloat64(context, frame->frame_time),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context,
            engine,
            "runtime",
            JS_NewFloat64(context, frame->runtime),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context,
            engine,
            "userProperties",
            user_properties,
            read_only
        ) < 0 || !mwx_scene_quickjs_install_timer_engine(owner, engine)) {
        JS_FreeValue(context, engine);
        return false;
    }
    if (!mwx_scene_quickjs_bind_active_engine(
            owner->domain, engine, previous_global_engine
        )) {
        JS_FreeValue(context, engine);
        return false;
    }
    owner->domain->active_frame_input = *frame;
    owner->domain->frame_input_active = true;
    return true;
}

bool mwx_scene_quickjs_restore_frame_engine_host(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_global_engine
) {
    if (owner == NULL) {
        return false;
    }
    owner->domain->frame_input_active = false;
    memset(
        &owner->domain->active_frame_input,
        0,
        sizeof(owner->domain->active_frame_input)
    );
    return mwx_scene_quickjs_restore_active_engine(
        owner->domain, previous_global_engine
    );
}

static int interrupt_handler(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    MWXSceneQuickJSDomain *domain = (MWXSceneQuickJSDomain *)opaque;
    if (domain != NULL && domain->cancellation_check != NULL &&
        domain->cancellation_check(domain->cancellation_opaque) != 0) {
        domain->interrupted = true;
        return 1;
    }
    if (domain == NULL || domain->interrupt_budget == 0) {
        if (domain != NULL) {
            domain->interrupted = true;
        }
        return 1;
    }
    domain->interrupt_budget -= 1;
    return 0;
}

static bool get_function(
    MWXSceneQuickJSOwner *owner,
    const char *name,
    JSValue *function,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    *function = JS_GetPropertyStr(domain->context, owner->module, name);
    if (JS_IsException(*function)) {
        mwx_scene_quickjs_write_exception(domain, diagnostic, diagnostic_capacity);
        return false;
    }
    if (!JS_IsFunction(domain->context, *function)) {
        JS_FreeValue(domain->context, *function);
        *function = JS_UNDEFINED;
    }
    return true;
}

void mwx_scene_quickjs_begin_callback(MWXSceneQuickJSOwner *owner) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    domain->callback_epoch += 1;
    if (domain->callback_epoch == 0) domain->callback_epoch = 1;
    domain->callback_active = true;
    domain->active_owner = owner;
}

void mwx_scene_quickjs_end_callback(MWXSceneQuickJSOwner *owner) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    domain->active_owner = NULL;
    domain->callback_active = false;
}

static MWXSceneQuickJSResult drain_jobs_after_call(
    MWXSceneQuickJSOwner *owner,
    JSValueConst result,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (JS_IsException(result)) {
        mwx_scene_quickjs_discard_jobs(owner);
        return MWX_SCENE_QUICKJS_OK;
    }
    return mwx_scene_quickjs_drain_jobs(
        owner, diagnostic, diagnostic_capacity
    );
}

bool mwx_scene_quickjs_assign_script_properties(
    MWXSceneQuickJSOwner *owner,
    const char *json,
    size_t length
);

static MWXSceneQuickJSResult call_primitive(
    MWXSceneQuickJSOwner *owner,
    JSValueConst function,
    double input,
    bool boolean_value,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    mwx_scene_quickjs_begin_callback(owner);
    if (!mwx_scene_quickjs_assign_script_properties(
            owner, script_properties_json, script_properties_length
        )) {
        mwx_scene_quickjs_end_callback(owner);
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript properties unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_global_layer = JS_UNDEFINED;
    JSValue previous_global_scene = JS_UNDEFINED;
    JSValue previous_global_object = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_owner_handles(
            owner, &previous_global_layer, &previous_global_scene,
            &previous_global_object
        )) {
        mwx_scene_quickjs_end_callback(owner);
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript typed handle host unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_global_engine = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_frame_engine_host(
            owner,
            frame,
            user_properties_json,
            user_properties_length,
            &previous_global_engine
        )) {
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_global_layer, previous_global_scene,
            previous_global_object
        );
        mwx_scene_quickjs_end_callback(owner);
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript frame engine host unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_dispatch_video_ended_callbacks(owner)) {
        mwx_scene_quickjs_restore_frame_engine_host(owner, previous_global_engine);
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_global_layer, previous_global_scene,
            previous_global_object
        );
        mwx_scene_quickjs_end_callback(owner);
        return mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
    }
    JSValue argument = boolean_value
        ? JS_NewBool(domain->context, input != 0)
        : JS_NewFloat64(domain->context, input);
    JSValue result = JS_Call(
        domain->context,
        function,
        owner->module,
        1,
        &argument
    );
    JS_FreeValue(domain->context, argument);
    MWXSceneQuickJSResult job_result = drain_jobs_after_call(
        owner, result, diagnostic, diagnostic_capacity
    );
    const bool engine_restored = mwx_scene_quickjs_restore_frame_engine_host(
        owner,
        previous_global_engine
    );
    const bool handles_restored = mwx_scene_quickjs_restore_owner_handles(
        owner, previous_global_layer, previous_global_scene,
        previous_global_object
    );
    mwx_scene_quickjs_end_callback(owner);
    const bool restored = engine_restored && handles_restored;
    if (!restored) {
        JS_FreeValue(domain->context, result);
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript material function host restore failed"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (job_result != MWX_SCENE_QUICKJS_OK) {
        JS_FreeValue(domain->context, result);
        return job_result;
    }
    if (JS_IsException(result)) {
        MWXSceneQuickJSResult failure = mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
        JS_FreeValue(domain->context, result);
        if (owner->material_function_overflow || owner->animation_command_overflow ||
            owner->video_command_overflow) {
            write_diagnostic(
                diagnostic,
                diagnostic_capacity,
                owner->video_command_overflow
                    ? "video command buffer exceeded"
                    : (owner->animation_command_overflow
                        ? "animation command buffer exceeded"
                        : "material function mutation buffer exceeded")
            );
            return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
        }
        return failure;
    }
    if (JS_IsUndefined(result)) {
        *output = input;
        JS_FreeValue(domain->context, result);
        return MWX_SCENE_QUICKJS_OK;
    }
    double value = 0;
    int conversion = boolean_value
        ? (JS_IsBool(result) ? JS_ToBool(domain->context, result) : -1)
        : JS_ToFloat64(domain->context, &value, result);
    if (boolean_value && conversion >= 0) value = conversion != 0;
    JS_FreeValue(domain->context, result);
    if (conversion < 0 || !isfinite(value)) {
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            boolean_value
                ? "callback returned non-Boolean value"
                : "callback returned non-finite or non-scalar value"
        );
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    *output = value;
    return MWX_SCENE_QUICKJS_OK;
}

static MWXSceneQuickJSResult call_string(
    MWXSceneQuickJSOwner *owner,
    JSValueConst function,
    const char *input,
    size_t input_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *output,
    size_t output_capacity,
    size_t *output_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    mwx_scene_quickjs_begin_callback(owner);
    JSValue previous_global_layer = JS_UNDEFINED;
    JSValue previous_global_scene = JS_UNDEFINED;
    JSValue previous_global_object = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_owner_handles(
            owner, &previous_global_layer, &previous_global_scene,
            &previous_global_object
        )) {
        mwx_scene_quickjs_end_callback(owner);
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript typed handle host unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_global_engine = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_frame_engine_host(
            owner, frame, user_properties_json, user_properties_length,
            &previous_global_engine
        )) {
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_global_layer, previous_global_scene,
            previous_global_object
        );
        mwx_scene_quickjs_end_callback(owner);
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript frame engine host unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_dispatch_video_ended_callbacks(owner)) {
        mwx_scene_quickjs_restore_frame_engine_host(owner, previous_global_engine);
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_global_layer, previous_global_scene,
            previous_global_object
        );
        mwx_scene_quickjs_end_callback(owner);
        return mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
    }
    JSValue argument = JS_NewStringLen(domain->context, input, input_length);
    JSValue result = JS_IsException(argument)
        ? JS_EXCEPTION
        : JS_Call(domain->context, function, owner->module, 1, &argument);
    JS_FreeValue(domain->context, argument);
    MWXSceneQuickJSResult job_result = drain_jobs_after_call(
        owner, result, diagnostic, diagnostic_capacity
    );
    const bool engine_restored = mwx_scene_quickjs_restore_frame_engine_host(
        owner, previous_global_engine
    );
    const bool handles_restored = mwx_scene_quickjs_restore_owner_handles(
        owner, previous_global_layer, previous_global_scene,
        previous_global_object
    );
    mwx_scene_quickjs_end_callback(owner);
    if (!engine_restored || !handles_restored) {
        JS_FreeValue(domain->context, result);
        write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript host restore failed"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (job_result != MWX_SCENE_QUICKJS_OK) {
        JS_FreeValue(domain->context, result);
        return job_result;
    }
    if (JS_IsException(result)) {
        MWXSceneQuickJSResult failure = mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
        JS_FreeValue(domain->context, result);
        return owner->material_function_overflow || owner->animation_command_overflow ||
                owner->video_command_overflow
            ? MWX_SCENE_QUICKJS_MUTATION_OVERFLOW : failure;
    }
    if (JS_IsUndefined(result)) {
        if (input_length >= output_capacity) {
            JS_FreeValue(domain->context, result);
            write_diagnostic(
                diagnostic, diagnostic_capacity,
                "callback string output capacity is insufficient"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
        memcpy(output, input, input_length);
        output[input_length] = '\0';
        *output_length = input_length;
        JS_FreeValue(domain->context, result);
        return MWX_SCENE_QUICKJS_OK;
    }
    if (!JS_IsString(result)) {
        JS_FreeValue(domain->context, result);
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "callback returned non-string value"
        );
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    size_t length = 0;
    const char *string = JS_ToCStringLen(domain->context, &length, result);
    if (string == NULL || length > 65536 || length >= output_capacity) {
        if (string != NULL) JS_FreeCString(domain->context, string);
        JS_FreeValue(domain->context, result);
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "callback returned oversized string value"
        );
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    memcpy(output, string, length);
    output[length] = '\0';
    *output_length = length;
    JS_FreeCString(domain->context, string);
    JS_FreeValue(domain->context, result);
    return MWX_SCENE_QUICKJS_OK;
}

bool mwx_scene_quickjs_assign_script_properties(
    MWXSceneQuickJSOwner *owner,
    const char *json,
    size_t length
) {
    if (json == NULL || length == 0) {
        return true;
    }
    JSContext *context = owner->domain->context;
    JSValue target = JS_GetPropertyStr(context, owner->module, "scriptProperties");
    JSValue source = JS_ParseJSON(context, json, length, "scriptProperties");
    if (JS_IsException(target) || JS_IsException(source) ||
        !JS_IsObject(target) || !JS_IsObject(source)) {
        JS_FreeValue(context, target);
        JS_FreeValue(context, source);
        return false;
    }
    JSValue arguments[2] = {
        JS_DupValue(context, target),
        JS_DupValue(context, source),
    };
    JSValue result = JS_Call(
        context,
        owner->domain->script_property_assigner,
        JS_UNDEFINED,
        2,
        arguments
    );
    JS_FreeValue(context, arguments[0]);
    JS_FreeValue(context, arguments[1]);
    JS_FreeValue(context, target);
    JS_FreeValue(context, source);
    const bool success = !JS_IsException(result);
    JS_FreeValue(context, result);
    return success;
}

static bool read_vec3(JSContext *context, JSValueConst value, double output[3]) {
    if (!JS_IsObject(value)) {
        double scalar = 0;
        if (JS_ToFloat64(context, &scalar, value) < 0 || !isfinite(scalar)) {
            return false;
        }
        output[0] = scalar;
        output[1] = scalar;
        output[2] = scalar;
        return true;
    }
    static const char *names[] = {"x", "y", "z"};
    for (size_t index = 0; index < 3; index += 1) {
        JSValue component = JS_GetPropertyStr(context, value, names[index]);
        int conversion = JS_ToFloat64(context, &output[index], component);
        JS_FreeValue(context, component);
        if (conversion < 0 || !isfinite(output[index])) {
            return false;
        }
    }
    return true;
}

static MWXSceneQuickJSResult call_vec3(
    MWXSceneQuickJSOwner *owner,
    JSValueConst function,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (!mwx_scene_quickjs_assign_script_properties(
            owner, script_properties_json, script_properties_length
        )) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript properties unavailable");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    mwx_scene_quickjs_begin_callback(owner);
    JSValue previous_global_layer = JS_UNDEFINED;
    JSValue previous_global_scene = JS_UNDEFINED;
    JSValue previous_global_object = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_owner_handles(
            owner, &previous_global_layer, &previous_global_scene,
            &previous_global_object
        )) {
        mwx_scene_quickjs_end_callback(owner);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript typed handle host unavailable");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_global_engine = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_frame_engine_host(
            owner,
            frame,
            user_properties_json,
            user_properties_length,
            &previous_global_engine
        )) {
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_global_layer, previous_global_scene,
            previous_global_object
        );
        mwx_scene_quickjs_end_callback(owner);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript frame engine host unavailable");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_dispatch_video_ended_callbacks(owner)) {
        mwx_scene_quickjs_restore_frame_engine_host(owner, previous_global_engine);
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_global_layer, previous_global_scene,
            previous_global_object
        );
        mwx_scene_quickjs_end_callback(owner);
        return mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
    }
    JSValue vector_arguments[3] = {
        JS_NewFloat64(domain->context, input[0]),
        JS_NewFloat64(domain->context, input[1]),
        JS_NewFloat64(domain->context, input[2]),
    };
    JSValue argument = JS_CallConstructor(
        domain->context, domain->vec3_constructor, 3, vector_arguments
    );
    for (size_t index = 0; index < 3; ++index) {
        JS_FreeValue(domain->context, vector_arguments[index]);
    }
    JSValue callback_argument = JS_DupValue(domain->context, argument);
    JSValue result = JS_Call(domain->context, function, owner->module, 1, &callback_argument);
    JS_FreeValue(domain->context, callback_argument);
    MWXSceneQuickJSResult job_result = drain_jobs_after_call(
        owner, result, diagnostic, diagnostic_capacity
    );
    const bool engine_restored = mwx_scene_quickjs_restore_frame_engine_host(
        owner, previous_global_engine
    );
    const bool handles_restored = mwx_scene_quickjs_restore_owner_handles(
        owner, previous_global_layer, previous_global_scene,
        previous_global_object
    );
    mwx_scene_quickjs_end_callback(owner);
    if (!engine_restored || !handles_restored) {
        JS_FreeValue(domain->context, argument);
        JS_FreeValue(domain->context, result);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript host restore failed");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (job_result != MWX_SCENE_QUICKJS_OK) {
        JS_FreeValue(domain->context, argument);
        JS_FreeValue(domain->context, result);
        return job_result;
    }
    if (JS_IsException(result)) {
        JS_FreeValue(domain->context, argument);
        MWXSceneQuickJSResult failure = mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
        JS_FreeValue(domain->context, result);
        return owner->material_function_overflow || owner->animation_command_overflow ||
                owner->video_command_overflow
            ? MWX_SCENE_QUICKJS_MUTATION_OVERFLOW : failure;
    }
    JSValueConst value = JS_IsUndefined(result) ? argument : result;
    const bool valid = read_vec3(domain->context, value, output);
    JS_FreeValue(domain->context, argument);
    JS_FreeValue(domain->context, result);
    if (!valid) {
        write_diagnostic(diagnostic, diagnostic_capacity, "callback returned invalid Vec3 value");
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSDomain *mwx_scene_quickjs_domain_create(
    size_t heap_limit,
    size_t stack_limit,
    uint64_t interrupt_budget,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (heap_limit == 0 || stack_limit == 0 || interrupt_budget == 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript domain configuration");
        return NULL;
    }
    MWXSceneQuickJSDomain *domain = calloc(1, sizeof(*domain));
    if (domain == NULL) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript domain allocation failed");
        return NULL;
    }
    domain->runtime = JS_NewRuntime();
    if (domain->runtime == NULL) {
        free(domain);
        write_diagnostic(diagnostic, diagnostic_capacity, "QuickJS runtime allocation failed");
        return NULL;
    }
    domain->interrupt_budget = interrupt_budget;
    domain->owner_creation_budget = interrupt_budget;
    JS_SetMemoryLimit(domain->runtime, heap_limit);
    JS_SetMaxStackSize(domain->runtime, stack_limit);
    JS_SetInterruptHandler(domain->runtime, interrupt_handler, domain);
    JS_SetModuleLoaderFunc(
        domain->runtime,
        NULL,
        mwx_scene_quickjs_load_allowlisted_module,
        domain
    );
    domain->context = JS_NewContext(domain->runtime);
    if (domain->context == NULL) {
        JS_FreeRuntime(domain->runtime);
        free(domain);
        write_diagnostic(diagnostic, diagnostic_capacity, "QuickJS context allocation failed");
        return NULL;
    }
    JS_SetContextOpaque(domain->context, domain);
    mwx_scene_quickjs_install_job_host(domain);
    domain->vec2_constructor = JS_UNDEFINED;
    domain->vec3_constructor = JS_UNDEFINED;
    domain->deep_freeze = JS_UNDEFINED;
    domain->script_property_assigner = JS_UNDEFINED;
    domain->active_engine = JS_UNDEFINED;
    domain->active_layer = JS_UNDEFINED;
    domain->active_scene = JS_UNDEFINED;
    domain->active_object = JS_UNDEFINED;
    domain->shared_value = JS_UNDEFINED;
    domain->user_properties_snapshot = JS_UNDEFINED;
    if (!mwx_scene_quickjs_install_active_engine_host(domain) ||
        !mwx_scene_quickjs_install_owner_handle_globals(domain) ||
        !mwx_scene_quickjs_install_value_host(domain) ||
        !install_input_host(domain) ||
        !mwx_scene_quickjs_install_layer_handle_class(domain)) {
        JS_FreeContext(domain->context);
        JS_FreeRuntime(domain->runtime);
        free(domain);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript value or layer host unavailable");
        return NULL;
    }
    return domain;
}

void mwx_scene_quickjs_domain_destroy(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) {
        return;
    }
    mwx_scene_quickjs_domain_abort_layer_snapshot(domain);
    if (domain->context != NULL) {
        JS_FreeValue(domain->context, domain->vec2_constructor);
        JS_FreeValue(domain->context, domain->vec3_constructor);
        JS_FreeValue(domain->context, domain->deep_freeze);
        JS_FreeValue(domain->context, domain->script_property_assigner);
        JS_FreeValue(domain->context, domain->active_engine);
        JS_FreeValue(domain->context, domain->active_layer);
        JS_FreeValue(domain->context, domain->active_scene);
        JS_FreeValue(domain->context, domain->active_object);
        JS_FreeValue(domain->context, domain->shared_value);
        JS_FreeValue(domain->context, domain->user_properties_snapshot);
        free(domain->user_properties_json);
        if (domain->layers != NULL) {
            for (uint32_t index = 0; index < domain->layer_count; ++index) {
                free(domain->layers[index].name);
                free(domain->layers[index].text);
                free(domain->layers[index].font);
                free(domain->layers[index].asset_path);
            }
            free(domain->layers);
        }
        JS_FreeContext(domain->context);
    }
    if (domain->runtime != NULL) {
        domain->cancellation_check = NULL;
        domain->cancellation_opaque = NULL;
        JS_FreeRuntime(domain->runtime);
    }
    free(domain);
}

void mwx_scene_quickjs_domain_set_cancellation_check(
    MWXSceneQuickJSDomain *domain,
    MWXSceneQuickJSCancellationCheck cancellation_check,
    void *opaque
) {
    if (domain == NULL) return;
    domain->cancellation_check = cancellation_check;
    domain->cancellation_opaque = cancellation_check != NULL ? opaque : NULL;
}

static MWXSceneQuickJSOwner *create_owner_with_budget(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    uint64_t interrupt_budget,
    bool value_only,
    MWXSceneQuickJSResult *result,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (result != NULL) *result = MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (domain == NULL || source == NULL || source_length == 0 || generation == 0 ||
        interrupt_budget == 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript owner configuration");
        return NULL;
    }
    if (source_length == SIZE_MAX) {
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript owner source length overflow"
        );
        return NULL;
    }
    if (source_length > MWX_SCENE_QUICKJS_MAX_OWNER_SOURCE_BYTES) {
        if (result != NULL) *result = MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript owner source byte budget exceeded"
        );
        return NULL;
    }
    domain->interrupt_budget = interrupt_budget;
    domain->interrupted = false;
    if (result != NULL) *result = MWX_SCENE_QUICKJS_EXCEPTION;
    char *module_source = malloc(source_length + 1);
    if (module_source == NULL) {
        if (result != NULL) *result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript source allocation failed");
        return NULL;
    }
    memcpy(module_source, source, source_length);
    module_source[source_length] = '\0';
    JSValue module = JS_Eval(
        domain->context,
        module_source,
        source_length,
        "inline.scene.js",
        JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY
    );
    free(module_source);
    if (JS_IsException(module)) {
        MWXSceneQuickJSResult failure = mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
        if (failure == MWX_SCENE_QUICKJS_EXCEPTION) {
            failure = MWX_SCENE_QUICKJS_COMPILE_ERROR;
        }
        if (result != NULL) *result = failure;
        JS_FreeValue(domain->context, module);
        return NULL;
    }

    MWXSceneQuickJSOwner *owner = calloc(1, sizeof(*owner));
    if (owner == NULL) {
        if (result != NULL) *result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        JS_FreeValue(domain->context, module);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner allocation failed");
        return NULL;
    }
    owner->domain = domain;
    owner->module = JS_UNDEFINED;
    domain->next_owner_identity += 1;
    if (domain->next_owner_identity == 0 || domain->next_owner_identity > INT64_MAX) {
        JS_FreeValue(domain->context, module);
        free(owner);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner identity exhausted");
        return NULL;
    }
    owner->identity = domain->next_owner_identity;
    owner->generation = generation;
    owner->value_only = value_only;
    owner->material_function_layer = JS_UNDEFINED;
    owner->scene_handle = JS_UNDEFINED;
    owner->object_handle = JS_UNDEFINED;
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_AUDIO_REGISTRATIONS; ++index) {
        owner->audio_registrations[index].object = JS_UNDEFINED;
        owner->audio_registrations[index].left = JS_UNDEFINED;
        owner->audio_registrations[index].right = JS_UNDEFINED;
        owner->audio_registrations[index].average = JS_UNDEFINED;
    }
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        owner->timers[index].callback = JS_UNDEFINED;
    }
    for (
        size_t index = 0;
        index < MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS;
        ++index
    ) {
        owner->rejections[index].promise = JS_UNDEFINED;
        owner->rejections[index].reason = JS_UNDEFINED;
    }
    owner->effect_names = calloc(1, sizeof(*owner->effect_names));
    if (owner->effect_names == NULL) {
        if (result != NULL) *result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        JS_FreeValue(domain->context, module);
        free(owner);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner allocation failed");
        return NULL;
    }

    JSModuleDef *module_definition = JS_VALUE_GET_PTR(module);
    JSValue previous_global_engine = JS_UNDEFINED;
    domain->value_only_guard_active = value_only;
    if (!mwx_scene_quickjs_bind_module_engine_host(
            owner, &previous_global_engine
        )) {
        JS_FreeValue(domain->context, module);
        free(owner->effect_names);
        free(owner);
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript module engine host unavailable"
        );
        domain->value_only_guard_active = false;
        return NULL;
    }
    JSValue evaluation = JS_EvalFunction(
        domain->context,
        JS_DupValue(domain->context, module)
    );
    const bool engine_restored = mwx_scene_quickjs_restore_module_engine_host(
        owner, previous_global_engine
    );
    const bool module_job_residue = mwx_scene_quickjs_owner_has_job_residue(owner);
    if (!engine_restored) {
        mwx_scene_quickjs_discard_jobs(owner);
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        mwx_scene_quickjs_destroy_audio_host(owner);
        free(owner->effect_names);
        free(owner);
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript module engine restore failed"
        );
        domain->value_only_guard_active = false;
        return NULL;
    }
    if (JS_IsException(evaluation)) {
        mwx_scene_quickjs_discard_jobs(owner);
        MWXSceneQuickJSResult failure = mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
        if (result != NULL) *result = failure;
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        mwx_scene_quickjs_destroy_audio_host(owner);
        mwx_scene_quickjs_destroy_job_host(owner);
        free(owner->effect_names);
        free(owner);
        domain->value_only_guard_active = false;
        return NULL;
    }
    JSPromiseStateEnum state = JS_PromiseState(domain->context, evaluation);
    if (state == JS_PROMISE_REJECTED) {
        JSValue reason = JS_PromiseResult(domain->context, evaluation);
        write_value_diagnostic(
            domain,
            reason,
            diagnostic,
            diagnostic_capacity,
            "SceneScript module evaluation rejected"
        );
        JS_FreeValue(domain->context, reason);
        if (result != NULL) {
            if (domain->interrupted) {
                *result = MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
            } else if (diagnostic != NULL &&
                       strstr(diagnostic, "out of memory") != NULL) {
                *result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
            } else {
                *result = MWX_SCENE_QUICKJS_EXCEPTION;
            }
        }
        mwx_scene_quickjs_discard_jobs(owner);
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        mwx_scene_quickjs_destroy_audio_host(owner);
        mwx_scene_quickjs_destroy_job_host(owner);
        free(owner->effect_names);
        free(owner);
        domain->value_only_guard_active = false;
        return NULL;
    }
    if (state == JS_PROMISE_PENDING) {
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript top-level await is unsupported"
        );
        mwx_scene_quickjs_discard_jobs(owner);
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        mwx_scene_quickjs_destroy_audio_host(owner);
        mwx_scene_quickjs_destroy_job_host(owner);
        free(owner->effect_names);
        free(owner);
        domain->value_only_guard_active = false;
        return NULL;
    }
    if (module_job_residue) {
        mwx_scene_quickjs_discard_jobs(owner);
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        mwx_scene_quickjs_destroy_audio_host(owner);
        mwx_scene_quickjs_destroy_job_host(owner);
        free(owner->effect_names);
        free(owner);
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript module jobs are unsupported"
        );
        domain->value_only_guard_active = false;
        return NULL;
    }
    JS_FreeValue(domain->context, evaluation);

    JSValue namespace = JS_GetModuleNamespace(domain->context, module_definition);
    JS_FreeValue(domain->context, module);
    if (JS_IsException(namespace)) {
        mwx_scene_quickjs_discard_jobs(owner);
        mwx_scene_quickjs_write_exception(domain, diagnostic, diagnostic_capacity);
        JS_FreeValue(domain->context, namespace);
        mwx_scene_quickjs_destroy_audio_host(owner);
        mwx_scene_quickjs_destroy_job_host(owner);
        free(owner->effect_names);
        free(owner);
        domain->value_only_guard_active = false;
        return NULL;
    }
    owner->module = namespace;
    if (!mwx_scene_quickjs_install_owner_handles(owner)) {
        mwx_scene_quickjs_destroy_owner_handles(owner);
        mwx_scene_quickjs_destroy_audio_host(owner);
        JS_FreeValue(domain->context, owner->module);
        free(owner);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript host globals unavailable");
        domain->value_only_guard_active = false;
        return NULL;
    }
    domain->value_only_guard_active = false;
    if (result != NULL) *result = MWX_SCENE_QUICKJS_OK;
    return owner;
}

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create_with_budget(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    uint64_t interrupt_budget,
    MWXSceneQuickJSResult *result,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    return create_owner_with_budget(
        domain, source, source_length, generation, interrupt_budget, false,
        result, diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create_value_only_with_budget(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    uint64_t interrupt_budget,
    MWXSceneQuickJSResult *result,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    return create_owner_with_budget(
        domain, source, source_length, generation, interrupt_budget, true,
        result, diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    uint64_t interrupt_budget,
    MWXSceneQuickJSResult *result,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSOwner *owner = create_owner_with_budget(
        domain, source, source_length, generation, interrupt_budget, false,
        result, diagnostic, diagnostic_capacity
    );
    if (owner != NULL) owner->effectful_boolean = true;
    return owner;
}

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    const uint64_t interrupt_budget = domain != NULL
        ? domain->owner_creation_budget : 0;
    return mwx_scene_quickjs_owner_create_with_budget(
        domain, source, source_length, generation, interrupt_budget, NULL,
        diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_has_function(
    MWXSceneQuickJSOwner *owner,
    const char *name,
    size_t name_length,
    uint32_t *available,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || name == NULL || name_length == 0 || name_length > 128 ||
        memchr(name, '\0', name_length) != NULL || available == NULL) {
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid SceneScript callback query"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char callback_name[129];
    memcpy(callback_name, name, name_length);
    callback_name[name_length] = '\0';
    JSValue function = JS_GetPropertyStr(
        owner->domain->context, owner->module, callback_name
    );
    if (JS_IsException(function)) {
        mwx_scene_quickjs_write_exception(
            owner->domain, diagnostic, diagnostic_capacity
        );
        JS_FreeValue(owner->domain->context, function);
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    *available = JS_IsFunction(owner->domain->context, function) ? 1 : 0;
    JS_FreeValue(owner->domain->context, function);
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_owner_destroy(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) {
        return;
    }
    mwx_scene_quickjs_discard_jobs(owner);
    mwx_scene_quickjs_destroy_job_host(owner);
    mwx_scene_quickjs_destroy_timer_host(owner);
    if (owner->domain != NULL && owner->domain->context != NULL) {
        JS_FreeValue(owner->domain->context, owner->module);
    }
    mwx_scene_quickjs_destroy_audio_host(owner);
    mwx_scene_quickjs_destroy_owner_handles(owner);
    free(owner);
}

static MWXSceneQuickJSResult initialize_primitive_callback(
    MWXSceneQuickJSOwner *owner,
    double input,
    bool boolean_value,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    *output = input;
    if (owner->initialized) return MWX_SCENE_QUICKJS_OK;
    JSValue init = JS_UNDEFINED;
    if (!get_function(owner, "init", &init, diagnostic, diagnostic_capacity)) {
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    if (JS_IsFunction(owner->domain->context, init)) {
        result = call_primitive(
            owner, init, input, boolean_value, frame,
            script_properties_json, script_properties_length,
            user_properties_json, user_properties_length,
            output, diagnostic, diagnostic_capacity
        );
    }
    JS_FreeValue(owner->domain->context, init);
    if (result == MWX_SCENE_QUICKJS_OK) owner->initialized = true;
    return result;
}

static MWXSceneQuickJSResult initialize_vec3_callback(
    MWXSceneQuickJSOwner *owner,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    memcpy(output, input, sizeof(double) * 3);
    if (owner->initialized) return MWX_SCENE_QUICKJS_OK;
    JSValue init = JS_UNDEFINED;
    if (!get_function(owner, "init", &init, diagnostic, diagnostic_capacity)) {
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    if (JS_IsFunction(owner->domain->context, init)) {
        result = call_vec3(
            owner, init, input, frame,
            script_properties_json, script_properties_length,
            user_properties_json, user_properties_length,
            output, diagnostic, diagnostic_capacity
        );
    }
    JS_FreeValue(owner->domain->context, init);
    if (result == MWX_SCENE_QUICKJS_OK) owner->initialized = true;
    return result;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_initialize_primitive_with_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    uint32_t boolean_value,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    uint32_t *did_initialize,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || frame == NULL || output == NULL ||
        did_initialize == NULL || !isfinite(input) || boolean_value > 1 ||
        (boolean_value != 0 && !owner->value_only && !owner->effectful_boolean) ||
        (boolean_value == 0 && owner->value_only) ||
        (boolean_value != 0 && input != 0 && input != 1) ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(diagnostic, diagnostic_capacity,
                         "invalid SceneScript initialization argument");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *output = input;
    *did_initialize = 0;
    if (owner->generation != expected_generation) {
        write_diagnostic(diagnostic, diagnostic_capacity,
                         "stale SceneScript owner generation");
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(diagnostic, diagnostic_capacity,
                         "SceneScript owner is disabled");
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    if (owner->initialized) return MWX_SCENE_QUICKJS_OK;
    owner->domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;
    MWXSceneQuickJSResult timer_result = mwx_scene_quickjs_run_due_timers(
        owner, frame, user_properties_json, user_properties_length,
        diagnostic, diagnostic_capacity
    );
    if (timer_result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return timer_result;
    }
    MWXSceneQuickJSResult result = initialize_primitive_callback(
        owner, input, boolean_value != 0, frame,
        script_properties_json, script_properties_length,
        user_properties_json, user_properties_length,
        output, diagnostic, diagnostic_capacity
    );
    if (result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return result;
    }
    *did_initialize = 1;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_initialize_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    uint32_t *did_initialize,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || owner->value_only || input == NULL || frame == NULL ||
        output == NULL || did_initialize == NULL ||
        !isfinite(input[0]) || !isfinite(input[1]) || !isfinite(input[2]) ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(diagnostic, diagnostic_capacity,
                         "invalid SceneScript Vec3 initialization argument");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    memcpy(output, input, sizeof(double) * 3);
    *did_initialize = 0;
    if (owner->generation != expected_generation) {
        write_diagnostic(diagnostic, diagnostic_capacity,
                         "stale SceneScript owner generation");
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(diagnostic, diagnostic_capacity,
                         "SceneScript owner is disabled");
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    if (owner->initialized) return MWX_SCENE_QUICKJS_OK;
    owner->domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;
    MWXSceneQuickJSResult timer_result = mwx_scene_quickjs_run_due_timers(
        owner, frame, user_properties_json, user_properties_length,
        diagnostic, diagnostic_capacity
    );
    if (timer_result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return timer_result;
    }
    MWXSceneQuickJSResult result = initialize_vec3_callback(
        owner, input, frame,
        script_properties_json, script_properties_length,
        user_properties_json, user_properties_length,
        output, diagnostic, diagnostic_capacity
    );
    if (result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return result;
    }
    *did_initialize = 1;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_primitive_with_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    uint32_t boolean_value,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || frame == NULL || output == NULL || !isfinite(input) ||
        boolean_value > 1 ||
        (boolean_value != 0 &&
         !owner->value_only && !owner->effectful_boolean) ||
        (boolean_value == 0 && owner->value_only) ||
        (boolean_value != 0 && input != 0 && input != 1) ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript update argument");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->generation != expected_generation) {
        write_diagnostic(diagnostic, diagnostic_capacity, "stale SceneScript owner generation");
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner is disabled");
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    MWXSceneQuickJSDomain *domain = owner->domain;
    domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;
    MWXSceneQuickJSResult timer_result = mwx_scene_quickjs_run_due_timers(
        owner, frame, user_properties_json, user_properties_length,
        diagnostic, diagnostic_capacity
    );
    if (timer_result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return timer_result;
    }
    if (!owner->initialized) {
        MWXSceneQuickJSResult result = initialize_primitive_callback(
            owner, input, boolean_value != 0, frame,
            script_properties_json, script_properties_length,
            user_properties_json, user_properties_length,
            output, diagnostic, diagnostic_capacity
        );
        if (result != MWX_SCENE_QUICKJS_OK) {
            owner->disabled = true;
            return result;
        }
        input = *output;
    }
    JSValue update = JS_UNDEFINED;
    if (!get_function(owner, "update", &update, diagnostic, diagnostic_capacity)) {
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!JS_IsFunction(domain->context, update)) {
        *output = input;
        return MWX_SCENE_QUICKJS_OK;
    }
    MWXSceneQuickJSResult result = call_primitive(
        owner, update, input, boolean_value != 0, frame,
        script_properties_json, script_properties_length,
        user_properties_json, user_properties_length,
        output, diagnostic, diagnostic_capacity
    );
    JS_FreeValue(domain->context, update);
    if (result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
    }
    return result;
}

static MWXSceneQuickJSResult initialize_string_callback(
    MWXSceneQuickJSOwner *owner,
    const char *input,
    size_t input_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *output,
    size_t output_capacity,
    size_t *output_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (input_length >= output_capacity) {
        write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript string output exceeded"
        );
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    memmove(output, input, input_length);
    output[input_length] = '\0';
    *output_length = input_length;
    if (owner->initialized) return MWX_SCENE_QUICKJS_OK;
    JSValue init = JS_UNDEFINED;
    if (!get_function(owner, "init", &init, diagnostic, diagnostic_capacity)) {
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    if (JS_IsFunction(owner->domain->context, init)) {
        result = call_string(
            owner, init, output, *output_length, frame,
            user_properties_json, user_properties_length,
            output, output_capacity, output_length,
            diagnostic, diagnostic_capacity
        );
    }
    JS_FreeValue(owner->domain->context, init);
    if (result == MWX_SCENE_QUICKJS_OK) owner->initialized = true;
    return result;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_initialize_string(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *input,
    size_t input_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *output,
    size_t output_capacity,
    size_t *output_length,
    uint32_t *did_initialize,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || owner->value_only || input == NULL ||
        input_length > 65536 || memchr(input, '\0', input_length) != NULL ||
        frame == NULL || output == NULL || output_capacity == 0 ||
        output_length == NULL || did_initialize == NULL ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid SceneScript string initialization argument"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *did_initialize = 0;
    if (owner->generation != expected_generation) {
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "stale SceneScript owner generation"
        );
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript owner is disabled"
        );
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    if (owner->initialized) {
        if (input_length >= output_capacity) return MWX_SCENE_QUICKJS_BAD_RETURN;
        memmove(output, input, input_length);
        output[input_length] = '\0';
        *output_length = input_length;
        return MWX_SCENE_QUICKJS_OK;
    }
    owner->domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;
    MWXSceneQuickJSResult timer_result = mwx_scene_quickjs_run_due_timers(
        owner, frame, user_properties_json, user_properties_length,
        diagnostic, diagnostic_capacity
    );
    if (timer_result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return timer_result;
    }
    MWXSceneQuickJSResult result = initialize_string_callback(
        owner, input, input_length, frame,
        user_properties_json, user_properties_length,
        output, output_capacity, output_length,
        diagnostic, diagnostic_capacity
    );
    if (result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return result;
    }
    *did_initialize = 1;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_string(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *input,
    size_t input_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *output,
    size_t output_capacity,
    size_t *output_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || owner->value_only || input == NULL || input_length > 65536 ||
        memchr(input, '\0', input_length) != NULL || frame == NULL ||
        output == NULL || output_capacity == 0 || output_length == NULL ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid SceneScript string update argument"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->generation != expected_generation) {
        write_diagnostic(
            diagnostic, diagnostic_capacity,
            "stale SceneScript owner generation"
        );
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript owner is disabled"
        );
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    MWXSceneQuickJSDomain *domain = owner->domain;
    domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;
    MWXSceneQuickJSResult timer_result = mwx_scene_quickjs_run_due_timers(
        owner, frame, user_properties_json, user_properties_length,
        diagnostic, diagnostic_capacity
    );
    if (timer_result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return timer_result;
    }
    char current[65537];
    if (input_length > 0) memcpy(current, input, input_length);
    current[input_length] = '\0';
    size_t current_length = input_length;
    if (!owner->initialized) {
        MWXSceneQuickJSResult result = initialize_string_callback(
            owner, current, current_length, frame,
            user_properties_json, user_properties_length,
            current, sizeof(current), &current_length,
            diagnostic, diagnostic_capacity
        );
        if (result != MWX_SCENE_QUICKJS_OK) {
            owner->disabled = true;
            return result;
        }
    }
    JSValue update = JS_UNDEFINED;
    if (!get_function(owner, "update", &update, diagnostic, diagnostic_capacity)) {
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!JS_IsFunction(domain->context, update)) {
        JS_FreeValue(domain->context, update);
        if (current_length >= output_capacity) {
            write_diagnostic(
                diagnostic, diagnostic_capacity,
                "SceneScript string output capacity is insufficient"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
        memcpy(output, current, current_length + 1);
        *output_length = current_length;
        return MWX_SCENE_QUICKJS_OK;
    }
    MWXSceneQuickJSResult result = call_string(
        owner, update, current, current_length, frame,
        user_properties_json, user_properties_length,
        output, output_capacity, output_length,
        diagnostic, diagnostic_capacity
    );
    JS_FreeValue(domain->context, update);
    if (result != MWX_SCENE_QUICKJS_OK) owner->disabled = true;
    return result;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || owner->value_only || input == NULL ||
        frame == NULL || output == NULL ||
        !isfinite(input[0]) || !isfinite(input[1]) || !isfinite(input[2]) ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript Vec3 update argument");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->generation != expected_generation) {
        write_diagnostic(diagnostic, diagnostic_capacity, "stale SceneScript owner generation");
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner is disabled");
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    MWXSceneQuickJSDomain *domain = owner->domain;
    domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;
    MWXSceneQuickJSResult timer_result = mwx_scene_quickjs_run_due_timers(
        owner, frame, user_properties_json, user_properties_length,
        diagnostic, diagnostic_capacity
    );
    if (timer_result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return timer_result;
    }
    double current[3] = {input[0], input[1], input[2]};
    if (!owner->initialized) {
        MWXSceneQuickJSResult result = initialize_vec3_callback(
            owner, current, frame,
            script_properties_json, script_properties_length,
            user_properties_json, user_properties_length,
            current, diagnostic, diagnostic_capacity
        );
        if (result != MWX_SCENE_QUICKJS_OK) {
            owner->disabled = true;
            return result;
        }
    }
    JSValue update = JS_UNDEFINED;
    if (!get_function(owner, "update", &update, diagnostic, diagnostic_capacity)) {
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!JS_IsFunction(domain->context, update)) {
        memcpy(output, current, sizeof(current));
        return MWX_SCENE_QUICKJS_OK;
    }
    MWXSceneQuickJSResult result = call_vec3(
        owner, update, current, frame,
        script_properties_json, script_properties_length,
        user_properties_json, user_properties_length,
        output, diagnostic, diagnostic_capacity
    );
    JS_FreeValue(domain->context, update);
    if (result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
    }
    return result;
}
