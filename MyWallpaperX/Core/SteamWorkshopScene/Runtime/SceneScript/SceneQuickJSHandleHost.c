#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct MWXSceneQuickJSEffectHandle {
    MWXSceneQuickJSOwner *owner;
    uint32_t effect_index;
    uint64_t callback_epoch;
} MWXSceneQuickJSEffectHandle;

typedef struct MWXSceneQuickJSLayerHandle {
    MWXSceneQuickJSDomain *domain;
    uint32_t layer_index;
    uint64_t callback_epoch;
} MWXSceneQuickJSLayerHandle;

static bool callback_owns_owner(const MWXSceneQuickJSOwner *owner) {
    return owner != NULL && owner->domain != NULL &&
        owner->domain->callback_active && owner->domain->active_owner == owner;
}

static bool callback_owns_epoch(
    const MWXSceneQuickJSDomain *domain,
    uint64_t callback_epoch
) {
    return domain != NULL && domain->callback_active &&
        domain->callback_epoch == callback_epoch;
}

static JSValue execute_material_function(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSEffectHandle *handle = opaque;
    if (handle == NULL || handle->owner == NULL || argc != 1 ||
        !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(context, "executeMaterialFunction expects one string");
    }
    MWXSceneQuickJSOwner *owner = handle->owner;
    if (!callback_owns_owner(owner) ||
        !callback_owns_epoch(owner->domain, handle->callback_epoch)) {
        return JS_ThrowTypeError(context, "effect handle is stale");
    }
    if (owner->material_function_count >=
        MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS) {
        owner->material_function_overflow = true;
        return JS_ThrowInternalError(context, "material function mutation buffer exceeded");
    }
    size_t length = 0;
    const char *name = JS_ToCStringLen(context, &length, argv[0]);
    if (name == NULL || length == 0 ||
        length >= MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME) {
        if (name != NULL) JS_FreeCString(context, name);
        return JS_ThrowTypeError(context, "material function name is invalid");
    }
    MWXSceneQuickJSMaterialFunctionMutationRecord *record =
        &owner->material_functions[owner->material_function_count];
    record->effect_index = handle->effect_index;
    memcpy(record->function_name, name, length);
    record->function_name[length] = '\0';
    owner->material_function_count += 1;
    JS_FreeCString(context, name);
    return JS_UNDEFINED;
}

static void free_effect_handle(void *opaque) {
    free(opaque);
}

static JSValue get_effect(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (!callback_owns_owner(owner) || argc != 1 || owner->effect_names == NULL) {
        return JS_ThrowTypeError(context, "getEffect host is unavailable");
    }
    int64_t index = -1;
    if (JS_IsString(argv[0])) {
        size_t length = 0;
        const char *name = JS_ToCStringLen(context, &length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        for (uint32_t candidate = 0; candidate < owner->effect_count; ++candidate) {
            const char *candidate_name = owner->effect_names[candidate];
            if (candidate_name != NULL && strlen(candidate_name) == length &&
                memcmp(candidate_name, name, length) == 0) {
                index = candidate;
                break;
            }
        }
        JS_FreeCString(context, name);
    } else if (JS_IsNumber(argv[0])) {
        double numeric_index = -1;
        if (JS_ToFloat64(context, &numeric_index, argv[0]) < 0 ||
            !isfinite(numeric_index) || floor(numeric_index) != numeric_index ||
            numeric_index < 0 || numeric_index > UINT32_MAX) {
            return JS_ThrowRangeError(context, "getEffect index is invalid");
        }
        index = (int64_t)numeric_index;
    } else {
        return JS_ThrowTypeError(context, "getEffect expects one name or index");
    }
    if (index < 0 || index >= owner->effect_count) {
        return JS_ThrowRangeError(context, "getEffect target does not exist");
    }
    JSValue effect = JS_NewObject(context);
    if (JS_IsException(effect)) return effect;
    MWXSceneQuickJSEffectHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) {
        JS_FreeValue(context, effect);
        return JS_ThrowInternalError(context, "material effect handle allocation failed");
    }
    handle->owner = owner;
    handle->effect_index = (uint32_t)index;
    handle->callback_epoch = owner->domain->callback_epoch;
    JSValue callback = JS_NewCClosure(
        context, execute_material_function, "executeMaterialFunction",
        free_effect_handle, 1, 0, handle
    );
    if (JS_IsException(callback) ||
        JS_DefinePropertyValueStr(
            context, effect, "executeMaterialFunction", callback, JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, effect);
        return JS_EXCEPTION;
    }
    const char *effect_name = owner->effect_names[index];
    if (effect_name != NULL &&
        JS_DefinePropertyValueStr(
            context, effect, "name", JS_NewString(context, effect_name),
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, effect);
        return JS_EXCEPTION;
    }
    return effect;
}

static JSValue get_effect_count(
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
    MWXSceneQuickJSOwner *owner = opaque;
    if (!callback_owns_owner(owner) || owner->effect_names == NULL) {
        return JS_ThrowTypeError(context, "getEffectCount host is unavailable");
    }
    return JS_NewUint32(context, owner->effect_count);
}

static bool install_effect_handle(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    JSValue layer = JS_NewObject(context);
    if (JS_IsException(layer)) return false;
    JSValue getter = JS_NewCClosure(context, get_effect, "getEffect", NULL, 1, 0, owner);
    JSValue count = JS_NewCClosure(
        context, get_effect_count, "getEffectCount", NULL, 0, 0, owner
    );
    if (JS_IsException(getter) || JS_IsException(count)) {
        JS_FreeValue(context, getter);
        JS_FreeValue(context, count);
        JS_FreeValue(context, layer);
        return false;
    }
    if (JS_DefinePropertyValueStr(
            context, layer, "getEffect", getter, JS_PROP_ENUMERABLE
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, layer, "getEffectCount", count, JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, layer);
        return false;
    }
    owner->material_function_layer = layer;
    return true;
}

bool mwx_scene_quickjs_install_owner_handles(MWXSceneQuickJSOwner *owner) {
    return owner != NULL && install_effect_handle(owner) &&
        mwx_scene_quickjs_install_layer_handles(owner) &&
        mwx_scene_quickjs_install_object_handle(owner);
}

void mwx_scene_quickjs_destroy_owner_handles(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return;
    if (owner->domain != NULL && owner->domain->context != NULL) {
        JS_FreeValue(owner->domain->context, owner->material_function_layer);
        JS_FreeValue(owner->domain->context, owner->scene_handle);
        JS_FreeValue(owner->domain->context, owner->object_handle);
    }
    if (owner->effect_names != NULL) {
        for (uint32_t index = 0; index < owner->effect_count; ++index) {
            free(owner->effect_names[index]);
        }
        free(owner->effect_names);
    }
}

bool mwx_scene_quickjs_bind_owner_handles(
    MWXSceneQuickJSOwner *owner,
    JSValue *previous_layer,
    JSValue *previous_scene,
    JSValue *previous_object
) {
    if (owner == NULL || previous_layer == NULL || previous_scene == NULL ||
        previous_object == NULL ||
        JS_IsUndefined(owner->material_function_layer) ||
        JS_IsUndefined(owner->scene_handle) || JS_IsUndefined(owner->object_handle)) return false;
    JSContext *context = owner->domain->context;
    JSValue global = JS_GetGlobalObject(context);
    *previous_layer = JS_GetPropertyStr(context, global, "thisLayer");
    *previous_scene = JS_GetPropertyStr(context, global, "thisScene");
    *previous_object = JS_GetPropertyStr(context, global, "thisObject");
    if (JS_IsException(*previous_layer) || JS_IsException(*previous_scene) ||
        JS_IsException(*previous_object)) {
        JS_FreeValue(context, *previous_layer);
        JS_FreeValue(context, *previous_scene);
        JS_FreeValue(context, *previous_object);
        JS_FreeValue(context, global);
        return false;
    }
    if (JS_SetPropertyStr(
            context, global, "thisLayer",
            JS_DupValue(context, owner->material_function_layer)
        ) < 0) {
        JS_FreeValue(context, *previous_layer);
        JS_FreeValue(context, *previous_scene);
        JS_FreeValue(context, *previous_object);
        JS_FreeValue(context, global);
        return false;
    }
    if (JS_SetPropertyStr(
            context, global, "thisScene",
            JS_DupValue(context, owner->scene_handle)
        ) < 0) {
        JS_SetPropertyStr(context, global, "thisLayer", *previous_layer);
        JS_FreeValue(context, *previous_scene);
        JS_FreeValue(context, *previous_object);
        JS_FreeValue(context, global);
        return false;
    }
    if (JS_SetPropertyStr(
            context, global, "thisObject",
            JS_DupValue(context, owner->object_handle)
        ) < 0) {
        JS_SetPropertyStr(context, global, "thisLayer", *previous_layer);
        JS_SetPropertyStr(context, global, "thisScene", *previous_scene);
        JS_FreeValue(context, *previous_object);
        JS_FreeValue(context, global);
        return false;
    }
    JS_FreeValue(context, global);
    return true;
}

bool mwx_scene_quickjs_restore_owner_handles(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_layer,
    JSValue previous_scene,
    JSValue previous_object
) {
    if (owner == NULL) return false;
    JSContext *context = owner->domain->context;
    JSValue global = JS_GetGlobalObject(context);
    int layer_result = JS_SetPropertyStr(context, global, "thisLayer", previous_layer);
    int scene_result = JS_SetPropertyStr(context, global, "thisScene", previous_scene);
    int object_result = JS_SetPropertyStr(context, global, "thisObject", previous_object);
    JS_FreeValue(context, global);
    return layer_result >= 0 && scene_result >= 0 && object_result >= 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_effect_catalog(
    MWXSceneQuickJSOwner *owner,
    uint32_t effect_count,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->effect_names == NULL || owner->effect_count != 0 ||
        effect_count > MWX_SCENE_QUICKJS_MAX_EFFECTS) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid effect catalog");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (effect_count == 0) return MWX_SCENE_QUICKJS_OK;
    char **effect_names = calloc(effect_count, sizeof(*effect_names));
    if (effect_names == NULL) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "effect catalog allocation failed");
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    free(owner->effect_names);
    owner->effect_names = effect_names;
    owner->effect_count = effect_count;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_effect_name(
    MWXSceneQuickJSOwner *owner,
    uint32_t effect_index,
    const char *name,
    size_t name_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->effect_names == NULL || name == NULL ||
        effect_index >= owner->effect_count || name_length == 0 ||
        name_length > MWX_SCENE_QUICKJS_MAX_EFFECT_NAME ||
        memchr(name, '\0', name_length) != NULL ||
        owner->effect_names[effect_index] != NULL) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid effect name");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char *copy = malloc(name_length + 1);
    if (copy == NULL) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "effect name allocation failed");
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    memcpy(copy, name, name_length);
    copy[name_length] = '\0';
    owner->effect_names[effect_index] = copy;
    return MWX_SCENE_QUICKJS_OK;
}

size_t mwx_scene_quickjs_owner_material_function_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner == NULL ? 0 : owner->material_function_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_material_function_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t *effect_index,
    char *function_name,
    size_t function_name_capacity,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || effect_index == NULL || function_name == NULL ||
        function_name_capacity == 0 || index >= owner->material_function_count) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid material function mutation");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    const MWXSceneQuickJSMaterialFunctionMutationRecord *record =
        &owner->material_functions[index];
    size_t length = strlen(record->function_name);
    if (length + 1 > function_name_capacity) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "material function name buffer is too small");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *effect_index = record->effect_index;
    memcpy(function_name, record->function_name, length + 1);
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_domain_reset_budget(
    MWXSceneQuickJSDomain *domain,
    uint64_t interrupt_budget
) {
    if (domain == NULL) return;
    domain->interrupt_budget = interrupt_budget;
    domain->interrupted = false;
}

void mwx_scene_quickjs_owner_invalidate(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return;
    owner->generation += 1;
    owner->disabled = true;
}

static bool valid_teardown_frame(const MWXSceneQuickJSFrameInput *frame) {
    return frame != NULL && isfinite(frame->time_of_day) &&
        frame->time_of_day >= 0 && frame->time_of_day <= 1 &&
        isfinite(frame->frame_time) && frame->frame_time >= 0 &&
        isfinite(frame->runtime) && frame->runtime >= 0;
}

static uint32_t active_dynamic_layer_count(const MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return 0;
    uint32_t count = 0;
    for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
        const MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (record->configured && record->dynamic && !record->destroyed &&
            record->owner_identity == owner->identity) count += 1;
    }
    return count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_lifecycle_snapshot(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSLifecycleSnapshot *snapshot
) {
    if (owner == NULL || snapshot == NULL) {
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *snapshot = (MWXSceneQuickJSLifecycleSnapshot){
        .teardown_started = owner->teardown_started ? 1 : 0,
        .destroy_callback_count = owner->destroy_callback_count,
        .active_timer_count = mwx_scene_quickjs_owner_active_timer_count(owner),
        .pending_layer_mutation_count = (uint32_t)owner->layer_mutation_count,
        .active_dynamic_layer_count = active_dynamic_layer_count(owner),
        .has_job_residue = mwx_scene_quickjs_owner_has_job_residue(owner) ? 1 : 0,
        .callback_active = owner->domain != NULL &&
            owner->domain->callback_active && owner->domain->active_owner == owner ? 1 : 0,
    };
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_teardown(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    uint32_t *destroy_callback_invoked,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (destroy_callback_invoked != NULL) *destroy_callback_invoked = 0;
    if (owner == NULL || destroy_callback_invoked == NULL ||
        !valid_teardown_frame(frame)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid SceneScript teardown"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->teardown_started) return MWX_SCENE_QUICKJS_OK;
    if (owner->generation != expected_generation) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "stale SceneScript owner generation"
        );
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }

    owner->teardown_started = true;
    MWXSceneQuickJSDomain *domain = owner->domain;
    JSContext *context = domain->context;
    domain->interrupted = false;
    mwx_scene_quickjs_discard_jobs(owner);
    mwx_scene_quickjs_destroy_job_host(owner);
    mwx_scene_quickjs_destroy_timer_host(owner);
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;

    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    JSValue function = JS_UNDEFINED;
    if (!mwx_scene_quickjs_assign_script_properties(
            owner, script_properties_json, script_properties_length
        )) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript teardown properties unavailable"
        );
        result = MWX_SCENE_QUICKJS_EXCEPTION;
    } else {
        function = JS_GetPropertyStr(context, owner->module, "destroy");
        if (JS_IsException(function)) {
            mwx_scene_quickjs_write_exception(domain, diagnostic, diagnostic_capacity);
            result = MWX_SCENE_QUICKJS_EXCEPTION;
        }
    }

    JSValue previous_layer = JS_UNDEFINED;
    JSValue previous_scene = JS_UNDEFINED;
    JSValue previous_object = JS_UNDEFINED;
    JSValue previous_engine = JS_UNDEFINED;
    bool callback_started = false;
    bool handles_bound = false;
    bool engine_bound = false;
    if (result == MWX_SCENE_QUICKJS_OK && JS_IsFunction(context, function)) {
        mwx_scene_quickjs_begin_callback(owner);
        callback_started = true;
        handles_bound = mwx_scene_quickjs_bind_owner_handles(
            owner, &previous_layer, &previous_scene, &previous_object
        );
        engine_bound = handles_bound && mwx_scene_quickjs_bind_frame_engine_host(
            owner, frame, user_properties_json, user_properties_length,
            &previous_engine
        );
        if (!engine_bound) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity, "SceneScript teardown host unavailable"
            );
            result = MWX_SCENE_QUICKJS_EXCEPTION;
        } else {
            owner->destroy_callback_count += 1;
            *destroy_callback_invoked = 1;
            JSValue callback_result = JS_Call(
                context, function, owner->module, 0, NULL
            );
            if (JS_IsException(callback_result)) {
                result = mwx_scene_quickjs_exception_result(
                    domain, diagnostic, diagnostic_capacity
                );
            }
            JS_FreeValue(context, callback_result);
        }
    }

    if (engine_bound && !mwx_scene_quickjs_restore_frame_engine_host(
            owner, previous_engine
        )) result = MWX_SCENE_QUICKJS_EXCEPTION;
    if (handles_bound && !mwx_scene_quickjs_restore_owner_handles(
            owner, previous_layer, previous_scene, previous_object
        )) result = MWX_SCENE_QUICKJS_EXCEPTION;
    if (callback_started) mwx_scene_quickjs_end_callback(owner);
    JS_FreeValue(context, function);

    mwx_scene_quickjs_discard_jobs(owner);
    mwx_scene_quickjs_destroy_job_host(owner);
    mwx_scene_quickjs_destroy_timer_host(owner);
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    mwx_scene_quickjs_owner_remove_dynamic_layers(owner);
    owner->material_function_count = 0;
    owner->animation_command_count = 0;
    owner->generation += 1;
    owner->disabled = true;
    return result;
}
