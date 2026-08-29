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

static MWXSceneQuickJSLayerRecord *owner_layer_record(
    MWXSceneQuickJSOwner *owner
) {
    if (!callback_owns_owner(owner) || !owner->target_layer_configured ||
        owner->target_layer_index >= owner->domain->layer_count) return NULL;
    MWXSceneQuickJSLayerRecord *record =
        &owner->domain->layers[owner->target_layer_index];
    return record->configured ? record : NULL;
}

static JSValue owner_layer_origin(
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
    MWXSceneQuickJSLayerRecord *record = owner_layer_record(owner);
    if (record == NULL) {
        return JS_ThrowTypeError(context, "thisLayer origin is unavailable");
    }
    JSValue arguments[3] = {
        JS_NewFloat64(context, record->current_origin[0]),
        JS_NewFloat64(context, record->current_origin[1]),
        JS_NewFloat64(context, record->current_origin[2]),
    };
    JSValue result = JS_CallConstructor(
        context, owner->domain->vec3_constructor, 3, arguments
    );
    for (size_t index = 0; index < 3; ++index) {
        JS_FreeValue(context, arguments[index]);
    }
    return result;
}

static JSValue owner_layer_id(
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
    MWXSceneQuickJSLayerRecord *record = owner_layer_record(opaque);
    if (record == NULL) {
        return JS_ThrowTypeError(context, "thisLayer id is unavailable");
    }
    return JS_NewInt64(context, record->layer_id);
}

static JSValue owner_layer_name(
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
    MWXSceneQuickJSLayerRecord *record = owner_layer_record(opaque);
    if (record == NULL) {
        return JS_ThrowTypeError(context, "thisLayer name is unavailable");
    }
    return JS_NewString(context, record->name);
}

static void free_layer_handle(void *opaque) {
    free(opaque);
}

static JSValue layer_origin(
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
    MWXSceneQuickJSLayerHandle *handle = opaque;
    if (handle == NULL || !callback_owns_epoch(handle->domain, handle->callback_epoch) ||
        handle->layer_index >= handle->domain->layer_count ||
        !handle->domain->layers[handle->layer_index].configured) {
        return JS_ThrowTypeError(context, "layer handle is stale");
    }
    const double *origin = handle->domain->layers[handle->layer_index].current_origin;
    JSValue arguments[3] = {
        JS_NewFloat64(context, origin[0]),
        JS_NewFloat64(context, origin[1]),
        JS_NewFloat64(context, origin[2]),
    };
    JSValue result = JS_CallConstructor(
        context, handle->domain->vec3_constructor, 3, arguments
    );
    for (size_t index = 0; index < 3; ++index) JS_FreeValue(context, arguments[index]);
    return result;
}

static JSValue make_layer_handle(
    JSContext *context,
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index
) {
    if (!domain->callback_active || layer_index >= domain->layer_count ||
        !domain->layers[layer_index].configured) {
        return JS_ThrowRangeError(context, "layer target does not exist");
    }
    JSValue layer = JS_NewObject(context);
    if (JS_IsException(layer)) return layer;
    MWXSceneQuickJSLayerHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) {
        JS_FreeValue(context, layer);
        return JS_ThrowInternalError(context, "layer handle allocation failed");
    }
    handle->domain = domain;
    handle->layer_index = layer_index;
    handle->callback_epoch = domain->callback_epoch;
    JSValue getter = JS_NewCClosure(
        context, layer_origin, "get origin", free_layer_handle, 0, 0, handle
    );
    JSAtom origin_atom = JS_NewAtom(context, "origin");
    int origin_result = JS_DefinePropertyGetSet(
        context, layer, origin_atom, getter, JS_UNDEFINED, JS_PROP_ENUMERABLE
    );
    JS_FreeAtom(context, origin_atom);
    MWXSceneQuickJSLayerRecord *record = &domain->layers[layer_index];
    if (origin_result < 0 ||
        JS_DefinePropertyValueStr(
            context, layer, "id", JS_NewInt64(context, record->layer_id),
            JS_PROP_ENUMERABLE
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, layer, "name", JS_NewString(context, record->name),
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    return layer;
}

static JSValue get_layer(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSDomain *domain = opaque;
    if (domain == NULL || !domain->callback_active || argc != 1) {
        return JS_ThrowTypeError(context, "getLayer host is unavailable");
    }
    int64_t index = -1;
    if (JS_IsString(argv[0])) {
        size_t length = 0;
        const char *name = JS_ToCStringLen(context, &length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        for (uint32_t candidate = 0; candidate < domain->layer_count; ++candidate) {
            const MWXSceneQuickJSLayerRecord *record = &domain->layers[candidate];
            if (record->configured && record->name != NULL &&
                strlen(record->name) == length &&
                memcmp(record->name, name, length) == 0) {
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
            return JS_ThrowRangeError(context, "getLayer index is invalid");
        }
        index = (int64_t)numeric_index;
    } else {
        return JS_ThrowTypeError(context, "getLayer expects one name or index");
    }
    if (index < 0 || index >= domain->layer_count) {
        return JS_ThrowRangeError(context, "getLayer target does not exist");
    }
    return make_layer_handle(context, domain, (uint32_t)index);
}

static JSValue get_layer_by_id(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSDomain *domain = opaque;
    double numeric_id = 0;
    if (domain == NULL || !domain->callback_active || argc != 1 ||
        JS_ToFloat64(context, &numeric_id, argv[0]) < 0 ||
        !isfinite(numeric_id) || floor(numeric_id) != numeric_id ||
        fabs(numeric_id) > 9007199254740991.0) {
        return JS_ThrowTypeError(context, "getLayerByID expects one integer id");
    }
    int64_t layer_id = (int64_t)numeric_id;
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        if (domain->layers[index].configured &&
            domain->layers[index].layer_id == layer_id) {
            return make_layer_handle(context, domain, index);
        }
    }
    return JS_ThrowRangeError(context, "getLayerByID target does not exist");
}

static JSValue get_layer_count(
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
    MWXSceneQuickJSDomain *domain = opaque;
    if (domain == NULL || !domain->callback_active) {
        return JS_ThrowTypeError(context, "getLayerCount host is unavailable");
    }
    return JS_NewUint32(context, domain->layer_count);
}

static bool install_effect_handle(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    JSValue layer = JS_NewObject(context);
    if (JS_IsException(layer)) return false;
    JSValue getter = JS_NewCClosure(context, get_effect, "getEffect", NULL, 1, 0, owner);
    JSValue count = JS_NewCClosure(
        context, get_effect_count, "getEffectCount", NULL, 0, 0, owner
    );
    JSValue origin = JS_NewCClosure(
        context, owner_layer_origin, "get origin", NULL, 0, 0, owner
    );
    JSValue id = JS_NewCClosure(
        context, owner_layer_id, "get id", NULL, 0, 0, owner
    );
    JSValue name = JS_NewCClosure(
        context, owner_layer_name, "get name", NULL, 0, 0, owner
    );
    if (JS_IsException(getter) || JS_IsException(count) ||
        JS_IsException(origin) || JS_IsException(id) || JS_IsException(name)) {
        JS_FreeValue(context, getter);
        JS_FreeValue(context, count);
        JS_FreeValue(context, origin);
        JS_FreeValue(context, id);
        JS_FreeValue(context, name);
        JS_FreeValue(context, layer);
        return false;
    }
    JSAtom origin_atom = JS_NewAtom(context, "origin");
    JSAtom id_atom = JS_NewAtom(context, "id");
    JSAtom name_atom = JS_NewAtom(context, "name");
    int origin_result = JS_DefinePropertyGetSet(
        context, layer, origin_atom, origin, JS_UNDEFINED, JS_PROP_ENUMERABLE
    );
    int id_result = JS_DefinePropertyGetSet(
        context, layer, id_atom, id, JS_UNDEFINED, JS_PROP_ENUMERABLE
    );
    int name_result = JS_DefinePropertyGetSet(
        context, layer, name_atom, name, JS_UNDEFINED, JS_PROP_ENUMERABLE
    );
    JS_FreeAtom(context, origin_atom);
    JS_FreeAtom(context, id_atom);
    JS_FreeAtom(context, name_atom);
    if (origin_result < 0 || id_result < 0 || name_result < 0 ||
        JS_DefinePropertyValueStr(
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

static bool install_scene_handle(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    JSValue scene = JS_NewObject(context);
    if (JS_IsException(scene)) return false;
    JSValue by_name = JS_NewCClosure(
        context, get_layer, "getLayer", NULL, 1, 0, owner->domain
    );
    JSValue by_id = JS_NewCClosure(
        context, get_layer_by_id, "getLayerByID", NULL, 1, 0, owner->domain
    );
    JSValue count = JS_NewCClosure(
        context, get_layer_count, "getLayerCount", NULL, 0, 0, owner->domain
    );
    if (JS_IsException(by_name) || JS_IsException(by_id) || JS_IsException(count) ||
        JS_DefinePropertyValueStr(
            context, scene, "getLayer", by_name, JS_PROP_ENUMERABLE
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, scene, "getLayerByID", by_id, JS_PROP_ENUMERABLE
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, scene, "getLayerCount", count, JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, scene);
        return false;
    }
    owner->scene_handle = scene;
    return true;
}

bool mwx_scene_quickjs_install_owner_handles(MWXSceneQuickJSOwner *owner) {
    return owner != NULL && install_effect_handle(owner) &&
        install_scene_handle(owner) && mwx_scene_quickjs_install_object_handle(owner);
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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_layer_catalog(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_count,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers != NULL || domain->layer_count != 0 ||
        layer_count > MWX_SCENE_QUICKJS_MAX_LAYERS) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid layer catalog");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (layer_count == 0) return MWX_SCENE_QUICKJS_OK;
    domain->layers = calloc(layer_count, sizeof(*domain->layers));
    if (domain->layers == NULL) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "layer catalog allocation failed");
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    domain->layer_count = layer_count;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_descriptor(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    int64_t layer_id,
    const char *name,
    size_t name_length,
    const double origin[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers == NULL || layer_index >= domain->layer_count ||
        name_length > MWX_SCENE_QUICKJS_MAX_LAYER_NAME ||
        (name_length > 0 && name == NULL) ||
        (name_length > 0 && memchr(name, '\0', name_length) != NULL) || origin == NULL ||
        !isfinite(origin[0]) || !isfinite(origin[1]) || !isfinite(origin[2]) ||
        layer_id < -9007199254740991LL || layer_id > 9007199254740991LL ||
        domain->layers[layer_index].configured) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid layer descriptor");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char *copy = malloc(name_length + 1);
    if (copy == NULL) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "layer name allocation failed");
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    if (name_length > 0) memcpy(copy, name, name_length);
    copy[name_length] = '\0';
    MWXSceneQuickJSLayerRecord *record = &domain->layers[layer_index];
    record->layer_id = layer_id;
    record->name = copy;
    memcpy(record->authored_origin, origin, sizeof(record->authored_origin));
    memcpy(record->current_origin, origin, sizeof(record->current_origin));
    record->configured = true;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_layer_identity(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->domain == NULL ||
        owner->target_layer_configured || owner->domain->callback_active) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid owner layer identity"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (record->configured && record->layer_id == layer_id) {
            owner->target_layer_index = index;
            owner->target_layer_configured = true;
            return MWX_SCENE_QUICKJS_OK;
        }
    }
    mwx_scene_quickjs_write_diagnostic(
        diagnostic, diagnostic_capacity, "owner layer identity does not exist"
    );
    return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_begin_layer_snapshot(
    MWXSceneQuickJSDomain *domain,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || generation == 0 ||
        generation <= domain->layer_snapshot_generation) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "stale layer snapshot generation");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        if (domain->layers[index].configured) {
            memcpy(
                domain->layers[index].current_origin,
                domain->layers[index].authored_origin,
                sizeof(domain->layers[index].current_origin)
            );
        }
    }
    domain->layer_snapshot_generation = generation;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_origin(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    const double origin[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers == NULL || layer_index >= domain->layer_count ||
        !domain->layers[layer_index].configured || origin == NULL ||
        !isfinite(origin[0]) || !isfinite(origin[1]) || !isfinite(origin[2]) ||
        domain->layer_snapshot_generation == 0 || domain->callback_active) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid layer origin snapshot");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    memcpy(
        domain->layers[layer_index].current_origin,
        origin,
        sizeof(domain->layers[layer_index].current_origin)
    );
    return MWX_SCENE_QUICKJS_OK;
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
