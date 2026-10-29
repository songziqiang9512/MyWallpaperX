#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

JSValue mwx_scene_quickjs_layer_make_vec3(JSContext *context, MWXSceneQuickJSDomain *domain, const double v[3]) {
    JSValue arguments[3] = {
        JS_NewFloat64(context, v[0]), JS_NewFloat64(context, v[1]),
        JS_NewFloat64(context, v[2]),
    };
    JSValue result = JS_CallConstructor(context, domain->vec3_constructor, 3, arguments);
    for (size_t index = 0; index < 3; ++index) JS_FreeValue(context, arguments[index]);
    return result;
}

static JSValue make_vec2(
    JSContext *context, MWXSceneQuickJSDomain *domain, const double v[2]
) {
    JSValue arguments[2] = {
        JS_NewFloat64(context, v[0]), JS_NewFloat64(context, v[1]),
    };
    JSValue result = JS_CallConstructor(
        context, domain->vec2_constructor, 2, arguments
    );
    for (size_t index = 0; index < 2; ++index)
        JS_FreeValue(context, arguments[index]);
    return result;
}

bool mwx_scene_quickjs_layer_read_vec3(
    JSContext *context, JSValueConst value, double output[3],
    bool *numeric_nonfinite
) {
    static const char *names[3] = {"x", "y", "z"};
    if (numeric_nonfinite != NULL) *numeric_nonfinite = false;
    for (size_t index = 0; index < 3; ++index) {
        JSValue component = JS_GetPropertyStr(context, value, names[index]);
        const bool converted = !JS_IsException(component) &&
            JS_ToFloat64(context, &output[index], component) >= 0;
        const bool reject_assignment = converted &&
            !isfinite(output[index]) && JS_IsNumber(component) &&
            numeric_nonfinite != NULL;
        JS_FreeValue(context, component);
        if (!converted) return false;
        if (reject_assignment) {
            // Read remaining components: malformed values and getter errors
            // must still fail the callback, even after a numeric NaN/Infinity.
            *numeric_nonfinite = true;
        } else if (!isfinite(output[index])) {
            return false;
        }
    }
    return true;
}

const double *mwx_scene_quickjs_layer_authored_transform_value(
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

static MWXSceneQuickJSLayerAccessHandle *layer_handle_for_receiver(
    JSValueConst receiver, MWXSceneQuickJSLayerAccessHandle *captured,
    enum MWXSceneQuickJSLayerAccessScope *scope
) {
    *scope = MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND;
    if (captured == NULL || captured->domain == NULL) return captured;
    MWXSceneQuickJSLayerAccessHandle *reference = JS_GetOpaque(
        receiver, captured->domain->layer_handle_class_id
    );
    if (reference != NULL) {
        *scope = MWX_SCENE_QUICKJS_LAYER_AUTHORED_REFERENCE;
        return reference->domain == captured->domain ? reference : NULL;
    }
    return captured;
}

static JSValue layer_get(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)argc; (void)argv;
    enum MWXSceneQuickJSLayerAccessScope scope;
    MWXSceneQuickJSLayerAccessHandle *handle = layer_handle_for_receiver(this_value, opaque, &scope);
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, scope);
    if (record == NULL) return JS_ThrowTypeError(context, "layer handle is stale");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    const uint32_t record_index = (uint32_t)(record - handle->domain->layers);
    MWXSceneQuickJSAuthoredLayerMutationRecord *authored_mutation =
        !record->dynamic ? mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index) : NULL;
    MWXSceneQuickJSAuthoredLayerMutationRecord *authored_baseline =
        !record->dynamic
            ? mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index) : NULL;
    switch ((enum LayerProperty)magic) {
    case LAYER_ORIGIN:
        return mwx_scene_quickjs_layer_make_vec3(
            context, handle->domain,
            !record->dynamic ? mwx_scene_quickjs_layer_authored_transform_value(
                owner, authored_mutation, authored_baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN,
                authored_mutation == NULL ? record->current_origin
                                          : authored_mutation->origin,
                record->current_origin
            ) : record->current_origin
        );
    case LAYER_SIZE:
        return record->dynamic && !record->size_available
            ? JS_UNDEFINED
            : make_vec2(context, handle->domain, record->size);
    case LAYER_SCALE:
        return mwx_scene_quickjs_layer_make_vec3(
            context, handle->domain,
            !record->dynamic ? mwx_scene_quickjs_layer_authored_transform_value(
                owner, authored_mutation, authored_baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE,
                authored_mutation == NULL ? record->scale
                                          : authored_mutation->scale,
                record->scale
            ) : record->scale
        );
    case LAYER_ANGLES:
        return mwx_scene_quickjs_layer_make_vec3(
            context, handle->domain,
            !record->dynamic ? mwx_scene_quickjs_layer_authored_transform_value(
                owner, authored_mutation, authored_baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES,
                authored_mutation == NULL ? record->angles
                                          : authored_mutation->angles,
                record->angles
            ) : record->angles
        );
    case LAYER_PERSPECTIVE: {
        uint32_t value = record->perspective;
        if (authored_mutation != NULL && (authored_mutation->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE) != 0)
            value = authored_mutation->perspective;
        else if (authored_baseline != NULL && (authored_baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE) != 0)
            value = authored_baseline->perspective;
        return JS_NewBool(context, value == 2 ? handle->domain->defaults_to_perspective : value != 0);
    }
    case LAYER_VISIBLE:
    case LAYER_SOLID: {
        const bool solid = (enum LayerProperty)magic == LAYER_SOLID;
        const uint32_t field = solid ? MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SOLID
                                    : MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY;
        if (authored_mutation != NULL && (authored_mutation->fields & field) != 0)
            return JS_NewBool(context, solid ? authored_mutation->solid : authored_mutation->visible);
        if (authored_baseline != NULL && (authored_baseline->fields & field) != 0)
            return JS_NewBool(context, solid ? authored_baseline->solid : authored_baseline->visible);
        return JS_NewBool(context, solid ? record->solid : record->visible);
    }
    case LAYER_ALPHA:
        return JS_NewFloat64(context,
            authored_mutation != NULL && (authored_mutation->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA)
                ? authored_mutation->alpha
                : authored_baseline != NULL && (authored_baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA)
                    ? authored_baseline->alpha : record->alpha);
    case LAYER_COLOR:
        return mwx_scene_quickjs_layer_make_vec3(context, handle->domain,
            authored_mutation != NULL && (authored_mutation->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR)
                ? authored_mutation->color
                : authored_baseline != NULL && (authored_baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR)
                    ? authored_baseline->color : record->color);
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
    case LAYER_POINT_SIZE:
        return JS_NewFloat64(context,
            authored_mutation != NULL && (authored_mutation->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE)
                ? authored_mutation->point_size
                : authored_baseline != NULL && (authored_baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE)
                    ? authored_baseline->point_size : record->point_size);
    case LAYER_FONT: {
        const char *font = !record->dynamic
            ? authored_font_value(authored_mutation, authored_baseline, record)
            : (record->font == NULL ? "" : record->font);
        return font[0] == '\0'
            ? JS_UNDEFINED
            : JS_NewString(context, font);
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
    enum MWXSceneQuickJSLayerAccessScope scope;
    MWXSceneQuickJSLayerAccessHandle *handle = layer_handle_for_receiver(this_value, opaque, &scope);
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, scope);
    if (record == NULL || argc != 1) {
        return JS_ThrowTypeError(context, "layer mutation target is not an owned dynamic layer");
    }
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    const uint32_t record_index = (uint32_t)(record - handle->domain->layers);
    const bool value_owner_target_visibility = owner->value_only &&
        (enum LayerProperty)magic == LAYER_VISIBLE &&
        owner->target_layer_configured &&
        record_index == owner->target_layer_index && !record->dynamic;
    if (owner->value_only && !value_owner_target_visibility) {
        return JS_ThrowTypeError(
            context,
            "Boolean value owner may only write its target visibility"
        );
    }
    const bool dynamic_target = mwx_scene_quickjs_layer_owns_dynamic_target(owner, record);
    const bool authored_target = !record->dynamic && !owner->value_only;
    const bool value_authored_target = !record->dynamic &&
        value_owner_target_visibility;
    if (!dynamic_target && !authored_target && !value_authored_target)
        return JS_ThrowTypeError(context, "layer mutation target is not owned by this script");

    switch ((enum LayerProperty)magic) {
    case LAYER_ORIGIN: {
        double value[3];
        bool numeric_nonfinite;
        if (!mwx_scene_quickjs_layer_read_vec3(context, argv[0], value, &numeric_nonfinite))
            return JS_ThrowTypeError(context, "layer origin expects finite Vec3");
        if (numeric_nonfinite) return JS_UNDEFINED;
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index);
            const double *current = mwx_scene_quickjs_layer_authored_transform_value(
                owner, mutation, baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN,
                mutation == NULL ? record->current_origin : mutation->origin,
                record->current_origin
            );
            if (memcmp(value, current, sizeof(value)) == 0) break;
            mutation = mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            memcpy(mutation->origin, value, sizeof(value));
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN;
            break;
        }
        if (memcmp(value, record->current_origin, sizeof(value)) == 0) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->current_origin, value, sizeof(value));
        break;
    }
    case LAYER_SCALE: {
        double value[3];
        bool numeric_nonfinite;
        if (!mwx_scene_quickjs_layer_read_vec3(context, argv[0], value, &numeric_nonfinite))
            return JS_ThrowTypeError(context, "layer scale expects finite Vec3");
        if (numeric_nonfinite) return JS_UNDEFINED;
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index);
            const double *current = mwx_scene_quickjs_layer_authored_transform_value(
                owner, mutation, baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE,
                mutation == NULL ? record->scale : mutation->scale,
                record->scale
            );
            if (memcmp(value, current, sizeof(value)) == 0) break;
            mutation = mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            memcpy(mutation->scale, value, sizeof(value));
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE;
            break;
        }
        if (memcmp(value, record->scale, sizeof(value)) == 0) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->scale, value, sizeof(value));
        break;
    }
    case LAYER_ANGLES: {
        double value[3];
        bool numeric_nonfinite;
        if (!mwx_scene_quickjs_layer_read_vec3(context, argv[0], value, &numeric_nonfinite))
            return JS_ThrowTypeError(context, "layer angles expects finite Vec3");
        if (numeric_nonfinite) return JS_UNDEFINED;
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index);
            const double *current = mwx_scene_quickjs_layer_authored_transform_value(
                owner, mutation, baseline, record_index,
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES,
                mutation == NULL ? record->angles : mutation->angles,
                record->angles
            );
            if (memcmp(value, current, sizeof(value)) == 0) {
                // Preserve an authored setter invocation even when the value
                // equals the current frame.  Some official scripts publish
                // their typed value through thisLayer.angles while returning
                // a text payload; the mutation journal is the ABI signal that
                // the return payload must not be decoded as Vec3.
                mutation = mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
                if (mutation == NULL)
                    return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
                mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES;
                break;
            }
            mutation = mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            memcpy(mutation->angles, value, sizeof(value));
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES;
            break;
        }
        if (memcmp(value, record->angles, sizeof(value)) == 0) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->angles, value, sizeof(value));
        break;
    }
    case LAYER_PERSPECTIVE: {
        // The public Boolean field ignores non-Boolean assignments in the
        // fixed official probe; JS truthiness would turn 1 or "false" into true.
        if (!JS_IsBool(argv[0])) return JS_UNDEFINED;
        const uint32_t value = JS_ToBool(context, argv[0]) != 0;
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index);
            const uint32_t current = mutation != NULL && (mutation->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE) != 0
                ? mutation->perspective
                : baseline != NULL && (baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE) != 0
                    ? baseline->perspective : record->perspective;
            if (current != 2 && current == value) break;
            mutation = mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            mutation->perspective = value;
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE;
            break;
        }
        if (record->perspective == value) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        record->perspective = value;
        break;
    }
    case LAYER_VISIBLE:
    case LAYER_SOLID: {
        int value = JS_ToBool(context, argv[0]);
        if (value < 0) return JS_EXCEPTION;
        const bool solid = (enum LayerProperty)magic == LAYER_SOLID;
        const uint32_t field = solid ? MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SOLID
                                    : MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY;
        bool *record_value = solid ? &record->solid : &record->visible;
        if (authored_target || value_authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index);
            MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
                mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index);
            const bool current = mutation != NULL && (mutation->fields & field) != 0
                ? (solid ? mutation->solid : mutation->visible)
                : baseline != NULL && (baseline->fields & field) != 0
                    ? (solid ? baseline->solid : baseline->visible) : *record_value;
            if (current == (value != 0)) break;
            mutation = mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            *(solid ? &mutation->solid : &mutation->visible) = value != 0;
            mutation->fields |= field;
            break;
        }
        if (*record_value == (value != 0)) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        *record_value = value != 0;
        break;
    }
    case LAYER_ALPHA: {
        // The property retains its raw value; display opacity is normalized downstream.
        double value = 0;
        if (JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value))
            return JS_ThrowRangeError(
                context, "layer alpha expects a finite number"
            );
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            mutation->alpha = value;
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA;
            break;
        }
        if (record->alpha == value) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        record->alpha = value;
        break;
    }
    case LAYER_COLOR: {
        double value[3];
        if (!mwx_scene_quickjs_layer_read_vec3(context, argv[0], value, NULL) ||
            value[0] < 0 || value[0] > 1 || value[1] < 0 || value[1] > 1 ||
            value[2] < 0 || value[2] > 1)
            return JS_ThrowRangeError(
                context, "dynamic layer color expects a normalized finite Vec3"
            );
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            memcpy(mutation->color, value, sizeof(value));
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR;
            break;
        }
        if (memcmp(value, record->color, sizeof(value)) == 0) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        memcpy(record->color, value, sizeof(value));
        break;
    }
    case LAYER_POINT_SIZE: {
        if ((!record->dynamic && !record->text_mutable) ||
            (record->dynamic && record->asset_path != NULL && record->asset_path[0] != '\0'))
            return JS_ThrowTypeError(context, "layer pointsize mutation target is not a text layer");
        double value;
        if (!JS_IsNumber(argv[0]) || JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value))
            return JS_ThrowTypeError(context, "layer pointsize expects finite Number");
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL)
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            mutation->point_size = value;
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE;
            break;
        }
        if (value == record->point_size) break;
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index))
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record))
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        record->point_size = value;
        record->dirty_fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE;
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
            authored_target ? mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index) : NULL;
        MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
            authored_target
                ? mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index) : NULL;
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
            mutation = mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
            if (mutation == NULL) {
                free(copy);
                return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
            }
            free(mutation->text);
            mutation->text = copy;
            mutation->fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT;
            break;
        }
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index)) {
            free(copy);
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        }
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record)) {
            free(copy);
            return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
        }
        free(record->text); record->text = copy;
        record->dirty_fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT;
        break;
    }
    case LAYER_FONT: {
        if (!record->text_mutable && !record->dynamic && !record->image_font_script_state)
            return JS_ThrowTypeError(
                context, "layer font mutation target is not a text layer"
            );
        size_t length = 0;
        const char *value = mwx_scene_quickjs_layer_read_font_path(context, argv[0], &length);
        if (value == NULL) return JS_EXCEPTION;
        const char *current = authored_target
            ? authored_font_value(
                mwx_scene_quickjs_authored_mutation_for_layer(owner, record_index),
                mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, record_index),
                record
            )
            : (record->font == NULL ? "" : record->font);
        if (strcmp(current, value) == 0) {
            JS_FreeCString(context, value);
            break;
        }
        char *copy = malloc(length + 1);
        if (copy != NULL) memcpy(copy, value, length + 1);
        JS_FreeCString(context, value);
        if (copy == NULL) return JS_ThrowOutOfMemory(context);
        if (record->image_font_script_state) {
            // Authored image font is script state, not a native text mutation.
            // Keep the target-layer value across fresh handles and snapshots;
            // native owner acceptance/rollback must not overwrite another writer.
            free(record->font);
            record->font = copy;
            break;
        }
        if (authored_target) {
            MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
                mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
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
        if (!mwx_scene_quickjs_layer_journal_dynamic_layer_value(owner, record_index)) {
            free(copy);
            return JS_ThrowInternalError(context, "dynamic layer rollback journal exceeded");
        }
        if (!mwx_scene_quickjs_layer_mark_dirty(owner, record)) {
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

bool mwx_scene_quickjs_layer_define_property(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent,
    const char *name, enum LayerProperty property, bool writable
) {
    MWXSceneQuickJSLayerAccessHandle *getter_handle = calloc(1, sizeof(*getter_handle));
    MWXSceneQuickJSLayerAccessHandle *setter_handle = writable
        ? calloc(1, sizeof(*setter_handle)) : NULL;
    if (getter_handle == NULL || (writable && setter_handle == NULL)) {
        free(getter_handle); free(setter_handle);
        JS_ThrowOutOfMemory(context); return false;
    }
    *getter_handle = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index,
        .expected_layer_id = owner_target ? 0 : owner->domain->layers[index].layer_id,
        .callback_epoch = owner->domain->callback_epoch,
        .owner_target = owner_target, .persistent = persistent,
    };
    if (setter_handle != NULL) *setter_handle = *getter_handle;
    JSValue getter = mwx_scene_quickjs_layer_access_closure(
        context, layer_get, name, 0, property, getter_handle
    );
    if (JS_IsException(getter)) { free(setter_handle); return false; }
    JSValue setter = writable ? mwx_scene_quickjs_layer_access_closure(
        context, layer_set, name, 1, property, setter_handle
    ) : JS_UNDEFINED;
    if (JS_IsException(setter)) { JS_FreeValue(context, getter); return false; }
    JSAtom atom = JS_NewAtom(context, name);
    if (atom == JS_ATOM_NULL) {
        JS_FreeValue(context, getter); JS_FreeValue(context, setter); return false;
    }
    int result = JS_DefinePropertyGetSet(
        context, layer, atom, getter, setter, JS_PROP_ENUMERABLE
    );
    JS_FreeAtom(context, atom);
    return result >= 0;
}
