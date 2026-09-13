#include "SceneQuickJSInternal.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

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
    }
    free(*snapshot);
    *snapshot = NULL;
}

static void clear_pending_snapshot(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) return;
    clear_snapshot(
        &domain->pending_layer_snapshot,
        domain->authored_layer_count
    );
    domain->pending_layer_snapshot_generation = 0;
}

static void clear_rollback_snapshot(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) return;
    clear_snapshot(
        &domain->rollback_layer_snapshot,
        domain->authored_layer_count
    );
    domain->rollback_layer_snapshot_generation = 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_begin_layer_snapshot(
    MWXSceneQuickJSDomain *domain,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers == NULL || domain->callback_active ||
        domain->pending_layer_snapshot != NULL ||
        domain->rollback_layer_snapshot != NULL || generation == 0 ||
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
        pending[index].visible = record->visible;
        pending[index].destroyed = record->destroyed;
        pending[index].alpha = record->alpha;
        pending[index].point_size = record->point_size;
        pending[index].video_available = record->video_available;
        pending[index].video_duration = record->video_duration;
        pending[index].video_rate = record->video_rate;
        pending[index].video_loop = record->video_loop;
        pending[index].video_current_time = record->video_current_time;
        pending[index].video_is_playing = record->video_is_playing;
        pending[index].video_ended_generation = record->video_ended_generation;
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
        !domain->layers[layer_index].configured || destroyed > 1 || scale == NULL ||
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
    staged->destroyed = destroyed != 0;
    staged->alpha = alpha;
    staged->point_size = point_size;
    staged->video_available = false;
    staged->video_duration = 0;
    staged->video_rate = 1;
    staged->video_loop = true;
    staged->video_current_time = 0;
    staged->video_is_playing = false;
    staged->video_ended_generation = 0;
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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_video_fields(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    uint32_t available,
    double duration,
    double rate,
    uint32_t loop,
    double current_time,
    uint32_t is_playing,
    uint64_t ended_generation,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        domain->pending_layer_snapshot == NULL ||
        layer_index >= domain->authored_layer_count ||
        !domain->layers[layer_index].configured || available > 1 || loop > 1 ||
        is_playing > 1 || !isfinite(duration) || duration < 0 ||
        !isfinite(rate) || rate <= 0 || rate > 16 ||
        !isfinite(current_time) || current_time < 0 ||
        (duration > 0 && current_time > duration)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid staged layer video fields"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    MWXSceneQuickJSStagedLayerSnapshot *staged =
        &domain->pending_layer_snapshot[layer_index];
    staged->video_available = available != 0;
    staged->video_duration = duration;
    staged->video_rate = rate;
    staged->video_loop = loop != 0;
    staged->video_current_time = current_time;
    staged->video_is_playing = is_playing != 0;
    staged->video_ended_generation = ended_generation;
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
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        if (!domain->layers[index].configured ||
            !domain->pending_layer_snapshot[index].runtime_fields_staged) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "layer snapshot staging is incomplete"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    const uint64_t generation = domain->pending_layer_snapshot_generation;
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        MWXSceneQuickJSStagedLayerSnapshot *staged =
            &domain->pending_layer_snapshot[index];
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
        const bool previous_destroyed = record->destroyed;
        const double previous_alpha = record->alpha;
        const double previous_point_size = record->point_size;
        const bool previous_video_available = record->video_available;
        const double previous_video_duration = record->video_duration;
        const double previous_video_rate = record->video_rate;
        const bool previous_video_loop = record->video_loop;
        const double previous_video_current_time = record->video_current_time;
        const bool previous_video_is_playing = record->video_is_playing;
        const uint64_t previous_video_ended_generation =
            record->video_ended_generation;
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
        if (staged->font != NULL) {
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
        record->destroyed = staged->destroyed;
        record->alpha = staged->alpha;
        record->point_size = staged->point_size;
        record->video_available = staged->video_available;
        record->video_duration = staged->video_duration;
        record->video_rate = staged->video_rate;
        record->video_loop = staged->video_loop;
        record->video_current_time = staged->video_current_time;
        record->video_is_playing = staged->video_is_playing;
        record->video_ended_generation = staged->video_ended_generation;
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
        staged->destroyed = previous_destroyed;
        staged->alpha = previous_alpha;
        staged->point_size = previous_point_size;
        staged->video_available = previous_video_available;
        staged->video_duration = previous_video_duration;
        staged->video_rate = previous_video_rate;
        staged->video_loop = previous_video_loop;
        staged->video_current_time = previous_video_current_time;
        staged->video_is_playing = previous_video_is_playing;
        staged->video_ended_generation = previous_video_ended_generation;
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
    domain->rollback_layer_snapshot = domain->pending_layer_snapshot;
    domain->rollback_layer_snapshot_generation = domain->layer_snapshot_generation;
    domain->pending_layer_snapshot = NULL;
    domain->pending_layer_snapshot_generation = 0;
    domain->layer_snapshot_generation = generation;
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_domain_abort_layer_snapshot(
    MWXSceneQuickJSDomain *domain
) {
    clear_pending_snapshot(domain);
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
        record->destroyed = saved->destroyed;
        record->alpha = saved->alpha;
        record->point_size = saved->point_size;
        record->video_available = saved->video_available;
        record->video_duration = saved->video_duration;
        record->video_rate = saved->video_rate;
        record->video_loop = saved->video_loop;
        record->video_current_time = saved->video_current_time;
        record->video_is_playing = saved->video_is_playing;
        record->video_ended_generation = saved->video_ended_generation;
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
    domain->layer_snapshot_generation =
        domain->rollback_layer_snapshot_generation;
    clear_rollback_snapshot(domain);
    return true;
}

void mwx_scene_quickjs_domain_finalize_layer_snapshot(
    MWXSceneQuickJSDomain *domain
) {
    clear_rollback_snapshot(domain);
}
