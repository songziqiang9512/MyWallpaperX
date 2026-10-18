#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static void finalize_layer_handle(JSRuntime *runtime, JSValue value) {
    (void)runtime;
    free(JS_GetOpaque(value, JS_GetClassID(value)));
}

JSValue mwx_scene_quickjs_create_owner_layer_handle(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    // Preserve the former plain receiver's intrinsic Object prototype. The
    // registered native class otherwise starts with a null prototype.
    JSValue prototype_source = JS_NewObject(context);
    if (JS_IsException(prototype_source)) return prototype_source;
    JSValue prototype = JS_GetPrototype(context, prototype_source);
    JS_FreeValue(context, prototype_source);
    if (JS_IsException(prototype)) return prototype;
    MWXSceneQuickJSLayerAccessHandle *identity = calloc(1, sizeof(*identity));
    if (identity == NULL) {
        JS_FreeValue(context, prototype);
        return JS_ThrowOutOfMemory(context);
    }
    *identity = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = true, .persistent = true,
    };
    JSValue layer = JS_NewObjectProtoClass(
        context, prototype, owner->domain->layer_handle_class_id
    );
    JS_FreeValue(context, prototype);
    if (JS_IsException(layer) || JS_SetOpaque(layer, identity) < 0) {
        free(identity);
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    return layer;
}

bool mwx_scene_quickjs_install_layer_handle_class(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL || domain->runtime == NULL ||
        domain->layer_handle_class_id != JS_INVALID_CLASS_ID) return false;
    static const JSClassDef layer_definition = {
        .class_name = "SceneLayerHandle",
        .finalizer = finalize_layer_handle,
    };
    JS_NewClassID(domain->runtime, &domain->layer_handle_class_id);
    return domain->layer_handle_class_id != JS_INVALID_CLASS_ID &&
        JS_NewClass(
            domain->runtime, domain->layer_handle_class_id, &layer_definition
        ) >= 0;
}

bool mwx_scene_quickjs_layer_callback_owns(MWXSceneQuickJSOwner *owner) {
    return owner != NULL && owner->domain != NULL &&
        owner->domain->callback_active && owner->domain->active_owner == owner;
}

bool mwx_scene_quickjs_layer_owns_dynamic_target(MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSLayerRecord *record) {
    return record->dynamic && (record->owner_identity == owner->identity ||
        (record->text_property_owner_identity == owner->identity && owner->target_layer_configured &&
         owner->target_layer_index < owner->domain->layer_count &&
         &owner->domain->layers[owner->target_layer_index] == record));
}

MWXSceneQuickJSLayerRecord *mwx_scene_quickjs_layer_record_for_handle(
    MWXSceneQuickJSLayerAccessHandle *handle,
    enum MWXSceneQuickJSLayerAccessScope scope
) {
    if (handle == NULL || handle->domain == NULL ||
        handle->domain->active_owner == NULL ||
        !mwx_scene_quickjs_layer_callback_owns(handle->domain->active_owner)) {
        return NULL;
    }
    MWXSceneQuickJSDomain *domain = handle->domain;
    MWXSceneQuickJSOwner *owner = domain->active_owner;
    const bool same_owner = owner->identity == handle->owner_identity;
    if (!same_owner && (scope != MWX_SCENE_QUICKJS_LAYER_AUTHORED_REFERENCE ||
        handle->owner_target || !handle->persistent)) return NULL;
    uint32_t index = handle->owner_target
        ? owner->target_layer_index : handle->layer_index;
    if ((handle->owner_target && !owner->target_layer_configured) ||
        index >= domain->layer_count) {
        return NULL;
    }
    MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
    if (!record->configured || record->destroyed) {
        return NULL;
    }
    if (record->dynamic) {
        if (!handle->persistent || !same_owner) {
            return NULL;
        }
    } else if (!handle->owner_target && !handle->persistent &&
               handle->callback_epoch != domain->callback_epoch) {
        return NULL;
    }
    return record;
}

static void free_layer_handle(void *opaque) {
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    if (handle->construction_finalized != NULL)
        *handle->construction_finalized = true;
    free(handle);
}

JSValue mwx_scene_quickjs_layer_access_closure(
    JSContext *context, JSCClosure *function, const char *name,
    int length, int magic, MWXSceneQuickJSLayerAccessHandle *handle
) {
    bool finalized = false;
    handle->construction_finalized = &finalized;
    // Existing ABI callers can retain an already reported VM exception.
    // Separate it from any failure created by this native allocation.
    const bool had_exception = JS_HasException(context);
    JSValue previous_exception = had_exception ? JS_GetException(context) : JS_UNDEFINED;
    JSValue value = JS_NewCClosure(
        context, function, name, free_layer_handle, length, magic, handle
    );
    // JS_NewCClosure's void function-property setup can leave a native
    // allocation exception alongside the returned function object.
    if (!JS_IsException(value) && JS_HasException(context)) {
        JSValue exception = JS_GetException(context);
        JS_FreeValue(context, value);
        JS_Throw(context, exception);
        value = JS_EXCEPTION;
    }
    if (JS_IsException(value)) {
        // Early CClosure allocation failure leaves opaque ownership here;
        // later failure invokes the finalizer before returning JS_EXCEPTION.
        if (!finalized) free(handle);
        JS_FreeValue(context, previous_exception);
    } else {
        handle->construction_finalized = NULL;
        if (had_exception) JS_Throw(context, previous_exception);
    }
    return value;
}

MWXSceneQuickJSOwner *mwx_scene_quickjs_bound_handle_owner(
    JSContext *context, const MWXSceneQuickJSLayerAccessHandle *handle,
    bool module_evaluation
) {
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (handle == NULL || domain == NULL || handle->domain != domain ||
        (module_evaluation ? domain->callback_active : !domain->callback_active))
        return NULL;
    MWXSceneQuickJSOwner *owner = module_evaluation
        ? domain->module_owner : domain->active_owner;
    return owner != NULL && owner->identity == handle->owner_identity ? owner : NULL;
}

JSValue mwx_scene_quickjs_owner_bound_closure(
    MWXSceneQuickJSOwner *owner, JSCClosure *function, const char *name,
    int length, int magic
) {
    MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return JS_ThrowOutOfMemory(owner->domain->context);
    *handle = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .callback_epoch = owner->domain->callback_epoch,
    };
    return mwx_scene_quickjs_layer_access_closure(
        owner->domain->context, function, name, length, magic, handle);
}

static JSValue get_parent(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    if (record == NULL || argc != 0)
        return JS_ThrowTypeError(context, "getParent layer handle is stale");
    if (!record->has_parent) return JS_UNDEFINED;
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    for (uint32_t index = 0; index < handle->domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *parent = &handle->domain->layers[index];
        if (parent->configured && !parent->destroyed &&
            parent->layer_id == record->parent_id) {
            return mwx_scene_quickjs_layer_make_layer_handle(context, owner, index, true);
        }
    }
    return JS_ThrowTypeError(context, "layer parent identity is invalid");
}

/// Children are the layers that name this layer as their parent, in render
/// order. Each child is the same callback-scoped layer handle any other lookup
/// returns, so writes travel the existing owner mutation journal instead of a
/// second object surface.
static JSValue get_children(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    if (record == NULL || argc != 0)
        return JS_ThrowTypeError(context, "getChildren layer handle is stale");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    if (!mwx_scene_quickjs_layer_callback_owns(owner))
        return JS_ThrowTypeError(context, "getChildren is unavailable");
    JSValue result = JS_NewArray(context);
    if (JS_IsException(result)) return result;
    const int32_t count = mwx_scene_quickjs_layer_active_count(handle->domain);
    uint32_t emitted = 0;
    for (int32_t order = 0; order < count; ++order) {
        const int32_t storage = mwx_scene_quickjs_layer_storage_at_order(handle->domain, order);
        if (storage < 0) {
            JS_FreeValue(context, result);
            return JS_ThrowInternalError(
                context, "layer render order is invalid"
            );
        }
        MWXSceneQuickJSLayerRecord *child = &handle->domain->layers[storage];
        if (!child->has_parent || child->parent_id != record->layer_id) continue;
        JSValue layer = mwx_scene_quickjs_layer_make_layer_handle(context, owner, (uint32_t)storage, true);
        if (JS_IsException(layer) || JS_SetPropertyUint32(
                context, result, emitted, layer
            ) < 0) {
            JS_FreeValue(context, result);
            return JS_EXCEPTION;
        }
        emitted += 1;
    }
    return result;
}

static bool define_get_children(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) { JS_ThrowOutOfMemory(context); return false; }
    *handle = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    JSValue function = mwx_scene_quickjs_layer_access_closure(
        context, get_children, "getChildren", 0, 0, handle
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        context, layer, "getChildren", function, JS_PROP_ENUMERABLE
    ) >= 0;
}

static JSValue get_transform_matrix(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    if (record == NULL)
        return JS_ThrowTypeError(
            context, "getTransformMatrix layer handle is stale"
        );
    if (argc != 0)
        return JS_ThrowTypeError(
            context, "getTransformMatrix expects no arguments"
        );
    if (!record->world_transform_available)
        return JS_ThrowTypeError(
            context, "layer world transform is unavailable"
        );
    return mwx_scene_quickjs_layer_make_mat4(context, handle->domain, record->world_transform);
}

static bool define_get_parent(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) { JS_ThrowOutOfMemory(context); return false; }
    *handle = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    JSValue function = mwx_scene_quickjs_layer_access_closure(
        context, get_parent, "getParent", 0, 0, handle
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        context, layer, "getParent", function, JS_PROP_ENUMERABLE
    ) >= 0;
}

static bool define_get_transform_matrix(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) { JS_ThrowOutOfMemory(context); return false; }
    *handle = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    JSValue function = mwx_scene_quickjs_layer_access_closure(
        context, get_transform_matrix, "getTransformMatrix",
        0, 0, handle
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        context, layer, "getTransformMatrix", function, JS_PROP_ENUMERABLE
    ) >= 0;
}

JSValue mwx_scene_quickjs_layer_make_layer_handle(
    JSContext *context, MWXSceneQuickJSOwner *owner, uint32_t index, bool persistent
) {
    if (!mwx_scene_quickjs_layer_callback_owns(owner) || index >= owner->domain->layer_count) {
        return JS_ThrowRangeError(context, "layer target does not exist");
    }
    // Explicit lookup always retains its concrete catalog referent.
    const bool owner_target = false;
    const bool has_owner_bone_target = owner->target_layer_configured &&
        index == owner->target_layer_index;
    MWXSceneQuickJSLayerAccessHandle *identity = calloc(1, sizeof(*identity));
    if (identity == NULL) return JS_EXCEPTION;
    *identity = (MWXSceneQuickJSLayerAccessHandle){
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
        {"size", LAYER_SIZE, false},
        {"angles", LAYER_ANGLES, true}, {"visible", LAYER_VISIBLE, true}, {"solid", LAYER_SOLID, true},
        {"perspective", LAYER_PERSPECTIVE, true},
        {"text", LAYER_TEXT, true}, {"pointsize", LAYER_POINT_SIZE, true},
        {"font", LAYER_FONT, true}, {"id", LAYER_ID, false},
        {"name", LAYER_NAME, false},
    };
    for (size_t field = 0; field < sizeof(fields) / sizeof(fields[0]); ++field) {
        if (!mwx_scene_quickjs_layer_define_property(context, layer, owner, index, owner_target, persistent,
                             fields[field].name, fields[field].property,
                             fields[field].writable)) {
            JS_FreeValue(context, layer); return JS_EXCEPTION;
        }
    }
    if (!mwx_scene_quickjs_layer_define_property(
            context, layer, owner, index, owner_target, persistent,
            "alpha", LAYER_ALPHA, true
        ) || !mwx_scene_quickjs_layer_define_property(
            context, layer, owner, index, owner_target, persistent,
            "color", LAYER_COLOR, true
        )) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_define_layer_effect_access(owner, layer, index)) {
        JS_FreeValue(context, layer); return JS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_define_layer_animation_accessor(owner, layer, index, false)) {
        JS_FreeValue(context, layer); return JS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_layer_define_get_video_texture(
            context, layer, owner, index, owner_target, persistent
        )) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_define_particle_instance(owner, layer, index, owner_target, persistent)) {
        JS_FreeValue(context, layer); return JS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_layer_define_layer_playback(context, layer, owner, index, owner_target, persistent)) {
        JS_FreeValue(context, layer); return JS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_layer_define_get_texture_animation(
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
    if (!define_get_children(
            context, layer, owner, index, owner_target, persistent
        )) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    if (!define_get_transform_matrix(
            context, layer, owner, index, owner_target, persistent
        )) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    if (!mwx_scene_quickjs_layer_define_puppet_bone_functions(
            context, layer, owner, index, has_owner_bone_target, persistent
        )) {
        JS_FreeValue(context, layer);
        return JS_EXCEPTION;
    }
    return layer;
}

MWXSceneQuickJSLayerRecord *mwx_scene_quickjs_layer_resolve_layer_argument(
    JSContext *context, MWXSceneQuickJSOwner *owner, JSValueConst value
) {
    if (!mwx_scene_quickjs_layer_callback_owns(owner)) return NULL;
    if (JS_IsStrictEqual(context, value, owner->material_function_layer)) {
        MWXSceneQuickJSLayerAccessHandle target = {
            .domain = owner->domain,
            .owner_identity = owner->identity,
            .callback_epoch = owner->domain->callback_epoch,
            .owner_target = true,
            .persistent = true,
        };
        return mwx_scene_quickjs_layer_record_for_handle(&target, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    }
    MWXSceneQuickJSLayerAccessHandle *handle = JS_GetOpaque(
        value, owner->domain->layer_handle_class_id
    );
    return mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
}

bool mwx_scene_quickjs_install_layer_handles(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return false;
    JSContext *context = owner->domain->context;
    if (!mwx_scene_quickjs_define_layer_animation_accessor(
            owner, owner->material_function_layer, UINT32_MAX, false
        )) return false;
    if (!mwx_scene_quickjs_define_puppet_animation_lookup(owner, owner->material_function_layer)) return false;
    const struct { const char *name; enum LayerProperty property; bool writable; } fields[] = {
        {"origin", LAYER_ORIGIN, true}, {"scale", LAYER_SCALE, true},
        {"size", LAYER_SIZE, false},
        {"angles", LAYER_ANGLES, true}, {"visible", LAYER_VISIBLE, true}, {"solid", LAYER_SOLID, true},
        {"perspective", LAYER_PERSPECTIVE, true},
        {"text", LAYER_TEXT, true}, {"pointsize", LAYER_POINT_SIZE, true},
        {"font", LAYER_FONT, true}, {"id", LAYER_ID, false}, {"name", LAYER_NAME, false},
    };
    for (size_t field = 0; field < sizeof(fields) / sizeof(fields[0]); ++field)
        if (!mwx_scene_quickjs_layer_define_property(context, owner->material_function_layer, owner, 0, true, true,
                             fields[field].name, fields[field].property, fields[field].writable))
            return false;
    // The owner's own layer handle must carry the same writable surface as
    // every looked-up layer handle: a swallowed `thisLayer.alpha = value` is a
    // silent divergence from the reference engine, not a capability boundary.
    if (!mwx_scene_quickjs_layer_define_property(context, owner->material_function_layer, owner, 0, true, true,
                         "alpha", LAYER_ALPHA, true) ||
        !mwx_scene_quickjs_layer_define_property(context, owner->material_function_layer, owner, 0, true, true,
                         "color", LAYER_COLOR, true))
        return false;
    if (!mwx_scene_quickjs_layer_define_get_video_texture(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    if (!mwx_scene_quickjs_define_particle_instance(owner, owner->material_function_layer, 0, true, true)) return false;
    if (!mwx_scene_quickjs_layer_define_layer_playback(context, owner->material_function_layer, owner, 0, true, true)) return false;
    if (!mwx_scene_quickjs_layer_define_get_texture_animation(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    if (!define_get_parent(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    if (!define_get_children(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    if (!define_get_transform_matrix(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    if (!mwx_scene_quickjs_layer_define_puppet_bone_functions(
            context, owner->material_function_layer, owner, 0, true, true
        )) return false;
    return mwx_scene_quickjs_install_scene_layer_handle(owner);
}
