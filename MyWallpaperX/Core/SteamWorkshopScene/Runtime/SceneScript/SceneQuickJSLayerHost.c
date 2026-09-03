#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct MWXSceneQuickJSLayerHandle {
    MWXSceneQuickJSDomain *domain;
    uint64_t owner_identity;
    uint32_t layer_index;
    uint64_t callback_epoch;
    bool owner_target;
    bool persistent;
} MWXSceneQuickJSLayerHandle;

typedef struct MWXSceneQuickJSVideoHandle {
    MWXSceneQuickJSDomain *domain;
    uint64_t owner_identity;
    uint32_t layer_index;
} MWXSceneQuickJSVideoHandle;

typedef struct MWXSceneQuickJSAssetHandle {
    char *path;
} MWXSceneQuickJSAssetHandle;

static JSValue make_layer_handle(
    JSContext *context,
    MWXSceneQuickJSOwner *owner,
    uint32_t index,
    bool persistent
);

static void finalize_layer_handle(JSRuntime *runtime, JSValue value) {
    (void)runtime;
    free(JS_GetOpaque(value, JS_GetClassID(value)));
}

static void finalize_asset_handle(JSRuntime *runtime, JSValue value) {
    (void)runtime;
    MWXSceneQuickJSAssetHandle *handle = JS_GetOpaque(
        value, JS_GetClassID(value)
    );
    if (handle == NULL) return;
    free(handle->path);
    free(handle);
}

bool mwx_scene_quickjs_install_layer_handle_class(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL || domain->runtime == NULL ||
        domain->layer_handle_class_id != JS_INVALID_CLASS_ID ||
        domain->asset_handle_class_id != JS_INVALID_CLASS_ID) return false;
    static const JSClassDef layer_definition = {
        .class_name = "SceneLayerHandle",
        .finalizer = finalize_layer_handle,
    };
    static const JSClassDef asset_definition = {
        .class_name = "SceneAssetHandle",
        .finalizer = finalize_asset_handle,
    };
    JS_NewClassID(domain->runtime, &domain->layer_handle_class_id);
    JS_NewClassID(domain->runtime, &domain->asset_handle_class_id);
    return domain->layer_handle_class_id != JS_INVALID_CLASS_ID &&
        domain->asset_handle_class_id != JS_INVALID_CLASS_ID &&
        JS_NewClass(
            domain->runtime, domain->layer_handle_class_id, &layer_definition
        ) >= 0 &&
        JS_NewClass(
            domain->runtime, domain->asset_handle_class_id, &asset_definition
        ) >= 0;
}

enum LayerProperty {
    LAYER_ORIGIN,
    LAYER_SCALE,
    LAYER_ANGLES,
    LAYER_VISIBLE,
    LAYER_ALPHA,
    LAYER_COLOR,
    LAYER_TEXT,
    LAYER_POINT_SIZE,
    LAYER_FONT,
    LAYER_ID,
    LAYER_NAME,
};

static bool callback_owns(MWXSceneQuickJSOwner *owner) {
    return owner != NULL && owner->domain != NULL &&
        owner->domain->callback_active && owner->domain->active_owner == owner;
}

static MWXSceneQuickJSLayerRecord *record_for_handle(
    MWXSceneQuickJSLayerHandle *handle
) {
    if (handle == NULL || handle->domain == NULL ||
        handle->domain->active_owner == NULL ||
        !callback_owns(handle->domain->active_owner) ||
        handle->domain->active_owner->identity != handle->owner_identity)
        return NULL;
    MWXSceneQuickJSDomain *domain = handle->domain;
    MWXSceneQuickJSOwner *owner = domain->active_owner;
    uint32_t index = handle->owner_target
        ? owner->target_layer_index : handle->layer_index;
    if ((handle->owner_target && !owner->target_layer_configured) ||
        index >= domain->layer_count) return NULL;
    MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
    if (!record->configured || record->destroyed) return NULL;
    if (record->dynamic) {
        if (!handle->persistent) return NULL;
    } else if (!handle->owner_target && !handle->persistent &&
               handle->callback_epoch != domain->callback_epoch) {
        return NULL;
    }
    return record;
}

static bool mark_dirty(MWXSceneQuickJSOwner *owner, MWXSceneQuickJSLayerRecord *record) {
    if (!record->dirty || record->dirty_owner_identity != owner->identity) {
        if (owner->layer_mutation_count >= MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS) {
            return false;
        }
        owner->layer_mutation_count += 1;
    }
    record->dirty = true;
    record->dirty_owner_identity = owner->identity;
    return true;
}

static JSValue make_vec3(JSContext *context, MWXSceneQuickJSDomain *domain, const double v[3]) {
    JSValue arguments[3] = {
        JS_NewFloat64(context, v[0]), JS_NewFloat64(context, v[1]),
        JS_NewFloat64(context, v[2]),
    };
    JSValue result = JS_CallConstructor(context, domain->vec3_constructor, 3, arguments);
    for (size_t index = 0; index < 3; ++index) JS_FreeValue(context, arguments[index]);
    return result;
}

static bool read_vec3(JSContext *context, JSValueConst value, double output[3]) {
    static const char *names[3] = {"x", "y", "z"};
    for (size_t index = 0; index < 3; ++index) {
        JSValue component = JS_GetPropertyStr(context, value, names[index]);
        const bool valid = !JS_IsException(component) &&
            JS_ToFloat64(context, &output[index], component) >= 0 &&
            isfinite(output[index]);
        JS_FreeValue(context, component);
        if (!valid) return false;
    }
    return true;
}

static bool valid_asset_path(const char *path, size_t length) {
    if (path == NULL || length == 0 ||
        length > MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH ||
        path[0] == '/' || path[0] == '\\' ||
        memchr(path, '\0', length) != NULL ||
        memchr(path, '\\', length) != NULL) return false;
    size_t segment_start = 0;
    for (size_t index = 0; index <= length; ++index) {
        if (index != length && path[index] != '/') continue;
        const size_t segment_length = index - segment_start;
        if (segment_length == 0 ||
            (segment_length == 1 && path[segment_start] == '.') ||
            (segment_length == 2 && path[segment_start] == '.' &&
             path[segment_start + 1] == '.')) return false;
        segment_start = index + 1;
    }
    return true;
}

static JSValue make_asset_handle(
    JSContext *context,
    MWXSceneQuickJSDomain *domain,
    const char *path,
    size_t length
) {
    if (!valid_asset_path(path, length)) return JS_UNDEFINED;
    MWXSceneQuickJSAssetHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return JS_EXCEPTION;
    handle->path = malloc(length + 1);
    if (handle->path == NULL) {
        free(handle);
        return JS_EXCEPTION;
    }
    memcpy(handle->path, path, length);
    handle->path[length] = '\0';
    JSValue value = JS_NewObjectClass(context, domain->asset_handle_class_id);
    if (JS_IsException(value) || JS_SetOpaque(value, handle) < 0) {
        free(handle->path);
        free(handle);
        JS_FreeValue(context, value);
        return JS_EXCEPTION;
    }
    return value;
}

static const char *registered_asset_path(
    MWXSceneQuickJSDomain *domain,
    JSValueConst value
) {
    if (domain == NULL || !JS_IsObject(value)) return NULL;
    MWXSceneQuickJSAssetHandle *handle = JS_GetOpaque(
        value, domain->asset_handle_class_id
    );
    return handle == NULL ? NULL : handle->path;
}

static JSValue register_asset(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (owner == NULL || owner->domain == NULL ||
        owner->domain->module_owner != owner ||
        owner->domain->callback_active || argc < 1 || argc > 2 ||
        !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(
            context, "registerAsset is only available during module evaluation"
        );
    }
    if (argc == 2 && JS_ToBool(context, argv[1]) < 0) return JS_EXCEPTION;
    size_t length = 0;
    const char *path = JS_ToCStringLen(context, &length, argv[0]);
    if (!valid_asset_path(path, length)) {
        if (path != NULL) JS_FreeCString(context, path);
        return JS_ThrowTypeError(context, "registerAsset path is invalid");
    }
    JSValue result = make_asset_handle(context, owner->domain, path, length);
    JS_FreeCString(context, path);
    return result;
}

bool mwx_scene_quickjs_install_asset_engine(
    MWXSceneQuickJSOwner *owner,
    JSValue engine
) {
    if (owner == NULL || owner->domain == NULL ||
        !JS_IsObject(engine)) return false;
    JSValue function = JS_NewCClosure(
        owner->domain->context, register_asset, "registerAsset", NULL,
        2, 0, owner
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        owner->domain->context, engine, "registerAsset", function,
        JS_PROP_ENUMERABLE
    ) >= 0;
}

static MWXSceneQuickJSAuthoredLayerMutationRecord *authored_mutation_for_layer(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    for (size_t index = 0; index < owner->authored_layer_mutation_count; ++index) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
            &owner->authored_layer_mutations[index];
        if (mutation->layer_index == layer_index) return mutation;
    }
    return NULL;
}

static MWXSceneQuickJSAuthoredLayerMutationRecord *
authored_mutation_baseline_for_layer(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    for (size_t index = 0;
         index < owner->authored_layer_mutation_baseline_count; ++index) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
            &owner->authored_layer_mutation_baselines[index];
        if (baseline->layer_index == layer_index) return baseline;
    }
    return NULL;
}

static MWXSceneQuickJSAuthoredLayerMutationRecord *stage_authored_mutation(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
        authored_mutation_for_layer(owner, layer_index);
    if (mutation != NULL) return mutation;
    if (owner->layer_mutation_count >= MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS ||
        owner->authored_layer_mutation_count >=
            MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS ||
        layer_index >= owner->domain->authored_layer_count) return NULL;
    MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[layer_index];
    mutation = &owner->authored_layer_mutations[
        owner->authored_layer_mutation_count++
    ];
    *mutation = (MWXSceneQuickJSAuthoredLayerMutationRecord){
        .layer_index = layer_index,
        .visible = record->visible,
    };
    memcpy(mutation->origin, record->current_origin, sizeof(mutation->origin));
    memcpy(mutation->scale, record->scale, sizeof(mutation->scale));
    memcpy(mutation->angles, record->angles, sizeof(mutation->angles));
    MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
        authored_mutation_baseline_for_layer(owner, layer_index);
    if (baseline != NULL) {
        if ((baseline->fields &
             MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN) != 0)
            memcpy(mutation->origin, baseline->origin, sizeof(mutation->origin));
        if ((baseline->fields &
             MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE) != 0)
            memcpy(mutation->scale, baseline->scale, sizeof(mutation->scale));
        if ((baseline->fields &
             MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES) != 0)
            memcpy(mutation->angles, baseline->angles, sizeof(mutation->angles));
        if ((baseline->fields &
             MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY) != 0)
            mutation->visible = baseline->visible;
    } else if (owner->target_layer_configured &&
        layer_index == owner->target_layer_index &&
        owner->authored_layer_baseline_available) {
        memcpy(
            mutation->origin, owner->authored_layer_baseline_origin,
            sizeof(mutation->origin)
        );
        memcpy(
            mutation->scale, owner->authored_layer_baseline_scale,
            sizeof(mutation->scale)
        );
        memcpy(
            mutation->angles, owner->authored_layer_baseline_angles,
            sizeof(mutation->angles)
        );
    }
    owner->layer_mutation_count += 1;
    return mutation;
}

static const double *authored_transform_value(
    const MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSAuthoredLayerMutationRecord *mutation,
    const MWXSceneQuickJSAuthoredLayerMutationRecord *baseline,
    uint32_t layer_index,
    uint32_t field,
    const double staged[3],
    const double current[3]
) {
    if (mutation != NULL && (mutation->fields & field) != 0) return staged;
    if (baseline != NULL && (baseline->fields & field) != 0) {
        if (field == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN)
            return baseline->origin;
        if (field == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE)
            return baseline->scale;
        return baseline->angles;
    }
    if (owner->target_layer_configured &&
        layer_index == owner->target_layer_index &&
        owner->authored_layer_baseline_available) {
        if (field == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN)
            return owner->authored_layer_baseline_origin;
        if (field == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE)
            return owner->authored_layer_baseline_scale;
        return owner->authored_layer_baseline_angles;
    }
    return current;
}

static const char *authored_font_value(
    const MWXSceneQuickJSAuthoredLayerMutationRecord *mutation,
    const MWXSceneQuickJSAuthoredLayerMutationRecord *baseline,
    const MWXSceneQuickJSLayerRecord *record
) {
    if (mutation != NULL &&
        (mutation->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT) != 0)
        return mutation->font;
    if (baseline != NULL &&
        (baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT) != 0)
        return baseline->font;
    return record->font == NULL ? "" : record->font;
}

static JSValue layer_get(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv;
    MWXSceneQuickJSLayerHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = record_for_handle(handle);
    if (record == NULL) return JS_ThrowTypeError(context, "layer handle is stale");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    const uint32_t record_index = (uint32_t)(record - handle->domain->layers);
    MWXSceneQuickJSAuthoredLayerMutationRecord *authored_mutation =
        !record->dynamic ? authored_mutation_for_layer(owner, record_index) : NULL;
    MWXSceneQuickJSAuthoredLayerMutationRecord *authored_baseline =
        !record->dynamic
            ? authored_mutation_baseline_for_layer(owner, record_index) : NULL;
    switch ((enum LayerProperty)magic) {
    case LAYER_ORIGIN:
        return make_vec3(
            context, handle->domain,
            !record->dynamic ? authored_transform_value(
                owner, authored_mutation, authored_baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN,
                authored_mutation == NULL ? record->current_origin
                                          : authored_mutation->origin,
                record->current_origin
            ) : record->current_origin
        );
    case LAYER_SCALE:
        return make_vec3(
            context, handle->domain,
            !record->dynamic ? authored_transform_value(
                owner, authored_mutation, authored_baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE,
                authored_mutation == NULL ? record->scale
                                          : authored_mutation->scale,
                record->scale
            ) : record->scale
        );
    case LAYER_ANGLES:
        return make_vec3(
            context, handle->domain,
            !record->dynamic ? authored_transform_value(
                owner, authored_mutation, authored_baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES,
                authored_mutation == NULL ? record->angles
                                          : authored_mutation->angles,
                record->angles
            ) : record->angles
        );
    case LAYER_VISIBLE:
        return JS_NewBool(
            context,
            authored_mutation != NULL &&
                    (authored_mutation->fields &
                     MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY) != 0
                ? authored_mutation->visible
                : (authored_baseline != NULL &&
                   (authored_baseline->fields &
                    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY) != 0
                    ? authored_baseline->visible
                : record->visible
                  )
        );
    case LAYER_ALPHA:
        return JS_NewFloat64(context, record->alpha);
    case LAYER_COLOR:
        return make_vec3(context, handle->domain, record->color);
    case LAYER_TEXT:
        return JS_NewString(
            context,
            authored_mutation != NULL &&
                    (authored_mutation->fields &
                     MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0
                ? authored_mutation->text
                : (authored_baseline != NULL &&
                   (authored_baseline->fields &
                    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0
                    ? authored_baseline->text
                : (record->text == NULL ? "" : record->text)
                  )
        );
    case LAYER_POINT_SIZE: return JS_NewFloat64(context, record->point_size);
    case LAYER_FONT: {
        const char *font = !record->dynamic
            ? authored_font_value(authored_mutation, authored_baseline, record)
            : (record->font == NULL ? "" : record->font);
        return font[0] == '\0'
            ? JS_UNDEFINED
            : make_asset_handle(context, handle->domain, font, strlen(font));
    }
    case LAYER_ID: return JS_NewInt64(context, record->layer_id);
    case LAYER_NAME: return JS_NewString(context, record->name == NULL ? "" : record->name);
    }
    return JS_UNDEFINED;
}

static JSValue layer_set(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    MWXSceneQuickJSLayerHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = record_for_handle(handle);
    if (record == NULL || argc != 1) {
        return JS_ThrowTypeError(context, "layer mutation target is not an owned dynamic layer");
    }
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    const uint32_t record_index = (uint32_t)(record - handle->domain->layers);
    const bool value_owner_target_visibility = owner->value_only &&
        handle->owner_target &&
        (enum LayerProperty)magic == LAYER_VISIBLE &&
        owner->target_layer_configured &&
        record_index == owner->target_layer_index && !record->dynamic;
    if (owner->value_only && !value_owner_target_visibility) {
        return JS_ThrowTypeError(
            context,
            "Boolean value owner may only write its target visibility"
        );
    }
    const bool dynamic_target = record->dynamic &&
        record->owner_identity == handle->owner_identity;
    const bool authored_target = !record->dynamic && !owner->value_only;
    const bool value_authored_target = !record->dynamic &&
        value_owner_target_visibility;
    if (!dynamic_target && !authored_target && !value_authored_target)
        return JS_ThrowTypeError(context, "layer mutation target is not owned by this script");

    switch ((enum LayerProperty)magic) {
    case LAYER_ORIGIN: {
        double value[3];
        if (!read_vec3(context, argv[0], value))
            return JS_ThrowTypeError(context, "layer origin expects finite Vec3");
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                authored_mutation_baseline_for_layer(owner, record_index);
            const double *current = authored_transform_value(
                owner, mutation, baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN,
                mutation == NULL ? record->current_origin : mutation->origin,
                record->current_origin
            );
            if (memcmp(value, current, sizeof(value)) == 0) break;
            mutation = stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            memcpy(mutation->origin, value, sizeof(value));
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN;
            break;
        }
        if (memcmp(value, record->current_origin, sizeof(value)) == 0) break;
        if (!mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->current_origin, value, sizeof(value));
        break;
    }
    case LAYER_SCALE: {
        double value[3];
        if (!read_vec3(context, argv[0], value))
            return JS_ThrowTypeError(context, "layer scale expects finite Vec3");
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                authored_mutation_baseline_for_layer(owner, record_index);
            const double *current = authored_transform_value(
                owner, mutation, baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE,
                mutation == NULL ? record->scale : mutation->scale,
                record->scale
            );
            if (memcmp(value, current, sizeof(value)) == 0) break;
            mutation = stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            memcpy(mutation->scale, value, sizeof(value));
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE;
            break;
        }
        if (memcmp(value, record->scale, sizeof(value)) == 0) break;
        if (!mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->scale, value, sizeof(value));
        break;
    }
    case LAYER_ANGLES: {
        double value[3];
        if (!read_vec3(context, argv[0], value))
            return JS_ThrowTypeError(context, "layer angles expects finite Vec3");
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                authored_mutation_baseline_for_layer(owner, record_index);
            const double *current = authored_transform_value(
                owner, mutation, baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES,
                mutation == NULL ? record->angles : mutation->angles,
                record->angles
            );
            if (memcmp(value, current, sizeof(value)) == 0) break;
            mutation = stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            memcpy(mutation->angles, value, sizeof(value));
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES;
            break;
        }
        if (memcmp(value, record->angles, sizeof(value)) == 0) break;
        if (!mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->angles, value, sizeof(value));
        break;
    }
    case LAYER_VISIBLE: {
        int value = JS_ToBool(context, argv[0]);
        if (value < 0) return JS_EXCEPTION;
        if (authored_target || value_authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                authored_mutation_baseline_for_layer(owner, record_index);
            const bool current = mutation != NULL &&
                (mutation->fields &
                 MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY) != 0
                    ? mutation->visible
                    : (baseline != NULL &&
                       (baseline->fields &
                        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY) != 0
                        ? baseline->visible
                        : record->visible);
            if (current == (value != 0)) break;
            mutation = stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            mutation->visible = value != 0;
            mutation->fields |=
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY;
            break;
        }
        if (record->visible == (value != 0)) break;
        if (!mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        record->visible = value != 0;
        break;
    }
    case LAYER_ALPHA: {
        double value = 0;
        if (!dynamic_target || JS_ToFloat64(context, &value, argv[0]) < 0 ||
            !isfinite(value) || value < 0 || value > 1)
            return JS_ThrowRangeError(
                context, "dynamic layer alpha expects a value from 0 to 1"
            );
        if (record->alpha == value) break;
        if (!mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        record->alpha = value;
        break;
    }
    case LAYER_COLOR: {
        double value[3];
        if (!dynamic_target || !read_vec3(context, argv[0], value) ||
            value[0] < 0 || value[0] > 1 || value[1] < 0 || value[1] > 1 ||
            value[2] < 0 || value[2] > 1)
            return JS_ThrowRangeError(
                context, "dynamic layer color expects a normalized finite Vec3"
            );
        if (memcmp(value, record->color, sizeof(value)) == 0) break;
        if (!mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->color, value, sizeof(value));
        break;
    }
    case LAYER_TEXT: {
        if (authored_target && !record->text_mutable)
            return JS_ThrowTypeError(
                context, "layer text mutation target is not a text layer"
            );
        size_t length = 0;
        const char *value = JS_ToCStringLen(context, &length, argv[0]);
        if (value == NULL || length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT ||
            memchr(value, '\0', length) != NULL) {
            if (value != NULL) JS_FreeCString(context, value);
            return JS_ThrowTypeError(context, "layer text is invalid");
        }
        char *copy = malloc(length + 1);
        if (copy == NULL) { JS_FreeCString(context, value); return JS_EXCEPTION; }
        memcpy(copy, value, length); copy[length] = '\0';
        JS_FreeCString(context, value);
        MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
            authored_target ? authored_mutation_for_layer(owner, record_index) : NULL;
        MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
            authored_target
                ? authored_mutation_baseline_for_layer(owner, record_index) : NULL;
        const char *current = mutation != NULL &&
                (mutation->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0
            ? mutation->text
            : (baseline != NULL &&
               (baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0
                ? baseline->text
                : (record->text == NULL ? "" : record->text));
        if (strcmp(current, copy) == 0) {
            free(copy);
            break;
        }
        if (authored_target) {
            mutation = stage_authored_mutation(owner, record_index);
            if (mutation == NULL) {
                free(copy);
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            }
            free(mutation->text);
            mutation->text = copy;
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT;
            break;
        }
        if (!mark_dirty(owner, record)) {
            free(copy);
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        }
        free(record->text); record->text = copy;
        break;
    }
    case LAYER_FONT: {
        if (!record->text_mutable && !record->dynamic)
            return JS_ThrowTypeError(
                context, "layer font mutation target is not a text layer"
            );
        const char *value = registered_asset_path(handle->domain, argv[0]);
        const size_t length = value == NULL ? 0 : strlen(value);
        if (!valid_asset_path(value, length) ||
            length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT)
            return JS_ThrowTypeError(
                context, "layer font expects a registered asset handle"
            );
        const char *current = authored_target
            ? authored_font_value(
                authored_mutation_for_layer(owner, record_index),
                authored_mutation_baseline_for_layer(owner, record_index),
                record
            )
            : (record->font == NULL ? "" : record->font);
        if (strcmp(current, value) == 0) break;
        char *copy = malloc(length + 1);
        if (copy == NULL) return JS_EXCEPTION;
        memcpy(copy, value, length + 1);
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                stage_authored_mutation(owner, record_index);
            if (mutation == NULL) {
                free(copy);
                return JS_ThrowInternalError(
                    context, "layer mutation buffer exceeded"
                );
            }
            free(mutation->font);
            mutation->font = copy;
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT;
            break;
        }
        if (!mark_dirty(owner, record)) {
            free(copy);
            return JS_ThrowInternalError(
                context, "layer mutation buffer exceeded"
            );
        }
        free(record->font);
        record->font = copy;
        break;
    }
    default:
        return JS_ThrowTypeError(context, "layer property is read-only");
    }
    return JS_UNDEFINED;
}

static void free_layer_handle(void *opaque) { free(opaque); }

static JSValue get_parent(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSLayerHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = record_for_handle(handle);
    if (record == NULL || argc != 0)
        return JS_ThrowTypeError(context, "getParent layer handle is stale");
    if (!record->has_parent) return JS_UNDEFINED;
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    for (uint32_t index = 0; index < handle->domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *parent = &handle->domain->layers[index];
        if (parent->configured && !parent->destroyed &&
            parent->layer_id == record->parent_id) {
            return make_layer_handle(context, owner, index, true);
        }
    }
    return JS_ThrowTypeError(context, "layer parent identity is invalid");
}

static MWXSceneQuickJSLayerRecord *video_record_for_handle(
    MWXSceneQuickJSVideoHandle *handle
) {
    if (handle == NULL || handle->domain == NULL ||
        handle->domain->active_owner == NULL ||
        !callback_owns(handle->domain->active_owner) ||
        handle->domain->active_owner->identity != handle->owner_identity ||
        handle->layer_index >= handle->domain->layer_count) return NULL;
    MWXSceneQuickJSLayerRecord *record = &handle->domain->layers[
        handle->layer_index
    ];
    return record->configured && !record->destroyed && record->video_available
        ? record : NULL;
}

static bool append_video_command(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSLayerRecord *record,
    uint32_t kind,
    double number_value,
    uint32_t bool_value
) {
    if (owner->video_command_count >= MWX_SCENE_QUICKJS_MAX_VIDEO_COMMANDS) {
        owner->video_command_overflow = true;
        return false;
    }
    owner->video_commands[owner->video_command_count++] =
        (MWXSceneQuickJSVideoCommand){
            .kind = kind,
            .layer_id = record->layer_id,
            .number_value = number_value,
            .bool_value = bool_value,
        };
    return true;
}

enum VideoProperty {
    VIDEO_DURATION,
    VIDEO_RATE,
    VIDEO_LOOP,
};

static JSValue video_get(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv;
    MWXSceneQuickJSLayerRecord *record = video_record_for_handle(opaque);
    if (record == NULL) return JS_ThrowTypeError(context, "video handle is stale");
    switch ((enum VideoProperty)magic) {
    case VIDEO_DURATION: return JS_NewFloat64(context, record->video_duration);
    case VIDEO_RATE: return JS_NewFloat64(context, record->video_rate);
    case VIDEO_LOOP: return JS_NewBool(context, record->video_loop);
    }
    return JS_UNDEFINED;
}

static JSValue video_set(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    MWXSceneQuickJSVideoHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = video_record_for_handle(handle);
    if (record == NULL || argc != 1)
        return JS_ThrowTypeError(context, "video handle is stale");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    bool accepted = false;
    if ((enum VideoProperty)magic == VIDEO_RATE) {
        double value = 0;
        if (JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value) ||
            value <= 0 || value > 16)
            return JS_ThrowRangeError(context, "video rate must be finite in (0, 16]");
        accepted = append_video_command(
            owner, record, MWX_SCENE_QUICKJS_VIDEO_SET_RATE, value, 0
        );
    } else if ((enum VideoProperty)magic == VIDEO_LOOP) {
        int value = JS_ToBool(context, argv[0]);
        if (value < 0) return JS_EXCEPTION;
        accepted = append_video_command(
            owner, record, MWX_SCENE_QUICKJS_VIDEO_SET_LOOP, 0,
            value != 0 ? 1 : 0
        );
    } else {
        return JS_ThrowTypeError(context, "video duration is read-only");
    }
    return accepted ? JS_UNDEFINED : JS_ThrowInternalError(
        context, "video command buffer exceeded"
    );
}

enum VideoFunction {
    VIDEO_PLAY,
    VIDEO_PAUSE,
    VIDEO_STOP,
    VIDEO_IS_PLAYING,
    VIDEO_GET_CURRENT_TIME,
    VIDEO_SET_CURRENT_TIME,
    VIDEO_ADD_ENDED_CALLBACK,
};

static JSValue video_call(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    MWXSceneQuickJSVideoHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = video_record_for_handle(handle);
    if (record == NULL) return JS_ThrowTypeError(context, "video handle is stale");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    switch ((enum VideoFunction)magic) {
    case VIDEO_IS_PLAYING:
        if (argc != 0) return JS_ThrowTypeError(context, "isPlaying expects no arguments");
        return JS_NewBool(context, record->video_is_playing);
    case VIDEO_GET_CURRENT_TIME:
        if (argc != 0)
            return JS_ThrowTypeError(context, "getCurrentTime expects no arguments");
        return JS_NewFloat64(context, record->video_current_time);
    case VIDEO_SET_CURRENT_TIME: {
        double value = 0;
        if (argc != 1 || JS_ToFloat64(context, &value, argv[0]) < 0 ||
            !isfinite(value) || value < 0 ||
            (record->video_duration > 0 && value > record->video_duration))
            return JS_ThrowRangeError(
                context, "setCurrentTime expects a bounded finite time"
            );
        if (!append_video_command(
                owner, record, MWX_SCENE_QUICKJS_VIDEO_SET_CURRENT_TIME,
                value, 0
            )) return JS_ThrowInternalError(context, "video command buffer exceeded");
        return JS_UNDEFINED;
    }
    case VIDEO_ADD_ENDED_CALLBACK: {
        if (argc != 1 || !JS_IsFunction(context, argv[0]))
            return JS_ThrowTypeError(context, "addEndedCallback expects a function");
        if (owner->video_ended_callback_count >=
            MWX_SCENE_QUICKJS_MAX_VIDEO_ENDED_CALLBACKS)
            return JS_ThrowInternalError(context, "video callback buffer exceeded");
        MWXSceneQuickJSVideoEndedCallbackRecord *callback =
            &owner->video_ended_callbacks[owner->video_ended_callback_count++];
        *callback = (MWXSceneQuickJSVideoEndedCallbackRecord){
            .layer_id = record->layer_id,
            .delivered_generation = record->video_ended_generation,
            .callback = JS_DupValue(context, argv[0]),
            .active = true,
        };
        return JS_UNDEFINED;
    }
    case VIDEO_PLAY:
    case VIDEO_PAUSE:
    case VIDEO_STOP: {
        if (argc != 0) return JS_ThrowTypeError(context, "video command expects no arguments");
        const uint32_t kind = (enum VideoFunction)magic == VIDEO_PLAY
            ? MWX_SCENE_QUICKJS_VIDEO_PLAY
            : ((enum VideoFunction)magic == VIDEO_PAUSE
                ? MWX_SCENE_QUICKJS_VIDEO_PAUSE
                : MWX_SCENE_QUICKJS_VIDEO_STOP);
        if (!append_video_command(owner, record, kind, 0, 0))
            return JS_ThrowInternalError(context, "video command buffer exceeded");
        return JS_UNDEFINED;
    }
    }
    return JS_UNDEFINED;
}

static void free_video_handle(void *opaque) { free(opaque); }

static MWXSceneQuickJSVideoHandle *copy_video_handle(
    MWXSceneQuickJSVideoHandle identity
) {
    MWXSceneQuickJSVideoHandle *copy = malloc(sizeof(*copy));
    if (copy != NULL) *copy = identity;
    return copy;
}

static JSValue make_video_handle(
    JSContext *context, MWXSceneQuickJSOwner *owner, uint32_t layer_index
) {
    MWXSceneQuickJSVideoHandle identity = {
        .domain = owner->domain,
        .owner_identity = owner->identity,
        .layer_index = layer_index,
    };
    JSValue video = JS_NewObject(context);
    if (JS_IsException(video)) return video;
    const struct {
        const char *name; enum VideoProperty property; bool writable;
    } properties[] = {
        {"duration", VIDEO_DURATION, false},
        {"rate", VIDEO_RATE, true},
        {"loop", VIDEO_LOOP, true},
    };
    for (size_t index = 0; index < sizeof(properties) / sizeof(properties[0]); ++index) {
        MWXSceneQuickJSVideoHandle *getter_handle = copy_video_handle(identity);
        MWXSceneQuickJSVideoHandle *setter_handle = properties[index].writable
            ? copy_video_handle(identity) : NULL;
        if (getter_handle == NULL ||
            (properties[index].writable && setter_handle == NULL)) {
            free(getter_handle); free(setter_handle); JS_FreeValue(context, video);
            return JS_EXCEPTION;
        }
        JSValue getter = JS_NewCClosure(
            context, video_get, properties[index].name, free_video_handle,
            0, properties[index].property, getter_handle
        );
        JSValue setter = properties[index].writable ? JS_NewCClosure(
            context, video_set, properties[index].name, free_video_handle,
            1, properties[index].property, setter_handle
        ) : JS_UNDEFINED;
        JSAtom atom = JS_NewAtom(context, properties[index].name);
        int result = JS_DefinePropertyGetSet(
            context, video, atom, getter, setter, JS_PROP_ENUMERABLE
        );
        JS_FreeAtom(context, atom);
        if (result < 0) { JS_FreeValue(context, video); return JS_EXCEPTION; }
    }
    const struct { const char *name; enum VideoFunction function; int argc; } functions[] = {
        {"play", VIDEO_PLAY, 0}, {"pause", VIDEO_PAUSE, 0},
        {"stop", VIDEO_STOP, 0}, {"isPlaying", VIDEO_IS_PLAYING, 0},
        {"getCurrentTime", VIDEO_GET_CURRENT_TIME, 0},
        {"setCurrentTime", VIDEO_SET_CURRENT_TIME, 1},
        {"addEndedCallback", VIDEO_ADD_ENDED_CALLBACK, 1},
    };
    for (size_t index = 0; index < sizeof(functions) / sizeof(functions[0]); ++index) {
        MWXSceneQuickJSVideoHandle *function_handle = copy_video_handle(identity);
        if (function_handle == NULL) { JS_FreeValue(context, video); return JS_EXCEPTION; }
        JSValue function = JS_NewCClosure(
            context, video_call, functions[index].name, free_video_handle,
            functions[index].argc, functions[index].function, function_handle
        );
        if (JS_IsException(function) || JS_DefinePropertyValueStr(
                context, video, functions[index].name, function,
                JS_PROP_ENUMERABLE
            ) < 0) { JS_FreeValue(context, video); return JS_EXCEPTION; }
    }
    return video;
}

static JSValue get_video_texture(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSLayerHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = record_for_handle(handle);
    if (record == NULL || argc != 0)
        return JS_ThrowTypeError(context, "getVideoTexture unavailable");
    if (!handle->domain->active_owner->value_only) return JS_UNDEFINED;
    if (!record->video_available) return JS_UNDEFINED;
    uint32_t index = handle->owner_target
        ? handle->domain->active_owner->target_layer_index
        : handle->layer_index;
    return make_video_handle(
        context, handle->domain->active_owner, index
    );
}

static bool define_get_video_texture(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return false;
    *handle = (MWXSceneQuickJSLayerHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index, .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    JSValue function = JS_NewCClosure(
        context, get_video_texture, "getVideoTexture", free_layer_handle,
        0, 0, handle
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        context, layer, "getVideoTexture", function, JS_PROP_ENUMERABLE
    ) >= 0;
}

static bool define_property(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent,
    const char *name, enum LayerProperty property, bool writable
) {
    MWXSceneQuickJSLayerHandle *getter_handle = calloc(1, sizeof(*getter_handle));
    MWXSceneQuickJSLayerHandle *setter_handle = writable
        ? calloc(1, sizeof(*setter_handle)) : NULL;
    if (getter_handle == NULL || (writable && setter_handle == NULL)) {
        free(getter_handle); free(setter_handle); return false;
    }
    *getter_handle = (MWXSceneQuickJSLayerHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    if (setter_handle != NULL) *setter_handle = *getter_handle;
    JSValue getter = JS_NewCClosure(
        context, layer_get, name, free_layer_handle, 0, property, getter_handle
    );
    JSValue setter = writable ? JS_NewCClosure(
        context, layer_set, name, free_layer_handle, 1, property, setter_handle
    ) : JS_UNDEFINED;
    JSAtom atom = JS_NewAtom(context, name);
    int result = JS_DefinePropertyGetSet(
        context, layer, atom, getter, setter, JS_PROP_ENUMERABLE
    );
    JS_FreeAtom(context, atom);
    return result >= 0;
}

static bool define_get_parent(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return false;
    *handle = (MWXSceneQuickJSLayerHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    JSValue function = JS_NewCClosure(
        context, get_parent, "getParent", free_layer_handle, 0, 0, handle
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        context, layer, "getParent", function, JS_PROP_ENUMERABLE
    ) >= 0;
}

static JSValue make_layer_handle(
    JSContext *context, MWXSceneQuickJSOwner *owner, uint32_t index, bool persistent
) {
    if (!callback_owns(owner) || index >= owner->domain->layer_count) {
        return JS_ThrowRangeError(context, "layer target does not exist");
    }
    const bool owner_target = owner->target_layer_configured &&
        index == owner->target_layer_index;
    MWXSceneQuickJSLayerHandle *identity = calloc(1, sizeof(*identity));
    if (identity == NULL) return JS_EXCEPTION;
    *identity = (MWXSceneQuickJSLayerHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target,
        .persistent = persistent,
    };
    JSValue layer = JS_NewObjectClass(
        context, owner->domain->layer_handle_class_id
    );
    if (JS_IsException(layer) || JS_SetOpaque(layer, identity) < 0) {
        free(identity);
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    const struct { const char *name; enum LayerProperty property; bool writable; } fields[] = {
        {"origin", LAYER_ORIGIN, true}, {"scale", LAYER_SCALE, true},
        {"angles", LAYER_ANGLES, true}, {"visible", LAYER_VISIBLE, true},
        {"text", LAYER_TEXT, true}, {"pointsize", LAYER_POINT_SIZE, false},
        {"font", LAYER_FONT, true}, {"id", LAYER_ID, false},
        {"name", LAYER_NAME, false},
    };
    for (size_t field = 0; field < sizeof(fields) / sizeof(fields[0]); ++field) {
        if (!define_property(context, layer, owner, index, owner_target, persistent,
                             fields[field].name, fields[field].property,
                             fields[field].writable)) {
            JS_FreeValue(context, layer); return JS_EXCEPTION;
        }
    }
    if (owner->domain->layers[index].dynamic &&
        (!define_property(
            context, layer, owner, index, owner_target, persistent,
            "alpha", LAYER_ALPHA, true
        ) || !define_property(
            context, layer, owner, index, owner_target, persistent,
            "color", LAYER_COLOR, true
        ))) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    if (!define_get_video_texture(
            context, layer, owner, index, owner_target, persistent
        )) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    if (!define_get_parent(
            context, layer, owner, index, owner_target, persistent
        )) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    return layer;
}

static MWXSceneQuickJSLayerRecord *resolve_layer_argument(
    JSContext *context, MWXSceneQuickJSOwner *owner, JSValueConst value
) {
    if (!callback_owns(owner)) return NULL;
    if (JS_IsStrictEqual(context, value, owner->material_function_layer)) {
        MWXSceneQuickJSLayerHandle target = {
            .domain = owner->domain,
            .owner_identity = owner->identity,
            .callback_epoch = owner->domain->callback_epoch,
            .owner_target = true,
            .persistent = true,
        };
        return record_for_handle(&target);
    }
    MWXSceneQuickJSLayerHandle *handle = JS_GetOpaque(
        value, owner->domain->layer_handle_class_id
    );
    return record_for_handle(handle);
}

static int32_t active_count(MWXSceneQuickJSDomain *domain) {
    int32_t count = 0;
    for (uint32_t index = 0; index < domain->layer_count; ++index)
        if (domain->layers[index].configured && !domain->layers[index].destroyed) count += 1;
    return count;
}

static int32_t storage_at_order(MWXSceneQuickJSDomain *domain, int32_t order) {
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        if (record->configured && !record->destroyed && record->order_index == order)
            return (int32_t)index;
    }
    return -1;
}

static JSValue get_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (!callback_owns(owner) || argc != 1) return JS_ThrowTypeError(context, "getLayer unavailable");
    int32_t storage = -1;
    if (JS_IsString(argv[0])) {
        size_t length = 0; const char *name = JS_ToCStringLen(context, &length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
            MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
            if (record->configured && !record->destroyed && strlen(record->name) == length &&
                memcmp(record->name, name, length) == 0) { storage = (int32_t)index; break; }
        }
        JS_FreeCString(context, name);
    } else {
        double numeric = -1;
        if (JS_ToFloat64(context, &numeric, argv[0]) < 0 || !isfinite(numeric) ||
            floor(numeric) != numeric || numeric < 0 || numeric > INT32_MAX)
            return JS_ThrowRangeError(context, "getLayer index is invalid");
        storage = storage_at_order(owner->domain, (int32_t)numeric);
    }
    if (storage < 0) return JS_ThrowRangeError(context, "getLayer target does not exist");
    return make_layer_handle(context, owner, (uint32_t)storage, true);
}

static JSValue get_layer_by_id(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque; double value = 0;
    if (!callback_owns(owner) || argc != 1 || JS_ToFloat64(context, &value, argv[0]) < 0 ||
        !isfinite(value) || floor(value) != value || fabs(value) > 9007199254740991.0)
        return JS_ThrowTypeError(context, "getLayerByID expects one integer id");
    for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (record->configured && !record->destroyed && record->layer_id == (int64_t)value)
            return make_layer_handle(context, owner, index, true);
    }
    return JS_ThrowRangeError(context, "getLayerByID target does not exist");
}

static bool read_optional_string(
    JSContext *context, JSValueConst object, const char *key,
    size_t maximum, char **output
) {
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsUndefined(value)) { JS_FreeValue(context, value); *output = calloc(1, 1); return *output != NULL; }
    size_t length = 0; const char *string = JS_ToCStringLen(context, &length, value);
    JS_FreeValue(context, value);
    if (string == NULL || length > maximum || memchr(string, '\0', length) != NULL) {
        if (string != NULL) JS_FreeCString(context, string); return false;
    }
    *output = malloc(length + 1);
    if (*output != NULL) { memcpy(*output, string, length); (*output)[length] = '\0'; }
    JS_FreeCString(context, string); return *output != NULL;
}

static bool read_optional_font(
    JSContext *context,
    MWXSceneQuickJSDomain *domain,
    JSValueConst object,
    char **output
) {
    JSValue value = JS_GetPropertyStr(context, object, "font");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        *output = calloc(1, 1);
        return *output != NULL;
    }
    const char *path = registered_asset_path(domain, value);
    const size_t length = path == NULL ? 0 : strlen(path);
    if (!valid_asset_path(path, length) ||
        length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT) {
        JS_FreeValue(context, value);
        return false;
    }
    *output = malloc(length + 1);
    if (*output != NULL) memcpy(*output, path, length + 1);
    JS_FreeValue(context, value);
    return *output != NULL;
}

static double optional_number(JSContext *context, JSValueConst object, const char *key, double fallback) {
    JSValue value = JS_GetPropertyStr(context, object, key); double result = fallback;
    if (!JS_IsUndefined(value) && JS_ToFloat64(context, &result, value) < 0) result = NAN;
    JS_FreeValue(context, value); return result;
}

static bool read_optional_bool(
    JSContext *context, JSValueConst object, const char *key,
    bool fallback, bool *output
) {
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        *output = fallback;
        return true;
    }
    if (!JS_IsBool(value)) {
        JS_FreeValue(context, value);
        return false;
    }
    int result = JS_ToBool(context, value);
    JS_FreeValue(context, value);
    if (result < 0) return false;
    *output = result != 0;
    return true;
}

static bool read_optional_vec3(
    JSContext *context, JSValueConst object, const char *key,
    const double fallback[3], double output[3]
) {
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        if (output != fallback)
            memcpy(output, fallback, sizeof(double) * 3);
        return true;
    }
    const bool valid = JS_IsObject(value) && read_vec3(context, value, output);
    JS_FreeValue(context, value);
    return valid;
}

static bool parse_color(const char *text, double color[3]) {
    if (text == NULL ||
        sscanf(text, " %lf %lf %lf ", &color[0], &color[1], &color[2]) != 3)
        return false;
    return isfinite(color[0]) && isfinite(color[1]) && isfinite(color[2]);
}

static bool read_optional_color(
    JSContext *context, JSValueConst object,
    const double fallback[3], double output[3]
) {
    JSValue value = JS_GetPropertyStr(context, object, "color");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        if (output != fallback)
            memcpy(output, fallback, sizeof(double) * 3);
        return true;
    }
    bool valid = false;
    if (JS_IsString(value)) {
        const char *text = JS_ToCString(context, value);
        valid = text != NULL && parse_color(text, output);
        if (text != NULL) JS_FreeCString(context, text);
    } else if (JS_IsObject(value)) {
        valid = read_vec3(context, value, output);
    }
    JS_FreeValue(context, value);
    return valid;
}

static bool read_optional_asset_path(
    JSContext *context, JSValueConst object, char **output
) {
    JSValue value = JS_GetPropertyStr(context, object, "image");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        *output = calloc(1, 1);
        return *output != NULL;
    }
    if (!JS_IsString(value)) {
        JS_FreeValue(context, value);
        return false;
    }
    size_t length = 0;
    const char *path = JS_ToCStringLen(context, &length, value);
    JS_FreeValue(context, value);
    if (path == NULL || length == 0 ||
        length > MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH ||
        memchr(path, '\0', length) != NULL) {
        if (path != NULL) JS_FreeCString(context, path);
        return false;
    }
    *output = malloc(length + 1);
    if (*output != NULL) {
        memcpy(*output, path, length);
        (*output)[length] = '\0';
    }
    JS_FreeCString(context, path);
    return *output != NULL;
}

static JSValue create_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque; MWXSceneQuickJSDomain *domain = owner->domain;
    if (owner->value_only)
        return JS_ThrowTypeError(context, "Boolean value owner scene handle is read-only");
    if (!callback_owns(owner) || argc != 1 ||
        (!JS_IsObject(argv[0]) && !JS_IsString(argv[0])))
        return JS_ThrowTypeError(
            context, "createLayer expects one configuration or asset path"
        );
    size_t owned = 0, scene_dynamic = 0;
    for (uint32_t i = 0; i < domain->layer_count; ++i)
        if (domain->layers[i].dynamic && !domain->layers[i].destroyed) {
            scene_dynamic += 1;
            if (domain->layers[i].owner_identity == owner->identity) owned += 1;
        }
    if (owned >= MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS ||
        scene_dynamic >= MWX_SCENE_QUICKJS_MAX_SCENE_DYNAMIC_LAYERS ||
        domain->layer_count >= MWX_SCENE_QUICKJS_MAX_LAYERS ||
        owner->layer_mutation_count >= MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS)
        return JS_NULL;
    char *text = NULL, *font = NULL, *name = NULL;
    char *asset_path = NULL;
    double point_size = 32, alpha = 1;
    double origin[3] = {0, 0, 0};
    double scale[3] = {1, 1, 1};
    double color[3] = {1, 1, 1};
    bool visible = true;
    const char *registered_asset = registered_asset_path(domain, argv[0]);
    if (JS_IsString(argv[0]) || registered_asset != NULL) {
        size_t length = 0;
        const char *path = registered_asset;
        if (path != NULL) {
            length = strlen(path);
        } else {
            path = JS_ToCStringLen(context, &length, argv[0]);
        }
        if (!valid_asset_path(path, length)) {
            if (registered_asset == NULL && path != NULL)
                JS_FreeCString(context, path);
            return JS_ThrowTypeError(context, "dynamic layer asset path is invalid");
        }
        asset_path = malloc(length + 1);
        text = calloc(1, 1); font = calloc(1, 1); name = calloc(1, 1);
        if (asset_path != NULL) {
            memcpy(asset_path, path, length); asset_path[length] = '\0';
        }
        if (registered_asset == NULL) JS_FreeCString(context, path);
        if (asset_path == NULL || text == NULL || font == NULL || name == NULL) {
            free(asset_path); free(text); free(font); free(name);
            return JS_EXCEPTION;
        }
    } else {
        if (!read_optional_string(context, argv[0], "text", MWX_SCENE_QUICKJS_MAX_LAYER_TEXT, &text) ||
            !read_optional_font(context, domain, argv[0], &font) ||
            !read_optional_string(context, argv[0], "name", MWX_SCENE_QUICKJS_MAX_LAYER_NAME, &name) ||
            !read_optional_asset_path(context, argv[0], &asset_path) ||
            !read_optional_vec3(context, argv[0], "origin", origin, origin) ||
            !read_optional_vec3(context, argv[0], "scale", scale, scale) ||
            !read_optional_color(context, argv[0], color, color) ||
            !read_optional_bool(context, argv[0], "visible", true, &visible)) {
            free(text); free(font); free(name); free(asset_path);
            return JS_ThrowTypeError(context, "dynamic layer configuration field is invalid");
        }
        point_size = optional_number(context, argv[0], "pointsize", 32);
        alpha = optional_number(context, argv[0], "alpha", 1);
        if (!isfinite(point_size) || point_size < 1 || point_size > 1024 ||
            !isfinite(alpha) || alpha < 0 || alpha > 1 ||
            color[0] < 0 || color[0] > 1 || color[1] < 0 || color[1] > 1 ||
            color[2] < 0 || color[2] > 1) {
            free(text); free(font); free(name); free(asset_path);
            return JS_ThrowRangeError(context, "dynamic layer configuration is invalid");
        }
    }
    int64_t identity = -1;
    for (;;) {
        bool collision = false;
        for (uint32_t i = 0; i < domain->layer_count; ++i)
            if (domain->layers[i].configured && domain->layers[i].layer_id == identity) collision = true;
        if (!collision) break;
        if (identity <= -9007199254740991LL) {
            free(text); free(font); free(name); free(asset_path);
            return JS_ThrowInternalError(context, "dynamic layer identity exhausted");
        }
        identity -= 1;
    }
    uint32_t index = domain->layer_count++;
    MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
    *record = (MWXSceneQuickJSLayerRecord){
        .layer_id = identity, .name = name, .text = text, .font = font,
        .asset_path = asset_path,
        .current_origin = {origin[0], origin[1], origin[2]},
        .scale = {scale[0], scale[1], scale[2]},
        .color = {color[0], color[1], color[2]},
        .alpha = alpha, .point_size = point_size,
        .order_index = active_count(domain), .owner_identity = owner->identity,
        .visible = visible, .dynamic = true, .configured = true,
    };
    if (!mark_dirty(owner, record)) return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
    return make_layer_handle(context, owner, index, true);
}

static JSValue get_layer_index(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (argc != 1) return JS_ThrowTypeError(context, "getLayerIndex expects one layer");
    MWXSceneQuickJSLayerRecord *record = resolve_layer_argument(
        context, owner, argv[0]
    );
    return JS_NewInt32(context, record == NULL ? -1 : record->order_index);
}

static JSValue get_layer_count(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (!callback_owns(owner)) return JS_ThrowTypeError(context, "getLayerCount unavailable");
    return JS_NewInt32(context, active_count(owner->domain));
}

static JSValue enumerate_layers(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (!callback_owns(owner) || argc != 0)
        return JS_ThrowTypeError(context, "enumerateLayers unavailable");
    const int32_t count = active_count(owner->domain);
    JSValue result = JS_NewArray(context);
    if (JS_IsException(result)) return result;
    for (int32_t order = 0; order < count; ++order) {
        const int32_t storage = storage_at_order(owner->domain, order);
        if (storage < 0) {
            JS_FreeValue(context, result);
            return JS_ThrowInternalError(context, "layer render order is invalid");
        }
        JSValue layer = make_layer_handle(
            context, owner, (uint32_t)storage, true
        );
        if (JS_IsException(layer) || JS_SetPropertyUint32(
                context, result, (uint32_t)order, layer
            ) < 0) {
            JS_FreeValue(context, result);
            return JS_EXCEPTION;
        }
    }
    return result;
}

static JSValue sort_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque; double order_value = 0;
    if (owner->value_only)
        return JS_ThrowTypeError(context, "Boolean value owner scene handle is read-only");
    if (!callback_owns(owner) || argc != 2 ||
        JS_ToFloat64(context, &order_value, argv[1]) < 0 || !isfinite(order_value) ||
        floor(order_value) != order_value || order_value < 0 || order_value > INT32_MAX)
        return JS_ThrowTypeError(context, "sortLayer expects a layer and non-negative index");
    MWXSceneQuickJSLayerRecord *target = resolve_layer_argument(
        context, owner, argv[0]
    );
    if (target == NULL || !target->dynamic ||
        target->owner_identity != owner->identity)
        return JS_ThrowTypeError(context, "sortLayer target is not an owned dynamic layer");
    int32_t count = active_count(owner->domain);
    int32_t desired = (int32_t)order_value >= count ? count - 1 : (int32_t)order_value;
    int32_t old = target->order_index;
    for (uint32_t i = 0; i < owner->domain->layer_count; ++i) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[i];
        if (!record->configured || record->destroyed || record == target) continue;
        if (desired < old && record->order_index >= desired && record->order_index < old)
            record->order_index += 1;
        else if (desired > old && record->order_index > old && record->order_index <= desired)
            record->order_index -= 1;
    }
    target->order_index = desired;
    if (!mark_dirty(owner, target)) return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
    return JS_UNDEFINED;
}

static JSValue destroy_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (owner->value_only)
        return JS_ThrowTypeError(context, "Boolean value owner scene handle is read-only");
    MWXSceneQuickJSLayerRecord *record = argc == 1
        ? resolve_layer_argument(context, owner, argv[0]) : NULL;
    if (record == NULL || !record->dynamic ||
        record->owner_identity != owner->identity)
        return JS_ThrowTypeError(context, "destroyLayer target is stale");
    int32_t removed = record->order_index;
    record->destroyed = true;
    if (!mark_dirty(owner, record))
        return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
    for (uint32_t j = 0; j < owner->domain->layer_count; ++j)
        if (!owner->domain->layers[j].destroyed &&
            owner->domain->layers[j].order_index > removed)
            owner->domain->layers[j].order_index -= 1;
    return JS_UNDEFINED;
}

bool mwx_scene_quickjs_install_layer_handles(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return false;
    JSContext *context = owner->domain->context;
    const struct { const char *name; enum LayerProperty property; bool writable; } fields[] = {
        {"origin", LAYER_ORIGIN, true}, {"scale", LAYER_SCALE, true},
        {"angles", LAYER_ANGLES, true}, {"visible", LAYER_VISIBLE, true},
        {"text", LAYER_TEXT, true}, {"pointsize", LAYER_POINT_SIZE, false},
        {"font", LAYER_FONT, true}, {"id", LAYER_ID, false}, {"name", LAYER_NAME, false},
    };
    for (size_t field = 0; field < sizeof(fields) / sizeof(fields[0]); ++field)
        if (!define_property(context, owner->material_function_layer, owner, 0, true, true,
                             fields[field].name, fields[field].property, fields[field].writable))
            return false;
    if (!define_get_video_texture(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    if (!define_get_parent(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    JSValue scene = JS_NewObject(context);
    if (JS_IsException(scene)) return false;
    struct { const char *name; JSCClosure *function; int argc; } functions[] = {
        {"getLayer", get_layer, 1}, {"getLayerByID", get_layer_by_id, 1},
        {"getLayerCount", get_layer_count, 0},
        {"enumerateLayers", enumerate_layers, 0}, {"createLayer", create_layer, 1},
        {"destroyLayer", destroy_layer, 1}, {"sortLayer", sort_layer, 2},
        {"getLayerIndex", get_layer_index, 1},
    };
    for (size_t index = 0; index < sizeof(functions) / sizeof(functions[0]); ++index) {
        JSValue function;
        function = JS_NewCClosure(context, functions[index].function,
                                  functions[index].name, NULL,
                                  functions[index].argc, 0, owner);
        if (JS_IsException(function) || JS_DefinePropertyValueStr(
                context, scene, functions[index].name, function, JS_PROP_ENUMERABLE
            ) < 0) { JS_FreeValue(context, scene); return false; }
    }
    owner->scene_handle = scene;
    return true;
}

void mwx_scene_quickjs_owner_discard_layer_mutations(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL) return;
    for (size_t index = 0; index < owner->authored_layer_mutation_count; ++index) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
            &owner->authored_layer_mutations[index];
        free(mutation->text);
        free(mutation->font);
        *mutation = (MWXSceneQuickJSAuthoredLayerMutationRecord){0};
    }
    owner->authored_layer_mutation_count = 0;
    owner->layer_mutation_count = 0;
    for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (record->dirty && record->dirty_owner_identity == owner->identity) {
            record->dirty = false;
            record->dirty_owner_identity = 0;
        }
    }
}

void mwx_scene_quickjs_owner_begin_layer_mutations(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return;
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    owner->video_command_count = 0;
    owner->video_command_overflow = false;
}

size_t mwx_scene_quickjs_owner_video_command_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner == NULL ? 0 : owner->video_command_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_video_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t requested,
    MWXSceneQuickJSVideoCommand *command,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || command == NULL ||
        requested >= owner->video_command_count ||
        requested >= MWX_SCENE_QUICKJS_MAX_VIDEO_COMMANDS) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid video command index"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *command = owner->video_commands[requested];
    return MWX_SCENE_QUICKJS_OK;
}

bool mwx_scene_quickjs_dispatch_video_ended_callbacks(
    MWXSceneQuickJSOwner *owner
) {
    if (!callback_owns(owner)) return false;
    JSContext *context = owner->domain->context;
    for (size_t index = 0; index < owner->video_ended_callback_count; ++index) {
        MWXSceneQuickJSVideoEndedCallbackRecord *callback =
            &owner->video_ended_callbacks[index];
        if (!callback->active) continue;
        MWXSceneQuickJSLayerRecord *record = NULL;
        for (uint32_t layer = 0; layer < owner->domain->layer_count; ++layer) {
            MWXSceneQuickJSLayerRecord *candidate = &owner->domain->layers[layer];
            if (candidate->configured && !candidate->destroyed &&
                candidate->layer_id == callback->layer_id &&
                candidate->video_available) {
                record = candidate;
                break;
            }
        }
        if (record == NULL ||
            record->video_ended_generation <= callback->delivered_generation)
            continue;
        JSValue result = JS_Call(
            context, callback->callback, owner->module, 0, NULL
        );
        if (JS_IsException(result)) {
            JS_FreeValue(context, result);
            return false;
        }
        JS_FreeValue(context, result);
        callback->delivered_generation = record->video_ended_generation;
    }
    return true;
}

void mwx_scene_quickjs_clear_video_ended_callbacks(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL ||
        owner->domain->context == NULL) return;
    for (size_t index = 0; index < owner->video_ended_callback_count; ++index) {
        MWXSceneQuickJSVideoEndedCallbackRecord *callback =
            &owner->video_ended_callbacks[index];
        if (callback->active) {
            JS_FreeValue(owner->domain->context, callback->callback);
            callback->active = false;
        }
    }
    owner->video_ended_callback_count = 0;
}

void mwx_scene_quickjs_owner_remove_dynamic_layers(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return;
    MWXSceneQuickJSDomain *domain = owner->domain;
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(owner);
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        if (!record->configured || !record->dynamic ||
            record->owner_identity != owner->identity) continue;
        record->destroyed = true;
        record->dirty = false;
        record->dirty_owner_identity = 0;
    }
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        if (!record->configured || record->destroyed) continue;
        int32_t order = 0;
        for (uint32_t candidate = 0; candidate < domain->layer_count; ++candidate) {
            MWXSceneQuickJSLayerRecord *other = &domain->layers[candidate];
            if (!other->configured || other->destroyed || other == record) continue;
            if (other->order_index < record->order_index ||
                (other->order_index == record->order_index && candidate < index)) {
                order += 1;
            }
        }
        record->order_index = order;
    }
    owner->authored_layer_baseline_available = false;
}

size_t mwx_scene_quickjs_owner_layer_mutation_count(const MWXSceneQuickJSOwner *owner) {
    return owner == NULL || owner->disabled ? 0 : owner->layer_mutation_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_layer_mutation_at(
    MWXSceneQuickJSOwner *owner, size_t requested,
    MWXSceneQuickJSLayerMutation *mutation,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->disabled || mutation == NULL ||
        requested >= owner->layer_mutation_count) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid layer mutation index");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (requested < owner->authored_layer_mutation_count) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *staged =
            &owner->authored_layer_mutations[requested];
        if (staged->layer_index >= owner->domain->authored_layer_count) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "invalid authored layer mutation target"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
        MWXSceneQuickJSLayerRecord *record =
            &owner->domain->layers[staged->layer_index];
        *mutation = (MWXSceneQuickJSLayerMutation){
            .kind = MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
            .dynamic = 0,
            .fields = staged->fields,
            .layer_id = record->layer_id,
            .order_index = record->order_index,
            .visible = staged->visible,
            .alpha = record->alpha,
            .point_size = record->point_size,
            .text = (staged->fields &
                     MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0
                ? staged->text
                : (record->text == NULL ? "" : record->text),
            .font = (staged->fields &
                     MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT) != 0
                ? staged->font
                : (record->font == NULL ? "" : record->font),
            .asset_path = record->asset_path == NULL ? "" : record->asset_path,
        };
        memcpy(mutation->origin, staged->origin, sizeof(mutation->origin));
        memcpy(mutation->scale, staged->scale, sizeof(mutation->scale));
        memcpy(mutation->angles, staged->angles, sizeof(mutation->angles));
        memcpy(mutation->color, record->color, sizeof(mutation->color));
        return MWX_SCENE_QUICKJS_OK;
    }
    requested -= owner->authored_layer_mutation_count;
    size_t found = 0;
    for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (!record->dirty || record->dirty_owner_identity != owner->identity) continue;
        if (found++ != requested) continue;
        *mutation = (MWXSceneQuickJSLayerMutation){
            .kind = record->destroyed ? MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY
                                      : MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
            .dynamic = record->dynamic, .fields = 0, .layer_id = record->layer_id,
            .order_index = record->order_index, .visible = record->visible,
            .alpha = record->alpha, .point_size = record->point_size,
            .text = record->text == NULL ? "" : record->text,
            .font = record->font == NULL ? "" : record->font,
            .asset_path = record->asset_path == NULL ? "" : record->asset_path,
        };
        memcpy(mutation->origin, record->current_origin, sizeof(mutation->origin));
        memcpy(mutation->scale, record->scale, sizeof(mutation->scale));
        memcpy(mutation->angles, record->angles, sizeof(mutation->angles));
        memcpy(mutation->color, record->color, sizeof(mutation->color));
        return MWX_SCENE_QUICKJS_OK;
    }
    return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_layer_catalog(
    MWXSceneQuickJSDomain *domain, uint32_t layer_count,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers != NULL || layer_count > MWX_SCENE_QUICKJS_MAX_LAYERS) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid layer catalog");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    domain->layers = calloc(MWX_SCENE_QUICKJS_MAX_LAYERS, sizeof(*domain->layers));
    if (domain->layers == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    domain->layer_count = layer_count; domain->authored_layer_count = layer_count;
    return MWX_SCENE_QUICKJS_OK;
}

static char *copy_string(const char *source, size_t length) {
    char *copy = malloc(length + 1); if (copy == NULL) return NULL;
    if (length > 0) memcpy(copy, source, length); copy[length] = '\0'; return copy;
}

static bool valid_layer_identity(int64_t identity) {
    return identity >= -9007199254740991LL &&
        identity <= 9007199254740991LL;
}

static bool validate_complete_layer_catalog(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index)
        if (!domain->layers[index].configured) return true;
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        for (uint32_t candidate = index + 1;
             candidate < domain->authored_layer_count; ++candidate) {
            if (domain->layers[candidate].layer_id == record->layer_id) {
                mwx_scene_quickjs_write_diagnostic(
                    diagnostic, diagnostic_capacity,
                    "duplicate authored layer identity"
                );
                return false;
            }
        }
        if (!record->has_parent) continue;
        bool parent_found = false;
        for (uint32_t candidate = 0;
             candidate < domain->authored_layer_count; ++candidate) {
            MWXSceneQuickJSLayerRecord *parent = &domain->layers[candidate];
            if (candidate != index && parent->layer_id == record->parent_id) {
                parent_found = true;
                break;
            }
        }
        if (!parent_found) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "invalid authored parent identity"
            );
            return false;
        }
    }
    return true;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_runtime_descriptor(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index, int64_t layer_id,
    uint32_t has_parent, int64_t parent_id,
    const char *name, size_t name_length, const double origin[3],
    const double scale[3], const double angles[3], uint32_t visible, double alpha,
    const char *text, size_t text_length, const char *font, size_t font_length,
    double point_size, const double color[3], char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || layer_index >= domain->authored_layer_count || name == NULL ||
        text == NULL || font == NULL || name_length > MWX_SCENE_QUICKJS_MAX_LAYER_NAME ||
        text_length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT || font_length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT ||
        origin == NULL || scale == NULL || angles == NULL || color == NULL ||
        has_parent > 1 || !valid_layer_identity(layer_id) ||
        (has_parent && (!valid_layer_identity(parent_id) || parent_id == layer_id)) ||
        !isfinite(alpha) || !isfinite(point_size) || domain->layers[layer_index].configured)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (size_t i = 0; i < 3; ++i)
        if (!isfinite(origin[i]) || !isfinite(scale[i]) || !isfinite(angles[i]) || !isfinite(color[i]))
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSLayerRecord *record = &domain->layers[layer_index];
    record->name = copy_string(name, name_length); record->text = copy_string(text, text_length);
    record->font = copy_string(font, font_length);
    if (record->name == NULL || record->text == NULL || record->font == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    record->layer_id = layer_id; record->parent_id = parent_id;
    record->has_parent = has_parent != 0;
    memcpy(record->authored_origin, origin, sizeof(record->authored_origin));
    memcpy(record->current_origin, origin, sizeof(record->current_origin));
    memcpy(record->scale, scale, sizeof(record->scale)); memcpy(record->angles, angles, sizeof(record->angles));
    memcpy(record->color, color, sizeof(record->color)); record->visible = visible != 0;
    record->alpha = alpha; record->point_size = point_size; record->order_index = (int32_t)layer_index;
    record->configured = true;
    return validate_complete_layer_catalog(
        domain, diagnostic, diagnostic_capacity
    ) ? MWX_SCENE_QUICKJS_OK : MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_mutation_capabilities(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    uint32_t text_mutable,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || text_mutable > 1 ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid authored layer mutation capabilities"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    domain->layers[layer_index].text_mutable = text_mutable != 0;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_descriptor(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index, int64_t layer_id,
    uint32_t has_parent, int64_t parent_id,
    const char *name, size_t name_length, const double origin[3],
    char *diagnostic, size_t diagnostic_capacity
) {
    static const double scale[3] = {1, 1, 1};
    static const double angles[3] = {0, 0, 0};
    static const double color[3] = {1, 1, 1};
    return mwx_scene_quickjs_domain_set_layer_runtime_descriptor(
        domain, layer_index, layer_id, has_parent, parent_id,
        name, name_length, origin,
        scale, angles, 1, 1, "", 0, "", 0, 32, color,
        diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_layer_identity(
    MWXSceneQuickJSOwner *owner, int64_t layer_id,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->target_layer_configured || owner->domain->callback_active)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (uint32_t index = 0; index < owner->domain->authored_layer_count; ++index)
        if (owner->domain->layers[index].configured && owner->domain->layers[index].layer_id == layer_id) {
            owner->target_layer_index = index; owner->target_layer_configured = true;
            return MWX_SCENE_QUICKJS_OK;
        }
    return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_authored_layer_baseline(
    MWXSceneQuickJSOwner *owner, uint64_t expected_generation,
    const double origin[3], const double scale[3], const double angles[3],
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->domain == NULL || origin == NULL || scale == NULL ||
        angles == NULL || owner->domain->callback_active ||
        !owner->target_layer_configured) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid authored layer baseline"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->generation != expected_generation) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "stale SceneScript owner generation"
        );
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    for (size_t index = 0; index < 3; ++index) {
        if (!isfinite(origin[index]) || !isfinite(scale[index]) ||
            !isfinite(angles[index])) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "non-finite authored layer baseline"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    memcpy(owner->authored_layer_baseline_origin, origin, sizeof(double) * 3);
    memcpy(owner->authored_layer_baseline_scale, scale, sizeof(double) * 3);
    memcpy(owner->authored_layer_baseline_angles, angles, sizeof(double) * 3);
    owner->authored_layer_baseline_available = true;
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_owner_clear_authored_layer_baseline(
    MWXSceneQuickJSOwner *owner
) {
    if (owner != NULL) owner->authored_layer_baseline_available = false;
}

void mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL) return;
    for (size_t index = 0;
         index < owner->authored_layer_mutation_baseline_count; ++index) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
            &owner->authored_layer_mutation_baselines[index];
        free(baseline->text);
        free(baseline->font);
        *baseline = (MWXSceneQuickJSAuthoredLayerMutationRecord){0};
    }
    owner->authored_layer_mutation_baseline_count = 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_add_authored_layer_mutation_baseline(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    int64_t layer_id,
    uint32_t fields,
    const double origin[3],
    const double scale[3],
    const double angles[3],
    uint32_t visible,
    const char *text,
    size_t text_length,
    const char *font,
    size_t font_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    const uint32_t supported_fields =
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT;
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->domain == NULL || owner->disabled ||
        owner->domain->callback_active || owner->generation != expected_generation ||
        fields == 0 || (fields & ~supported_fields) != 0 || visible > 1 ||
        origin == NULL || scale == NULL || angles == NULL || text == NULL ||
        font == NULL ||
        text_length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT ||
        font_length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT ||
        memchr(text, '\0', text_length) != NULL ||
        memchr(font, '\0', font_length) != NULL ||
        owner->authored_layer_mutation_baseline_count >=
            MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid authored layer mutation baseline"
        );
        return owner != NULL && owner->generation != expected_generation
            ? MWX_SCENE_QUICKJS_STALE_OWNER
            : MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (size_t index = 0; index < 3; ++index) {
        if (!isfinite(origin[index]) || !isfinite(scale[index]) ||
            !isfinite(angles[index])) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "non-finite authored layer mutation baseline"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    uint32_t layer_index = UINT32_MAX;
    for (uint32_t index = 0; index < owner->domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (record->configured && !record->destroyed &&
            record->layer_id == layer_id) {
            layer_index = index;
            break;
        }
    }
    if (layer_index == UINT32_MAX ||
        ((fields & (MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT |
                    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT)) != 0 &&
         !owner->domain->layers[layer_index].text_mutable)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "authored layer mutation baseline target is invalid"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (authored_mutation_baseline_for_layer(owner, layer_index) != NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "duplicate authored layer mutation baseline target"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char *text_copy = NULL;
    char *font_copy = NULL;
    if ((fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0) {
        text_copy = malloc(text_length + 1);
        if (text_copy == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        memcpy(text_copy, text, text_length);
        text_copy[text_length] = '\0';
    }
    if ((fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT) != 0) {
        if (!valid_asset_path(font, font_length)) {
            free(text_copy);
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
        font_copy = malloc(font_length + 1);
        if (font_copy == NULL) {
            free(text_copy);
            return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        }
        memcpy(font_copy, font, font_length);
        font_copy[font_length] = '\0';
    }
    MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
        &owner->authored_layer_mutation_baselines[
            owner->authored_layer_mutation_baseline_count++
        ];
    *baseline = (MWXSceneQuickJSAuthoredLayerMutationRecord){
        .layer_index = layer_index,
        .fields = fields,
        .visible = visible != 0,
        .text = text_copy,
        .font = font_copy,
    };
    memcpy(baseline->origin, origin, sizeof(baseline->origin));
    memcpy(baseline->scale, scale, sizeof(baseline->scale));
    memcpy(baseline->angles, angles, sizeof(baseline->angles));
    return MWX_SCENE_QUICKJS_OK;
}
