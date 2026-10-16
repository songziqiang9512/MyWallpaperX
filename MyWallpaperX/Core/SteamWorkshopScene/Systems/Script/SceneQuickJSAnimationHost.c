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
    uint32_t layer_index;
    int64_t layer_id;
    bool named_lookup;
    bool current_property;
} MWXSceneQuickJSAnimationHandle;

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
    free(opaque);
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
    return JS_NewCClosure(
        owner->domain->context, function, name,
        free_animation_handle, 0, 0, handle
    );
}

static bool named_animation_layer_alive(
    MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSNamedAnimationRecord *animation
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (animation->layer_index >= domain->authored_layer_count) return false;
    const MWXSceneQuickJSLayerRecord *layer = &domain->layers[animation->layer_index];
    const MWXSceneQuickJSAuthoredLayerMutationRecord *pending =
        mwx_scene_quickjs_authored_mutation_for_layer(owner, animation->layer_index);
    return layer->configured && !layer->dynamic && !layer->destroyed &&
        layer->layer_id == animation->layer_id && (pending == NULL || !pending->destroyed);
}

static JSValue mutate_animation(
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
    MWXSceneQuickJSOwner *owner = animation_handle_owner(handle);
    bool available = owner != NULL;
    if (available && handle->target_index == UINT32_MAX) {
        available = owner->current_animation_available;
    } else if (available) {
        MWXSceneQuickJSDomain *domain = owner->domain;
        available = !owner->value_only &&
            handle->catalog_index < domain->named_animation_count &&
            domain->named_animations[handle->catalog_index].target_index == handle->target_index &&
            named_animation_layer_alive(owner, &domain->named_animations[handle->catalog_index]);
    }
    if (argc != 0 || !available) {
        return JS_ThrowTypeError(context, "animation handle is stale");
    }
    if (owner->animation_command_count >= MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS) {
        owner->animation_command_overflow = true;
        return JS_ThrowInternalError(context, "animation command buffer exceeded");
    }
    owner->animation_commands[owner->animation_command_count] =
        (MWXSceneQuickJSAnimationCommandRecord){handle->command, handle->target_index};
    owner->animation_command_count += 1;
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
            return JS_ThrowTypeError(context, "layer getAnimation expects one name");
        }
        if (!owner->current_animation_available) {
            return JS_ThrowRangeError(context, "current property animation does not exist");
        }
    } else {
        if (argc != 1 || !handle->named_lookup || !JS_IsString(argv[0])) {
            return JS_ThrowTypeError(context, "named animation lookup expects one layer name");
        }
        MWXSceneQuickJSDomain *domain = owner->domain;
        uint32_t layer_index = handle->layer_index;
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
            if (candidate->layer_index == layer_index && candidate->name_length == length &&
                memcmp(candidate->name, name, length) == 0 &&
                named_animation_layer_alive(owner, candidate)) {
                target.target_index = candidate->target_index;
                target.catalog_index = (uint32_t)i;
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
    const MWXSceneQuickJSAnimationHandle target = {.current_property = true};
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
        .named_lookup = true,
        .current_property = current_property,
    };
    JSValue animation = animation_closure(owner, get_animation, "getAnimation", 0, &target);
    if (JS_IsException(animation)) return false;
    return JS_DefinePropertyValueStr(
        context, layer, "getAnimation", animation, JS_PROP_ENUMERABLE | JS_PROP_CONFIGURABLE
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
    if (owner == NULL || command == NULL || target_index == NULL ||
        index >= owner->animation_command_count) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid animation command mutation"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *command = owner->animation_commands[index].command;
    *target_index = owner->animation_commands[index].target_index;
    return MWX_SCENE_QUICKJS_OK;
}
