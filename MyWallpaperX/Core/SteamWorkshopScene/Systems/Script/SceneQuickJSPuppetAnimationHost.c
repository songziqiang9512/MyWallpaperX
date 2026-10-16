#include "SceneQuickJSInternal.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

// The domain holds a projection of the one native playback runtime. A closure
// retains identities only; it never retains a potentially freed owner/record.
typedef struct PuppetAnimationHandle {
    MWXSceneQuickJSDomain *domain;
    uint64_t owner_identity, generation, target_incarnation;
    MWXSceneQuickJSPuppetAnimationIdentity target;
    int operation;
} PuppetAnimationHandle;

static MWXSceneQuickJSPuppetAnimationIdentity snapshot_identity(
    const MWXSceneQuickJSPuppetAnimationSnapshot *snapshot
) {
    return (MWXSceneQuickJSPuppetAnimationIdentity){
        snapshot->layer_id, snapshot->animation_layer_index,
        snapshot->animation_layer_id, snapshot->has_animation_layer_id
    };
}

static bool same_identity(MWXSceneQuickJSPuppetAnimationIdentity a,
    MWXSceneQuickJSPuppetAnimationIdentity b) {
    return a.layer_id == b.layer_id && a.animation_layer_index == b.animation_layer_index &&
        a.has_animation_layer_id == b.has_animation_layer_id &&
        (!a.has_animation_layer_id || a.animation_layer_id == b.animation_layer_id);
}

static MWXSceneQuickJSPuppetAnimationRecord *record_for_identity(
    MWXSceneQuickJSDomain *domain, MWXSceneQuickJSPuppetAnimationIdentity identity
) {
    for (size_t i = 0; i < domain->puppet_animation_count; ++i)
        if (same_identity(snapshot_identity(&domain->puppet_animations[i].snapshot), identity))
            return &domain->puppet_animations[i];
    return NULL;
}

static bool parent_alive(MWXSceneQuickJSOwner *owner, int64_t layer_id) {
    // The standalone C thisObject API predates the layer catalog. Production
    // layer receivers additionally bind the prepared authored parent record.
    if (!owner->target_layer_configured) return owner->domain->layer_count == 0;
    uint32_t index = owner->target_layer_index;
    if (index >= owner->domain->authored_layer_count) return false;
    const MWXSceneQuickJSLayerRecord *layer = &owner->domain->layers[index];
    const MWXSceneQuickJSAuthoredLayerMutationRecord *pending =
        mwx_scene_quickjs_authored_mutation_for_layer(owner, index);
    return layer->configured && !layer->dynamic && !layer->destroyed &&
        layer->layer_id == layer_id && (pending == NULL || !pending->destroyed);
}

static MWXSceneQuickJSPuppetAnimationRecord *resolve_source(
    MWXSceneQuickJSOwner *owner, bool executable) {
    if (owner == NULL || owner->domain == NULL || owner->disabled ||
        !owner->puppet_animation_configured || owner->puppet_animation_incarnation == 0 ||
        !parent_alive(owner, owner->puppet_animation_identity.layer_id)) return NULL;
    if (owner->puppet_animation_catalog_index >= owner->domain->puppet_animation_count) return NULL;
    MWXSceneQuickJSPuppetAnimationRecord *record =
        &owner->domain->puppet_animations[owner->puppet_animation_catalog_index];
    return (!executable || (owner->puppet_animation_available && record->available)) &&
        same_identity(snapshot_identity(&record->snapshot), owner->puppet_animation_identity) &&
        record->incarnation == owner->puppet_animation_incarnation ? record : NULL;
}

static MWXSceneQuickJSPuppetAnimationRecord *source_record(MWXSceneQuickJSOwner *owner) {
    return resolve_source(owner, true);
}

static void clear_pending_events(MWXSceneQuickJSOwner *owner) {
    for (size_t i = 0; i < owner->puppet_event_count; ++i) js_free_rt(owner->domain->runtime, owner->puppet_events[i].name);
    js_free_rt(owner->domain->runtime, owner->puppet_events);
    owner->puppet_events = NULL;
    owner->puppet_event_count = owner->puppet_event_cursor = 0;
    owner->puppet_event_failure = 0;
    if (owner->puppet_event_queue_epoch != UINT64_MAX) owner->puppet_event_queue_epoch++;
}

uint32_t mwx_scene_quickjs_owner_animation_event_export(const MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return 0;
    JSContext *context = owner->domain->context;
    JSValue function = JS_GetPropertyStr(context, owner->module, "animationEvent");
    uint32_t kind = JS_IsUndefined(function) ? 0 : JS_IsFunction(context, function) ? 1 : 2;
    JS_FreeValue(context, function);
    return kind;
}

bool mwx_scene_quickjs_owner_has_pending_puppet_animation_events(const MWXSceneQuickJSOwner *owner) {
    return owner != NULL && !owner->disabled && owner->puppet_handles_events &&
        (owner->puppet_event_failure != 0 || owner->puppet_event_cursor < owner->puppet_event_count);
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_publish_puppet_animation_events(
    MWXSceneQuickJSDomain *domain, const MWXSceneQuickJSPuppetAnimationEvent *events,
    size_t count, char *diagnostic, size_t diagnostic_capacity) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        (count != 0 && events == NULL)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (size_t i = 0; i < count; ++i) {
        const MWXSceneQuickJSPuppetAnimationEvent *event = &events[i];
        MWXSceneQuickJSPuppetAnimationIdentity identity = { event->layer_id,
            event->animation_layer_index, event->animation_layer_id, event->has_animation_layer_id };
        MWXSceneQuickJSPuppetAnimationRecord *record = record_for_identity(domain, identity);
        uint32_t failure = event->failure;
        if (!failure && (event->sequence == 0 || event->name == NULL ||
            strlen(event->name) == 0 || strlen(event->name) > 1024 || event->frame < 0 ||
            event->frame > INT64_C(9007199254740991))) failure = 2;
        if (!failure && (record == NULL || record->incarnation == 0 ||
            event->sequence <= record->event_published_sequence)) continue;
        for (MWXSceneQuickJSOwner *owner = domain->puppet_animation_owners;
             owner != NULL; owner = owner->puppet_animation_next) {
            if (!owner->puppet_handles_events || resolve_source(owner, false) == NULL ||
                owner->puppet_animation_identity.layer_id != event->layer_id) continue;
            if (failure) { owner->puppet_event_failure = failure; continue; }
            if (owner->puppet_event_count == 64) { owner->puppet_event_failure = 5; continue; }
            if (owner->puppet_events == NULL) {
                owner->puppet_events = js_malloc_rt(domain->runtime, 64 * sizeof(*owner->puppet_events));
                if (owner->puppet_events == NULL) { owner->puppet_event_failure = 8; continue; }
            }
            char *name = js_malloc_rt(domain->runtime, strlen(event->name) + 1);
            if (name == NULL) { owner->puppet_event_failure = 8; continue; }
            strcpy(name, event->name);
            owner->puppet_events[owner->puppet_event_count++] =
                (MWXSceneQuickJSPuppetPendingEvent){ identity, record->incarnation, name, event->frame };
        }
        if (!failure) record->event_published_sequence = event->sequence;
    }
    return MWX_SCENE_QUICKJS_OK;
}

static MWXSceneQuickJSOwner *handle_owner(const PuppetAnimationHandle *handle) {
    if (handle == NULL || handle->domain == NULL || !handle->domain->callback_active) return NULL;
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    if (owner == NULL || owner->identity != handle->owner_identity ||
        owner->generation != handle->generation || source_record(owner) == NULL) return NULL;
    return owner;
}

static MWXSceneQuickJSPuppetAnimationRecord *handle_record(
    MWXSceneQuickJSOwner *owner, const PuppetAnimationHandle *handle
) {
    if (handle->target.layer_id != owner->puppet_animation_identity.layer_id) return NULL;
    MWXSceneQuickJSPuppetAnimationRecord *record = record_for_identity(owner->domain, handle->target);
    return record != NULL && record->available && record->incarnation == handle->target_incarnation
        ? record : NULL;
}

static bool puppet_transaction(MWXSceneQuickJSOwner *owner) {
    if (owner->puppet_animation_baseline != NULL) return true;
    owner->puppet_animation_baseline = mwx_scene_quickjs_owner_timer_snapshot(owner);
    return owner->puppet_animation_baseline != NULL;
}

static void apply_command(MWXSceneQuickJSPuppetAnimationSnapshot *state,
    const MWXSceneQuickJSPuppetAnimationCommand *command) {
    switch (command->action) {
    case 0: state->is_playing = 1; break;
    case 1: state->is_playing = 0; break;
    case 2: state->is_playing = 0; state->current_frame = 0; break;
    case 3: state->current_frame = (float)command->value; break;
    case 4: state->rate = (float)command->value; break;
    case 5: state->blend = (float)command->value; break;
    case 6: state->visible = command->value != 0; break;
    }
}

static MWXSceneQuickJSPuppetAnimationSnapshot current_state(MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSPuppetAnimationRecord *record) {
    MWXSceneQuickJSPuppetAnimationSnapshot state = record->snapshot;
    MWXSceneQuickJSPuppetAnimationIdentity identity = snapshot_identity(&state);
    bool is_self = same_identity(identity, owner->puppet_animation_identity);
    for (size_t i = 0; i <= owner->puppet_animation_command_count; ++i) {
        if (is_self && owner->puppet_animation_visibility.present &&
            i == owner->puppet_animation_visibility.journal_cutoff)
            state.visible = owner->puppet_animation_visibility.value;
        if (i == owner->puppet_animation_command_count) break;
        const MWXSceneQuickJSPuppetAnimationCommand *command = &owner->puppet_animation_commands[i];
        MWXSceneQuickJSPuppetAnimationIdentity target = {
            command->layer_id, command->animation_layer_index,
            command->animation_layer_id, command->has_animation_layer_id
        };
        if (same_identity(identity, target)) apply_command(&state, command);
    }
    return state;
}

static bool puppet_command(MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSPuppetAnimationRecord *record, uint32_t action, double value) {
    if (owner->puppet_animation_command_count >= MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_COMMANDS) {
        owner->puppet_animation_command_overflow = true;
        return false;
    }
    if (!puppet_transaction(owner)) return false;
    uint32_t ordinal = 0;
    for (size_t i = owner->puppet_animation_command_count; i > 0; --i) {
        if (owner->puppet_animation_commands[i - 1].callback_epoch != owner->domain->callback_epoch) break;
        ordinal++;
    }
    const MWXSceneQuickJSPuppetAnimationSnapshot *state = &record->snapshot;
    owner->puppet_animation_commands[owner->puppet_animation_command_count++] =
        (MWXSceneQuickJSPuppetAnimationCommand) {
            .layer_id = state->layer_id, .animation_layer_index = state->animation_layer_index,
            .animation_layer_id = state->animation_layer_id,
            .has_animation_layer_id = state->has_animation_layer_id,
            .action = action, .value = value,
            .callback_epoch = owner->domain->callback_epoch, .ordinal = ordinal
        };
    if (action == 6) owner->puppet_animation_visibility_staged = true;
    return true;
}

static JSValue animation_call(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv, int magic, void *opaque) {
    (void)this_value; (void)magic;
    PuppetAnimationHandle *handle = opaque;
    MWXSceneQuickJSOwner *owner = handle_owner(handle);
    MWXSceneQuickJSPuppetAnimationRecord *record = owner == NULL ? NULL : handle_record(owner, handle);
    if (record == NULL) return JS_ThrowTypeError(context, "Puppet animation target is unavailable or stale");
    bool is_self = same_identity(handle->target, owner->puppet_animation_identity);
    int operation = handle->operation;
    if (operation <= 6) {
        double value = 0;
        if (operation <= 2 ? argc != 0 : argc != 1)
            return JS_ThrowTypeError(context, "invalid Puppet animation command argument");
        if (operation == 6) {
            if (!is_self || !JS_IsBool(argv[0]))
                return JS_ThrowTypeError(context, "animation visible requires its own Boolean owner");
            value = JS_ToBool(context, argv[0]);
        } else if (operation >= 3 && (!JS_IsNumber(argv[0]) ||
            JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value) || fabs(value) > FLT_MAX)) {
            return JS_ThrowTypeError(context, "animation command expects a finite Float");
        }
        if (!puppet_command(owner, record, (uint32_t)operation, value))
            return JS_ThrowRangeError(context, "Puppet animation command or snapshot budget exceeded");
        return JS_UNDEFINED;
    }
    MWXSceneQuickJSPuppetAnimationSnapshot state = current_state(owner, record);
    if (operation == 16) {
        if (!is_self) return JS_ThrowTypeError(context, "ended callbacks require their own animation owner");
        if (argc != 1 || !JS_IsFunction(context, argv[0]))
            return JS_ThrowTypeError(context, "addEndedCallback expects one function");
        if (!state.supports_ended_callbacks || state.ended_failure)
            return JS_ThrowRangeError(context, "Puppet animation ended profile is unsupported");
        if (owner->puppet_animation_callback_count >= MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_CALLBACKS)
            return JS_ThrowRangeError(context, "Puppet animation callback budget exceeded");
        if (!puppet_transaction(owner)) return JS_ThrowInternalError(context, "animation callback snapshot allocation failed");
        owner->puppet_animation_callbacks[owner->puppet_animation_callback_count++] = JS_DupValue(context, argv[0]);
        owner->puppet_animation_registration_count++;
        return JS_UNDEFINED;
    }
    if (argc != 0) return JS_ThrowTypeError(context, "animation getter expects no argument");
    switch (operation) {
    case 7: return JS_NewFloat64(context, state.current_frame);
    case 8: return JS_NewBool(context, state.is_playing);
    case 9: return JS_NewFloat64(context, state.fps);
    case 10: return JS_NewFloat64(context, state.frame_count);
    case 11: return JS_NewFloat64(context, state.duration);
    case 12: return JS_NewString(context, state.name);
    case 13: return JS_NewFloat64(context, state.rate);
    case 14: return JS_NewFloat64(context, state.blend);
    case 15: return JS_NewBool(context, state.visible);
    }
    return JS_ThrowTypeError(context, "unknown Puppet animation operation");
}

static void free_handle(void *opaque) { free(opaque); }

static JSValue animation_function(MWXSceneQuickJSOwner *owner, const char *name,
    int operation, const MWXSceneQuickJSPuppetAnimationRecord *record) {
    PuppetAnimationHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return JS_ThrowOutOfMemory(owner->domain->context);
    *handle = (PuppetAnimationHandle){ .domain = owner->domain,
        .owner_identity = owner->identity, .generation = owner->generation, .operation = operation };
    if (record != NULL) {
        handle->target = snapshot_identity(&record->snapshot);
        handle->target_incarnation = record->incarnation;
    }
    return JS_NewCClosure(owner->domain->context, animation_call, name,
        free_handle, 0, 0, handle);
}

static JSValue target_handle(MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSPuppetAnimationRecord *record) {
    JSContext *context = owner->domain->context;
    JSValue object = JS_NewObject(context);
    if (JS_IsException(object)) return object;
    const char *methods[] = { "play", "pause", "stop", "setFrame", "getFrame", "isPlaying", "addEndedCallback" };
    const int operations[] = { 0, 1, 2, 3, 7, 8, 16 };
    for (size_t i = 0; i < sizeof(operations) / sizeof(operations[0]); ++i) {
        JSValue function = animation_function(owner, methods[i], operations[i], record);
        if (JS_IsException(function) || JS_DefinePropertyValueStr(context, object,
            methods[i], function, JS_PROP_ENUMERABLE) < 0) goto fail;
    }
    const char *properties[] = { "fps", "frameCount", "duration", "name", "rate", "blend", "visible" };
    for (size_t i = 0; i < sizeof(properties) / sizeof(properties[0]); ++i) {
        JSAtom atom = JS_NewAtom(context, properties[i]);
        if (atom == JS_ATOM_NULL) goto fail;
        JSValue getter = animation_function(owner, properties[i], 9 + (int)i, record);
        JSValue setter = i >= 4 ? animation_function(owner, properties[i], (int)i, record) : JS_UNDEFINED;
        int result = JS_IsException(getter) || JS_IsException(setter) ? -1 :
            JS_DefinePropertyGetSet(context, object, atom, getter, setter, JS_PROP_ENUMERABLE);
        JS_FreeAtom(context, atom);
        if (result < 0) goto fail;
    }
    return object;
fail:
    JS_FreeValue(context, object);
    return JS_EXCEPTION;
}

JSValue mwx_scene_quickjs_puppet_animation_handle(MWXSceneQuickJSOwner *owner) {
    MWXSceneQuickJSPuppetAnimationRecord *record = source_record(owner);
    if (record == NULL)
        return JS_ThrowTypeError(owner->domain->context, "prepared Puppet animation metadata is unavailable");
    return target_handle(owner, record);
}

static JSValue get_animation_layer(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv, int magic, void *opaque) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = handle_owner(opaque);
    if (owner == NULL || !owner->target_layer_configured ||
        !owner->puppet_animation_identity.has_animation_layer_id)
        return JS_ThrowTypeError(context, "getAnimationLayer requires its prepared nested owner");
    if (argc != 1 || (!JS_IsString(argv[0]) && !JS_IsNumber(argv[0])))
        return JS_ThrowTypeError(context, "getAnimationLayer expects one name or index");
    double authored_index = 0;
    size_t name_length = 0;
    const char *name = NULL;
    if (JS_IsNumber(argv[0])) {
        if (JS_ToFloat64(context, &authored_index, argv[0]) < 0) return JS_EXCEPTION;
        if (!isfinite(authored_index) || authored_index < 0 || authored_index > UINT32_MAX ||
            trunc(authored_index) != authored_index)
            return JS_ThrowRangeError(context, "animation layer index is invalid");
    } else {
        name = JS_ToCStringLen(context, &name_length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        if (name_length == 0 || name_length > 1024 || memchr(name, '\0', name_length) != NULL) {
            JS_FreeCString(context, name);
            return JS_ThrowRangeError(context, "animation layer name is invalid");
        }
    }
    size_t matches = 0;
    MWXSceneQuickJSPuppetAnimationRecord *target = NULL;
    for (size_t i = 0; i < owner->domain->puppet_animation_count; ++i) {
        MWXSceneQuickJSPuppetAnimationRecord *record = &owner->domain->puppet_animations[i];
        const MWXSceneQuickJSPuppetAnimationSnapshot *snapshot = &record->snapshot;
        if (!record->available || snapshot->layer_id != owner->puppet_animation_identity.layer_id) continue;
        if (name != NULL ? strlen(snapshot->name) == name_length &&
            memcmp(snapshot->name, name, name_length) == 0 : snapshot->animation_layer_index == (uint32_t)authored_index) {
            matches++; target = record;
        }
    }
    if (name != NULL) JS_FreeCString(context, name);
    if (matches != 1) return JS_ThrowRangeError(context, "animation layer does not exist or is ambiguous");
    return target_handle(owner, target);
}

bool mwx_scene_quickjs_define_puppet_animation_lookup(MWXSceneQuickJSOwner *owner, JSValue layer) {
    PuppetAnimationHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return false;
    *handle = (PuppetAnimationHandle){ .domain = owner->domain,
        .owner_identity = owner->identity, .generation = owner->generation };
    JSValue function = JS_NewCClosure(owner->domain->context, get_animation_layer,
        "getAnimationLayer", free_handle, 1, 0, handle);
    return !JS_IsException(function) && JS_DefinePropertyValueStr(owner->domain->context,
        layer, "getAnimationLayer", function, JS_PROP_ENUMERABLE) >= 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_puppet_animation(
    MWXSceneQuickJSOwner *owner, int64_t layer_id, uint32_t authored_index,
    int64_t animation_layer_id, uint32_t has_animation_layer_id,
    char *diagnostic, size_t diagnostic_capacity) {
    if (owner == NULL || owner->domain == NULL || owner->value_only ||
        !owner->effectful_boolean || owner->current_animation_available ||
        owner->puppet_animation_configured || has_animation_layer_id > 1 || layer_id < 0) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid Puppet animation owner configuration");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    owner->puppet_animation_identity = (MWXSceneQuickJSPuppetAnimationIdentity){
        layer_id, authored_index, animation_layer_id, has_animation_layer_id };
    owner->puppet_animation_catalog_index = SIZE_MAX;
    owner->puppet_animation_configured = true;
    owner->puppet_handles_events = mwx_scene_quickjs_owner_animation_event_export(owner) != 0;
    owner->puppet_animation_next = owner->domain->puppet_animation_owners;
    owner->domain->puppet_animation_owners = owner;
    return MWX_SCENE_QUICKJS_OK;
}

static bool valid_snapshot(const MWXSceneQuickJSPuppetAnimationSnapshot *snapshot) {
    return snapshot->layer_id >= 0 && snapshot->has_animation_layer_id <= 1 &&
        snapshot->name != NULL && strlen(snapshot->name) <= 1024 &&
        isfinite(snapshot->fps) && snapshot->fps > 0 &&
        isfinite(snapshot->frame_count) && snapshot->frame_count >= 0 &&
        isfinite(snapshot->duration) && snapshot->duration >= 0 &&
        isfinite(snapshot->current_frame) && fabs(snapshot->current_frame) <= FLT_MAX &&
        isfinite(snapshot->rate) && fabs(snapshot->rate) <= FLT_MAX &&
        isfinite(snapshot->blend) && fabs(snapshot->blend) <= FLT_MAX &&
        snapshot->is_playing <= 1 && snapshot->visible <= 1 && snapshot->supports_ended_callbacks <= 1;
}

static bool same_metadata(const MWXSceneQuickJSPuppetAnimationSnapshot *a,
    const MWXSceneQuickJSPuppetAnimationSnapshot *b) {
    return a->animation_id == b->animation_id && a->fps == b->fps &&
        a->frame_count == b->frame_count && a->duration == b->duration &&
        strcmp(a->name, b->name) == 0 && b->ended_sequence >= a->ended_sequence;
}

static void clear_catalog(MWXSceneQuickJSDomain *domain) {
    for (size_t i = 0; i < domain->puppet_animation_count; ++i)
        free((char *)domain->puppet_animations[i].snapshot.name);
    free(domain->puppet_animations);
    domain->puppet_animations = NULL;
    domain->puppet_animation_count = 0;
}

static void refresh_owners(MWXSceneQuickJSDomain *domain, bool layout_changed) {
    for (MWXSceneQuickJSOwner *owner = domain->puppet_animation_owners; owner; owner = owner->puppet_animation_next) {
        size_t index = owner->puppet_animation_catalog_index;
        MWXSceneQuickJSPuppetAnimationRecord *record = index < domain->puppet_animation_count
            ? &domain->puppet_animations[index] : NULL;
        if (layout_changed || !owner->puppet_animation_catalog_bound) {
            record = record_for_identity(domain, owner->puppet_animation_identity);
            owner->puppet_animation_catalog_index = record == NULL ? SIZE_MAX
                : (size_t)(record - domain->puppet_animations);
            owner->puppet_animation_catalog_bound = true;
        }
        if (owner->puppet_animation_incarnation == 0 && record != NULL && record->available) {
            owner->puppet_animation_incarnation = record->incarnation;
            owner->puppet_animation_delivered_sequence = record->snapshot.ended_sequence;
        }
        owner->puppet_animation_available = !owner->disabled && record != NULL && record->available &&
            owner->puppet_animation_incarnation == record->incarnation;
        if (record == NULL || owner->puppet_animation_incarnation != record->incarnation)
            clear_pending_events(owner);
        if (owner->puppet_animation_baseline == NULL && owner->puppet_animation_command_count == 0) {
            owner->puppet_animation_visibility = (MWXSceneQuickJSPuppetVisibilityValue){0};
            owner->puppet_animation_visibility_staged = false;
        }
    }
}

static bool publish_stable_layout(MWXSceneQuickJSDomain *domain,
    const MWXSceneQuickJSPuppetAnimationSnapshot *snapshots, size_t count) {
    if (count != domain->puppet_animation_count) return false;
    // A previously unique identity at every unchanged slot proves uniqueness
    // without another pairwise scan. Validate the entire input before writing.
    for (size_t i = 0; i < count; ++i) {
        const MWXSceneQuickJSPuppetAnimationRecord *record = &domain->puppet_animations[i];
        if (record->incarnation == 0 || !valid_snapshot(&snapshots[i]) ||
            !same_identity(snapshot_identity(&record->snapshot), snapshot_identity(&snapshots[i])) ||
            !same_metadata(&record->snapshot, &snapshots[i])) return false;
    }
    for (size_t i = 0; i < count; ++i) {
        const char *name = domain->puppet_animations[i].snapshot.name;
        domain->puppet_animations[i].snapshot = snapshots[i];
        domain->puppet_animations[i].snapshot.name = name;
        domain->puppet_animations[i].available = true;
    }
    refresh_owners(domain, false);
    return true;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_publish_puppet_animations(
    MWXSceneQuickJSDomain *domain, const MWXSceneQuickJSPuppetAnimationSnapshot *snapshots,
    size_t count, char *diagnostic, size_t diagnostic_capacity) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || count > MWX_SCENE_QUICKJS_MAX_LAYERS ||
        (count != 0 && snapshots == NULL)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (domain->puppet_animation_owners == NULL) { clear_catalog(domain); return MWX_SCENE_QUICKJS_OK; }
    if (publish_stable_layout(domain, snapshots, count)) return MWX_SCENE_QUICKJS_OK;
    MWXSceneQuickJSPuppetAnimationRecord *records = calloc(count ? count : 1, sizeof(*records));
    char **new_names = calloc(count ? count : 1, sizeof(*new_names));
    bool *reused_names = calloc(domain->puppet_animation_count ? domain->puppet_animation_count : 1, sizeof(*reused_names));
    if (records == NULL || new_names == NULL || reused_names == NULL) {
        free(records); free(new_names); free(reused_names);
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    uint64_t issuer = domain->puppet_animation_incarnation_issuer;
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    for (size_t i = 0; i < count; ++i) {
        const MWXSceneQuickJSPuppetAnimationSnapshot *snapshot = &snapshots[i];
        MWXSceneQuickJSPuppetAnimationIdentity identity = snapshot_identity(snapshot);
        records[i].snapshot.layer_id = identity.layer_id;
        records[i].snapshot.animation_layer_index = identity.animation_layer_index;
        records[i].snapshot.animation_layer_id = identity.animation_layer_id;
        records[i].snapshot.has_animation_layer_id = identity.has_animation_layer_id;
        bool unique = true, first = true;
        for (size_t j = 0; j < count; ++j)
            if (i != j && same_identity(identity, snapshot_identity(&snapshots[j]))) {
                unique = false;
                if (j < i) first = false;
            }
        // Duplicate input identities are all unavailable. Only their canonical
        // first slot may retain the old allocation and incarnation for recovery.
        if (!first) continue;
        MWXSceneQuickJSPuppetAnimationRecord *old = record_for_identity(domain, identity);
        if (old != NULL && old->incarnation != 0) {
            records[i].snapshot = old->snapshot;
            records[i].incarnation = old->incarnation;
            records[i].event_published_sequence = old->event_published_sequence;
            reused_names[old - domain->puppet_animations] = true;
            // Still present but malformed is transient unavailability, not
            // removal. Keep the proven metadata and allow its valid restoration.
            if (!unique || !valid_snapshot(snapshot) || !same_metadata(&old->snapshot, snapshot)) continue;
            records[i].snapshot = *snapshot;
            records[i].snapshot.name = old->snapshot.name;
        } else {
            if (!unique || !valid_snapshot(snapshot)) continue;
            if (issuer == UINT64_MAX) { result = MWX_SCENE_QUICKJS_INVALID_ARGUMENT; break; }
            new_names[i] = malloc(strlen(snapshot->name) + 1);
            if (new_names[i] == NULL) { result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; break; }
            strcpy(new_names[i], snapshot->name);
            records[i].snapshot = *snapshot;
            records[i].snapshot.name = new_names[i];
            records[i].incarnation = ++issuer;
        }
        records[i].available = true;
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        for (size_t i = 0; i < domain->puppet_animation_count; ++i)
            if (!reused_names[i]) free((char *)domain->puppet_animations[i].snapshot.name);
        free(domain->puppet_animations);
        domain->puppet_animations = records;
        domain->puppet_animation_count = count;
        domain->puppet_animation_incarnation_issuer = issuer;
        refresh_owners(domain, true);
    } else {
        for (size_t i = 0; i < count; ++i) free(new_names[i]);
        free(records);
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "Puppet animation catalog publication failed");
    }
    free(new_names); free(reused_names);
    return result;
}

size_t mwx_scene_quickjs_owner_puppet_animation_command_count(const MWXSceneQuickJSOwner *owner) {
    return owner == NULL ? 0 : owner->puppet_animation_command_overflow ?
        MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_COMMANDS + 1 :
        owner->puppet_animation_command_count - owner->puppet_animation_command_read_start;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_puppet_animation_command_at(
    const MWXSceneQuickJSOwner *owner, size_t index, MWXSceneQuickJSPuppetAnimationCommand *command,
    char *diagnostic, size_t diagnostic_capacity) {
    if (owner == NULL || command == NULL || index >=
        owner->puppet_animation_command_count - owner->puppet_animation_command_read_start)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (owner->puppet_animation_command_overflow) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "Puppet animation command budget exceeded");
        return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
    }
    *command = owner->puppet_animation_commands[owner->puppet_animation_command_read_start + index];
    return MWX_SCENE_QUICKJS_OK;
}

bool mwx_scene_quickjs_owner_has_pending_puppet_animation_end(const MWXSceneQuickJSOwner *owner) {
    MWXSceneQuickJSPuppetAnimationRecord *record = source_record((MWXSceneQuickJSOwner *)owner);
    return record != NULL && owner->puppet_animation_callback_count != 0 &&
        (record->snapshot.ended_failure || record->snapshot.ended_sequence > owner->puppet_animation_delivered_sequence);
}

MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_puppet_animation_end(
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json, size_t script_properties_length,
    const char *user_properties_json, size_t user_properties_length,
    char *diagnostic, size_t diagnostic_capacity) {
    if (!mwx_scene_quickjs_owner_has_pending_puppet_animation_end(owner)) return MWX_SCENE_QUICKJS_OK;
    const MWXSceneQuickJSPuppetAnimationSnapshot *snapshot = &source_record(owner)->snapshot;
    if (snapshot->ended_failure) {
        owner->puppet_animation_delivered_sequence = snapshot->ended_sequence;
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "Puppet natural-ended callback profile is unsupported");
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    owner->puppet_animation_delivered_sequence = snapshot->ended_sequence;
    if (!puppet_transaction(owner)) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    mwx_scene_quickjs_begin_callback(owner);
    JSValue previous_layer = JS_UNDEFINED, previous_scene = JS_UNDEFINED, previous_object = JS_UNDEFINED, previous_engine = JS_UNDEFINED;
    bool properties = mwx_scene_quickjs_assign_script_properties(owner, script_properties_json, script_properties_length);
    bool handles = properties && mwx_scene_quickjs_bind_owner_handles(owner, &previous_layer, &previous_scene, &previous_object);
    bool engine = handles && mwx_scene_quickjs_bind_frame_engine_host(owner, frame, user_properties_json, user_properties_length, &previous_engine);
    MWXSceneQuickJSResult result = engine ? MWX_SCENE_QUICKJS_OK : MWX_SCENE_QUICKJS_EXCEPTION;
    size_t count = owner->puppet_animation_callback_count;
    for (size_t i = 0; result == MWX_SCENE_QUICKJS_OK && i < count; i++) {
        JSValue value = JS_Call(owner->domain->context, owner->puppet_animation_callbacks[i], JS_UNDEFINED, 0, NULL);
        if (JS_IsException(value)) result = mwx_scene_quickjs_exception_result(owner->domain, diagnostic, diagnostic_capacity);
        JS_FreeValue(owner->domain->context, value);
        if (result == MWX_SCENE_QUICKJS_OK) result = mwx_scene_quickjs_drain_jobs(owner, diagnostic, diagnostic_capacity);
    }
    if (engine && !mwx_scene_quickjs_restore_frame_engine_host(owner, previous_engine)) result = MWX_SCENE_QUICKJS_EXCEPTION;
    if (handles && !mwx_scene_quickjs_restore_owner_handles(owner, previous_layer, previous_scene, previous_object)) result = MWX_SCENE_QUICKJS_EXCEPTION;
    mwx_scene_quickjs_end_callback(owner);
    return result;
}

void mwx_scene_quickjs_prepare_puppet_animation_visibility(MWXSceneQuickJSOwner *owner, double *output) {
    MWXSceneQuickJSPuppetAnimationRecord *record = source_record(owner);
    if (record == NULL) return;
    if (owner->puppet_animation_visibility_staged)
        *output = current_state(owner, record).visible ? 1 : 0;
    if (!puppet_transaction(owner)) { owner->puppet_animation_command_overflow = true; return; }
    owner->puppet_animation_visibility = (MWXSceneQuickJSPuppetVisibilityValue){
        true, *output != 0, owner->puppet_animation_command_count };
    owner->puppet_animation_visibility_staged = false;
}

MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_puppet_animation_events(
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSFrameInput *frame,
    const char *properties, size_t properties_length, const char *users, size_t users_length,
    double *value, char *diagnostic, size_t diagnostic_capacity) {
    if (!mwx_scene_quickjs_owner_has_pending_puppet_animation_events(owner)) return MWX_SCENE_QUICKJS_OK;
    if (owner->puppet_event_failure) {
        const char *reasons[] = { "", "unsupportedMode", "invalidEvent", "nonFinitePhase",
            "multipleLoopsCrossed", "eventBudgetExceeded", "sequenceOverflow", "invalidEvent", "event allocation failed" };
        uint32_t code = owner->puppet_event_failure;
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity,
            code < sizeof(reasons) / sizeof(reasons[0]) ? reasons[code] : "invalid event failure");
        return code == 5 ? MWX_SCENE_QUICKJS_MUTATION_OVERFLOW :
            code == 8 ? MWX_SCENE_QUICKJS_MEMORY_EXCEEDED : MWX_SCENE_QUICKJS_DISABLED;
    }
    if (source_record(owner) == NULL) {
        if (resolve_source(owner, false) != NULL) return MWX_SCENE_QUICKJS_OK;
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "Puppet event receiver is temporarily unavailable");
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (!puppet_transaction(owner)) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    JSContext *context = owner->domain->context;
    JSValue function = JS_GetPropertyStr(context, owner->module, "animationEvent");
    if (!JS_IsFunction(context, function)) {
        JS_FreeValue(context, function);
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "animationEvent must be a function");
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    mwx_scene_quickjs_begin_callback(owner);
    JSValue layer = JS_UNDEFINED, scene = JS_UNDEFINED, object = JS_UNDEFINED, engine = JS_UNDEFINED;
    bool assigned = mwx_scene_quickjs_assign_script_properties(owner, properties, properties_length);
    bool handles = assigned && mwx_scene_quickjs_bind_owner_handles(owner, &layer, &scene, &object);
    bool bound = handles && mwx_scene_quickjs_bind_frame_engine_host(owner, frame, users, users_length, &engine);
    MWXSceneQuickJSResult result = bound ? MWX_SCENE_QUICKJS_OK : MWX_SCENE_QUICKJS_EXCEPTION;
    while (result == MWX_SCENE_QUICKJS_OK && owner->puppet_event_cursor < owner->puppet_event_count) {
        const MWXSceneQuickJSPuppetPendingEvent *pending = &owner->puppet_events[owner->puppet_event_cursor];
        MWXSceneQuickJSPuppetAnimationRecord *record = record_for_identity(owner->domain, pending->identity);
        if (record == NULL || record->incarnation != pending->incarnation) {
            owner->puppet_event_cursor++; continue;
        }
        JSValue event = JS_NewObject(context);
        JSValue name = JS_IsException(event) ? JS_EXCEPTION : JS_NewString(context, pending->name);
        if (JS_IsException(event) || JS_IsException(name)) {
            JS_FreeValue(context, name); JS_FreeValue(context, event);
            (void)mwx_scene_quickjs_exception_result(owner->domain, diagnostic, diagnostic_capacity);
            result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
            break;
        }
        bool created =
            JS_DefinePropertyValueStr(context, event, "name", name, JS_PROP_C_W_E) >= 0 &&
            JS_DefinePropertyValueStr(context, event, "frame", JS_NewFloat64(context, (double)pending->frame), JS_PROP_C_W_E) >= 0;
        if (!created) { JS_FreeValue(context, event); result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; break; }
        JSValue arguments[] = { event, JS_NewBool(context, *value != 0) };
        JSValue returned = JS_Call(context, function, owner->module, 2, arguments);
        JS_FreeValue(context, event); JS_FreeValue(context, arguments[1]);
        if (JS_IsException(returned)) result = mwx_scene_quickjs_exception_result(owner->domain, diagnostic, diagnostic_capacity);
        else if (JS_IsBool(returned)) *value = JS_ToBool(context, returned);
        else if (!JS_IsUndefined(returned)) {
            mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "animationEvent expects Boolean or undefined return");
            result = MWX_SCENE_QUICKJS_BAD_RETURN;
        }
        JS_FreeValue(context, returned);
        if (result == MWX_SCENE_QUICKJS_OK) result = mwx_scene_quickjs_drain_jobs(owner, diagnostic, diagnostic_capacity);
        if (result == MWX_SCENE_QUICKJS_OK) {
            owner->puppet_event_cursor++;
            mwx_scene_quickjs_prepare_puppet_animation_visibility(owner, value);
        }
    }
    if (bound && !mwx_scene_quickjs_restore_frame_engine_host(owner, engine)) result = MWX_SCENE_QUICKJS_EXCEPTION;
    if (handles && !mwx_scene_quickjs_restore_owner_handles(owner, layer, scene, object)) result = MWX_SCENE_QUICKJS_EXCEPTION;
    mwx_scene_quickjs_end_callback(owner);
    JS_FreeValue(context, function);
    return result;
}

void mwx_scene_quickjs_puppet_animation_finish_transaction(MWXSceneQuickJSOwner *owner, bool commit) {
    MWXSceneQuickJSPuppetAnimationRecord *record = source_record(owner);
    bool visible = record != NULL && current_state(owner, record).visible;
    if (owner->puppet_animation_baseline != NULL) {
        if (!commit) mwx_scene_quickjs_owner_timer_restore(owner, owner->puppet_animation_baseline);
        mwx_scene_quickjs_owner_timer_snapshot_destroy(owner->puppet_animation_baseline, owner);
        owner->puppet_animation_baseline = NULL;
    }
    if (commit && record != NULL)
        owner->puppet_animation_visibility = (MWXSceneQuickJSPuppetVisibilityValue){ true, visible, 0 };
    if (commit && owner->puppet_event_cursor != 0) {
        size_t consumed = owner->puppet_event_cursor;
        for (size_t i = 0; i < consumed; ++i) js_free_rt(owner->domain->runtime, owner->puppet_events[i].name);
        owner->puppet_event_count -= consumed;
        memmove(owner->puppet_events, owner->puppet_events + consumed,
            owner->puppet_event_count * sizeof(*owner->puppet_events));
        owner->puppet_event_cursor = 0;
        if (owner->puppet_event_queue_epoch != UINT64_MAX) owner->puppet_event_queue_epoch++;
    }
    owner->puppet_animation_command_count = 0;
    owner->puppet_animation_command_read_start = 0;
    owner->puppet_animation_registration_count = 0;
    owner->puppet_animation_command_overflow = false;
    owner->puppet_animation_visibility.journal_cutoff = 0;
    owner->puppet_animation_visibility_staged = false;
}

void mwx_scene_quickjs_destroy_puppet_animation_host(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return;
    clear_pending_events(owner);
    MWXSceneQuickJSOwner **cursor = &owner->domain->puppet_animation_owners;
    while (*cursor != NULL && *cursor != owner) cursor = &(*cursor)->puppet_animation_next;
    if (*cursor == owner) *cursor = owner->puppet_animation_next;
    for (size_t i = 0; i < owner->puppet_animation_callback_count; i++)
        JS_FreeValue(owner->domain->context, owner->puppet_animation_callbacks[i]);
    owner->puppet_animation_callback_count = 0;
    owner->puppet_animation_configured = false;
    owner->puppet_animation_available = false;
    if (owner->domain->puppet_animation_owners == NULL) clear_catalog(owner->domain);
}

size_t mwx_scene_quickjs_domain_puppet_animation_owner_count(const MWXSceneQuickJSDomain *domain) {
    size_t count = 0;
    if (domain != NULL) for (const MWXSceneQuickJSOwner *owner = domain->puppet_animation_owners; owner; owner = owner->puppet_animation_next) count++;
    return count;
}

size_t mwx_scene_quickjs_owner_puppet_animation_registration_count(const MWXSceneQuickJSOwner *owner) {
    return owner == NULL ? 0 : owner->puppet_animation_registration_count;
}
