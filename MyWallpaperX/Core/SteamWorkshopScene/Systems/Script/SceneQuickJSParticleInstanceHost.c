#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdlib.h>

// The instance object borrows the ordinary layer identity. Its scalar writes
// stay in the same owner journal as transform, visibility and text writes.
static void free_instance_handle(void *opaque) {
    free(opaque);
}

static MWXSceneQuickJSLayerAccessHandle *copy_instance_handle(
    const MWXSceneQuickJSLayerAccessHandle *source
) {
    MWXSceneQuickJSLayerAccessHandle *copy = malloc(sizeof(*copy));
    if (copy != NULL) *copy = *source;
    return copy;
}

static MWXSceneQuickJSLayerRecord *instance_record_for_handle(MWXSceneQuickJSLayerAccessHandle *handle) {
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle);
    if (record == NULL || record->dynamic || !record->particle_instance_available) return NULL;
    MWXSceneQuickJSAuthoredLayerMutationRecord *mutation = mwx_scene_quickjs_authored_mutation_for_layer(
        handle->domain->active_owner, (uint32_t)(record - handle->domain->layers));
    return mutation != NULL && mutation->destroyed ? NULL : record;
}

static double particle_alpha_projection(
    MWXSceneQuickJSOwner *owner, uint32_t index,
    const MWXSceneQuickJSLayerRecord *record
) {
    const uint32_t field = MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA;
    MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
        mwx_scene_quickjs_authored_mutation_for_layer(owner, index);
    if (mutation != NULL && (mutation->fields & field) != 0)
        return mutation->particle_alpha;
    MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
        mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, index);
    if (baseline != NULL && (baseline->fields & field) != 0)
        return baseline->particle_alpha;
    return record->particle_alpha;
}

static JSValue instance_alpha_get(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = instance_record_for_handle(handle);
    if (record == NULL)
        return JS_ThrowTypeError(context, "particle instance handle is stale or unavailable");
    return JS_NewFloat64(context, particle_alpha_projection(
        handle->domain->active_owner, (uint32_t)(record - handle->domain->layers), record));
}

static JSValue instance_alpha_set(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = instance_record_for_handle(handle);
    if (record == NULL || argc != 1)
        return JS_ThrowTypeError(context, "particle instance mutation target is stale or unavailable");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    if (owner->value_only)
        return JS_ThrowTypeError(context, "Boolean value owner cannot write particle instance fields");
    double value;
    if (!JS_IsNumber(argv[0]) || JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value))
        return JS_ThrowTypeError(context, "particle instance alpha requires a finite Number");
    MWXSceneQuickJSAuthoredLayerMutationRecord *mutation = mwx_scene_quickjs_stage_authored_mutation(
        owner, (uint32_t)(record - handle->domain->layers));
    if (mutation == NULL)
        return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
    mutation->particle_alpha = value;
    mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA;
    return JS_UNDEFINED;
}

static JSValue instance_get(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = instance_record_for_handle(handle);
    if (record == NULL)
        return JS_ThrowTypeError(context, "particle instance is unavailable for this layer");
    JSValue instance = JS_NewObject(context);
    if (JS_IsException(instance)) return instance;
    MWXSceneQuickJSLayerAccessHandle *getter_handle = copy_instance_handle(handle);
    MWXSceneQuickJSLayerAccessHandle *setter_handle = copy_instance_handle(handle);
    if (getter_handle == NULL || setter_handle == NULL) {
        free(getter_handle); free(setter_handle); JS_FreeValue(context, instance);
        return JS_ThrowInternalError(context, "particle instance handle allocation failed");
    }
    JSValue getter = JS_NewCClosure(context, instance_alpha_get, "alpha",
        free_instance_handle, 0, 0, getter_handle);
    JSValue setter = JS_NewCClosure(context, instance_alpha_set, "alpha",
        free_instance_handle, 1, 0, setter_handle);
    if (JS_IsException(getter) || JS_IsException(setter)) {
        JS_FreeValue(context, getter); JS_FreeValue(context, setter);
        JS_FreeValue(context, instance); return JS_EXCEPTION;
    }
    JSAtom atom = JS_NewAtom(context, "alpha");
    int result = JS_DefinePropertyGetSet(context, instance, atom, getter, setter, JS_PROP_ENUMERABLE);
    JS_FreeAtom(context, atom);
    // SceneScript modules are strict. Sealing prevents unsupported fields from
    // becoming inert JS properties that appear to accept native writes.
    if (result < 0 || JS_PreventExtensions(context, instance) < 0) {
        JS_FreeValue(context, instance); return JS_EXCEPTION;
    }
    return instance;
}

bool mwx_scene_quickjs_define_particle_instance(
    MWXSceneQuickJSOwner *owner, JSValue layer, uint32_t index,
    bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerAccessHandle identity = {
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index, .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    MWXSceneQuickJSLayerAccessHandle *handle = copy_instance_handle(&identity);
    if (handle == NULL) return false;
    JSValue getter = JS_NewCClosure(owner->domain->context, instance_get, "instance",
        free_instance_handle, 0, 0, handle);
    if (JS_IsException(getter)) return false;
    JSAtom atom = JS_NewAtom(owner->domain->context, "instance");
    int result = JS_DefinePropertyGetSet(owner->domain->context, layer, atom,
        getter, JS_UNDEFINED, JS_PROP_ENUMERABLE);
    JS_FreeAtom(owner->domain->context, atom);
    return result >= 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_particle_instance_alpha(
    MWXSceneQuickJSOwner *owner, int64_t layer_id, double *alpha
) {
    if (owner == NULL || owner->domain == NULL || owner->disabled || alpha == NULL ||
        owner->domain->active_owner != owner || !owner->domain->callback_active)
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    if (owner->layer_mutation_overflow) return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
    for (uint32_t index = 0; index < owner->domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (!record->configured || record->destroyed || record->layer_id != layer_id) continue;
        MWXSceneQuickJSAuthoredLayerMutationRecord *mutation = mwx_scene_quickjs_authored_mutation_for_layer(owner, index);
        if (mutation != NULL && mutation->destroyed) return MWX_SCENE_QUICKJS_STALE_OWNER;
        if (!record->particle_instance_available) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        *alpha = particle_alpha_projection(owner, index, record);
        return MWX_SCENE_QUICKJS_OK;
    }
    return MWX_SCENE_QUICKJS_STALE_OWNER;
}
