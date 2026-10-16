#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

bool mwx_scene_quickjs_layer_mark_dirty(MWXSceneQuickJSOwner *owner, MWXSceneQuickJSLayerRecord *record) {
    owner = mwx_scene_quickjs_text_transaction_owner(owner);
    if (record->dirty && record->dirty_owner_identity != owner->identity) {
        owner->layer_mutation_overflow = true;
        return false;
    }
    if (!record->dirty) {
        record->dirty_fields = 0;
        if (owner->layer_mutation_count >= MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS) {
            owner->layer_mutation_overflow = true;
            return false;
        }
        owner->layer_mutation_count += 1;
    }
    record->dirty = true;
    record->dirty_owner_identity = owner->identity;
    return true;
}

static char *duplicate_optional_layer_string(const char *source) {
    if (source == NULL) return NULL;
    const size_t length = strlen(source);
    char *copy = malloc(length + 1);
    if (copy == NULL) return NULL;
    memcpy(copy, source, length + 1);
    return copy;
}

bool mwx_scene_quickjs_layer_ensure_dynamic_layer_transaction(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL) return false;
    if (owner->dynamic_layer_transaction_active) return true;
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (domain->dynamic_layer_transaction_participant_count == SIZE_MAX)
        return false;
    owner->dynamic_layer_transaction_active = true;
    owner->dynamic_layer_created_count = 0;
    owner->dynamic_layer_value_baseline_count = 0;
    domain->dynamic_layer_transaction_participant_count += 1;
    return true;
}

static bool created_layer_slot_for_owner(
    const MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    if (owner == NULL) return false;
    for (size_t index = 0; index < owner->dynamic_layer_created_count; ++index)
        if (owner->dynamic_layer_created_indices[index] == layer_index) return true;
    return false;
}

bool mwx_scene_quickjs_layer_journal_dynamic_layer_creation(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    if (!mwx_scene_quickjs_layer_ensure_dynamic_layer_transaction(owner) ||
        layer_index >= MWX_SCENE_QUICKJS_MAX_LAYERS)
        return false;
    if (created_layer_slot_for_owner(owner, layer_index)) return true;
    if (owner->dynamic_layer_created_count >= MWX_SCENE_QUICKJS_MAX_LAYERS)
        return false;
    owner->dynamic_layer_created_indices[
        owner->dynamic_layer_created_count++
    ] = layer_index;
    return true;
}

static MWXSceneQuickJSDynamicLayerValueBaseline *value_baseline_for_layer(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    for (size_t index = 0;
         index < owner->dynamic_layer_value_baseline_count; ++index) {
        MWXSceneQuickJSDynamicLayerValueBaseline *baseline =
            &owner->dynamic_layer_value_baselines[index];
        if (baseline->layer_index == layer_index) return baseline;
    }
    return NULL;
}

bool mwx_scene_quickjs_layer_journal_dynamic_layer_value(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
) {
    owner = mwx_scene_quickjs_text_transaction_owner(owner);
    if (!mwx_scene_quickjs_layer_ensure_dynamic_layer_transaction(owner) ||
        layer_index >= owner->domain->layer_count) return false;
    // A newly-created record has no previous value to restore.  Its slot is
    // removed by the creation journal on discard.
    if (owner->domain->layers[layer_index].dirty &&
        owner->domain->layers[layer_index].dirty_owner_identity != owner->identity) {
        owner->layer_mutation_overflow = true;
        return false;
    }
    if (created_layer_slot_for_owner(owner, layer_index)) return true;
    if (value_baseline_for_layer(owner, layer_index) != NULL) return true;
    if (owner->dynamic_layer_value_baseline_count >=
        MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS) return false;
    MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[layer_index];
    MWXSceneQuickJSDynamicLayerValueBaseline *baseline =
        &owner->dynamic_layer_value_baselines[
            owner->dynamic_layer_value_baseline_count
        ];
    *baseline = (MWXSceneQuickJSDynamicLayerValueBaseline){
        .layer_index = layer_index,
        .dirty_fields = record->dirty_fields,
        .alpha = record->alpha,
        .point_size = record->point_size,
        .visible = record->visible, .solid = record->solid,
        .perspective = record->perspective,
        .text = duplicate_optional_layer_string(record->text),
        .font = duplicate_optional_layer_string(record->font),
    };
    if ((record->text != NULL && baseline->text == NULL) ||
        (record->font != NULL && baseline->font == NULL)) {
        free(baseline->text);
        free(baseline->font);
        *baseline = (MWXSceneQuickJSDynamicLayerValueBaseline){0};
        return false;
    }
    memcpy(baseline->current_origin, record->current_origin,
           sizeof(baseline->current_origin));
    memcpy(baseline->scale, record->scale, sizeof(baseline->scale));
    memcpy(baseline->angles, record->angles, sizeof(baseline->angles));
    memcpy(baseline->color, record->color, sizeof(baseline->color));
    owner->dynamic_layer_value_baseline_count += 1;
    return true;
}

static bool dynamic_layer_record_is_active(
    const MWXSceneQuickJSLayerRecord *record
) {
    return record != NULL && record->configured && !record->destroyed;
}

static bool topology_sequence_remove(
    uint32_t sequence[MWX_SCENE_QUICKJS_MAX_LAYERS],
    size_t *count,
    uint32_t layer_index
) {
    if (sequence == NULL || count == NULL) return false;
    for (size_t position = 0; position < *count; ++position) {
        if (sequence[position] != layer_index) continue;
        if (position + 1 < *count) {
            memmove(
                &sequence[position], &sequence[position + 1],
                (*count - position - 1) * sizeof(sequence[0])
            );
        }
        *count -= 1;
        return true;
    }
    return false;
}

static bool topology_sequence_insert(
    uint32_t sequence[MWX_SCENE_QUICKJS_MAX_LAYERS],
    size_t *count,
    uint32_t layer_index,
    int32_t requested_order
) {
    if (sequence == NULL || count == NULL ||
        *count >= MWX_SCENE_QUICKJS_MAX_LAYERS) return false;
    size_t position = requested_order < 0 ? 0 : (size_t)requested_order;
    if (position > *count) position = *count;
    if (position < *count) {
        memmove(
            &sequence[position + 1], &sequence[position],
            (*count - position) * sizeof(sequence[0])
        );
    }
    sequence[position] = layer_index;
    *count += 1;
    return true;
}

static bool begin_dynamic_layer_topology_transaction(
    MWXSceneQuickJSDomain *domain
) {
    if (domain == NULL) return false;
    if (domain->dynamic_layer_topology_transaction_active) return true;
    if (domain->layer_count > MWX_SCENE_QUICKJS_MAX_LAYERS) return false;
    domain->dynamic_layer_topology_transaction_active = true;
    domain->dynamic_layer_topology_baseline_layer_count = domain->layer_count;
    domain->dynamic_layer_topology_baseline_order_count = 0;
    memset(
        domain->dynamic_layer_topology_baseline_active, 0,
        sizeof(domain->dynamic_layer_topology_baseline_active)
    );
    // Capture the stable pre-edit order once.  The authored catalog and any
    // previously published dynamic tombstones remain the baseline; subsequent
    // owners append operations to the same frame candidate.
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        if (!dynamic_layer_record_is_active(record)) continue;
        if (domain->dynamic_layer_topology_baseline_order_count >=
            MWX_SCENE_QUICKJS_MAX_LAYERS) {
            domain->dynamic_layer_topology_transaction_active = false;
            return false;
        }
        size_t position = domain->dynamic_layer_topology_baseline_order_count;
        while (position > 0) {
            const uint32_t previous =
                domain->dynamic_layer_topology_baseline_order[position - 1];
            MWXSceneQuickJSLayerRecord *previous_record =
                &domain->layers[previous];
            if (previous_record->order_index < record->order_index ||
                (previous_record->order_index == record->order_index &&
                 previous < index)) break;
            domain->dynamic_layer_topology_baseline_order[position] = previous;
            position -= 1;
        }
        domain->dynamic_layer_topology_baseline_order[position] = index;
        domain->dynamic_layer_topology_baseline_order_count += 1;
        domain->dynamic_layer_topology_baseline_active[index] = 1;
    }
    domain->dynamic_layer_topology_operation_count = 0;
    return true;
}

bool mwx_scene_quickjs_layer_append_dynamic_layer_topology_operation(
    MWXSceneQuickJSOwner *owner,
    uint32_t kind,
    uint32_t layer_index,
    int32_t order_index
) {
    owner = mwx_scene_quickjs_text_transaction_owner(owner);
    if (!mwx_scene_quickjs_layer_ensure_dynamic_layer_transaction(owner) ||
        owner->domain == NULL ||
        !begin_dynamic_layer_topology_transaction(owner->domain)) return false;
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (domain->dynamic_layer_topology_operation_count >=
        MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYER_OPERATIONS) return false;
    if (layer_index >= MWX_SCENE_QUICKJS_MAX_LAYERS) return false;
    if (!owner->dynamic_layer_topology_participating) {
        if (domain->dynamic_layer_topology_participant_count == SIZE_MAX)
            return false;
        owner->dynamic_layer_topology_participating = true;
        domain->dynamic_layer_topology_participant_count += 1;
    }
    domain->dynamic_layer_topology_operations[
        domain->dynamic_layer_topology_operation_count++
    ] = (MWXSceneQuickJSDynamicLayerTopologyOperation){
        .owner_identity = owner->identity,
        .layer_index = layer_index,
        .order_index = order_index,
        .kind = kind,
        .state = MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_PENDING,
    };
    return true;
}

static void mark_owner_topology_operations(
    MWXSceneQuickJSOwner *owner,
    uint32_t state
) {
    if (owner == NULL || owner->domain == NULL) return;
    MWXSceneQuickJSDomain *domain = owner->domain;
    for (size_t index = 0;
         index < domain->dynamic_layer_topology_operation_count; ++index) {
        MWXSceneQuickJSDynamicLayerTopologyOperation *operation =
            &domain->dynamic_layer_topology_operations[index];
        if (operation->owner_identity == owner->identity &&
            operation->state == MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_PENDING)
            operation->state = state;
    }
}

void mwx_scene_quickjs_layer_discard_last_dynamic_layer_topology_operation(
    MWXSceneQuickJSOwner *owner
) {
    owner = mwx_scene_quickjs_text_transaction_owner(owner);
    if (owner == NULL || owner->domain == NULL) return;
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (domain->dynamic_layer_topology_operation_count == 0) return;
    MWXSceneQuickJSDynamicLayerTopologyOperation *operation =
        &domain->dynamic_layer_topology_operations[
            domain->dynamic_layer_topology_operation_count - 1
        ];
    if (operation->owner_identity == owner->identity &&
        operation->state == MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_PENDING)
        operation->state = MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_DISCARDED;
}

// The one journal replay serves both C restoration and the host's immutable
// candidate projection. Filtering never mutates records or journal state.
static bool project_dynamic_layer_topology(
    MWXSceneQuickJSDomain *domain, const uint64_t *accepted_owner_ids,
    uint32_t accepted_owner_count, bool filtering_pending,
    uint32_t sequence[MWX_SCENE_QUICKJS_MAX_LAYERS], size_t *count,
    bool active[MWX_SCENE_QUICKJS_MAX_LAYERS]
) {
    if (domain == NULL || !domain->dynamic_layer_topology_transaction_active ||
        domain->layer_count > MWX_SCENE_QUICKJS_MAX_LAYERS) return false;
    *count = domain->dynamic_layer_topology_baseline_order_count;
    if (*count > MWX_SCENE_QUICKJS_MAX_LAYERS) return false;
    memcpy(sequence, domain->dynamic_layer_topology_baseline_order, *count * sizeof(sequence[0]));
    memcpy(active, domain->dynamic_layer_topology_baseline_active,
           MWX_SCENE_QUICKJS_MAX_LAYERS * sizeof(active[0]));
    for (size_t op_index = 0; op_index < domain->dynamic_layer_topology_operation_count; ++op_index) {
        const MWXSceneQuickJSDynamicLayerTopologyOperation *operation = &domain->dynamic_layer_topology_operations[op_index];
        if (operation->state == MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_DISCARDED) continue;
        if (filtering_pending && operation->state == MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_PENDING) {
            bool accepted = false;
            for (uint32_t index = 0; index < accepted_owner_count; ++index)
                if (accepted_owner_ids[index] == operation->owner_identity) { accepted = true; break; }
            if (!accepted) continue;
        }
        if (operation->layer_index >= domain->layer_count) return false;
        const uint32_t index = operation->layer_index;
        const MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        switch (operation->kind) {
        case MWX_SCENE_QUICKJS_DYNAMIC_LAYER_CREATE:
            if (!record->configured || !record->dynamic || record->owner_identity != operation->owner_identity) break;
            topology_sequence_remove(sequence, count, index);
            active[index] = topology_sequence_insert(sequence, count, index, operation->order_index);
            break;
        case MWX_SCENE_QUICKJS_DYNAMIC_LAYER_SORT:
            if (!record->configured || !active[index] ||
                (record->dynamic && record->owner_identity != operation->owner_identity &&
                 (record->text_property_owner_identity == 0 ||
                  record->text_property_owner_identity != operation->owner_identity))) break;
            topology_sequence_remove(sequence, count, index);
            active[index] = topology_sequence_insert(sequence, count, index, operation->order_index);
            break;
        case MWX_SCENE_QUICKJS_DYNAMIC_LAYER_DESTROY:
            if (!record->configured || !active[index] || record->owner_identity != operation->owner_identity) break;
            topology_sequence_remove(sequence, count, index);
            active[index] = false;
            break;
        default: return false;
        }
    }
    return true;
}

static void rebuild_dynamic_layer_topology(MWXSceneQuickJSDomain *domain) {
    uint32_t sequence[MWX_SCENE_QUICKJS_MAX_LAYERS];
    bool active[MWX_SCENE_QUICKJS_MAX_LAYERS];
    size_t count = 0;
    if (!project_dynamic_layer_topology(domain, NULL, 0, false, sequence, &count, active)) return;
    for (uint32_t index = 0; index < domain->layer_count; ++index)
        if (domain->layers[index].configured) domain->layers[index].destroyed = !active[index];
    for (size_t position = 0; position < count; ++position) {
        const uint32_t index = sequence[position];
        if (index < domain->layer_count && domain->layers[index].configured && active[index])
            domain->layers[index].order_index = (int32_t)position;
    }
}

uint64_t mwx_scene_quickjs_owner_pending_layer_topology_identity(MWXSceneQuickJSOwner *owner) {
    return owner != NULL && !owner->disabled && owner->dynamic_layer_topology_participating
        ? owner->identity : 0;
}

uint32_t mwx_scene_quickjs_domain_has_pending_layer_topology(MWXSceneQuickJSDomain *domain) {
    return domain != NULL && domain->dynamic_layer_topology_transaction_active;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_project_pending_layer_order(
    MWXSceneQuickJSDomain *domain, const uint64_t *accepted_owner_ids,
    uint32_t accepted_owner_count, int64_t *layer_ids, uint32_t capacity, uint32_t *output_count
) {
    if (domain == NULL || domain->context == NULL || domain->callback_active ||
        !domain->dynamic_layer_topology_transaction_active || output_count == NULL ||
        layer_ids == NULL || capacity > MWX_SCENE_QUICKJS_MAX_LAYERS ||
        accepted_owner_count > MWX_SCENE_QUICKJS_MAX_LAYERS ||
        (accepted_owner_count != 0 && accepted_owner_ids == NULL)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (uint32_t index = 0; index < accepted_owner_count; ++index)
        if (accepted_owner_ids[index] == 0 || accepted_owner_ids[index] > domain->next_owner_identity)
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    uint32_t sequence[MWX_SCENE_QUICKJS_MAX_LAYERS];
    bool active[MWX_SCENE_QUICKJS_MAX_LAYERS];
    size_t count = 0;
    if (!project_dynamic_layer_topology(domain, accepted_owner_ids, accepted_owner_count,
            true, sequence, &count, active) || count > capacity) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (size_t position = 0; position < count; ++position) {
        const uint32_t index = sequence[position];
        if (index >= domain->layer_count || !domain->layers[index].configured || !active[index])
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        layer_ids[position] = domain->layers[index].layer_id;
    }
    *output_count = (uint32_t)count;
    return MWX_SCENE_QUICKJS_OK;
}

static void clear_domain_dynamic_layer_topology(
    MWXSceneQuickJSDomain *domain
) {
    if (domain == NULL) return;
    domain->dynamic_layer_topology_transaction_active = false;
    domain->dynamic_layer_topology_baseline_layer_count = 0;
    domain->dynamic_layer_topology_baseline_order_count = 0;
    domain->dynamic_layer_topology_operation_count = 0;
    domain->dynamic_layer_topology_participant_count = 0;
    memset(
        domain->dynamic_layer_topology_baseline_active, 0,
        sizeof(domain->dynamic_layer_topology_baseline_active)
    );
}

static void clear_layer_mutation_buffers(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL) return;
    for (size_t index = 0; index < owner->authored_layer_mutation_count; ++index) {
        MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
            &owner->authored_layer_mutations[index];
        free(mutation->text);
        free(mutation->font);
        free(mutation->effect_visible);
        *mutation = (MWXSceneQuickJSAuthoredLayerMutationRecord){0};
    }
    owner->authored_layer_mutation_count = 0;
    owner->layer_mutation_count = 0;
    owner->layer_mutation_overflow = false;
    for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (record->dirty && record->dirty_owner_identity == owner->identity) {
            record->dirty = false;
            record->dirty_owner_identity = 0;
            record->dirty_fields = 0;
        }
    }
}

static void clear_dynamic_layer_journal(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL) return;
    MWXSceneQuickJSDomain *domain = owner->domain;
    const bool was_active = owner->dynamic_layer_transaction_active;
    const bool was_topology_participating =
        owner->dynamic_layer_topology_participating;
    for (size_t index = 0;
         index < owner->dynamic_layer_value_baseline_count; ++index) {
        MWXSceneQuickJSDynamicLayerValueBaseline *baseline =
            &owner->dynamic_layer_value_baselines[index];
        free(baseline->text);
        free(baseline->font);
        *baseline = (MWXSceneQuickJSDynamicLayerValueBaseline){0};
    }
    memset(
        owner->dynamic_layer_created_indices, 0,
        sizeof(owner->dynamic_layer_created_indices)
    );
    owner->dynamic_layer_created_count = 0;
    owner->dynamic_layer_value_baseline_count = 0;
    owner->dynamic_layer_transaction_active = false;
    owner->dynamic_layer_topology_participating = false;
    if (!was_active || domain == NULL) return;
    if (domain->dynamic_layer_transaction_participant_count > 0)
        domain->dynamic_layer_transaction_participant_count -= 1;
    if (was_topology_participating &&
        domain->dynamic_layer_topology_participant_count > 0)
        domain->dynamic_layer_topology_participant_count -= 1;
    if (domain->dynamic_layer_topology_transaction_active) {
        rebuild_dynamic_layer_topology(domain);
        if (domain->dynamic_layer_topology_participant_count == 0)
            clear_domain_dynamic_layer_topology(domain);
    }
}

static void restore_dynamic_layer_journal(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL ||
        !owner->dynamic_layer_transaction_active) return;
    MWXSceneQuickJSDomain *domain = owner->domain;
    for (size_t index = 0;
         index < owner->dynamic_layer_value_baseline_count; ++index) {
        MWXSceneQuickJSDynamicLayerValueBaseline *baseline =
            &owner->dynamic_layer_value_baselines[index];
        if (baseline->layer_index >= domain->layer_count) continue;
        MWXSceneQuickJSLayerRecord *record =
            &domain->layers[baseline->layer_index];
        free(record->text);
        free(record->font);
        record->text = baseline->text;
        record->font = baseline->font;
        baseline->text = NULL;
        baseline->font = NULL;
        memcpy(record->current_origin, baseline->current_origin,
               sizeof(record->current_origin));
        memcpy(record->scale, baseline->scale, sizeof(record->scale));
        memcpy(record->angles, baseline->angles, sizeof(record->angles));
        memcpy(record->color, baseline->color, sizeof(record->color));
        record->alpha = baseline->alpha;
        record->point_size = baseline->point_size;
        record->visible = baseline->visible;
        record->solid = baseline->solid;
        record->perspective = baseline->perspective;
        record->dirty_fields = baseline->dirty_fields;
    }
}

static void discard_owner_created_layers(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL) return;
    MWXSceneQuickJSDomain *domain = owner->domain;
    for (size_t index = 0;
         index < owner->dynamic_layer_created_count; ++index) {
        const uint32_t layer_index = owner->dynamic_layer_created_indices[index];
        if (layer_index >= domain->layer_count) continue;
        MWXSceneQuickJSLayerRecord *record = &domain->layers[layer_index];
        if (!record->configured || !record->dynamic ||
            record->owner_identity != owner->identity) continue;
        free(record->name);
        free(record->text);
        free(record->font);
        free(record->asset_path);
        *record = (MWXSceneQuickJSLayerRecord){0};
    }
}

static void finish_dynamic_layer_transaction(
    MWXSceneQuickJSOwner *owner,
    bool committing
) {
    if (owner == NULL || owner->domain == NULL ||
        !owner->dynamic_layer_transaction_active) return;
    if (committing) {
        mark_owner_topology_operations(
            owner, MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_COMMITTED
        );
    } else {
        mark_owner_topology_operations(
            owner, MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_DISCARDED
        );
        restore_dynamic_layer_journal(owner);
        discard_owner_created_layers(owner);
    }
    clear_dynamic_layer_journal(owner);
}

void mwx_scene_quickjs_owner_discard_layer_mutations(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL) return;
    if (owner->domain->particle_boundary != NULL)
        owner->domain->particle_boundary(owner->domain->particle_emission_opaque, owner, 1);
    mwx_scene_quickjs_finish_text_clones(owner, false);
    mwx_scene_quickjs_puppet_animation_finish_transaction(owner, false);
    owner->initialization_pending = false;
    if (owner->initialization_timers != NULL) {
        mwx_scene_quickjs_owner_timer_restore(owner, owner->initialization_timers);
        mwx_scene_quickjs_owner_timer_snapshot_destroy(owner->initialization_timers, owner);
        owner->initialization_timers = NULL;
    }
    owner->effect_visibility_staged = false;
    owner->effect_visibility_pending = false;
    finish_dynamic_layer_transaction(owner, false);
    clear_layer_mutation_buffers(owner);
    owner->media_playback_command_count = 0;
    owner->media_playback_command_overflow = false;
    owner->media_playback_callback_epoch = 0;
    owner->media_playback_callback_start = 0;
    owner->particle_playback_command_count = 0;
    owner->particle_playback_command_overflow = false;
    if (owner->puppet_bone_transaction_active)
    for (uint32_t bone = 0; bone < owner->puppet_bone_count; ++bone) {
        memcpy(owner->puppet_bone_world[bone], owner->puppet_bone_world_baseline[bone], sizeof(double) * 16);
        memcpy(owner->puppet_bone_local[bone], owner->puppet_bone_local_baseline[bone], sizeof(double) * 16);
    }
    owner->puppet_bone_mutation_count = 0;
    owner->puppet_bone_transaction_active = false;
}

void mwx_scene_quickjs_owner_commit_layer_mutations(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL) return;
    mwx_scene_quickjs_finish_text_clones(owner, true);
    mwx_scene_quickjs_puppet_animation_finish_transaction(owner, true);
    if (owner->initialization_pending) owner->initialized = true;
    owner->initialization_pending = false;
    if (owner->initialization_timers != NULL) {
        mwx_scene_quickjs_owner_timer_snapshot_destroy(owner->initialization_timers, owner);
        owner->initialization_timers = NULL;
    }
    if (owner->effect_visibility_pending) {
        owner->effect_visibility_committed_visible =
            owner->effect_visibility_pending_visible;
    }
    owner->effect_visibility_staged = false;
    owner->effect_visibility_pending = false;
    finish_dynamic_layer_transaction(owner, true);
    clear_layer_mutation_buffers(owner);
    owner->particle_playback_command_count = 0;
    owner->particle_playback_command_overflow = false;
    owner->puppet_bone_mutation_count = 0;
    owner->puppet_bone_transaction_active = false;
}

void mwx_scene_quickjs_owner_begin_layer_mutations(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return;
    owner->text_clone_failed = false;
    // Primitive entries export only their new range. Keep earlier callbacks'
    // commands for this owner's read-your-writes until the shared frame barrier.
    owner->puppet_animation_command_read_start = owner->puppet_animation_command_count;
    owner->puppet_animation_registration_count = 0;
    mwx_scene_quickjs_layer_ensure_dynamic_layer_transaction(owner);
    clear_layer_mutation_buffers(owner);
    owner->particle_playback_command_count = 0;
    owner->particle_playback_command_overflow = false;
    owner->puppet_bone_mutation_count = 0;
    if (!owner->puppet_bone_transaction_active)
    for (uint32_t bone = 0; bone < owner->puppet_bone_count; ++bone) {
        memcpy(owner->puppet_bone_world_baseline[bone], owner->puppet_bone_world[bone], sizeof(double) * 16);
        memcpy(owner->puppet_bone_local_baseline[bone], owner->puppet_bone_local[bone], sizeof(double) * 16);
    }
    owner->puppet_bone_transaction_active = true;
    owner->media_playback_command_count = 0;
    owner->media_playback_command_overflow = false;
    owner->media_playback_callback_epoch = 0;
    owner->media_playback_callback_start = 0;
    owner->texture_animation_command_count = 0;
    owner->texture_animation_command_overflow = false;
}

bool mwx_scene_quickjs_owner_remove_dynamic_layers(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return false;
    MWXSceneQuickJSDomain *domain = owner->domain;
    // Permanent removal never runs inside a callback.  Besides protecting a
    // peer, this keeps a same-owner callback from losing its provisional
    // journal before it has returned a result to the host.
    if (domain->callback_active) return false;
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(owner);
    // Teardown is itself a topology edit.  A direct caller may arrive while a
    // peer still owns a provisional frame journal; do not discard that peer's
    // state or mutate its records.  The scene-wide lifecycle barrier releases
    // every owner first, and a direct caller can retry after the peer commits
    // or discards its journal.
    if (domain->dynamic_layer_topology_participant_count != 0) {
        owner->authored_layer_baseline_available = false;
        return false;
    }
    bool removed_layers = false;
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        if (!record->configured || !record->dynamic ||
            record->owner_identity != owner->identity) continue;
        removed_layers = removed_layers || !record->destroyed;
        record->destroyed = true;
        record->dirty = false;
        record->dirty_owner_identity = 0;
    }
    if (removed_layers) mwx_scene_quickjs_compact_layer_order(domain);
    owner->authored_layer_baseline_available = false;
    // Removal is permanent; there is no frame result to commit.  Any empty
    // domain candidate can be discarded now; layer_count remains monotonic so
    // stale handles cannot alias a future dynamic layer.
    if (domain->dynamic_layer_topology_transaction_active &&
        domain->dynamic_layer_topology_participant_count == 0)
        clear_domain_dynamic_layer_topology(domain);
    clear_dynamic_layer_journal(owner);
    clear_layer_mutation_buffers(owner);
    owner->particle_playback_command_count = 0;
    owner->particle_playback_command_overflow = false;
    return true;
}
