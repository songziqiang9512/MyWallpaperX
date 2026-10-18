#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdlib.h>
#include <stdint.h>

struct MWXSceneQuickJSTimerLifetime {
    JSRuntime *runtime;
    MWXSceneQuickJSOwner *owner;
    uint64_t owner_identity;
    size_t references;
};

struct MWXSceneQuickJSTimerCancellation {
    MWXSceneQuickJSTimerLifetime *lifetime;
    uint64_t identity;
    bool externally_cancelled;
    bool *construction_finalized;
};

static void release_lifetime(MWXSceneQuickJSTimerLifetime *lifetime) {
    if (--lifetime->references == 0) js_free_rt(lifetime->runtime, lifetime);
}

static void free_cancellation(void *opaque) {
    MWXSceneQuickJSTimerCancellation *token = opaque;
    MWXSceneQuickJSTimerLifetime *lifetime = token->lifetime;
    if (token->construction_finalized != NULL)
        *token->construction_finalized = true;
    js_free_rt(lifetime->runtime, token);
    release_lifetime(lifetime);
}

static bool belongs_to_owner(
    const MWXSceneQuickJSTimerCancellation *token,
    const MWXSceneQuickJSOwner *owner
) {
    return token != NULL && token->lifetime == owner->timer_lifetime &&
        token->lifetime->owner == owner;
}

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
    JS_FreeValue(owner->domain->context, timer->cancellation);
    timer->callback = JS_UNDEFINED;
    timer->cancellation = JS_UNDEFINED;
    timer->cancellation_token = NULL;
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
    void *opaque
) {
    (void)this_value;
    (void)argc;
    (void)argv;
    (void)magic;
    MWXSceneQuickJSOwner *caller = active_owner(context);
    MWXSceneQuickJSTimerCancellation *token = opaque;
    MWXSceneQuickJSOwner *owner = token->lifetime->owner;
    if (caller == NULL || caller->value_only ||
        caller->domain->value_only_guard_active ||
        caller->domain->runtime != token->lifetime->runtime) {
        return JS_ThrowTypeError(context, "timer cancel owner is unavailable");
    }
    // Teardown clears timers before invoking destroy. The still-live creator
    // may idempotently clear its old capability there; it cannot reach a new
    // registration or lend this cleanup permission to a peer.
    if (owner == NULL && caller->identity == token->lifetime->owner_identity)
        return JS_UNDEFINED;
    if (owner == NULL || owner->domain != caller->domain || owner->disabled) {
        return JS_ThrowTypeError(context, "timer cancel owner is unavailable");
    }
    // This capability cancels its registration even if a local rollback has
    // temporarily removed it. A later creator snapshot cannot undo a peer's
    // completed scheduling action; same-owner snapshot semantics stay intact.
    if (caller != owner) token->externally_cancelled = true;
    deactivate_timer(owner, timer_with_identity(owner, token->identity));
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
    // Cancellation closures can outlive a rejected frame in the JS heap.
    // Never recycle their identities, including beyond JS's exact index range.
    if (owner->next_timer_identity >= UINT64_C(9007199254740991)) {
        return JS_ThrowRangeError(context, "SceneScript timer identity budget exceeded");
    }
    owner->next_timer_identity += 1;
    slot->identity = owner->next_timer_identity;
    slot->remaining_seconds = milliseconds / 1000.0;
    slot->interval_seconds = milliseconds / 1000.0;
    slot->callback = JS_DupValue(context, argv[0]);
    slot->cancellation = JS_UNDEFINED;
    slot->cancellation_token = NULL;
    slot->repeating = magic != 0;
    slot->active = true;
    if (owner->timer_lifetime == NULL) {
        owner->timer_lifetime = js_mallocz(context, sizeof(*owner->timer_lifetime));
        if (owner->timer_lifetime == NULL) {
            deactivate_timer(owner, slot);
            return JS_EXCEPTION;
        }
        *owner->timer_lifetime = (MWXSceneQuickJSTimerLifetime){
            .runtime = JS_GetRuntime(context), .owner = owner,
            .owner_identity = owner->identity, .references = 1,
        };
    }
    MWXSceneQuickJSTimerCancellation *token = js_mallocz(context, sizeof(*token));
    if (token == NULL) {
        deactivate_timer(owner, slot);
        return JS_EXCEPTION;
    }
    token->lifetime = owner->timer_lifetime;
    token->identity = slot->identity;
    token->lifetime->references += 1;
    bool finalized = false;
    token->construction_finalized = &finalized;
    JSValue cancel = JS_NewCClosure(
        context, cancel_timer, "cancel", free_cancellation, 0, 0, token
    );
    // The VM can fail before taking opaque ownership, or during function
    // property setup after installing its finalizer.
    if (!JS_IsException(cancel) && JS_HasException(context)) {
        JSValue exception = JS_GetException(context);
        JS_FreeValue(context, cancel);
        JS_Throw(context, exception);
        cancel = JS_EXCEPTION;
    }
    if (JS_IsException(cancel)) {
        if (!finalized) free_cancellation(token);
        deactivate_timer(owner, slot);
    } else {
        token->construction_finalized = NULL;
        slot->cancellation = JS_DupValue(context, cancel);
        slot->cancellation_token = token;
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
            owner->media_playback_command_overflow || owner->texture_animation_command_overflow || owner->particle_playback_command_overflow ||
            owner->storage_mutation_overflow
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
        mwx_scene_quickjs_begin_callback(owner);
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

MWXSceneQuickJSTimerFrameSnapshot *mwx_scene_quickjs_owner_timer_snapshot(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL || owner->domain->context == NULL) {
        return NULL;
    }
    MWXSceneQuickJSTimerFrameSnapshot *snapshot = calloc(1, sizeof(*snapshot));
    if (snapshot == NULL) return NULL;
    snapshot->timer_runtime = owner->timer_runtime;
    snapshot->timer_runtime_initialized = owner->timer_runtime_initialized;
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        snapshot->timers[index] = owner->timers[index];
        if (owner->timers[index].active) {
            snapshot->timers[index].callback = JS_DupValue(
                owner->domain->context, owner->timers[index].callback
            );
            snapshot->timers[index].cancellation = JS_DupValue(
                owner->domain->context, owner->timers[index].cancellation
            );
        } else {
            snapshot->timers[index].callback = JS_UNDEFINED;
            snapshot->timers[index].cancellation = JS_UNDEFINED;
            snapshot->timers[index].cancellation_token = NULL;
        }
    }
    snapshot->puppet_animation_callback_count = owner->puppet_animation_callback_count;
    snapshot->puppet_animation_delivered_sequence = owner->puppet_animation_delivered_sequence;
    snapshot->puppet_event_cursor = owner->puppet_event_cursor;
    snapshot->puppet_event_queue_epoch = owner->puppet_event_queue_epoch;
    snapshot->puppet_animation_command_count = owner->puppet_animation_command_count;
    snapshot->puppet_animation_command_read_start = owner->puppet_animation_command_read_start;
    snapshot->puppet_animation_registration_count = owner->puppet_animation_registration_count;
    snapshot->puppet_animation_command_overflow = owner->puppet_animation_command_overflow;
    snapshot->puppet_animation_visibility = owner->puppet_animation_visibility;
    snapshot->puppet_animation_visibility_staged = owner->puppet_animation_visibility_staged;
    for (size_t i = 0; i < owner->puppet_animation_callback_count; i++)
        snapshot->puppet_animation_callbacks[i] = JS_DupValue(owner->domain->context, owner->puppet_animation_callbacks[i]);
    return snapshot;
}

bool mwx_scene_quickjs_owner_timer_restore(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSTimerFrameSnapshot *snapshot
) {
    if (owner == NULL || snapshot == NULL || owner->domain == NULL ||
        owner->domain->context == NULL) return false;
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        deactivate_timer(owner, &owner->timers[index]);
        const MWXSceneQuickJSTimerRecord *saved = &snapshot->timers[index];
        if (saved->active && belongs_to_owner(saved->cancellation_token, owner) &&
            !saved->cancellation_token->externally_cancelled) {
            owner->timers[index] = *saved;
            owner->timers[index].callback = JS_DupValue(
                owner->domain->context, saved->callback
            );
            owner->timers[index].cancellation = JS_DupValue(
                owner->domain->context, saved->cancellation
            );
        } else {
            owner->timers[index] = (MWXSceneQuickJSTimerRecord){
                .callback = JS_UNDEFINED, .cancellation = JS_UNDEFINED,
            };
        }
    }
    for (size_t i = 0; i < owner->puppet_animation_callback_count; i++)
        JS_FreeValue(owner->domain->context, owner->puppet_animation_callbacks[i]);
    owner->puppet_animation_callback_count = snapshot->puppet_animation_callback_count;
    for (size_t i = 0; i < snapshot->puppet_animation_callback_count; i++)
        owner->puppet_animation_callbacks[i] = JS_DupValue(owner->domain->context, snapshot->puppet_animation_callbacks[i]);
    // Natural-end input belongs to the consumed cadence. Roots, controls and
    // scheduled work roll back, but an already invoked event never replays.
    if (owner->puppet_animation_delivered_sequence < snapshot->puppet_animation_delivered_sequence)
        owner->puppet_animation_delivered_sequence = snapshot->puppet_animation_delivered_sequence;
    // Source payload is retained until commit; only provisional consumption
    // rolls back. Retirement/commit invalidates snapshots of the old queue.
    if (owner->puppet_event_queue_epoch == snapshot->puppet_event_queue_epoch &&
        snapshot->puppet_event_cursor <= owner->puppet_event_count)
        owner->puppet_event_cursor = snapshot->puppet_event_cursor;
    owner->puppet_animation_command_count = snapshot->puppet_animation_command_count;
    owner->puppet_animation_command_read_start = snapshot->puppet_animation_command_read_start;
    owner->puppet_animation_registration_count = snapshot->puppet_animation_registration_count;
    owner->puppet_animation_command_overflow = snapshot->puppet_animation_command_overflow;
    owner->puppet_animation_visibility = snapshot->puppet_animation_visibility;
    owner->puppet_animation_visibility_staged = snapshot->puppet_animation_visibility_staged;
    // Restore scheduled work, but retain the owner's lifetime issuance counter:
    // closures from discarded work must not cancel a subsequently issued timer.
    owner->timer_runtime = snapshot->timer_runtime;
    owner->timer_runtime_initialized = snapshot->timer_runtime_initialized;
    return true;
}

void mwx_scene_quickjs_owner_timer_snapshot_destroy(
    MWXSceneQuickJSTimerFrameSnapshot *snapshot,
    MWXSceneQuickJSOwner *owner
) {
    if (snapshot == NULL) return;
    if (owner != NULL && owner->domain != NULL && owner->domain->context != NULL) {
        for (size_t i = 0; i < snapshot->puppet_animation_callback_count; i++)
            JS_FreeValue(owner->domain->context, snapshot->puppet_animation_callbacks[i]);
        for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
            if (snapshot->timers[index].active) {
                JS_FreeValue(
                    owner->domain->context, snapshot->timers[index].callback
                );
                JS_FreeValue(
                    owner->domain->context, snapshot->timers[index].cancellation
                );
            }
        }
    }
    free(snapshot);
}

void mwx_scene_quickjs_destroy_timer_host(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL || owner->domain->context == NULL) {
        return;
    }
    // Escaping cancellation closures and snapshots must lose the owner before
    // any callback or owner memory is released.
    if (owner->timer_lifetime != NULL) {
        MWXSceneQuickJSTimerLifetime *lifetime = owner->timer_lifetime;
        lifetime->owner = NULL;
        owner->timer_lifetime = NULL;
        release_lifetime(lifetime);
    }
    for (size_t index = 0; index < MWX_SCENE_QUICKJS_MAX_TIMERS; ++index) {
        deactivate_timer(owner, &owner->timers[index]);
    }
}
