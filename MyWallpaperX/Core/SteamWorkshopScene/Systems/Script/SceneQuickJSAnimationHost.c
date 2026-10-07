#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct MWXSceneQuickJSAnimationHandle {
    MWXSceneQuickJSOwner *owner;
    uint64_t callback_epoch;
    MWXSceneQuickJSAnimationCommand command;
} MWXSceneQuickJSAnimationHandle;

static bool callback_owns_animation(
    const MWXSceneQuickJSAnimationHandle *handle
) {
    return handle != NULL && handle->owner != NULL &&
        handle->owner->domain != NULL &&
        handle->owner->domain->callback_active &&
        handle->owner->domain->active_owner == handle->owner &&
        handle->owner->domain->callback_epoch == handle->callback_epoch;
}

static void free_animation_handle(void *opaque) {
    free(opaque);
}

static JSValue mutate_current_animation(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)argv;
    (void)magic;
    MWXSceneQuickJSAnimationHandle *handle = opaque;
    if (argc != 0 || !callback_owns_animation(handle)) {
        return JS_ThrowTypeError(context, "animation handle is stale");
    }
    MWXSceneQuickJSOwner *owner = handle->owner;
    if (owner->animation_command_count >= MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS) {
        owner->animation_command_overflow = true;
        return JS_ThrowInternalError(context, "animation command buffer exceeded");
    }
    owner->animation_commands[owner->animation_command_count] = handle->command;
    owner->animation_command_count += 1;
    return JS_UNDEFINED;
}

static bool define_animation_command(
    JSContext *context,
    JSValue animation,
    MWXSceneQuickJSOwner *owner,
    const char *name,
    MWXSceneQuickJSAnimationCommand command
) {
    MWXSceneQuickJSAnimationHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return false;
    handle->owner = owner;
    handle->callback_epoch = owner->domain->callback_epoch;
    handle->command = command;
    JSValue callback = JS_NewCClosure(
        context, mutate_current_animation, name,
        free_animation_handle, 0, 0, handle
    );
    if (JS_IsException(callback) ||
        JS_DefinePropertyValueStr(
            context, animation, name, callback, JS_PROP_ENUMERABLE
        ) < 0) {
        return false;
    }
    return true;
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
    (void)argv;
    (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (owner == NULL || owner->domain == NULL ||
        !owner->domain->callback_active || owner->domain->active_owner != owner) {
        return JS_ThrowTypeError(context, "getAnimation host is unavailable");
    }
    if (argc != 0) {
        return JS_ThrowTypeError(context, "named animation lookup is unsupported");
    }
    if (!owner->current_animation_available) {
        return JS_ThrowRangeError(context, "current property animation does not exist");
    }
    JSValue animation = JS_NewObject(context);
    if (JS_IsException(animation)) return animation;
    if (!define_animation_command(
            context, animation, owner, "play", MWX_SCENE_QUICKJS_ANIMATION_PLAY
        ) ||
        !define_animation_command(
            context, animation, owner, "pause", MWX_SCENE_QUICKJS_ANIMATION_PAUSE
        ) ||
        !define_animation_command(
            context, animation, owner, "stop", MWX_SCENE_QUICKJS_ANIMATION_STOP
        )) {
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
    JSValue animation = JS_NewCClosure(
        context, get_animation, "getAnimation", NULL, 0, 0, owner
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
    JSContext *context = owner->domain->context;
    JSValue animation = JS_NewCClosure(
        context, get_animation, "getAnimation", NULL, 0, 0, owner
    );
    if (JS_IsException(animation)) return false;
    return JS_DefinePropertyValueStr(
        context, owner->material_function_layer, "getAnimation",
        animation, JS_PROP_ENUMERABLE
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_current_animation(
    MWXSceneQuickJSOwner *owner,
    uint32_t available,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || available != 1 || owner->current_animation_available) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid current animation configuration"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    owner->current_animation_available = true;
    return MWX_SCENE_QUICKJS_OK;
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
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || command == NULL || index >= owner->animation_command_count) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid animation command mutation"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *command = owner->animation_commands[index];
    return MWX_SCENE_QUICKJS_OK;
}

// Puppet layers carry their prepared identity and a host-published mirror.
// Closures may survive callbacks; no closure stores a potentially freed owner.
#include <float.h>

typedef struct PuppetAnimationHandle {
    MWXSceneQuickJSDomain *domain;
    uint64_t owner_identity, generation;
    int operation;
} PuppetAnimationHandle;

static MWXSceneQuickJSOwner *puppet_handle_owner(PuppetAnimationHandle *handle) {
    if (handle == NULL || handle->domain == NULL) return NULL;
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    if (!handle->domain->callback_active || owner == NULL || owner->disabled ||
        owner->identity != handle->owner_identity || owner->generation != handle->generation ||
        !owner->puppet_animation_available) return NULL;
    return owner;
}

static bool puppet_transaction(MWXSceneQuickJSOwner *owner) {
    if (owner->puppet_animation_baseline != NULL) return true;
    owner->puppet_animation_baseline = mwx_scene_quickjs_owner_timer_snapshot(owner);
    return owner->puppet_animation_baseline != NULL;
}

static bool puppet_command(MWXSceneQuickJSOwner *owner, uint32_t action, double value) {
    if (owner->puppet_animation_command_count >= MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_COMMANDS) {
        owner->puppet_animation_command_overflow = true;
        return false;
    }
    if (!puppet_transaction(owner)) return false;
    MWXSceneQuickJSPuppetAnimationSnapshot *state = &owner->puppet_animation_overlay;
    uint32_t ordinal = 0;
    for (size_t i = owner->puppet_animation_command_count; i > 0; --i) {
        if (owner->puppet_animation_commands[i - 1].callback_epoch != owner->domain->callback_epoch) break;
        ordinal++;
    }
    owner->puppet_animation_commands[owner->puppet_animation_command_count++] =
        (MWXSceneQuickJSPuppetAnimationCommand) {
            .layer_id = state->layer_id, .animation_layer_index = state->animation_layer_index,
            .animation_layer_id = state->animation_layer_id,
            .has_animation_layer_id = state->has_animation_layer_id,
            .action = action, .value = value,
            .callback_epoch = owner->domain->callback_epoch, .ordinal = ordinal
        };
    switch (action) {
    case 0: state->is_playing = 1; break;
    case 1: state->is_playing = 0; break;
    case 2: state->is_playing = 0; state->current_frame = 0; break;
    case 3: state->current_frame = (float)value; break;
    case 4: state->rate = (float)value; break;
    case 5: state->blend = (float)value; break;
    case 6: state->visible = value != 0; owner->puppet_animation_visibility_staged = true; break;
    }
    return true;
}

static JSValue puppet_animation_call(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv, int magic, void *opaque) {
    (void)this_value; (void)magic;
    PuppetAnimationHandle *handle = opaque;
    MWXSceneQuickJSOwner *owner = puppet_handle_owner(handle);
    if (owner == NULL) return JS_ThrowTypeError(context, "Puppet animation owner is unavailable or stale");
    MWXSceneQuickJSPuppetAnimationSnapshot *state = &owner->puppet_animation_overlay;
    int operation = handle->operation;
    if (operation <= 6) {
        double value = 0;
        if (operation <= 2 ? argc != 0 : argc != 1)
            return JS_ThrowTypeError(context, "invalid Puppet animation command argument");
        if (operation == 6) {
            if (!JS_IsBool(argv[0])) return JS_ThrowTypeError(context, "animation visible expects Boolean");
            value = JS_ToBool(context, argv[0]);
        } else if (operation >= 3 && (!JS_IsNumber(argv[0]) ||
            JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value) || fabs(value) > FLT_MAX)) {
            return JS_ThrowTypeError(context, "animation command expects a finite Float");
        }
        if (!puppet_command(owner, (uint32_t)operation, value))
            return JS_ThrowRangeError(context, "Puppet animation command or snapshot budget exceeded");
        return JS_UNDEFINED;
    }
    if (operation == 16) {
        if (argc != 1 || !JS_IsFunction(context, argv[0]))
            return JS_ThrowTypeError(context, "addEndedCallback expects one function");
        if (!state->supports_ended_callbacks || state->ended_failure)
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
    case 7: return JS_NewFloat64(context, state->current_frame);
    case 8: return JS_NewBool(context, state->is_playing);
    case 9: return JS_NewFloat64(context, state->fps);
    case 10: return JS_NewFloat64(context, state->frame_count);
    case 11: return JS_NewFloat64(context, state->duration);
    case 12: return JS_NewString(context, owner->puppet_animation_name);
    case 13: return JS_NewFloat64(context, state->rate);
    case 14: return JS_NewFloat64(context, state->blend);
    case 15: return JS_NewBool(context, state->visible);
    }
    return JS_ThrowTypeError(context, "unknown Puppet animation operation");
}

static JSValue puppet_function(MWXSceneQuickJSOwner *owner, const char *name, int operation) {
    PuppetAnimationHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return JS_ThrowOutOfMemory(owner->domain->context);
    *handle = (PuppetAnimationHandle){ owner->domain, owner->identity, owner->generation, operation };
    return JS_NewCClosure(owner->domain->context, puppet_animation_call, name,
        free_animation_handle, 0, 0, handle);
}

JSValue mwx_scene_quickjs_puppet_animation_handle(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    if (!owner->puppet_animation_available)
        return JS_ThrowTypeError(context, "prepared Puppet animation metadata is unavailable");
    JSValue object = JS_NewObject(context);
    if (JS_IsException(object)) return object;
    const char *methods[] = { "play", "pause", "stop", "setFrame", "getFrame", "isPlaying", "addEndedCallback" };
    const int operations[] = { 0, 1, 2, 3, 7, 8, 16 };
    for (size_t i = 0; i < sizeof(operations) / sizeof(operations[0]); ++i) {
        JSValue function = puppet_function(owner, methods[i], operations[i]);
        if (JS_IsException(function) || JS_DefinePropertyValueStr(context, object,
            methods[i], function, JS_PROP_ENUMERABLE) < 0) goto fail;
    }
    const char *properties[] = { "fps", "frameCount", "duration", "name", "rate", "blend", "visible" };
    for (size_t i = 0; i < sizeof(properties) / sizeof(properties[0]); ++i) {
        JSAtom atom = JS_NewAtom(context, properties[i]);
        if (atom == JS_ATOM_NULL) goto fail;
        JSValue getter = puppet_function(owner, properties[i], 9 + (int)i);
        JSValue setter = i >= 4 ? puppet_function(owner, properties[i], (int)i) : JS_UNDEFINED;
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

static bool same_puppet_identity(const MWXSceneQuickJSPuppetAnimationSnapshot *a,
    const MWXSceneQuickJSPuppetAnimationSnapshot *b) {
    return a->layer_id == b->layer_id && a->animation_layer_index == b->animation_layer_index &&
        a->has_animation_layer_id == b->has_animation_layer_id &&
        (!a->has_animation_layer_id || a->animation_layer_id == b->animation_layer_id);
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
    owner->puppet_animation_committed = (MWXSceneQuickJSPuppetAnimationSnapshot){
        .layer_id = layer_id, .animation_layer_index = authored_index,
        .animation_layer_id = animation_layer_id, .has_animation_layer_id = has_animation_layer_id };
    owner->puppet_animation_configured = true;
    owner->puppet_animation_next = owner->domain->puppet_animation_owners;
    owner->domain->puppet_animation_owners = owner;
    return MWX_SCENE_QUICKJS_OK;
}

static bool valid_puppet_snapshot(const MWXSceneQuickJSPuppetAnimationSnapshot *s) {
    return s->layer_id >= 0 && s->has_animation_layer_id <= 1 &&
        s->name != NULL && strlen(s->name) <= 1024 &&
        isfinite(s->fps) && s->fps > 0 && isfinite(s->frame_count) && s->frame_count >= 0 &&
        isfinite(s->duration) && s->duration >= 0 && isfinite(s->current_frame) &&
        fabs(s->current_frame) <= FLT_MAX && isfinite(s->rate) && fabs(s->rate) <= FLT_MAX &&
        isfinite(s->blend) && fabs(s->blend) <= FLT_MAX &&
        s->is_playing <= 1 && s->visible <= 1 && s->supports_ended_callbacks <= 1;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_publish_puppet_animations(
    MWXSceneQuickJSDomain *domain, const MWXSceneQuickJSPuppetAnimationSnapshot *snapshots,
    size_t count, char *diagnostic, size_t diagnostic_capacity) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || count > MWX_SCENE_QUICKJS_MAX_LAYERS ||
        (count != 0 && snapshots == NULL)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    size_t owner_count = 0;
    for (MWXSceneQuickJSOwner *owner = domain->puppet_animation_owners; owner; owner = owner->puppet_animation_next) owner_count++;
    if (owner_count == 0) return MWX_SCENE_QUICKJS_OK;
    typedef struct Pending { MWXSceneQuickJSOwner *owner; const MWXSceneQuickJSPuppetAnimationSnapshot *snapshot; char *name; } Pending;
    Pending *pending = calloc(owner_count ? owner_count : 1, sizeof(*pending));
    if (pending == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    size_t index = 0;
    for (MWXSceneQuickJSOwner *owner = domain->puppet_animation_owners; owner; owner = owner->puppet_animation_next, index++) {
        pending[index].owner = owner;
        if (owner->disabled) continue;
        for (size_t i = 0; i < count; i++) {
            if (!same_puppet_identity(&owner->puppet_animation_committed, &snapshots[i])) continue;
            if (pending[index].snapshot != NULL || !valid_puppet_snapshot(&snapshots[i])) { pending[index].snapshot = NULL; break; }
            pending[index].snapshot = &snapshots[i];
        }
        const MWXSceneQuickJSPuppetAnimationSnapshot *next = pending[index].snapshot;
        if (next == NULL) continue;
        if (owner->puppet_animation_name != NULL) {
            const MWXSceneQuickJSPuppetAnimationSnapshot *old = &owner->puppet_animation_committed;
            if (next->animation_id != old->animation_id || next->fps != old->fps ||
                next->frame_count != old->frame_count || next->duration != old->duration ||
                strcmp(next->name, owner->puppet_animation_name) != 0 ||
                next->ended_sequence < old->ended_sequence) { pending[index].snapshot = NULL; continue; }
        } else {
            pending[index].name = malloc(strlen(next->name) + 1);
            if (pending[index].name == NULL) { result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; break; }
            strcpy(pending[index].name, next->name);
        }
    }
    if (result == MWX_SCENE_QUICKJS_OK) for (size_t i = 0; i < owner_count; i++) {
        MWXSceneQuickJSOwner *owner = pending[i].owner;
        if (pending[i].snapshot == NULL) { owner->puppet_animation_available = false; continue; }
        if (pending[i].name != NULL) {
            owner->puppet_animation_name = pending[i].name; pending[i].name = NULL;
            owner->puppet_animation_delivered_sequence = pending[i].snapshot->ended_sequence;
        }
        owner->puppet_animation_committed = *pending[i].snapshot;
        owner->puppet_animation_committed.name = owner->puppet_animation_name;
        owner->puppet_animation_overlay = owner->puppet_animation_committed;
        owner->puppet_animation_available = true;
    }
    for (size_t i = 0; i < owner_count; i++) free(pending[i].name);
    free(pending);
    if (result != MWX_SCENE_QUICKJS_OK)
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "prepared Puppet animation snapshot identity or metadata changed");
    return result;
}

size_t mwx_scene_quickjs_owner_puppet_animation_command_count(const MWXSceneQuickJSOwner *owner) {
    return owner == NULL ? 0 : owner->puppet_animation_command_overflow ?
        MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_COMMANDS + 1 : owner->puppet_animation_command_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_puppet_animation_command_at(
    const MWXSceneQuickJSOwner *owner, size_t index, MWXSceneQuickJSPuppetAnimationCommand *command,
    char *diagnostic, size_t diagnostic_capacity) {
    if (owner == NULL || command == NULL || index >= owner->puppet_animation_command_count)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (owner->puppet_animation_command_overflow) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "Puppet animation command budget exceeded");
        return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
    }
    *command = owner->puppet_animation_commands[index];
    return MWX_SCENE_QUICKJS_OK;
}

bool mwx_scene_quickjs_owner_has_pending_puppet_animation_end(const MWXSceneQuickJSOwner *owner) {
    return owner != NULL && !owner->disabled && owner->puppet_animation_available && owner->puppet_animation_callback_count != 0 &&
        (owner->puppet_animation_committed.ended_failure ||
         owner->puppet_animation_committed.ended_sequence > owner->puppet_animation_delivered_sequence);
}

MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_puppet_animation_end(
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json, size_t script_properties_length,
    const char *user_properties_json, size_t user_properties_length,
    char *diagnostic, size_t diagnostic_capacity) {
    if (!mwx_scene_quickjs_owner_has_pending_puppet_animation_end(owner)) return MWX_SCENE_QUICKJS_OK;
    if (owner->puppet_animation_committed.ended_failure) {
        owner->puppet_animation_delivered_sequence = owner->puppet_animation_committed.ended_sequence;
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "Puppet natural-ended callback profile is unsupported");
        // This latched playback-profile failure cannot recover on a later callback.
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    owner->puppet_animation_delivered_sequence = owner->puppet_animation_committed.ended_sequence;
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
    if (result == MWX_SCENE_QUICKJS_OK) owner->puppet_animation_delivered_sequence = owner->puppet_animation_committed.ended_sequence;
    return result;
}

void mwx_scene_quickjs_prepare_puppet_animation_visibility(MWXSceneQuickJSOwner *owner, double *output) {
    if (!owner->puppet_animation_available) return;
    if (owner->puppet_animation_visibility_staged) *output = owner->puppet_animation_overlay.visible ? 1 : 0;
    if (!puppet_transaction(owner)) { owner->puppet_animation_command_overflow = true; return; }
    owner->puppet_animation_overlay.visible = *output != 0;
    owner->puppet_animation_visibility_staged = false;
}

void mwx_scene_quickjs_puppet_animation_finish_transaction(MWXSceneQuickJSOwner *owner, bool commit) {
    if (owner->puppet_animation_baseline != NULL) {
        if (!commit) mwx_scene_quickjs_owner_timer_restore(owner, owner->puppet_animation_baseline);
        mwx_scene_quickjs_owner_timer_snapshot_destroy(owner->puppet_animation_baseline, owner);
        owner->puppet_animation_baseline = NULL;
    }
    if (commit && owner->puppet_animation_available) owner->puppet_animation_committed = owner->puppet_animation_overlay;
    owner->puppet_animation_command_count = 0;
    owner->puppet_animation_registration_count = 0;
    owner->puppet_animation_command_overflow = false;
    owner->puppet_animation_visibility_staged = false;
}

void mwx_scene_quickjs_destroy_puppet_animation_host(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return;
    MWXSceneQuickJSOwner **cursor = &owner->domain->puppet_animation_owners;
    while (*cursor != NULL && *cursor != owner) cursor = &(*cursor)->puppet_animation_next;
    if (*cursor == owner) *cursor = owner->puppet_animation_next;
    for (size_t i = 0; i < owner->puppet_animation_callback_count; i++)
        JS_FreeValue(owner->domain->context, owner->puppet_animation_callbacks[i]);
    owner->puppet_animation_callback_count = 0;
    free(owner->puppet_animation_name);
    owner->puppet_animation_name = NULL;
    owner->puppet_animation_configured = false;
    owner->puppet_animation_available = false;
}

size_t mwx_scene_quickjs_domain_puppet_animation_owner_count(const MWXSceneQuickJSDomain *domain) {
    size_t count = 0;
    if (domain != NULL) for (const MWXSceneQuickJSOwner *owner = domain->puppet_animation_owners; owner; owner = owner->puppet_animation_next) count++;
    return count;
}

size_t mwx_scene_quickjs_owner_puppet_animation_registration_count(const MWXSceneQuickJSOwner *owner) {
    return owner == NULL ? 0 : owner->puppet_animation_registration_count;
}
