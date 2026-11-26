#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct MWXSceneQuickJSAnimationHandle {
    MWXSceneQuickJSDomain *domain;
    uint64_t owner_identity;
    uint64_t generation;
    MWXSceneQuickJSAnimationCommand command;
    uint32_t target_index;
    uint32_t catalog_index;
    uint32_t playback_index;
    uint32_t layer_index;
    int64_t layer_id;
    bool component_lookup;
    bool current_property;
    bool scene_lookup;
    bool *construction_finalized;
} MWXSceneQuickJSAnimationHandle;

uint32_t mwx_scene_quickjs_owner_animation_event_export(const MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return 0;
    JSContext *context = owner->domain->context;
    JSValue function = JS_GetPropertyStr(context, owner->module, "animationEvent");
    uint32_t kind = JS_IsUndefined(function) ? 0 : JS_IsFunction(context, function) ? 1 : 2;
    JS_FreeValue(context, function);
    return kind;
}

void mwx_scene_quickjs_owner_configure_animation_events(MWXSceneQuickJSOwner *owner, uint32_t exported) {
    if (owner == NULL || owner->domain == NULL) return;
    owner->handles_animation_events = exported != 0;
    if (!owner->handles_animation_events && !owner->puppet_animation_configured) return;
    owner->animation_next = owner->domain->animation_owners;
    owner->domain->animation_owners = owner;
}

size_t mwx_scene_quickjs_domain_animation_owner_count(const MWXSceneQuickJSDomain *domain) {
    size_t count = 0;
    if (domain != NULL) for (const MWXSceneQuickJSOwner *owner = domain->animation_owners;
        owner; owner = owner->animation_next) count++;
    return count;
}

bool mwx_scene_quickjs_owner_has_pending_animation_events(const MWXSceneQuickJSOwner *owner) {
    return owner != NULL && !owner->disabled && owner->handles_animation_events &&
        (owner->animation_event_failure != 0 || owner->animation_event_cursor < owner->animation_event_count);
}

static bool animation_receiver_matches(MWXSceneQuickJSOwner *owner, int64_t layer_id) {
    if (owner->disabled) return false;
    if (!owner->target_layer_configured)
        return owner->domain->layer_count == 0 && owner->puppet_animation_configured &&
            owner->puppet_animation_identity.layer_id == layer_id;
    if (owner->target_layer_index >= owner->domain->layer_count) return false;
    const MWXSceneQuickJSLayerRecord *layer = &owner->domain->layers[owner->target_layer_index];
    const MWXSceneQuickJSAuthoredLayerMutationRecord *pending =
        mwx_scene_quickjs_authored_mutation_for_layer(owner, owner->target_layer_index);
    return layer->configured && !layer->destroyed && layer->layer_id == layer_id &&
        (pending == NULL || !pending->destroyed);
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_publish_animation_events(
    MWXSceneQuickJSDomain *domain, const MWXSceneQuickJSAnimationEvent *events,
    size_t count, char *diagnostic, size_t diagnostic_capacity) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || (count != 0 && events == NULL))
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (size_t i = 0; i < count; ++i) {
        const MWXSceneQuickJSAnimationEvent *event = &events[i];
        if (event->source_kind > 1) continue;
        MWXSceneQuickJSPuppetAnimationIdentity identity = { .layer_id = event->layer_id,
            .animation_layer_index = event->animation_layer_index, .animation_layer_id = event->animation_layer_id,
            .has_animation_layer_id = event->has_animation_layer_id };
        MWXSceneQuickJSPuppetAnimationRecord *record = event->source_kind == 1
            ? mwx_scene_quickjs_puppet_animation_record_for_identity(domain, identity) : NULL;
        uint32_t failure = event->failure;
        if (!failure && event->name == NULL) failure = 2;
        if (!failure && event->source_kind == 1) {
            if (event->sequence == 0 || strlen(event->name) == 0 || strlen(event->name) > 1024 ||
                !isfinite(event->frame) || event->frame < 0 || event->frame > 9007199254740991.0) failure = 2;
            else if (record == NULL || record->incarnation == 0 ||
                event->sequence <= record->event_published_sequence) continue;
        }
        for (MWXSceneQuickJSOwner *owner = domain->animation_owners;
             owner != NULL; owner = owner->animation_next) {
            if (!owner->handles_animation_events || !animation_receiver_matches(owner, event->layer_id)) continue;
            if (failure) { owner->animation_event_failure = failure; continue; }
            if (owner->animation_event_count == 64) { owner->animation_event_failure = 5; continue; }
            if (owner->animation_events == NULL) {
                owner->animation_events = js_malloc_rt(domain->runtime, 64 * sizeof(*owner->animation_events));
                if (owner->animation_events == NULL) { owner->animation_event_failure = 8; continue; }
            }
            char *name = js_malloc_rt(domain->runtime, strlen(event->name) + 1);
            if (name == NULL) { owner->animation_event_failure = 8; continue; }
            strcpy(name, event->name);
            owner->animation_events[owner->animation_event_count++] = (MWXSceneQuickJSAnimationPendingEvent){
                .source_kind = event->source_kind, .layer_id = event->layer_id,
                .puppet_identity = record == NULL ? (MWXSceneQuickJSPuppetAnimationIdentity){0} : identity,
                .puppet_incarnation = record == NULL ? 0 : record->incarnation,
                .name = name, .frame = event->frame };
        }
        if (!failure && record != NULL) record->event_published_sequence = event->sequence;
    }
    return MWX_SCENE_QUICKJS_OK;
}

bool mwx_scene_quickjs_animation_transaction(MWXSceneQuickJSOwner *owner) {
    if (owner->animation_baseline == NULL)
        owner->animation_baseline = mwx_scene_quickjs_owner_timer_snapshot(owner);
    return owner->animation_baseline != NULL;
}

MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_animation_events(
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSFrameInput *frame,
    const char *properties, size_t properties_length, const char *users, size_t users_length,
    double *value, uint32_t dimensions, bool boolean_value, uint32_t returned_value_field,
    uint32_t *value_produced, char *diagnostic, size_t diagnostic_capacity) {
    if (!mwx_scene_quickjs_owner_has_pending_animation_events(owner)) return MWX_SCENE_QUICKJS_OK;
    if (owner->animation_event_failure) {
        const char *reasons[] = { "", "unsupportedMode", "invalidEvent", "nonFinitePhase",
            "multipleLoopsCrossed", "eventBudgetExceeded", "sequenceOverflow", "invalidEvent", "event allocation failed" };
        uint32_t code = owner->animation_event_failure;
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity,
            code < sizeof(reasons) / sizeof(reasons[0]) ? reasons[code] : "invalid event failure");
        return code == 5 ? MWX_SCENE_QUICKJS_MUTATION_OVERFLOW :
            code == 8 ? MWX_SCENE_QUICKJS_MEMORY_EXCEEDED : MWX_SCENE_QUICKJS_DISABLED;
    }
    if (!mwx_scene_quickjs_animation_transaction(owner)) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    JSContext *context = owner->domain->context;
    JSValue function = JS_UNDEFINED;
    JSValue layer = JS_UNDEFINED, scene = JS_UNDEFINED, object = JS_UNDEFINED, engine = JS_UNDEFINED;
    bool handles = false, bound = false;
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    while (result == MWX_SCENE_QUICKJS_OK && owner->animation_event_cursor < owner->animation_event_count) {
        const MWXSceneQuickJSAnimationPendingEvent *pending = &owner->animation_events[owner->animation_event_cursor];
        MWXSceneQuickJSPuppetAnimationRecord *record = pending->source_kind == 1
            ? mwx_scene_quickjs_puppet_animation_record_for_identity(owner->domain, pending->puppet_identity) : NULL;
        if (!animation_receiver_matches(owner, pending->layer_id) ||
            (pending->source_kind == 1 && (record == NULL || record->incarnation != pending->puppet_incarnation))) {
            owner->animation_event_cursor++; continue;
        }
        if (owner->puppet_animation_configured && !owner->puppet_animation_available) break;
        if (!bound) {
            function = JS_GetPropertyStr(context, owner->module, "animationEvent");
            if (!JS_IsFunction(context, function)) {
                mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "animationEvent must be a function");
                result = MWX_SCENE_QUICKJS_BAD_RETURN;
                break;
            }
            mwx_scene_quickjs_begin_callback(owner);
            bool assigned = mwx_scene_quickjs_assign_script_properties(owner, properties, properties_length);
            handles = assigned && mwx_scene_quickjs_bind_owner_handles(owner, &layer, &scene, &object);
            bound = handles && mwx_scene_quickjs_bind_frame_engine_host(owner, frame, users, users_length, &engine);
            if (!bound) { result = MWX_SCENE_QUICKJS_EXCEPTION; break; }
        }
        mwx_scene_quickjs_begin_callback(owner);
        JSValue event = JS_NewObject(context);
        JSValue name = JS_IsException(event) ? JS_EXCEPTION : JS_NewString(context, pending->name);
        if (JS_IsException(event) || JS_IsException(name)) {
            JS_FreeValue(context, name); JS_FreeValue(context, event);
            (void)mwx_scene_quickjs_exception_result(owner->domain, diagnostic, diagnostic_capacity);
            result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
            break;
        }
        bool created = JS_DefinePropertyValueStr(context, event, "name", name, JS_PROP_C_W_E) >= 0 &&
            JS_DefinePropertyValueStr(context, event, "frame", JS_NewFloat64(context, pending->frame), JS_PROP_C_W_E) >= 0;
        JSValue input = dimensions > 1 ? mwx_scene_quickjs_make_vector(owner->domain, value, dimensions)
            : boolean_value ? JS_NewBool(context, *value != 0) : JS_NewFloat64(context, *value);
        if (!created || JS_IsException(input)) {
            JS_FreeValue(context, input); JS_FreeValue(context, event);
            result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
            break;
        }
        JSValue arguments[] = { event, input };
        JSValue returned = JS_Call(context, function, owner->module, 2, arguments);
        JS_FreeValue(context, event); JS_FreeValue(context, input);
        bool produced = !JS_IsUndefined(returned);
        if (JS_IsException(returned)) result = mwx_scene_quickjs_exception_result(owner->domain, diagnostic, diagnostic_capacity);
        else if (produced) {
            bool valid;
            if (dimensions > 1) valid = mwx_scene_quickjs_read_vector(context, returned, value, dimensions, true);
            else if (boolean_value) {
                valid = JS_IsBool(returned) || !owner->puppet_animation_configured;
                produced = JS_IsBool(returned);
                if (produced) *value = JS_ToBool(context, returned);
            } else valid = JS_IsNumber(returned) && JS_ToFloat64(context, value, returned) >= 0 &&
                (!owner->puppet_animation_configured || isfinite(*value));
            if (!valid) {
                mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "animationEvent returned an invalid typed value");
                result = MWX_SCENE_QUICKJS_BAD_RETURN;
            }
        }
        JS_FreeValue(context, returned);
        if (result == MWX_SCENE_QUICKJS_OK) result = mwx_scene_quickjs_drain_jobs(owner, diagnostic, diagnostic_capacity);
        if (result == MWX_SCENE_QUICKJS_OK) {
            if (returned_value_field != 0) {
                // Consume this callback's earlier self write in the same journal.
                // A later event/update can still write the field normally.
                MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                    mwx_scene_quickjs_authored_mutation_for_layer(owner, owner->target_layer_index);
                if (mutation != NULL && !mutation->destroyed && (mutation->fields & returned_value_field) != 0) {
                    if (produced) mwx_scene_quickjs_consume_authored_mutation_field(owner, mutation, returned_value_field);
                    else { *value = mutation->alpha; produced = true; }
                }
            }
            if (produced && value_produced != NULL) *value_produced = 1;
            owner->animation_event_cursor++;
            if (boolean_value) mwx_scene_quickjs_prepare_puppet_animation_visibility(owner, value);
        }
    }
    if (bound && !mwx_scene_quickjs_restore_frame_engine_host(owner, engine)) result = MWX_SCENE_QUICKJS_EXCEPTION;
    if (handles && !mwx_scene_quickjs_restore_owner_handles(owner, layer, scene, object)) result = MWX_SCENE_QUICKJS_EXCEPTION;
    mwx_scene_quickjs_end_callback(owner);
    JS_FreeValue(context, function);
    return result;
}

void mwx_scene_quickjs_finish_animation_events(MWXSceneQuickJSOwner *owner, bool commit) {
    if (owner->animation_baseline != NULL) {
        if (!commit) mwx_scene_quickjs_owner_timer_restore(owner, owner->animation_baseline);
        mwx_scene_quickjs_owner_timer_snapshot_destroy(owner->animation_baseline, owner);
        owner->animation_baseline = NULL;
    }
    if (commit && owner->animation_event_cursor != 0) {
        size_t consumed = owner->animation_event_cursor;
        for (size_t i = 0; i < consumed; ++i) js_free_rt(owner->domain->runtime, owner->animation_events[i].name);
        owner->animation_event_count -= consumed;
        memmove(owner->animation_events, owner->animation_events + consumed,
            owner->animation_event_count * sizeof(*owner->animation_events));
        owner->animation_event_cursor = 0;
        if (owner->animation_event_queue_epoch != UINT64_MAX) owner->animation_event_queue_epoch++;
    }
}

void mwx_scene_quickjs_destroy_animation_events(MWXSceneQuickJSOwner *owner) {
    for (size_t i = 0; i < owner->animation_event_count; ++i)
        js_free_rt(owner->domain->runtime, owner->animation_events[i].name);
    js_free_rt(owner->domain->runtime, owner->animation_events);
    owner->animation_events = NULL;
    owner->animation_event_count = owner->animation_event_cursor = 0;
    owner->animation_event_failure = 0;
    if (owner->animation_event_queue_epoch != UINT64_MAX) owner->animation_event_queue_epoch++;
    MWXSceneQuickJSOwner **cursor = &owner->domain->animation_owners;
    while (*cursor != NULL && *cursor != owner) cursor = &(*cursor)->animation_next;
    if (*cursor == owner) *cursor = owner->animation_next;
}

// The JS closure belongs to this domain, but can outlive its original owner.
// Resolve only the current callback owner; never dereference a retained owner.
static MWXSceneQuickJSOwner *animation_handle_owner(
    const MWXSceneQuickJSAnimationHandle *handle
) {
    if (handle == NULL || handle->domain == NULL ||
        !handle->domain->callback_active) return NULL;
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    if (owner == NULL || owner->disabled ||
        owner->identity != handle->owner_identity ||
        owner->generation != handle->generation) return NULL;
    return owner;
}

static void free_animation_handle(void *opaque) {
    MWXSceneQuickJSAnimationHandle *handle = opaque;
    if (handle->construction_finalized != NULL) *handle->construction_finalized = true;
    free(handle);
}

static JSValue animation_closure(
    MWXSceneQuickJSOwner *owner,
    JSCClosure *function,
    const char *name,
    MWXSceneQuickJSAnimationCommand command,
    const MWXSceneQuickJSAnimationHandle *target
) {
    MWXSceneQuickJSAnimationHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return JS_ThrowOutOfMemory(owner->domain->context);
    if (target != NULL) *handle = *target;
    handle->domain = owner->domain;
    handle->owner_identity = owner->identity;
    handle->generation = owner->generation;
    handle->command = command;
    bool finalized = false;
    handle->construction_finalized = &finalized;
    JSContext *context = owner->domain->context;
    const bool had_exception = JS_HasException(context);
    JSValue previous_exception = had_exception ? JS_GetException(context) : JS_UNDEFINED;
    JSValue closure = JS_NewCClosure(
        context, function, name,
        free_animation_handle, 0, 0, handle
    );
    // Early failure leaves the opaque allocation here. A later error during
    // function property creation may accompany a returned function object.
    if (!JS_IsException(closure) && JS_HasException(context)) {
        JS_FreeValue(context, closure);
        closure = JS_EXCEPTION;
    }
    if (JS_IsException(closure)) {
        if (!finalized) free(handle);
        JS_FreeValue(context, previous_exception);
    } else {
        handle->construction_finalized = NULL;
        if (had_exception) JS_Throw(context, previous_exception);
    }
    return closure;
}

static const MWXSceneQuickJSLayerRecord *animation_layer(
    MWXSceneQuickJSOwner *owner, uint32_t layer_index
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (layer_index >= domain->authored_layer_count) return NULL;
    const MWXSceneQuickJSLayerRecord *layer = &domain->layers[layer_index];
    const MWXSceneQuickJSAuthoredLayerMutationRecord *pending =
        mwx_scene_quickjs_authored_mutation_for_layer(owner, layer_index);
    return layer->configured && !layer->dynamic && !layer->destroyed &&
        (pending == NULL || !pending->destroyed) ? layer : NULL;
}

static bool named_animation_layer_alive(
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSNamedAnimationRecord *animation
) {
    const MWXSceneQuickJSLayerRecord *layer = animation_layer(owner, animation->layer_index);
    return layer != NULL && layer->layer_id == animation->layer_id;
}

static MWXSceneQuickJSOwner *animation_target_owner(
    const MWXSceneQuickJSAnimationHandle *handle
) {
    MWXSceneQuickJSOwner *owner = animation_handle_owner(handle);
    if (owner == NULL) return NULL;
    if (handle->catalog_index == UINT32_MAX) {
        return owner->current_animation_available &&
            (!owner->target_layer_configured || animation_layer(owner, owner->target_layer_index) != NULL)
            ? owner : NULL;
    }
    MWXSceneQuickJSDomain *domain = owner->domain;
    return !owner->value_only &&
        handle->catalog_index < domain->named_animation_count &&
        domain->named_animations[handle->catalog_index].target_index == handle->target_index &&
        named_animation_layer_alive(owner, &domain->named_animations[handle->catalog_index])
        ? owner : NULL;
}

static JSValue mutate_animation(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv, int magic, void *opaque) {
    (void)this_value;
    (void)magic;
    const MWXSceneQuickJSAnimationHandle *handle = opaque;
    MWXSceneQuickJSOwner *owner = animation_target_owner(handle);
    if (owner == NULL) {
        return JS_ThrowTypeError(context, "animation handle is stale");
    }
    double number = 0;
    if (handle->command == MWX_SCENE_QUICKJS_ANIMATION_SET_FRAME ||
        handle->command == MWX_SCENE_QUICKJS_ANIMATION_SET_RATE) {
        if (argc != 1 || !JS_IsNumber(argv[0]) ||
            JS_ToFloat64(context, &number, argv[0]) < 0 || !isfinite(number)) {
            return JS_ThrowTypeError(context, "%s expects one finite Number",
                handle->command == MWX_SCENE_QUICKJS_ANIMATION_SET_RATE ? "rate" : "setFrame");
        }
    } else if (argc != 0) {
        return JS_ThrowTypeError(context, "animation command expects no arguments");
    }
    if (owner->animation_command_count >= MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS) {
        owner->animation_command_overflow = true;
        return JS_ThrowInternalError(context, "animation command buffer exceeded");
    }
    const size_t index = owner->animation_command_count;
    const uint64_t epoch = owner->domain->callback_epoch;
    owner->animation_commands[index] = (MWXSceneQuickJSAnimationCommandRecord){
        .command = handle->command,
        .target_index = handle->target_index,
        .value = number,
        .callback_epoch = epoch,
        .ordinal = index > 0 && owner->animation_commands[index - 1].callback_epoch == epoch
            ? owner->animation_commands[index - 1].ordinal + 1 : 0,
        .playback_index = handle->playback_index,
    };
    owner->animation_command_count = index + 1;
    return JS_UNDEFINED;
}

static bool define_animation_command(
    JSContext *context,
    JSValue animation,
    MWXSceneQuickJSOwner *owner,
    const char *name,
    MWXSceneQuickJSAnimationCommand command,
    const MWXSceneQuickJSAnimationHandle *target
) {
    JSValue callback = animation_closure(
        owner, mutate_animation, name, command, target
    );
    if (JS_IsException(callback) ||
        JS_DefinePropertyValueStr(
            context, animation, name, callback, JS_PROP_ENUMERABLE
        ) < 0) {
        return false;
    }
    return true;
}

static JSValue get_animation_rate(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv, int magic, void *opaque) {
    (void)this_value; (void)argc; (void)argv; (void)magic;
    const MWXSceneQuickJSAnimationHandle *handle = opaque;
    MWXSceneQuickJSOwner *owner = animation_target_owner(handle);
    if (owner == NULL) return JS_ThrowTypeError(context, "animation handle is stale");

    MWXSceneQuickJSDomain *domain = owner->domain;
    if (domain->animation_rate_lookup == NULL || handle->target_index == UINT32_MAX)
        return JS_ThrowRangeError(context, "animation rate is unavailable");
    for (size_t i = owner->animation_command_count; i > 0; --i) {
        const MWXSceneQuickJSAnimationCommandRecord *write = &owner->animation_commands[i - 1];
        if (write->command == MWX_SCENE_QUICKJS_ANIMATION_SET_RATE &&
            write->playback_index == handle->playback_index)
            return JS_NewFloat64(context, write->value);
    }
    double rate;
    if (!domain->animation_rate_lookup(domain->animation_rate_opaque, handle->target_index, &rate))
        return JS_ThrowRangeError(context, "animation rate is unavailable");
    return JS_NewFloat64(context, rate);
}

static bool define_animation_rate(JSContext *context, JSValue animation,
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSAnimationHandle *target) {
    JSAtom property = JS_NewAtom(context, "rate");
    if (property == JS_ATOM_NULL) return false;
    JSValue getter = animation_closure(owner, get_animation_rate, "rate",
        MWX_SCENE_QUICKJS_ANIMATION_SET_RATE, target);
    JSValue setter = JS_IsException(getter) ? JS_UNDEFINED
        : animation_closure(owner, mutate_animation, "rate", MWX_SCENE_QUICKJS_ANIMATION_SET_RATE, target);
    int result = -1;
    if (JS_IsException(getter) || JS_IsException(setter)) {
        JS_FreeValue(context, getter);
        JS_FreeValue(context, setter);
    } else {
        result = JS_DefinePropertyGetSet(context, animation, property, getter, setter, JS_PROP_ENUMERABLE);
    }
    JS_FreeAtom(context, property);
    return result >= 0;
}

static JSValue get_animation(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSAnimationHandle *handle = opaque;
    MWXSceneQuickJSOwner *owner = animation_handle_owner(handle);
    if (owner == NULL) {
        return JS_ThrowTypeError(context, "getAnimation host is unavailable");
    }
    MWXSceneQuickJSAnimationHandle target = *handle;
    target.target_index = UINT32_MAX;
    target.catalog_index = UINT32_MAX;
    if (argc == 0) {
        if (!handle->current_property) {
            return JS_ThrowTypeError(context, "getAnimation expects one name");
        }
        if (!owner->current_animation_available) {
            return JS_ThrowRangeError(context, "current property animation does not exist");
        }
        target.target_index = owner->animation_target_index;
        target.playback_index = owner->animation_playback_index;
    } else {
        if (argc != 1 || !JS_IsString(argv[0])) {
            return JS_ThrowTypeError(context, "named animation lookup expects one String name");
        }
        if (handle->component_lookup &&
            (!owner->animation_target_configured || owner->animation_effect_index == UINT32_MAX)) {
            return JS_ThrowTypeError(context, "animation component is unavailable");
        }
        MWXSceneQuickJSDomain *domain = owner->domain;
        uint32_t layer_index = handle->layer_index;
        if (!handle->scene_lookup) {
            if (layer_index == UINT32_MAX) {
                if (!owner->target_layer_configured) {
                    return JS_ThrowTypeError(context, "animation layer is unavailable");
                }
                layer_index = owner->target_layer_index;
            }
            if (layer_index >= domain->authored_layer_count ||
                !domain->layers[layer_index].configured ||
                domain->layers[layer_index].destroyed || domain->layers[layer_index].dynamic ||
                (handle->layer_index != UINT32_MAX &&
                 domain->layers[layer_index].layer_id != handle->layer_id)) {
                return JS_ThrowTypeError(context, "animation layer is stale");
            }
        }
        size_t length = 0;
        const char *name = JS_ToCStringLen(context, &length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        if (length == 0 || length > MWX_SCENE_QUICKJS_MAX_ANIMATION_NAME ||
            memchr(name, '\0', length) != NULL) {
            JS_FreeCString(context, name);
            return JS_ThrowRangeError(context, "animation name is invalid");
        }
        size_t matches = 0;
        for (size_t i = 0; i < domain->named_animation_count; ++i) {
            const MWXSceneQuickJSNamedAnimationRecord *candidate = &domain->named_animations[i];
            const bool scope_matches = handle->scene_lookup ||
                (candidate->layer_index == layer_index && (handle->component_lookup
                    ? candidate->scene_only &&
                        candidate->effect_index == owner->animation_effect_index &&
                        candidate->pass_index == owner->animation_pass_index
                    : !candidate->scene_only));
            if (scope_matches && candidate->name_length == length &&
                memcmp(candidate->name, name, length) == 0 &&
                named_animation_layer_alive(owner, candidate)) {
                target.target_index = candidate->target_index;
                target.catalog_index = (uint32_t)i;
                target.playback_index = candidate->playback_index;
                matches += 1;
            }
        }
        JS_FreeCString(context, name);
        if (matches != 1) {
            return JS_ThrowRangeError(context, "named animation does not exist or is ambiguous");
        }
    }
    JSValue animation = JS_NewObject(context);
    if (JS_IsException(animation)) return animation;
    if (!define_animation_command(
            context, animation, owner, "play", MWX_SCENE_QUICKJS_ANIMATION_PLAY, &target
        ) ||
        !define_animation_command(
            context, animation, owner, "pause", MWX_SCENE_QUICKJS_ANIMATION_PAUSE, &target
        ) ||
        !define_animation_command(
            context, animation, owner, "stop", MWX_SCENE_QUICKJS_ANIMATION_STOP, &target
        ) ||
        !define_animation_command(
            context, animation, owner, "setFrame", MWX_SCENE_QUICKJS_ANIMATION_SET_FRAME, &target
        ) || !define_animation_rate(context, animation, owner, &target)) {
        JS_FreeValue(context, animation);
        return JS_EXCEPTION;
    }
    return animation;
}

bool mwx_scene_quickjs_install_object_handle(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return false;
    JSContext *context = owner->domain->context;
    JSValue object = JS_NewObject(context);
    if (JS_IsException(object)) return false;
    const MWXSceneQuickJSAnimationHandle target = {
        .layer_index = UINT32_MAX, .current_property = true, .component_lookup = true,
    };
    JSValue animation = animation_closure(
        owner, get_animation, "getAnimation", 0, &target
    );
    if (JS_IsException(animation) ||
        JS_DefinePropertyValueStr(
            context, object, "getAnimation", animation, JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, object);
        return false;
    }
    owner->object_handle = object;
    return true;
}

/// A layer property belongs to the layer, so `thisObject` is the layer's own
/// handle there and the documented `ILayer extends IObject` surface includes
/// the current property's animation. Only that scope gets the accessor: for an
/// effect or particle property the current property is the component's, and
/// exposing it through the layer handle would misattribute its owner.
bool mwx_scene_quickjs_define_property_animation_accessor(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL ||
        !JS_IsObject(owner->material_function_layer)) {
        return false;
    }
    return mwx_scene_quickjs_define_layer_animation_accessor(
        owner, owner->material_function_layer, UINT32_MAX, true
    );
}

bool mwx_scene_quickjs_define_layer_animation_accessor(
    MWXSceneQuickJSOwner *owner, JSValue layer, uint32_t layer_index,
    bool current_property
) {
    if (owner == NULL || owner->domain == NULL || !JS_IsObject(layer) ||
        (layer_index != UINT32_MAX && layer_index >= owner->domain->layer_count)) return false;
    JSContext *context = owner->domain->context;
    const MWXSceneQuickJSAnimationHandle target = {
        .layer_index = layer_index,
        .layer_id = layer_index == UINT32_MAX ? 0 : owner->domain->layers[layer_index].layer_id,
        .current_property = current_property,
    };
    JSValue animation = animation_closure(owner, get_animation, "getAnimation", 0, &target);
    if (JS_IsException(animation)) return false;
    return JS_DefinePropertyValueStr(
        context, layer, "getAnimation", animation, JS_PROP_ENUMERABLE | JS_PROP_CONFIGURABLE
    ) >= 0;
}

bool mwx_scene_quickjs_define_scene_animation_accessor(
    MWXSceneQuickJSOwner *owner, JSValue scene
) {
    if (owner == NULL || owner->domain == NULL || !JS_IsObject(scene)) return false;
    const MWXSceneQuickJSAnimationHandle target = {
        .scene_lookup = true,
    };
    JSValue animation = animation_closure(owner, get_animation, "getAnimation", 0, &target);
    if (JS_IsException(animation)) return false;
    return JS_DefinePropertyValueStr(
        owner->domain->context, scene, "getAnimation", animation,
        JS_PROP_ENUMERABLE | JS_PROP_CONFIGURABLE
    ) >= 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_read_bound_scalar(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *property_name,
    size_t property_name_length,
    double *value,
    uint32_t *present,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->domain == NULL ||
        owner->domain->context == NULL || property_name == NULL ||
        property_name_length == 0 || property_name_length > 256 ||
        memchr(property_name, '\0', property_name_length) != NULL ||
        value == NULL || present == NULL ||
        JS_IsUndefined(owner->object_handle)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid bound scalar property request"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *value = 0;
    *present = 0;
    if (owner->generation != expected_generation) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "stale SceneScript owner generation"
        );
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript owner is disabled"
        );
        return MWX_SCENE_QUICKJS_DISABLED;
    }

    JSContext *context = owner->domain->context;
    JSAtom atom = JS_NewAtomLen(context, property_name, property_name_length);
    if (atom == JS_ATOM_NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "bound scalar property atom allocation failed"
        );
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    JSPropertyDescriptor descriptor = {
        .flags = 0,
        .value = JS_UNDEFINED,
        .getter = JS_UNDEFINED,
        .setter = JS_UNDEFINED,
    };
    int found = JS_GetOwnProperty(
        context, &descriptor, owner->object_handle, atom
    );
    JS_FreeAtom(context, atom);
    if (found < 0) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "bound scalar property lookup failed"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (found == 0) return MWX_SCENE_QUICKJS_OK;

    const bool data_property = JS_IsUndefined(descriptor.getter) &&
        JS_IsUndefined(descriptor.setter) && JS_IsNumber(descriptor.value);
    double scalar = 0;
    const int conversion = data_property
        ? JS_ToFloat64(context, &scalar, descriptor.value) : -1;
    JS_FreeValue(context, descriptor.value);
    JS_FreeValue(context, descriptor.getter);
    JS_FreeValue(context, descriptor.setter);
    if (!data_property || conversion < 0 || !isfinite(scalar)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "bound scalar property is not a finite data value"
        );
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    *value = scalar;
    *present = 1;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_animation_target(
    MWXSceneQuickJSOwner *owner,
    uint32_t available,
    uint32_t effect_index,
    uint32_t pass_index,
    uint32_t target_index,
    uint32_t playback_index,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || available > 1 || owner->animation_target_configured ||
        (effect_index == UINT32_MAX) != (pass_index == UINT32_MAX)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid animation target configuration"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    owner->current_animation_available = available != 0;
    owner->animation_effect_index = effect_index;
    owner->animation_pass_index = pass_index;
    owner->animation_target_index = target_index;
    owner->animation_playback_index = playback_index;
    owner->animation_target_configured = true;
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_domain_bind_animation_rate_lookup(
    MWXSceneQuickJSDomain *domain, MWXSceneQuickJSAnimationRateLookup lookup, void *opaque
) {
    domain->animation_rate_lookup = lookup;
    domain->animation_rate_opaque = opaque;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_named_animations(
    MWXSceneQuickJSDomain *domain,
    const MWXSceneQuickJSNamedAnimation *animations,
    size_t count,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->context == NULL || domain->callback_epoch != 0 ||
        domain->named_animations_configured || count > MWX_SCENE_QUICKJS_MAX_NAMED_ANIMATIONS ||
        (count != 0 && animations == NULL)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid named animation catalog"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    MWXSceneQuickJSNamedAnimationRecord *catalog = count == 0 ? NULL :
        calloc(count, sizeof(*catalog));
    if (count != 0 && catalog == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    for (size_t i = 0; i < count; ++i) {
        const MWXSceneQuickJSNamedAnimation *input = &animations[i];
        if (input->target_index == UINT32_MAX || input->name == NULL ||
            input->scene_only > 1 ||
            input->name_length == 0 || input->name_length > MWX_SCENE_QUICKJS_MAX_ANIMATION_NAME ||
            memchr(input->name, '\0', input->name_length) != NULL) goto invalid;
        for (size_t j = 0; j < i; ++j)
            if (catalog[j].target_index == input->target_index) goto invalid;
        uint32_t layer_index = UINT32_MAX;
        for (uint32_t j = 0; j < domain->authored_layer_count; ++j) {
            const MWXSceneQuickJSLayerRecord *layer = &domain->layers[j];
            if (layer->configured && !layer->dynamic && !layer->destroyed &&
                layer->layer_id == input->layer_id) {
                if (layer_index != UINT32_MAX) goto invalid;
                layer_index = j;
            }
        }
        if (layer_index == UINT32_MAX) goto invalid;
        catalog[i].target_index = input->target_index;
        catalog[i].layer_index = layer_index;
        catalog[i].layer_id = input->layer_id;
        catalog[i].name_length = input->name_length;
        catalog[i].scene_only = input->scene_only;
        catalog[i].effect_index = input->effect_index;
        catalog[i].pass_index = input->pass_index;
        catalog[i].playback_index = input->playback_index;
        memcpy(catalog[i].name, input->name, input->name_length);
    }
    domain->named_animations = catalog;
    domain->named_animation_count = count;
    domain->named_animations_configured = true;
    return MWX_SCENE_QUICKJS_OK;
invalid:
    free(catalog);
    mwx_scene_quickjs_write_diagnostic(
        diagnostic, diagnostic_capacity, "invalid named animation target or name"
    );
    return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
}

size_t mwx_scene_quickjs_owner_animation_command_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner == NULL ? 0 : owner->animation_command_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_animation_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSAnimationCommand *command,
    uint32_t *target_index,
    double *value,
    uint64_t *callback_epoch,
    uint32_t *ordinal,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    // Author code can catch the command-buffer exception. The host must still
    // reject the entire journal instead of publishing its bounded prefix.
    if (owner != NULL && owner->animation_command_overflow) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "animation command buffer exceeded"
        );
        return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
    }
    if (owner == NULL || command == NULL || target_index == NULL || value == NULL ||
        callback_epoch == NULL || ordinal == NULL ||
        index >= owner->animation_command_count) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid animation command mutation"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *command = owner->animation_commands[index].command;
    *target_index = owner->animation_commands[index].target_index;
    *value = owner->animation_commands[index].value;
    *callback_epoch = owner->animation_commands[index].callback_epoch;
    *ordinal = owner->animation_commands[index].ordinal;
    return MWX_SCENE_QUICKJS_OK;
}
