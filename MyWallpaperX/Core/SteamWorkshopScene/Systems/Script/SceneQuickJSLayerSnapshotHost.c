#include "SceneQuickJSInternal.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int32_t order;
    uint32_t index;
} MWXSceneQuickJSLayerOrderEntry;

static int compare_layer_order(const void *left, const void *right) {
    const MWXSceneQuickJSLayerOrderEntry *a = left;
    const MWXSceneQuickJSLayerOrderEntry *b = right;
    if (a->order != b->order) return a->order < b->order ? -1 : 1;
    return a->index == b->index ? 0 : (a->index < b->index ? -1 : 1);
}

void mwx_scene_quickjs_compact_layer_order(MWXSceneQuickJSDomain *domain) {
    // Capture the complete old rank before any write: storage order need not
    // match render order after authored sorts. Lifecycle edits stay bounded.
    MWXSceneQuickJSLayerOrderEntry entries[MWX_SCENE_QUICKJS_MAX_LAYERS];
    size_t count = 0;
    for (uint32_t i = 0; i < domain->layer_count; ++i) {
        const MWXSceneQuickJSLayerRecord *record = &domain->layers[i];
        if (record->configured && !record->destroyed)
            entries[count++] = (MWXSceneQuickJSLayerOrderEntry){record->order_index, i};
    }
    qsort(entries, count, sizeof(*entries), compare_layer_order);
    for (size_t i = 0; i < count; ++i)
        domain->layers[entries[i].index].order_index = (int32_t)i;
}

static char *copy_snapshot_string(const char *source, size_t length) {
    char *copy = malloc(length + 1);
    if (copy == NULL) return NULL;
    if (length > 0) memcpy(copy, source, length);
    copy[length] = '\0';
    return copy;
}

static void clear_snapshot(
    MWXSceneQuickJSStagedLayerSnapshot **snapshot,
    uint32_t layer_count
) {
    if (snapshot == NULL || *snapshot == NULL) return;
    for (uint32_t index = 0; index < layer_count; ++index) {
        free((*snapshot)[index].text);
        free((*snapshot)[index].font);
        free((*snapshot)[index].effect_visible);
    }
    free(*snapshot);
    *snapshot = NULL;
}

static void clear_text_clone_snapshot(MWXSceneQuickJSTextCloneSnapshot **head) {
    while (*head) {
        MWXSceneQuickJSTextCloneSnapshot *next = (*head)->next;
        free((*head)->text); free(*head); *head = next;
    }
}

static void clear_pending_snapshot(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) return;
    clear_text_clone_snapshot(&domain->pending_text_clone_snapshot);
    domain->pending_text_clone_count = 0;
    clear_snapshot(
        &domain->pending_layer_snapshot,
        domain->authored_layer_count
    );
    domain->pending_layer_snapshot_generation = 0;
    free(domain->pending_video_observations);
    domain->pending_video_observations = NULL;
    domain->pending_video_observation_count = 0;
    domain->pending_video_observations_staged = false;
}

static void clear_rollback_snapshot(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) return;
    clear_text_clone_snapshot(&domain->rollback_text_clone_snapshot);
    clear_snapshot(
        &domain->rollback_layer_snapshot,
        domain->authored_layer_count
    );
    domain->rollback_layer_snapshot_generation = 0;
    free(domain->rollback_video_observations);
    domain->rollback_video_observations = NULL;
    domain->rollback_video_observation_count = 0;
    domain->rollback_video_observations_replaced = false;
    free(domain->rollback_layer_order);
    domain->rollback_layer_order = NULL;
    domain->rollback_layer_order_count = 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_begin_layer_snapshot(
    MWXSceneQuickJSDomain *domain,
    uint64_t generation,
    uint32_t defaults_to_perspective,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers == NULL || domain->callback_active ||
        domain->pending_layer_snapshot != NULL ||
        domain->rollback_layer_snapshot != NULL || defaults_to_perspective > 1 || generation == 0 ||
        generation <= domain->layer_snapshot_generation) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid layer snapshot transaction"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        if (!domain->layers[index].configured) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "layer snapshot catalog is incomplete"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    size_t allocation_count = domain->authored_layer_count == 0
        ? 1 : domain->authored_layer_count;
    MWXSceneQuickJSStagedLayerSnapshot *pending = calloc(
        allocation_count, sizeof(*pending)
    );
    if (pending == NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "layer snapshot staging allocation failed"
        );
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        memcpy(pending[index].current_origin, record->authored_origin,
               sizeof(pending[index].current_origin));
        memcpy(pending[index].world_transform, record->world_transform,
               sizeof(pending[index].world_transform));
        pending[index].world_transform_available =
            record->world_transform_available;
        memcpy(pending[index].scale, record->scale,
               sizeof(pending[index].scale));
        memcpy(pending[index].angles, record->angles,
               sizeof(pending[index].angles));
        memcpy(pending[index].color, record->color,
               sizeof(pending[index].color));
        if (record->effect_count > 0) {
            pending[index].effect_visible = malloc(record->effect_count);
            if (pending[index].effect_visible == NULL) {
                clear_snapshot(&pending, domain->authored_layer_count);
                return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
            }
            memcpy(pending[index].effect_visible, record->effect_visible, record->effect_count);
        }
        pending[index].visible = record->visible;
        pending[index].solid = record->solid;
        pending[index].perspective = record->perspective;
        pending[index].destroyed = record->destroyed;
        pending[index].alpha = record->alpha;
        pending[index].particle_instance_available = record->particle_instance_available;
        pending[index].particle_alpha = record->particle_alpha;
        pending[index].point_size = record->point_size;
        pending[index].video_source_index = record->video_source_index;
        pending[index].sound_available = record->sound_available;
        pending[index].sound_is_playing = record->sound_is_playing;
        pending[index].particle_playback = record->particle_playback;
        pending[index].texture_animation_available =
            record->texture_animation_available;
        pending[index].texture_animation_frame_count =
            record->texture_animation_frame_count;
        pending[index].texture_animation_duration =
            record->texture_animation_duration;
        pending[index].texture_animation_rate = record->texture_animation_rate;
        pending[index].texture_animation_current_frame =
            record->texture_animation_current_frame;
        pending[index].texture_animation_is_playing =
            record->texture_animation_is_playing;
        pending[index].texture_animation_shared_rate =
            record->texture_animation_shared_rate;
        pending[index].texture_animation_shared_current_frame =
            record->texture_animation_shared_current_frame;
        pending[index].texture_animation_shared_is_playing =
            record->texture_animation_shared_is_playing;
    }
    domain->pending_layer_snapshot = pending;
    domain->pending_layer_snapshot_generation = generation;
    domain->pending_defaults_to_perspective = defaults_to_perspective != 0;
    domain->pending_camera_transforms = domain->camera_transforms;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid reused layer runtime fields"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    memcpy(domain->pending_layer_snapshot[layer_index].current_origin,
           domain->layers[layer_index].current_origin,
           sizeof(domain->layers[layer_index].current_origin));
    domain->pending_layer_snapshot[layer_index].runtime_fields_staged = true;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_world_transform(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    const double world_transform[16],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL || world_transform == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid staged layer world transform"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (size_t index = 0; index < 16; ++index) {
        if (!isfinite(world_transform[index]) ||
            fabs(world_transform[index]) > FLT_MAX) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "non-finite staged layer world transform"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    MWXSceneQuickJSStagedLayerSnapshot *staged =
        &domain->pending_layer_snapshot[layer_index];
    memcpy(
        staged->world_transform,
        world_transform,
        sizeof(staged->world_transform)
    );
    staged->world_transform_available = true;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_runtime_fields(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    const double scale[3],
    const double angles[3],
    uint32_t destroyed,
    uint32_t visible,
    uint32_t solid,
    uint32_t perspective,
    double alpha,
    const char *text,
    size_t text_length,
    const char *font,
    size_t font_length,
    double point_size,
    const double color[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured || destroyed > 1 || solid > 1 || perspective > 2 || scale == NULL ||
        angles == NULL || color == NULL || text == NULL || font == NULL ||
        text_length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT ||
        font_length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT || !isfinite(alpha) ||
        !isfinite(point_size)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid staged layer runtime fields"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (size_t index = 0; index < 3; ++index) {
        if (!isfinite(scale[index]) || !isfinite(angles[index]) ||
            !isfinite(color[index])) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "non-finite staged layer runtime fields"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    char *text_copy = copy_snapshot_string(text, text_length);
    char *font_copy = copy_snapshot_string(font, font_length);
    if (text_copy == NULL || font_copy == NULL) {
        free(text_copy);
        free(font_copy);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "layer snapshot string allocation failed"
        );
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    MWXSceneQuickJSStagedLayerSnapshot *staged =
        &domain->pending_layer_snapshot[layer_index];
    free(staged->text);
    free(staged->font);
    staged->text = text_copy;
    staged->font = font_copy;
    memcpy(staged->scale, scale, sizeof(staged->scale));
    memcpy(staged->angles, angles, sizeof(staged->angles));
    memcpy(staged->color, color, sizeof(staged->color));
    staged->visible = visible != 0;
    staged->solid = solid != 0;
    staged->perspective = perspective;
    staged->destroyed = destroyed != 0;
    staged->alpha = alpha;
    staged->point_size = point_size;
    staged->sound_available = false;
    staged->sound_is_playing = false;
    staged->particle_playback = (MWXSceneQuickJSParticlePlaybackState){0};
    staged->particle_instance_available = false;
    staged->particle_alpha = 1;
    staged->texture_animation_available = false;
    staged->texture_animation_frame_count = 0;
    staged->texture_animation_duration = 0;
    staged->texture_animation_rate = 1;
    staged->texture_animation_current_frame = 0;
    staged->texture_animation_is_playing = false;
    staged->texture_animation_shared_rate = 1;
    staged->texture_animation_shared_current_frame = 0;
    staged->texture_animation_shared_is_playing = false;
    staged->runtime_fields_staged = true;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_stage_video_observations(
    MWXSceneQuickJSDomain *domain, const MWXSceneQuickJSVideoObservation *observations,
    uint32_t count, char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || domain->pending_layer_snapshot == NULL ||
        (count != 0 && observations == NULL)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSVideoObservation *copy = count == 0 ? NULL : malloc(sizeof(*copy) * (size_t)count);
    if (count != 0 && copy == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    if (count != 0) memcpy(copy, observations, sizeof(*copy) * (size_t)count);
    free(domain->pending_video_observations);
    domain->pending_video_observations = copy;
    domain->pending_video_observation_count = count;
    domain->pending_video_observations_staged = true;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_video_source(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index, uint32_t source_index,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count || !domain->layers[layer_index].configured ||
        (source_index != UINT32_MAX && source_index >= (domain->pending_video_observations_staged
            ? domain->pending_video_observation_count : domain->video_observation_count)))
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (source_index != UINT32_MAX && !(domain->pending_video_observations_staged
            ? domain->pending_video_observations : domain->video_observations)[source_index].available)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    domain->pending_layer_snapshot[layer_index].video_source_index = source_index;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_withdraw_authored_video_sources(
    MWXSceneQuickJSDomain *domain
) {
    if (domain == NULL || domain->callback_active) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        domain->layers[index].video_source_index = UINT32_MAX;
        if (domain->pending_layer_snapshot != NULL)
            domain->pending_layer_snapshot[index].video_source_index = UINT32_MAX;
        if (domain->rollback_layer_snapshot != NULL)
            domain->rollback_layer_snapshot[index].video_source_index = UINT32_MAX;
    }
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_sound_fields(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index,
    uint32_t available, uint32_t is_playing,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured || available > 1 || is_playing > 1) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid staged layer sound fields"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    MWXSceneQuickJSStagedLayerSnapshot *staged =
        &domain->pending_layer_snapshot[layer_index];
    staged->sound_available = available != 0;
    staged->sound_is_playing = is_playing != 0;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_texture_animation_fields(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    uint32_t available,
    uint32_t frame_count,
    double duration,
    double rate,
    double current_frame,
    uint32_t is_playing,
    double shared_rate,
    double shared_current_frame,
    uint32_t shared_is_playing,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured || available > 1 ||
        is_playing > 1 || shared_is_playing > 1 ||
        (available != 0 && frame_count == 0) || !isfinite(duration) ||
        duration < 0 || !isfinite(rate) || fabs(rate) > 16 ||
        !isfinite(current_frame) || current_frame < 0 ||
        floor(current_frame) != current_frame ||
        (frame_count > 0 && current_frame >= frame_count) ||
        !isfinite(shared_rate) || fabs(shared_rate) > 16 ||
        !isfinite(shared_current_frame) || shared_current_frame < 0 ||
        floor(shared_current_frame) != shared_current_frame ||
        (frame_count > 0 && shared_current_frame >= frame_count)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid staged layer texture animation fields"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    MWXSceneQuickJSStagedLayerSnapshot *staged =
        &domain->pending_layer_snapshot[layer_index];
    staged->texture_animation_available = available != 0;
    staged->texture_animation_frame_count = frame_count;
    staged->texture_animation_duration = duration;
    staged->texture_animation_rate = rate;
    staged->texture_animation_current_frame = current_frame;
    staged->texture_animation_is_playing = is_playing != 0;
    staged->texture_animation_shared_rate = shared_rate;
    staged->texture_animation_shared_current_frame = shared_current_frame;
    staged->texture_animation_shared_is_playing = shared_is_playing != 0;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_camera_transforms(
    MWXSceneQuickJSDomain *domain, const double eye[3], const double center[3], const double up[3],
    double zoom, char *diagnostic, size_t diagnostic_capacity
) {
    if (domain == NULL || domain->callback_active || domain->pending_layer_snapshot == NULL ||
        eye == NULL || center == NULL || up == NULL || !isfinite(zoom))
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (size_t i = 0; i < 3; ++i)
        if (!isfinite(eye[i]) || !isfinite(center[i]) || !isfinite(up[i])) {
            mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "non-finite camera snapshot");
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    MWXSceneQuickJSCameraCommand value = {.mask = 15, .zoom = zoom};
    memcpy(value.eye, eye, sizeof(value.eye));
    memcpy(value.center, center, sizeof(value.center));
    memcpy(value.up, up, sizeof(value.up));
    domain->pending_camera_transforms = value;
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
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL || origin == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid staged layer origin"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (size_t index = 0; index < 3; ++index) {
        if (!isfinite(origin[index])) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "non-finite staged layer origin"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    memcpy(
        domain->pending_layer_snapshot[layer_index].current_origin,
        origin,
        sizeof(domain->pending_layer_snapshot[layer_index].current_origin)
    );
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_text_clone_value(
    MWXSceneQuickJSDomain *domain, int64_t layer_id, const char *text, size_t length,
    char *diagnostic, size_t capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, capacity, "");
    if (!domain || domain->callback_active || !domain->pending_layer_snapshot || !text ||
        length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT || memchr(text, 0, length)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    uint32_t index = domain->authored_layer_count;
    for (; index < domain->layer_count; ++index)
        if (domain->layers[index].layer_id == layer_id && domain->layers[index].configured &&
            domain->layers[index].dynamic && !domain->layers[index].destroyed &&
            domain->layers[index].text_template_identity) break;
    if (index == domain->layer_count) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSTextCloneSnapshot *entry = domain->pending_text_clone_snapshot;
    for (; entry; entry = entry->next) if (entry->layer_index == index) break;
    if (!entry && domain->pending_text_clone_count >= MWX_SCENE_QUICKJS_MAX_SCENE_DYNAMIC_LAYERS)
        return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
    char *copy = copy_snapshot_string(text, length);
    if (!copy) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    if (!entry) {
        entry = calloc(1, sizeof(*entry));
        if (!entry) { free(copy); return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; }
        entry->layer_index = index; entry->layer_id = layer_id;
        entry->next = domain->pending_text_clone_snapshot;
        domain->pending_text_clone_snapshot = entry; ++domain->pending_text_clone_count;
    }
    free(entry->text); entry->text = copy;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_commit_layer_snapshot(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL ||
        domain->pending_layer_snapshot_generation == 0 ||
        domain->pending_layer_snapshot_generation <=
            domain->layer_snapshot_generation) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid layer snapshot commit"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    for (MWXSceneQuickJSTextCloneSnapshot *entry = domain->pending_text_clone_snapshot; entry; entry = entry->next)
        if (entry->layer_index >= domain->layer_count || !domain->layers[entry->layer_index].configured ||
            domain->layers[entry->layer_index].destroyed || domain->layers[entry->layer_index].layer_id != entry->layer_id ||
            !domain->layers[entry->layer_index].text_template_identity) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    bool order_changed = false;
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        if (!domain->layers[index].configured ||
            !domain->pending_layer_snapshot[index].runtime_fields_staged) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "layer snapshot staging is incomplete"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
        order_changed = order_changed || (domain->layers[index].destroyed !=
            domain->pending_layer_snapshot[index].destroyed);
    }
    // Snapshot publication owns authored retirement. Save dynamic ranks too,
    // since removing an authored slot changes every surviving catalog ordinal.
    if (order_changed && domain->layer_count > 0) {
        int32_t *saved_order = malloc(domain->layer_count * sizeof(*saved_order));
        if (saved_order == NULL) {
            mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity,
                "layer snapshot order staging allocation failed");
            return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        }
        for (uint32_t i = 0; i < domain->layer_count; ++i)
            saved_order[i] = domain->layers[i].order_index;
        domain->rollback_layer_order = saved_order;
        domain->rollback_layer_order_count = domain->layer_count;
    }
    const uint64_t generation = domain->pending_layer_snapshot_generation;
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        MWXSceneQuickJSStagedLayerSnapshot *staged =
            &domain->pending_layer_snapshot[index];
        uint8_t *previous_effect_visible = record->effect_visible;
        record->effect_visible = staged->effect_visible;
        staged->effect_visible = previous_effect_visible;
        double previous_current_origin[3];
        double previous_world_transform[16];
        double previous_scale[3];
        double previous_angles[3];
        double previous_color[3];
        memcpy(previous_current_origin, record->current_origin,
               sizeof(previous_current_origin));
        memcpy(previous_world_transform, record->world_transform,
               sizeof(previous_world_transform));
        const bool previous_world_transform_available =
            record->world_transform_available;
        memcpy(previous_scale, record->scale, sizeof(previous_scale));
        memcpy(previous_angles, record->angles, sizeof(previous_angles));
        memcpy(previous_color, record->color, sizeof(previous_color));
        const bool previous_visible = record->visible;
        const bool previous_solid = record->solid;
        const uint32_t previous_perspective = record->perspective;
        const bool previous_destroyed = record->destroyed;
        const double previous_alpha = record->alpha;
        const bool previous_particle_instance_available = record->particle_instance_available;
        const double previous_particle_alpha = record->particle_alpha;
        const double previous_point_size = record->point_size;
        const uint32_t previous_video_source_index = record->video_source_index;
        const bool previous_sound_available = record->sound_available;
        const bool previous_sound_is_playing = record->sound_is_playing;
        const MWXSceneQuickJSParticlePlaybackState previous_particle_playback = record->particle_playback;
        const bool previous_texture_animation_available =
            record->texture_animation_available;
        const uint32_t previous_texture_animation_frame_count =
            record->texture_animation_frame_count;
        const double previous_texture_animation_duration =
            record->texture_animation_duration;
        const double previous_texture_animation_rate =
            record->texture_animation_rate;
        const double previous_texture_animation_current_frame =
            record->texture_animation_current_frame;
        const bool previous_texture_animation_is_playing =
            record->texture_animation_is_playing;
        const double previous_texture_animation_shared_rate =
            record->texture_animation_shared_rate;
        const double previous_texture_animation_shared_current_frame =
            record->texture_animation_shared_current_frame;
        const bool previous_texture_animation_shared_is_playing =
            record->texture_animation_shared_is_playing;
        if (staged->text != NULL) {
            char *candidate = staged->text;
            staged->text = record->text;
            staged->text_replaced = true;
            record->text = candidate;
        }
        // Image font is target-layer JS state; native snapshots own text fonts.
        if (staged->font != NULL && !record->image_font_script_state) {
            char *candidate = staged->font;
            staged->font = record->font;
            staged->font_replaced = true;
            record->font = candidate;
        }
        memcpy(record->current_origin, staged->current_origin,
               sizeof(record->current_origin));
        memcpy(record->world_transform, staged->world_transform,
               sizeof(record->world_transform));
        record->world_transform_available =
            staged->world_transform_available;
        memcpy(record->scale, staged->scale, sizeof(record->scale));
        memcpy(record->angles, staged->angles, sizeof(record->angles));
        memcpy(record->color, staged->color, sizeof(record->color));
        record->visible = staged->visible;
        record->solid = staged->solid;
        record->perspective = staged->perspective;
        record->destroyed = staged->destroyed;
        record->alpha = staged->alpha;
        record->particle_instance_available = staged->particle_instance_available;
        record->particle_alpha = staged->particle_alpha;
        record->point_size = staged->point_size;
        record->video_source_index = staged->video_source_index;
        record->sound_available = staged->sound_available;
        record->sound_is_playing = staged->sound_is_playing;
        record->particle_playback = staged->particle_playback;
        record->texture_animation_available =
            staged->texture_animation_available;
        record->texture_animation_frame_count =
            staged->texture_animation_frame_count;
        record->texture_animation_duration =
            staged->texture_animation_duration;
        record->texture_animation_rate = staged->texture_animation_rate;
        record->texture_animation_current_frame =
            staged->texture_animation_current_frame;
        record->texture_animation_is_playing =
            staged->texture_animation_is_playing;
        record->texture_animation_shared_rate =
            staged->texture_animation_shared_rate;
        record->texture_animation_shared_current_frame =
            staged->texture_animation_shared_current_frame;
        record->texture_animation_shared_is_playing =
            staged->texture_animation_shared_is_playing;
        memcpy(staged->current_origin, previous_current_origin,
               sizeof(staged->current_origin));
        memcpy(staged->world_transform, previous_world_transform,
               sizeof(staged->world_transform));
        staged->world_transform_available =
            previous_world_transform_available;
        memcpy(staged->scale, previous_scale, sizeof(staged->scale));
        memcpy(staged->angles, previous_angles, sizeof(staged->angles));
        memcpy(staged->color, previous_color, sizeof(staged->color));
        staged->visible = previous_visible;
        staged->solid = previous_solid;
        staged->perspective = previous_perspective;
        staged->destroyed = previous_destroyed;
        staged->alpha = previous_alpha;
        staged->particle_instance_available = previous_particle_instance_available;
        staged->particle_alpha = previous_particle_alpha;
        staged->point_size = previous_point_size;
        staged->video_source_index = previous_video_source_index;
        staged->sound_available = previous_sound_available;
        staged->sound_is_playing = previous_sound_is_playing;
        staged->particle_playback = previous_particle_playback;
        staged->texture_animation_available =
            previous_texture_animation_available;
        staged->texture_animation_frame_count =
            previous_texture_animation_frame_count;
        staged->texture_animation_duration =
            previous_texture_animation_duration;
        staged->texture_animation_rate = previous_texture_animation_rate;
        staged->texture_animation_current_frame =
            previous_texture_animation_current_frame;
        staged->texture_animation_is_playing =
            previous_texture_animation_is_playing;
        staged->texture_animation_shared_rate =
            previous_texture_animation_shared_rate;
        staged->texture_animation_shared_current_frame =
            previous_texture_animation_shared_current_frame;
        staged->texture_animation_shared_is_playing =
            previous_texture_animation_shared_is_playing;
    }
    for (MWXSceneQuickJSTextCloneSnapshot *entry = domain->pending_text_clone_snapshot; entry; entry = entry->next) {
        char *old = domain->layers[entry->layer_index].text;
        domain->layers[entry->layer_index].text = entry->text; entry->text = old;
    }
    domain->rollback_text_clone_snapshot = domain->pending_text_clone_snapshot;
    domain->pending_text_clone_snapshot = NULL; domain->pending_text_clone_count = 0;
    if (order_changed) mwx_scene_quickjs_compact_layer_order(domain);
    if (domain->pending_video_observations_staged) {
        domain->rollback_video_observations = domain->video_observations;
        domain->rollback_video_observation_count = domain->video_observation_count;
        domain->rollback_video_observations_replaced = true;
        domain->video_observations = domain->pending_video_observations;
        domain->video_observation_count = domain->pending_video_observation_count;
        domain->pending_video_observations = NULL;
        domain->pending_video_observation_count = 0;
        domain->pending_video_observations_staged = false;
    }
    domain->rollback_layer_snapshot = domain->pending_layer_snapshot;
    domain->rollback_layer_snapshot_generation = domain->layer_snapshot_generation;
    domain->rollback_defaults_to_perspective = domain->defaults_to_perspective;
    domain->rollback_camera_transforms = domain->camera_transforms;
    domain->camera_transforms = domain->pending_camera_transforms;
    domain->defaults_to_perspective = domain->pending_defaults_to_perspective;
    domain->pending_layer_snapshot = NULL;
    domain->pending_layer_snapshot_generation = 0;
    domain->layer_snapshot_generation = generation;
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_domain_abort_layer_snapshot(
    MWXSceneQuickJSDomain *domain
) {
    clear_pending_snapshot(domain);
    mwx_scene_quickjs_layer_finalize_topology(domain);
}

bool mwx_scene_quickjs_domain_rollback_layer_snapshot(
    MWXSceneQuickJSDomain *domain
) {
    if (domain == NULL || domain->rollback_layer_snapshot == NULL) {
        return false;
    }
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        MWXSceneQuickJSStagedLayerSnapshot *saved =
            &domain->rollback_layer_snapshot[index];
        free(record->effect_visible);
        record->effect_visible = saved->effect_visible;
        saved->effect_visible = NULL;
        if (saved->text_replaced) {
            free(record->text);
            record->text = saved->text;
            saved->text = NULL;
        }
        if (saved->font_replaced) {
            free(record->font);
            record->font = saved->font;
            saved->font = NULL;
        }
        memcpy(record->current_origin, saved->current_origin,
               sizeof(record->current_origin));
        memcpy(record->world_transform, saved->world_transform,
               sizeof(record->world_transform));
        record->world_transform_available =
            saved->world_transform_available;
        memcpy(record->scale, saved->scale, sizeof(record->scale));
        memcpy(record->angles, saved->angles, sizeof(record->angles));
        memcpy(record->color, saved->color, sizeof(record->color));
        record->visible = saved->visible;
        record->solid = saved->solid;
        record->perspective = saved->perspective;
        record->destroyed = saved->destroyed;
        record->alpha = saved->alpha;
        record->particle_instance_available = saved->particle_instance_available;
        record->particle_alpha = saved->particle_alpha;
        record->point_size = saved->point_size;
        record->video_source_index = saved->video_source_index;
        record->sound_available = saved->sound_available;
        record->sound_is_playing = saved->sound_is_playing;
        record->particle_playback = saved->particle_playback;
        record->texture_animation_available =
            saved->texture_animation_available;
        record->texture_animation_frame_count =
            saved->texture_animation_frame_count;
        record->texture_animation_duration = saved->texture_animation_duration;
        record->texture_animation_rate = saved->texture_animation_rate;
        record->texture_animation_current_frame =
            saved->texture_animation_current_frame;
        record->texture_animation_is_playing =
            saved->texture_animation_is_playing;
        record->texture_animation_shared_rate =
            saved->texture_animation_shared_rate;
        record->texture_animation_shared_current_frame =
            saved->texture_animation_shared_current_frame;
        record->texture_animation_shared_is_playing =
            saved->texture_animation_shared_is_playing;
    }
    for (MWXSceneQuickJSTextCloneSnapshot *entry = domain->rollback_text_clone_snapshot; entry; entry = entry->next) {
        if (entry->layer_index >= domain->layer_count || !domain->layers[entry->layer_index].configured ||
            domain->layers[entry->layer_index].layer_id != entry->layer_id) continue;
        free(domain->layers[entry->layer_index].text);
        domain->layers[entry->layer_index].text = entry->text; entry->text = NULL;
    }
    for (uint32_t i = 0; i < domain->rollback_layer_order_count && i < domain->layer_count; ++i)
        domain->layers[i].order_index = domain->rollback_layer_order[i];
    domain->layer_snapshot_generation =
        domain->rollback_layer_snapshot_generation;
    domain->defaults_to_perspective = domain->rollback_defaults_to_perspective;
    domain->camera_transforms = domain->rollback_camera_transforms;
    if (domain->rollback_video_observations_replaced) {
        free(domain->video_observations);
        domain->video_observations = domain->rollback_video_observations;
        domain->video_observation_count = domain->rollback_video_observation_count;
        domain->rollback_video_observations = NULL;
    }
    clear_rollback_snapshot(domain);
    mwx_scene_quickjs_layer_finalize_topology(domain);
    return true;
}

void mwx_scene_quickjs_domain_finalize_layer_snapshot(
    MWXSceneQuickJSDomain *domain
) {
    clear_rollback_snapshot(domain);
    mwx_scene_quickjs_layer_finalize_topology(domain);
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_effects(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index,
    uint32_t count, const uint8_t *visible
) {
    if (domain == NULL || domain->callback_active || domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count ||
        count != domain->layers[layer_index].effect_count || (count > 0 && visible == NULL))
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    for (uint32_t i = 0; i < count; ++i)
        if (visible[i] > 1) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (count > 0) memcpy(domain->pending_layer_snapshot[layer_index].effect_visible, visible, count);
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_particle_playback(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index,
    MWXSceneQuickJSParticlePlaybackState state, char *diagnostic, size_t diagnostic_capacity
) {
    if (domain == NULL || domain->callback_active || domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count || !domain->layers[layer_index].configured ||
        state.available > 1 || state.live > 1 || state.emission_pending > 1 || state.rearm_has_work > 1 || state.intent > 2) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid particle playback observation");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    domain->pending_layer_snapshot[layer_index].particle_playback = state;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_particle_instance_alpha(
    MWXSceneQuickJSDomain *domain, uint32_t layer_index, uint32_t available,
    double alpha, char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count || !domain->layers[layer_index].configured ||
        available > 1 || !isfinite(alpha)) {
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "invalid particle instance projection");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    MWXSceneQuickJSStagedLayerSnapshot *staged = &domain->pending_layer_snapshot[layer_index];
    staged->particle_instance_available = available != 0;
    staged->particle_alpha = alpha;
    return MWX_SCENE_QUICKJS_OK;
}
