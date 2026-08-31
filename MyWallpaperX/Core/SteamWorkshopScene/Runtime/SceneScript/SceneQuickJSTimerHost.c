#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdint.h>

static MWXSceneQuickJSOwner *active_owner(JSContext *context) {
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain == NULL || !domain->callback_active ||
        domain->active_owner == NULL || domain->active_owner->disabled) {
        return NULL;
    }
    return domain->active_owner;
}

static MWXSceneQuickJSTimerRecord *timer_with_identity(
    MWXSceneQuickJSOwner *owner,
    uint64_t identity
) {
    if (owner == NULL || identity == 0) return NULL;
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        MWXSceneQuickJSTimerRecord *timer = &owner->timers[index];
        if (timer->active && timer->identity == identity) return timer;
    }
    return NULL;
}

static void deactivate_timer(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSTimerRecord *timer
) {
    if (owner == NULL || timer == NULL || !timer->active) return;
    JS_FreeValue(owner->domain->context, timer->callback);
    timer->callback = JS_UNDEFINED;
    timer->active = false;
    timer->identity = 0;
    timer->remaining_seconds = 0;
    timer->interval_seconds = 0;
    timer->repeating = false;
}

static JSValue cancel_timer(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    JSValue *function_data
) {
    (void)this_value;
    (void)argc;
    (void)argv;
    (void)magic;
    MWXSceneQuickJSOwner *owner = active_owner(context);
    uint64_t owner_identity = 0;
    uint64_t identity = 0;
    if (owner == NULL ||
        JS_ToIndex(context, &owner_identity, function_data[0]) < 0 ||
        JS_ToIndex(context, &identity, function_data[1]) < 0 ||
        owner_identity != owner->identity) {
        return JS_ThrowTypeError(context, "timer cancel owner is unavailable");
    }
    deactivate_timer(owner, timer_with_identity(owner, identity));
    return JS_UNDEFINED;
}

static JSValue register_timer(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic
) {
    (void)this_value;
    MWXSceneQuickJSOwner *owner = active_owner(context);
    if (owner != NULL && owner->value_only) {
        return JS_ThrowTypeError(
            context, "timers are unavailable to value-only SceneScript owners"
        );
    }
    double milliseconds = 0;
    if (owner == NULL || argc != 2 || !JS_IsFunction(context, argv[0]) ||
        JS_ToFloat64(context, &milliseconds, argv[1]) < 0 ||
        !isfinite(milliseconds) || milliseconds < 0 ||
        milliseconds > 86400000.0) {
        return JS_ThrowTypeError(
            context,
            "engine timer expects a callback and 0...86400000 milliseconds"
        );
    }
    MWXSceneQuickJSTimerRecord *slot = NULL;
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        if (!owner->timers[index].active) {
            slot = &owner->timers[index];
            break;
        }
    }
    if (slot == NULL) {
        return JS_ThrowRangeError(context, "SceneScript timer budget exceeded");
    }
    owner->next_timer_identity += 1;
    if (owner->next_timer_identity == 0) owner->next_timer_identity = 1;
    slot->identity = owner->next_timer_identity;
    slot->remaining_seconds = milliseconds / 1000.0;
    slot->interval_seconds = milliseconds / 1000.0;
    slot->callback = JS_DupValue(context, argv[0]);
    slot->repeating = magic != 0;
    slot->active = true;
    JSValue function_data[2] = {
        JS_NewInt64(context, (int64_t)owner->identity),
        JS_NewInt64(context, (int64_t)slot->identity),
    };
    JSValue cancel = JS_NewCFunctionData(
        context, cancel_timer, 0, 0, 2, function_data
    );
    JS_FreeValue(context, function_data[0]);
    JS_FreeValue(context, function_data[1]);
    if (JS_IsException(cancel)) {
        deactivate_timer(owner, slot);
    }
    return cancel;
}

bool mwx_scene_quickjs_install_timer_engine(
    MWXSceneQuickJSOwner *owner,
    JSValue engine
) {
    if (owner == NULL || !JS_IsObject(engine)) return false;
    JSContext *context = owner->domain->context;
    JSValue timeout = JS_NewCFunctionMagic(
        context, register_timer, "setTimeout", 2, JS_CFUNC_generic_magic, 0
    );
    JSValue interval = JS_NewCFunctionMagic(
        context, register_timer, "setInterval", 2, JS_CFUNC_generic_magic, 1
    );
    if (JS_IsException(timeout) || JS_IsException(interval)) {
        JS_FreeValue(context, timeout);
        JS_FreeValue(context, interval);
        return false;
    }
    const int flags = JS_PROP_ENUMERABLE;
    if (JS_DefinePropertyValueStr(
            context, engine, "setTimeout", timeout, flags
        ) < 0 || JS_DefinePropertyValueStr(
            context, engine, "setInterval", interval, flags
        ) < 0) {
        return false;
    }
    return true;
}

static MWXSceneQuickJSResult timer_exception(
    MWXSceneQuickJSOwner *owner,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSResult result = mwx_scene_quickjs_exception_result(
        owner->domain, diagnostic, diagnostic_capacity
    );
    return owner->material_function_overflow || owner->animation_command_overflow ||
            owner->video_command_overflow
        ? MWX_SCENE_QUICKJS_MUTATION_OVERFLOW : result;
}

MWXSceneQuickJSResult mwx_scene_quickjs_run_due_timers(
    MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (owner == NULL || frame == NULL) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (!owner->timer_runtime_initialized) {
        owner->timer_runtime = frame->runtime;
        owner->timer_runtime_initialized = true;
        return MWX_SCENE_QUICKJS_OK;
    }
    if (frame->runtime == owner->timer_runtime) return MWX_SCENE_QUICKJS_OK;
    owner->timer_runtime = frame->runtime;
    uint64_t due[MWX_SCENE_QUICKJS_MAX_TIMERS];
    size_t due_count = 0;
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        MWXSceneQuickJSTimerRecord *timer = &owner->timers[index];
        if (!timer->active) continue;
        timer->remaining_seconds -= frame->frame_time;
        if (timer->remaining_seconds <= 0) due[due_count++] = timer->identity;
    }
    if (due_count == 0) return MWX_SCENE_QUICKJS_OK;

    mwx_scene_quickjs_begin_callback(owner);
    JSValue previous_layer = JS_UNDEFINED;
    JSValue previous_scene = JS_UNDEFINED;
    JSValue previous_object = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_owner_handles(
            owner, &previous_layer, &previous_scene, &previous_object
        )) {
        mwx_scene_quickjs_end_callback(owner);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript timer handles unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_engine = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_frame_engine_host(
            owner, frame, user_properties_json, user_properties_length,
            &previous_engine
        )) {
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_layer, previous_scene, previous_object
        );
        mwx_scene_quickjs_end_callback(owner);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript timer engine unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }

    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    for (size_t index = 0; index < due_count; ++index) {
        MWXSceneQuickJSTimerRecord *timer = timer_with_identity(owner, due[index]);
        if (timer == NULL) continue;
        JSValue callback = JS_DupValue(owner->domain->context, timer->callback);
        if (timer->repeating) {
            timer->remaining_seconds = timer->interval_seconds;
        } else {
            deactivate_timer(owner, timer);
        }
        JSValue callback_result = JS_Call(
            owner->domain->context, callback, JS_UNDEFINED, 0, NULL
        );
        JS_FreeValue(owner->domain->context, callback);
        if (JS_IsException(callback_result)) {
            mwx_scene_quickjs_discard_jobs(owner);
            JS_FreeValue(owner->domain->context, callback_result);
            result = timer_exception(owner, diagnostic, diagnostic_capacity);
            break;
        }
        result = mwx_scene_quickjs_drain_jobs(
            owner, diagnostic, diagnostic_capacity
        );
        JS_FreeValue(owner->domain->context, callback_result);
        if (result != MWX_SCENE_QUICKJS_OK) break;
    }

    const bool engine_restored = mwx_scene_quickjs_restore_frame_engine_host(
        owner, previous_engine
    );
    const bool handles_restored = mwx_scene_quickjs_restore_owner_handles(
        owner, previous_layer, previous_scene, previous_object
    );
    mwx_scene_quickjs_end_callback(owner);
    if (!engine_restored || !handles_restored) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript timer host restore failed"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    return result;
}

uint32_t mwx_scene_quickjs_owner_active_timer_count(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL) return 0;
    uint32_t count = 0;
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        if (owner->timers[index].active) count += 1;
    }
    return count;
}

void mwx_scene_quickjs_destroy_timer_host(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL || owner->domain->context == NULL) {
        return;
    }
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        deactivate_timer(owner, &owner->timers[index]);
    }
}
