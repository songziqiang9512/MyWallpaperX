#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

MWXSceneQuickJSAuthoredLayerMutationRecord *mwx_scene_quickjs_authored_mutation_for_layer(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    owner = mwx_scene_quickjs_text_transaction_owner(owner);
    for (size_t index = 0; index < owner->authored_layer_mutation_count; ++index) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
            &owner->authored_layer_mutations[index];
        if (mutation->layer_index == layer_index) return mutation;
    }
    return NULL;
}

MWXSceneQuickJSAuthoredLayerMutationRecord *
mwx_scene_quickjs_authored_mutation_baseline_for_layer(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    owner = mwx_scene_quickjs_text_transaction_owner(owner);
    for (size_t index = 0;
         index < owner->authored_layer_mutation_baseline_count; ++index) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
            &owner->authored_layer_mutation_baselines[index];
        if (baseline->layer_index == layer_index) return baseline;
    }
    return NULL;
}

MWXSceneQuickJSAuthoredLayerMutationRecord *mwx_scene_quickjs_stage_authored_mutation(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    owner = mwx_scene_quickjs_text_transaction_owner(owner);
    MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
        mwx_scene_quickjs_authored_mutation_for_layer(owner, layer_index);
    if (mutation != NULL) return mutation;
    if (layer_index >= owner->domain->authored_layer_count) return NULL;
    if (owner->layer_mutation_count >= MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS ||
        owner->authored_layer_mutation_count >= MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS) {
        owner->layer_mutation_overflow = true;
        return NULL;
    }
    MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[layer_index];
    mutation = &owner->authored_layer_mutations[
        owner->authored_layer_mutation_count++
    ];
    *mutation = (MWXSceneQuickJSAuthoredLayerMutationRecord){
        .layer_index = layer_index,
        .visible = record->visible, .solid = record->solid,
        .perspective = record->perspective,
        .alpha = record->alpha,
        .particle_alpha = record->particle_alpha,
        .point_size = record->point_size,
    };
    memcpy(mutation->color, record->color, sizeof(mutation->color));
    memcpy(mutation->origin, record->current_origin, sizeof(mutation->origin));
    memcpy(mutation->scale, record->scale, sizeof(mutation->scale));
    memcpy(mutation->angles, record->angles, sizeof(mutation->angles));
    MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
        mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, layer_index);
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
        if ((baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SOLID) != 0)
            mutation->solid = baseline->solid;
        if ((baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE) != 0)
            mutation->perspective = baseline->perspective;
        if ((baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA) != 0)
            mutation->particle_alpha = baseline->particle_alpha;
        if ((baseline->fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE) != 0)
            mutation->point_size = baseline->point_size;
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

size_t mwx_scene_quickjs_owner_layer_mutation_count(const MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->disabled) return 0;
    // A caught JS exception cannot turn an unsafe, truncated journal into success.
    return owner->layer_mutation_overflow ? SIZE_MAX : owner->layer_mutation_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_layer_mutation_at(
    MWXSceneQuickJSOwner *owner, size_t requested,
    MWXSceneQuickJSLayerMutation *mutation,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner != NULL && owner->layer_mutation_overflow) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "layer mutation buffer exceeded");
        return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
    }
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
            .kind = staged->destroyed
                ? MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY
                : MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
            .dynamic = 0,
            .fields = staged->destroyed ? 0 : staged->fields,
            .effect_count = staged->destroyed || staged->effect_visible == NULL ? 0 : record->effect_count,
            .effect_visible = staged->destroyed ? NULL : staged->effect_visible,
            .layer_id = record->layer_id,
            .order_index = record->order_index,
            .visible = staged->visible, .solid = staged->solid,
            .perspective = staged->perspective,
            .alpha = staged->alpha,
            .particle_alpha = staged->particle_alpha,
            .point_size = staged->point_size,
            .text = (staged->fields &
                     MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0
                ? staged->text
                : (record->text == NULL ? "" : record->text),
            .font = (staged->fields &
                     MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT) != 0
                ? staged->font
                : (record->font == NULL ? "" : record->font),
            .asset_path = record->asset_path == NULL ? "" : record->asset_path,
            .text_template_identity = record->text_template_identity,
        };
        memcpy(mutation->origin, staged->origin, sizeof(mutation->origin));
        memcpy(mutation->scale, staged->scale, sizeof(mutation->scale));
        memcpy(mutation->angles, staged->angles, sizeof(mutation->angles));
        memcpy(mutation->color, staged->color, sizeof(mutation->color));
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
            .dynamic = record->dynamic, .fields = record->dirty_fields, .layer_id = record->layer_id,
            .order_index = record->order_index, .visible = record->visible, .solid = record->solid,
            .perspective = record->perspective,
            .alpha = record->alpha, .point_size = record->point_size,
            .size_available = record->size_available,
            .text = record->text == NULL ? "" : record->text,
            .font = record->font == NULL ? "" : record->font,
            .asset_path = record->asset_path == NULL ? "" : record->asset_path,
            .text_template_identity = record->text_template_identity,
        };
        memcpy(mutation->origin, record->current_origin, sizeof(mutation->origin));
        memcpy(mutation->scale, record->scale, sizeof(mutation->scale));
        memcpy(mutation->angles, record->angles, sizeof(mutation->angles));
        memcpy(mutation->color, record->color, sizeof(mutation->color));
        memcpy(mutation->size, record->size, sizeof(mutation->size));
        return MWX_SCENE_QUICKJS_OK;
    }
    return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_layer_catalog(
    MWXSceneQuickJSDomain *domain, uint32_t layer_count,
    uint32_t defaults_to_perspective,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers != NULL || defaults_to_perspective > 1 || layer_count > MWX_SCENE_QUICKJS_MAX_LAYERS) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid layer catalog");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    domain->layers = calloc(MWX_SCENE_QUICKJS_MAX_LAYERS, sizeof(*domain->layers));
    if (domain->layers == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    domain->layer_count = layer_count; domain->authored_layer_count = layer_count;
    domain->defaults_to_perspective = defaults_to_perspective != 0;
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
    const double size[2],
    const double scale[3], const double angles[3], uint32_t visible, double alpha,
    const char *text, size_t text_length, const char *font, size_t font_length,
    double point_size, const double color[3], char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || layer_index >= domain->authored_layer_count || name == NULL ||
        text == NULL || font == NULL || name_length > MWX_SCENE_QUICKJS_MAX_LAYER_NAME ||
        text_length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT || font_length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT ||
        origin == NULL || size == NULL || scale == NULL || angles == NULL ||
        color == NULL ||
        has_parent > 1 || !valid_layer_identity(layer_id) ||
        (has_parent && (!valid_layer_identity(parent_id) || parent_id == layer_id)) ||
        !isfinite(alpha) || !isfinite(point_size) || domain->layers[layer_index].configured)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (size_t i = 0; i < 3; ++i)
        if (!isfinite(origin[i]) || !isfinite(scale[i]) || !isfinite(angles[i]) || !isfinite(color[i]))
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (size_t i = 0; i < 2; ++i)
        if (!isfinite(size[i]) || size[i] < 0)
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSLayerRecord *record = &domain->layers[layer_index];
    record->name = copy_string(name, name_length); record->text = copy_string(text, text_length);
    record->font = copy_string(font, font_length);
    if (record->name == NULL || record->text == NULL || record->font == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    record->layer_id = layer_id; record->parent_id = parent_id;
    record->has_parent = has_parent != 0;
    memcpy(record->authored_origin, origin, sizeof(record->authored_origin));
    memcpy(record->current_origin, origin, sizeof(record->current_origin));
    memcpy(record->size, size, sizeof(record->size));
    memcpy(record->scale, scale, sizeof(record->scale)); memcpy(record->angles, angles, sizeof(record->angles));
    memcpy(record->color, color, sizeof(record->color)); record->visible = visible != 0; record->solid = true;
    record->perspective = 2;
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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_initial_configuration(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index,
    const char *json, size_t json_length,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || domain->layers == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured || json == NULL ||
        domain->layers[layer_index].initial_configuration != NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid initial layer configuration"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    JSContext *context = domain->context;
    JSValue value = JS_ParseJSON(context, json, json_length, "initial-layer-configuration");
    if (JS_IsException(value))
        return mwx_scene_quickjs_exception_result(domain, diagnostic, diagnostic_capacity);
    if (!JS_IsObject(value) || JS_IsArray(value)) {
        JS_FreeValue(context, value);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "initial layer configuration must be an object"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    size_t length = 0;
    uint8_t *bytes = JS_WriteObject(context, &length, value, 0);
    JS_FreeValue(context, value);
    if (bytes == NULL)
        return mwx_scene_quickjs_exception_result(domain, diagnostic, diagnostic_capacity);
    domain->layers[layer_index].initial_configuration = bytes;
    domain->layers[layer_index].initial_configuration_length = length;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_descriptor(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index, int64_t layer_id,
    uint32_t has_parent, int64_t parent_id,
    const char *name, size_t name_length, const double origin[3],
    const double size[2],
    char *diagnostic, size_t diagnostic_capacity
) {
    static const double scale[3] = {1, 1, 1};
    static const double angles[3] = {0, 0, 0};
    static const double color[3] = {1, 1, 1};
    return mwx_scene_quickjs_domain_set_layer_runtime_descriptor(
        domain, layer_index, layer_id, has_parent, parent_id,
        name, name_length, origin, size,
        scale, angles, 1, 1, "", 0, "", 0, 32, color,
        diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_property_object_scope(
    MWXSceneQuickJSOwner *owner,
    uint32_t property_object_is_layer,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->domain == NULL || property_object_is_layer > 1 ||
        owner->domain->callback_active) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid property object scope"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (property_object_is_layer != 0 &&
        !mwx_scene_quickjs_define_property_animation_accessor(owner)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "property object animation accessor unavailable"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    owner->property_object_is_layer = property_object_is_layer != 0;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_layer_identity(
    MWXSceneQuickJSOwner *owner, int64_t layer_id,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->target_layer_configured || owner->domain->callback_active)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSLayerAccessHandle *reference = JS_GetOpaque(
        owner->material_function_layer, owner->domain->layer_handle_class_id
    );
    if (reference == NULL || reference->domain != owner->domain)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (uint32_t index = 0; index < owner->domain->authored_layer_count; ++index)
        if (owner->domain->layers[index].configured && owner->domain->layers[index].layer_id == layer_id) {
            owner->target_layer_index = index; owner->target_layer_configured = true;
            // Publish the configured referent on the existing native object.
            // Other script owners retain this layer, never their own target.
            reference->layer_index = index;
            reference->owner_target = false;
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
        free(baseline->effect_visible);
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
    uint32_t solid,
    uint32_t perspective,
    const char *text,
    size_t text_length,
    const char *font,
    size_t font_length,
    double alpha,
    double particle_alpha,
    double point_size,
    const double color[3],
    uint32_t effect_count, const uint8_t *effect_visible,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    const uint32_t supported_fields =
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SOLID |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_EFFECT_VISIBILITY |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA;
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->domain == NULL || owner->disabled ||
        owner->domain->callback_active || owner->generation != expected_generation ||
        fields == 0 || (fields & ~supported_fields) != 0 || visible > 1 || solid > 1 || perspective > 1 ||
        origin == NULL || scale == NULL || angles == NULL || text == NULL ||
        font == NULL || color == NULL || !isfinite(alpha) || alpha < 0 || alpha > 1 ||
        !isfinite(particle_alpha) ||
        ((fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE) != 0 && !isfinite(point_size)) ||
        text_length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT ||
        font_length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT ||
        memchr(text, '\0', text_length) != NULL ||
        memchr(font, '\0', font_length) != NULL ||
        owner->authored_layer_mutation_baseline_count >=
            MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS) {
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
            !isfinite(angles[index]) || !isfinite(color[index]) || color[index] < 0 || color[index] > 1) {
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
        ((fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA) != 0 &&
         !owner->domain->layers[layer_index].particle_instance_available) ||
        ((fields & (MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT |
                    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT |
                    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE)) != 0 &&
         !owner->domain->layers[layer_index].text_mutable)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "authored layer mutation baseline target is invalid"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (mwx_scene_quickjs_authored_mutation_baseline_for_layer(owner, layer_index) != NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "duplicate authored layer mutation baseline target"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    const bool has_effects = (fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_EFFECT_VISIBILITY) != 0;
    if (has_effects != (effect_count > 0) ||
        (has_effects && (effect_visible == NULL || effect_count > owner->domain->layers[layer_index].effect_count)))
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (uint32_t i = 0; i < effect_count; ++i)
        if (effect_visible[i] > 2) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    char *text_copy = NULL;
    char *font_copy = NULL;
    if ((fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT) != 0) {
        text_copy = malloc(text_length + 1);
        if (text_copy == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        memcpy(text_copy, text, text_length);
        text_copy[text_length] = '\0';
    }
    if ((fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT) != 0) {
        if (!mwx_scene_quickjs_layer_valid_asset_path(font, font_length, MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH)) {
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
    uint8_t *effect_copy = effect_count == 0 ? NULL : malloc(owner->domain->layers[layer_index].effect_count);
    if (effect_count > 0 && effect_copy == NULL) {
        free(text_copy); free(font_copy); return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    if (effect_count > 0) {
        memset(effect_copy, 2, owner->domain->layers[layer_index].effect_count);
        memcpy(effect_copy, effect_visible, effect_count);
    }
    MWXSceneQuickJSAuthoredLayerMutationRecord *baseline =
        &owner->authored_layer_mutation_baselines[
            owner->authored_layer_mutation_baseline_count++
        ];
    *baseline = (MWXSceneQuickJSAuthoredLayerMutationRecord){
        .layer_index = layer_index,
        .fields = fields,
        .visible = visible != 0, .solid = solid != 0, .perspective = perspective,
        .alpha = alpha,
        .particle_alpha = particle_alpha,
        .point_size = point_size,
        .effect_visible = effect_copy,
        .text = text_copy,
        .font = font_copy,
    };
    memcpy(baseline->origin, origin, sizeof(baseline->origin));
    memcpy(baseline->scale, scale, sizeof(baseline->scale));
    memcpy(baseline->angles, angles, sizeof(baseline->angles));
    memcpy(baseline->color, color, sizeof(baseline->color));
    return MWX_SCENE_QUICKJS_OK;
}
