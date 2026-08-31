#include "SceneQuickJSInternal.h"

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

static void clear_pending_snapshot(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL || domain->pending_layer_snapshot == NULL) return;
    for (uint32_t index = 0; index < domain->authored_layer_count; ++index) {
        free(domain->pending_layer_snapshot[index].text);
        free(domain->pending_layer_snapshot[index].font);
    }
    free(domain->pending_layer_snapshot);
    domain->pending_layer_snapshot = NULL;
    domain->pending_layer_snapshot_generation = 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_begin_layer_snapshot(
    MWXSceneQuickJSDomain *domain,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->layers == NULL || domain->callback_active ||
        domain->pending_layer_snapshot != NULL || generation == 0 ||
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
        memcpy(
            pending[index].current_origin,
            domain->layers[index].authored_origin,
            sizeof(pending[index].current_origin)
        );
    }
    domain->pending_layer_snapshot = pending;
    domain->pending_layer_snapshot_generation = generation;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_runtime_fields(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    const double scale[3],
    const double angles[3],
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
        !domain->layers[layer_index].configured || scale == NULL ||
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
    staged->alpha = alpha;
    staged->point_size = point_size;
    staged->video_available = false;
    staged->video_duration = 0;
    staged->video_rate = 1;
    staged->video_loop = true;
    staged->video_current_time = 0;
    staged->video_is_playing = false;
    staged->video_ended_generation = 0;
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
        free(record->text);
        free(record->font);
        record->text = staged->text;
        record->font = staged->font;
        staged->text = NULL;
        staged->font = NULL;
        memcpy(record->current_origin, staged->current_origin,
               sizeof(record->current_origin));
        memcpy(record->scale, staged->scale, sizeof(record->scale));
        memcpy(record->angles, staged->angles, sizeof(record->angles));
        memcpy(record->color, staged->color, sizeof(record->color));
        record->visible = staged->visible;
        record->alpha = staged->alpha;
        record->point_size = staged->point_size;
        record->video_available = staged->video_available;
        record->video_duration = staged->video_duration;
        record->video_rate = staged->video_rate;
        record->video_loop = staged->video_loop;
        record->video_current_time = staged->video_current_time;
        record->video_is_playing = staged->video_is_playing;
        record->video_ended_generation = staged->video_ended_generation;
    }
    domain->layer_snapshot_generation = generation;
    clear_pending_snapshot(domain);
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_domain_abort_layer_snapshot(
    MWXSceneQuickJSDomain *domain
) {
    clear_pending_snapshot(domain);
}
